using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record WorkPhotoCard(long MediaId, Grid Print, CompositeTransform Pose);

    private static readonly (double X, double Y, double Angle)[] WorkPrintFan =
        [(0, 0, 0), (-5, 4, -3.2), (6, 6, 2.6), (-8, 10, -4.8), (7, 13, 3.8)];
    private const double WorkPrintWidth = 188;
    private const double WorkPrintHeight = 222;
    private const double WorkWheelThreshold = 120;

    private readonly List<WorkPhotoCard> workPhotoCards = [];
    private int workPhotoFanDirection;
    private Storyboard? workPhotoPeel;
    private DispatcherQueueTimer? workPileWheelIdle;
    private double workWheelDistance;
    private bool workWheelCommitted;

    private void PresentWorkPhotoPile(VideoWorkSession session, int direction = 1)
    {
        var photos = session.Groups[session.OverviewGroup].Items;
        var count = Math.Min(WorkPrintFan.Length, photos.Count);
        var cards = new WorkPhotoCard[count];
        for (var depth = 0; depth < count; depth++)
        {
            var photo = photos[WorkPileIndex(session.OverviewPhotoIndex, direction * depth, photos.Count)];
            cards[depth] = workPhotoCards.Find(card => card.MediaId == photo.Id) ?? MakeWorkPhotoCard(photo);
            SetWorkPrintPose(cards[depth].Pose, depth);
        }

        VideoWorkPrints.Children.Clear();
        workPhotoCards.Clear();
        workPhotoCards.AddRange(cards);
        for (var depth = cards.Length - 1; depth >= 0; depth--)
            VideoWorkPrints.Children.Add(cards[depth].Print);
        workPhotoFanDirection = direction;
        UpdateWorkPileName(session);
    }

    private static int WorkPileIndex(int index, int offset, int count) => (index + offset + count) % count;

    private WorkPhotoCard MakeWorkPhotoCard(Media photo)
    {
        var image = new Image { DataContext = new Tile(photo, 0), Stretch = Stretch.UniformToFill };
        void LoadPrint(object sender, RoutedEventArgs args)
        {
            image.Loaded -= LoadPrint;
            LoadThumbnail(image);
        }
        image.Loaded += LoadPrint;

        var imageLayer = new Grid { Background = new SolidColorBrush(Color.FromArgb(255, 83, 82, 79)) };
        imageLayer.Children.Add(new FontIcon
        {
            Glyph = "\uE91B", FontSize = 24,
            Foreground = new SolidColorBrush(Color.FromArgb(255, 224, 221, 214))
        });
        imageLayer.Children.Add(image);

        var pose = new CompositeTransform();
        var print = new Grid
        {
            Width = WorkPrintWidth, Height = WorkPrintHeight,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new(.5, .5), RenderTransform = pose
        };
        print.Children.Add(new Border
        {
            CornerRadius = new(4), Background = new SolidColorBrush(Color.FromArgb(82, 0, 0, 0)),
            RenderTransform = new TranslateTransform { X = 2, Y = 4 }
        });
        print.Children.Add(new Border
        {
            CornerRadius = new(4), Padding = new(5, 5, 5, 12), BorderThickness = new(1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(255, 198, 195, 190)),
            Background = new SolidColorBrush(Color.FromArgb(255, 241, 239, 232)),
            Child = imageLayer
        });
        return new(photo.Id, print, pose);
    }

    private static void SetWorkPrintPose(CompositeTransform pose, int depth)
    {
        (pose.TranslateX, pose.TranslateY, pose.Rotation) = WorkPrintFan[depth];
        pose.ScaleX = pose.ScaleY = 1 - depth * .022;
    }

    private void UpdateWorkPileName(VideoWorkSession session)
    {
        var photos = session.Groups[session.OverviewGroup].Items;
        var index = session.OverviewPhotoIndex;
        AutomationProperties.SetName(VideoWorkPhotoPile,
            $"{session.Groups[session.OverviewGroup].Title}，{photos[index].FileName}，{index + 1} / {photos.Count}");
    }

    private void VideoWorkPileWheelChanged(object sender, PointerRoutedEventArgs args)
    {
        var pointer = args.GetCurrentPoint(VideoWorkPhotoPile).Properties;
        if (!pointer.IsHorizontalMouseWheel || pointer.MouseWheelDelta == 0 ||
            videoWorkSession is not { Browsing: false } session || workOpeningVisuals is not null ||
            session.Groups[session.OverviewGroup].Items.Count < 2)
            return;

        // WinUI reports horizontal wheel packets without gesture phases. Keep each burst
        // locked after its first page until packets stop, including the momentum tail.
        var idle = workPileWheelIdle ??= CreateWorkPileWheelTimer();
        idle.Stop();
        idle.Start();
        args.Handled = true;
        if (workWheelCommitted || workPhotoPeel is not null)
            return;

        workWheelDistance += pointer.MouseWheelDelta;
        var direction = Math.Sign(workWheelDistance);
        if (Math.Abs(workWheelDistance) >= WorkWheelThreshold)
        {
            workWheelCommitted = true;
            MoveWorkPile(direction);
        }
        else if (workMotionSettings.AnimationsEnabled)
        {
            if (direction != 0 && workPhotoFanDirection != direction)
                PresentWorkPhotoPile(session, direction);
            UpdateWorkPeelPose(-workWheelDistance * (WorkPrintWidth * .28 / WorkWheelThreshold));
        }
    }

    private DispatcherQueueTimer CreateWorkPileWheelTimer()
    {
        var timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(230);
        timer.IsRepeating = false;
        timer.Tick += (_, _) =>
        {
            if (!workWheelCommitted)
                RelaxWorkPhotoPile();
            ResetWorkPileWheel();
        };
        return timer;
    }

    private void VideoWorkPilePointerExited(object sender, PointerRoutedEventArgs args)
    {
        if (!workWheelCommitted)
        {
            workWheelDistance = 0;
            RelaxWorkPhotoPile();
        }
    }

    private void ResetWorkPileWheel()
    {
        workPileWheelIdle?.Stop();
        workWheelDistance = 0;
        workWheelCommitted = false;
    }

    private void RelaxWorkPhotoPile()
    {
        if (workPhotoPeel is null && workPhotoCards.Count > 1)
        {
            var front = workPhotoCards[0].Pose;
            if (front.TranslateX != 0)
                AnimateWorkPhotoPeel(
                    front, workPhotoCards[1].Pose, destination: 0, duration: 150, completed: () => { });
        }
    }

    private void UpdateWorkPeelPose(double travel)
    {
        var front = workPhotoCards[0].Pose;
        front.TranslateX = travel;
        front.Rotation = travel * .045;
        var fraction = Math.Min(1, Math.Abs(travel) / (WorkPrintWidth * .28));
        front.ScaleX = front.ScaleY = 1 + .02 * fraction;

        var next = workPhotoCards[1].Pose;
        var (x, y, angle) = WorkPrintFan[1];
        next.TranslateX = x * (1 - fraction);
        next.TranslateY = y * (1 - fraction);
        next.Rotation = angle * (1 - fraction);
        next.ScaleX = next.ScaleY = 1 - .022 * (1 - fraction);
    }

    private void MoveWorkPile(int direction)
    {
        if (videoWorkSession is not { Browsing: false } session ||
            workPhotoPeel is not null || session.Groups[session.OverviewGroup].Items.Count < 2)
            return;

        if (workPhotoFanDirection != direction)
            PresentWorkPhotoPile(session, direction);
        session.OverviewPhotoIndex = WorkPileIndex(session.OverviewPhotoIndex, direction,
            session.Groups[session.OverviewGroup].Items.Count);
        UpdateWorkPileName(session);

        if (!workMotionSettings.AnimationsEnabled)
        {
            PresentWorkPhotoPile(session);
            return;
        }

        AnimateWorkPhotoPeel(workPhotoCards[0].Pose, workPhotoCards[1].Pose,
            destination: -direction * WorkPrintWidth * .64, duration: 185, completed: () => PresentWorkPhotoPile(session));
    }

    private void AnimateWorkPhotoPeel(CompositeTransform front, CompositeTransform next, double destination,
        double duration, Action completed)
    {
        var animating = workPhotoPeel = new Storyboard();
        var leaving = destination != 0;
        var (nextX, nextY, nextAngle) = leaving ? (0d, 0d, 0d) : WorkPrintFan[1];
        Add(front, "TranslateX", destination);
        Add(front, "Rotation", destination * .045);
        Add(front, "ScaleX", leaving ? 1.02 : 1);
        Add(front, "ScaleY", leaving ? 1.02 : 1);
        if (leaving)
            Add(workPhotoCards[0].Print, "Opacity", 0);
        Add(next, "TranslateX", nextX);
        Add(next, "TranslateY", nextY);
        Add(next, "Rotation", nextAngle);
        Add(next, "ScaleX", leaving ? 1 : .978);
        Add(next, "ScaleY", leaving ? 1 : .978);

        animating.Completed += (_, _) =>
        {
            if (!ReferenceEquals(workPhotoPeel, animating))
                return;
            workPhotoPeel = null;
            // Recompose the rest poses before the ending animation releases its values.
            if (!leaving)
            {
                SetWorkPrintPose(front, 0);
                SetWorkPrintPose(next, 1);
            }
            animating.Stop();
            completed();
        };
        animating.Begin();

        void Add(DependencyObject target, string property, double value)
        {
            var animation = new DoubleAnimation
            {
                To = value, Duration = new Duration(TimeSpan.FromMilliseconds(duration)),
                EnableDependentAnimation = true, EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(animation, target);
            Storyboard.SetTargetProperty(animation, property);
            animating.Children.Add(animation);
        }
    }

    private void CancelWorkPhotoPeel()
    {
        var animating = workPhotoPeel;
        workPhotoPeel = null;
        animating?.Stop();
    }
}
