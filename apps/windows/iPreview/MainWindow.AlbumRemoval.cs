using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private long? selectionAlbum;
    private long? selectionBeforeAlbumRemoval;
    private readonly HashSet<long> albumRemovalIds = [];

    private bool SelectingAlbumMembers => selectionAlbum.HasValue;

    private void BeginAlbumSelection(object sender, RoutedEventArgs args)
    {
        selectionAlbum = current.Album;
        selectionBeforeAlbumRemoval = Selection?.Media.Id;
        ShowItems(selectionBeforeAlbumRemoval);
        FocusAlbumSelectionItem(selectionBeforeAlbumRemoval);
    }

    private void FocusAlbumSelectionItem(long? mediaId) =>
        FocusBrowserItem(ActiveMediaBrowser, tiles.FirstOrDefault(tile => tile.Media.Id == mediaId) ?? tiles.FirstOrDefault(),
            FocusState.Programmatic);

    private void LibraryKeyDown(object sender, KeyRoutedEventArgs args)
    {
        FindInLibrary(args);
        ChangeBrowseModeShortcut(args);
        if (args.Key != VirtualKey.Escape || !SelectingAlbumMembers)
            return;
        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown)
        {
            if (albumPress?.Dragging == true)
                CancelAlbumAdjustmentPointer();
            else
                CancelAlbumSelection(sender, args);
        }
    }

    private void CancelAlbumSelection(object sender, RoutedEventArgs args)
    {
        var previous = selectionBeforeAlbumRemoval;
        ClearAlbumSelection();
        ShowItems(previous, revealSelection: true);
    }

    private void ClearAlbumSelection()
    {
        CancelAlbumAdjustmentPointer();
        if (SelectingAlbumMembers)
        {
            foreach (var tile in tiles)
                tile.SetAlbumRemovalSelection(false);
        }
        selectionAlbum = null;
        selectionBeforeAlbumRemoval = null;
        albumRemovalIds.Clear();
    }

    private void UpdateAlbumSelectionTools()
    {
        BrowseTools.Visibility = SelectingAlbumMembers ? Visibility.Collapsed : Visibility.Visible;
        AlbumSelectionTools.Visibility = SelectingAlbumMembers ? Visibility.Visible : Visibility.Collapsed;
        if (!SelectingAlbumMembers)
            return;
        AlbumSelectionCount.Text = $"已选 {albumRemovalIds.Count} 项";
        RemoveAlbumSelectionButton.IsEnabled = albumRemovalIds.Count > 0;
    }

    private void RemoveFromAlbum(object sender, RoutedEventArgs args)
    {
        if (selectionAlbum is not long album || albumRemovalIds.Count == 0)
            return;
        try
        {
            Database.RemoveFromAlbum(album, albumRemovalIds);
            var previous = selectionBeforeAlbumRemoval;
            ClearAlbumSelection();
            Reload(previous);
            if (tiles.Count == 0)
                EmptyAlbumAddButton.Focus(FocusState.Programmatic);
            else
                FocusSelectedMedia();
        }
        catch (InvalidOperationException error) { ShowNotice("无法移除引用", error.Message); }
    }
}
