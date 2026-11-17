using System.ComponentModel;
using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

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

        public Media Media { get; } = media;
        public string FileName => Media.FileName;
        public string DisplayPath => Media.DisplayPath;
        public string Label => !Media.Available ? "离线" : Media.IsVideo ? "▶ 视频" : "";
        public Visibility BadgeVisibility => Label.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        public Brush? RowBackground => index % 2 == 0 ? null : AlternateBackground;
        private string Extension => Path.GetExtension(Media.RelativePath).TrimStart('.').ToUpperInvariant();
        public string Kind => $"{Extension} {(Media.IsVideo ? "视频" : "图像")}";
        public TileDetails Details { get; private set; } = TileDetails.Unavailable;
        public Task<TileDetails>? DetailsRequest { get; set; }

        public event PropertyChangedEventHandler? PropertyChanged;

        public void SetDetails(TileDetails details)
        {
            if (Details == details)
                return;
            Details = details;
            PropertyChanged?.Invoke(this, new(nameof(Details)));
        }
    }

    private BrowseMode browseMode;
    private bool browsingFolders;
    private bool updatingBrowser;
    private int filmstripGeneration;

    private ListViewBase ActiveMediaBrowser => browseMode switch
    {
        BrowseMode.List => DetailsList,
        BrowseMode.Gallery => Filmstrip,
        _ => Gallery
    };

    private void ChangeBrowseMode(object sender, SelectionChangedEventArgs args)
    {
        if (catalog is null || sender is not ComboBox { SelectedIndex: >= 0 } picker)
            return;

        var selected = Selection?.Media.Id ?? selectionBeforeAlbumRemoval;
        browseMode = (BrowseMode)picker.SelectedIndex;
        RefreshMediaBrowser(selected);
        if (SelectingAlbumMembers)
            FocusAlbumSelectionItem(selected);
        else
            FocusSelectedMedia();
    }

    private void RefreshMediaBrowser(long? selected)
    {
        var browser = ActiveMediaBrowser;
        var mediaVisibility = browsingFolders ? Visibility.Collapsed : Visibility.Visible;
        updatingBrowser = true;
        try
        {
            ViewModePicker.Visibility = mediaVisibility;
            Gallery.Visibility = browser == Gallery ? mediaVisibility : Visibility.Collapsed;
            DetailsPane.Visibility = browser == DetailsList ? mediaVisibility : Visibility.Collapsed;
            FilmstripPane.Visibility = browser == Filmstrip ? mediaVisibility : Visibility.Collapsed;
            Gallery.ItemsSource = Gallery.Visibility == Visibility.Visible ? tiles : null;
            DetailsList.ItemsSource = DetailsPane.Visibility == Visibility.Visible ? tiles : null;
            Filmstrip.ItemsSource = FilmstripPane.Visibility == Visibility.Visible ? tiles : null;
            browser.SelectionMode = SelectingAlbumMembers ? ListViewSelectionMode.Multiple : ListViewSelectionMode.Single;
            if (SelectingAlbumMembers)
            {
                browser.SelectedItems.Clear();
                foreach (var tile in tiles.Where(tile => albumRemovalIds.Contains(tile.Media.Id)))
                    browser.SelectedItems.Add(tile);
            }
            else
            {
                browser.SelectedItem = tiles.Find(tile => tile.Media.Id == selected) ?? tiles.FirstOrDefault();
            }
        }
        finally
        {
            updatingBrowser = false;
        }
        UpdateSelection();
        UpdateFilmstripPreview(SelectingAlbumMembers ? tiles.Find(tile => tile.Media.Id == selected) : null);
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
        try
        {
            var file = new FileInfo(MediaFiles.OpenPath(media));
            return new(file.LastWriteTime.ToString("yyyy-MM-dd HH:mm", CultureInfo.CurrentCulture), FormatBytes(file.Length));
        }
        catch (Exception error) when (MediaFailure(error))
        {
            return TileDetails.Unavailable;
        }
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
                ShowFilmstripMessage(tile.Media.Available ? "无法显示此媒体" : "来源不可用");
        }
    }

    private void ShowFilmstripMessage(string message)
    {
        FilmstripMessage.Text = message;
        FilmstripMessage.Visibility = Visibility.Visible;
    }
}
