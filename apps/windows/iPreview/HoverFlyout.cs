using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;

namespace IPreview;

internal sealed class HoverFlyout
{
    private readonly FrameworkElement anchor;
    private readonly FlyoutBase flyout;
    private bool openingFromHover;

    public HoverFlyout(FrameworkElement anchor, FlyoutBase flyout)
    {
        this.anchor = anchor;
        this.flyout = flyout;
        flyout.Closed += OnClosed;
    }

    public bool IsOpen => flyout.IsOpen || openingFromHover;

    public void Peek(PointerRoutedEventArgs args)
    {
        if (!IsOpen && args.GetCurrentPoint(anchor).PointerDeviceType == PointerDeviceType.Mouse)
            Show(FlyoutShowMode.TransientWithDismissOnPointerMoveAway);
    }

    public void Open()
    {
        if (openingFromHover)
            return;
        if (!flyout.IsOpen)
            Show(FlyoutShowMode.Standard);
        else if (flyout.ShowMode != FlyoutShowMode.Standard)
        {
            openingFromHover = true;
            flyout.Hide();
        }
    }

    public void Hide()
    {
        openingFromHover = false;
        flyout.Hide();
    }

    private void OnClosed(object? sender, object args)
    {
        if (!openingFromHover)
            return;
        openingFromHover = false;
        Show(FlyoutShowMode.Standard);
    }

    private void Show(FlyoutShowMode mode)
    {
        flyout.ShowMode = mode;
        flyout.ShowAt(anchor);
    }
}
