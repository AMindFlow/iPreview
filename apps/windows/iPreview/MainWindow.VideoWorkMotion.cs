using System.Numerics;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI.ViewManagement;

namespace IPreview;

public sealed partial class MainWindow
{
    private readonly UISettings workMotionSettings = new();
    private List<Visual>? workOpeningVisuals;
    private Storyboard? workAuraAnimation;

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
        hinge.InsertKeyFrame(1, -83, easing);
        lid.StartAnimation("RotationAngleInDegrees", hinge);
        AnimateWorkOpacity(lid, 1, .36f, duration);

        var selected = VideoWorkItems.ContainerFromIndex(session.OpeningGroup);
        if (VideoWorkItems.ItemsPanelRoot is Panel panel)
        {
            foreach (var book in panel.Children.OfType<GridViewItem>())
            {
                var visual = ElementCompositionPreview.GetElementVisual(book);
                visuals.Add(visual);
                visual.CenterPoint = new((float)book.ActualWidth / 2, (float)book.ActualHeight / 2, 0);
                var comingForward = ReferenceEquals(book, selected);
                AnimateWorkScale(visual, 1, comingForward ? 1.15f : .76f, duration, easing);
                AnimateWorkOpacity(visual, 1, comingForward ? .86f : .16f, duration);
            }
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
