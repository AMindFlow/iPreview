using System.Reflection;
using System.Runtime.InteropServices;

namespace IPreview;

internal static class LibVlcNative
{
    private const string Library = "iPreview.LibVLC";

    static LibVlcNative()
    {
        // LibVLC otherwise searches directories supplied by the parent process.
        Environment.SetEnvironmentVariable("VLC_PLUGIN_PATH", null);
        NativeLibrary.SetDllImportResolver(typeof(LibVlcNative).Assembly, Resolve);
    }

    private static nint Resolve(string name, Assembly assembly, DllImportSearchPath? _)
    {
        if (name != Library)
            return 0;

        var directory = Path.Combine(AppContext.BaseDirectory, "LibVLC");
        return NativeLibrary.Load(Path.Combine(directory, "libvlc.dll"), assembly,
            DllImportSearchPath.UseDllDirectoryForDependencies | DllImportSearchPath.System32);
    }

    internal enum State { NothingSpecial, Opening, Buffering, Playing, Paused, Stopped, Ended, Error }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate uint SetupVideo(ref nint opaque, nint chroma, ref uint width, ref uint height,
        nint pitches, nint lines);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate void CleanupVideo(nint opaque);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate nint LockVideo(nint opaque, nint planes);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate void DisplayVideo(nint opaque, nint picture);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_new")]
    internal static extern nint New(int argc, nint[] argv);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_release")]
    internal static extern void Release(nint instance);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_new_path")]
    internal static extern nint NewPath(nint instance, [MarshalAs(UnmanagedType.LPUTF8Str)] string path);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_add_option")]
    internal static extern void AddOption(nint media, [MarshalAs(UnmanagedType.LPUTF8Str)] string option);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_release")]
    internal static extern void ReleaseMedia(nint media);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_new_from_media")]
    internal static extern nint NewPlayer(nint media);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_release")]
    internal static extern void ReleasePlayer(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_play")]
    internal static extern int Play(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_stop")]
    internal static extern void Stop(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_set_pause")]
    internal static extern void SetPause(nint player, int pause);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_get_state")]
    internal static extern State GetState(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_get_length")]
    internal static extern long GetLength(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_get_time")]
    internal static extern long GetTime(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_set_time")]
    internal static extern void SetTime(nint player, long milliseconds);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_media_player_is_seekable")]
    internal static extern int IsSeekable(nint player);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_video_set_callbacks")]
    internal static extern void SetVideoCallbacks(nint player, LockVideo videoLock, nint unlock,
        DisplayVideo display, nint opaque);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_video_set_format_callbacks")]
    internal static extern void SetVideoFormat(nint player, SetupVideo setup, CleanupVideo cleanup);

    [DllImport(Library, CallingConvention = CallingConvention.Cdecl, EntryPoint = "libvlc_errmsg")]
    private static extern nint ErrorMessage();

    internal static IOException Failure(string message)
    {
        var error = Marshal.PtrToStringUTF8(ErrorMessage());
        return new IOException(string.IsNullOrWhiteSpace(error) ? message : $"{message}\n{error}");
    }
}
