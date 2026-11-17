using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private async void NavigationTreeKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key is not (VirtualKey.Enter or VirtualKey.Space or VirtualKey.Escape) ||
            FocusManager.GetFocusedElement(Root.XamlRoot) is not TreeViewItem control ||
            NavTree.NodeFromContainer(control)?.Content is not Navigation { Source: not null } target)
            return;

        if (args.Key == VirtualKey.Space)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                NavigateFromContent(target);
        }
        else if (args.Key == VirtualKey.Escape && VisibleSource is not null && current.Folder is not null)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                NavigateToSourceParent();
        }
        else if (args.Key == VirtualKey.Enter && target.Folder is not null)
        {
            args.Handled = true;
            if (!args.KeyStatus.WasKeyDown)
                await RenameIndexedFolder(target, fromSidebar: true);
        }
    }

    private void FocusSidebarFolder(long source, string folder)
    {
        var node = FindNavigationNode(NavTree.RootNodes, new Navigation("", Source: source, Folder: folder));
        if (node is null)
            return;
        for (var parent = node.Parent; parent is not null; parent = parent.Parent)
            parent.IsExpanded = true;
        NavTree.SelectedNode = node;
        NavTree.UpdateLayout();
        if (NavTree.ContainerFromNode(node) is not Control item || !item.Focus(FocusState.Keyboard))
            NavTree.Focus(FocusState.Keyboard);
    }

    private Task RenameIndexedFolder(Navigation target, bool fromSidebar)
    {
        if (target is not { Source: long id, Folder: { } path })
            return Task.CompletedTask;
        var anchor = media.Find(item => item.Source.Id == id && item.Present &&
            item.RelativePath.StartsWith(path, StringComparison.Ordinal));
        if (anchor is null)
        {
            ShowNotice("无法重命名", "所选文件夹已不在活动索引中。");
            return Task.CompletedTask;
        }
        return RenameSourceItem(id, path.TrimEnd('/'), sources[id].Available, isDirectory: true,
            expectedMediaId: anchor.Id, fromSidebar: fromSidebar);
    }

    private async Task RenameSourceItem(long sourceId, string path, bool available, bool isDirectory,
        long expectedMediaId, bool fromSidebar = false)
    {
        if (busy || catalog is null)
            return;
        if (Database.CurrentRenameNotice() is { } pending)
        {
            ShowNotice("有待恢复的重命名", pending, InfoBarSeverity.Warning);
            return;
        }
        if (!available)
        {
            ShowNotice("无法重命名", "来源或所选项目当前不可用。");
            return;
        }

        var source = sources[sourceId];
        var leaf = SourceRename.SplitPath(path).Leaf;
        var extension = isDirectory ? "" : Path.GetExtension(leaf);
        var entry = new TextBox
        {
            Header = "名称",
            Text = leaf[..(leaf.Length - extension.Length)],
            MaxLength = 255
        };
        var errorMessage = new TextBlock { TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        var content = new StackPanel { Spacing = 10 };
        content.Children.Add(new TextBlock
        {
            Text = $"磁盘位置：{source.Path}\\{path.Replace('/', '\\')}",
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(entry);
        if (extension.Length > 0)
            content.Children.Add(new TextBlock { Text = $"保留扩展名 {extension}" });
        content.Children.Add(errorMessage);
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = isDirectory ? "重命名源文件夹" : "重命名源文件",
            Content = content,
            PrimaryButtonText = "重命名",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };
        dialog.Opened += (_, _) =>
        {
            entry.Focus(FocusState.Programmatic);
            entry.SelectAll();
        };
        dialog.PreviewKeyDown += (_, args) =>
        {
            if (args.Key == VirtualKey.Enter && args.KeyStatus.WasKeyDown)
                args.Handled = true;
        };
        string? renamedPath = null;
        dialog.PrimaryButtonClick += (_, args) =>
        {
            try
            {
                renamedPath = Database.RenameSourceItem(sourceId, path, entry.Text, isDirectory, expectedMediaId);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException)
            {
                args.Cancel = true;
                errorMessage.Text = error.Message;
                errorMessage.Visibility = Visibility.Visible;
                if (Database.RenameRecoveryNotice is not null && Database.CurrentRenameNotice() is not null)
                    dialog.IsPrimaryButtonEnabled = false;
                entry.Focus(FocusState.Programmatic);
            }
        };
        SetBusy(true);
        try
        {
            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary && renamedPath is not null && renamedPath != path)
            {
                if (isDirectory && current is { Source: long activeSource, Folder: { } folder } &&
                    activeSource == sourceId && folder.StartsWith(path + "/", StringComparison.Ordinal))
                {
                    var updated = renamedPath + folder[path.Length..];
                    current = new Navigation(SourceRename.SplitPath(updated.TrimEnd('/')).Leaf,
                        Source: sourceId, Folder: updated);
                }
                Reload(isDirectory ? Selection?.Media.Id : expectedMediaId);
            }
        }
        finally
        {
            SetBusy(false);
            if (fromSidebar)
                FocusSidebarFolder(sourceId, (renamedPath ?? path) + "/");
            else if (isDirectory)
                FocusSourceFolder((renamedPath ?? path) + "/");
            else
                FocusSelectedMedia();
        }
    }
}
