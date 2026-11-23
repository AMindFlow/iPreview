using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace IPreview;

public sealed partial class MainWindow
{
    private Grid? revealedSourceRow;

    private void SourceRowLoaded(object sender, RoutedEventArgs args)
    {
        var row = (Grid)sender;
        var menu = new MenuFlyout();
        var scan = new MenuFlyoutItem { Text = "重新扫描" };
        var delete = new MenuFlyoutItem { Text = "删除媒体源" };
        scan.Click += async (_, _) => await RescanSidebarSourceAsync(row);
        delete.Click += async (_, _) => await DeleteSidebarSourceAsync(row);
        menu.Items.Add(scan);
        menu.Items.Add(delete);
        menu.Opening += (_, _) => scan.IsEnabled = delete.IsEnabled = !busy;
        row.ContextFlyout = menu;
    }

    private void SourceRowUnloaded(object sender, RoutedEventArgs args)
    {
        if (ReferenceEquals(revealedSourceRow, sender))
            RevealSourceActions(null);
    }

    private void SourceRowWheelChanged(object sender, PointerRoutedEventArgs args)
    {
        var row = (Grid)sender;
        var pointer = args.GetCurrentPoint(row).Properties;
        if (!pointer.IsHorizontalMouseWheel || pointer.MouseWheelDelta == 0 || busy)
            return;
        if (pointer.MouseWheelDelta > 0)
            RevealSourceActions(row);
        else if (revealedSourceRow == row)
            RevealSourceActions(null);
        args.Handled = true;
    }

    private void RevealSourceActions(Grid? row)
    {
        if (revealedSourceRow == row)
            return;
        if (revealedSourceRow is { } previous)
            SetSourceActionsVisible(previous, false);
        revealedSourceRow = row;
        if (row is not null)
            SetSourceActionsVisible(row, true);
    }

    private static void SetSourceActionsVisible(Grid row, bool visible)
    {
        ((FrameworkElement)row.FindName("SourceActions")).Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        ((FrameworkElement)row.FindName("SourceDescription")).Margin = visible ? new Thickness(0, 0, 56, 0) : new Thickness();
    }

    private async void RescanSidebarSource(object sender, RoutedEventArgs args) =>
        await RescanSidebarSourceAsync((FrameworkElement)sender);

    private async Task RescanSidebarSourceAsync(FrameworkElement row)
    {
        if (busy || row.DataContext is not Navigation { Source: long id } || !sources.TryGetValue(id, out var source))
            return;
        RevealSourceActions(null);
        await RescanSourcesAsync([source]);
    }

    private async void DeleteSidebarSource(object sender, RoutedEventArgs args) =>
        await DeleteSidebarSourceAsync((FrameworkElement)sender);

    private async Task DeleteSidebarSourceAsync(FrameworkElement row)
    {
        if (busy || row.DataContext is not Navigation { Source: long id } || !sources.TryGetValue(id, out var source))
            return;
        RevealSourceActions(null);
        var version = libraryDataVersion;
        SetBusy(true);
        try
        {
            var dialog = new ContentDialog
            {
                XamlRoot = Root.XamlRoot,
                RequestedTheme = Root.RequestedTheme,
                Title = "删除媒体源",
                Content = $"将删除「{source.Name}」的索引、专辑组织设置及其在合集中的媒体引用。原始文件会保留。",
                PrimaryButtonText = "删除媒体源",
                CloseButtonText = "取消",
                DefaultButton = ContentDialogButton.Close
            };
            if (await dialog.ShowAsync() != ContentDialogResult.Primary)
                return;
            Database.DeleteSource(id, version);
            var wasCurrentSource = current.Source == id;
            Notice.IsOpen = false;
            Reload(Selection?.Media.Id);
            if (wasCurrentSource)
                LibraryHomeButton.Focus(FocusState.Programmatic);
        }
        catch (SourceDeletionChangedException error)
        {
            Reload(Selection?.Media.Id);
            ShowNotice("无法删除媒体源", error.Message, InfoBarSeverity.Warning);
        }
        catch (InvalidOperationException error)
        {
            ShowNotice("无法删除媒体源", error.Message);
        }
        finally
        {
            SetBusy(false);
        }
    }
}
