using System.Runtime.InteropServices;

namespace IPreview;

internal sealed class LibVlcVideoPlayback : IDisposable
{
    private sealed unsafe class NativeFrame(uint width, uint height) : IDisposable
    {
        public readonly int Width = (int)width;
        public readonly int Height = (int)height;
        public readonly int Pitch = ((int)width * 4 + 31) & ~31;
        public readonly int Lines = ((int)height + 31) & ~31;
        public nint Data { get; private set; }

        public bool Allocate()
        {
            Data = (nint)NativeMemory.AlignedAlloc((nuint)(Pitch * Lines), 32);
            return Data != 0;
        }

        public void Dispose() => NativeMemory.AlignedFree((void*)Data);
    }

    private readonly LibVlcNative.LockVideo lockVideo = Lock;
    private readonly LibVlcNative.SetupVideo setupVideo = Setup;
    private readonly LibVlcNative.CleanupVideo cleanupVideo = Cleanup;
    private readonly LibVlcNative.DisplayVideo displayVideo;
    private nint instance;
    private nint player;
    private readonly object frameGate = new();
    private byte[] pixels = [];
    private int frameWidth;
    private int frameHeight;
    private bool closed;

    internal Action? FrameReady { get; set; }

    internal LibVlcVideoPlayback(string path)
    {
        displayVideo = Display;
        var demux = Path.GetExtension(path).ToLowerInvariant() switch
        {
            ".mp4" or ".mov" => "mp4",
            ".ts" => "ts",
            ".mkv" or ".webm" => "mkv",
            ".avi" => "avi",
            _ => throw new IOException("LibVLC 不支持此预览文件的后缀。")
        };

        string[] arguments = [
            "--ignore-config", "--no-plugins-cache", "--no-metadata-network-access",
            "--no-sub-autodetect-file", "--no-video-title-show", "--avcodec-hw=none"
        ];
        var nativeArguments = new nint[arguments.Length];
        try
        {
            for (var index = 0; index < arguments.Length; index++)
                nativeArguments[index] = Marshal.StringToCoTaskMemUTF8(arguments[index]);
            instance = LibVlcNative.New(arguments.Length, nativeArguments);
        }
        finally
        {
            foreach (var argument in nativeArguments)
                Marshal.FreeCoTaskMem(argument);
        }

        if (instance == 0)
            throw LibVlcNative.Failure("无法初始化随附的 LibVLC。");
        try
        {
            var media = LibVlcNative.NewPath(instance, path);
            if (media == 0)
                throw LibVlcNative.Failure("LibVLC 无法打开视频文件。");
            try
            {
                LibVlcNative.AddOption(media, $":demux={demux}");
                player = LibVlcNative.NewPlayer(media);
            }
            finally
            {
                LibVlcNative.ReleaseMedia(media);
            }

            if (player == 0)
                throw LibVlcNative.Failure("LibVLC 无法创建播放器。");
            LibVlcNative.SetVideoCallbacks(player, lockVideo, 0, displayVideo, 0);
            LibVlcNative.SetVideoFormat(player, setupVideo, cleanupVideo);
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    private static uint Setup(ref nint opaque, nint chroma, ref uint width, ref uint height, nint pitches, nint lines)
    {
        // WinUI consumes little-endian BGRA. The RV32 padding byte is made opaque on copy.
        const double maximumEdge = 1920;
        if (width == 0 || height == 0)
            return 0;
        var scale = Math.Min(1, maximumEdge / Math.Max(width, height));
        var requestedWidth = Math.Max(1, (uint)(width * scale));
        var requestedHeight = Math.Max(1, (uint)(height * scale));
        var frame = new NativeFrame(requestedWidth, requestedHeight);
        try
        {
            if (!frame.Allocate())
                return 0;
            opaque = GCHandle.ToIntPtr(GCHandle.Alloc(frame));
        }
        catch (OutOfMemoryException)
        {
            frame.Dispose();
            return 0;
        }
        Marshal.WriteInt32(chroma, 0x32335652); // ASCII RV32
        Marshal.WriteInt32(pitches, frame.Pitch);
        Marshal.WriteInt32(lines, frame.Lines);
        width = requestedWidth;
        height = requestedHeight;
        return 1;
    }

    private static void Cleanup(nint opaque)
    {
        var handle = GCHandle.FromIntPtr(opaque);
        ((NativeFrame)handle.Target!).Dispose();
        handle.Free();
    }

    private static nint Lock(nint opaque, nint planes)
    {
        var frame = (NativeFrame)GCHandle.FromIntPtr(opaque).Target!;
        Marshal.WriteIntPtr(planes, frame.Data);
        return opaque;
    }

    private void Display(nint opaque, nint picture)
    {
        var frame = (NativeFrame)GCHandle.FromIntPtr(opaque).Target!;
        lock (frameGate)
        {
            if (closed)
                return;

            var rowBytes = frame.Width * 4;
            if (pixels.Length != rowBytes * frame.Height)
                pixels = new byte[rowBytes * frame.Height];
            frameWidth = frame.Width;
            frameHeight = frame.Height;
            for (var row = 0; row < frame.Height; row++)
                Marshal.Copy(frame.Data + row * frame.Pitch, pixels, row * rowBytes, rowBytes);

            var colors = MemoryMarshal.Cast<byte, uint>(pixels.AsSpan());
            for (var index = 0; index < colors.Length; index++)
                colors[index] |= 0xFF000000;
        }

        FrameReady?.Invoke();
    }

    internal void ReadFrame(Action<int, int, byte[]> read)
    {
        lock (frameGate)
        {
            if (!closed && pixels.Length != 0)
                read(frameWidth, frameHeight, pixels);
        }
    }

    internal LibVlcNative.State State => LibVlcNative.GetState(player);
    internal TimeSpan Duration => PlaybackTime(LibVlcNative.GetLength(player));
    internal TimeSpan Position => PlaybackTime(LibVlcNative.GetTime(player));
    internal bool CanSeek => LibVlcNative.IsSeekable(player) != 0;

    private static TimeSpan PlaybackTime(long milliseconds) =>
        TimeSpan.FromTicks(Math.Clamp(milliseconds, 0, TimeSpan.MaxValue.Ticks / TimeSpan.TicksPerMillisecond) *
            TimeSpan.TicksPerMillisecond);

    internal void Play()
    {
        if (LibVlcNative.Play(player) != 0)
            throw LibVlcNative.Failure("LibVLC 无法开始播放。");
    }

    internal void Pause() => LibVlcNative.SetPause(player, 1);
    internal void Seek(TimeSpan position) => LibVlcNative.SetTime(player, (long)position.TotalMilliseconds);

    public void Dispose()
    {
        lock (frameGate)
        {
            if (closed)
                return;
            closed = true;
            FrameReady = null;
            pixels = [];
        }

        // Stop joins the native decoder before callback pointers or frame storage can be released.
        if (player != 0)
        {
            LibVlcNative.Stop(player);
            LibVlcNative.ReleasePlayer(player);
            player = 0;
        }
        LibVlcNative.Release(instance);
        instance = 0;
        GC.KeepAlive(lockVideo);
        GC.KeepAlive(setupVideo);
        GC.KeepAlive(cleanupVideo);
        GC.KeepAlive(displayVideo);
    }
}
