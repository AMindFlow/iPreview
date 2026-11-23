using System.Diagnostics;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage;

namespace IPreview;

public sealed partial class MainWindow
{
    private LibVlcVideoPlayback? fallbackVideo;
    private WriteableBitmap? fallbackBitmap;
    private string? fallbackSystemError;
    private (Media Media, int Generation)? awaitingNativeVideo;
    private CancellationTokenSource? nativeFrameVerification;
    private bool nativePausedByUser;
    private (Media Media, int Generation, string Title, string SystemError)? deferredNativeVideoRecovery;

    private async Task VerifyNativeVideo(string path, Media media, MediaPlayer owner, int generation)
    {
        var verification = new CancellationTokenSource();
        nativeFrameVerification = verification;
        try
        {
            var endedWithoutFrames = await Task.Run(() => NativeVideoEndedWithoutFrames(path, verification.Token));
            if (endedWithoutFrames && CanUpdatePreview(generation) && ReferenceEquals(player, owner) &&
                ReferenceEquals(nativeFrameVerification, verification))
            {
                await RecoverSystemVideo(media, generation, "系统无法播放此视频。",
                    "系统播放器播放结束，未能解码任何视频画面。");
            }
        }
        finally
        {
            if (ReferenceEquals(nativeFrameVerification, verification))
                nativeFrameVerification = null;
            verification.Dispose();
        }
    }

    private static async Task<bool> NativeVideoEndedWithoutFrames(string path, CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested)
            return false;

        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            if (cancellationToken.IsCancellationRequested)
                return false;

            using var source = MediaSource.CreateFromStorageFile(file);
            using var verifier = new MediaPlayer();
            verifier.CommandManager.IsEnabled = false;
            verifier.IsMuted = true;
            // Frame-server mode disables automatic rendering, so it belongs only on the companion player.
            verifier.IsVideoFrameServerEnabled = true;
            var endedWithoutFrames = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            verifier.VideoFrameAvailable += (_, _) => endedWithoutFrames.TrySetResult(false);
            verifier.MediaFailed += (_, _) => endedWithoutFrames.TrySetResult(false);
            verifier.MediaEnded += (_, _) => endedWithoutFrames.TrySetResult(true);
            using var canceled = cancellationToken.Register(() => endedWithoutFrames.TrySetResult(false));
            if (cancellationToken.IsCancellationRequested)
                return false;

            verifier.Source = source;
            verifier.Play();
            return await endedWithoutFrames.Task;
        }
        catch (Exception error) when (MediaFailure(error) || error is NotSupportedException)
        {
            Debug.WriteLine($"Windows video frame verification unavailable: {error.Message}");
            return false;
        }
    }

    private void StopNativeVideoVerification()
    {
        var verification = nativeFrameVerification;
        nativeFrameVerification = null;
        verification?.Cancel();
    }

    private bool RecoverIfNativeVideoMissing(MediaPlaybackSession session, bool playbackConfirmed)
    {
        if (awaitingNativeVideo is not { } current)
            return false;

        if (session.NaturalVideoWidth != 0 || session.NaturalVideoHeight != 0)
        {
            awaitingNativeVideo = null;
            return false;
        }

        if (!playbackConfirmed || !CanUpdatePreview(current.Generation))
            return false;

        _ = RecoverSystemVideo(current.Media, current.Generation, "系统无法播放此视频。",
            "系统播放器已开始播放，但没有可用的视频画面。");
        return true;
    }

    private async Task OpenPreviewVideo(Media media, int generation)
    {
        try
        {
            var file = await OpenMediaFile(media);
            if (CanUpdatePreview(generation))
                StartVideo(file, media, generation);
        }
        catch (Exception error) when (MediaFailure(error))
        {
            if (CanUpdatePreview(generation))
                await RecoverSystemVideo(media, generation, "无法打开此视频。", error.Message);
        }
    }

    private async Task RecoverSystemVideo(Media media, int generation, string title, string systemError)
    {
        if (!LibVlcVideoPlayback.Supports(media.RelativePath))
        {
            ShowPreviewError(title, systemError);
            return;
        }
        if (nativePausedByUser)
        {
            deferredNativeVideoRecovery = (media, generation, title, systemError);
            awaitingNativeVideo = null;
            StopNativeVideoVerification();
            return;
        }

        StopVideo();
        MainImage.Visibility = Visibility.Visible;
        VideoSurface.Visibility = Visibility.Collapsed;
        PlayPause.IsEnabled = false;
        SetPreviewSeekEnabled(false);
        try
        {
            var fallback = await Task.Run(() => new LibVlcVideoPlayback(MediaFiles.OpenPath(media)));
            if (!CanUpdatePreview(generation))
            {
                await Task.Run(fallback.Dispose);
                return;
            }

            fallbackVideo = fallback;
            fallbackSystemError = systemError;
            var dispatcher = DispatcherQueue;
            int queued = 0;
            fallback.FrameReady = () =>
            {
                if (Interlocked.Exchange(ref queued, 1) == 0 &&
                    !dispatcher.TryEnqueue(() =>
                    {
                        Interlocked.Exchange(ref queued, 0);
                        if (CanUpdatePreview(generation) && ReferenceEquals(fallback, fallbackVideo))
                            PresentFallbackFrame(fallback);
                    }))
                {
                    Interlocked.Exchange(ref queued, 0);
                }
            };
            fallback.Play();
            playbackClock.Start();
        }
        catch (Exception error) when (MediaFailure(error) ||
            error is DllNotFoundException or EntryPointNotFoundException or BadImageFormatException)
        {
            if (CanUpdatePreview(generation))
                ShowFallbackError(systemError, error.Message);
        }
    }

    private void PresentFallbackFrame(LibVlcVideoPlayback fallback)
    {
        fallback.ReadFrame((width, height, pixels) =>
        {
            if (fallbackBitmap is not { } bitmap || bitmap.PixelWidth != width || bitmap.PixelHeight != height)
                fallbackBitmap = bitmap = new WriteableBitmap(width, height);

            using var target = bitmap.PixelBuffer.AsStream();
            target.Write(pixels, 0, pixels.Length);
        });
        if (fallbackBitmap is { } shown)
        {
            shown.Invalidate();
            if (!ReferenceEquals(MainImage.Source, shown))
                MainImage.Source = shown;
        }
    }

    private void UpdateFallbackTime(LibVlcVideoPlayback fallback)
    {
        var state = fallback.State;
        if (state == LibVlcNative.State.Error ||
            ((state is LibVlcNative.State.Ended or LibVlcNative.State.Stopped) && fallbackBitmap is null))
        {
            ShowFallbackError(fallbackSystemError, "LibVLC 无法解码此视频。");
            return;
        }

        var duration = fallback.Duration;
        PlayPause.IsEnabled = fallbackBitmap is not null;
        UpdateVideoTime(state == LibVlcNative.State.Ended ? duration : fallback.Position,
            duration, fallback.CanSeek, state == LibVlcNative.State.Playing);
    }

    private void ShowFallbackError(string? systemError, string detail)
    {
        var message = string.IsNullOrWhiteSpace(systemError)
            ? detail : $"{detail}\n系统播放器：{systemError}";
        ShowPreviewError("无法播放此视频。", message);
    }

    private void StopFallbackVideo()
    {
        var fallback = fallbackVideo;
        fallbackVideo = null;
        fallbackBitmap = null;
        fallbackSystemError = null;
        fallback?.Dispose();
    }

    private void ToggleFallbackVideo(LibVlcVideoPlayback fallback)
    {
        try
        {
            if (fallback.State == LibVlcNative.State.Playing)
                fallback.Pause();
            else
                fallback.Play();
            UpdateFallbackTime(fallback);
        }
        catch (IOException error)
        {
            ShowFallbackError(fallbackSystemError, error.Message);
        }
    }
}
