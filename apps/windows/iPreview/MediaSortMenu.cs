using Microsoft.UI.Xaml.Controls;

namespace IPreview;

internal static class MediaSortMenu
{
    public static void Attach(Button button, Func<MediaSort> current, Action<MediaSort> choose)
    {
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
            var item = new RadioMenuFlyoutItem { Text = title, GroupName = "MediaSortField" };
            item.Click += (_, _) => choose(current() with { Field = field });
            menu.Items.Add(item);
            return (field, item);
        }).ToArray();

        menu.Items.Add(new MenuFlyoutSeparator());
        var ascending = new RadioMenuFlyoutItem { Text = "升序", GroupName = "MediaSortDirection" };
        var descending = new RadioMenuFlyoutItem { Text = "降序", GroupName = "MediaSortDirection" };
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
