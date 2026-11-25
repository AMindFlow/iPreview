using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record WorkGroup(string Title, Tile Cover, IReadOnlyList<Media> Items);

    private sealed class VideoWorkSession(IndexedVideoWork work, IReadOnlyList<WorkGroup> groups, Control? entry)
    {
        public IndexedVideoWork Work { get; } = work;
        public IReadOnlyList<WorkGroup> Groups { get; } = groups;
        public Control? Entry { get; } = entry;
        public int OverviewIndex { get; set; }
        public int PhotoGroup { get; set; } = -1;
        public bool Browsing => PhotoGroup >= 0;
        public IReadOnlyList<Media> Photos { get; set; } = [];
        public int PhotoIndex { get; set; }
        public int PhotoGeneration { get; set; }
        public CancellationTokenSource? PhotoRequest { get; set; }
        public MediaSortSession Sort { get; } = new();

        public void CancelPhotoTasks()
        {
            Sort.Cancel();
            PhotoGeneration++;
            PhotoRequest?.Cancel();
        }
    }

    private List<IndexedVideoWork> videoWorks = [];
    private VideoWorkSession? videoWorkSession;
    private bool BrowsingVideoWork => videoWorkSession?.Browsing == true;

    private IndexedVideoWork? WorkAt(Navigation location) => videoWorks.Find(work =>
        work.Video.Source.Id == location.Source && work.RelativePath == (location.Folder?.TrimEnd('/') ?? ""));

    private void PreviewCurrentWork(object sender, RoutedEventArgs args)
    {
        if (WorkAt(current) is { } work)
            OpenVideoWork(work);
    }

    private void OpenVideoWork(IndexedVideoWork work)
    {
        if (busy)
            return;
        List<WorkGroup> groups = [];
        if (work.Samples.Count != 0)
            groups.Add(new("官方样张", new Tile(work.Samples[0], 0), work.Samples));
        groups.AddRange(work.PhotoSets.Select(book =>
            new WorkGroup(book.Title, new Tile(book.Cover ?? book.Photos[0], 0), book.Photos)));
        var session = new VideoWorkSession(work, groups, FocusManager.GetFocusedElement(Root.XamlRoot) as Control);
        videoWorkSession = session;
        VideoWorkTitle.Text = work.Title;
        VideoWorkDiscCover.DataContext = new Tile(work.Video, 0);
        VideoWorkItems.ItemsSource = groups;
        LibraryView.IsHitTestVisible = false;
        LibraryHost.IsEnabled = false;
        VideoWorkOverlay.Visibility = Visibility.Visible;
        SelectVideoWorkItem(0, FocusState.Programmatic);
    }

    private void SelectVideoWorkItem(int index, FocusState focus)
    {
        VideoWorkItems.SelectedIndex = index - 1;
        if (index == 0)
        {
            VideoWorkDisc.IsChecked = true;
            VideoWorkDisc.Focus(focus);
        }
        else
            FocusBrowserItem(VideoWorkItems, VideoWorkItems.SelectedItem, focus);
    }

    private void BackFromVideoWork(object sender, RoutedEventArgs args) => BackFromVideoWork();

    private void BackFromVideoWork()
    {
        if (videoWorkSession is not { } session)
            return;
        if (session.Browsing)
            ClosePreview();
        videoWorkSession = null;
        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        VideoWorkDiscCover.DataContext = null;
        VideoWorkItems.ItemsSource = null;
        LibraryHost.IsEnabled = true;
        LibraryView.IsHitTestVisible = true;
        if (session.Entry?.Focus(FocusState.Programmatic) == true)
            return;
        if (browsingFolders)
            FocusSourceFolder();
        else
            FocusSelectedMedia();
    }

    private void VideoWorkDiscClicked(object sender, RoutedEventArgs args) => EnterVideoWork(0);

    private void VideoWorkSelectionChanged(object sender, SelectionChangedEventArgs args) =>
        VideoWorkDisc.IsChecked = VideoWorkItems.SelectedIndex < 0;

    private void VideoWorkItemClicked(object sender, ItemClickEventArgs args)
    {
        var index = VideoWorkItems.Items.IndexOf(args.ClickedItem);
        if (index >= 0)
            EnterVideoWork(index + 1);
    }

    private void EnterVideoWork(int index)
    {
        if (videoWorkSession is not { Browsing: false } session)
            return;
        session.OverviewIndex = index;
        var group = Math.Max(0, index - 1);
        session.Sort.Order = default;
        WorkPhotoGroupPicker.ItemsSource = session.Groups.Select(item => item.Title).ToArray();
        WorkPhotoGroupPicker.SelectedIndex = group;
        session.PhotoGroup = group;
        MediaSortMenu.Attach(WorkPhotoSortButton, () => session.Sort.Order, async order =>
        {
            if (session.Sort.Order == order)
                return;
            session.Sort.Order = order;
            await ArrangeWorkPhotos(session);
        });
        WorkPhotoPane.Visibility = Visibility.Visible;
        LayoutWorkPhotoPane(PreviewWorkspace.ActualWidth);

        var poster = VideoWorkDiscCover.Source as BitmapImage;
        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        OpenPreview([new Tile(session.Work.Video, 0)], 0, new(BrowseMode.Icons, 1), poster, startVideo: index == 0);
        ShowWorkPhotoGroup(session);
    }

    private void VideoWorkKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                BackFromVideoWork();
            return;
        }

        var focused = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
        var onDisc = ReferenceEquals(focused, VideoWorkDisc);
        if (!onDisc && !IsWithin(focused, VideoWorkItems))
            return;
        var index = onDisc ? -1 : Math.Max(0, VideoWorkItems.SelectedIndex);
        if (!onDisc && args.Key == VirtualKey.Space)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                EnterVideoWork(index + 1);
            return;
        }

        BrowseDirection? direction = args.Key switch
        {
            VirtualKey.Left => BrowseDirection.Left,
            VirtualKey.Right => BrowseDirection.Right,
            VirtualKey.Up => BrowseDirection.Up,
            VirtualKey.Down => BrowseDirection.Down,
            _ => null
        };
        if (direction is not { } arrow)
            return;
        args.Handled = true;
        if (onDisc && arrow == BrowseDirection.Right && VideoWorkItems.Items.Count != 0)
            SelectVideoWorkItem(1, FocusState.Keyboard);
        else if (!onDisc)
        {
            var layout = new BrowseLayout(BrowseMode.Icons, GridColumns(VideoWorkItems));
            if (layout.NeighborOf(index, VideoWorkItems.Items.Count, arrow) is int next)
                SelectVideoWorkItem(next + 1, FocusState.Keyboard);
            else if (arrow == BrowseDirection.Left)
                SelectVideoWorkItem(0, FocusState.Keyboard);
        }
    }

    private static bool IsWithin(DependencyObject? element, DependencyObject ancestor)
    {
        for (; element is not null; element = VisualTreeHelper.GetParent(element))
            if (ReferenceEquals(element, ancestor))
                return true;
        return false;
    }

    private void WorkPhotoGroupChanged(object sender, SelectionChangedEventArgs args)
    {
        var index = WorkPhotoGroupPicker.SelectedIndex;
        if (videoWorkSession is not { Browsing: true } session || index < 0 || index == session.PhotoGroup)
            return;
        session.PhotoGroup = index;
        ShowWorkPhotoGroup(session);
        _ = ArrangeWorkPhotos(session);
    }

    private void ShowWorkPhotoGroup(VideoWorkSession session)
    {
        session.Photos = session.Groups[session.PhotoGroup].Items;
        session.PhotoIndex = 0;
        WorkPhotoSortButton.IsEnabled = session.Photos.Count > 1;
        LoadWorkPhoto(session);
    }

    private async Task ArrangeWorkPhotos(VideoWorkSession session)
    {
        if (!ReferenceEquals(session, videoWorkSession) || !session.Browsing)
            return;
        var group = session.PhotoGroup;
        var arranged = await session.Sort.ArrangeAsync(session.Groups[group].Items, media => media);
        if (arranged is null || !ReferenceEquals(session, videoWorkSession) || session.PhotoGroup != group)
            return;

        var selected = session.Photos[session.PhotoIndex].Id;
        session.Photos = arranged;
        session.PhotoIndex = arranged.FindIndex(photo => photo.Id == selected);
        UpdateWorkPhotoNavigation(session);
    }

    private void WorkPhotoPreviousClicked(object sender, RoutedEventArgs args) => MoveWorkPhoto(-1);
    private void WorkPhotoNextClicked(object sender, RoutedEventArgs args) => MoveWorkPhoto(1);
    private void FocusWorkPhoto(object sender, PointerRoutedEventArgs args) => WorkPhotoCanvas.Focus(FocusState.Pointer);

    private void MoveWorkPhoto(int offset)
    {
        if (videoWorkSession is not { Browsing: true } session)
            return;
        var index = session.PhotoIndex + offset;
        if (index < 0 || index >= session.Photos.Count)
            return;
        session.PhotoIndex = index;
        LoadWorkPhoto(session);
    }

    private void UpdateWorkPhotoNavigation(VideoWorkSession session)
    {
        WorkPhotoPrevious.IsEnabled = session.PhotoIndex > 0;
        WorkPhotoNext.IsEnabled = session.PhotoIndex < session.Photos.Count - 1;
        WorkPhotoName.Text = session.Photos[session.PhotoIndex].FileName;
        WorkPhotoCount.Text = $"{session.PhotoIndex + 1} / {session.Photos.Count}";
    }

    private async void LoadWorkPhoto(VideoWorkSession session)
    {
        UpdateWorkPhotoNavigation(session);
        WorkPhotoImage.Source = null;
        WorkPhotoError.Visibility = Visibility.Collapsed;
        var generation = ++session.PhotoGeneration;
        session.PhotoRequest?.Cancel();
        using var request = new CancellationTokenSource();
        session.PhotoRequest = request;
        try
        {
            var image = await DecodeImage(session.Photos[session.PhotoIndex], 0, true,
                (_, error) => ShowWorkPhotoError(session, generation, error.ErrorMessage), request.Token);
            if (CanUpdateWorkPhoto(session, generation) && WorkPhotoError.Visibility == Visibility.Collapsed)
                WorkPhotoImage.Source = image;
        }
        catch (OperationCanceledException) when (request.IsCancellationRequested) { }
        catch (Exception error) when (MediaFailure(error))
        {
            ShowWorkPhotoError(session, generation, error.Message);
        }
        finally
        {
            if (ReferenceEquals(session.PhotoRequest, request))
                session.PhotoRequest = null;
        }
    }

    private bool CanUpdateWorkPhoto(VideoWorkSession session, int generation) =>
        ReferenceEquals(session, videoWorkSession) && session.Browsing && session.PhotoGeneration == generation;

    private void ShowWorkPhotoError(VideoWorkSession session, int generation, string detail)
    {
        if (!CanUpdateWorkPhoto(session, generation))
            return;
        WorkPhotoImage.Source = null;
        WorkPhotoError.Text = string.IsNullOrWhiteSpace(detail) ? "无法解码此图片。" : $"无法解码此图片。\n{detail}";
        WorkPhotoError.Visibility = Visibility.Visible;
    }

    private void PreviewWorkspaceSizeChanged(object sender, SizeChangedEventArgs args) =>
        LayoutWorkPhotoPane(args.NewSize.Width);

    private void LayoutWorkPhotoPane(double width)
    {
        var stacked = BrowsingVideoWork && width > 0 && width < 790;
        PreviewWorkspace.ColumnSpacing = BrowsingVideoWork && !stacked ? 12 : 0;
        PreviewWorkspace.RowSpacing = stacked ? 10 : 0;
        WorkPhotoColumn.Width = new(BrowsingVideoWork && !stacked ? 1 : 0, GridUnitType.Star);
        WorkPhotoRow.Height = new(stacked ? 1 : 0, GridUnitType.Star);
        Grid.SetColumn(WorkPhotoPane, stacked ? 0 : 1);
        Grid.SetRow(WorkPhotoPane, stacked ? 1 : 0);
    }

    private bool RestoreVideoWorkAfterMediaPreview()
    {
        if (videoWorkSession is not { Browsing: true } session)
            return false;
        session.CancelPhotoTasks();
        session.PhotoGroup = -1;
        session.Photos = [];
        WorkPhotoPane.Visibility = Visibility.Collapsed;
        WorkPhotoImage.Source = null;
        WorkPhotoGroupPicker.ItemsSource = null;
        WorkPhotoSortButton.Flyout = null;
        LayoutWorkPhotoPane(PreviewWorkspace.ActualWidth);
        VideoWorkOverlay.Visibility = Visibility.Visible;
        SelectVideoWorkItem(session.OverviewIndex, FocusState.Programmatic);
        return true;
    }
}
