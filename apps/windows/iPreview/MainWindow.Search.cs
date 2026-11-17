using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;
using Windows.UI.Core;

namespace IPreview;

public sealed partial class MainWindow
{
    private bool searchOpen;
    private bool searchAllSources;
    private bool searchExact;
    private bool consumingExactPrefix;
    private int searchRevision;
    private GlobalSearchScope searchResultKind;
    private List<GlobalSearchHit> searchHits = [];
    private Control? searchReturnFocus;
    private TextBox? composingInput;

    private bool IsComposingText => composingInput is { FocusState: not FocusState.Unfocused };

    private IEnumerable<Media> ScopeMedia()
    {
        var location = current;
        if (location.Album is long album)
            return albumMembers.GetValueOrDefault(album) ?? [];
        return media.Where(item => item.Present
            && (location.Source is null || item.Source.Id == location.Source)
            && (location.Folder is null || item.RelativePath.StartsWith(location.Folder, StringComparison.Ordinal)));
    }

    private void GoToLibrary(object sender, RoutedEventArgs args) => NavigateFromContent(Library);

    private void FindInLibrary(KeyRoutedEventArgs args)
    {
        if (!IsFindShortcut(args) || catalog is null || busy || titleEdit is not null ||
            SelectingAlbumMembers || IsComposingText)
            return;

        args.Handled = true;
        if (!args.KeyStatus.WasKeyDown)
            OpenSearch(allSources: KeyIsDown(VirtualKey.Shift));
    }

    private static bool KeyIsDown(VirtualKey key) =>
        (InputKeyboardSource.GetKeyStateForCurrentThread(key) & CoreVirtualKeyStates.Down) != 0;

    private static bool IsFindShortcut(KeyRoutedEventArgs args) =>
        args.Key == VirtualKey.F && KeyIsDown(VirtualKey.Control) && !KeyIsDown(VirtualKey.Menu) &&
        !KeyIsDown(VirtualKey.LeftWindows) && !KeyIsDown(VirtualKey.RightWindows);

    private void TextCompositionStarted(TextBox sender, TextCompositionStartedEventArgs args) => composingInput = sender;

    private void TextCompositionEnded(TextBox sender, TextCompositionEndedEventArgs args)
    {
        if (ReferenceEquals(sender, composingInput))
            composingInput = null;
        if (ReferenceEquals(sender, SearchInput) && searchOpen)
            DispatcherQueue.TryEnqueue(CommitSearchInput);
    }

    private void ShowGlobalSearch(object sender, RoutedEventArgs args) => OpenSearch(allSources: true);

    private async void OpenSearch(bool allSources)
    {
        if (catalog is null || busy || titleEdit is not null || SelectingAlbumMembers)
            return;
        if (!searchOpen)
        {
            searchReturnFocus = FocusManager.GetFocusedElement(Root.XamlRoot) as Control;
            searchResultKind = GlobalSearchScope.All;
            SearchFiles.IsChecked = SearchDirectories.IsChecked = false;
            SearchInput.Text = "";
            searchExact = false;
            UpdateSearchExactIndicator();
            searchOpen = true;
            SearchOverlay.Visibility = Visibility.Visible;
            LibraryView.IsHitTestVisible = false;
        }

        var refresh = ChangeSearchDomain(allSources);
        if (!SearchInput.Focus(FocusState.Programmatic))
        {
            DispatcherQueue.TryEnqueue(() =>
            {
                if (SearchOverlay.Visibility == Visibility.Visible)
                    SearchInput.Focus(FocusState.Programmatic);
            });
        }
        await refresh;
    }

    private Task ChangeSearchDomain(bool allSources)
    {
        searchAllSources = allSources;
        var label = allSources ? "搜索所有来源" : "搜索当前范围";
        SearchInput.PlaceholderText = label;
        AutomationProperties.SetName(SearchInput, label);
        SearchDomain.Content = allSources ? "Ctrl+0 全局" : "Ctrl+0 当前范围";
        ToolTipService.SetToolTip(SearchDomain, allSources ? "切换到当前范围" : "切换到全局");
        return RefreshSearch();
    }

    private async void SwitchSearchDomainClick(object sender, RoutedEventArgs args)
    {
        if (searchOpen)
            await SwitchSearchDomain();
    }

    private async void SwitchSearchDomainShortcut(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        if (SearchOverlay.Visibility != Visibility.Visible || IsComposingText)
            return;
        args.Handled = true;
        await SwitchSearchDomain();
    }

    private Task SwitchSearchDomain()
    {
        SearchInput.Focus(FocusState.Programmatic);
        return ChangeSearchDomain(!searchAllSources);
    }

    private void CloseSearchButton(object sender, RoutedEventArgs args) => CloseSearch();
    private void DismissSearchFromBackdrop(object sender, TappedRoutedEventArgs args) => CloseSearch();

    private void CloseSearch(bool restoreFocus = true)
    {
        searchOpen = false;
        searchRevision++;
        SearchOverlay.Visibility = Visibility.Collapsed;
        LibraryView.IsHitTestVisible = true;
        SetSearchHits([]);
        SearchStatus.Visibility = Visibility.Collapsed;
        var previousFocus = searchReturnFocus;
        searchReturnFocus = null;
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

    private void SearchEdited(object sender, TextChangedEventArgs args)
    {
        if (!consumingExactPrefix)
            CommitSearchInput();
    }

    private async void CommitSearchInput()
    {
        if (!searchOpen || IsComposingText)
            return;

        var input = SearchInput.Text;
        var parsed = GlobalSearchTerm.Parse(input);
        if (!searchExact && parsed.Exact)
        {
            searchExact = true;
            consumingExactPrefix = true;
            var prefixLength = input.TrimEnd().Length - parsed.Text.Length;
            var caret = Math.Clamp(SearchInput.SelectionStart - prefixLength, 0, parsed.Text.Length);
            SearchInput.Text = parsed.Text;
            SearchInput.SelectionStart = caret;
            consumingExactPrefix = false;
            UpdateSearchExactIndicator();
        }
        await RefreshSearch();
    }

    private void UpdateSearchExactIndicator()
    {
        SearchExactBadge.Visibility = searchExact ? Visibility.Visible : Visibility.Collapsed;
        SearchExactHint.Visibility = searchExact ? Visibility.Collapsed : Visibility.Visible;
        SearchKeyHelp.Text = searchExact
            ? "↑ / ↓ 选择    Enter 前往    Space 预览    Esc 取消精确匹配"
            : "↑ / ↓ 选择    Enter 前往    Space 预览    Esc 关闭";
    }

    private async Task RefreshSearch()
    {
        var generation = ++searchRevision;
        var query = new GlobalSearchTerm(SearchInput.Text.Trim(), searchExact);
        SetSearchHits([]);
        SearchStatus.Visibility = query.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        if (query.Text.Length == 0)
            return;

        SearchStatus.Text = "正在搜索…";
        await Task.Delay(100);
        if (generation != searchRevision)
            return;

        var kind = searchResultKind;
        IEnumerable<Source> searchSources = sources.Values;
        IEnumerable<Media> searchMedia = media;
        string? folderRoot = null;
        if (!searchAllSources)
        {
            searchMedia = ScopeMedia();
            if (current.Album is not null)
            {
                if (kind == GlobalSearchScope.Directories)
                {
                    SearchStatus.Text = "没有匹配结果";
                    return;
                }
                kind = GlobalSearchScope.Files;
            }
            else if (current.Source is long source)
            {
                searchSources = [sources[source]];
                folderRoot = current.Folder;
            }
        }
        try
        {
            var hits = await Task.Run(() => MediaSearch.Find(searchSources, searchMedia, query, kind, folderRoot));
            if (generation != searchRevision)
                return;
            SetSearchHits(hits);
            SearchStatus.Visibility = hits.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            SearchStatus.Text = "没有匹配结果";
        }
        catch (Exception error) when (error is InvalidOperationException or EntryPointNotFoundException or DllNotFoundException)
        {
            if (generation == searchRevision)
                SearchStatus.Text = error.Message;
        }
    }

    private void SetSearchHits(List<GlobalSearchHit> hits)
    {
        searchHits = hits;
        SearchResults.ItemsSource = hits;
        SearchResults.SelectedItem = hits.FirstOrDefault();
        SearchResults.Visibility = hits.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void ResultKindClicked(object sender, RoutedEventArgs args) =>
        await ChangeResultKind(ReferenceEquals(sender, SearchFiles) ? GlobalSearchScope.Files : GlobalSearchScope.Directories);

    private async void ResultKindShortcut(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        if (SearchOverlay.Visibility != Visibility.Visible || IsComposingText)
            return;
        args.Handled = true;
        await ChangeResultKind(sender.Key == VirtualKey.Number1 ? GlobalSearchScope.Files : GlobalSearchScope.Directories);
    }

    private Task ChangeResultKind(GlobalSearchScope kind)
    {
        searchResultKind = searchResultKind == kind ? GlobalSearchScope.All : kind;
        SearchFiles.IsChecked = searchResultKind == GlobalSearchScope.Files;
        SearchDirectories.IsChecked = searchResultKind == GlobalSearchScope.Directories;
        SearchInput.Focus(FocusState.Programmatic);
        return RefreshSearch();
    }

    private async void SearchKeyDown(object sender, KeyRoutedEventArgs args)
    {
        var editingQuery = SearchInput.FocusState != FocusState.Unfocused;
        if (editingQuery && IsComposingText)
            return;
        if (IsFindShortcut(args))
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                OpenSearch(allSources: KeyIsDown(VirtualKey.Shift));
            return;
        }
        var focused = FocusManager.GetFocusedElement(Root.XamlRoot);
        var resultFocused = focused is ListViewItem row && SearchResults.ItemFromContainer(row) is GlobalSearchHit;
        switch (args.Key)
        {
            case VirtualKey.Up when editingQuery || resultFocused:
            case VirtualKey.Down when editingQuery || resultFocused:
                if (searchHits.Count == 0)
                    return;
                args.Handled = true;
                var direction = args.Key == VirtualKey.Up ? -1 : 1;
                var index = editingQuery
                    ? direction < 0 ? searchHits.Count - 1 : 0
                    : Math.Clamp(SearchResults.SelectedIndex + direction, 0, searchHits.Count - 1);
                FocusSearchResult(searchHits[index]);
                break;
            case VirtualKey.Enter when editingQuery || resultFocused:
                if (SearchResults.SelectedItem is not GlobalSearchHit result)
                    return;
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    OpenSearchResult(result);
                break;
            case VirtualKey.Space when resultFocused:
                if (SearchResults.SelectedItem is not GlobalSearchHit { Media: { } item })
                    return;
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown)
                    OpenSearchPreview(item);
                break;
            case VirtualKey.Escape:
                args.Handled = true;
                if (args.KeyStatus.WasKeyDown)
                    return;
                if (!searchExact)
                {
                    CloseSearch();
                    return;
                }
                searchExact = false;
                UpdateSearchExactIndicator();
                SearchInput.Focus(FocusState.Programmatic);
                await RefreshSearch();
                break;
        }
    }

    private void FocusSearchResult(GlobalSearchHit result)
    {
        SearchResults.SelectedItem = result;
        FocusBrowserItem(SearchResults, result, FocusState.Keyboard);
    }

    private void OpenSearchResult(GlobalSearchHit result)
    {
        var target = current;
        if (searchAllSources || current.Album is null)
        {
            var label = result.Folder is { } folder
                ? SourceRename.SplitPath(folder.TrimEnd('/')).Leaf
                : result.Source.Name;
            target = new Navigation(label, Source: result.Source.Id, Folder: result.Folder);
        }
        CloseSearch(restoreFocus: false);
        NavigateTo(target, result.Media?.Id);
        if (browsingFolders)
            FocusSourceFolder();
        else
            FocusSelectedMedia();
    }

    private void OpenSearchPreview(Media item)
    {
        var files = searchHits.Select(hit => hit.Media).OfType<Media>();
        var results = files.Select((media, index) => new Tile(media, index)).ToList();
        var selected = results.FindIndex(tile => tile.Media.Id == item.Id);
        SearchOverlay.Visibility = Visibility.Collapsed;
        OpenPreview(results, selected, new(BrowseMode.List, 1));
    }

    private bool RestoreSearchAfterPreview(long? selectedId)
    {
        if (!searchOpen)
            return false;
        SearchOverlay.Visibility = Visibility.Visible;
        if (searchHits.Find(hit => hit.Media?.Id == selectedId && hit.Media is not null) is { } result)
            FocusSearchResult(result);
        else
            SearchInput.Focus(FocusState.Programmatic);
        return true;
    }
}
