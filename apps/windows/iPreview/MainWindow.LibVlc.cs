using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace IPreview;

public sealed partial class MainWindow
{
    private LibVlcVideoPlayback? fallbackVideo;
    private WriteableBitmap? fallbackBitmap;
    private string? fallbackSystemError;

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
                await StartFallbackVideo(media, generation, error.Message);
        }
    }

    private async Task StartFallbackVideo(Media media, int generation, string systemError)
    {
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
