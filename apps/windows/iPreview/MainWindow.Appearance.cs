using System.Security;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Win32;

namespace IPreview;

public sealed partial class MainWindow
{
    private const string PreferencesKey = @"HKEY_CURRENT_USER\Software\AMindFlow\iPreview";
    private const string ThemeValue = "Theme";

    private void RestoreTheme()
    {
        var theme = ElementTheme.Default;
        try
        {
            theme = Registry.GetValue(PreferencesKey, ThemeValue, null) switch
            {
                nameof(ElementTheme.Light) => ElementTheme.Light,
                nameof(ElementTheme.Dark) => ElementTheme.Dark,
                _ => ElementTheme.Default
            };
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        {
            ShowNotice("无法读取主题设置", error.Message, InfoBarSeverity.Warning);
        }
        ApplyTheme(theme);
    }

    private void ChangeTheme(object sender, RoutedEventArgs args)
    {
        var option = (RadioMenuFlyoutItem)sender;
        var theme = Enum.Parse<ElementTheme>((string)option.Tag);
        try
        {
            Registry.SetValue(PreferencesKey, ThemeValue, theme.ToString());
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        {
            ApplyTheme(Root.RequestedTheme);
            ShowNotice("无法保存主题设置", error.Message);
            return;
        }
        ApplyTheme(theme);
    }

    private void ApplyTheme(ElementTheme theme)
    {
        Root.RequestedTheme = theme;
        AppWindow.TitleBar.PreferredTheme = theme switch
        {
            ElementTheme.Light => TitleBarTheme.Light,
            ElementTheme.Dark => TitleBarTheme.Dark,
            _ => TitleBarTheme.UseDefaultAppMode
        };
        SystemThemeOption.IsChecked = theme == ElementTheme.Default;
        LightThemeOption.IsChecked = theme == ElementTheme.Light;
        DarkThemeOption.IsChecked = theme == ElementTheme.Dark;
        var option = theme switch
        {
            ElementTheme.Light => LightThemeOption,
            ElementTheme.Dark => DarkThemeOption,
            _ => SystemThemeOption
        };
        var label = $"主题：{option.Text}";
        AutomationProperties.SetName(ThemeButton, label);
        ToolTipService.SetToolTip(ThemeButton, label);
    }
}
