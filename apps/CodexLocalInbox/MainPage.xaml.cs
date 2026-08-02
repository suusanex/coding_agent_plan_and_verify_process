using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml;
using CodexLocalInbox.ViewModels;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace CodexLocalInbox;

/// <summary>
/// The main content page displayed inside the application window.
/// </summary>
public sealed partial class MainPage : Page
{
    public InboxViewModel ViewModel { get; } = new();

    public MainPage()
    {
        InitializeComponent();
        DataContext = ViewModel;
        Loaded += async (_, _) => await ViewModel.StartAsync();
    }

    public static Visibility BoolToVisibility(bool value) =>
        value ? Visibility.Visible : Visibility.Collapsed;

    public static Visibility Not(bool value) =>
        value ? Visibility.Collapsed : Visibility.Visible;

    public static bool NotBool(bool value) => !value;

    public static string ActionName(string action, string title) =>
        $"{action} notification {title}";
}
