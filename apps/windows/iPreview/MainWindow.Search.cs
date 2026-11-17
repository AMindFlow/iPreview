using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI.Core;

namespace IPreview;

public sealed partial class MainWindow
{
    private bool globalSearchOpen;
    private int globalSearchRevision;
    private GlobalSearchScope globalSearchScope;
    private List<GlobalSearchHit> globalSearchHits = [];
    private Control? globalSearchReturnFocus;
    private TextBox? scopedSearchInput;
    private TextBox? composingInput;

    private bool IsComposingText => composingInput is { FocusState: not FocusState.Unfocused };

    private IEnumerable<Media> ScopeMedia()
    {
        if (current.Album is long album)
            return albumMembers.GetValueOrDefault(album) ?? [];
        return media.Where(item => item.Present
            && (current.Source is null || item.Source.Id == current.Source)
            && (current.Folder is null || item.RelativePath.StartsWith(current.Folder, StringComparison.Ordinal)));
    }

    private void GoToLibrary(object sender, RoutedEventArgs args) => NavigateFromContent(Library);

    private void FindInLibrary(KeyRoutedEventArgs args)
    {
        if (!IsFindShortcut(args) || catalog is null || busy || globalSearchOpen || titleEdit is not null ||
            SelectingAlbumMembers || IsComposingText)
            return;

        var global = KeyIsDown(VirtualKey.Shift);
        if (!global && Query.Visibility != Visibility.Visible)
            return;
        args.Handled = true;
        if (args.KeyStatus.WasKeyDown)
            return;
        if (global)
        {
            OpenGlobalSearch();
            return;
        }

        Query.ApplyTemplate();
        FindQueryInput(Query)?.Focus(FocusState.Keyboard);
    }

    private static bool KeyIsDown(VirtualKey key) =>
        (InputKeyboardSource.GetKeyStateForCurrentThread(key) & CoreVirtualKeyStates.Down) != 0;

    private static bool IsFindShortcut(KeyRoutedEventArgs args) =>
        args.Key == VirtualKey.F && KeyIsDown(VirtualKey.Control) && !KeyIsDown(VirtualKey.Menu) &&
        !KeyIsDown(VirtualKey.LeftWindows) && !KeyIsDown(VirtualKey.RightWindows);

    private static TextBox? FindQueryInput(DependencyObject parent)
    {
        if (parent is TextBox input)
            return input;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            if (FindQueryInput(VisualTreeHelper.GetChild(parent, i)) is { } textBox)
                return textBox;
        }
        return null;
    }

    private void ObserveScopedSearchFocus(UIElement sender, GettingFocusEventArgs args)
    {
        if (args.NewFocusedElement is not TextBox input || ReferenceEquals(input, scopedSearchInput))
            return;
        if (scopedSearchInput is not null)
        {
            scopedSearchInput.TextCompositionStarted -= TextCompositionStarted;
            scopedSearchInput.TextCompositionEnded -= TextCompositionEnded;
        }
        scopedSearchInput = input;
        input.TextCompositionStarted += TextCompositionStarted;
        input.TextCompositionEnded += TextCompositionEnded;
    }

    private void TextCompositionStarted(TextBox sender, TextCompositionStartedEventArgs args) => composingInput = sender;

    private void TextCompositionEnded(TextBox sender, TextCompositionEndedEventArgs args)
    {
        if (ReferenceEquals(sender, composingInput))
            composingInput = null;
    }

    private void ShowGlobalSearch(object sender, RoutedEventArgs args) => OpenGlobalSearch();

    private void OpenGlobalSearch()
    {
        if (catalog is null || busy || globalSearchOpen)
            return;

        globalSearchReturnFocus = FocusManager.GetFocusedElement(Root.XamlRoot) as Control;
        globalSearchScope = GlobalSearchScope.All;
        GlobalFileScope.IsChecked = GlobalDirectoryScope.IsChecked = false;
        GlobalSearchInput.Text = "";
        GlobalSearchExactBadge.Visibility = Visibility.Collapsed;
        globalSearchOpen = true;
        GlobalSearchOverlay.Visibility = Visibility.Visible;
        LibraryView.IsHitTestVisible = false;
        DispatcherQueue.TryEnqueue(() =>
        {
            if (GlobalSearchOverlay.Visibility == Visibility.Visible)
                GlobalSearchInput.Focus(FocusState.Programmatic);
        });
    }

    private void CloseGlobalSearchButton(object sender, RoutedEventArgs args) => CloseGlobalSearch();
    private void DismissGlobalSearchFromBackdrop(object sender, TappedRoutedEventArgs args) => CloseGlobalSearch();

    private void CloseGlobalSearch(bool restoreFocus = true)
    {
        globalSearchOpen = false;
        globalSearchRevision++;
        GlobalSearchOverlay.Visibility = Visibility.Collapsed;
        LibraryView.IsHitTestVisible = true;
        SetGlobalSearchHits([]);
        GlobalSearchStatus.Visibility = Visibility.Collapsed;
        var previousFocus = globalSearchReturnFocus;
        globalSearchReturnFocus = null;
        if (!restoreFocus)
            return;
        if (previousFocus is { IsEnabled: true, IsLoaded: true, Visibility: Visibility.Visible } &&
            previousFocus.Focus(FocusState.Programmatic))
            return;

        if (browsingFolders)
            FocusSourceFolder();
        else if (Selection is not null)
            FocusSelectedMedia();
        else
            LibraryHomeButton.Focus(FocusState.Programmatic);
    }

    private async void GlobalSearchEdited(object sender, TextChangedEventArgs args)
    {
        if (globalSearchOpen)
            await RefreshGlobalSearch();
    }

    private async Task RefreshGlobalSearch()
    {
        var generation = ++globalSearchRevision;
        var query = GlobalSearchTerm.Parse(GlobalSearchInput.Text);
        GlobalSearchExactBadge.Visibility = query.Exact ? Visibility.Visible : Visibility.Collapsed;
        SetGlobalSearchHits([]);
        GlobalSearchStatus.Visibility = query.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (query.Text.Length == 0)
            return;

        GlobalSearchStatus.Text = "正在搜索…";
        await Task.Delay(100);
        if (generation != globalSearchRevision)
            return;

        var scope = globalSearchScope;
        var sourceSnapshot = sources.Values;
        var mediaSnapshot = media;
        try
        {
            var hits = await Task.Run(() => MediaSearch.FindGlobal(sourceSnapshot, mediaSnapshot, query, scope));
            if (generation != globalSearchRevision)
                return;
            SetGlobalSearchHits(hits);
            GlobalSearchStatus.Visibility = hits.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            GlobalSearchStatus.Text = "没有匹配结果";
        }
        catch (Exception error) when (error is InvalidOperationException or EntryPointNotFoundException or DllNotFoundException)
        {
            if (generation == globalSearchRevision)
                GlobalSearchStatus.Text = error.Message;
        }
    }

    private void SetGlobalSearchHits(List<GlobalSearchHit> hits)
    {
        globalSearchHits = hits;
        GlobalSearchResults.ItemsSource = hits;
        GlobalSearchResults.SelectedItem = hits.FirstOrDefault();
        GlobalSearchResults.Visibility = hits.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void GlobalScopeClicked(object sender, RoutedEventArgs args) =>
        await ChangeGlobalSearchScope(ReferenceEquals(sender, GlobalFileScope) ? GlobalSearchScope.Files : GlobalSearchScope.Directories);

    private async void GlobalScopeShortcut(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        if (GlobalSearchOverlay.Visibility != Visibility.Visible || IsComposingText)
            return;
        args.Handled = true;
        await ChangeGlobalSearchScope(sender.Key == VirtualKey.Number1 ? GlobalSearchScope.Files : GlobalSearchScope.Directories);
    }

    private Task ChangeGlobalSearchScope(GlobalSearchScope scope)
    {
        globalSearchScope = globalSearchScope == scope ? GlobalSearchScope.All : scope;
        GlobalFileScope.IsChecked = globalSearchScope == GlobalSearchScope.Files;
        GlobalDirectoryScope.IsChecked = globalSearchScope == GlobalSearchScope.Directories;
        GlobalSearchInput.Focus(FocusState.Programmatic);
        return RefreshGlobalSearch();
    }

    private void GlobalSearchKeyDown(object sender, KeyRoutedEventArgs args)
    {
        var editingQuery = GlobalSearchInput.FocusState != FocusState.Unfocused;
        if (editingQuery && IsComposingText)
            return;
        if (IsFindShortcut(args) && KeyIsDown(VirtualKey.Shift))
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                GlobalSearchInput.Focus(FocusState.Keyboard);
            return;
        }
        var focused = FocusManager.GetFocusedElement(Root.XamlRoot);
        var resultFocused = focused is ListViewItem row && GlobalSearchResults.ItemFromContainer(row) is GlobalSearchHit;
        switch (args.Key)
        {
            case VirtualKey.Up when editingQuery || resultFocused:
            case VirtualKey.Down when editingQuery || resultFocused:
                if (globalSearchHits.Count == 0)
                    return;
                args.Handled = true;
                var direction = args.Key == VirtualKey.Up ? -1 : 1;
                var index = editingQuery
                    ? direction < 0 ? globalSearchHits.Count - 1 : 0
                    : Math.Clamp(GlobalSearchResults.SelectedIndex + direction, 0, globalSearchHits.Count - 1);
                FocusGlobalResult(globalSearchHits[index]);
                break;
            case VirtualKey.Enter when editingQuery || resultFocused:
                if (GlobalSearchResults.SelectedItem is not GlobalSearchHit result)
                    return;
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    OpenGlobalSearchResult(result);
                break;
            case VirtualKey.Space when resultFocused:
                if (GlobalSearchResults.SelectedItem is not GlobalSearchHit { Media: { } item })
                    return;
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    OpenGlobalSearchPreview(item);
                break;
            case VirtualKey.Escape:
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    CloseGlobalSearch();
                break;
        }
    }

    private void FocusGlobalResult(GlobalSearchHit result)
    {
        GlobalSearchResults.SelectedItem = result;
        FocusBrowserItem(GlobalSearchResults, result, FocusState.Keyboard);
    }

    private void OpenGlobalSearchResult(GlobalSearchHit result)
    {
        CloseGlobalSearch(restoreFocus: false);
        var label = result.Folder is { } folder
            ? SourceRename.SplitPath(folder.TrimEnd('/')).Leaf
            : result.Source.Name;
        var target = new Navigation(label, Source: result.Source.Id, Folder: result.Folder);
        NavigateTo(target, result.Media?.Id);
        if (browsingFolders)
            FocusSourceFolder();
        else
            FocusSelectedMedia();
    }

    private void OpenGlobalSearchPreview(Media item)
    {
        var files = globalSearchHits.Select(hit => hit.Media).OfType<Media>();
        var results = files.Select((media, index) => new Tile(media, index)).ToList();
        var selected = results.FindIndex(tile => tile.Media.Id == item.Id);
        GlobalSearchOverlay.Visibility = Visibility.Collapsed;
        OpenPreview(results, selected, new(BrowseMode.List, 1));
    }

    private bool RestoreGlobalSearchAfterPreview(long? selectedId)
    {
        if (!globalSearchOpen)
            return false;
        GlobalSearchOverlay.Visibility = Visibility.Visible;
        if (globalSearchHits.Find(hit => hit.Media?.Id == selectedId && hit.Media is not null) is { } result)
            FocusGlobalResult(result);
        else
            GlobalSearchInput.Focus(FocusState.Programmatic);
        return true;
    }
}
