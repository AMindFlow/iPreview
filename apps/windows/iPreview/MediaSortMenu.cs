using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace IPreview;

internal static class MediaSortMenu
{
    public static void Attach(Button button, Func<MediaSort> current, Action<MediaSort> choose)
    {
        button.Content = SliderIcon();
        var menu = new MenuFlyout();
        var fields = new[]
        {
            (MediaSortField.Original, "原次序"),
            (MediaSortField.Name, "文件名"),
            (MediaSortField.Modified, "修改时间"),
            (MediaSortField.Size, "文件大小")
        }.Select(entry =>
        {
            var (field, title) = entry;
            var item = new ToggleMenuFlyoutItem { Text = title };
            item.Click += (_, _) => choose(current() with { Field = field });
            menu.Items.Add(item);
            return (field, item);
        }).ToArray();

        menu.Items.Add(new MenuFlyoutSeparator());
        var ascending = new ToggleMenuFlyoutItem { Text = "升序" };
        var descending = new ToggleMenuFlyoutItem { Text = "降序" };
        ascending.Click += (_, _) => choose(current() with { Descending = false });
        descending.Click += (_, _) => choose(current() with { Descending = true });
        menu.Items.Add(ascending);
        menu.Items.Add(descending);
        menu.Opening += (_, _) =>
        {
            var sort = current();
            foreach (var (field, item) in fields)
                item.IsChecked = field == sort.Field;
            ascending.IsChecked = !sort.Descending;
            descending.IsChecked = sort.Descending;
            ascending.IsEnabled = descending.IsEnabled = sort.Field != MediaSortField.Original;
        };
        button.Flyout = menu;
    }

    private static PathIcon SliderIcon()
    {
        var tracks = new GeometryGroup();
        int[] positions = [10, 5, 12];
        for (var row = 0; row < positions.Length; row++)
        {
            var x = positions[row];
            var y = 2 + row * 5;
            tracks.Children.Add(new RectangleGeometry { Rect = new(0, y - 0.55, x - 2, 1.1) });
            tracks.Children.Add(new RectangleGeometry { Rect = new(x + 2, y - 0.55, 14 - x, 1.1) });
            tracks.Children.Add(new EllipseGeometry { Center = new(x, y), RadiusX = 1.65, RadiusY = 1.65 });
        }
        return new PathIcon { Width = 16, Height = 14, Data = tracks };
    }
}

internal sealed class MediaSortSession
{
    private CancellationTokenSource? pending;
    public MediaSort Order { get; set; }

    public void Cancel() => pending?.Cancel();

    public async Task<List<T>?> ArrangeAsync<T>(IReadOnlyList<T> items, Func<T, Media> media)
    {
        Cancel();
        var order = Order;
        if (!order.NeedsFileFacts || items.Count < 2)
            return order.Arrange(items, media);

        using var request = new CancellationTokenSource();
        pending = request;
        try
        {
            var ordered = await Task.Run(() => order.Arrange(items, media, request.Token));
            return request.IsCancellationRequested ? null : ordered;
        }
        catch (OperationCanceledException) when (request.IsCancellationRequested) { return null; }
        finally
        {
            if (ReferenceEquals(pending, request))
                pending = null;
        }
    }
}
