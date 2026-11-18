using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Foundation;
using Windows.UI.ViewManagement;

namespace IPreview;

public sealed partial class MainWindow
{
    private bool sidebarCollapsed;
    private Storyboard? sidebarAnimation;

    private void ToggleSidebar(object sender, RoutedEventArgs args)
    {
        var width = Sidebar.ActualWidth;
        var offset = SidebarToolsOffset.X;
        sidebarAnimation?.Stop();
        Sidebar.Width = width;
        SidebarToolsOffset.X = offset;
        sidebarCollapsed = !sidebarCollapsed;
        SidebarToggleGlyph.Glyph = sidebarCollapsed ? "\uE76C" : "\uE76B";
        var label = sidebarCollapsed ? "展开侧边栏" : "收起侧边栏";
        AutomationProperties.SetName(SidebarToggleButton, label);
        ToolTipService.SetToolTip(SidebarToggleButton, label);
        var targetWidth = sidebarCollapsed ? 0 : 200;
        var targetOffset = sidebarCollapsed ? 0 : 112;
        if (!new UISettings().AnimationsEnabled)
        {
            Sidebar.Width = targetWidth;
            SidebarToolsOffset.X = targetOffset;
            return;
        }

        var animation = new Storyboard();
        var duration = new Duration(TimeSpan.FromMilliseconds(240));
        var easing = new CubicEase { EasingMode = EasingMode.EaseInOut };
        var resize = new DoubleAnimation
        {
            From = width, To = targetWidth, Duration = duration, EasingFunction = easing,
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(resize, Sidebar);
        Storyboard.SetTargetProperty(resize, "Width");
        animation.Children.Add(resize);
        var moveTools = new DoubleAnimation
        {
            From = offset, To = targetOffset, Duration = duration, EasingFunction = easing
        };
        Storyboard.SetTarget(moveTools, SidebarToolsOffset);
        Storyboard.SetTargetProperty(moveTools, "X");
        animation.Children.Add(moveTools);
        animation.Completed += (_, _) =>
        {
            Sidebar.Width = targetWidth;
            SidebarToolsOffset.X = targetOffset;
            animation.Stop();
            if (ReferenceEquals(sidebarAnimation, animation))
                sidebarAnimation = null;
        };
        sidebarAnimation = animation;
        animation.Begin();
    }

    private void SidebarSizeChanged(object sender, SizeChangedEventArgs args) =>
        Sidebar.Clip = new RectangleGeometry { Rect = new Rect(0, 0, args.NewSize.Width, args.NewSize.Height) };

    private static int GridColumns(GridView browser) => browser.ItemsPanelRoot is ItemsWrapGrid { ItemWidth: > 0 } panel
        ? Math.Max(1, (int)Math.Floor(panel.ActualWidth / panel.ItemWidth)) : 1;

    private void CardGridSizeChanged(object sender, SizeChangedEventArgs args)
    {
        var browser = (GridView)sender;
        UpdateCardMetrics(browser);
        for (var index = 0; index < browser.Items.Count; index++)
        {
            if (browser.ContainerFromIndex(index) is GridViewItem item)
                SizeCard(browser, item);
        }
    }

    private void CardContainerChanging(ListViewBase sender, ContainerContentChangingEventArgs args)
    {
        if (args.InRecycleQueue)
            return;
        if (args.Phase == 0)
        {
            args.RegisterUpdateCallback(CardContainerChanging);
            return;
        }
        var browser = (GridView)sender;
        UpdateCardMetrics(browser);
        SizeCard(browser, (GridViewItem)args.ItemContainer);
    }

    private void UpdateCardMetrics(GridView browser)
    {
        if (browser.ItemsPanelRoot is not ItemsWrapGrid panel || browser.ActualWidth <= 0)
            return;
        var width = Math.Max(148, browser.ActualWidth - 4);
        var columns = Math.Max(1, (int)Math.Floor((width + 15) / 230));
        panel.ItemWidth = width / columns;
        panel.ItemHeight = CardWidth(browser) / 1.47 + (browser == SourceFolders ? 62 : 41);
    }

    private static double CardWidth(GridView browser) =>
        Math.Max(148, (browser.ItemsPanelRoot as ItemsWrapGrid)?.ItemWidth - 15 ?? 215);

    private static void SizeCard(GridView browser, GridViewItem item)
    {
        if (item.ContentTemplateRoot is not Grid card || card.Children.FirstOrDefault() is not Border thumbnail)
            return;
        card.Width = CardWidth(browser);
        thumbnail.Height = card.Width / 1.47;
    }
}
