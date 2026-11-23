using Microsoft.UI.Input;
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

    private void InitializeTitleBar()
    {
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        SearchOverlay.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => UpdateTitleBarRegions());
        PreviewOverlay.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => UpdateTitleBarRegions());
    }

    private void TitleBarLoaded(object sender, RoutedEventArgs args)
    {
        AppTitleBar.Loaded -= TitleBarLoaded;
        AppTitleBar.XamlRoot.Changed += (_, _) => UpdateTitleBarRegions();
        UpdateTitleBarRegions();
    }

    private void TitleBarSizeChanged(object sender, SizeChangedEventArgs args) => UpdateTitleBarRegions();

    private void UpdateTitleBarRegions()
    {
        if (!AppTitleBar.IsLoaded)
            return;
        var scale = AppTitleBar.XamlRoot.RasterizationScale;
        var left = AppWindow.TitleBar.LeftInset / scale;
        var right = Math.Max(left, Root.ActualWidth - AppWindow.TitleBar.RightInset / scale);
        var overlay = SearchOverlay.Visibility == Visibility.Visible || PreviewOverlay.Visibility == Visibility.Visible;
        Rect bounds;
        if (overlay)
            bounds = new Rect(left, 0, right - left, AppTitleBar.ActualHeight);
        else if (sidebarAnimation is not null)
            bounds = new Rect(12, 0, 184, AppTitleBar.ActualHeight);
        else
            bounds = BoundsInRoot(SidebarTools);
        var clippedLeft = Math.Max(left, bounds.Left);
        var clippedRight = Math.Max(clippedLeft, Math.Min(right, bounds.Right));
        var rectangle = new Windows.Graphics.RectInt32((int)Math.Round(clippedLeft * scale),
            (int)Math.Round(bounds.Top * scale), (int)Math.Round((clippedRight - clippedLeft) * scale),
            (int)Math.Round(bounds.Height * scale));
        InputNonClientPointerSource.GetForWindowId(AppWindow.Id)
            .SetRegionRects(NonClientRegionKind.Passthrough, [rectangle]);
    }

    private void ToggleSidebar(object sender, RoutedEventArgs args)
    {
        var width = Sidebar.ActualWidth;
        var offset = SidebarToolsOffset.X;
        sidebarAnimation?.Stop();
        sidebarAnimation = null;
        Sidebar.Width = width;
        SidebarToolsOffset.X = offset;
        sidebarCollapsed = !sidebarCollapsed;
        Sidebar.Visibility = Visibility.Visible;
        Sidebar.IsHitTestVisible = !sidebarCollapsed;
        SidebarToggleDivider.Height = sidebarCollapsed ? 5 : 12;
        var label = sidebarCollapsed ? "展开侧边栏" : "收起侧边栏";
        AutomationProperties.SetName(SidebarToggleButton, label);
        ToolTipService.SetToolTip(SidebarToggleButton, label);
        var targetWidth = sidebarCollapsed ? 0 : 200;
        var targetOffset = sidebarCollapsed ? 0 : 112;
        if (!new UISettings().AnimationsEnabled)
        {
            Sidebar.Width = targetWidth;
            SidebarToolsOffset.X = targetOffset;
            Sidebar.Visibility = sidebarCollapsed ? Visibility.Collapsed : Visibility.Visible;
            UpdateTitleBarRegions();
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
            Sidebar.Visibility = sidebarCollapsed ? Visibility.Collapsed : Visibility.Visible;
            if (ReferenceEquals(sidebarAnimation, animation))
                sidebarAnimation = null;
            UpdateTitleBarRegions();
        };
        sidebarAnimation = animation;
        UpdateTitleBarRegions();
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
        if (browser.ItemsPanelRoot is Panel panel)
        {
            foreach (var item in panel.Children.OfType<GridViewItem>())
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
        panel.ItemWidth = Math.Floor(width / columns);
        panel.ItemHeight = CardWidth(browser) / 1.47 + (browser == SourceFolders ? 62 : 41);
    }

    private static double CardWidth(GridView browser) =>
        Math.Max(148, ((ItemsWrapGrid)browser.ItemsPanelRoot).ItemWidth - 15);

    private static void SizeCard(GridView browser, GridViewItem item)
    {
        if (item.ContentTemplateRoot is not Grid card || card.Children.FirstOrDefault() is not Border thumbnail)
            return;
        card.Width = CardWidth(browser);
        thumbnail.Height = card.Width / 1.47;
    }
}
