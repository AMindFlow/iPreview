using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace IPreview;

public sealed partial class MainWindow
{
    private SourceAlbumIndex sourceAlbumIndex = SourceAlbumIndex.Empty;

    private SourceAlbumKey? VisibleAlbumKey
    {
        get
        {
            if (VisibleSource is not { } source)
                return null;
            var key = new SourceAlbumKey(source.Id, current.Folder?.TrimEnd('/') ?? "");
            var workPath = ScopeMedia().FirstOrDefault()?.WorkAlbumPath;
            return (workPath is null ? key.MatchesLayout(source.Layout) : key.RelativePath == workPath) ? key : null;
        }
    }

    private void ShowSourceAlbumControls(IEnumerable<Media> members)
    {
        if (VisibleAlbumKey is { } key && members.Any())
        {
            SourceAlbumCover.Child = CoverArtwork(sourceAlbumIndex.Covers(key, members));
            SourceAlbumCover.Visibility = OrganizeSourceAlbum.Visibility = Visibility.Visible;
        }
        else
        {
            SourceAlbumCover.Child = null;
            SourceAlbumCover.Visibility = OrganizeSourceAlbum.Visibility = Visibility.Collapsed;
        }
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

    private async void OpenSourceAlbumOrganization(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy || VisibleAlbumKey is not { } key)
            return;

        var panel = new StackPanel { Spacing = 8 };
        var status = new InfoBar { Severity = InfoBarSeverity.Error, IsClosable = false };
        var form = new StackPanel { Spacing = 12 };
        panel.Children.Add(form);
        panel.Children.Add(status);
        var images = MediaSearch.ByPath(ScopeMedia().Where(item => item.Available && !item.IsVideo)).ToList();
        var imagesById = images.ToDictionary(item => item.Id);
        var selected = Selection?.Media.Id;
        var changed = false;

        try
        {
            Render();
            await OrganizationDialog(current.Label, panel).ShowAsync();
            if (changed)
                Reload(selected);
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("无法读取专辑组织", error.Message);
        }

        void Apply(Action change)
        {
            try
            {
                change();
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

            var favorite = new CheckBox { Content = "收藏", IsChecked = organization.Favorite };
            favorite.Click += (_, _) => Apply(() => Database.SetFavorite(favorite.IsChecked == true, key));
            form.Children.Add(favorite);

            var rating = new ComboBox
            {
                Header = "评分",
                ItemsSource = new[] { "未评分" }.Concat(Enumerable.Range(0, 11)
                    .Select(value => (value / 2d).ToString("0.#", CultureInfo.CurrentCulture) + " 星")).ToArray(),
                SelectedIndex = organization.RatingHalf is int half ? half + 1 : 0,
                MinWidth = 115
            };
            rating.SelectionChanged += (_, _) => Apply(() =>
                Database.SetRatingHalf(rating.SelectedIndex == 0 ? null : rating.SelectedIndex - 1, key));
            form.Children.Add(rating);

            var tagPanel = new StackPanel { Spacing = 6 };
            tagPanel.Children.Add(new TextBlock { Text = "标签", FontSize = 14 });
            foreach (var tag in organization.Tags)
            {
                var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
                line.Children.Add(new TextBlock { Text = tag.Name, VerticalAlignment = VerticalAlignment.Center });
                line.Children.Add(OrganizationButton("移除", () => Apply(() => Database.RemoveAlbumTag(tag.Id, key)),
                    $"移除标签 {tag.Name}"));
                tagPanel.Children.Add(line);
            }
            var input = new TextBox { PlaceholderText = "标签名称", MinWidth = 140 };
            var addTag = OrganizationButton("添加", () => Apply(() => Database.AddAlbumTag(input.Text, key)));
            addTag.IsEnabled = false;
            input.TextChanged += (_, _) => addTag.IsEnabled = !string.IsNullOrWhiteSpace(input.Text);
            var attached = organization.Tags.Select(tag => tag.Id).ToHashSet();
            var existing = TagSelector(Database.ReadAlbumTags().Where(tag => !attached.Contains(tag.Id)).ToList());
            existing.PlaceholderText = "已有标签";
            existing.SelectionChanged += (_, _) =>
            {
                if (existing.SelectedItem is SourceAlbumTag tag)
                    Apply(() => Database.AddAlbumTag(tag.Id, key));
            };
            var tagActions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            tagActions.Children.Add(input);
            tagActions.Children.Add(addTag);
            tagActions.Children.Add(existing);
            tagPanel.Children.Add(tagActions);
            form.Children.Add(tagPanel);

            var coverPanel = new StackPanel { Spacing = 8 };
            var coverActions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            var mode = organization.ConfiguredCoverIds.Count switch
            {
                0 => "自动",
                1 => "手选",
                int count => $"{count} 张拼图"
            };
            coverActions.Children.Add(new TextBlock { Text = $"封面 · {mode}", VerticalAlignment = VerticalAlignment.Center });
            var choose = OrganizationButton("选择图片",
                () => ChooseAlbumCover(coverPanel, images, ids => Apply(() => Database.ReplaceCover(ids, key)), Render));
            choose.IsEnabled = images.Count > 0;
            coverActions.Children.Add(choose);
            if (organization.ConfiguredCoverIds.Count > 0)
                coverActions.Children.Add(OrganizationButton("恢复自动", () => Apply(() => Database.ReplaceCover([], key))));
            coverPanel.Children.Add(coverActions);
            coverPanel.Children.Add(new Border
            {
                Height = 122, Width = 180, HorizontalAlignment = HorizontalAlignment.Left, CornerRadius = new(8),
                Child = CoverArtwork(organization.EffectiveCoverIds.Where(imagesById.ContainsKey).Select(id => imagesById[id]).ToArray())
            });
            form.Children.Add(coverPanel);
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
        var sortButton = new Button { Content = new FontIcon { Glyph = "\uE8CB", FontSize = 14 } };
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
                sourceAlbumIndex = Database.ReadSourceAlbumIndex();
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
