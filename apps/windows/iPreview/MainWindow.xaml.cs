using System.Collections.ObjectModel;
using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.FileProperties;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow : Window
{
    private sealed record Navigation(string Label, long? Source = null, string? Folder = null,
        long? Album = null, string Glyph = "\uE8B7")
    {
        public override string ToString() => Label;
    }

    private sealed record NavigationHeading(string Label, string Glyph);

    private static readonly Navigation Library = new("媒体库", Glyph: "\uE8B9");
    private Catalog? catalog;
    private Navigation current = Library;
    private Dictionary<long, Source> sources = [];
    private List<Media> media = [];
    private List<Album> albums = [];
    private Dictionary<long, List<Media>> albumMembers = [];
    private ObservableCollection<Tile> tiles = [];
    private bool searching;
    private bool busy;
    private int previewIndex = -1;
    private long? initialSelection;
    private List<Tile> previewTiles = [];
    private BrowseLayout previewLayout;
    private int previewGeneration;
    private bool previewVideoLocked;
    private MediaPlayer? player;
    private MediaSource? videoSource;
    private readonly DispatcherTimer playbackClock = new() { Interval = TimeSpan.FromMilliseconds(200) };
    private bool settingPosition;

    public MainWindow()
    {
        InitializeComponent();
        SystemBackdrop = new MicaBackdrop();
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 760));
        Root.Loaded += OpenCatalog;
        Root.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler(CommitTitleOnOutsideClick), true);
        playbackClock.Tick += (_, _) => UpdateTime();
        Closed += (_, _) =>
        {
            CancelAlbumAdjustmentPointer();
            previewGeneration++;
            filmstripGeneration++;
            StopVideo();
            catalog?.Dispose();
        };
    }

    private Catalog Database => catalog ?? throw new InvalidOperationException("媒体库尚未打开。");
    private Tile? Selection => ActiveMediaBrowser.SelectedItem as Tile;

    private void OpenCatalog(object sender, RoutedEventArgs args)
    {
        Root.Loaded -= OpenCatalog;
        try
        {
            var dataDirectory = Environment.GetEnvironmentVariable("IPREVIEW_DATA_DIR");
            dataDirectory ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "iPreview");
            catalog = new Catalog(dataDirectory);
            Reload();
            if (catalog.RenameRecoveryNotice is { } warning)
                ShowNotice("有待恢复的重命名", warning, InfoBarSeverity.Warning);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            ShowNotice("无法打开媒体库", error.Message);
            ImportButton.IsEnabled = false;
            CreateAlbumButton.IsEnabled = false;
            Rescan.IsEnabled = false;
        }
    }

    private void Reload(long? selected = null)
    {
        var expanded = ExpandedSources(NavTree.RootNodes);
        var snapshot = Database.Read();
        sources = snapshot.Sources;
        media = snapshot.Media;
        albums = snapshot.Albums;
        albumMembers = snapshot.AlbumMembers;

        NavTree.RootNodes.Clear();
        if (sources.Count > 0)
        {
            var sourcesNode = new TreeViewNode { Content = new NavigationHeading("来源", "\uE8B7"), IsExpanded = true };
            foreach (var source in sources.Values.OrderBy(source => source.Name).ThenBy(source => source.Id))
            {
                var label = source.Available ? source.Name : $"{source.Name}（离线）";
                var glyph = source.Layout switch
                {
                    Layout.MultiCreator => "\uE902",
                    Layout.Creator => "\uE77B",
                    _ => "\uE8B7"
                };
                var node = new TreeViewNode
                {
                    Content = new Navigation(label, Source: source.Id, Glyph: glyph),
                    IsExpanded = expanded.Contains(source.Id)
                };
                AddFolders(node, source.Id, media.Where(item => item.Source.Id == source.Id && item.Present));
                sourcesNode.Children.Add(node);
            }
            NavTree.RootNodes.Add(sourcesNode);
        }

        if (albums.Count > 0)
        {
            var albumsNode = new TreeViewNode { Content = new NavigationHeading("虚拟专辑", "\uE7B8"), IsExpanded = true };
            foreach (var album in albums)
                albumsNode.Children.Add(new TreeViewNode { Content = new Navigation(album.Name, Album: album.Id, Glyph: "\uE7B8") });
            NavTree.RootNodes.Add(albumsNode);
        }

        if (current.Album is long albumId)
            current = new(albums.Single(album => album.Id == albumId).Name, Album: albumId);
        NavTree.SelectedNode = FindNavigationNode(NavTree.RootNodes, current);
        ShowItems(selected);
    }

    private static TreeViewNode? FindNavigationNode(IEnumerable<TreeViewNode> nodes, Navigation target)
    {
        foreach (var node in nodes)
        {
            if (node.Content is Navigation entry && entry.Source == target.Source &&
                entry.Folder == target.Folder && entry.Album == target.Album)
                return node;
            if (FindNavigationNode(node.Children, target) is { } match)
                return match;
        }
        return null;
    }

    private static HashSet<long> ExpandedSources(IEnumerable<TreeViewNode> roots) =>
        roots.SelectMany(root => root.Children)
            .Where(node => node.IsExpanded && node.Content is Navigation { Source: not null })
            .Select(node => ((Navigation)node.Content).Source!.Value).ToHashSet();

    private static void AddFolders(TreeViewNode node, long source, IEnumerable<Media> items)
    {
        var known = new Dictionary<string, TreeViewNode>(StringComparer.Ordinal);
        foreach (var item in MediaSearch.ByPath(items))
        {
            var labels = item.RelativePath.Split('/');
            var parent = node;
            var prefix = "";
            for (var index = 0; index < labels.Length - 1; index++)
            {
                prefix += labels[index] + "/";
                if (!known.TryGetValue(prefix, out var child))
                {
                    child = new TreeViewNode { Content = new Navigation(labels[index], source, prefix) };
                    known.Add(prefix, child);
                    parent.Children.Add(child);
                }
                parent = child;
            }
        }
    }

    private void Navigate(TreeView sender, TreeViewItemInvokedEventArgs args)
    {
        var content = args.InvokedItem is TreeViewNode node ? node.Content : args.InvokedItem;
        if (content is Navigation target)
        {
            NavigateTo(target);
            if (browsingFolders)
                FocusSourceFolder();
        }
    }

    private void NavigateTo(Navigation target, long? selectedMedia = null)
    {
        current = target;
        searching = false;
        Query.Text = "";
        Notice.IsOpen = false;
        NavTree.SelectedNode = FindNavigationNode(NavTree.RootNodes, current);
        ShowItems(selectedMedia);
    }

    private void OpenSourceFolder(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is Navigation target)
            NavigateFromContent(target);
    }

    private async void SourceFoldersKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key is VirtualKey.Left or VirtualKey.Right)
        {
            args.Handled = true;
            return;
        }
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                NavigateToSourceParent();
            return;
        }
        if (args.Key is not (VirtualKey.Enter or VirtualKey.Space))
            return;
        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown &&
            FocusManager.GetFocusedElement(Root.XamlRoot) is ListViewItem item &&
            SourceFolders.ItemFromContainer(item) is Navigation target)
        {
            if (args.Key == VirtualKey.Space)
                NavigateFromContent(target);
            else
                await RenameIndexedFolder(target, fromSidebar: false);
        }
    }

    private Source? VisibleSource => !searching && current.Source is long id ? sources[id] : null;

    private void GoBackToSourceFolder(object sender, RoutedEventArgs args) => NavigateToSourceParent();

    private void NavigateToSourceParent()
    {
        if (VisibleSource is not { } source || current.Folder is not { } path)
            return;
        var (parent, _) = SourceRename.SplitPath(path.TrimEnd('/'));
        var target = parent.Length == 0
            ? new Navigation(source.Name, Source: source.Id)
            : new Navigation(SourceRename.SplitPath(parent).Leaf, Source: source.Id, Folder: parent + "/");
        NavigateTo(target);
        if (browsingFolders)
            FocusSourceFolder(path);
        else
            FocusSidebarFolder(source.Id, path);
    }

    private void NavigateFromContent(Navigation target, string? restoringFolder = null)
    {
        NavigateTo(target);
        if (browsingFolders)
            FocusSourceFolder(restoringFolder);
        else
            FocusSelectedMedia();
    }

    private void FocusSourceFolder(string? restoringFolder = null)
    {
        var folders = SourceFolders.Items.OfType<Navigation>();
        var folder = folders.FirstOrDefault(item => item.Folder == restoringFolder) ?? folders.FirstOrDefault();
        FocusBrowserItem(SourceFolders, folder, FocusState.Keyboard);
    }

    private bool ShowSourceFolders()
    {
        var source = VisibleSource;
        var path = current.Folder;
        var atAlbum = path is not null && path.IndexOf('/') != path.Length - 1;
        var browseFolders = source?.Layout switch
        {
            Layout.MultiCreator => !atAlbum,
            Layout.Creator => path is null,
            _ => false
        };
        BackToSourceFolder.Visibility = source is not null && path is not null ? Visibility.Visible : Visibility.Collapsed;
        SourceFolders.Visibility = browseFolders ? Visibility.Visible : Visibility.Collapsed;
        SourceFolders.ItemsSource = browseFolders
            ? FindNavigationNode(NavTree.RootNodes, current)?.Children.Select(node => (Navigation)node.Content).ToList()
            : null;
        return browseFolders;
    }

    private void ShowItems(long? selected = null)
    {
        if (catalog is null)
            return;
        Query.Visibility = SearchOptions.Visibility = current == Library ? Visibility.Collapsed : Visibility.Visible;
        browsingFolders = ShowSourceFolders();
        var scopedMedia = ScopeMedia();
        IEnumerable<Media> items = browsingFolders ? []
            : current.Album is not null ? scopedMedia : MediaSearch.ByPath(scopedMedia);

        if (searching)
        {
            try
            {
                items = MediaSearch.Find(scopedMedia.Where(item => item.Present), Query.Text,
                    SearchMode.SelectedIndex == 0, SearchFolders.IsChecked == true, SearchFiles.IsChecked == true);
            }
            catch (Exception error) when (error is InvalidOperationException or EntryPointNotFoundException or DllNotFoundException)
            {
                ShowNotice("搜索失败", error.Message);
                items = [];
            }
        }

        tiles = new ObservableCollection<Tile>(items.Select((item, index) => new Tile(item, index)));
        if (selectionAlbum is long selectedAlbum)
        {
            if (current.Album != selectedAlbum || searching || tiles.Count == 0)
                ClearAlbumSelection();
            else
                albumRemovalIds.IntersectWith(tiles.Select(tile => tile.Media.Id));
        }
        RefreshMediaBrowser(selected);
        Heading.Text = searching ? $"“{Query.Text.Trim()}”的搜索结果" : current.Label;
        RefreshTitleEditor();
        var choosingCreator = VisibleSource?.Layout == Layout.MultiCreator && current.Folder is null;
        CountLabel.Text = browsingFolders
            ? $"{SourceFolders.Items.Count}{(choosingCreator ? " 位创作者" : " 个专辑")}"
            : $"{tiles.Count} 项" + (current.Source is null && current.Album is null && !searching
                ? $" · {sources.Count} 个来源" : "");
        if (!searching && current.Source is long source && !sources[source].Available)
            CountLabel.Text += " · 来源离线";
        var showAlbum = current.Album is not null && !searching;
        var isEmptyAlbum = showAlbum && tiles.Count == 0;
        AlbumTools.Visibility = showAlbum ? Visibility.Visible : Visibility.Collapsed;
        AlbumPickerButton.Visibility = showAlbum && !isEmptyAlbum ? Visibility.Visible : Visibility.Collapsed;
        SelectAlbumMembersButton.Visibility = AlbumPickerButton.Visibility;
        EmptyAlbumPicker.Visibility = isEmptyAlbum ? Visibility.Visible : Visibility.Collapsed;
        EmptyLabel.Text = searching ? "没有匹配项。" : sources.Count == 0
                ? "导入文件夹后，图片和视频会显示在这里。" : "此处没有媒体项目。";
        if (browsingFolders)
            EmptyLabel.Text = choosingCreator ? "没有已索引的创作者。" : "没有已索引的专辑。";
        var visibleItemCount = browsingFolders ? SourceFolders.Items.Count : tiles.Count;
        EmptyLabel.Visibility = visibleItemCount == 0 && !isEmptyAlbum ? Visibility.Visible : Visibility.Collapsed;
        Rescan.IsEnabled = !busy && sources.Count > 0;
    }

    private void SearchSubmitted(AutoSuggestBox sender, AutoSuggestBoxQuerySubmittedEventArgs args)
    {
        searching = !string.IsNullOrWhiteSpace(args.QueryText);
        ShowItems();
    }

    private void SearchEdited(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args)
    {
        if (searching && string.IsNullOrWhiteSpace(sender.Text))
        {
            searching = false;
            ShowItems();
        }
    }

    private void ChangeSearchMode(object sender, SelectionChangedEventArgs args)
    {
        if (searching)
            ShowItems();
    }

    private void ChangeSearchScope(object sender, RoutedEventArgs args)
    {
        if (searching)
            ShowItems();
    }

    private async void ChooseSource(object sender, RoutedEventArgs args)
    {
        if (busy)
            return;
        SetBusy(true);
        try
        {
            var picker = new FolderPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary };
            picker.FileTypeFilter.Add("*");
            WinRT.Interop.InitializeWithWindow.Initialize(picker, WinRT.Interop.WindowNative.GetWindowHandle(this));
            var folder = await picker.PickSingleFolderAsync();
            if (folder is null)
                return;
            Database.CheckSourcePath(folder.Path);
            var scanVersion = Database.DataVersion;
            var summary = await Task.Run(() => MediaFiles.Probe(folder.Path));
            if (summary.Options.Count == 0)
            {
                ShowNotice("未找到支持的媒体", "请选择媒体所在目录，或包含创作者与专辑的文件夹。", InfoBarSeverity.Warning);
                return;
            }

            var layout = summary.Options.Keys.First();
            var optionPicker = new StackPanel { Spacing = 10 };
            foreach (var option in summary.Options)
            {
                var choice = new RadioButton
                {
                    GroupName = "Layout",
                    Content = $"{MediaFiles.Display(option.Key)} · {option.Value.Count} 项",
                    IsChecked = option.Key == layout
                };
                choice.Checked += (_, _) => layout = option.Key;
                optionPicker.Children.Add(choice);
            }

            var result = await new ContentDialog
            {
                XamlRoot = Root.XamlRoot,
                Title = $"导入 {MediaFiles.FolderName(summary.Path)}",
                Content = optionPicker,
                PrimaryButtonText = "导入",
                CloseButtonText = "取消",
                DefaultButton = ContentDialogButton.Primary
            }.ShowAsync();

            if (result == ContentDialogResult.Primary)
            {
                var imported = Database.Import(summary.Path, layout, summary.Options[layout], scanVersion);
                searching = false;
                Query.Text = "";
                current = new Navigation(MediaFiles.FolderName(summary.Path), Source: imported);
                Notice.IsOpen = false;
                Reload();
                if (browsingFolders)
                    FocusSourceFolder();
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or COMException)
        {
            ShowNotice("无法导入文件夹", error.Message);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async void RescanSources(object sender, RoutedEventArgs args)
    {
        if (busy || catalog is null)
            return;
        SetBusy(true);
        try
        {
            List<Source> scanSources = current.Source is long id ? [sources[id]] : sources.Values.ToList();
            var offline = new List<string>();
            var pending = new List<string>();
            foreach (var source in scanSources)
            {
                if (Database.HasPendingRename(source.Id))
                {
                    pending.Add(source.Name);
                    continue;
                }
                List<ScannedMedia>? scan = null;
                var scanVersion = Database.DataVersion;
                try
                {
                    scan = await Task.Run(() => MediaFiles.Scan(source.Path, source.Layout));
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    offline.Add(source.Name);
                }
                Database.Rescan(source.Id, scan, scanVersion);
            }
            if (pending.Count > 0)
            {
                var warning = $"待恢复重命名：{string.Join("、", pending)}";
                if (offline.Count > 0)
                    warning += $"。离线：{string.Join("、", offline)}";
                ShowNotice("部分来源暂未重扫", warning, InfoBarSeverity.Warning);
            }
            else if (offline.Count == 0)
                Notice.IsOpen = false;
            else
                ShowNotice("部分来源不可用", string.Join("、", offline), InfoBarSeverity.Warning);
            Reload(Selection?.Media.Id);
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("重新扫描失败", error.Message);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool value)
    {
        busy = value;
        ImportButton.IsEnabled = !value && catalog is not null;
        CreateAlbumButton.IsEnabled = !value && catalog is not null;
        Rescan.IsEnabled = !value && sources.Count > 0;
    }

    private async Task<string?> AskAlbumName(string title, string initial)
    {
        var entry = new TextBox { Header = "专辑名称", Text = initial };
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = title,
            Content = entry,
            PrimaryButtonText = "保存",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = !string.IsNullOrWhiteSpace(initial)
        };
        entry.TextChanged += (_, _) => dialog.IsPrimaryButtonEnabled = !string.IsNullOrWhiteSpace(entry.Text);
        return await dialog.ShowAsync() == ContentDialogResult.Primary ? entry.Text.Trim() : null;
    }

    private async void CreateAlbum(object sender, RoutedEventArgs args)
    {
        if (catalog is null)
            return;
        var name = await AskAlbumName("新建虚拟专辑", "");
        if (name is null)
            return;
        try
        {
            current = new(name, Album: Database.CreateAlbum(name));
            searching = false;
            Query.Text = "";
            Reload();
        }
        catch (InvalidOperationException error) { ShowNotice("无法创建专辑", error.Message); }
    }

    private void SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (updatingBrowser || !ReferenceEquals(sender, ActiveMediaBrowser))
            return;
        Tile? changed = null;
        if (SelectingAlbumMembers)
        {
            foreach (var tile in args.RemovedItems.OfType<Tile>())
            {
                albumRemovalIds.Remove(tile.Media.Id);
                tile.SetAlbumRemovalSelection(false);
                changed = tile;
            }
            foreach (var tile in args.AddedItems.OfType<Tile>())
            {
                albumRemovalIds.Add(tile.Media.Id);
                tile.SetAlbumRemovalSelection(true);
                changed = tile;
            }
        }
        UpdateSelection();
        UpdateFilmstripPreview(changed);
    }

    private void UpdateSelection()
    {
        if (OpenButton is null || AlbumSelectionTools is null)
            return;
        UpdateAlbumSelectionTools();
        OpenButton.IsEnabled = Selection is not null;
    }

    private void ShowNotice(string title, string message, InfoBarSeverity severity = InfoBarSeverity.Error)
    {
        Notice.Title = title;
        Notice.Message = message;
        Notice.Severity = severity;
        Notice.IsOpen = true;
    }

    private void LoadThumbnail(object sender, RoutedEventArgs args) => LoadThumbnail((Image)sender);
    private void UpdateThumbnail(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        if (sender.IsLoaded)
            LoadThumbnail((Image)sender);
    }

    private async void LoadThumbnail(Image image)
    {
        image.Source = null;
        if (image.DataContext is not Tile { Media: { Available: true } } tile)
            return;
        try
        {
            var thumbnail = tile.Media.IsVideo
                ? await DecodeVideoThumbnail(tile.Media)
                : await DecodeImage(tile.Media, 320, false);
            if (image.IsLoaded && ReferenceEquals(tile, image.DataContext))
                image.Source = thumbnail;
        }
        catch (Exception error) when (MediaFailure(error))
        {
            // Missing and damaged media retain their labelled card and report the reason in preview.
        }
    }

    private static async Task<BitmapImage> DecodeImage(Media media, int width, bool animated,
                                                       ExceptionRoutedEventHandler? imageFailed = null)
    {
        var file = await OpenMediaFile(media);
        using var stream = await file.OpenReadAsync();
        var bitmap = new BitmapImage { DecodePixelWidth = width, AutoPlay = animated };
        if (imageFailed is not null)
            bitmap.ImageFailed += imageFailed;
        await bitmap.SetSourceAsync(stream);
        return bitmap;
    }

    private static async Task<BitmapImage?> DecodeVideoThumbnail(Media media, uint width = 320)
    {
        var file = await OpenMediaFile(media);
        using var stream = await file.GetThumbnailAsync(ThumbnailMode.VideosView, width, ThumbnailOptions.ResizeThumbnail);
        if (stream is null || stream.Type != ThumbnailType.Image)
            return null;
        var bitmap = new BitmapImage();
        await bitmap.SetSourceAsync(stream);
        return bitmap;
    }

    private static async Task<StorageFile> OpenMediaFile(Media media)
    {
        var path = await Task.Run(() => MediaFiles.OpenPath(media));
        return await StorageFile.GetFileFromPathAsync(path);
    }

    private static bool MediaFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or COMException or ArgumentException;

    private void PreviewSelected(object sender, RoutedEventArgs args) => OpenPreview();
    private void PreviewDoubleTapped(object sender, DoubleTappedRoutedEventArgs args) => OpenPreview();

    private async void GalleryKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (SelectingAlbumMembers)
        {
            if (args.Key == VirtualKey.Enter || (args.Key == VirtualKey.Space && args.KeyStatus.WasKeyDown))
                args.Handled = true;
            return;
        }
        if (args.Key == VirtualKey.Escape && VisibleSource is not null && current.Folder is not null)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                NavigateToSourceParent();
            return;
        }
        if (args.Key == VirtualKey.Enter)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown && Selection is { } tile)
                await RenameSourceItem(tile.Media.Source.Id, tile.Media.RelativePath, tile.Media.Available,
                    isDirectory: false, expectedMediaId: tile.Media.Id);
            return;
        }
        if (args.Key != VirtualKey.Space)
            return;
        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown)
            OpenPreview();
    }

    private void OpenPreview()
    {
        var browser = ActiveMediaBrowser;
        if (SelectingAlbumMembers || browser.SelectedIndex < 0)
            return;
        if (browseMode == BrowseMode.Icons)
            Gallery.UpdateLayout();
        previewBrowser = browser;
        OpenPreview(tiles.ToList(), browser.SelectedIndex, new(browseMode, Columns));
    }

    private void OpenPreview(List<Tile> items, int selectedIndex, BrowseLayout layout)
    {
        initialSelection = items[selectedIndex].Media.Id;
        previewTiles = items;
        previewLayout = layout;
        PreviewTopRail.Height = PreviewBottomRail.Height = new GridLength(layout.Mode == BrowseMode.Gallery ? 0 : 36);
        PreviewLeftRail.Width = PreviewRightRail.Width = new GridLength(layout.Mode == BrowseMode.List ? 0 : 44);
        PreviewOverlay.Visibility = Visibility.Visible;
        var thumbnail = ThumbnailOf(initialSelection);
        LibraryView.IsHitTestVisible = false;
        LibraryHost.IsEnabled = false;
        ShowPreview(selectedIndex, thumbnail?.Image);
        AnimatePreview(thumbnail, opening: true, complete: null);
        if (!PreviewCanvas.Focus(FocusState.Programmatic))
            DispatcherQueue.TryEnqueue(() => PreviewCanvas.Focus(FocusState.Programmatic));
    }

    private int Columns => browseMode == BrowseMode.Icons &&
        Gallery.ItemsPanelRoot is ItemsWrapGrid { ItemWidth: > 0 } panel
        ? Math.Max(1, (int)Math.Floor(panel.ActualWidth / panel.ItemWidth))
        : 1;

    private void ClosePreviewButton(object sender, RoutedEventArgs args) => ClosePreview(initialSelection);

    private void ClosePreview(long? selectedId)
    {
        if (previewClosing || PreviewOverlay.Visibility != Visibility.Visible)
            return;
        if (previewMoving)
        {
            afterPreviewMotion = () => ClosePreview(selectedId);
            return;
        }
        previewClosing = true;
        if (player?.PlaybackSession.CanPause == true)
            player.Pause();
        AnimatePreview(ThumbnailOf(selectedId), opening: false, complete: () => FinishClosePreview(selectedId));
    }

    private void FinishClosePreview(long? selectedId)
    {
        previewClosing = false;
        previewBrowser = null;
        previewGeneration++;
        previewIndex = -1;
        StopVideo();
        MainImage.Source = null;
        NeighborLeft.Source = NeighborRight.Source = NeighborTop.Source = NeighborBottom.Source = null;
        PreviewOverlay.Visibility = Visibility.Collapsed;
        previewTiles = [];
        LibraryHost.IsEnabled = true;
        if (RestoreGlobalSearchAfterPreview(selectedId))
            return;
        LibraryView.IsHitTestVisible = true;
        var browser = ActiveMediaBrowser;
        browser.SelectedItem = tiles.FirstOrDefault(tile => tile.Media.Id == selectedId) ?? tiles.FirstOrDefault();
        FocusSelectedMedia();
    }

    private void PreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                ClosePreview(initialSelection);
            return;
        }
        if (previewIndex < 0 || previewClosing)
            return;
        if (args.Key == VirtualKey.Enter && previewTiles[previewIndex].Media.IsVideo)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                ChangePreviewVideoLock(!previewVideoLocked);
            return;
        }
        if (previewVideoLocked && args.Key is VirtualKey.Space or VirtualKey.Left or VirtualKey.Right or VirtualKey.Up or VirtualKey.Down)
        {
            args.Handled = true;
            if (args.KeyStatus.WasKeyDown)
                return;
            if (args.Key == VirtualKey.Space)
                ToggleVideo();
            else if (args.Key == VirtualKey.Left)
                SeekVideoBy(-VideoSeekInterval);
            else if (args.Key == VirtualKey.Right)
                SeekVideoBy(VideoSeekInterval);
            return;
        }
        if (!ReferenceEquals(FocusManager.GetFocusedElement(Root.XamlRoot), PreviewCanvas))
            return;
        if (args.Key == VirtualKey.Space)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                ClosePreview(previewTiles[previewIndex].Media.Id);
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
        MovePreview(arrow);
    }

    private async void ShowPreview(int index, BitmapImage? poster)
    {
        previewIndex = index;
        var generation = ++previewGeneration;
        StopVideo();
        var tile = previewTiles[index];
        PreviewTitle.Text = tile.FileName;
        IndexLabel.Text = $"{index + 1} / {previewTiles.Count}";
        PreviewError.Visibility = Visibility.Collapsed;
        MainImage.Source = tile.Media.IsVideo ? null : poster;
        VideoSurface.Visibility = Visibility.Collapsed;
        PlayPause.IsEnabled = false;
        SetPreviewSeekEnabled(false);
        if (tile.Media.IsVideo)
            TimeLabel.Text = DurationLabel.Text = "0:00";
        VideoControls.Visibility = tile.Media.IsVideo ? Visibility.Visible : Visibility.Collapsed;
        SetPreviewVideoLock(false);
        LoadNeighbor(NeighborLeft, BrowseDirection.Left, generation);
        LoadNeighbor(NeighborRight, BrowseDirection.Right, generation);
        LoadNeighbor(NeighborTop, BrowseDirection.Up, generation);
        LoadNeighbor(NeighborBottom, BrowseDirection.Down, generation);

        try
        {
            if (tile.Media.IsVideo)
            {
                var file = await OpenMediaFile(tile.Media);
                if (generation == previewGeneration)
                    StartVideo(file, generation);
                return;
            }

            var image = await DecodeImage(tile.Media, 0, true, (_, error) =>
            {
                if (generation == previewGeneration)
                    ShowPreviewError("无法解码此图片。", error.ErrorMessage);
            });
            if (generation == previewGeneration && PreviewError.Visibility == Visibility.Collapsed)
                MainImage.Source = image;
        }
        catch (Exception error) when (MediaFailure(error))
        {
            if (generation == previewGeneration)
                ShowPreviewError(tile.Media.IsVideo ? "无法打开此视频。" : "无法解码此图片。", error.Message);
        }
    }

    private async void LoadNeighbor(Image image, BrowseDirection direction, int generation)
    {
        image.Source = null;
        if (previewLayout.NeighborOf(previewIndex, previewTiles.Count, direction) is not int index)
            return;
        try
        {
            var media = previewTiles[index].Media;
            var bitmap = media.IsVideo ? await DecodeVideoThumbnail(media) : await DecodeImage(media, 24, false);
            if (generation == previewGeneration)
                image.Source = bitmap;
        }
        catch (Exception error) when (MediaFailure(error)) { }
    }

    private void StartVideo(StorageFile file, int generation)
    {
        var mediaPlayer = new MediaPlayer();
        player = mediaPlayer;
        mediaPlayer.CommandManager.IsEnabled = false;
        mediaPlayer.MediaOpened += (_, _) => DispatcherQueue.TryEnqueue(() =>
        {
            if (generation != previewGeneration)
                return;
            PlayPause.IsEnabled = true;
            UpdateTime();
        });
        mediaPlayer.MediaFailed += (_, details) => DispatcherQueue.TryEnqueue(() =>
        {
            if (generation == previewGeneration)
                ShowPreviewError("系统无法播放此视频。", details.ErrorMessage);
        });

        VideoSurface.SetMediaPlayer(mediaPlayer);
        VideoSurface.Visibility = Visibility.Visible;
        videoSource = MediaSource.CreateFromStorageFile(file);
        mediaPlayer.Source = videoSource;
        mediaPlayer.Play();
        playbackClock.Start();
    }

    private void StopVideo()
    {
        playbackClock.Stop();
        if (player is not { } active)
            return;

        player = null;
        var source = videoSource;
        videoSource = null;
        try
        {
            if (active.PlaybackSession.CanPause)
                active.Pause();
            active.Source = null;
        }
        finally
        {
            VideoSurface.SetMediaPlayer(null);
            using (active)
            {
                source?.Dispose();
            }
        }
    }

    private void ShowPreviewError(string title, string detail)
    {
        StopVideo();
        MainImage.Source = null;
        VideoSurface.Visibility = Visibility.Collapsed;
        PlayPause.IsEnabled = false;
        SetPreviewSeekEnabled(false);
        PreviewError.Text = string.IsNullOrWhiteSpace(detail) ? title : $"{title}\n{detail}";
        PreviewError.Visibility = Visibility.Visible;
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void UpdateTime()
    {
        if (player is null)
            return;
        var session = player.PlaybackSession;
        var duration = session.NaturalDuration;
        var position = session.Position;
        SetPreviewSeekEnabled(session.CanSeek && duration > TimeSpan.Zero);
        settingPosition = true;
        Timeline.Maximum = Math.Max(1, duration.TotalSeconds);
        Timeline.Value = Math.Max(0, Math.Min(position.TotalSeconds, Timeline.Maximum));
        settingPosition = false;
        TimeLabel.Text = FormatTime(position);
        DurationLabel.Text = FormatTime(duration);
        PlayPause.Content = session.PlaybackState == MediaPlaybackState.Playing ? "暂停" : "播放";
    }

    private static string FormatTime(TimeSpan time) =>
        time.ToString(time.TotalHours >= 1 ? @"h\:mm\:ss" : @"m\:ss", CultureInfo.InvariantCulture);

    private const int VideoSeekInterval = 15;

    private void MovePreviewLeft(object sender, RoutedEventArgs args) => MovePreview(BrowseDirection.Left);
    private void MovePreviewRight(object sender, RoutedEventArgs args) => MovePreview(BrowseDirection.Right);
    private void MovePreviewUp(object sender, RoutedEventArgs args) => MovePreview(BrowseDirection.Up);
    private void MovePreviewDown(object sender, RoutedEventArgs args) => MovePreview(BrowseDirection.Down);

    private void MovePreview(BrowseDirection direction)
    {
        if (previewIndex < 0 || previewVideoLocked || previewMoving || previewClosing ||
            previewLayout.NeighborOf(previewIndex, previewTiles.Count, direction) is not int next)
            return;
        ShowPreview(next, ThumbnailOf(previewTiles[next].Media.Id)?.Image);
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void ToggleVideoLock(object sender, RoutedEventArgs args) => ChangePreviewVideoLock(VideoLock.IsChecked == true);

    private void ChangePreviewVideoLock(bool locked)
    {
        SetPreviewVideoLock(locked);
        PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void SetPreviewVideoLock(bool locked)
    {
        previewVideoLocked = locked;
        VideoLock.IsChecked = locked;
        VideoLock.Content = locked ? "已锁定" : "未锁定";

        UpdateDirection(PreviewLeft, NeighborLeft, BrowseDirection.Left);
        UpdateDirection(PreviewRight, NeighborRight, BrowseDirection.Right);
        UpdateDirection(PreviewUp, NeighborTop, BrowseDirection.Up);
        UpdateDirection(PreviewDown, NeighborBottom, BrowseDirection.Down);

        if (locked)
        {
            PreviewHint.Text = "← / → 跳转 15 秒    Space 播放或暂停    Enter 解锁    Esc 退出";
            return;
        }
        var navigation = previewLayout.Mode switch
        {
            BrowseMode.List => "↑ / ↓ 切换媒体",
            BrowseMode.Gallery => "← / → 切换媒体",
            _ => "方向键 切换媒体"
        };
        var lockHint = previewTiles[previewIndex].Media.IsVideo ? "    Enter 锁定" : "";
        PreviewHint.Text = $"{navigation}    Space / Esc 退出{lockHint}";

        void UpdateDirection(Button button, Image neighbor, BrowseDirection direction)
        {
            var available = !locked && previewLayout.NeighborOf(previewIndex, previewTiles.Count, direction) is not null;
            button.Visibility = neighbor.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void TogglePlayback(object sender, RoutedEventArgs args) => ToggleVideo();

    private void ToggleVideo()
    {
        if (player is null)
            return;
        if (player.PlaybackSession.PlaybackState == MediaPlaybackState.Playing)
            player.Pause();
        else
            player.Play();
        UpdateTime();
    }

    private void SetPreviewSeekEnabled(bool enabled) => VideoBack.IsEnabled = VideoForward.IsEnabled = Timeline.IsEnabled = enabled;

    private void SeekVideoBack(object sender, RoutedEventArgs args) => SeekVideoBy(-VideoSeekInterval);
    private void SeekVideoForward(object sender, RoutedEventArgs args) => SeekVideoBy(VideoSeekInterval);

    private void SeekVideoBy(int seconds)
    {
        if (player?.PlaybackSession is { } session)
            SeekVideoTo(session.Position.TotalSeconds + seconds);
    }

    private void Seek(object sender, Microsoft.UI.Xaml.Controls.Primitives.RangeBaseValueChangedEventArgs args)
    {
        if (!settingPosition)
            SeekVideoTo(args.NewValue);
    }

    private void SeekVideoTo(double seconds)
    {
        if (player?.PlaybackSession is not { CanSeek: true } session || session.NaturalDuration <= TimeSpan.Zero)
            return;
        session.Position = TimeSpan.FromSeconds(Math.Clamp(seconds, 0, session.NaturalDuration.TotalSeconds));
    }
}
