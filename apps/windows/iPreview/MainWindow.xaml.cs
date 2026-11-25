using System.Collections.ObjectModel;
using System.Globalization;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
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
        long? Album = null, string Glyph = "\uE8B7", string Help = "", IReadOnlyList<Media>? Cover = null,
        string Caption = "", SidebarAlbumFavorite? Favorite = null)
    {
        public Thickness SidebarIndent => Folder is null ? new() : new(14, 0, 0, 0);
        public Visibility FavoriteVisibility => Favorite is null ? Visibility.Collapsed : Visibility.Visible;
        public override string ToString() => Label;
    }

    private static readonly Navigation Library = new("媒体库", Glyph: "\uE8B9");
    private Catalog? catalog;
    private Navigation current = Library;
    private Dictionary<long, Source> sources = [];
    private List<Media> media = [];
    private List<Album> albums = [];
    private Dictionary<long, List<Media>> albumMembers = [];
    private long libraryDataVersion;
    private ObservableCollection<Tile> tiles = [];
    private bool busy;
    private int previewIndex = -1;
    private List<Tile> previewTiles = [];
    private BrowseLayout previewLayout;
    private int previewGeneration;
    private int previewImageGeneration;
    private bool previewVideoLocked;
    private bool previewVideoWaiting;
    private readonly DispatcherTimer previewCopyTimer = new() { Interval = TimeSpan.FromSeconds(1.2) };
    private MediaPlayer? player;
    private MediaSource? videoSource;
    private readonly DispatcherTimer playbackClock = new() { Interval = TimeSpan.FromMilliseconds(200) };
    private bool settingPosition;

    public MainWindow()
    {
        InitializeComponent();
        SetBrowseMode(browseMode);
        InitializeMediaSort();
        InitializeSourceAlbumStars();
        SystemBackdrop = new MicaBackdrop();
        InitializeTitleBar();
        RestoreTheme();
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 760));
        Root.Loaded += OpenCatalog;
        Root.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(DismissSourceActionsOnOutsideClick), true);
        Root.AddHandler(UIElement.PointerReleasedEvent, new PointerEventHandler(CommitTitleOnOutsideClick), true);
        playbackClock.Tick += (_, _) => UpdateTime();
        previewCopyTimer.Tick += (_, _) => ResetPreviewCopyFeedback();
        Closed += (_, _) =>
        {
            CancelAlbumAdjustmentPointer();
            browserSort.Cancel();
            previewSort.Cancel();
            videoWorkSession?.CancelPhotoTasks();
            previewNeighborGeneration++;
            sidebarAnimation?.Stop();
            sidebarAnimation = null;
            previewCopyTimer.Stop();
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
            LibraryHomeButton.Focus(FocusState.Programmatic);
            if (catalog.RenameRecoveryNotice is { } warning)
                ShowNotice("有待恢复的重命名", warning, InfoBarSeverity.Warning);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            ShowNotice("无法打开媒体库", error.Message);
            ImportButton.IsEnabled = false;
            AddSourceButton.IsEnabled = false;
            CreateAlbumButton.IsEnabled = false;
            Rescan.IsEnabled = false;
        }
    }

    private void Reload(long? selected = null, Navigation? destination = null)
    {
        BackFromVideoWork();
        var snapshot = Database.Read();
        current = destination ?? current;
        libraryDataVersion = snapshot.DataVersion;
        sources = snapshot.Sources;
        media = snapshot.Media;
        albums = snapshot.Albums;
        albumMembers = snapshot.AlbumMembers;
        sourceAlbumIndex = Database.ReadSourceAlbumIndex();
        sourceAlbumKeys = media.Where(item => item.Present).Select(SourceAlbumKey.FromMedia).ToHashSet();
        videoWorks = snapshot.VideoWorks;

        RevealSourceActions(null);
        AlbumNavigation.ItemsSource = albums.Select(album => new Navigation(album.Name, Album: album.Id,
            Glyph: "\uE7B8")).ToList();

        if (current.Source is long sourceId && !sources.ContainsKey(sourceId))
            current = Library;
        if (current.Album is long albumId)
            current = albums.Find(album => album.Id == albumId) is { } album
                ? new(album.Name, Album: albumId) : Library;
        UpdateNavigationSelection();
        ShowItems(selected);
        RefreshSearchTagsFromCatalog();
    }

    private void UpdateNavigationSelection()
    {
        var sidebarFavorites = SourceNavigation.Items.OfType<Navigation>()
            .Select(item => item.Favorite).OfType<SidebarAlbumFavorite>()
            .ToDictionary(favorite => favorite.Key);
        var rows = SourceSidebarRows(sidebarFavorites).ToList();
        if (!SourceNavigation.Items.OfType<Navigation>().SequenceEqual(rows))
            SourceNavigation.ItemsSource = rows;
        var sourceRows = SourceNavigation.Items.OfType<Navigation>().Where(item => item.Source == current.Source);
        SourceNavigation.SelectedItem = sourceRows.FirstOrDefault(item => item.Folder == current.Folder)
            ?? sourceRows.FirstOrDefault();
        AlbumNavigation.SelectedItem = AlbumNavigation.Items.OfType<Navigation>()
            .FirstOrDefault(item => item.Album == current.Album);
    }

    private IEnumerable<Navigation> SourceSidebarRows(
        IReadOnlyDictionary<SourceAlbumKey, SidebarAlbumFavorite> sidebarFavorites)
    {
        foreach (var source in sources.Values.OrderBy(source => source.Name).ThenBy(source => source.Id))
        {
            var label = source.Available ? source.Name : $"{source.Name}（离线）";
            var glyph = source.Layout switch
            {
                Layout.MultiCreator => "\uE902",
                Layout.Creator => "\uE77B",
                _ => "\uE8B7"
            };
            var rootFavorite = AlbumKeyAt(source, null) is { } rootKey
                ? SidebarFavoriteFor(rootKey, label, sidebarFavorites) : null;
            yield return new Navigation(label, Source: source.Id, Glyph: glyph, Help: source.Path, Favorite: rootFavorite);
            if (current.Source == source.Id && current.Folder is { } folder && AlbumKeyAt(source, folder) is { } album)
                yield return new Navigation(current.Label, Source: source.Id, Folder: folder,
                    Favorite: SidebarFavoriteFor(album, current.Label, sidebarFavorites));
        }
    }

    private void Navigate(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is Navigation target)
            NavigateFromContent(target);
    }

    private void NavigateTo(Navigation target, long? selectedMedia = null)
    {
        current = target;
        RevealSourceActions(null);
        Notice.IsOpen = false;
        UpdateNavigationSelection();
        ShowItems(selectedMedia);
    }

    private void OpenSourceFolder(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is Navigation target)
            NavigateFromContent(target);
    }

    private async void SourceFoldersKeyDown(object sender, KeyRoutedEventArgs args)
    {
        var direction = args.Key switch
        {
            VirtualKey.Left => BrowseDirection.Left,
            VirtualKey.Right => BrowseDirection.Right,
            VirtualKey.Up => BrowseDirection.Up,
            VirtualKey.Down => BrowseDirection.Down,
            _ => (BrowseDirection?)null
        };
        if (direction is { } toward)
        {
            args.Handled = true;
            var index = Math.Max(0, SourceFolders.SelectedIndex);
            var layout = new BrowseLayout(BrowseMode.Icons, GridColumns(SourceFolders));
            if (layout.NeighborOf(index, SourceFolders.Items.Count, toward) is int destination)
            {
                SourceFolders.SelectedIndex = destination;
                FocusBrowserItem(SourceFolders, SourceFolders.SelectedItem, FocusState.Keyboard);
            }
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
        if (!args.KeyStatus.WasKeyDown && SourceFolders.SelectedItem is Navigation target)
        {
            if (args.Key == VirtualKey.Space)
            {
                if (WorkAt(target) is { } work)
                    OpenVideoWork(work);
                else
                    NavigateFromContent(target);
            }
            else
                await RenameIndexedFolder(target);
        }
    }

    private Source? VisibleSource => current.Source is long id ? sources[id] : null;

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
            FocusSidebarSource(source.Id);
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
        SourceFolders.SelectedItem = folder;
        FocusBrowserItem(SourceFolders, folder, FocusState.Keyboard);
    }

    private bool ShowSourceFolders()
    {
        var source = VisibleSource;
        var path = current.Folder;
        var atAlbum = path is not null && path.IndexOf('/') != path.Length - 1;
        var browseFolders = WorkAt(current) is null && (source?.Layout switch
        {
            Layout.MultiCreator => !atAlbum,
            Layout.Creator => path is null,
            _ => false
        });
        BackToSourceFolder.Visibility = source is not null && path is not null ? Visibility.Visible : Visibility.Collapsed;
        SourceFolders.Visibility = browseFolders ? Visibility.Visible : Visibility.Collapsed;
        if (!browseFolders)
        {
            SourceFolders.ItemsSource = null;
            return false;
        }
        var prefix = path ?? "";
        var choosingCreator = source?.Layout == Layout.MultiCreator && path is null;
        var folders = MediaSearch.ByPath(media.Where(item => source is not null && item.Source.Id == source.Id &&
                item.Present && item.RelativePath.StartsWith(prefix, StringComparison.Ordinal)))
            .Where(item => item.RelativePath[prefix.Length..].Contains('/'))
            .GroupBy(item => item.RelativePath[prefix.Length..].Split('/')[0])
            .Select(group =>
            {
                var folder = prefix + group.Key + "/";
                var albumPath = folder.TrimEnd('/');
                var isCreator = choosingCreator && !group.Any(item => item.WorkAlbumPath == albumPath);
                var count = isCreator
                    ? group.Select(item => item.RelativePath[folder.Length..].Split('/')[0]).Distinct().Count()
                    : group.Count();
                var key = new SourceAlbumKey(source!.Id, albumPath);
                IReadOnlyList<Media> cover = isCreator ? [group.First()]
                    : sourceAlbumIndex.Covers(key, SourceAlbumMembers(key, group));
                return new Navigation(group.Key, Source: source!.Id, Folder: folder,
                    Cover: cover, Caption: $"{count} {(isCreator ? "个专辑" : "项")}");
            }).ToList();
        SourceFolders.ItemsSource = folders;
        if (SourceFolders.Items.Count > 0)
            SourceFolders.SelectedIndex = 0;
        return browseFolders;
    }

    private void ShowItems(long? selected = null, bool revealSelection = false)
    {
        if (catalog is null)
            return;
        browserSort.Cancel();
        browsingFolders = ShowSourceFolders();
        var scopedMedia = ScopeMedia();
        IEnumerable<Media> items = browsingFolders ? []
            : current.Album is not null ? scopedMedia : MediaSearch.ByPath(scopedMedia);

        var displayed = items.ToList();
        if (selectionAlbum is long selectedAlbum)
        {
            if (current.Album != selectedAlbum || displayed.Count == 0)
                ClearAlbumSelection();
            else
                albumRemovalIds.IntersectWith(displayed.Select(item => item.Id));
        }
        var order = SelectingAlbumMembers ? default : browserSort.Order;
        if (order.Field == MediaSortField.Name)
            displayed = order.Arrange(displayed, static item => item);
        tiles = new ObservableCollection<Tile>(displayed.Select((item, index) => new Tile(item, index)));
        RefreshMediaBrowser(selected);
        Heading.Text = current.Label;
        RefreshTitleEditor();
        ShowSourceAlbumControls(scopedMedia);
        ManageAlbumTags.Visibility = current == Library ? Visibility.Visible : Visibility.Collapsed;
        var choosingCreator = VisibleSource?.Layout == Layout.MultiCreator && current.Folder is null;
        CountLabel.Text = browsingFolders
            ? $"{SourceFolders.Items.Count}{(choosingCreator ? " 位创作者" : " 个专辑")}"
            : $"{tiles.Count} 项";
        var work = WorkAt(current);
        PreviewWorkButton.Visibility = work is null ? Visibility.Collapsed : Visibility.Visible;
        if (VisibleSource is { } visibleSource)
            CountLabel.Text = (work is null ? MediaFiles.Display(visibleSource.Layout) : "视频作品") + " · " + CountLabel.Text;
        if (current.Source is long source && !sources[source].Available)
            CountLabel.Text += " · 媒体源离线";
        var showAlbum = current.Album is not null;
        var isEmptyAlbum = showAlbum && tiles.Count == 0;
        AlbumTools.Visibility = showAlbum ? Visibility.Visible : Visibility.Collapsed;
        AlbumPickerButton.Visibility = showAlbum && !isEmptyAlbum ? Visibility.Visible : Visibility.Collapsed;
        SelectAlbumMembersButton.Visibility = AlbumPickerButton.Visibility;
        EmptyAlbumPicker.Visibility = isEmptyAlbum ? Visibility.Visible : Visibility.Collapsed;
        EmptyLabel.Text = sources.Count == 0
                ? "导入文件夹后，图片和视频会显示在这里。" : "此处没有媒体项目。";
        if (browsingFolders)
            EmptyLabel.Text = choosingCreator ? "没有已索引的创作者。" : "没有已索引的专辑。";
        var visibleItemCount = browsingFolders ? SourceFolders.Items.Count : tiles.Count;
        EmptyLabel.Visibility = visibleItemCount == 0 && !isEmptyAlbum ? Visibility.Visible : Visibility.Collapsed;
        Rescan.Visibility = current.Source is not null ? Visibility.Visible : Visibility.Collapsed;
        Rescan.IsEnabled = !busy && sources.Count > 0;
        if (revealSelection)
            FocusSelectedMedia();
        if (order.NeedsFileFacts && tiles.Count > 1)
            SortBrowserByFileFacts(tiles);
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
                    Content = $"{ImportLayoutName(option.Key, option.Value)} · {option.Value.Count} 项",
                    IsChecked = option.Key == layout
                };
                choice.Checked += (_, _) => layout = option.Key;
                optionPicker.Children.Add(choice);
            }

            var result = await new ContentDialog
            {
                XamlRoot = Root.XamlRoot,
                RequestedTheme = Root.RequestedTheme,
                Title = $"导入 {MediaFiles.FolderName(summary.Path)}",
                Content = optionPicker,
                PrimaryButtonText = "导入",
                CloseButtonText = "取消",
                DefaultButton = ContentDialogButton.Primary
            }.ShowAsync();

            if (result == ContentDialogResult.Primary)
            {
                var imported = Database.Import(summary.Path, layout, summary.Options[layout], scanVersion);
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

    private static string ImportLayoutName(Layout layout, List<ScannedMedia> files) =>
        layout == Layout.Flat && files.Any(file => file.VideoWork is VideoWorkMembership.Video)
            ? "视频作品" : MediaFiles.Display(layout);

    private async void RescanSources(object sender, RoutedEventArgs args) =>
        await RescanSourcesAsync(current.Source is long id ? [sources[id]] : sources.Values.ToList());

    private async Task RescanSourcesAsync(IReadOnlyList<Source> scanSources)
    {
        if (busy || catalog is null)
            return;
        SetBusy(true);
        try
        {
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
                var scanVersion = libraryDataVersion;
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
                ShowNotice("部分媒体源暂未重扫", warning, InfoBarSeverity.Warning);
            }
            else if (offline.Count == 0)
                Notice.IsOpen = false;
            else
                ShowNotice("部分媒体源不可用", string.Join("、", offline), InfoBarSeverity.Warning);
            Reload(Selection?.Media.Id);
        }
        catch (InvalidOperationException error)
        {
            if (libraryDataVersion != Database.DataVersion)
                Reload(Selection?.Media.Id);
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
        AddSourceButton.IsEnabled = ImportButton.IsEnabled;
        CreateAlbumButton.IsEnabled = !value && catalog is not null;
        DeleteAlbumButton.IsEnabled = !value && catalog is not null;
        ManageAlbumTags.IsEnabled = !value && catalog is not null;
        SourceAlbumCoverButton.IsEnabled = SourceAlbumFavorite.IsEnabled = !value;
        SourceAlbumMetadata.IsHitTestVisible = !value;
        SourceAlbumClearRating.IsEnabled = !value && displayedAlbumRating is not null;
        BrowserSortButton.IsEnabled = !value && catalog is not null;
        Rescan.IsEnabled = !value && sources.Count > 0;
    }

    private async Task<string?> AskAlbumName(string title, string initial)
    {
        var entry = new TextBox { Header = "合集名称", Text = initial };
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            RequestedTheme = Root.RequestedTheme,
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
        var name = await AskAlbumName("新建合集", "");
        if (name is null)
            return;
        try
        {
            current = new(name, Album: Database.CreateAlbum(name));
            Reload();
        }
        catch (InvalidOperationException error) { ShowNotice("无法创建合集", error.Message); }
    }

    private async void DeleteAlbum(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy || titleEdit is not null || current.Album is not long album)
            return;

        var expectedDataVersion = libraryDataVersion;
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = "删除合集",
            Content = new TextBlock
            {
                Text = $"将删除「{current.Label}」及其中的媒体引用。原始媒体文件会保留。",
                TextWrapping = TextWrapping.Wrap
            },
            PrimaryButtonText = "删除合集",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
            return;

        try
        {
            try
            {
                Database.DeleteAlbum(album, expectedDataVersion);
            }
            catch (AlbumDeletionChangedException)
            {
                Reload(Selection?.Media.Id);
                throw;
            }
            Reload(destination: Library);
            Notice.IsOpen = false;
            if (!LibraryHomeButton.Focus(FocusState.Programmatic))
                FocusSelectedMedia();
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("无法删除合集", error.Message);
        }
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
        if (AlbumSelectionTools is null)
            return;
        UpdateAlbumSelectionTools();
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
        ExceptionRoutedEventHandler? imageFailed = null, CancellationToken cancellationToken = default)
    {
        var file = await OpenMediaFile(media, cancellationToken);
        using var stream = await file.OpenReadAsync().AsTask(cancellationToken);
        var bitmap = new BitmapImage { DecodePixelWidth = width, AutoPlay = animated };
        if (imageFailed is not null)
            bitmap.ImageFailed += imageFailed;
        await bitmap.SetSourceAsync(stream).AsTask(cancellationToken);
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

    private static async Task<StorageFile> OpenMediaFile(Media media, CancellationToken cancellationToken = default)
    {
        var path = await Task.Run(() => MediaFiles.OpenPath(media), cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        return await StorageFile.GetFileFromPathAsync(path).AsTask(cancellationToken);
    }

    private static bool MediaFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or COMException or ArgumentException;

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

    private void OpenPreview(List<Tile> items, int selectedIndex, BrowseLayout layout,
        BitmapImage? poster = null, bool startVideo = true)
    {
        var work = BrowsingVideoWork;
        originalPreviewTiles = items;
        previewTiles = items;
        previewSort.Order = default;
        PreviewSortButton.IsEnabled = items.Count > 1;
        PreviewSortButton.Visibility = IndexLabel.Visibility = work ? Visibility.Collapsed : Visibility.Visible;
        var closeName = work ? "返回作品总览" : "退出预览";
        AutomationProperties.SetName(PreviewCloseAction, closeName);
        ToolTipService.SetToolTip(PreviewCloseAction, closeName + "（Esc）");
        previewLayout = layout;
        PreviewTopRail.Height = PreviewBottomRail.Height = new GridLength(work || layout.Mode == BrowseMode.Gallery ? 0 : 36);
        PreviewLeftRail.Width = PreviewRightRail.Width = new GridLength(work || layout.Mode == BrowseMode.List ? 0 : 44);
        PreviewOverlay.Visibility = Visibility.Visible;
        var thumbnail = ThumbnailOf(items[selectedIndex].Media.Id);
        LibraryView.IsHitTestVisible = false;
        LibraryHost.IsEnabled = false;
        ShowPreview(selectedIndex, poster ?? thumbnail?.Image, startVideo);
        if (!work)
            AnimatePreview(thumbnail, opening: true, complete: null);
        var target = work && !startVideo ? WorkPhotoCanvas : PreviewCanvas;
        if (!target.Focus(FocusState.Programmatic))
            DispatcherQueue.TryEnqueue(() => target.Focus(FocusState.Programmatic));
    }

    private int Columns => browseMode == BrowseMode.Icons ? GridColumns(Gallery) : 1;

    private void ClosePreviewButton(object sender, RoutedEventArgs args) => ClosePreview();

    private void ClosePreview()
    {
        if (previewClosing || PreviewOverlay.Visibility != Visibility.Visible)
            return;
        if (previewMoving)
        {
            afterPreviewMotion = ClosePreview;
            return;
        }
        previewClosing = true;
        StopNativeVideoVerification();
        previewSort.Cancel();
        ResetPreviewCopyFeedback();
        var selectedId = previewTiles[previewIndex].Media.Id;
        if (player?.PlaybackSession.CanPause == true)
            player.Pause();
        if (fallbackVideo?.State == LibVlcNative.State.Playing)
            fallbackVideo.Pause();
        if (!searchOpen && videoWorkSession is null)
        {
            var browser = ActiveMediaBrowser;
            var selected = tiles.FirstOrDefault(tile => tile.Media.Id == selectedId) ?? tiles.FirstOrDefault();
            browser.SelectedItem = selected;
            if (selected is not null)
            {
                browser.ScrollIntoView(selected);
                browser.UpdateLayout();
            }
        }
        if (BrowsingVideoWork)
            FinishClosePreview(selectedId);
        else
            AnimatePreview(ThumbnailOf(selectedId), opening: false, complete: () => FinishClosePreview(selectedId));
    }

    private void FinishClosePreview(long? selectedId)
    {
        previewBrowser = null;
        previewGeneration++;
        previewIndex = -1;
        originalPreviewTiles = [];
        previewTiles = [];
        PreviewOverlay.Visibility = Visibility.Collapsed;
        if (videoWorkSession is null)
            LibraryHost.IsEnabled = true;
        StopVideo();
        if (!RestoreVideoWorkAfterMediaPreview() && !RestoreSearchAfterPreview(selectedId))
        {
            FocusSelectedMedia();
            LibraryView.IsHitTestVisible = true;
        }
        MainImage.Source = null;
        NeighborLeft.Source = NeighborRight.Source = NeighborTop.Source = NeighborBottom.Source = null;
        previewClosing = false;
    }

    private void CopyPreviewFilename(object sender, DoubleTappedRoutedEventArgs args)
    {
        if (previewIndex < 0 || previewClosing)
            return;

        var tile = previewTiles[previewIndex];
        ResetPreviewCopyFeedback();
        var content = new DataPackage();
        content.SetText(tile.FileName);
        args.Handled = true;
        if (!Clipboard.SetContentWithOptions(content, null))
        {
            PreviewHint.Text = "剪贴板正忙，请双击文件名重试。";
            return;
        }
        // Clipboard.Flush can lose the race for the clipboard after SetContentWithOptions succeeds.
        const int cannotOpenClipboard = unchecked((int)0x800401D0);
        const int cannotCloseClipboard = unchecked((int)0x800401D4);
        try
        {
            Clipboard.Flush();
        }
        catch (ExternalException error) when (error.HResult is cannotOpenClipboard or cannotCloseClipboard)
        {
            PreviewHint.Text = "剪贴板正忙，请双击文件名重试。";
            return;
        }
        SetPreviewVideoLock(previewVideoLocked);
        if (!tile.Media.IsVideo)
        {
            PreviewTitle.Visibility = Visibility.Collapsed;
            PreviewCopyFeedback.Visibility = Visibility.Visible;
            AnimatePreviewCopyFeedback();
            previewCopyTimer.Start();
        }
    }

    private void ResetPreviewCopyFeedback()
    {
        previewCopyTimer.Stop();
        PreviewCopyFeedback.Visibility = Visibility.Collapsed;
        PreviewTitle.Visibility = Visibility.Visible;
    }

    private void PreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        var work = BrowsingVideoWork;
        var focus = FocusManager.GetFocusedElement(Root.XamlRoot);
        if (work && (WorkPhotoGroupPicker.IsDropDownOpen || focus is MenuFlyoutItemBase))
            return;
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                ClosePreview();
            return;
        }
        if (previewIndex < 0 || previewClosing)
            return;
        if (work && !ReferenceEquals(focus, PreviewCanvas))
        {
            if (ReferenceEquals(focus, WorkPhotoCanvas) && args.Key is VirtualKey.Left or VirtualKey.Right)
            {
                args.Handled = true;
                MoveWorkPhoto(args.Key == VirtualKey.Left ? -1 : 1);
            }
            return;
        }
        if (args.Key == VirtualKey.Enter && VideoControls.Visibility == Visibility.Visible)
        {
            if (ReferenceEquals(focus, PreviewCloseAction) || ReferenceEquals(focus, PreviewSortButton))
                return;
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
        if (!ReferenceEquals(focus, PreviewCanvas))
            return;
        if (args.Key == VirtualKey.Space)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
            {
                if (work)
                    ToggleVideo();
                else
                    ClosePreview();
            }
            return;
        }
        if (work)
            return;
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

    private async void ShowPreview(int index, BitmapImage? poster, bool startVideo = true)
    {
        previewIndex = index;
        var generation = ++previewGeneration;
        StopVideo();
        var tile = previewTiles[index];
        ResetPreviewCopyFeedback();
        PreviewTitle.Text = tile.FileName;
        IndexLabel.Text = $"{index + 1} / {previewTiles.Count}";
        PreviewError.Visibility = Visibility.Collapsed;
        // Hold the last usable frame while the current item is being decoded.
        if (poster is not null)
            SetPreviewImage(poster, generation);
        MainImage.Visibility = Visibility.Visible;
        VideoSurface.Visibility = Visibility.Collapsed;
        PlayPause.IsEnabled = false;
        SetPreviewSeekEnabled(false);
        if (tile.Media.IsVideo)
            TimeLabel.Text = DurationLabel.Text = "0:00";
        VideoControls.Visibility = tile.Media.IsVideo ? Visibility.Visible : Visibility.Collapsed;
        SetPreviewVideoLock(false);
        RefreshPreviewNeighbors();

        try
        {
            if (tile.Media.IsVideo)
            {
                if (startVideo)
                    await OpenPreviewVideo(tile.Media, generation);
                else
                {
                    previewVideoWaiting = true;
                    PlayPause.Content = "播放";
                    PlayPause.IsEnabled = true;
                }
                return;
            }

            var image = await DecodeImage(tile.Media, 0, true, (_, error) =>
            {
                if (CanUpdatePreview(generation))
                    ShowPreviewError("无法解码此图片。", error.ErrorMessage);
            });
            if (CanUpdatePreview(generation) && PreviewError.Visibility == Visibility.Collapsed)
                SetPreviewImage(image, generation);
        }
        catch (Exception error) when (MediaFailure(error))
        {
            if (CanUpdatePreview(generation))
                ShowPreviewError(tile.Media.IsVideo ? "无法打开此视频。" : "无法解码此图片。", error.Message);
        }
    }

    private bool CanUpdatePreview(int generation) => generation == previewGeneration && !previewClosing;

    private void SetPreviewImage(BitmapImage image, int generation)
    {
        MainImage.Source = image;
        previewImageGeneration = generation;
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
            if (generation == previewNeighborGeneration && !previewClosing && previewIndex >= 0)
                image.Source = bitmap;
        }
        catch (Exception error) when (MediaFailure(error)) { }
    }

    private void StartVideo(StorageFile file, Media media, int generation)
    {
        var mediaPlayer = new MediaPlayer();
        player = mediaPlayer;
        var canFallback = LibVlcVideoPlayback.Supports(media.RelativePath);
        mediaPlayer.CommandManager.IsEnabled = false;
        mediaPlayer.MediaOpened += (_, _) => DispatcherQueue.TryEnqueue(() =>
        {
            if (!CanUpdatePreview(generation) || !ReferenceEquals(player, mediaPlayer))
                return;
            if (canFallback)
                awaitingNativeVideo = (media, generation);
            MainImage.Visibility = Visibility.Collapsed;
            if (previewImageGeneration != generation)
                VideoSurface.PosterSource = null;
            PlayPause.IsEnabled = true;
            UpdateTime();
        });
        mediaPlayer.MediaFailed += (_, details) =>
        {
            var message = details.ErrorMessage;
            DispatcherQueue.TryEnqueue(async () =>
            {
                if (CanUpdatePreview(generation) && ReferenceEquals(player, mediaPlayer))
                    await RecoverSystemVideo(media, generation, "系统无法播放此视频。", message);
            });
        };

        if (canFallback)
        {
            mediaPlayer.MediaEnded += (_, _) => DispatcherQueue.TryEnqueue(() =>
            {
                if (ReferenceEquals(player, mediaPlayer))
                    RecoverIfNativeVideoMissing(mediaPlayer.PlaybackSession, playbackConfirmed: true);
            });
        }

        VideoSurface.PosterSource = MainImage.Source;
        VideoSurface.SetMediaPlayer(mediaPlayer);
        VideoSurface.Visibility = Visibility.Visible;
        videoSource = MediaSource.CreateFromStorageFile(file);
        mediaPlayer.Source = videoSource;
        mediaPlayer.Play();
        playbackClock.Start();
        if (canFallback)
            _ = VerifyNativeVideo(file.Path, media, mediaPlayer, generation);
    }

    private void StopVideo()
    {
        playbackClock.Stop();
        previewVideoWaiting = false;
        awaitingNativeVideo = null;
        nativePausedByUser = false;
        deferredNativeVideoRecovery = null;
        StopNativeVideoVerification();
        StopFallbackVideo();
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
            VideoSurface.PosterSource = null;
            using (active)
            {
                source?.Dispose();
            }
        }
    }

    private void ShowPreviewError(string title, string detail)
    {
        StopVideo();
        MainImage.Visibility = Visibility.Collapsed;
        VideoSurface.Visibility = Visibility.Collapsed;
        PlayPause.IsEnabled = false;
        SetPreviewSeekEnabled(false);
        PreviewError.Text = string.IsNullOrWhiteSpace(detail) ? title : $"{title}\n{detail}";
        PreviewError.Visibility = Visibility.Visible;
        VideoControls.Visibility = Visibility.Collapsed;
        SetPreviewVideoLock(false);
        if (!BrowsingVideoWork)
            PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void UpdateTime()
    {
        if (fallbackVideo is { } fallback)
        {
            UpdateFallbackTime(fallback);
            return;
        }
        if (player is { } active)
        {
            var session = active.PlaybackSession;
            var position = session.Position;
            var playing = !nativePausedByUser && session.PlaybackState == MediaPlaybackState.Playing;
            // Let initial video setup settle before treating an advancing audio-only session as failed.
            if (RecoverIfNativeVideoMissing(session, playing && position >= TimeSpan.FromSeconds(1)))
                return;
            UpdateVideoTime(position, session.NaturalDuration, session.CanSeek, playing);
        }
    }

    private void UpdateVideoTime(TimeSpan position, TimeSpan duration, bool canSeek, bool isPlaying)
    {
        SetPreviewSeekEnabled(canSeek && duration > TimeSpan.Zero);
        settingPosition = true;
        Timeline.Maximum = Math.Max(1, duration.TotalSeconds);
        Timeline.Value = Math.Max(0, Math.Min(position.TotalSeconds, Timeline.Maximum));
        settingPosition = false;
        TimeLabel.Text = FormatTime(position);
        DurationLabel.Text = FormatTime(duration);
        PlayPause.Content = isPlaying ? "暂停" : "播放";
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

        UpdatePreviewNavigation();

        if (locked)
        {
            PreviewHint.Text = "← / → 跳转 15 秒    Space 播放或暂停    Enter 解锁    Esc 退出";
            return;
        }
        if (BrowsingVideoWork)
        {
            PreviewHint.Text = VideoControls.Visibility == Visibility.Visible
                ? "Space 播放或暂停    Enter 锁定    Esc 返回"
                : "";
            return;
        }
        var navigation = previewLayout.Mode switch
        {
            BrowseMode.List => "↑ / ↓ 切换媒体",
            BrowseMode.Gallery => "← / → 切换媒体",
            _ => "方向键 切换媒体"
        };
        var lockHint = VideoControls.Visibility == Visibility.Visible ? "    Enter 锁定" : "";
        PreviewHint.Text = $"{navigation}    Space / Esc 退出{lockHint}";
    }

    private void UpdatePreviewNavigation()
    {
        UpdateDirection(PreviewLeft, NeighborLeft, BrowseDirection.Left);
        UpdateDirection(PreviewRight, NeighborRight, BrowseDirection.Right);
        UpdateDirection(PreviewUp, NeighborTop, BrowseDirection.Up);
        UpdateDirection(PreviewDown, NeighborBottom, BrowseDirection.Down);

        void UpdateDirection(Button button, Image neighbor, BrowseDirection direction)
        {
            var available = !previewVideoLocked &&
                previewLayout.NeighborOf(previewIndex, previewTiles.Count, direction) is not null;
            button.Visibility = neighbor.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void TogglePlayback(object sender, RoutedEventArgs args) => ToggleVideo();

    private void ToggleVideo()
    {
        if (previewVideoWaiting)
        {
            previewVideoWaiting = false;
            PlayPause.IsEnabled = false;
            _ = OpenPreviewVideo(previewTiles[previewIndex].Media, previewGeneration);
            return;
        }
        if (fallbackVideo is { } fallback)
        {
            ToggleFallbackVideo(fallback);
            return;
        }
        if (player is not { } active)
            return;
        if (!nativePausedByUser && active.PlaybackSession.PlaybackState == MediaPlaybackState.Playing)
        {
            nativePausedByUser = true;
            active.Pause();
            UpdateTime();
            return;
        }

        nativePausedByUser = false;
        if (deferredNativeVideoRecovery is { } recovery)
        {
            if (CanUpdatePreview(recovery.Generation))
                _ = RecoverSystemVideo(recovery.Media, recovery.Generation, recovery.Title, recovery.SystemError);
            return;
        }

        active.Play();
        UpdateTime();
    }

    private void SetPreviewSeekEnabled(bool enabled) => VideoBack.IsEnabled = VideoForward.IsEnabled = Timeline.IsEnabled = enabled;

    private void SeekVideoBack(object sender, RoutedEventArgs args) => SeekVideoBy(-VideoSeekInterval);
    private void SeekVideoForward(object sender, RoutedEventArgs args) => SeekVideoBy(VideoSeekInterval);

    private void SeekVideoBy(int seconds)
    {
        var position = fallbackVideo?.Position ?? player?.PlaybackSession.Position;
        if (position is { } current)
            SeekVideoTo(current.TotalSeconds + seconds);
    }

    private void Seek(object sender, Microsoft.UI.Xaml.Controls.Primitives.RangeBaseValueChangedEventArgs args)
    {
        if (!settingPosition)
            SeekVideoTo(args.NewValue);
    }

    private void SeekVideoTo(double seconds)
    {
        if (fallbackVideo is { } fallback)
        {
            var duration = fallback.Duration;
            if (fallback.CanSeek && duration > TimeSpan.Zero)
                fallback.Seek(TimeSpan.FromSeconds(Math.Clamp(seconds, 0, duration.TotalSeconds)));
            return;
        }
        if (player?.PlaybackSession is not { CanSeek: true } session || session.NaturalDuration <= TimeSpan.Zero)
            return;
        session.Position = TimeSpan.FromSeconds(Math.Clamp(seconds, 0, session.NaturalDuration.TotalSeconds));
    }
}
