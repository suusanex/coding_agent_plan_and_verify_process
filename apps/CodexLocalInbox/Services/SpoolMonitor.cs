using System.Threading;

namespace CodexLocalInbox.Services;

public sealed class SpoolMonitor : IDisposable
{
    private readonly SpoolInboxService _service;
    private readonly Func<IReadOnlyList<Models.InboxEntry>, Task> _publish;
    private readonly TimeSpan _debounce;
    private readonly TimeSpan _period;
    private readonly CancellationTokenSource _cts = new();
    private readonly SemaphoreSlim _scanGate = new(1, 1);
    private FileSystemWatcher? _watcher;
    private CancellationTokenSource? _debounceCts;
    private Task? _periodicTask;
    private bool _disposed;

    public SpoolMonitor(
        SpoolInboxService service,
        Func<IReadOnlyList<Models.InboxEntry>, Task> publish,
        TimeSpan? debounce = null,
        TimeSpan? period = null)
    {
        _service = service;
        _publish = publish;
        _debounce = debounce ?? TimeSpan.FromMilliseconds(350);
        _period = period ?? TimeSpan.FromSeconds(30);
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfDisposed();
        await ScanAsync(cancellationToken).ConfigureAwait(false);
        ConfigureWatcher();
        _periodicTask = PeriodicLoopAsync(_cts.Token);
    }

    public Task RequestRescanAsync(CancellationToken cancellationToken = default) =>
        ScanAsync(cancellationToken);

    private void ConfigureWatcher()
    {
        if (_watcher is not null)
        {
            return;
        }

        var root = _service.RootPath;
        if (!Directory.Exists(root))
        {
            return;
        }

        _watcher = new FileSystemWatcher(root, "*.json")
        {
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
            IncludeSubdirectories = false,
            EnableRaisingEvents = true
        };
        _watcher.Created += OnFileEvent;
        _watcher.Changed += OnFileEvent;
        _watcher.Deleted += OnFileEvent;
        _watcher.Renamed += OnRenamed;
    }

    private void OnFileEvent(object sender, FileSystemEventArgs args) => ScheduleDebouncedScan();
    private void OnRenamed(object sender, RenamedEventArgs args) => ScheduleDebouncedScan();

    private void ScheduleDebouncedScan()
    {
        if (_disposed)
        {
            return;
        }

        _debounceCts?.Cancel();
        _debounceCts?.Dispose();
        _debounceCts = CancellationTokenSource.CreateLinkedTokenSource(_cts.Token);
        var token = _debounceCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(_debounce, token).ConfigureAwait(false);
                await ScanAsync(token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
            }
        }, token);
    }

    private async Task PeriodicLoopAsync(CancellationToken token)
    {
        using var timer = new PeriodicTimer(_period);
        try
        {
            while (await timer.WaitForNextTickAsync(token).ConfigureAwait(false))
            {
                ConfigureWatcher();
                await ScanAsync(token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
    }

    private async Task ScanAsync(CancellationToken cancellationToken)
    {
        await _scanGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            var snapshot = await Task.Run(_service.Scan, cancellationToken).ConfigureAwait(false);
            await _publish(snapshot).ConfigureAwait(false);
        }
        finally
        {
            _scanGate.Release();
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _cts.Cancel();
        _watcher?.Dispose();
        _debounceCts?.Cancel();
        _debounceCts?.Dispose();
        _scanGate.Dispose();
        _cts.Dispose();
    }

    private void ThrowIfDisposed()
    {
        if (_disposed)
        {
            throw new ObjectDisposedException(nameof(SpoolMonitor));
        }
    }
}
