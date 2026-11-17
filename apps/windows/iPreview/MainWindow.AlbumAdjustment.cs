using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;

namespace IPreview;

public sealed partial class MainWindow
{
    private const ulong AlbumHoldMicroseconds = 350_000;
    private const double AlbumDragDistanceSquared = 16;

    private sealed record AlbumDropSlot(int Index, FrameworkElement Element, Rect Bounds, Transform? Transform);

    private sealed class AlbumPress(FrameworkElement surface, Pointer pointer, Tile tile, Point anchor, ulong time)
    {
        public FrameworkElement Surface { get; } = surface;
        public Pointer Pointer { get; } = pointer;
        public Tile Tile { get; } = tile;
        public Point Anchor { get; } = anchor;
        public ulong Time { get; } = time;
        public bool Rejected { get; set; }
        public int SourceIndex { get; set; } = -1;
        public int TargetIndex { get; set; } = -1;
        public long[]? ExpectedOrder { get; set; }
        public Rect SourceBounds { get; set; }
        public Rect Viewport { get; set; }
        public Rect WindowBounds { get; set; }
        public List<AlbumDropSlot> Slots { get; } = [];
        public bool Dragging => SourceIndex >= 0;
    }

    private AlbumPress? albumPress;

    private void AlbumAdjustmentPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (!SelectingAlbumMembers || sender is not FrameworkElement { DataContext: Tile tile } surface)
            return;
        var input = args.GetCurrentPoint(AlbumDragLayer);
        if (!input.Properties.IsLeftButtonPressed)
            return;
        args.Handled = true;
        if (busy || albumPress is not null || !surface.CapturePointer(args.Pointer))
            return;
        albumPress = new AlbumPress(surface, args.Pointer, tile, input.Position, input.Timestamp);
        if (ActiveMediaBrowser.ContainerFromItem(tile) is Control item)
            item.Focus(FocusState.Pointer);
    }

    private void AlbumAdjustmentTapped(object sender, TappedRoutedEventArgs args)
    {
        if (SelectingAlbumMembers)
            args.Handled = true;
    }

    private void AlbumAdjustmentPointerMoved(object sender, PointerRoutedEventArgs args)
    {
        if (albumPress is not { } press || press.Pointer.PointerId != args.Pointer.PointerId)
            return;
        args.Handled = true;
        if (press.Rejected)
            return;
        var input = args.GetCurrentPoint(AlbumDragLayer);
        if (!press.Dragging)
        {
            if (!Moved(input.Position, press.Anchor))
                return;
            if (tiles.Count < 2 || !StartAlbumDrag(press))
            {
                press.Rejected = true;
                return;
            }
        }
        UpdateAlbumDrag(press, input.Position);
    }

    private void AlbumAdjustmentPointerReleased(object sender, PointerRoutedEventArgs args)
    {
        if (albumPress is not { } press || press.Pointer.PointerId != args.Pointer.PointerId)
            return;
        args.Handled = true;
        var input = args.GetCurrentPoint(AlbumDragLayer);
        if (press.Dragging)
            UpdateAlbumDrag(press, input.Position);
        var destination = press.TargetIndex;
        CancelAlbumAdjustmentPointer();
        if (press.Dragging)
        {
            if (destination >= 0 && destination != press.SourceIndex && selectionAlbum is long album)
                SaveAlbumOrder(album, press.Tile.Media.Id, destination, press.ExpectedOrder!);
        }
        else if (!press.Rejected && input.Timestamp - press.Time < AlbumHoldMicroseconds &&
                 !Moved(input.Position, press.Anchor) &&
                 DragBounds(press.Surface).Contains(input.Position))
        {
            var selection = ActiveMediaBrowser.SelectedItems;
            if (selection.Contains(press.Tile))
                selection.Remove(press.Tile);
            else
                selection.Add(press.Tile);
        }
    }

    private void AlbumAdjustmentPointerInterrupted(object sender, PointerRoutedEventArgs args)
    {
        if (albumPress is { } press && press.Pointer.PointerId == args.Pointer.PointerId)
            CancelAlbumAdjustmentPointer();
    }

    private static bool Moved(Point point, Point anchor)
    {
        var x = point.X - anchor.X;
        var y = point.Y - anchor.Y;
        return x * x + y * y >= AlbumDragDistanceSquared;
    }

    private Rect DragBounds(FrameworkElement element) => element.TransformToVisual(AlbumDragLayer)
        .TransformBounds(new Rect(0, 0, element.ActualWidth, element.ActualHeight));

    private bool StartAlbumDrag(AlbumPress press)
    {
        var browser = ActiveMediaBrowser;
        if (browser.ItemsPanelRoot is not Panel panel)
            return false;
        var index = tiles.IndexOf(press.Tile);
        if (index < 0)
            return false;
        press.SourceBounds = DragBounds(press.Surface);
        press.Viewport = DragBounds(browser);
        press.WindowBounds = new Rect(0, 0, AlbumDragLayer.ActualWidth, AlbumDragLayer.ActualHeight);
        foreach (var element in panel.Children.OfType<FrameworkElement>())
        {
            var slot = browser.IndexFromContainer(element);
            if (slot >= 0)
                press.Slots.Add(new AlbumDropSlot(slot, element, DragBounds(element), element.RenderTransform));
        }
        if (!press.Slots.Exists(slot => slot.Index == index))
            return false;
        press.SourceIndex = index;
        press.ExpectedOrder = tiles.Select(tile => tile.Media.Id).ToArray();
        AlbumDragCaption.Text = press.Tile.FileName;
        AlbumDragImage.Source = null;
        AlbumDragAvatar.Width = AlbumDropPlaceholder.Width = press.SourceBounds.Width;
        AlbumDragAvatar.Height = AlbumDropPlaceholder.Height = press.SourceBounds.Height;
        SnapshotAlbumDragAvatar(press);
        return true;
    }

    private async void SnapshotAlbumDragAvatar(AlbumPress press)
    {
        try
        {
            var bitmap = new RenderTargetBitmap();
            await bitmap.RenderAsync(press.Surface);
            if (ReferenceEquals(albumPress, press) && bitmap.PixelWidth > 0)
                AlbumDragImage.Source = bitmap;
        }
        catch (COMException)
        {
            // The source-sized filename tile remains available if the renderer cannot capture the content.
        }
    }

    private void UpdateAlbumDrag(AlbumPress press, Point point)
    {
        var source = press.SourceBounds;
        var x = source.Left + point.X - press.Anchor.X;
        var y = source.Top + point.Y - press.Anchor.Y;
        var target = press.Viewport.Contains(point) && press.WindowBounds.Contains(point)
            ? press.Slots
                .Where(slot => VisibleIn(slot.Bounds, press.Viewport))
                .MinBy(slot =>
                {
                    var bounds = slot.Bounds;
                    var dx = (x + source.Width / 2 - bounds.Left - bounds.Width / 2) / Math.Max(1, bounds.Width / 2);
                    var dy = (y + source.Height / 2 - bounds.Top - bounds.Height / 2) / Math.Max(1, bounds.Height / 2);
                    return dx * dx + dy * dy;
                })
            : null;
        AlbumDragAvatar.Visibility = AlbumDropPlaceholder.Visibility =
            target is null ? Visibility.Collapsed : Visibility.Visible;
        Canvas.SetLeft(AlbumDragAvatar, x);
        Canvas.SetTop(AlbumDragAvatar, y);
        var destination = target?.Index ?? -1;
        if (press.TargetIndex == destination)
            return;
        press.TargetIndex = destination;
        var origin = press.Slots.Single(slot => slot.Index == press.SourceIndex);
        origin.Element.Opacity = target is not null ? 0.2 : 1;
        if (target is not null)
        {
            Canvas.SetLeft(AlbumDropPlaceholder, source.Left + target.Bounds.Left - origin.Bounds.Left);
            Canvas.SetTop(AlbumDropPlaceholder, source.Top + target.Bounds.Top - origin.Bounds.Top);
        }
        foreach (var slot in press.Slots)
        {
            var shifted = destination < 0 ? slot.Index
                : slot.Index == press.SourceIndex ? destination
                : press.SourceIndex < slot.Index && slot.Index <= destination ? slot.Index - 1
                : destination <= slot.Index && slot.Index < press.SourceIndex ? slot.Index + 1
                : slot.Index;
            var next = shifted == slot.Index ? null : press.Slots.Find(candidate => candidate.Index == shifted);
            slot.Element.RenderTransform = next is null ? slot.Transform : new TranslateTransform
            {
                X = next.Bounds.Left - slot.Bounds.Left,
                Y = next.Bounds.Top - slot.Bounds.Top
            };
        }
    }

    private static bool VisibleIn(Rect bounds, Rect viewport) =>
        bounds.Left < viewport.Right && bounds.Right > viewport.Left &&
        bounds.Top < viewport.Bottom && bounds.Bottom > viewport.Top;

    private void CancelAlbumAdjustmentPointer()
    {
        if (albumPress is not { } press)
            return;
        albumPress = null;
        press.Surface.ReleasePointerCapture(press.Pointer);
        foreach (var slot in press.Slots)
        {
            slot.Element.RenderTransform = slot.Transform;
            if (slot.Index == press.SourceIndex)
                slot.Element.Opacity = 1;
        }
        AlbumDragAvatar.Visibility = AlbumDropPlaceholder.Visibility = Visibility.Collapsed;
        AlbumDragImage.Source = null;
    }

    private void SaveAlbumOrder(long album, long mediaId, int target, long[] expected)
    {
        try
        {
            Database.MoveInAlbum(album, mediaId, target, expected);
            Reload(mediaId);
            FocusAlbumSelectionItem(mediaId);
        }
        catch (AlbumOrderChangedException error)
        {
            Reload(mediaId);
            ShowNotice("无法调整顺序", error.Message);
        }
        catch (InvalidOperationException error) { ShowNotice("无法调整顺序", error.Message); }
    }
}
