using Microsoft.UI.Xaml;

namespace IPreview;

public partial class App : Application
{
    private Window? window;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        window = new MainWindow();
        window.AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "AppIcon.ico"));
        window.Activate();
    }
}
