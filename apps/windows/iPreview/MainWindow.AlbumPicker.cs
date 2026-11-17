using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace IPreview;

public sealed partial class MainWindow
{
    private async void PickAlbumMedia(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy || searching || current.Album is not long album)
            return;

        var staged = new AlbumMediaPicker(media, (albumMembers.GetValueOrDefault(album) ?? []).Select(item => item.Id),
            ReadPickerThumbnail)
        {
            Height = Math.Clamp(Root.ActualHeight - 200, 220, 410)
        };
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = $"添加到「{current.Label}」",
            PrimaryButtonText = "确认添加",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false
        };
        staged.CanAddChanged += canAdd => dialog.IsPrimaryButtonEnabled = canAdd;
        var selected = Selection?.Media.Id;
        var error = new InfoBar { Title = "无法添加媒体", Severity = InfoBarSeverity.Error };
        var content = new StackPanel { Spacing = 7 };
        content.Children.Add(error);
        content.Children.Add(staged);
        dialog.Content = content;
        dialog.PrimaryButtonClick += (_, click) =>
        {
            try
            {
                Database.AppendToAlbum(album, staged.MediaIDs);
            }
            catch (InvalidOperationException failure)
            {
                click.Cancel = true;
                error.Message = failure.Message;
                error.IsOpen = true;
            }
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            Reload(selected);
    }

    private static async Task<BitmapImage?> ReadPickerThumbnail(Media item)
    {
        try
        {
            return item.IsVideo ? await DecodeVideoThumbnail(item, 112) : await DecodeImage(item, 112, false);
        }
        catch (Exception error) when (MediaFailure(error))
        {
            return null;
        }
    }
}
