using Microsoft.UI.Xaml;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using CommunityToolkit.Mvvm.Input;
using System.Runtime.InteropServices;
using WinRT.Interop;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace CodexLocalInbox;

/// <summary>
/// The application window. This hosts a Frame that displays pages. Add your
/// UI and logic to MainPage.xaml / MainPage.xaml.cs instead of here so you
/// can use Page features such as navigation events and the Loaded lifecycle.
/// </summary>
public sealed partial class MainWindow : Window
{
    private bool _allowClose;
    private bool _isExiting;
    public IRelayCommand ShowWindowCommand { get; }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(nint hWnd);

    public MainWindow()
    {
        ShowWindowCommand = new RelayCommand(ShowInbox);
        InitializeComponent();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        AppWindow.SetIcon("Assets/AppIcon.ico");
        Closed += OnClosed;
        SizeToUtilityWindow();

        // Navigate the root frame to the main page on startup.
        RootFrame.Navigate(typeof(MainPage));
    }

    private void SizeToUtilityWindow()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var scale = GetDpiForWindow(hwnd) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32(
            (int)Math.Round(760 * scale),
            (int)Math.Round(720 * scale)));
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        if (_allowClose)
        {
            return;
        }

        args.Handled = true;
        AppWindow.Hide();
    }

    private void ShowInbox_Click(object sender, RoutedEventArgs e) => ShowInbox();

    private async void Exit_Click(object sender, RoutedEventArgs e) => await ExitApplicationAsync();

    public void ShowInbox()
    {
        AppWindow.Show();
        Activate();
    }

    private async Task ExitApplicationAsync()
    {
        if (_isExiting)
        {
            return;
        }

        _isExiting = true;
        if (RootFrame.Content is MainPage page)
        {
            await page.ViewModel.DisposeAsync();
        }

        _allowClose = true;
        TrayIcon.Dispose();
        Close();
    }
}
