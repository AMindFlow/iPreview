using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record WorkGroup(string Title, string Glyph, Tile Cover, IReadOnlyList<Media> Items);
    private sealed record WorkRow(string Title, string Glyph, Tile Cover);

    private sealed class VideoWorkSession(IndexedVideoWork work, IReadOnlyList<WorkGroup> groups, Control? entry)
    {
        public IndexedVideoWork Work { get; } = work;
        public IReadOnlyList<WorkGroup> Groups { get; } = groups;
        public Control? Entry { get; } = entry;
        public int GroupIndex { get; set; }
        public bool InsideGroup { get; set; }
        public List<Tile> Files { get; set; } = [];
        public MediaSortSession Sort { get; } = new();
        public WorkGroup Group => Groups[GroupIndex];
    }

    private List<IndexedVideoWork> videoWorks = [];
    private VideoWorkSession? videoWorkSession;

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
        List<WorkGroup> groups =
        [
            new("影碟", "\uEC4F", new Tile(work.Video, 0), [work.Video]),
            new("官方样张", "\uE91B", new Tile(work.Samples[0], 0), work.Samples)
        ];
        groups.AddRange(work.PhotoSets.Select(book =>
            new WorkGroup(book.Title, "\uE82D", new Tile(book.Cover ?? book.Photos[0], 0), book.Photos)));
        var session = new VideoWorkSession(work, groups, FocusManager.GetFocusedElement(Root.XamlRoot) as Control);
        videoWorkSession = session;
        MediaSortMenu.Attach(VideoWorkSortButton, () => session.Sort.Order, async order =>
        {
            session.Sort.Order = order;
            var selected = (VideoWorkItems.SelectedItem as WorkRow)?.Cover.Media.Id;
            await ArrangeVideoWorkFiles(session, selected);
        });
        LibraryView.IsHitTestVisible = false;
        LibraryHost.IsEnabled = false;
        VideoWorkOverlay.Visibility = Visibility.Visible;
        ShowVideoWorkLevel(session, 0);
    }

    private void ShowVideoWorkLevel(VideoWorkSession session, int selectedIndex)
    {
        VideoWorkSortButton.Visibility = session.InsideGroup ? Visibility.Visible : Visibility.Collapsed;
        VideoWorkTitle.Text = session.InsideGroup ? session.Group.Title : session.Work.Title;
        var back = session.InsideGroup ? "返回作品" : "退出作品预览";
        AutomationProperties.SetName(VideoWorkBack, back);
        ToolTipService.SetToolTip(VideoWorkBack, back + "（Esc）");
        VideoWorkBackIcon.Glyph = session.InsideGroup ? "\uE72B" : "\uE711";
        VideoWorkItems.ItemsSource = session.InsideGroup
            ? session.Files.Select(tile => new WorkRow(tile.FileName, tile.Media.IsVideo ? "\uE768" : "\uE91B", tile)).ToList()
            : session.Groups.Select(group => new WorkRow(group.Title, group.Glyph, group.Cover)).ToList();
        SelectVideoWorkItem(selectedIndex, FocusState.Programmatic);
    }

    private void SelectVideoWorkItem(int index, FocusState focus)
    {
        VideoWorkItems.SelectedIndex = index;
        FocusBrowserItem(VideoWorkItems, VideoWorkItems.SelectedItem, focus);
    }

    private void BackFromVideoWork(object sender, RoutedEventArgs args) => BackFromVideoWork();

    private void BackFromVideoWork()
    {
        if (videoWorkSession is not { } session)
            return;
        session.Sort.Cancel();
        if (session.InsideGroup)
        {
            session.InsideGroup = false;
            ShowVideoWorkLevel(session, session.GroupIndex);
            return;
        }
        videoWorkSession = null;
        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        VideoWorkItems.ItemsSource = null;
        VideoWorkSortButton.Flyout = null;
        LibraryHost.IsEnabled = true;
        LibraryView.IsHitTestVisible = true;
        if (session.Entry?.Focus(FocusState.Programmatic) == true)
            return;
        if (browsingFolders)
            FocusSourceFolder();
        else
            FocusSelectedMedia();
    }

    private void VideoWorkItemClicked(object sender, ItemClickEventArgs args) =>
        EnterVideoWorkItem(VideoWorkItems.Items.IndexOf(args.ClickedItem));

    private async void EnterVideoWorkItem(int index)
    {
        if (videoWorkSession is not { } session || index < 0)
            return;
        if (session.InsideGroup)
        {
            session.Sort.Cancel();
            VideoWorkOverlay.IsHitTestVisible = false;
            VideoWorkOverlay.Visibility = Visibility.Collapsed;
            OpenPreview(session.Files, index, new BrowseLayout(BrowseMode.Gallery, 1));
        }
        else
        {
            session.GroupIndex = index;
            session.InsideGroup = true;
            session.Files = session.Group.Items.Select((media, position) => new Tile(media, position)).ToList();
            ShowVideoWorkLevel(session, 0);
            await ArrangeVideoWorkFiles(session, selected: null);
        }
    }

    private async Task ArrangeVideoWorkFiles(VideoWorkSession session, long? selected)
    {
        var arranged = await session.Sort.ArrangeAsync(session.Group.Items, item => item);
        if (arranged is null || !ReferenceEquals(session, videoWorkSession) || !session.InsideGroup)
            return;
        session.Files = arranged.Select((item, position) => new Tile(item, position)).ToList();
        var index = session.Files.FindIndex(tile => tile.Media.Id == selected);
        ShowVideoWorkLevel(session, Math.Max(0, index));
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

        if (FocusManager.GetFocusedElement(Root.XamlRoot) is Button || VideoWorkItems.Items.Count == 0)
            return;
        var index = Math.Max(0, VideoWorkItems.SelectedIndex);
        if (args.Key == VirtualKey.Space)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                EnterVideoWorkItem(index);
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
        if (direction is { } arrow)
        {
            args.Handled = true;
            var layout = new BrowseLayout(BrowseMode.Icons, GridColumns(VideoWorkItems));
            if (layout.NeighborOf(index, VideoWorkItems.Items.Count, arrow) is int next)
                SelectVideoWorkItem(next, FocusState.Keyboard);
        }
    }

    private bool RestoreVideoWorkAfterMediaPreview(long? mediaId)
    {
        if (videoWorkSession is not { } session)
            return false;
        VideoWorkOverlay.Visibility = Visibility.Visible;
        VideoWorkOverlay.IsHitTestVisible = true;
        var index = session.Files.FindIndex(tile => tile.Media.Id == mediaId);
        SelectVideoWorkItem(Math.Max(0, index), FocusState.Programmatic);
        return true;
    }
}
