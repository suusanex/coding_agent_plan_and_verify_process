using System.Threading;

namespace CodexLocalInbox.Services;

public sealed class SpoolMonitor : IAsyncDisposable
{
    private readonly object _stateGate = new();
    private readonly SpoolInboxService _service;
    private readonly Func<IReadOnlyList<Models.InboxEntry>, Task> _publish;
    private readonly TimeSpan _debounce;
    private readonly TimeSpan _period;
    private readonly CancellationTokenSource _cts = new();
    private readonly SemaphoreSlim _scanGate = new(1, 1);
    private readonly HashSet<Task> _debounceTasks = [];
    private FileSystemWatcher? _watcher;
    private Task? _periodicTask;
    private Task? _stopTask;
    private long _debounceVersion;
    private int _state;

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
        ThrowIfStopping();
        await ScanAsync(cancellationToken).ConfigureAwait(false);
        ThrowIfStopping();
        ConfigureWatcher();
        lock (_stateGate)
        {
            ThrowIfStopping();
            _periodicTask ??= PeriodicLoopAsync(_cts.Token);
        }
    }

    public Task RequestRescanAsync(CancellationToken cancellationToken = default)
    {
        ThrowIfStopping();
        return ScanAsync(cancellationToken);
    }

    private void ConfigureWatcher()
    {
        lock (_stateGate)
        {
            if (_state != 0 || _watcher is not null)
            {
                return;
            }

            var root = _service.RootPath;
            if (!Directory.Exists(root))
            {
                return;
            }

            var watcher = new FileSystemWatcher(root, "*.json")
            {
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                IncludeSubdirectories = false
            };
            watcher.Created += OnFileEvent;
            watcher.Changed += OnFileEvent;
            watcher.Deleted += OnFileEvent;
            watcher.Renamed += OnRenamed;
            watcher.EnableRaisingEvents = true;
            _watcher = watcher;
        }
    }

    private void OnFileEvent(object sender, FileSystemEventArgs args) => ScheduleDebouncedScan();
    private void OnRenamed(object sender, RenamedEventArgs args) => ScheduleDebouncedScan();

    private void ScheduleDebouncedScan()
    {
        Task debounceTask;
        long debounceVersion;
        lock (_stateGate)
        {
            if (_state != 0)
            {
                return;
            }

            debounceVersion = ++_debounceVersion;
            debounceTask = DebouncedScanAsync(debounceVersion, _cts.Token);
            _debounceTasks.Add(debounceTask);
        }

        _ = debounceTask.ContinueWith(
            completedTask =>
            {
                _ = completedTask.Exception;
                lock (_stateGate)
                {
                    _debounceTasks.Remove(completedTask);
                }
            },
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    private async Task DebouncedScanAsync(long debounceVersion, CancellationToken token)
    {
        try
        {
            await Task.Delay(_debounce, token).ConfigureAwait(false);
            lock (_stateGate)
            {
                if (_state != 0 || debounceVersion != _debounceVersion)
                {
                    return;
                }
            }

            await ScanAsync(token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
        }
    }

    private async Task PeriodicLoopAsync(CancellationToken token)
    {
        using var timer = new PeriodicTimer(_period);
        try
        {
            while (await timer.WaitForNextTickAsync(token).ConfigureAwait(false))
            {
                try
                {
                    ConfigureWatcher();
                    await ScanAsync(token).ConfigureAwait(false);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                }
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
    }

    private async Task ScanAsync(CancellationToken cancellationToken)
    {
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            _cts.Token);
        await _scanGate.WaitAsync(linkedCts.Token).ConfigureAwait(false);
        try
        {
            var snapshot = await Task.Run(_service.Scan, linkedCts.Token).ConfigureAwait(false);
            await _publish(snapshot).ConfigureAwait(false);
        }
        finally
        {
            _scanGate.Release();
        }
    }

    public Task StopAsync()
    {
        lock (_stateGate)
        {
            if (_stopTask is not null)
            {
                return _stopTask;
            }

            _state = 1;
            _stopTask = StopCoreAsync();
            return _stopTask;
        }
    }

    private async Task StopCoreAsync()
    {
        _cts.Cancel();
        FileSystemWatcher? watcher;
        Task? periodicTask;
        Task[] debounceTasks;
        lock (_stateGate)
        {
            watcher = _watcher;
            _watcher = null;
            periodicTask = _periodicTask;
            debounceTasks = [.. _debounceTasks];
        }

        watcher?.Dispose();

        var backgroundTasks = periodicTask is null
            ? debounceTasks
            : [periodicTask, .. debounceTasks];
        foreach (var task in backgroundTasks)
        {
            try
            {
                await task.ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (_cts.IsCancellationRequested)
            {
            }
        }

        await _scanGate.WaitAsync().ConfigureAwait(false);
        _scanGate.Release();

        lock (_stateGate)
        {
            _state = 2;
        }

        _cts.Dispose();
        _scanGate.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(false);
        GC.SuppressFinalize(this);
    }

    private void ThrowIfStopping()
    {
        if (Volatile.Read(ref _state) != 0)
        {
            throw new ObjectDisposedException(nameof(SpoolMonitor));
        }
    }
}
