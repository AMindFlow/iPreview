using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.UI.ViewManagement;

namespace IPreview;

public sealed partial class MainWindow
{
    private ListViewBase? previewBrowser;
    private bool previewMoving;
    private bool previewClosing;
    private Action? afterPreviewMotion;

    private sealed record PreviewThumbnail(BitmapImage Image, Rect Bounds, Rect VisibleBounds);

    private PreviewThumbnail? ThumbnailOf(long? mediaId)
    {
        if (videoWorkSession is not null)
            return null;
        if (mediaId is null || previewBrowser is not { IsLoaded: true } browser)
            return null;
        var tile = tiles.FirstOrDefault(item => item.Media.Id == mediaId);
        if (tile is null || browser.ContainerFromItem(tile) is not UIElement container ||
            FindThumbnail(container) is not { Source: BitmapImage bitmap, ActualWidth: > 0, ActualHeight: > 0 } image ||
            bitmap.PixelWidth <= 0 || bitmap.PixelHeight <= 0)
            return null;

        var bounds = BoundsInRoot(image);
        var viewport = BoundsInRoot(browser);
        var left = Math.Max(bounds.Left, viewport.Left);
        var top = Math.Max(bounds.Top, viewport.Top);
        var right = Math.Min(bounds.Right, viewport.Right);
        var bottom = Math.Min(bounds.Bottom, viewport.Bottom);
        if (right - left < 8 || bottom - top < 8)
            return null;

        return new(bitmap, bounds, new Rect(left, top, right - left, bottom - top));
    }

    private static Image? FindThumbnail(DependencyObject element)
    {
        if (element is Image image)
            return image;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(element); index++)
        {
            var found = FindThumbnail(VisualTreeHelper.GetChild(element, index));
            if (found is not null)
                return found;
        }
        return null;
    }

    private Rect BoundsInRoot(FrameworkElement element) =>
        element.TransformToVisual(Root).TransformBounds(new Rect(0, 0, element.ActualWidth, element.ActualHeight));

    private void AnimatePreview(PreviewThumbnail? thumbnail, bool opening, Action? complete)
    {
        if (!new UISettings().AnimationsEnabled)
        {
            complete?.Invoke();
            return;
        }

        previewMoving = true;
        PreviewBackdrop.Opacity = PreviewContent.Opacity = opening ? 0 : 1;
        var canvasVisual = ElementCompositionPreview.GetElementVisual(PreviewMotionLayer);
        var compositor = canvasVisual.Compositor;
        var easing = compositor.CreateCubicBezierEasingFunction(new Vector2(.42f, 0), new Vector2(.58f, 1));
        var duration = TimeSpan.FromMilliseconds(240);
        var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
        InsetClip? clip = null;
        if (thumbnail is not null)
        {
            Root.UpdateLayout();
            var stage = BoundsInRoot(PreviewStage);
            var poster = thumbnail.Image;
            if (!opening && previewImageGeneration == previewGeneration &&
                MainImage.Source is BitmapImage { PixelWidth: > 0, PixelHeight: > 0 } shown)
                poster = shown;
            var ratio = (double)poster.PixelWidth / poster.PixelHeight;
            var fitted = MediaBounds(stage, ratio, fill: false);
            var filled = MediaBounds(thumbnail.Bounds, ratio, fill: true);
            if (fitted.Width > 0 && fitted.Height > 0)
            {
                PreviewStage.Opacity = 0;
                PreviewMotionImage.Source = poster;
                PreviewMotionImage.Width = fitted.Width;
                PreviewMotionImage.Height = fitted.Height;
                PreviewMotionLayer.Visibility = Visibility.Visible;
                PreviewMotionLayer.UpdateLayout();

                var from = opening ? filled : fitted;
                var to = opening ? fitted : filled;
                var visibleFrom = opening ? thumbnail.VisibleBounds : fitted;
                var visibleTo = opening ? fitted : thumbnail.VisibleBounds;
                clip = compositor.CreateInsetClip();
                canvasVisual.Clip = clip;
                StartMediaAnimation(compositor, easing, duration, from, to, fitted.Width);
                StartClipAnimation(clip, compositor, easing, duration, visibleFrom, visibleTo);
            }
        }
        StartPreviewFade(PreviewBackdrop, compositor, easing, duration, opening);
        StartPreviewFade(PreviewContent, compositor, easing, duration, opening);
        batch.Completed += (_, _) =>
        {
            canvasVisual.Clip = null;
            clip?.Dispose();
            PreviewMotionLayer.Visibility = Visibility.Collapsed;
            PreviewMotionImage.Source = null;
            PreviewMotionImage.Scale = Vector3.One;
            PreviewMotionImage.Translation = Vector3.Zero;
            PreviewBackdrop.Opacity = PreviewContent.Opacity = PreviewStage.Opacity = 1;
            batch.Dispose();
            previewMoving = false;
            complete?.Invoke();
            var pending = afterPreviewMotion;
            afterPreviewMotion = null;
            pending?.Invoke();
        };
        batch.End();
    }

    private void AnimatePreviewCopyFeedback()
    {
        if (!new UISettings().AnimationsEnabled)
            return;

        var compositor = ElementCompositionPreview.GetElementVisual(PreviewCopyFeedback).Compositor;
        var animation = compositor.CreateScalarKeyFrameAnimation();
        animation.Target = "Opacity";
        animation.Duration = TimeSpan.FromMilliseconds(120);
        animation.InsertKeyFrame(0, 0f);
        animation.InsertKeyFrame(1, 1f);
        PreviewCopyFeedback.StartAnimation(animation);
    }

    private void StartMediaAnimation(Compositor compositor, CompositionEasingFunction easing, TimeSpan duration,
                                     Rect from, Rect to, double normalWidth)
    {
        var start = (float)(from.Width / normalWidth);
        var end = (float)(to.Width / normalWidth);
        PreviewMotionImage.CenterPoint = Vector3.Zero;
        PreviewMotionImage.Scale = new Vector3(start, start, 1);
        PreviewMotionImage.Translation = new Vector3((float)from.X, (float)from.Y, 0);

        var scale = compositor.CreateVector3KeyFrameAnimation();
        scale.Target = "Scale";
        scale.Duration = duration;
        scale.InsertKeyFrame(1, new Vector3(end, end, 1), easing);
        PreviewMotionImage.StartAnimation(scale);

        var translation = compositor.CreateVector3KeyFrameAnimation();
        translation.Target = "Translation";
        translation.Duration = duration;
        translation.InsertKeyFrame(1, new Vector3((float)to.X, (float)to.Y, 0), easing);
        PreviewMotionImage.StartAnimation(translation);
    }

    private void StartClipAnimation(InsetClip clip, Compositor compositor, CompositionEasingFunction easing,
                                    TimeSpan duration, Rect from, Rect to)
    {
        clip.LeftInset = (float)from.Left;
        clip.TopInset = (float)from.Top;
        clip.RightInset = (float)(Root.ActualWidth - from.Right);
        clip.BottomInset = (float)(Root.ActualHeight - from.Bottom);
        Animate("LeftInset", (float)to.Left);
        Animate("TopInset", (float)to.Top);
        Animate("RightInset", (float)(Root.ActualWidth - to.Right));
        Animate("BottomInset", (float)(Root.ActualHeight - to.Bottom));

        void Animate(string property, float value)
        {
            var animation = compositor.CreateScalarKeyFrameAnimation();
            animation.Duration = duration;
            animation.InsertKeyFrame(1, value, easing);
            clip.StartAnimation(property, animation);
        }
    }

    private static void StartPreviewFade(UIElement element, Compositor compositor, CompositionEasingFunction easing,
                                         TimeSpan duration, bool opening)
    {
        var opacity = compositor.CreateScalarKeyFrameAnimation();
        opacity.Target = "Opacity";
        opacity.Duration = duration;
        opacity.InsertKeyFrame(1, opening ? 1 : 0, easing);
        element.StartAnimation(opacity);
    }

    private static Rect MediaBounds(Rect bounds, double aspectRatio, bool fill)
    {
        var proposedHeight = bounds.Width / aspectRatio;
        var height = fill ? Math.Max(bounds.Height, proposedHeight) : Math.Min(bounds.Height, proposedHeight);
        var width = height * aspectRatio;
        return new Rect(bounds.X + (bounds.Width - width) / 2, bounds.Y + (bounds.Height - height) / 2, width, height);
    }
}
