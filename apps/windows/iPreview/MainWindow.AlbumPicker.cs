using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;

namespace IPreview;

public sealed partial class MainWindow
{
    private async void PickAlbumMedia(object sender, RoutedEventArgs args)
    {
        if (catalog is null || busy || current.Album is not long album)
            return;

        var staged = new AlbumMediaPicker(media, (albumMembers.GetValueOrDefault(album) ?? []).Select(item => item.Id),
            ReadPickerThumbnail);
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = $"添加到「{current.Label}」",
            PrimaryButtonText = "添加媒体",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false
        };
        dialog.Resources["ContentDialogMaxWidth"] = 1100d;
        var saving = false;
        staged.CanAddChanged += canAdd => dialog.IsPrimaryButtonEnabled = canAdd && !saving;
        dialog.Closing += (_, closing) =>
        {
            if (saving)
                closing.Cancel = true;
        };
        var selected = Selection?.Media.Id;
        void FitPicker()
        {
            staged.Width = Math.Clamp(Root.ActualWidth - 76, 234, 1050);
            staged.Height = Math.Clamp(Root.ActualHeight - 157, 204, 620);
        }
        FitPicker();
        dialog.Content = staged;
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
            staged.ShowAddError(null);
            var chosen = staged.SelectedMedia;
            try
            {
                var unavailable = await Task.Run(() => chosen.FirstOrDefault(item => !AlbumMediaPicker.CanRead(item)));
                if (unavailable is not null)
                {
                    click.Cancel = true;
                    staged.ShowAddError($"「{unavailable.FileName}」已不可用。请移除该项后重试。");
                    staged.RecheckCurrentAlbum();
                    return;
                }
                Database.AppendToAlbum(album, chosen.Select(item => item.Id).ToArray());
            }
            catch (InvalidOperationException failure)
            {
                click.Cancel = true;
                staged.ShowAddError(failure.Message);
            }
            finally
            {
                saving = false;
                staged.IsEnabled = true;
                dialog.IsPrimaryButtonEnabled = chosen.Length != 0;
                deferral.Complete();
            }
        };
        SizeChangedEventHandler resize = (_, _) => FitPicker();
        Root.SizeChanged += resize;
        try
        {
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
                Reload(selected);
        }
        finally
        {
            Root.SizeChanged -= resize;
        }
    }

    private static async Task<BitmapImage?> ReadPickerThumbnail(Media item)
    {
        try
        {
            return item.IsVideo ? await DecodeVideoThumbnail(item, 192) : await DecodeImage(item, 192, false);
        }
        catch (Exception error) when (MediaFailure(error))
        {
            return null;
        }
    }
}
