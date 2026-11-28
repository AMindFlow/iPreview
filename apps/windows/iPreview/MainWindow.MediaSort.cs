using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;

namespace IPreview;

public sealed partial class MainWindow
{
    private readonly MediaSortSession browserSort = new();
    private readonly MediaSortSession previewSort = new();
    private List<Tile> originalPreviewTiles = [];
    private int previewNeighborGeneration;

    private void InitializeMediaSort()
    {
        MediaSortMenu.Attach(BrowserSortButton, () => browserSort.Order, order =>
        {
            if (busy || SelectingAlbumMembers || browserSort.Order == order)
                return;
            browserSort.Order = order;
            ShowItems(Selection?.Media.Id, revealSelection: true);
        });
        MediaSortMenu.Attach(PreviewSortButton, () => previewSort.Order, ChoosePreviewSort);
    }

    private async void SortBrowserByFileFacts(ObservableCollection<Tile> original)
    {
        var ordered = await browserSort.ArrangeAsync(original, tile => tile.Media);
        if (ordered is null || !ReferenceEquals(original, tiles))
            return;
        var selected = Selection?.Media.Id;
        var hadBrowserFocus = false;
        for (var element = FocusManager.GetFocusedElement(Root.XamlRoot) as DependencyObject;
             element is not null; element = VisualTreeHelper.GetParent(element))
        {
            if (element == ActiveMediaBrowser)
            {
                hadBrowserFocus = true;
                break;
            }
        }

        tiles = new(ordered);
        for (var index = 0; index < ordered.Count; index++)
            ordered[index].SetRowIndex(index);
        RefreshMediaBrowser(selected);
        if (hadBrowserFocus && !searchOpen && previewIndex < 0)
            FocusSelectedMedia();
    }

    private async void ChoosePreviewSort(MediaSort order)
    {
        if (previewIndex < 0 || previewClosing || previewSort.Order == order)
            return;
        previewSort.Order = order;
        var original = originalPreviewTiles;
        var ordered = await previewSort.ArrangeAsync(original, tile => tile.Media);
        if (ordered is null || !ReferenceEquals(original, originalPreviewTiles) || previewIndex < 0 || previewClosing)
            return;

        var selected = previewTiles[previewIndex];
        previewTiles = ordered;
        previewIndex = ordered.IndexOf(selected);
        if (ComicReadingActive)
            ShowPreview(previewIndex, poster: null);
        else
        {
            UpdateImagePreviewIndex(spread: null);
            UpdatePreviewNavigation();
            RefreshPreviewNeighbors();
            RestartImageSlideClock();
        }
        if (!previewVideoLocked)
            PreviewCanvas.Focus(FocusState.Programmatic);
    }

    private void RefreshPreviewNeighbors()
    {
        var generation = ++previewNeighborGeneration;
        if (ComicReadingActive || musicPreview is not null)
        {
            NeighborLeft.Source = NeighborRight.Source = NeighborTop.Source = NeighborBottom.Source = null;
            return;
        }
        LoadNeighbor(NeighborLeft, BrowseDirection.Left, generation);
        LoadNeighbor(NeighborRight, BrowseDirection.Right, generation);
        LoadNeighbor(NeighborTop, BrowseDirection.Up, generation);
        LoadNeighbor(NeighborBottom, BrowseDirection.Down, generation);
    }
}
