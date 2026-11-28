using System.Globalization;
using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media.Imaging;

namespace IPreview;

public sealed partial class MainWindow
{
    private enum ImageSlideState { Stopped, Playing, Paused }

    private readonly DispatcherTimer imageSlideClock = new() { Interval = TimeSpan.FromSeconds(2) };
    private ImageSlideState imageSlideState;
    private bool imageSlideReady;
    private bool comicReading;
    private bool comicCoverSingle = true;
    private CancellationTokenSource? comicPageLoad;

    private bool ComicReadingActive => comicReading && previewIndex >= 0 && !previewTiles[previewIndex].Media.IsVideo;
    private PhotoSpread? CurrentComicSpread => ComicReadingActive
        ? PhotoSpread.Around(previewIndex, previewTiles.Count, comicCoverSingle, IsPreviewImage)
        : null;

    private bool IsPreviewImage(int index) => !previewTiles[index].Media.IsVideo;

    private PhotoSpread? PrepareImagePreview(bool image)
    {
        imageSlideReady = false;
        imageSlideClock.Stop();
        comicPageLoad?.Cancel();
        ImagePreviewBar.Visibility = image ? Visibility.Visible : Visibility.Collapsed;
        if (!image)
        {
            SetImageSlideState(ImageSlideState.Stopped);
            ResetComicReading();
        }
        var spread = CurrentComicSpread;
        if (spread is null)
            ClearComicImages();
        PreviewLeftRail.Width = PreviewRightRail.Width = new GridLength(
            BrowsingVideoWork || (spread is null && previewLayout.Mode == BrowseMode.List) ? 0 : 44);
        return spread;
    }

    private void ResetComicReading()
    {
        comicReading = false;
        ComicReadingToggle.IsChecked = false;
        ComicCoverToggle.Visibility = Visibility.Collapsed;
        ClearComicImages();
    }

    private void ClearComicImages()
    {
        ComicPages.Visibility = Visibility.Collapsed;
        ComicLeftImage.Source = ComicRightImage.Source = null;
    }

    private void ToggleComicReading(object sender, RoutedEventArgs args)
    {
        if (previewClosing || previewIndex < 0)
            return;
        comicReading = ComicReadingToggle.IsChecked == true;
        ComicCoverToggle.Visibility = comicReading ? Visibility.Visible : Visibility.Collapsed;
        ShowPreview(previewIndex, ThumbnailOf(previewTiles[previewIndex].Media.Id)?.Image);
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void ToggleComicCover(object sender, RoutedEventArgs args)
    {
        if (previewClosing || !ComicReadingActive)
            return;
        comicCoverSingle = ComicCoverToggle.IsChecked == true;
        ComicCoverToggle.Content = comicCoverSingle ? "首页单页" : "首页双页";
        ShowPreview(previewIndex, poster: null);
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private int? PreviewDestination(BrowseDirection direction) => PreviewDestination(direction, CurrentComicSpread);

    private int? PreviewDestination(BrowseDirection direction, PhotoSpread? spread) => spread is { } comic
        ? direction switch
        {
            BrowseDirection.Left => comic.Previous,
            BrowseDirection.Right => comic.Next,
            _ => null
        }
        : previewLayout.NeighborOf(previewIndex, previewTiles.Count, direction);

    private void UpdateImagePreviewIndex(PhotoSpread? spread)
    {
        var position = spread is { Second: int second } comic
            ? $"{comic.First + 1}–{second + 1}"
            : (previewIndex + 1).ToString(CultureInfo.CurrentCulture);
        IndexLabel.Text = $"{position} / {previewTiles.Count}";
    }

    private async Task LoadComicSpread(PhotoSpread spread, bool? turningForward, int generation)
    {
        using var load = new CancellationTokenSource();
        comicPageLoad = load;
        try
        {
            var left = LoadComicPage(previewTiles[spread.First].Media, load.Token);
            var right = spread.Second is int second
                ? LoadComicPage(previewTiles[second].Media, load.Token)
                : Task.FromResult<BitmapImage?>(null);
            var images = await Task.WhenAll(left, right);
            if (!CanUpdatePreview(generation))
                return;

            var doublePage = spread.Second is not null;
            ComicLeftImage.Source = images[0];
            ComicRightImage.Source = images[1];
            ComicLeftError.Visibility = images[0] is null ? Visibility.Visible : Visibility.Collapsed;
            ComicRightError.Visibility = doublePage && images[1] is null ? Visibility.Visible : Visibility.Collapsed;
            ComicRightPage.Visibility = doublePage ? Visibility.Visible : Visibility.Collapsed;
            Grid.SetColumnSpan(ComicLeftPage, doublePage ? 1 : 2);
            AutomationProperties.SetName(ComicLeftPage, previewTiles[spread.First].FileName);
            AutomationProperties.SetName(ComicRightPage, spread.Second is int position ? previewTiles[position].FileName : "");
            ComicPages.Visibility = Visibility.Visible;
            MainImage.Visibility = Visibility.Collapsed;
            if (turningForward is bool forward)
                AnimateComicTurn(forward, doublePage);
        }
        catch (OperationCanceledException) when (load.IsCancellationRequested) { }
        finally
        {
            if (ReferenceEquals(comicPageLoad, load))
                comicPageLoad = null;
        }
    }

    private static async Task<BitmapImage?> LoadComicPage(Media media, CancellationToken cancellationToken)
    {
        try
        {
            var failed = false;
            var image = await DecodeImage(media, 0, true, (_, _) => failed = true, cancellationToken);
            return failed || image.PixelWidth <= 0 ? null : image;
        }
        catch (Exception error) when (MediaFailure(error))
        {
            return null;
        }
    }

    private void AnimateComicTurn(bool forward, bool doublePage)
    {
        if (!workMotionSettings.AnimationsEnabled)
            return;

        ComicPages.UpdateLayout();
        var page = forward || !doublePage ? ComicLeftPage : ComicRightPage;
        var visual = ElementCompositionPreview.GetElementVisual(page);
        var compositor = visual.Compositor;
        var hinge = !doublePage ? page.ActualWidth / 2 : forward ? page.ActualWidth : 0;
        visual.CenterPoint = new((float)hinge, (float)page.ActualHeight / 2, 0);
        visual.RotationAxis = Vector3.UnitY;
        var turn = compositor.CreateScalarKeyFrameAnimation();
        turn.Duration = TimeSpan.FromMilliseconds(240);
        turn.InsertKeyFrame(0, forward ? -76 : 76);
        turn.InsertKeyFrame(1, 0, compositor.CreateCubicBezierEasingFunction(new(.2f, .7f), new(.3f, 1)));
        visual.StartAnimation("RotationAngleInDegrees", turn);
    }

    private void ToggleImageSlideshow(object sender, RoutedEventArgs args)
    {
        SetImageSlideState(imageSlideState == ImageSlideState.Playing ? ImageSlideState.Paused : ImageSlideState.Playing);
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void StopImageSlideshow(object sender, RoutedEventArgs args)
    {
        SetImageSlideState(ImageSlideState.Stopped);
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void SetImageSlideState(ImageSlideState state)
    {
        imageSlideState = state;
        ImageSlideToggle.Content = state switch
        {
            ImageSlideState.Playing => "暂停自动播放",
            ImageSlideState.Paused => "继续自动播放",
            _ => "开始自动播放"
        };
        ImageSlideStop.Visibility = state == ImageSlideState.Stopped ? Visibility.Collapsed : Visibility.Visible;
        RestartImageSlideClock();
    }

    private void RestartImageSlideClock()
    {
        imageSlideClock.Stop();
        if (imageSlideReady && imageSlideState == ImageSlideState.Playing)
            imageSlideClock.Start();
    }

    private void AdvanceImageSlideshow()
    {
        if (imageSlideState != ImageSlideState.Playing || previewIndex < 0 || previewClosing)
            return;
        var next = CurrentComicSpread is { } spread ? spread.Next : previewIndex + 1;
        if (next is int index && index < previewTiles.Count && IsPreviewImage(index))
            ShowPreview(index, ThumbnailOf(previewTiles[index].Media.Id)?.Image, turningForward: true);
        else
            SetImageSlideState(ImageSlideState.Stopped);
    }

    private void SetImageSlidePreset(object sender, RoutedEventArgs args)
    {
        var button = (Button)sender;
        ImageSlideSeconds.Value = double.Parse((string)button.Tag, CultureInfo.InvariantCulture);
        ImageSlideIntervalFlyout.Hide();
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void SetCustomImageSlideInterval(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (double.IsNaN(args.NewValue))
            return;
        imageSlideClock.Interval = TimeSpan.FromSeconds(args.NewValue);
        ImageSlideInterval.Content = $"{args.NewValue:g} 秒";
        RestartImageSlideClock();
    }
}
