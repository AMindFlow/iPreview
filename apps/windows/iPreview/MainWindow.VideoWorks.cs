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

    private sealed class VideoWorkSession(IndexedVideoWork work, IReadOnlyList<WorkGroup> groups)
    {
        public IndexedVideoWork Work { get; } = work;
        public IReadOnlyList<WorkGroup> Groups { get; } = groups;
        public int OverviewIndex { get; set; }
        public int OpeningGroup { get; set; }
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
    private bool workVideoActive;

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
        var session = new VideoWorkSession(work, groups);
        videoWorkSession = session;
        VideoWorkTitle.Text = work.Title;
        VideoWorkTapeCover.DataContext = new Tile(work.Video, 0);
        VideoWorkItems.ItemsSource = groups;
        LibraryView.IsHitTestVisible = false;
        LibraryHost.IsEnabled = false;
        VideoWorkOverlay.Visibility = Visibility.Visible;
        SelectVideoWorkItem(0, FocusState.Programmatic);
    }

    private void SelectVideoWorkItem(int index, FocusState focus)
    {
        if (index == 0)
        {
            VideoWorkTape.Focus(focus);
            return;
        }
        VideoWorkItems.SelectedIndex = index - 1;
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
        CancelWorkOpening();
        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        VideoWorkTapeCover.DataContext = null;
        VideoWorkItems.ItemsSource = null;
        LibraryHost.IsEnabled = true;
        LibraryView.IsHitTestVisible = true;
        if (browsingFolders)
            FocusBrowserItem(SourceFolders, SourceFolders.SelectedItem, FocusState.Programmatic);
        else
            FocusSelectedMedia();
    }

    private void VideoWorkTapeClicked(object sender, RoutedEventArgs args) => BeginVideoWork(0);

    private void VideoWorkItemClicked(object sender, ItemClickEventArgs args)
    {
        if (workOpeningVisuals is not null)
            return;
        var index = VideoWorkItems.Items.IndexOf(args.ClickedItem);
        if (index >= 0)
            SelectVideoWorkItem(index + 1, FocusState.Pointer);
    }

    private void BeginVideoWork(int index)
    {
        if (videoWorkSession is not { Browsing: false } session || workOpeningVisuals is not null)
            return;
        session.OverviewIndex = index;
        session.OpeningGroup = Math.Max(0, VideoWorkItems.SelectedIndex);
        AnimateWorkOpening(session, () => EnterVideoWork(session));
    }

    private void EnterVideoWork(VideoWorkSession session)
    {
        var group = session.OpeningGroup;
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

        var poster = VideoWorkTapeCover.Source as BitmapImage;
        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        OpenPreview([new Tile(session.Work.Video, 0)], 0, new(BrowseMode.Icons, 1), poster);
        SetActiveWorkPane(video: true);
        AnimateWorkArrival(PreviewStage, .55f);
        ShowWorkPhotoGroup(session, opening: true);
    }

    private void VideoWorkKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
            {
                if (workOpeningVisuals is not null && videoWorkSession is { } opening)
                {
                    CancelWorkOpening();
                    SelectVideoWorkItem(opening.OverviewIndex, FocusState.Programmatic);
                }
                else
                    BackFromVideoWork();
            }
            return;
        }

        if (workOpeningVisuals is not null)
        {
            args.Handled = true;
            return;
        }
        var focused = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
        var onTape = ReferenceEquals(focused, VideoWorkTape);
        if (!onTape && !IsWithin(focused, VideoWorkItems))
            return;
        var index = onTape ? -1 : Math.Max(0, VideoWorkItems.SelectedIndex);
        if (args.Key == VirtualKey.Space)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                BeginVideoWork(index + 1);
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
        if (onTape && arrow == BrowseDirection.Right && VideoWorkItems.Items.Count != 0)
            SelectVideoWorkItem(1, FocusState.Keyboard);
        else if (!onTape)
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

    private void WorkPanePointerPressed(object sender, PointerRoutedEventArgs args) =>
        ActivateWorkPaneAt(args.OriginalSource as DependencyObject);

    private void WorkPaneGotFocus(object sender, RoutedEventArgs args) =>
        ActivateWorkPaneAt(FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject);

    private void ActivateWorkPaneAt(DependencyObject? element)
    {
        if (!BrowsingVideoWork)
            return;
        if (IsWithin(element, WorkVideoPane))
            SetActiveWorkPane(video: true);
        else if (IsWithin(element, WorkPhotoPane))
            SetActiveWorkPane(video: false);
    }

    private void SetActiveWorkPane(bool video)
    {
        workVideoActive = video;
        WorkVideoAura.Visibility = video ? Visibility.Visible : Visibility.Collapsed;
        WorkPhotoAura.Visibility = video ? Visibility.Collapsed : Visibility.Visible;
        StartWorkAura();
    }

    private void FocusWorkVideo(object sender, PointerRoutedEventArgs args)
    {
        if (BrowsingVideoWork)
            PreviewCanvas.Focus(FocusState.Pointer);
    }

    private void WorkWorkspaceKeyDown(KeyRoutedEventArgs args)
    {
        var focus = FocusManager.GetFocusedElement(Root.XamlRoot);
        if (WorkPhotoGroupPicker.IsDropDownOpen || focus is MenuFlyoutItemBase)
            return;

        if (args.Key is VirtualKey.Escape or VirtualKey.Tab)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
            {
                if (args.Key == VirtualKey.Escape)
                    ClosePreview();
                else
                {
                    SetActiveWorkPane(video: !workVideoActive);
                    (workVideoActive ? PreviewCanvas : WorkPhotoCanvas).Focus(FocusState.Keyboard);
                }
            }
            return;
        }
        if (previewClosing || previewIndex < 0)
            return;

        if (!workVideoActive)
        {
            if (ReferenceEquals(focus, WorkPhotoGroupPicker) || !IsWithin(focus as DependencyObject, WorkPhotoPane))
                return;
            if (args.Key is VirtualKey.Left or VirtualKey.Right)
            {
                args.Handled = true;
                MoveWorkPhoto(args.Key == VirtualKey.Left ? -1 : 1);
            }
            else if (ReferenceEquals(focus, WorkPhotoCanvas) && args.Key is VirtualKey.Up or VirtualKey.Down)
            {
                args.Handled = true;
                (args.Key == VirtualKey.Up ? (Control)WorkPhotoGroupPicker : WorkPhotoSortButton).Focus(FocusState.Keyboard);
            }
            return;
        }

        var onCanvas = ReferenceEquals(focus, PreviewCanvas);
        var onTimeline = ReferenceEquals(focus, Timeline);
        if (!onCanvas && !onTimeline)
            return;
        switch (args.Key)
        {
            case VirtualKey.Space:
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    ToggleVideo();
                break;
            case VirtualKey.Enter when VideoControls.Visibility == Visibility.Visible:
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    SetPreviewVideoLock(!previewVideoLocked);
                break;
            case VirtualKey.Left or VirtualKey.Right when previewVideoLocked:
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    SeekVideoBy(args.Key == VirtualKey.Left ? -VideoSeekInterval : VideoSeekInterval);
                break;
            case VirtualKey.Down when onCanvas && Timeline.IsEnabled:
                args.Handled = true;
                Timeline.Focus(FocusState.Keyboard);
                break;
        }
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

    private void ShowWorkPhotoGroup(VideoWorkSession session, bool opening = false)
    {
        session.Photos = session.Groups[session.PhotoGroup].Items;
        session.PhotoIndex = 0;
        WorkPhotoSortButton.IsEnabled = session.Photos.Count > 1;
        LoadWorkPhoto(session, opening);
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

    private async void LoadWorkPhoto(VideoWorkSession session, bool opening = false)
    {
        ResetWorkArrival(WorkPhotoImage);
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
            {
                WorkPhotoImage.Source = image;
                if (opening)
                    AnimateWorkArrival(WorkPhotoImage, .70f);
            }
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
        var browsing = BrowsingVideoWork;
        PreviewWorkspace.ColumnSpacing = browsing ? 12 : 0;
        WorkPhotoColumn.Width = new(browsing ? 1 : 0, GridUnitType.Star);

        var compact = browsing && width > 0 && width < 910;
        VideoControlBar.ColumnSpacing = compact ? 2 : 7;
        VideoControlBar.Padding = compact ? new Thickness(4, 3, 4, 3) : new Thickness(10, 3, 10, 3);
        VideoBack.MinWidth = VideoForward.MinWidth = PlayPause.MinWidth = compact ? 32 : 44;
        Grid.SetRow(TimeLabel, compact ? 1 : 0);
        Grid.SetColumn(TimeLabel, compact ? 0 : 3);
        Grid.SetRow(Timeline, compact ? 1 : 0);
        Grid.SetColumn(Timeline, compact ? 1 : 4);
        Grid.SetColumnSpan(Timeline, compact ? 5 : 1);
        Grid.SetRow(DurationLabel, compact ? 1 : 0);
        Grid.SetColumn(DurationLabel, compact ? 6 : 5);
    }

    private void VideoWorkBooksSizeChanged(object sender, SizeChangedEventArgs args)
    {
        if (VideoWorkItems.ItemsPanelRoot is ItemsWrapGrid books && args.NewSize.Width > 10)
            books.ItemWidth = Math.Min(157, args.NewSize.Width - 6);
    }

    private bool RestoreVideoWorkAfterMediaPreview()
    {
        if (videoWorkSession is not { Browsing: true } session)
            return false;
        session.CancelPhotoTasks();
        ResetWorkArrival(WorkPhotoImage);
        ResetWorkArrival(PreviewStage);
        StopWorkAura();
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
