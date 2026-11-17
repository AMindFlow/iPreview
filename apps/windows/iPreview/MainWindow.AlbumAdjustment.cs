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
    private const double AlbumScrollMargin = 36;
    private const double AlbumScrollStep = 22;

    private sealed record AlbumDropSlot(int Index, FrameworkElement Element, Rect Bounds, Transform? Transform, double Opacity);

    private sealed class AlbumPress(ListViewBase browser, FrameworkElement surface, Pointer pointer, Tile tile,
        Point anchor, Rect sourceBounds, ulong time)
    {
        public ListViewBase Browser { get; } = browser;
        public FrameworkElement Surface { get; } = surface;
        public Pointer Pointer { get; } = pointer;
        public Tile Tile { get; } = tile;
        public Point Anchor { get; } = anchor;
        public Rect SourceBounds { get; } = sourceBounds;
        public ulong Time { get; } = time;
        public bool Rejected { get; set; }
        public int SourceIndex { get; set; } = -1;
        public int TargetIndex { get; set; } = -1;
        public long[]? ExpectedOrder { get; set; }
        public Point SourceInset { get; set; }
        public Point Position { get; set; }
        public ScrollViewer? Scroll { get; set; }
        public FrameworkElement? ContentViewport { get; set; }
        public Rect Viewport { get; set; }
        public Rect WindowBounds { get; set; }
        public bool SlotsDirty { get; set; }
        public Dictionary<int, AlbumDropSlot> Slots { get; } = [];
        public bool Dragging => SourceIndex >= 0;
    }

    private AlbumPress? albumPress;
    private readonly DispatcherTimer albumDragScroll = new() { Interval = TimeSpan.FromMilliseconds(30) };

    private void AlbumAdjustmentPointerPressed(object sender, PointerRoutedEventArgs args)
    {
        if (!SelectingAlbumMembers || sender is not FrameworkElement { DataContext: Tile tile } surface)
            return;
        var input = args.GetCurrentPoint(AlbumDragLayer);
        if (!input.Properties.IsLeftButtonPressed)
            return;
        args.Handled = true;
        if (busy || albumPress is not null || !Root.CapturePointer(args.Pointer))
            return;
        var browser = ActiveMediaBrowser;
        albumPress = new AlbumPress(browser, surface, args.Pointer, tile, input.Position, DragBounds(surface),
            input.Timestamp);
        if (browser.ContainerFromItem(tile) is Control item)
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
        {
            press.Browser.UpdateLayout();
            if (!ReferenceEquals(albumPress, press))
                return;
            press.SlotsDirty = true;
            UpdateAlbumDrag(press, input.Position);
        }
        var destination = press.TargetIndex;
        CancelAlbumAdjustmentPointer();
        if (press.Dragging)
        {
            if (destination >= 0 && destination != press.SourceIndex && selectionAlbum is long album)
                SaveAlbumOrder(album, press, destination);
        }
        else if (!press.Rejected && input.Timestamp - press.Time < AlbumHoldMicroseconds &&
                 !Moved(input.Position, press.Anchor) &&
                 ReferenceEquals(press.Surface.DataContext, press.Tile) &&
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

    private void AlbumAdjustmentPointerWheelChanged(object sender, PointerRoutedEventArgs args)
    {
        if (albumPress is not { Dragging: true, Scroll: not null } press)
            return;
        var input = args.GetCurrentPoint(AlbumDragLayer);
        if (!press.Viewport.Contains(input.Position) || (input.Properties.IsHorizontalMouseWheel && press.Browser != Filmstrip))
            return;
        args.Handled = true;
        var delta = input.Properties.MouseWheelDelta;
        ScrollAlbumDragBy(press, input.Properties.IsHorizontalMouseWheel ? delta : -delta);
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
        if (press.Browser.ItemsPanelRoot is not Panel panel || !ReferenceEquals(press.Surface.DataContext, press.Tile))
            return false;
        var index = tiles.IndexOf(press.Tile);
        if (index < 0)
            return false;
        for (var ancestor = VisualTreeHelper.GetParent(panel); ancestor is not null && ancestor != press.Browser;
             ancestor = VisualTreeHelper.GetParent(ancestor))
        {
            if (ancestor is ScrollContentPresenter viewport)
                press.ContentViewport = viewport;
            if (ancestor is ScrollViewer scroll)
            {
                press.Scroll = scroll;
                break;
            }
        }
        RefreshAlbumDropSlots(press);
        if (!press.Slots.TryGetValue(index, out var origin))
            return false;
        press.SourceIndex = index;
        var surface = DragBounds(press.Surface);
        press.SourceInset = new Point(surface.Left - origin.Bounds.Left, surface.Top - origin.Bounds.Top);
        press.ExpectedOrder = tiles.Select(tile => tile.Media.Id).ToArray();
        if (press.Scroll is not null)
            press.Scroll.ViewChanged += AlbumDragViewChanged;
        press.Browser.SizeChanged += AlbumDragSizeChanged;
        press.Browser.ContainerContentChanging += AlbumDragContainerChanged;
        albumDragScroll.Tick += ScrollAlbumDrag;
        albumDragScroll.Start();
        AlbumDragCaption.Text = press.Tile.FileName;
        AlbumDragImage.Source = null;
        AlbumDragAvatar.Width = AlbumDropPlaceholder.Width = press.SourceBounds.Width;
        AlbumDragAvatar.Height = AlbumDropPlaceholder.Height = press.SourceBounds.Height;
        SnapshotAlbumDragAvatar(press);
        return true;
    }

    private void AlbumDragViewChanged(object? sender, ScrollViewerViewChangedEventArgs args) => InvalidateAlbumDropSlots();
    private void AlbumDragSizeChanged(object sender, SizeChangedEventArgs args) => InvalidateAlbumDropSlots();
    private void AlbumDragContainerChanged(ListViewBase sender, ContainerContentChangingEventArgs args) => InvalidateAlbumDropSlots();

    private void InvalidateAlbumDropSlots()
    {
        if (albumPress is { Dragging: true } press)
            press.SlotsDirty = true;
    }

    private void ScrollAlbumDrag(object? sender, object args)
    {
        if (albumPress is not { Dragging: true } press)
            return;
        if (press.SlotsDirty)
            UpdateAlbumDrag(press, press.Position);
        if (press.Scroll is null || !press.Viewport.Contains(press.Position) ||
            !press.WindowBounds.Contains(press.Position))
            return;

        var horizontal = press.Browser == Filmstrip;
        var start = horizontal ? press.Viewport.Left : press.Viewport.Top;
        var end = horizontal ? press.Viewport.Right : press.Viewport.Bottom;
        var position = horizontal ? press.Position.X : press.Position.Y;
        var edge = Math.Min(AlbumScrollMargin, (end - start) / 2);
        if (edge <= 0)
            return;
        var amount = Math.Max(0, (position - (end - edge)) / edge) -
                     Math.Max(0, ((start + edge) - position) / edge);
        ScrollAlbumDragBy(press, amount * AlbumScrollStep);
    }

    private void ScrollAlbumDragBy(AlbumPress press, double amount)
    {
        var scroll = press.Scroll!;
        var horizontal = press.Browser == Filmstrip;
        var offset = horizontal ? scroll.HorizontalOffset : scroll.VerticalOffset;
        var limit = horizontal ? scroll.ScrollableWidth : scroll.ScrollableHeight;
        var next = Math.Clamp(offset + amount, 0, limit);
        if (Math.Abs(next - offset) > 0.5 &&
            scroll.ChangeView(horizontal ? next : null, horizontal ? null : next, null, disableAnimation: true))
            press.SlotsDirty = true;
    }

    private void RefreshAlbumDropSlots(AlbumPress press)
    {
        RestoreAlbumDropSlots(press);
        press.Slots.Clear();
        press.TargetIndex = -1;
        press.SlotsDirty = false;
        var browser = press.Browser;
        press.Viewport = DragBounds(press.ContentViewport ?? browser);
        press.WindowBounds = new Rect(0, 0, AlbumDragLayer.ActualWidth, AlbumDragLayer.ActualHeight);
        if (browser.ItemsPanelRoot is not Panel panel)
            return;

        foreach (var element in panel.Children.OfType<FrameworkElement>())
        {
            var index = browser.IndexFromContainer(element);
            if (index >= 0 && ReferenceEquals(browser.ContainerFromIndex(index), element))
                press.Slots.Add(index, new AlbumDropSlot(index, element, DragBounds(element), element.RenderTransform,
                    element.Opacity));
        }
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
        press.Position = point;
        if (press.SlotsDirty)
            RefreshAlbumDropSlots(press);
        var source = press.SourceBounds;
        var x = source.Left + point.X - press.Anchor.X;
        var y = source.Top + point.Y - press.Anchor.Y;
        var target = press.Viewport.Contains(point) && press.WindowBounds.Contains(point)
            ? press.Slots.Values
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
        if (press.Slots.TryGetValue(press.SourceIndex, out var origin))
            origin.Element.Opacity = target is not null ? origin.Opacity * 0.2 : origin.Opacity;
        if (target is not null)
        {
            Canvas.SetLeft(AlbumDropPlaceholder, target.Bounds.Left + press.SourceInset.X);
            Canvas.SetTop(AlbumDropPlaceholder, target.Bounds.Top + press.SourceInset.Y);
        }
        foreach (var slot in press.Slots.Values)
        {
            var shifted = destination < 0 ? slot.Index
                : slot.Index == press.SourceIndex ? destination
                : press.SourceIndex < slot.Index && slot.Index <= destination ? slot.Index - 1
                : destination <= slot.Index && slot.Index < press.SourceIndex ? slot.Index + 1
                : slot.Index;
            var next = shifted == slot.Index ? null : press.Slots.GetValueOrDefault(shifted);
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
        Root.ReleasePointerCapture(press.Pointer);
        if (press.Dragging)
        {
            albumDragScroll.Stop();
            albumDragScroll.Tick -= ScrollAlbumDrag;
            if (press.Scroll is not null)
                press.Scroll.ViewChanged -= AlbumDragViewChanged;
            press.Browser.SizeChanged -= AlbumDragSizeChanged;
            press.Browser.ContainerContentChanging -= AlbumDragContainerChanged;
        }
        RestoreAlbumDropSlots(press);
        AlbumDragAvatar.Visibility = AlbumDropPlaceholder.Visibility = Visibility.Collapsed;
        AlbumDragImage.Source = null;
    }

    private static void RestoreAlbumDropSlots(AlbumPress press)
    {
        foreach (var slot in press.Slots.Values)
            slot.Element.RenderTransform = slot.Transform;
        if (press.Slots.TryGetValue(press.SourceIndex, out var origin))
            origin.Element.Opacity = origin.Opacity;
    }

    private void SaveAlbumOrder(long album, AlbumPress press, int target)
    {
        var tile = press.Tile;
        var source = press.SourceIndex;
        try
        {
            Database.MoveInAlbum(album, tile.Media.Id, target, press.ExpectedOrder!);
        }
        catch (AlbumOrderChangedException error)
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                Reload(Selection?.Media.Id);
                ShowNotice("无法调整顺序", error.Message);
            });
            return;
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("无法调整顺序", error.Message);
            return;
        }

        var members = albumMembers[album];
        members.RemoveAt(source);
        members.Insert(target, tile.Media);

        var displayedItems = tiles;
        // Retain the ItemsSource. WinUI can process individual removals and insertions after the release.
        DispatcherQueue.TryEnqueue(() =>
        {
            if (!ReferenceEquals(tiles, displayedItems))
                return;

            var browser = ActiveMediaBrowser;
            var selected = Selection;
            updatingBrowser = true;
            try
            {
                tiles.RemoveAt(source);
                tiles.Insert(target, tile);
                for (var i = Math.Min(source, target); i <= Math.Max(source, target); i++)
                    tiles[i].SetRowIndex(i);
                if (SelectingAlbumMembers)
                    RestoreAlbumRemovalSelection(browser);
                else
                    browser.SelectedItem = selected;
            }
            finally
            {
                updatingBrowser = false;
            }
            UpdateSelection();
            UpdateFilmstripPreview(SelectingAlbumMembers ? tile : null);
            if (SelectingAlbumMembers)
                FocusAlbumSelectionItem(tile.Media.Id);
        });
    }
}
