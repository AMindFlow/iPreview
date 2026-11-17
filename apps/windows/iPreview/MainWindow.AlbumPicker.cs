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
            Width = Math.Clamp(Root.ActualWidth - 96, 260, 480)
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
        var saving = false;
        staged.CanAddChanged += canAdd => dialog.IsPrimaryButtonEnabled = canAdd && !saving;
        dialog.Closing += (_, closing) =>
        {
            if (saving)
                closing.Cancel = true;
        };
        var selected = Selection?.Media.Id;
        var error = new InfoBar { Title = "无法添加媒体", Severity = InfoBarSeverity.Error };
        var content = new Grid
        {
            Height = Math.Clamp(Root.ActualHeight - 200, 220, 410),
            RowSpacing = 7
        };
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        content.Children.Add(error);
        Grid.SetRow(staged, 1);
        content.Children.Add(staged);
        dialog.Content = content;
        dialog.PrimaryButtonClick += async (_, click) =>
        {
            if (saving)
            {
                click.Cancel = true;
                return;
            }

            var deferral = click.GetDeferral();
            saving = true;
            staged.IsEnabled = false;
            dialog.IsPrimaryButtonEnabled = false;
            error.IsOpen = false;
            var chosen = staged.SelectedMedia;
            try
            {
                var unavailable = await Task.Run(() => chosen.FirstOrDefault(item => !AlbumMediaPicker.CanRead(item)));
                if (unavailable is not null)
                {
                    click.Cancel = true;
                    error.Message = $"「{unavailable.FileName}」已不可用。请从待添加列表移除后重试。";
                    error.IsOpen = true;
                    staged.RecheckCurrentAlbum();
                    return;
                }
                Database.AppendToAlbum(album, chosen.Select(item => item.Id).ToArray());
            }
            catch (InvalidOperationException failure)
            {
                click.Cancel = true;
                error.Message = failure.Message;
                error.IsOpen = true;
            }
            finally
            {
                saving = false;
                staged.IsEnabled = true;
                dialog.IsPrimaryButtonEnabled = chosen.Length != 0;
                deferral.Complete();
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
