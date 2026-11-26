using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record WorkGroup(string Title, IReadOnlyList<Media> Items);

    private sealed class VideoWorkSession(IndexedVideoWork work, IReadOnlyList<WorkGroup> groups)
    {
        public IndexedVideoWork Work { get; } = work;
        public IReadOnlyList<WorkGroup> Groups { get; } = groups;
        public BitmapImage? VideoPoster { get; set; }
        private readonly int[] overviewPhotoPositions = new int[groups.Count];
        public bool OpeningFromPile { get; set; }
        public int OverviewGroup { get; set; }
        public int OverviewPhotoIndex
        {
            get => overviewPhotoPositions[OverviewGroup];
            set => overviewPhotoPositions[OverviewGroup] = value;
        }
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

    private const double WorkTapeWidth = 196;
    private const double WorkTapeHeight = 332;
    private const double WorkPileWidth = 224;
    private const double WorkPileHeight = 252;

    private List<IndexedVideoWork> videoWorks = [];
    private VideoWorkSession? videoWorkSession;
    private CancellationTokenSource? workTapeCoverRequest;
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
            groups.Add(new("官方样张", work.Samples));
        groups.AddRange(work.PhotoSets.Select(book =>
            new WorkGroup(book.Title, book.Photos)));
        var session = new VideoWorkSession(work, groups);
        videoWorkSession = session;
        VideoWorkTitle.Text = work.Title;
        var fileName = work.Video.FileName;
        VideoWorkTapeCaption.Text = fileName;
        ToolTipService.SetToolTip(VideoWorkTapeCaption, fileName);
        AutomationProperties.SetName(VideoWorkTape, fileName);
        _ = LoadWorkTapeCover(session);
        VideoWorkSingleGroup.Visibility = groups.Count == 1 ? Visibility.Visible : Visibility.Collapsed;
        VideoWorkSingleGroup.Text = groups[0].Title;
        VideoWorkOverviewGroups.Visibility = groups.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        VideoWorkOverviewGroups.ItemsSource = groups.Select(group => group.Title).ToArray();
        VideoWorkOverviewGroups.SelectedIndex = 0;
        PresentWorkPhotoPile(session);
        LibraryView.IsHitTestVisible = false;
        LibraryHost.IsEnabled = false;
        VideoWorkOverlay.Visibility = Visibility.Visible;
        LayoutVideoWorkShowcase();
        FocusVideoWorkEntrance(session);
    }

    private void VideoWorkShowcaseSizeChanged(object sender, SizeChangedEventArgs args) => LayoutVideoWorkShowcase();

    private void LayoutVideoWorkShowcase()
    {
        var halfWidth = (VideoWorkShowcase.ActualWidth - VideoWorkShowcase.ColumnSpacing) / 2;
        var regionHeight = VideoWorkShowcase.ActualHeight;
        if (videoWorkSession is null || halfWidth <= 0 || regionHeight <= 0)
            return;

        var targetArea = .40 * halfWidth * regionHeight;
        var maxWidth = Math.Max(1, halfWidth - 40);
        // Both artwork slots sit between matching 28-point rows and 8-point gaps.
        var maxHeight = Math.Max(1, regionHeight - 88);
        var tapeScale = Math.Min(Math.Sqrt(targetArea / (WorkTapeWidth * WorkTapeHeight)),
            Math.Min(maxWidth / WorkTapeWidth, maxHeight / WorkTapeHeight));
        var pileScale = Math.Min(Math.Sqrt(targetArea / (200 * 238)),
            Math.Min(maxWidth / WorkPileWidth, maxHeight / WorkPileHeight));
        VideoWorkTapeArtwork.Width = WorkTapeWidth * tapeScale;
        VideoWorkTapeArtwork.Height = WorkTapeHeight * tapeScale;
        VideoWorkPileArtwork.Width = WorkPileWidth * pileScale;
        VideoWorkPileArtwork.Height = WorkPileHeight * pileScale;

        var innerSpace = (halfWidth - Math.Max(VideoWorkTapeArtwork.Width, VideoWorkPileArtwork.Width)) / 2;
        var inward = Math.Clamp(innerSpace - 16, 0, halfWidth * .075);
        VideoWorkTapeInward.X = inward;
        VideoWorkPileInward.X = -inward;
    }

    private void VideoWorkOverviewGroupChanged(object sender, SelectionChangedEventArgs args)
    {
        var index = VideoWorkOverviewGroups.SelectedIndex;
        if (videoWorkSession is not { Browsing: false } session || index < 0 || index == session.OverviewGroup)
            return;
        if (workOpeningVisuals is not null)
        {
            VideoWorkOverviewGroups.SelectedIndex = session.OverviewGroup;
            return;
        }
        CancelWorkPhotoPeel();
        ResetWorkPileWheel();
        session.OverviewGroup = index;
        PresentWorkPhotoPile(session);
    }

    private void FocusVideoWorkEntrance(VideoWorkSession session)
    {
        VideoWorkOverlay.UpdateLayout();
        var target = session.OpeningFromPile ? VideoWorkPhotoPile : VideoWorkTape;
        if (!target.Focus(FocusState.Programmatic))
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                var focus = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
                if (ReferenceEquals(videoWorkSession, session) && VideoWorkOverlay.Visibility == Visibility.Visible &&
                    !IsWithin(focus, VideoWorkOverlay))
                    target.Focus(FocusState.Programmatic);
            });
        }
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
        CancelWorkPhotoPeel();
        ResetWorkPileWheel();
        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        workTapeCoverRequest?.Cancel();
        SetWorkTapeCover(null);
        VideoWorkOverviewGroups.ItemsSource = null;
        workPhotoCards.Clear();
        VideoWorkPrints.Children.Clear();
        LibraryHost.IsEnabled = true;
        LibraryView.IsHitTestVisible = true;
        if (browsingFolders)
            FocusBrowserItem(SourceFolders, SourceFolders.SelectedItem, FocusState.Programmatic);
        else
            FocusSelectedMedia();
    }

    private void VideoWorkTapeClicked(object sender, RoutedEventArgs args) => BeginVideoWork(fromPile: false);
    private void VideoWorkPileClicked(object sender, RoutedEventArgs args) => BeginVideoWork(fromPile: true);

    private void BeginVideoWork(bool fromPile)
    {
        if (videoWorkSession is not { Browsing: false } session || workOpeningVisuals is not null)
            return;
        session.OpeningFromPile = fromPile;
        CancelWorkPhotoPeel();
        ResetWorkPileWheel();
        PresentWorkPhotoPile(session);
        AnimateWorkOpening(session, () => EnterVideoWork(session));
    }

    private void EnterVideoWork(VideoWorkSession session)
    {
        var group = session.OverviewGroup;
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

        VideoWorkOverlay.Visibility = Visibility.Collapsed;
        OpenPreview([new Tile(session.Work.Video, 0)], 0, new(BrowseMode.Icons, 1), session.VideoPoster);
        SetActiveWorkPane(video: true);
        AnimateWorkArrival(PreviewStage, .55f);
        ShowWorkPhotoGroup(session, opening: true);
    }

    private static IEnumerable<Media> WorkTapeCandidates(Media video, IEnumerable<Media> indexedMedia)
    {
        var parent = SourceRename.SplitPath(video.RelativePath).Parent;
        return indexedMedia.Where(item => item.Source.Id == video.Source.Id && item.Available && !item.IsVideo &&
            SourceRename.SplitPath(item.RelativePath).Parent == parent);
    }

    private static IEnumerable<Media> RankWorkTapeCovers(IEnumerable<(Media Media, uint Width, uint Height)> images) =>
        images.Where(image => image.Width > 0 && image.Height > 0)
            .OrderBy(image => Math.Abs(Math.Log((16d * image.Width) / (9d * image.Height))))
            .ThenByDescending(image => (ulong)image.Width * image.Height)
            .ThenBy(image => image.Media.FileName, MediaSearch.NaturalName)
            .ThenBy(image => image.Media.Id)
            .Select(image => image.Media);

    private void SetWorkTapeCover(ImageSource? source) =>
        VideoWorkTapeCover.ImageSource = VideoWorkTapeSpineCover.ImageSource = source;

    private async Task LoadWorkTapeCover(VideoWorkSession session)
    {
        workTapeCoverRequest?.Cancel();
        using var request = new CancellationTokenSource();
        workTapeCoverRequest = request;
        var cancellation = request.Token;
        var video = session.Work.Video;
        session.VideoPoster = ThumbnailOf(video.Id)?.Image;
        SetWorkTapeCover(session.VideoPoster);
        var posterTask = LoadWorkTapePoster(session, cancellation);
        try
        {
            List<(Media Media, uint Width, uint Height)> dimensions = [];
            foreach (var candidate in WorkTapeCandidates(video, media).ToArray())
            {
                try
                {
                    var file = await OpenMediaFile(candidate, cancellation);
                    using var stream = await file.OpenReadAsync().AsTask(cancellation);
                    var decoder = await BitmapDecoder.CreateAsync(stream).AsTask(cancellation);
                    dimensions.Add((candidate, decoder.OrientedPixelWidth, decoder.OrientedPixelHeight));
                }
                catch (Exception error) when (MediaFailure(error)) { }
            }
            foreach (var candidate in RankWorkTapeCovers(dimensions))
            {
                try
                {
                    var cover = await DecodeImage(candidate, 540, false, cancellationToken: cancellation);
                    if (ReferenceEquals(videoWorkSession, session) && !cancellation.IsCancellationRequested)
                        SetWorkTapeCover(cover);
                    break;
                }
                catch (Exception error) when (MediaFailure(error)) { }
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        finally
        {
            await posterTask;
            if (ReferenceEquals(workTapeCoverRequest, request))
                workTapeCoverRequest = null;
        }
    }

    private async Task LoadWorkTapePoster(VideoWorkSession session, CancellationToken cancellation)
    {
        if (session.VideoPoster is not null || !session.Work.Video.Available)
            return;
        try
        {
            var poster = await DecodeVideoThumbnail(session.Work.Video, cancellationToken: cancellation);
            if (!ReferenceEquals(videoWorkSession, session) || cancellation.IsCancellationRequested)
                return;
            session.VideoPoster = poster;
            if (VideoWorkTapeCover.ImageSource is null)
                SetWorkTapeCover(poster);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (Exception error) when (MediaFailure(error)) { }
    }

    private void VideoWorkRootKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (videoWorkSession is not { } session || args.Key is not (VirtualKey.Escape or VirtualKey.Tab) ||
            KeyIsDown(VirtualKey.Control) || KeyIsDown(VirtualKey.Menu) ||
            KeyIsDown(VirtualKey.LeftWindows) || KeyIsDown(VirtualKey.RightWindows) ||
            (args.Key == VirtualKey.Escape && KeyIsDown(VirtualKey.Shift)))
            return;
        var focus = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
        if (VideoWorkOverviewGroups.IsDropDownOpen || WorkPhotoGroupPicker.IsDropDownOpen ||
            focus is MenuFlyoutItemBase)
            return;

        args.Handled = true;
        if (args.KeyStatus.WasKeyDown)
            return;
        if (args.Key == VirtualKey.Escape)
        {
            if (session.Browsing)
                ClosePreview();
            else if (workOpeningVisuals is not null)
            {
                CancelWorkOpening();
                FocusVideoWorkEntrance(session);
            }
            else
                BackFromVideoWork();
            return;
        }

        if (session.Browsing)
        {
            SetActiveWorkPane(video: !workVideoActive);
            (workVideoActive ? PreviewCanvas : WorkPhotoCanvas).Focus(FocusState.Keyboard);
        }
        else if (workOpeningVisuals is null)
        {
            var onPhotos = IsWithin(focus, VideoWorkPhotoPile) || IsWithin(focus, VideoWorkOverviewGroups);
            (onPhotos ? VideoWorkTape : VideoWorkPhotoPile).Focus(FocusState.Keyboard);
        }
    }

    private void VideoWorkKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (VideoWorkOverviewGroups.IsDropDownOpen)
            return;

        if (workOpeningVisuals is not null)
        {
            args.Handled = true;
            return;
        }
        var focused = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
        var onTape = IsWithin(focused, VideoWorkTape);
        var onPile = IsWithin(focused, VideoWorkPhotoPile);
        if (!onTape && !onPile)
            return;

        if (args.Key is VirtualKey.Space or VirtualKey.Enter)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                BeginVideoWork(fromPile: onPile);
        }
        else if (onPile && args.Key is VirtualKey.Left or VirtualKey.Right)
        {
            args.Handled = true;
            MoveWorkPile(args.Key == VirtualKey.Left ? -1 : 1);
        }
        else if (onPile && args.Key == VirtualKey.Down && VideoWorkOverviewGroups.Visibility == Visibility.Visible)
        {
            args.Handled = true;
            VideoWorkOverviewGroups.Focus(FocusState.Keyboard);
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
        switch (args.Key)
        {
            case VirtualKey.Space when onCanvas || onTimeline:
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    ToggleVideo();
                break;
            case VirtualKey.Left or VirtualKey.Right when !onTimeline:
                args.Handled = true;
                if (Timeline.IsEnabled && !args.KeyStatus.WasKeyDown)
                    SeekVideoBy(args.Key == VirtualKey.Left ? -VideoSeekInterval : VideoSeekInterval);
                break;
            case VirtualKey.Down when onCanvas && Timeline.IsEnabled:
                args.Handled = true;
                Timeline.Focus(FocusState.Keyboard);
                break;
            case VirtualKey.Up when onTimeline:
                args.Handled = true;
                PreviewCanvas.Focus(FocusState.Keyboard);
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
        session.PhotoIndex = opening ? session.OverviewPhotoIndex : 0;
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
        Grid.SetColumnSpan(Timeline, compact ? 4 : 1);
        Grid.SetRow(VideoEndControls, compact ? 1 : 0);
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
        FocusVideoWorkEntrance(session);
        return true;
    }
}
