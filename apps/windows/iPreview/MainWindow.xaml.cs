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
    private sealed record Navigation(string Label, long? Source = null, string? Folder = null, long? Album = null)
    {
        public override string ToString() => Label;
    }

    private static readonly Navigation Library = new("媒体库");
    private Catalog? catalog;
    private Navigation current = Library;
    private Dictionary<long, Source> sources = [];
    private List<Media> media = [];
    private List<Album> albums = [];
    private Dictionary<long, List<Media>> albumMembers = [];
    private List<Tile> tiles = [];
    private bool searching;
    private bool busy;
    private int previewIndex = -1;
    private long? initialSelection;
    private List<Tile> previewTiles = [];
    private int previewGeneration;
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
        playbackClock.Tick += (_, _) => UpdateTime();
        Closed += (_, _) =>
        {
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
        NavTree.RootNodes.Add(new TreeViewNode { Content = Library });
        if (sources.Count > 0)
        {
            var sourcesNode = new TreeViewNode { Content = "文件夹", IsExpanded = true };
            foreach (var source in sources.Values.OrderBy(source => source.Name).ThenBy(source => source.Id))
            {
                var label = source.Available ? source.Name : $"{source.Name}（离线）";
                var node = new TreeViewNode
                {
                    Content = new Navigation(label, Source: source.Id),
                    IsExpanded = expanded.Contains(source.Id)
                };
                AddFolders(node, source.Id, media.Where(item => item.Source.Id == source.Id && item.Present));
                sourcesNode.Children.Add(node);
            }
            NavTree.RootNodes.Add(sourcesNode);
        }

        if (albums.Count > 0)
        {
            var albumsNode = new TreeViewNode { Content = "虚拟专辑", IsExpanded = true };
            foreach (var album in albums)
                albumsNode.Children.Add(new TreeViewNode { Content = new Navigation(album.Name, Album: album.Id) });
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
            NavigateTo(target);
    }

    private void NavigateTo(Navigation target)
    {
        current = target;
        searching = false;
        Query.Text = "";
        Notice.IsOpen = false;
        NavTree.SelectedNode = FindNavigationNode(NavTree.RootNodes, current);
        ShowItems();
    }

    private void OpenSourceFolder(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is Navigation target)
            NavigateFromContent(target);
    }

    private void GoBackToSourceFolder(object sender, RoutedEventArgs args)
    {
        if (current.Source is not long sourceID || current.Folder is not { } path)
            return;
        var separator = path.IndexOf('/');
        var creator = path[..separator];
        var target = separator == path.Length - 1
            ? new Navigation(sources[sourceID].Name, Source: sourceID)
            : new Navigation(creator, Source: sourceID, Folder: path[..(separator + 1)]);
        NavigateFromContent(target);
    }

    private void NavigateFromContent(Navigation target)
    {
        NavigateTo(target);
        var browser = SourceFolders.Visibility == Visibility.Visible ? (Control)SourceFolders : ActiveMediaBrowser;
        browser.Focus(FocusState.Programmatic);
    }

    private bool ShowSourceFolders()
    {
        var isMultiCreator = !searching && current.Source is long id && sources[id].Layout == Layout.MultiCreator;
        var path = current.Folder;
        var atAlbum = path is not null && path.IndexOf('/') != path.Length - 1;
        var browseFolders = isMultiCreator && !atAlbum;
        BackToSourceFolder.Visibility = isMultiCreator && path is not null ? Visibility.Visible : Visibility.Collapsed;
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
        browsingFolders = ShowSourceFolders();
        IEnumerable<Media> items = browsingFolders ? []
            : current.Album is long album
            ? albumMembers.GetValueOrDefault(album) ?? []
            : MediaSearch.ByPath(media.Where(item => item.Present
                && (current.Source is null || item.Source.Id == current.Source)
                && (current.Folder is null || item.RelativePath.StartsWith(current.Folder, StringComparison.Ordinal))));

        if (searching)
        {
            try
            {
                items = MediaSearch.Find(media.Where(item => item.Present), Query.Text,
                    SearchMode.SelectedIndex == 0, SearchFolders.IsChecked == true, SearchFiles.IsChecked == true);
            }
            catch (Exception error) when (error is InvalidOperationException or EntryPointNotFoundException or DllNotFoundException)
            {
                ShowNotice("搜索失败", error.Message);
                items = [];
            }
        }

        tiles = items.Select((item, index) => new Tile(item, index)).ToList();
        RefreshMediaBrowser(selected);
        Heading.Text = searching ? $"“{Query.Text.Trim()}”的搜索结果" : current.Label;
        CountLabel.Text = browsingFolders
            ? $"{SourceFolders.Items.Count}{(current.Folder is null ? " 位创作者" : " 个专辑")}"
            : $"{tiles.Count} 项" + (current.Source is null && current.Album is null && !searching
                ? $" · {sources.Count} 个来源" : "");
        if (!searching && current.Source is long source && !sources[source].Available)
            CountLabel.Text += " · 来源离线";
        AlbumTools.Visibility = current.Album is not null && !searching ? Visibility.Visible : Visibility.Collapsed;
        EmptyLabel.Text = searching ? "没有匹配项。" : current.Album is not null
            ? "从媒体库选取图片或视频，加入此专辑。" : sources.Count == 0
                ? "导入文件夹后，图片和视频会显示在这里。" : "此处没有媒体项目。";
        if (browsingFolders)
            EmptyLabel.Text = current.Folder is null ? "没有已索引的创作者。" : "没有已索引的专辑。";
        var visibleItemCount = browsingFolders ? SourceFolders.Items.Count : tiles.Count;
        EmptyLabel.Visibility = visibleItemCount == 0 ? Visibility.Visible : Visibility.Collapsed;
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
                var imported = Database.Import(summary.Path, layout, summary.Options[layout]);
                searching = false;
                Query.Text = "";
                current = new Navigation(MediaFiles.FolderName(summary.Path), Source: imported);
                Notice.IsOpen = false;
                Reload();
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
            foreach (var source in scanSources)
            {
                List<ScannedMedia>? scan = null;
                try
                {
                    scan = await Task.Run(() => MediaFiles.Scan(source.Path, source.Layout));
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                {
                    offline.Add(source.Name);
                }
                Database.Rescan(source.Id, scan);
            }
            if (offline.Count == 0)
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

    private async void RenameAlbum(object sender, RoutedEventArgs args)
    {
        if (current.Album is not long album)
            return;
        var name = await AskAlbumName("重命名虚拟专辑", current.Label);
        if (name is null)
            return;
        try
        {
            Database.RenameAlbum(album, name);
            Reload(Selection?.Media.Id);
        }
        catch (InvalidOperationException error) { ShowNotice("无法重命名专辑", error.Message); }
    }

    private async void AddToAlbum(object sender, RoutedEventArgs args)
    {
        if (Selection is not Tile tile)
            return;
        try
        {
            if (albums.Count == 0)
            {
                var name = await AskAlbumName("新建虚拟专辑并添加媒体", "");
                if (name is null)
                    return;
                Database.CreateAlbum(name, tile.Media.Id);
            }
            else
            {
                var combo = new ComboBox { ItemsSource = albums, DisplayMemberPath = nameof(Album.Name), SelectedIndex = 0 };
                var choice = await new ContentDialog
                {
                    XamlRoot = Root.XamlRoot,
                    Title = "加入虚拟专辑",
                    Content = combo,
                    PrimaryButtonText = "加入",
                    CloseButtonText = "取消",
                    DefaultButton = ContentDialogButton.Primary
                }.ShowAsync();
                if (choice != ContentDialogResult.Primary || combo.SelectedItem is not Album album)
                    return;
                Database.AddToAlbum(album.Id, tile.Media.Id);
            }
            Reload(tile.Media.Id);
        }
        catch (InvalidOperationException error) { ShowNotice("无法添加媒体", error.Message); }
    }

    private void RemoveFromAlbum(object sender, RoutedEventArgs args)
    {
        if (current.Album is not long album || Selection is not Tile tile)
            return;
        try
        {
            Database.RemoveFromAlbum(album, tile.Media.Id);
            Reload();
        }
        catch (InvalidOperationException error) { ShowNotice("无法移除引用", error.Message); }
    }

    private void MoveEarlier(object sender, RoutedEventArgs args) => MoveMember(-1);
    private void MoveLater(object sender, RoutedEventArgs args) => MoveMember(1);

    private void MoveMember(int offset)
    {
        if (current.Album is not long album || Selection is not Tile tile)
            return;
        try
        {
            Database.MoveInAlbum(album, tile.Media.Id, offset);
            Reload(tile.Media.Id);
        }
        catch (InvalidOperationException error) { ShowNotice("无法调整顺序", error.Message); }
    }

    private void SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (updatingBrowser || !ReferenceEquals(sender, ActiveMediaBrowser))
            return;
        UpdateSelection();
        UpdateFilmstripPreview();
    }

    private void UpdateSelection()
    {
        if (OpenButton is null || AddButton is null || MoveUpButton is null ||
            MoveDownButton is null || RemoveButton is null)
            return;
        OpenButton.IsEnabled = Selection is not null;
        AddButton.IsEnabled = Selection is not null;
        RemoveButton.IsEnabled = Selection is not null;
        MoveUpButton.IsEnabled = Selection is not null && ActiveMediaBrowser.SelectedIndex > 0;
        MoveDownButton.IsEnabled = Selection is not null && ActiveMediaBrowser.SelectedIndex < tiles.Count - 1;
    }

    private void ShowNotice(string title, string message, InfoBarSeverity severity = InfoBarSeverity.Error)
    {
        Notice.Title = title;
        Notice.Message = message;
        Notice.Severity = severity;
        Notice.IsOpen = true;
    }

    private void LoadThumbnail(object sender, RoutedEventArgs args) => LoadThumbnail((Image)sender);
    private void UpdateThumbnail(FrameworkElement sender, DataContextChangedEventArgs args) => LoadThumbnail((Image)sender);

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
            if (ReferenceEquals(tile, image.DataContext))
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
        var file = await StorageFile.GetFileFromPathAsync(MediaFiles.OpenPath(media));
        using var stream = await file.OpenReadAsync();
        var bitmap = new BitmapImage { DecodePixelWidth = width, AutoPlay = animated };
        if (imageFailed is not null)
            bitmap.ImageFailed += imageFailed;
        await bitmap.SetSourceAsync(stream);
        return bitmap;
    }

    private static async Task<BitmapImage?> DecodeVideoThumbnail(Media media, uint width = 320)
    {
        var file = await StorageFile.GetFileFromPathAsync(MediaFiles.OpenPath(media));
        using var stream = await file.GetThumbnailAsync(ThumbnailMode.VideosView, width, ThumbnailOptions.ResizeThumbnail);
        if (stream is null || stream.Type != ThumbnailType.Image)
            return null;
        var bitmap = new BitmapImage();
        await bitmap.SetSourceAsync(stream);
        return bitmap;
    }

    private static bool MediaFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or COMException or ArgumentException;

    private void PreviewSelected(object sender, RoutedEventArgs args) => OpenPreview();
    private void PreviewDoubleTapped(object sender, DoubleTappedRoutedEventArgs args) => OpenPreview();

    private void GalleryKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key != VirtualKey.Space)
            return;
        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown)
            OpenPreview();
    }

    private void OpenPreview()
    {
        var browser = ActiveMediaBrowser;
        if (browser.SelectedIndex < 0)
            return;
        initialSelection = Selection?.Media.Id;
        previewTiles = tiles;
        previewColumns = Columns;
        PreviewOverlay.Visibility = Visibility.Visible;
        LibraryView.Visibility = Visibility.Collapsed;
        ShowPreview(browser.SelectedIndex);
        if (!PreviewCanvas.Focus(FocusState.Programmatic))
            DispatcherQueue.TryEnqueue(() => PreviewCanvas.Focus(FocusState.Programmatic));
    }

    private int Columns => browseMode == BrowseMode.Icons &&
        Gallery.ItemsPanelRoot is ItemsWrapGrid { ItemWidth: > 0 } panel
        ? Math.Max(1, (int)Math.Floor(panel.ActualWidth / panel.ItemWidth))
        : 1;
    private int previewColumns = 1;

    private void ClosePreviewButton(object sender, RoutedEventArgs args) => ClosePreview(initialSelection);

    private void ClosePreview(long? selectedId)
    {
        previewGeneration++;
        previewIndex = -1;
        StopVideo();
        MainImage.Source = null;
        NeighborLeft.Source = NeighborRight.Source = NeighborTop.Source = NeighborBottom.Source = null;
        PreviewOverlay.Visibility = Visibility.Collapsed;
        LibraryView.Visibility = Visibility.Visible;
        previewTiles = [];
        var browser = ActiveMediaBrowser;
        browser.SelectedItem = tiles.Find(tile => tile.Media.Id == selectedId) ?? tiles.FirstOrDefault();
        FocusSelectedMedia();
    }

    private void PreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Escape)
        {
            args.Handled = true;
            ClosePreview(initialSelection);
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
        var delta = args.Key switch
        {
            VirtualKey.Left => -1,
            VirtualKey.Right => 1,
            VirtualKey.Up => -previewColumns,
            VirtualKey.Down => previewColumns,
            _ => 0
        };
        if (delta == 0)
            return;
        args.Handled = true;
        var next = previewIndex + delta;
        if (next >= 0 && next < previewTiles.Count)
            ShowPreview(next);
    }

    private async void ShowPreview(int index)
    {
        previewIndex = index;
        var generation = ++previewGeneration;
        StopVideo();
        var tile = previewTiles[index];
        PreviewTitle.Text = tile.FileName;
        IndexLabel.Text = $"{index + 1} / {previewTiles.Count}";
        PreviewError.Visibility = Visibility.Collapsed;
        MainImage.Source = null;
        VideoSurface.Visibility = Visibility.Collapsed;
        VideoControls.Visibility = Visibility.Collapsed;
        LoadNeighbor(NeighborLeft, index - 1, generation);
        LoadNeighbor(NeighborRight, index + 1, generation);
        LoadNeighbor(NeighborTop, index - previewColumns, generation);
        LoadNeighbor(NeighborBottom, index + previewColumns, generation);

        try
        {
            if (tile.Media.IsVideo)
            {
                var file = await StorageFile.GetFileFromPathAsync(MediaFiles.OpenPath(tile.Media));
                if (generation == previewGeneration)
                    StartVideo(file, generation);
                return;
            }

            var image = await DecodeImage(tile.Media, 0, true, (source, error) =>
            {
                if (generation != previewGeneration ||
                    (MainImage.Source is { } currentSource && !ReferenceEquals(currentSource, source)))
                    return;

                MainImage.Source = null;
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

    private async void LoadNeighbor(Image image, int index, int generation)
    {
        image.Source = null;
        if (index < 0 || index >= previewTiles.Count)
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
            VideoControls.Visibility = Visibility.Visible;
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
        VideoSurface.Visibility = Visibility.Collapsed;
        VideoControls.Visibility = Visibility.Collapsed;
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
        settingPosition = true;
        Timeline.Maximum = Math.Max(1, duration.TotalSeconds);
        Timeline.Value = Math.Max(0, Math.Min(position.TotalSeconds, Timeline.Maximum));
        settingPosition = false;
        TimeLabel.Text = $"{FormatTime(position)} / {FormatTime(duration)}";
        PlayPause.Content = session.PlaybackState == MediaPlaybackState.Playing ? "暂停" : "播放";
    }

    private static string FormatTime(TimeSpan time) =>
        time.ToString(time.TotalHours >= 1 ? @"h\:mm\:ss" : @"m\:ss", CultureInfo.InvariantCulture);

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

    private void Seek(object sender, Microsoft.UI.Xaml.Controls.Primitives.RangeBaseValueChangedEventArgs args)
    {
        if (player is not null && !settingPosition && player.PlaybackSession.CanSeek)
            player.PlaybackSession.Position = TimeSpan.FromSeconds(args.NewValue);
    }
}
