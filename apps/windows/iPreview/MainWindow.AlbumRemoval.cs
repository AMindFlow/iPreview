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
        RefreshMediaBrowser(selectionBeforeAlbumRemoval);
        FocusAlbumSelectionItem(selectionBeforeAlbumRemoval);
    }

    private void FocusAlbumSelectionItem(long? mediaId) =>
        FocusBrowserItem(ActiveMediaBrowser, tiles.Find(tile => tile.Media.Id == mediaId) ?? tiles.FirstOrDefault(),
            FocusState.Programmatic);

    private void LibraryKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key != VirtualKey.Escape || !SelectingAlbumMembers)
            return;
        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown)
            CancelAlbumSelection(sender, args);
    }

    private void CancelAlbumSelection(object sender, RoutedEventArgs args)
    {
        var previous = selectionBeforeAlbumRemoval;
        ClearAlbumSelection();
        RefreshMediaBrowser(previous);
        FocusSelectedMedia();
    }

    private void ClearAlbumSelection()
    {
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
        if (current.Album is not long album)
            return;

        var batch = SelectingAlbumMembers;
        IReadOnlyCollection<long> ids = batch ? albumRemovalIds : Selection is { } tile ? [tile.Media.Id] : [];
        if (ids.Count == 0)
            return;
        try
        {
            Database.RemoveFromAlbum(album, ids);
            var previous = selectionBeforeAlbumRemoval;
            ClearAlbumSelection();
            Reload(previous);
            if (batch && tiles.Count == 0)
                EmptyAlbumAddButton.Focus(FocusState.Programmatic);
            else if (batch)
                FocusSelectedMedia();
        }
        catch (InvalidOperationException error) { ShowNotice("无法移除引用", error.Message); }
    }
}
