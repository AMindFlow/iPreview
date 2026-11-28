using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;

namespace IPreview;

public sealed partial class MainWindow
{
    private void MediaMetadataContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        var container = args.ItemContainer;
        if (args.InRecycleQueue || args.Item is not Tile { Media: { IsVideo: true } } tile)
        {
            container.ContextFlyout = null;
            return;
        }

        var menu = new MenuFlyout();
        var action = new MenuFlyoutItem { Text = "媒体元信息" };
        menu.Items.Add(action);
        menu.Opening += (_, _) => action.IsEnabled = !SelectingAlbumMembers;
        action.Click += async (_, _) => await ShowVideoMetadataAsync(tile.Media);
        container.ContextFlyout = menu;
    }

    private async Task ShowVideoMetadataAsync(Media item)
    {
        var values = new TextBlock { Text = "正在读取…", TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        AutomationProperties.SetLiveSetting(values, AutomationLiveSetting.Polite);
        var panel = new StackPanel { Spacing = 12 };
        panel.Children.Add(new TextBlock { Text = item.FileName, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
        panel.Children.Add(values);
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = "媒体元信息",
            Content = panel,
            CloseButtonText = "关闭",
            DefaultButton = ContentDialogButton.Close,
        };

        using var cancellation = new CancellationTokenSource();
        var token = cancellation.Token;
        dialog.Opened += async (_, _) => await PopulateVideoMetadataAsync(item, values, token);
        try
        {
            await dialog.ShowAsync();
        }
        finally
        {
            cancellation.Cancel();
        }
    }

    private static async Task PopulateVideoMetadataAsync(Media item, TextBlock values, CancellationToken token)
    {
        StorageFile file;
        try
        {
            file = await OpenMediaFile(item, token);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            return;
        }
        catch (Exception error) when (MediaFailure(error))
        {
            if (!token.IsCancellationRequested)
                values.Text = "源文件已离线、移动或无法安全读取。";
            return;
        }

        try
        {
            var metadata = await VideoMetadata.ReadAsync(file, token);
            if (token.IsCancellationRequested)
                return;

            const string missing = "未提供";
            var size = metadata.Width > 0 && metadata.Height > 0 ? $"{metadata.Width} × {metadata.Height}" : missing;
            var duration = metadata.Duration > TimeSpan.Zero ? FormatTime(metadata.Duration) : missing;
            values.Text = $"分辨率（像素）  {size}\n时长  {duration}\n标题  {metadata.Title ?? missing}\n作者  {metadata.Author ?? missing}";
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (Exception error) when (error is InvalidDataException || MediaFailure(error))
        {
            if (!token.IsCancellationRequested)
                values.Text = "无法识别视频元信息。";
        }
    }
}
