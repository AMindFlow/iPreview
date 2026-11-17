using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;

namespace IPreview;

public sealed partial class MainWindow
{
    private sealed record TitleEdit(Navigation Page, long? ExpectedMedia);
    private TitleEdit? titleEdit;

    private bool CanEditTitle => catalog is not null && !busy && !searching && selectionAlbum is null &&
        (current.Album is not null || current is { Source: long source, Folder: not null } && sources[source].Available);

    private void BeginTitleEdit(object sender, DoubleTappedRoutedEventArgs args)
    {
        if (!CanEditTitle || titleEdit is not null)
            return;
        long? expectedMedia = null;
        if (current is { Source: long source, Folder: { } folder })
        {
            expectedMedia = media.Find(item => item.Source.Id == source && item.Present &&
                item.RelativePath.StartsWith(folder, StringComparison.Ordinal))?.Id;
            if (expectedMedia is null)
            {
                ShowNotice("无法重命名", "所选文件夹已不在活动索引中。");
                return;
            }
        }
        titleEdit = new(current, expectedMedia);
        TitleEditor.Text = current.Label;
        RefreshTitleEditor();
        TitleEditor.Focus(FocusState.Programmatic);
        TitleEditor.SelectAll();
        args.Handled = true;
    }

    private void RefreshTitleEditor()
    {
        var editing = titleEdit?.Page == current && !searching;
        TitleEditor.Visibility = editing ? Visibility.Visible : Visibility.Collapsed;
        Heading.Visibility = editing ? Visibility.Collapsed : Visibility.Visible;
        ToolTipService.SetToolTip(Heading, CanEditTitle ? "双击标题重命名" : null);
    }

    private void TitleEditorKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (titleEdit is not { } edit || args.Key is not (VirtualKey.Enter or VirtualKey.Escape))
            return;
        args.Handled = true;
        if (args.KeyStatus.WasKeyDown)
            return;
        if (args.Key == VirtualKey.Enter)
            CommitTitleEdit(edit, TitleEditor.Text);
        else
        {
            titleEdit = null;
            RefreshTitleEditor();
        }
        if (browsingFolders)
            FocusSourceFolder();
        else
            FocusSelectedMedia();
    }

    private void CommitTitleOnOutsideClick(object sender, PointerRoutedEventArgs args)
    {
        if (titleEdit is not { } edit)
            return;
        for (var element = args.OriginalSource as DependencyObject; element is not null;
             element = VisualTreeHelper.GetParent(element))
        {
            if (element == TitleEditor)
                return;
        }
        var name = TitleEditor.Text;
        DispatcherQueue.TryEnqueue(() => CommitTitleEdit(edit, name));
    }

    private void CommitTitleEdit(TitleEdit edit, string input)
    {
        if (!ReferenceEquals(edit, titleEdit))
            return;
        titleEdit = null;
        RefreshTitleEditor();
        var name = input.Trim();
        if (name.Length == 0 || name == edit.Page.Label)
            return;

        try
        {
            if (edit.Page.Album is long album)
                Database.RenameAlbum(album, name);
            else if (edit.Page is { Source: long source, Folder: { } folder } && edit.ExpectedMedia is long expectedMedia)
            {
                var path = folder.TrimEnd('/');
                var renamedPath = Database.RenameSourceItem(source, path, name, isDirectory: true,
                    expectedMediaId: expectedMedia);
                FollowRenamedDirectory(source, path, renamedPath);
            }
            Reload(Selection?.Media.Id);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            ShowNotice("无法重命名", error.Message);
        }
    }
}
