using System.ComponentModel;
using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record TileDetails(string Modified, string Size)
    {
        public static readonly TileDetails Unavailable = new("—", "—");
    }

    private sealed class Tile(Media media, int index) : INotifyPropertyChanged
    {
        private static readonly Brush AlternateBackground = new SolidColorBrush(
            Windows.UI.Color.FromArgb(10, 102, 121, 153));
        private static readonly Brush TransparentBackground = new SolidColorBrush(
            Windows.UI.Color.FromArgb(0, 0, 0, 0));
        private bool alternateRow = index % 2 != 0;

        public Media Media { get; } = media;
        public string FileName => Media.FileName;
        public string DisplayPath => Media.DisplayPath;
        public string Label => !Media.Available ? "离线" : Media.IsVideo ? "▶ 视频" : "";
        public Visibility BadgeVisibility => Label.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        public Brush RowBackground => alternateRow ? AlternateBackground : TransparentBackground;
        private string Extension => Path.GetExtension(Media.RelativePath).TrimStart('.').ToUpperInvariant();
        public string Kind => $"{Extension} {(Media.IsVideo ? "视频" : "图像")}";
        public TileDetails Details { get; private set; } = TileDetails.Unavailable;
        public Task<TileDetails>? DetailsRequest { get; set; }
        private bool albumRemovalSelection;
        public Visibility AlbumRemovalTickVisibility => albumRemovalSelection ? Visibility.Visible : Visibility.Collapsed;

        public event PropertyChangedEventHandler? PropertyChanged;

        public void SetRowIndex(int index)
        {
            var alternate = index % 2 != 0;
            if (alternateRow == alternate)
                return;
            alternateRow = alternate;
            PropertyChanged?.Invoke(this, new(nameof(RowBackground)));
        }

        public void SetAlbumRemovalSelection(bool marked)
        {
            if (albumRemovalSelection == marked)
                return;
            albumRemovalSelection = marked;
            PropertyChanged?.Invoke(this, new(nameof(AlbumRemovalTickVisibility)));
        }

        public void SetDetails(TileDetails details)
        {
            if (Details == details)
                return;
            Details = details;
            PropertyChanged?.Invoke(this, new(nameof(Details)));
        }
    }

    private BrowseMode browseMode = BrowseMode.List;
    private bool browsingFolders;
    private bool updatingBrowser;
    private int filmstripGeneration;

    private ListViewBase ActiveMediaBrowser => browseMode switch
    {
        BrowseMode.List => DetailsList,
        BrowseMode.Gallery => Filmstrip,
        _ => Gallery
    };

    private void ChangeBrowseMode(object sender, RoutedEventArgs args)
    {
        var mode = ReferenceEquals(sender, ListModeButton) ? BrowseMode.List
            : ReferenceEquals(sender, GalleryModeButton) ? BrowseMode.Gallery : BrowseMode.Icons;
        SetBrowseMode(mode, sender is Control { FocusState: FocusState.Keyboard });
    }

    private void SetBrowseMode(BrowseMode mode, bool keepPickerFocus = false)
    {
        IconModeButton.IsChecked = mode == BrowseMode.Icons;
        ListModeButton.IsChecked = mode == BrowseMode.List;
        GalleryModeButton.IsChecked = mode == BrowseMode.Gallery;
        if (browseMode == mode)
            return;
        var selected = Selection?.Media.Id ?? selectionBeforeAlbumRemoval;
        browseMode = mode;
        RefreshMediaBrowser(selected);
        if (keepPickerFocus)
            return;
        if (SelectingAlbumMembers)
            FocusAlbumSelectionItem(selected);
        else
            FocusSelectedMedia();
    }

    private void ChangeBrowseModeShortcut(KeyRoutedEventArgs args)
    {
        if (args.Handled || catalog is null || busy || browsingFolders || titleEdit is not null || IsComposingText ||
            !KeyIsDown(VirtualKey.Control) || KeyIsDown(VirtualKey.Shift) || KeyIsDown(VirtualKey.Menu) ||
            KeyIsDown(VirtualKey.LeftWindows) || KeyIsDown(VirtualKey.RightWindows))
            return;
        BrowseMode? mode = args.Key switch
        {
            VirtualKey.Number1 => BrowseMode.List,
            VirtualKey.Number2 => BrowseMode.Gallery,
            VirtualKey.Number3 => BrowseMode.Icons,
            _ => null
        };
        if (mode is not { } target)
            return;
        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown)
            SetBrowseMode(target);
    }

    private void RefreshMediaBrowser(long? selected)
    {
        CancelAlbumAdjustmentPointer();
        var browser = ActiveMediaBrowser;
        var mediaVisibility = browsingFolders || tiles.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        updatingBrowser = true;
        try
        {
            ViewModePicker.Visibility = mediaVisibility;
            BrowserSortButton.Visibility = SelectingAlbumMembers ? Visibility.Collapsed : mediaVisibility;
            Gallery.Visibility = browser == Gallery ? mediaVisibility : Visibility.Collapsed;
            DetailsPane.Visibility = browser == DetailsList ? mediaVisibility : Visibility.Collapsed;
            FilmstripPane.Visibility = browser == Filmstrip ? mediaVisibility : Visibility.Collapsed;
            Gallery.ItemsSource = Gallery.Visibility == Visibility.Visible ? tiles : null;
            DetailsList.ItemsSource = DetailsPane.Visibility == Visibility.Visible ? tiles : null;
            Filmstrip.ItemsSource = FilmstripPane.Visibility == Visibility.Visible ? tiles : null;
            browser.SelectionMode = SelectingAlbumMembers ? ListViewSelectionMode.Multiple : ListViewSelectionMode.Single;
            if (SelectingAlbumMembers)
                RestoreAlbumRemovalSelection(browser);
            else
                browser.SelectedItem = tiles.FirstOrDefault(tile => tile.Media.Id == selected) ?? tiles.FirstOrDefault();
        }
        finally
        {
            updatingBrowser = false;
        }
        UpdateSelection();
        UpdateFilmstripPreview(SelectingAlbumMembers ? tiles.FirstOrDefault(tile => tile.Media.Id == selected) : null);
    }

    private void RestoreAlbumRemovalSelection(ListViewBase browser)
    {
        browser.SelectedItems.Clear();
        foreach (var tile in tiles)
        {
            var marked = albumRemovalIds.Contains(tile.Media.Id);
            tile.SetAlbumRemovalSelection(marked);
            if (marked)
                browser.SelectedItems.Add(tile);
        }
    }

    private void FocusSelectedMedia()
    {
        var browser = ActiveMediaBrowser;
        FocusBrowserItem(browser, browser.SelectedItem, FocusState.Programmatic);
    }

    private static void FocusBrowserItem(ListViewBase browser, object? item, FocusState focusState)
    {
        if (item is not null)
        {
            browser.UpdateLayout();
            browser.ScrollIntoView(item);
            browser.UpdateLayout();
            if (browser.ContainerFromItem(item) is Control container && container.Focus(focusState))
                return;
        }
        browser.Focus(focusState);
    }

    private void LoadListDetails(object sender, RoutedEventArgs args) => LoadListDetails((FrameworkElement)sender);

    private void UpdateListDetails(FrameworkElement sender, DataContextChangedEventArgs args) => LoadListDetails(sender);

    private async void LoadListDetails(FrameworkElement row)
    {
        if (!row.IsLoaded || row.DataContext is not Tile { Media: { Available: true } } tile)
            return;

        tile.DetailsRequest ??= Task.Run(() => ReadTileDetails(tile.Media));
        var details = await tile.DetailsRequest;
        if (row.IsLoaded && ReferenceEquals(row.DataContext, tile))
            tile.SetDetails(details);
    }

    private static TileDetails ReadTileDetails(Media media)
    {
        var facts = MediaFileFacts.Read(media);
        return facts is { Modified: DateTime modified, Size: long size }
            ? new(modified.ToLocalTime().ToString("yyyy-MM-dd HH:mm", CultureInfo.CurrentCulture), FormatBytes(size))
            : TileDetails.Unavailable;
    }

    private static string FormatBytes(long length) => length switch
    {
        < 1024 => $"{length} B",
        < 1024 * 1024 => $"{length / 1024d:0.#} KB",
        < 1024 * 1024 * 1024 => $"{length / (1024d * 1024):0.#} MB",
        _ => $"{length / (1024d * 1024 * 1024):0.#} GB"
    };

    private async void UpdateFilmstripPreview(Tile? focused = null)
    {
        var generation = ++filmstripGeneration;
        FilmstripImage.Source = null;
        FilmstripMessage.Visibility = Visibility.Collapsed;
        var tile = focused ?? Selection;
        if (FilmstripPane.Visibility == Visibility.Collapsed || tile is null)
            return;

        try
        {
            var image = tile.Media.IsVideo
                ? await DecodeVideoThumbnail(tile.Media, 1280)
                : await DecodeImage(tile.Media, 1600, false, (_, _) =>
                {
                    if (generation != filmstripGeneration)
                        return;
                    FilmstripImage.Source = null;
                    ShowFilmstripMessage("无法显示此媒体");
                });
            if (generation != filmstripGeneration || FilmstripMessage.Visibility == Visibility.Visible)
                return;
            if (image is null)
                ShowFilmstripMessage("没有视频缩略图");
            else
                FilmstripImage.Source = image;
        }
        catch (Exception error) when (MediaFailure(error))
        {
            if (generation == filmstripGeneration)
                ShowFilmstripMessage(tile.Media.Available ? "无法显示此媒体" : "媒体源不可用");
        }
    }

    private void ShowFilmstripMessage(string message)
    {
        FilmstripMessage.Text = message;
        FilmstripMessage.Visibility = Visibility.Visible;
    }
}
