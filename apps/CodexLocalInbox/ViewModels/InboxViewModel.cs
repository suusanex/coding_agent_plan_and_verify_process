using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexLocalInbox.Models;
using CodexLocalInbox.Services;

namespace CodexLocalInbox.ViewModels;

public partial class InboxViewModel : ObservableObject, IDisposable
{
    private readonly SpoolInboxService _service;
    private readonly SpoolMonitor _monitor;
    private readonly Func<Uri, Task<bool>> _launchUri;
    private bool _disposed;

    public ObservableCollection<InboxEntry> Entries { get; } = [];

    [ObservableProperty]
    public partial bool IsLoading { get; set; }

    [ObservableProperty]
    public partial bool HasError { get; set; }

    [ObservableProperty]
    public partial string StatusMessage { get; set; } = string.Empty;

    public bool IsEmpty => !IsLoading && Entries.Count == 0 && !HasError;
    public bool IsErrorState => !IsLoading && Entries.Count == 0 && HasError;
    public bool HasEntries => Entries.Count > 0;

    public InboxViewModel(
        SpoolInboxService? service = null,
        Func<Uri, Task<bool>>? launchUri = null)
    {
        _service = service ?? new SpoolInboxService();
        _launchUri = launchUri ?? (uri => Windows.System.Launcher.LaunchUriAsync(uri).AsTask());
        _monitor = new SpoolMonitor(_service, PublishSnapshotAsync);
        Entries.CollectionChanged += (_, _) =>
        {
            OnPropertyChanged(nameof(IsEmpty));
            OnPropertyChanged(nameof(IsErrorState));
            OnPropertyChanged(nameof(HasEntries));
        };
    }

    public async Task StartAsync()
    {
        IsLoading = true;
        try
        {
            await _monitor.StartAsync();
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException)
        {
            HasError = true;
            StatusMessage = ex.Message;
            IsLoading = false;
            OnPropertyChanged(nameof(IsErrorState));
        }
    }

    [RelayCommand]
    private async Task RefreshAsync()
    {
        IsLoading = true;
        HasError = false;
        StatusMessage = string.Empty;
        try
        {
            await _monitor.RequestRescanAsync();
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException)
        {
            HasError = true;
            StatusMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
            OnPropertyChanged(nameof(IsEmpty));
            OnPropertyChanged(nameof(IsErrorState));
        }
    }

    [RelayCommand]
    private async Task ResumeAsync(InboxEntry? entry)
    {
        if (entry?.ResumeUri is null ||
            !UriLaunchPolicy.TryGetResumeUri(entry.ResumeUri, out var uri))
        {
            ShowError("This resume link is not allowed.");
            return;
        }

        await LaunchAsync(uri);
    }

    [RelayCommand]
    private async Task OpenResultAsync(InboxEntry? entry)
    {
        if (entry?.ResultUri is null ||
            !UriLaunchPolicy.TryGetResultUri(entry.ResultUri, out var uri))
        {
            ShowError("This result link is not allowed.");
            return;
        }

        await LaunchAsync(uri);
    }

    [RelayCommand]
    private async Task DeleteAsync(InboxEntry? entry)
    {
        if (entry is null)
        {
            return;
        }

        var result = await Task.Run(() => _service.Delete(entry));
        if (!result.Succeeded)
        {
            ShowError(result.ErrorMessage ?? "Unable to delete the file.");
            return;
        }

        Entries.Remove(entry);
    }

    private async Task LaunchAsync(Uri uri)
    {
        try
        {
            App.Window?.Activate();
            if (!await _launchUri(uri))
            {
                ShowError("Windows could not open the requested link.");
            }
        }
        catch (Exception ex) when (ex is UriFormatException or InvalidOperationException)
        {
            ShowError($"Unable to open the requested link: {ex.Message}");
        }
    }

    private Task PublishSnapshotAsync(IReadOnlyList<InboxEntry> snapshot)
    {
        void Apply()
        {
            Entries.Clear();
            foreach (var entry in snapshot)
            {
                Entries.Add(entry);
            }

            IsLoading = false;
            HasError = false;
            StatusMessage = string.Empty;
            OnPropertyChanged(nameof(IsEmpty));
            OnPropertyChanged(nameof(IsErrorState));
        }

        if (App.DispatcherQueue is { } dispatcher && !dispatcher.HasThreadAccess)
        {
            dispatcher.TryEnqueue(Apply);
        }
        else
        {
            Apply();
        }

        return Task.CompletedTask;
    }

    private void ShowError(string message)
    {
        HasError = true;
        StatusMessage = message;
        OnPropertyChanged(nameof(IsErrorState));
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _monitor.Dispose();
    }
}
