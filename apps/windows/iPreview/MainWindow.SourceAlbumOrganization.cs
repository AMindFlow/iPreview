using System.ComponentModel;
using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed class SidebarAlbumFavorite(SourceAlbumKey key, string title, bool isFavorite) : INotifyPropertyChanged
    {
        public SourceAlbumKey Key { get; } = key;
        public string Title { get; } = title;
        public bool IsFavorite { get; private set; } = isFavorite;
        public Visibility BookmarkFill => IsFavorite ? Visibility.Visible : Visibility.Collapsed;
        public string ActionLabel => IsFavorite ? $"取消收藏专辑「{Title}」" : $"收藏专辑「{Title}」";

        public event PropertyChangedEventHandler? PropertyChanged;

        public void SetFavorite(bool value)
        {
            if (IsFavorite == value)
                return;
            IsFavorite = value;
            PropertyChanged?.Invoke(this, new(nameof(BookmarkFill)));
            PropertyChanged?.Invoke(this, new(nameof(ActionLabel)));
        }
    }

    private SourceAlbumIndex sourceAlbumIndex = SourceAlbumIndex.Empty;
    private HashSet<SourceAlbumKey> sourceAlbumKeys = [];

    private readonly FontIcon[] sourceAlbumStarFills = new FontIcon[5];
    private int? displayedAlbumRating;
    private HoverFlyout? ratingOptions;
    private HoverFlyout RatingOptions => ratingOptions ??= new(SourceAlbumRatingOptions, SourceAlbumRatingFlyout);
    private bool sourceAlbumHasTags;
    private Button? hoveredTagAction;

    private SourceAlbumKey? VisibleAlbumKey => VisibleSource is { } source
        ? AlbumKeyAt(source, current.Folder) : null;

    private SourceAlbumKey? AlbumKeyAt(Source source, string? folder)
    {
        var key = new SourceAlbumKey(source.Id, folder?.TrimEnd('/') ?? "");
        return sourceAlbumKeys.Contains(key) ? key : null;
    }

    private SidebarAlbumFavorite SidebarFavoriteFor(SourceAlbumKey key, string title,
        IReadOnlyDictionary<SourceAlbumKey, SidebarAlbumFavorite> sidebarFavorites)
    {
        var favorite = sourceAlbumIndex.FavoriteAlbums.Contains(key);
        if (sidebarFavorites.TryGetValue(key, out var existing) && existing.Title == title)
        {
            existing.SetFavorite(favorite);
            return existing;
        }
        return new(key, title, favorite);
    }

    private static IEnumerable<Media> SourceAlbumMembers(SourceAlbumKey key, IEnumerable<Media> items) =>
        items.Where(item => SourceAlbumKey.FromMedia(item) == key);

    private void InitializeSourceAlbumStars()
    {
        for (var star = 0; star < sourceAlbumStarFills.Length; star++)
        {
            var target = new Grid { Width = 24, Height = 26 };
            target.Children.Add(new FontIcon { Glyph = "\uE734", FontSize = 16, IsHitTestVisible = false });
            var fill = new FontIcon { Glyph = "\uE735", FontSize = 16, IsHitTestVisible = false };
            sourceAlbumStarFills[star] = fill;
            target.Children.Add(fill);
            for (var side = 0; side < 2; side++)
            {
                var half = star * 2 + side + 1;
                var choose = new Button
                {
                    Style = (Style)LibraryView.Resources["AlbumRatingHalfButton"],
                    HorizontalAlignment = side == 0 ? HorizontalAlignment.Left : HorizontalAlignment.Right,
                    UseSystemFocusVisuals = true,
                };
                var name = $"设为 {FormatAlbumRating(half)}";
                AutomationProperties.SetName(choose, name);
                ToolTipService.SetToolTip(choose, name);
                choose.PointerEntered += (_, _) => DrawSourceAlbumStars(half);
                choose.Click += (_, _) => SetSourceAlbumRating(half);
                target.Children.Add(choose);
            }
            SourceAlbumStars.Children.Add(target);
        }
        SourceAlbumStars.PointerExited += (_, _) => DrawSourceAlbumStars(displayedAlbumRating ?? 0);
    }

    private static string FormatAlbumRating(int half) =>
        (half / 2d).ToString("0.#", CultureInfo.CurrentCulture) + " 星";

    private void DrawSourceAlbumStars(int half)
    {
        for (var star = 0; star < sourceAlbumStarFills.Length; star++)
        {
            var fill = sourceAlbumStarFills[star];
            int points = Math.Clamp(half - star * 2, 0, 2);
            fill.Visibility = points == 0 ? Visibility.Collapsed : Visibility.Visible;
            fill.Clip = points == 1 ? new RectangleGeometry { Rect = new(0, 0, 12, 26) } : null;
        }
    }

    private void ShowSourceAlbumControls(IEnumerable<Media> members)
    {
        var album = members.Any() ? VisibleAlbumKey : null;
        SourceAlbumCoverButton.Visibility = SourceAlbumFavorite.Visibility = SourceAlbumMetadata.Visibility =
            album is null ? Visibility.Collapsed : Visibility.Visible;
        if (album is not { } key)
        {
            SourceAlbumCover.Child = null;
            SourceAlbumTags.ItemsSource = null;
            return;
        }

        SourceAlbumCover.Child = CoverArtwork(sourceAlbumIndex.Covers(key, SourceAlbumMembers(key, members)));
        var favorite = sourceAlbumIndex.FavoriteAlbums.Contains(key);
        SourceAlbumFavorite.IsChecked = favorite;
        SourceAlbumFavoriteFill.Visibility = favorite ? Visibility.Visible : Visibility.Collapsed;
        ToolTipService.SetToolTip(SourceAlbumFavorite, favorite ? "取消收藏专辑" : "收藏专辑");
        displayedAlbumRating = sourceAlbumIndex.RatingsHalf.TryGetValue(key, out var half) ? half : null;
        DrawSourceAlbumStars(displayedAlbumRating ?? 0);
        SourceAlbumRatingValue.Text = displayedAlbumRating is int rating ? FormatAlbumRating(rating) : "未评分";
        AutomationProperties.SetHelpText(SourceAlbumRatingOptions, SourceAlbumRatingValue.Text);
        var tags = sourceAlbumIndex.TagsFor(key);
        SourceAlbumTags.ItemsSource = tags;
        sourceAlbumHasTags = tags.Count > 0;
        SourceAlbumAddTag.Opacity = sourceAlbumHasTags ? 0 : 1;
    }

    private void RefreshSourceAlbumMetadata()
    {
        sourceAlbumIndex = Database.ReadSourceAlbumIndex();
        UpdateNavigationSelection();
        ShowSourceAlbumControls(ScopeMedia());
        RefreshSearchTagsFromCatalog();
    }

    private void ToggleSourceAlbumFavorite(object sender, RoutedEventArgs args)
    {
        if (!busy && VisibleAlbumKey is { } key)
            SaveAlbumMetadata(() => Database.SetFavorite(SourceAlbumFavorite.IsChecked == true, key));
    }

    private void ToggleSidebarAlbumFavorite(object sender, RoutedEventArgs args)
    {
        if (busy || sender is not Button { DataContext: Navigation { Favorite: { } favorite } } button)
            return;
        var focus = button.FocusState;
        SaveAlbumMetadata(() => Database.SetFavorite(!favorite.IsFavorite, favorite.Key));
        if (focus == FocusState.Unfocused || button.FocusState != FocusState.Unfocused)
            return;

        var rows = SourceNavigation.Items.OfType<Navigation>();
        var row = rows.FirstOrDefault(item => item.Favorite?.Key == favorite.Key);
        if (row is not null)
        {
            SourceNavigation.ScrollIntoView(row);
            SourceNavigation.UpdateLayout();
            if (SourceNavigation.ContainerFromItem(row) is { } container &&
                FindSidebarBookmark(container)?.Focus(focus) == true)
                return;
        }
        // An inactive nested favorite is removed from the sidebar once unpinned.
        FocusBrowserItem(SourceNavigation, row ?? rows.FirstOrDefault(item =>
            item.Source == favorite.Key.SourceId && item.Folder is null), focus);
    }

    private static Button? FindSidebarBookmark(DependencyObject element)
    {
        if (element is Button { Name: "SidebarBookmark" } bookmark)
            return bookmark;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(element); index++)
            if (FindSidebarBookmark(VisualTreeHelper.GetChild(element, index)) is { } child)
                return child;
        return null;
    }

    private void PeekSourceAlbumRatingOptions(object sender, PointerRoutedEventArgs args)
    {
        if (!busy)
            RatingOptions.Peek(args);
    }

    private void OpenSourceAlbumRatingOptions(object sender, RoutedEventArgs args)
    {
        if (!busy)
            RatingOptions.Open();
    }

    private void PrepareSourceAlbumRatingOptions(object sender, object args)
    {
        SourceAlbumZeroRating.IsChecked = displayedAlbumRating == 0;
        SourceAlbumClearRating.IsChecked = displayedAlbumRating is null;
    }

    private void SetSourceAlbumZeroRating(object sender, RoutedEventArgs args) => SetSourceAlbumRating(0);
    private void ClearSourceAlbumRating(object sender, RoutedEventArgs args) => SetSourceAlbumRating(null);

    private void SetSourceAlbumRating(int? half)
    {
        if (!busy && VisibleAlbumKey is { } key && displayedAlbumRating != half)
            SaveAlbumMetadata(() => Database.SetRatingHalf(half, key));
    }

    private void RemoveVisibleAlbumTag(object sender, RoutedEventArgs args)
    {
        if (!busy && VisibleAlbumKey is { } key && sender is FrameworkElement { DataContext: SourceAlbumTag tag })
            SaveAlbumMetadata(() => Database.RemoveAlbumTag(tag.Id, key));
    }

    private void SaveAlbumMetadata(Action edit)
    {
        try
        {
            edit();
            RefreshSourceAlbumMetadata();
        }
        catch (Exception error) when (error is ArgumentException or InvalidOperationException)
        {
            ShowSourceAlbumControls(ScopeMedia());
            ShowNotice("无法保存专辑组织", error.Message);
        }
    }

    private void TagChipEntered(object sender, PointerRoutedEventArgs args)
    {
        var button = (Button)((Grid)sender).FindName("RemoveTagButton");
        hoveredTagAction = button;
        SetTagRemoveVisibility(button, true);
    }

    private void TagChipExited(object sender, PointerRoutedEventArgs args)
    {
        var button = (Button)((Grid)sender).FindName("RemoveTagButton");
        if (ReferenceEquals(hoveredTagAction, button))
            hoveredTagAction = null;
        if (button.FocusState == FocusState.Unfocused)
            SetTagRemoveVisibility(button, false);
    }

    private void InitializeTagRemoveButton(object sender, RoutedEventArgs args)
    {
        if (sender is Button { Tag: string action, DataContext: SourceAlbumTag tag } button)
            AutomationProperties.SetName(button, $"{action} {tag.Name}");
    }

    private void FocusTagRemoveButton(object sender, RoutedEventArgs args) => SetTagRemoveVisibility((Button)sender, true);

    private void BlurTagRemoveButton(object sender, RoutedEventArgs args) =>
        SetTagRemoveVisibility((Button)sender, ReferenceEquals(sender, hoveredTagAction));

    private static void SetTagRemoveVisibility(Button button, bool show)
    {
        button.Opacity = show ? 1 : 0;
        button.IsHitTestVisible = show;
    }

    private void ShowAlbumTagPlus(object sender, PointerRoutedEventArgs args)
    {
        hoveredTagAction = SourceAlbumAddTag;
        SourceAlbumAddTag.Opacity = 1;
    }

    private void FadeAlbumTagPlus(object sender, PointerRoutedEventArgs args)
    {
        if (ReferenceEquals(hoveredTagAction, SourceAlbumAddTag))
            hoveredTagAction = null;
        if (sourceAlbumHasTags && SourceAlbumAddTag.FocusState == FocusState.Unfocused)
            SourceAlbumAddTag.Opacity = 0;
    }

    private void RevealAlbumTagButton(object sender, RoutedEventArgs args) => ((Button)sender).Opacity = 1;

    private void HideAlbumTagButton(object sender, RoutedEventArgs args)
    {
        var button = (Button)sender;
        button.Opacity = ReferenceEquals(button, hoveredTagAction) || !sourceAlbumHasTags ? 1 : 0;
    }

    private void LoadFolderCover(object sender, RoutedEventArgs args) => UpdateFolderCover((Border)sender);

    private void UpdateFolderCover(FrameworkElement sender, DataContextChangedEventArgs args)
    {
        if (sender.IsLoaded)
            UpdateFolderCover((Border)sender);
    }

    private void UpdateFolderCover(Border surface)
    {
        surface.Child = CoverArtwork((surface.DataContext as Navigation)?.Cover ?? []);
    }

    private UIElement CoverArtwork(IReadOnlyList<Media> images)
    {
        if (images.Count == 0)
            return new FontIcon { Glyph = "\uEB9F", FontSize = 22, Opacity = 0.65 };
        var collage = new Grid { RowSpacing = 2, ColumnSpacing = 2 };
        for (var row = 0; row < (images.Count > 2 ? 2 : 1); row++)
            collage.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
        for (var column = 0; column < Math.Min(2, images.Count); column++)
            collage.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });

        for (var index = 0; index < images.Count; index++)
        {
            var image = new Image { Stretch = Stretch.UniformToFill, DataContext = new Tile(images[index], 0) };
            image.Loaded += LoadThumbnail;
            Grid.SetRow(image, index / 2);
            Grid.SetColumn(image, index % 2);
            if (images.Count == 3 && index == 2)
                Grid.SetColumnSpan(image, 2);
            collage.Children.Add(image);
        }
        return collage;
    }

    private async void EditSourceAlbumCover(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy || VisibleAlbumKey is not { } key)
            return;

        var status = new InfoBar { Severity = InfoBarSeverity.Error, IsClosable = false };
        var form = new StackPanel { Spacing = 9 };
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(form);
        panel.Children.Add(status);
        var images = MediaSearch.ByPath(SourceAlbumMembers(key, ScopeMedia())
            .Where(item => item.Available && !item.IsVideo)).ToList();
        var imagesById = images.ToDictionary(item => item.Id);
        var changed = false;
        try
        {
            Render();
            await OrganizationDialog("选择专辑封面", panel).ShowAsync();
            if (changed)
                RefreshSourceAlbumMetadata();
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("无法读取封面", error.Message);
        }

        void Save(long[] ids)
        {
            try
            {
                Database.ReplaceCover(ids, key);
                changed = true;
                status.IsOpen = false;
                Render();
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException)
            {
                status.Message = error.Message;
                status.IsOpen = true;
            }
        }

        void Render()
        {
            var organization = Database.ReadSourceAlbumOrganization(key);
            form.Children.Clear();
            var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var mode = organization.ConfiguredCoverIds.Count switch
            {
                0 => "自动",
                1 => "手选",
                int count => $"{count} 张拼图"
            };
            actions.Children.Add(new TextBlock { Text = mode, VerticalAlignment = VerticalAlignment.Center });
            var choose = OrganizationButton("选择图片", () => ChooseAlbumCover(form, images, Save, Render));
            choose.IsEnabled = images.Count > 0;
            actions.Children.Add(choose);
            if (organization.ConfiguredCoverIds.Count > 0)
                actions.Children.Add(OrganizationButton("恢复自动", () => Save([])));
            form.Children.Add(actions);
            form.Children.Add(new Border
            {
                Height = 122, Width = 180, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new(8),
                Child = CoverArtwork(organization.EffectiveCoverIds.Where(imagesById.ContainsKey).Select(id => imagesById[id]).ToArray())
            });
        }
    }

    private async void AddVisibleAlbumTag(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy || VisibleAlbumKey is not { } key)
            return;

        var panel = new StackPanel { Spacing = 6 };
        var input = new TextBox { PlaceholderText = "标签名称", MinWidth = 140 };
        AutomationProperties.SetName(input, "标签名称");
        var add = new Button { Content = "添加", IsEnabled = false };
        var done = new Button { Content = "完成" };
        var row = new Grid { ColumnSpacing = 6 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(add, 1);
        Grid.SetColumn(done, 2);
        row.Children.Add(input);
        row.Children.Add(add);
        row.Children.Add(done);

        var suggestions = new ListView
        {
            DisplayMemberPath = nameof(SourceAlbumTag.Name),
            SelectionMode = ListViewSelectionMode.Single,
            IsItemClickEnabled = true,
            MaxHeight = 150,
            Visibility = Visibility.Collapsed
        };
        AutomationProperties.SetName(suggestions, "已有标签建议");
        var status = new InfoBar { Severity = InfoBarSeverity.Error, IsClosable = false };
        panel.Children.Add(row);
        panel.Children.Add(suggestions);
        panel.Children.Add(status);
        var dialog = OrganizationDialog("添加专辑标签", panel);
        dialog.CloseButtonText = "";
        dialog.DefaultButton = ContentDialogButton.None;
        dialog.Opened += (_, _) => input.Focus(FocusState.Programmatic);
        var composing = false;
        input.TextCompositionStarted += (_, _) => composing = true;
        input.TextCompositionEnded += (_, _) => composing = false;
        dialog.PreviewKeyDown += (_, args) =>
        {
            if (args.Key != VirtualKey.Escape || composing)
                return;
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                dialog.Hide();
        };
        input.TextChanged += (_, _) => UpdateSuggestions();
        input.PreviewKeyDown += (_, args) =>
        {
            if (composing)
                return;

            if (args.Key == VirtualKey.Enter)
            {
                args.Handled = true;
                if (!args.KeyStatus.WasKeyDown && add.IsEnabled)
                    AddTag(suggestions.SelectedItem as SourceAlbumTag);
                return;
            }
            if (args.Key is not (VirtualKey.Up or VirtualKey.Down) || suggestions.Items.Count == 0)
                return;
            args.Handled = true;
            var index = suggestions.SelectedIndex;
            var last = suggestions.Items.Count - 1;
            suggestions.SelectedIndex = args.Key == VirtualKey.Up
                ? (index < 0 ? last : Math.Max(0, index - 1))
                : Math.Min(last, index + 1);
            suggestions.ScrollIntoView(suggestions.SelectedItem);
        };
        suggestions.ItemClick += (_, args) => AddTag((SourceAlbumTag)args.ClickedItem);
        add.Click += (_, _) => AddTag(suggestions.SelectedItem as SourceAlbumTag);
        done.Click += (_, _) => dialog.Hide();
        await dialog.ShowAsync();

        void AddTag(SourceAlbumTag? tag)
        {
            if (composing)
                return;
            try
            {
                if (tag is not null)
                    Database.AddAlbumTag(tag.Id, key);
                else
                    Database.AddAlbumTag(input.Text, key);
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException)
            {
                status.Message = error.Message;
                status.IsOpen = true;
                input.Focus(FocusState.Programmatic);
                return;
            }
            RefreshSourceAlbumMetadata();
            status.IsOpen = false;
            input.Text = "";
            input.Focus(FocusState.Programmatic);
        }

        void UpdateSuggestions()
        {
            var (_, prefix) = SourceAlbumTag.NamesFrom(input.Text);
            add.IsEnabled = prefix.Length > 0;
            if (!add.IsEnabled)
            {
                suggestions.ItemsSource = null;
                suggestions.Visibility = Visibility.Collapsed;
                return;
            }

            var matches = sourceAlbumIndex.Tags.Where(tag => tag.NormalizedName.StartsWith(prefix, StringComparison.Ordinal)
                && (!sourceAlbumIndex.TaggedAlbums.TryGetValue(tag.Id, out var albums) || !albums.Contains(key))).ToArray();
            suggestions.ItemsSource = matches;
            suggestions.SelectedIndex = -1;
            suggestions.Visibility = matches.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        }
    }

    private void ChooseAlbumCover(Panel target, List<Media> images, Action<long[]> save, Action cancel)
    {
        target.Children.Clear();
        var available = images.Select((item, index) => new Tile(item, index)).ToList();
        var items = new ListView
        {
            Height = 225, SelectionMode = ListViewSelectionMode.Multiple, ItemsSource = available,
            ItemTemplate = (DataTemplate)LibraryView.Resources["AlbumCoverChoiceTemplate"],
            IsMultiSelectCheckBoxEnabled = true
        };
        AutomationProperties.SetName(items, "封面图片");
        var selection = new List<Tile>();
        var sorting = new MediaSortSession();
        var restoringSelection = false;
        items.Unloaded += (_, _) => sorting.Cancel();
        var sortButton = new Button();
        AutomationProperties.SetName(sortButton, "文件排序");
        ToolTipService.SetToolTip(sortButton, "文件排序");
        MediaSortMenu.Attach(sortButton, () => sorting.Order, async order =>
        {
            sorting.Order = order;
            if (await sorting.ArrangeAsync(available, tile => tile.Media) is not { } sorted || !items.IsLoaded)
                return;
            restoringSelection = true;
            items.ItemsSource = sorted;
            foreach (var tile in selection)
                items.SelectedItems.Add(tile);
            restoringSelection = false;
        });
        var selectedNames = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var apply = OrganizationButton("设为封面", () => save(selection.Select(tile => tile.Media.Id).ToArray()));
        apply.IsEnabled = false;
        items.SelectionChanged += (_, args) =>
        {
            if (restoringSelection)
                return;
            foreach (var removed in args.RemovedItems.OfType<Tile>())
                selection.Remove(removed);
            foreach (var added in args.AddedItems.OfType<Tile>())
            {
                if (selection.Count < 4)
                    selection.Add(added);
                else
                    items.SelectedItems.Remove(added);
            }
            apply.IsEnabled = selection.Count > 0;
            selectedNames.Text = string.Join("  ", selection.Select((tile, index) => $"{index + 1}. {tile.FileName}"));
        };
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        actions.Children.Add(sortButton);
        actions.Children.Add(OrganizationButton("取消", cancel));
        actions.Children.Add(apply);
        target.Children.Add(items);
        target.Children.Add(selectedNames);
        target.Children.Add(actions);
    }

    private async void OpenGlobalTagManagement(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy)
            return;
        var form = new StackPanel { Spacing = 8 };
        var status = new InfoBar { Severity = InfoBarSeverity.Error, IsClosable = false };
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(form);
        panel.Children.Add(status);
        var changed = false;
        try
        {
            Render();
            await OrganizationDialog("管理标签", panel).ShowAsync();
            if (changed)
                RefreshSourceAlbumMetadata();
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("无法读取标签", error.Message);
        }

        void Apply(Action edit)
        {
            try
            {
                edit();
                changed = true;
                status.IsOpen = false;
                Render();
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException)
            {
                status.Message = error.Message;
                status.IsOpen = true;
            }
        }

        void Render(long? selected = null)
        {
            form.Children.Clear();
            var tags = Database.ReadAlbumTags();
            if (tags.Count == 0)
            {
                form.Children.Add(new TextBlock { Text = "没有标签" });
                return;
            }
            var picker = TagSelector(tags);
            var editor = new StackPanel { Spacing = 8 };
            form.Children.Add(picker);
            form.Children.Add(editor);
            picker.SelectionChanged += (_, _) =>
            {
                editor.Children.Clear();
                if (picker.SelectedItem is not SourceAlbumTag tag)
                    return;
                var name = new TextBox { Text = tag.Name, Header = "标签名称" };
                var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                var rename = OrganizationButton("重命名", () => Apply(() => Database.RenameTag(tag.Id, name.Text)));
                name.TextChanged += (_, _) => rename.IsEnabled = !string.IsNullOrWhiteSpace(name.Text);
                actions.Children.Add(rename);
                actions.Children.Add(OrganizationButton("删除", () =>
                {
                    editor.Children.Clear();
                    var confirmation = new TextBlock
                    {
                        Text = $"将从全库移除「{tag.Name}」及其专辑关联。", TextWrapping = TextWrapping.Wrap
                    };
                    var choices = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                    choices.Children.Add(OrganizationButton("取消", () => Render(tag.Id)));
                    choices.Children.Add(OrganizationButton("删除标签", () => Apply(() => Database.DeleteTag(tag.Id))));
                    editor.Children.Add(confirmation);
                    editor.Children.Add(choices);
                }));
                editor.Children.Add(name);
                editor.Children.Add(actions);
            };
            picker.SelectedItem = tags.FirstOrDefault(tag => tag.Id == selected) ?? tags[0];
        }
    }

    private ContentDialog OrganizationDialog(string title, UIElement panel) => new()
    {
        XamlRoot = Root.XamlRoot,
        RequestedTheme = Root.RequestedTheme,
        Title = title,
        Content = new ScrollViewer
        {
            MaxHeight = Math.Max(180, Root.ActualHeight - 190),
            Content = panel,
            HorizontalScrollMode = ScrollMode.Disabled,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        },
        CloseButtonText = "完成",
        DefaultButton = ContentDialogButton.Close
    };

    private static ComboBox TagSelector(IReadOnlyList<SourceAlbumTag> tags)
    {
        var picker = new ComboBox { ItemsSource = tags, DisplayMemberPath = nameof(SourceAlbumTag.Name), MinWidth = 105 };
        AutomationProperties.SetName(picker, "标签");
        return picker;
    }

    private static Button OrganizationButton(string label, Action click, string? accessibilityName = null)
    {
        var button = new Button { Content = label };
        button.Click += (_, _) => click();
        if (accessibilityName is not null)
            AutomationProperties.SetName(button, accessibilityName);
        return button;
    }
}
