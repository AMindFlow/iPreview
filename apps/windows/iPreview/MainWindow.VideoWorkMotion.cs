using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI.ViewManagement;

namespace IPreview;

public sealed partial class MainWindow
{
    private static readonly Matrix4x4 WorkTapeFrontPerspective = CreateWorkTapeFrontPerspective();
    private static readonly Matrix4x4 WorkTapeSpinePerspective = CreateWorkTapeSpinePerspective();
    private readonly UISettings workMotionSettings = new();
    private List<Visual>? workOpeningVisuals;
    private Storyboard? workAuraAnimation;

    private static Matrix4x4 CreateWorkTapeFrontPerspective()
    {
        const float viewWidth = (float)WorkTapeWidth;
        const float viewHeight = (float)WorkTapeHeight;
        const float frontWidth = 172f;
        const float frontHeight = 308f;

        const float x0 = 0.155f * viewWidth;
        const float y0 = 0.045f * viewHeight;
        const float x1 = 0.970f * viewWidth;
        const float y1 = 0.082f * viewHeight;
        const float x2 = 0.970f * viewWidth;
        const float y2 = 0.930f * viewHeight;
        const float x3 = 0.155f * viewWidth;
        const float y3 = 0.969f * viewHeight;

        const float leftHeight = y3 - y0;
        const float rightHeight = y2 - y1;
        const float p = leftHeight / rightHeight - 1f;
        const float leftScale = leftHeight / frontHeight;

        const float yaw = 24f * (MathF.PI / 180f);
        const float m14 = p / frontWidth;
        float m34 = -m14 / MathF.Tan(yaw);
        const float vx = viewWidth * 0.5f;
        const float vy = viewHeight * 0.5f;

        return new Matrix4x4(
            ((1f + p) * x1 - x0) / frontWidth, ((1f + p) * y1 - y0) / frontWidth, 0f, m14,
            (x3 - x0) / frontHeight, leftScale, 0f, 0f,
            leftScale * MathF.Sin(yaw) + vx * m34, vy * m34, 1f, m34,
            x0, y0, 0f, 1f);
    }

    private static Matrix4x4 CreateWorkTapeSpinePerspective()
    {
        const float viewWidth = (float)WorkTapeWidth;
        const float viewHeight = (float)WorkTapeHeight;
        const float spineWidth = 22f;
        const float spineHeight = 308f;

        const float ex = 0.065f * viewWidth;
        const float ey = 0.060f * viewHeight;
        const float ax = 0.155f * viewWidth;
        const float ay = 0.045f * viewHeight;
        const float dx = 0.155f * viewWidth;
        const float dy = 0.969f * viewHeight;
        const float fx = 0.065f * viewWidth;
        const float fy = 0.946f * viewHeight;

        const float backHeight = fy - ey;
        const float frontHeight = dy - ay;
        const float p = backHeight / frontHeight - 1f;

        return new Matrix4x4(
            ((1f + p) * ax - ex) / spineWidth, ((1f + p) * ay - ey) / spineWidth, 0f, p / spineWidth,
            (fx - ex) / spineHeight, backHeight / spineHeight, 0f, 0f,
            0f, 0f, 1f, 0f,
            ex, ey, 0f, 1f);
    }

    private void VideoWorkTapeFrontLoaded(object sender, RoutedEventArgs args) =>
        VideoWorkTapeFront.TransformMatrix = WorkTapeFrontPerspective;

    private void VideoWorkTapeSpineLoaded(object sender, RoutedEventArgs args) =>
        VideoWorkTapeSpine.TransformMatrix = WorkTapeSpinePerspective;

    private void AnimateWorkOpening(VideoWorkSession session, Action open)
    {
        if (!workMotionSettings.AnimationsEnabled)
        {
            open();
            return;
        }

        var lid = ElementCompositionPreview.GetElementVisual(VideoWorkTapeLid);
        var compositor = lid.Compositor;
        var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
        var easing = compositor.CreateCubicBezierEasingFunction(new(.22f, .63f), new(.38f, 1));
        var visuals = workOpeningVisuals = [lid];
        var duration = TimeSpan.FromMilliseconds(335);
        lid.CenterPoint = new(1, (float)VideoWorkTapeLid.ActualHeight / 2, 0);
        lid.RotationAxis = Vector3.UnitY;
        var hinge = compositor.CreateScalarKeyFrameAnimation();
        hinge.Duration = duration;
        hinge.InsertKeyFrame(0, 0);
        hinge.InsertKeyFrame(1, 65, easing);
        lid.StartAnimation("RotationAngleInDegrees", hinge);
        AnimateWorkOpacity(lid, 1, .36f, duration);

        for (var depth = 0; depth < workPhotoCards.Count; depth++)
        {
            var print = workPhotoCards[depth].Print;
            var visual = ElementCompositionPreview.GetElementVisual(print);
            visuals.Add(visual);
            visual.CenterPoint = new((float)print.ActualWidth / 2, (float)print.ActualHeight / 2, 0);
            var comingForward = depth == 0;
            AnimateWorkScale(visual, 1, comingForward ? 1.15f : .76f, duration, easing);
            AnimateWorkOpacity(visual, 1, comingForward ? .86f : .16f, duration);
        }

        batch.Completed += (_, _) =>
        {
            batch.Dispose();
            if (!ReferenceEquals(workOpeningVisuals, visuals))
                return;
            CancelWorkOpening();
            if (ReferenceEquals(session, videoWorkSession))
                open();
        };
        batch.End();
    }

    private void CancelWorkOpening()
    {
        var visuals = workOpeningVisuals;
        if (visuals is null)
            return;
        workOpeningVisuals = null;
        foreach (var visual in visuals)
        {
            visual.StopAnimation("Scale");
            visual.StopAnimation("Opacity");
            visual.StopAnimation("RotationAngleInDegrees");
            visual.Scale = Vector3.One;
            visual.Opacity = 1;
            visual.RotationAngleInDegrees = 0;
        }
    }

    private void AnimateWorkArrival(FrameworkElement content, float initialScale)
    {
        if (!workMotionSettings.AnimationsEnabled)
            return;
        content.UpdateLayout();
        var visual = ElementCompositionPreview.GetElementVisual(content);
        var compositor = visual.Compositor;
        var easing = compositor.CreateCubicBezierEasingFunction(new(.15f, .65f), new(.25f, 1));
        var duration = TimeSpan.FromMilliseconds(300);
        visual.CenterPoint = new((float)content.ActualWidth / 2, (float)content.ActualHeight / 2, 0);
        AnimateWorkScale(visual, initialScale, 1, duration, easing);
        AnimateWorkOpacity(visual, .60f, 1, duration);
    }

    private static void ResetWorkArrival(UIElement content)
    {
        var visual = ElementCompositionPreview.GetElementVisual(content);
        visual.StopAnimation("Scale");
        visual.StopAnimation("Opacity");
        visual.Scale = Vector3.One;
        visual.Opacity = 1;
    }

    private void WorkAnimationsChanged(UISettings sender, UISettingsAnimationsEnabledChangedEventArgs args)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            if (BrowsingVideoWork)
                StartWorkAura();
        });
    }

    private static void AnimateWorkScale(Visual visual, float from, float to, TimeSpan duration,
        CompositionEasingFunction easing)
    {
        var animation = visual.Compositor.CreateVector3KeyFrameAnimation();
        animation.Duration = duration;
        animation.InsertKeyFrame(0, new(from, from, 1));
        animation.InsertKeyFrame(1, new(to, to, 1), easing);
        visual.StartAnimation("Scale", animation);
    }

    private static void AnimateWorkOpacity(Visual visual, float from, float to, TimeSpan duration)
    {
        var animation = visual.Compositor.CreateScalarKeyFrameAnimation();
        animation.Duration = duration;
        animation.InsertKeyFrame(0, from);
        animation.InsertKeyFrame(1, to);
        visual.StartAnimation("Opacity", animation);
    }

    private void StartWorkAura()
    {
        if (!workMotionSettings.AnimationsEnabled)
        {
            workAuraAnimation?.Stop();
            workAuraAnimation = null;
            return;
        }
        if (workAuraAnimation is not null)
            return;

        var rotation = ((LinearGradientBrush)WorkVideoAura.BorderBrush).RelativeTransform;
        var turn = new DoubleAnimation
        {
            From = 0, To = 360, Duration = new Duration(TimeSpan.FromSeconds(5)),
            RepeatBehavior = RepeatBehavior.Forever,
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(turn, rotation);
        Storyboard.SetTargetProperty(turn, "Angle");
        var animation = workAuraAnimation = new Storyboard();
        animation.Children.Add(turn);
        animation.Begin();
    }

    private void StopWorkAura()
    {
        workAuraAnimation?.Stop();
        workAuraAnimation = null;
        WorkVideoAura.Visibility = WorkPhotoAura.Visibility = Visibility.Collapsed;
    }
}
