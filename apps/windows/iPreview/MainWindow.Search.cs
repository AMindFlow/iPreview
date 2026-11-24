using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Data;
using Windows.System;
using Windows.UI.Core;

namespace IPreview;

public sealed partial class MainWindow
{
    private bool searchOpen;
    private bool searchAllSources;
    private bool searchExact;
    private bool updatingSearchInput;
    private int searchRevision;
    private GlobalSearchScope searchResultKind;
    private List<GlobalSearchHit> searchHits = [];
    private List<SourceAlbumTag> searchTagSuggestions = [];
    private readonly List<long> searchTagIds = [];
    private bool suggestingTags;

    private sealed class SearchResultGroup(SearchResultCategory category, IEnumerable<GlobalSearchHit> hits)
        : List<GlobalSearchHit>(hits)
    {
        public string Key { get; } = category switch
        {
            SearchResultCategory.Creator => "创作者",
            SearchResultCategory.Album => "专辑",
            SearchResultCategory.Directory => "目录",
            _ => "文件"
        };
    }
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
            searchTagIds.Clear();
            UpdateSearchTagStack();
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
        var label = allSources ? "搜索所有媒体源" : "搜索当前范围";
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
        SearchTagsFlyout.Hide();
        SearchOverlay.Visibility = Visibility.Collapsed;
        LibraryView.IsHitTestVisible = true;
        SetSearchHits([]);
        SetTagSuggestions(null);
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
        if (!updatingSearchInput)
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
            updatingSearchInput = true;
            var prefixLength = input.TrimEnd().Length - parsed.Text.Length;
            var caret = Math.Clamp(SearchInput.SelectionStart - prefixLength, 0, parsed.Text.Length);
            SearchInput.Text = parsed.Text;
            SearchInput.SelectionStart = caret;
            updatingSearchInput = false;
            UpdateSearchExactIndicator();
        }
        await RefreshSearch();
    }

    private void UpdateSearchExactIndicator()
    {
        SearchExactBadge.Visibility = searchExact ? Visibility.Visible : Visibility.Collapsed;
        SearchExactHint.Visibility = searchExact ? Visibility.Collapsed : Visibility.Visible;
        UpdateSearchKeyHelp();
    }

    private void UpdateSearchKeyHelp()
    {
        SearchKeyHelp.Text = suggestingTags ? "↑ / ↓ 选择    Enter 应用标签" : searchExact
            ? "↑ / ↓ 选择    Enter 前往    Space 预览    Esc 取消精确匹配"
            : "↑ / ↓ 选择    Enter 前往    Space 预览    Esc 关闭    # 筛选标签";
    }

    private async Task RefreshSearch()
    {
        var generation = ++searchRevision;
        var input = SearchInput.Text;
        var query = new GlobalSearchTerm(input.Trim(), searchExact);
        SetSearchHits([]);
        if (SearchTagTrigger(input) is int marker)
        {
            SetTagSuggestions(SourceAlbumTag.Suggestions(input[(marker + 1)..], sourceAlbumIndex.Tags));
            SearchStatus.Visibility = searchTagSuggestions.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            SearchStatus.Text = "没有匹配标签";
            return;
        }
        SetTagSuggestions(null);
        var taggedAlbums = searchTagIds.Count == 0 ? null
            : sourceAlbumIndex.AlbumsMatchingAnyTagIds(searchTagIds.ToHashSet());
        var hasQuery = query.Text.Length > 0 || taggedAlbums is not null;
        SearchStatus.Visibility = hasQuery ? Visibility.Visible : Visibility.Collapsed;
        if (!hasQuery)
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
            var hits = await Task.Run(() => MediaSearch.Find(searchSources, searchMedia, query, kind, folderRoot, taggedAlbums));
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
        var groups = hits.GroupBy(hit => hit.Category).OrderBy(group => group.Key)
            .Select(group => new SearchResultGroup(group.Key, group)).ToList();
        searchHits = groups.SelectMany(group => group).ToList();
        SearchResults.ItemsSource = groups.Count == 0 ? null
            : new CollectionViewSource { Source = groups, IsSourceGrouped = true }.View;
        SearchResults.SelectedItem = searchHits.FirstOrDefault();
        SearchResults.Visibility = searchHits.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private void SetTagSuggestions(List<SourceAlbumTag>? suggestions)
    {
        suggestingTags = suggestions is not null;
        UpdateSearchKeyHelp();
        searchTagSuggestions = suggestions ?? [];
        SearchTagSuggestions.ItemsSource = searchTagSuggestions;
        SearchTagSuggestions.SelectedIndex = -1;
        SearchTagSuggestions.Visibility = searchTagSuggestions.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void ChooseTagSuggestion(object sender, ItemClickEventArgs args)
    {
        if (args.ClickedItem is SourceAlbumTag tag)
            await ApplySearchTag(tag);
    }

    private static int? SearchTagTrigger(string input)
    {
        for (var index = input.Length - 1; index >= 0; index--)
        {
            if ((input[index] is '#' or '＃') && (index == 0 || char.IsWhiteSpace(input[index - 1])))
                return index;
        }
        return null;
    }

    private bool RemoveSearchTagTrigger()
    {
        if (SearchTagTrigger(SearchInput.Text) is not int marker)
            return false;
        updatingSearchInput = true;
        SearchInput.Text = SearchInput.Text[..marker];
        SearchInput.SelectionStart = marker;
        updatingSearchInput = false;
        return true;
    }

    private void UpdateSearchTagStack()
    {
        var tagsById = sourceAlbumIndex.Tags.ToDictionary(tag => tag.Id);
        searchTagIds.RemoveAll(id => !tagsById.ContainsKey(id));
        var tags = searchTagIds.Select(id => tagsById[id]).ToArray();
        SearchActiveTags.ItemsSource = tags;
        SearchTagStack.Visibility = tags.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        SearchTagStackedIcon.Visibility = tags.Length > 1 ? Visibility.Visible : Visibility.Collapsed;
        SearchTagName.Text = tags.LastOrDefault()?.Name ?? "";
        AutomationProperties.SetName(SearchTagStack, "标签筛选 " + string.Join("、", tags.Select(tag => tag.Name)));
    }

    private void RefreshSearchTagsFromCatalog()
    {
        if (!searchOpen)
            return;
        UpdateSearchTagStack();
        if (SearchOverlay.Visibility == Visibility.Visible)
            _ = RefreshSearch();
    }

    private void PeekSearchTags(object sender, PointerRoutedEventArgs args)
    {
        if (!SearchTagsFlyout.IsOpen && searchTagIds.Count > 0 &&
            args.GetCurrentPoint(SearchTagStack).PointerDeviceType == PointerDeviceType.Mouse)
            SearchTagsFlyout.ShowAt(SearchTagStack, new FlyoutShowOptions
            {
                ShowMode = FlyoutShowMode.TransientWithDismissOnPointerMoveAway
            });
    }

    private async void RemoveSearchTag(object sender, RoutedEventArgs args)
    {
        if (sender is not FrameworkElement { DataContext: SourceAlbumTag tag })
            return;
        searchTagIds.Remove(tag.Id);
        SearchTagsFlyout.Hide();
        UpdateSearchTagStack();
        SearchInput.Focus(FocusState.Programmatic);
        await RefreshSearch();
    }

    private Task ApplySearchTag(SourceAlbumTag tag)
    {
        RemoveSearchTagTrigger();
        if (!searchTagIds.Contains(tag.Id))
            searchTagIds.Add(tag.Id);
        UpdateSearchTagStack();
        SearchInput.Focus(FocusState.Programmatic);
        return RefreshSearch();
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
        var focusedResult = focused is ListViewItem row ? SearchResults.ItemFromContainer(row) as GlobalSearchHit : null;
        var resultFocused = focusedResult is not null;
        switch (args.Key)
        {
            case VirtualKey.Up when editingQuery || resultFocused:
            case VirtualKey.Down when editingQuery || resultFocused:
                if (suggestingTags)
                {
                    if (searchTagSuggestions.Count == 0)
                        return;
                    args.Handled = true;
                    int delta = args.Key == VirtualKey.Up ? -1 : 1;
                    var currentSuggestion = SearchTagSuggestions.SelectedIndex;
                    var next = currentSuggestion < 0 && delta < 0 ? searchTagSuggestions.Count - 1
                        : Math.Clamp(currentSuggestion + delta, 0, searchTagSuggestions.Count - 1);
                    SearchTagSuggestions.SelectedIndex = next;
                    SearchTagSuggestions.ScrollIntoView(searchTagSuggestions[next]);
                    return;
                }
                if (searchHits.Count == 0)
                    return;
                args.Handled = true;
                var direction = args.Key == VirtualKey.Up ? -1 : 1;
                var index = editingQuery
                    ? direction < 0 ? searchHits.Count - 1 : 0
                    : Math.Clamp(searchHits.IndexOf(focusedResult!) + direction, 0, searchHits.Count - 1);
                FocusSearchResult(searchHits[index]);
                break;
            case VirtualKey.Enter when editingQuery || resultFocused:
                if (suggestingTags)
                {
                    args.Handled = true;
                    if (!args.KeyStatus.WasKeyDown && searchTagSuggestions.Count > 0)
                        await ApplySearchTag(searchTagSuggestions[Math.Max(0, SearchTagSuggestions.SelectedIndex)]);
                    return;
                }
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
                if (SearchTagsFlyout.IsOpen)
                {
                    SearchTagsFlyout.Hide();
                    return;
                }
                if (suggestingTags && RemoveSearchTagTrigger())
                {
                    await RefreshSearch();
                    return;
                }
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
            var folder = result.Media?.WorkAlbumPath is { } work ? (work.Length == 0 ? null : work + "/") : result.Folder;
            var label = folder is null ? result.Source.Name : SourceRename.SplitPath(folder.TrimEnd('/')).Leaf;
            target = new Navigation(label, Source: result.Source.Id, Folder: folder);
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
        SearchTagsFlyout.Hide();
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
