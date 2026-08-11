using System.Diagnostics;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using AgentExecutionBroker.Contracts;

namespace AgentExecutionBroker.Host;

public sealed class BrokerHost : IAsyncDisposable
{
    private readonly BrokerService _service;
    private readonly Mutex _mutex;
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);
    private bool _disposed;

    public BrokerHost()
    {
        _mutex = new Mutex(false, @"Local\AgentExecutionBroker.v1", out var createdNew);
        if (!createdNew)
        {
            _mutex.Dispose();
            throw new InvalidOperationException("Another Agent Execution Broker Host already owns this user session.");
        }

        _service = new BrokerService();
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var pipe = new NamedPipeServerStream(BrokerProtocol.PipeName, PipeDirection.InOut, 16,
                PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            try
            {
                await pipe.WaitForConnectionAsync(cancellationToken);
                _ = Task.Run(() => HandleConnectionAsync(pipe), CancellationToken.None);
            }
            catch
            {
                pipe.Dispose();
                throw;
            }
        }
    }

    private async Task HandleConnectionAsync(NamedPipeServerStream pipe)
    {
        await using (pipe)
        {
            try
            {
                var bytes = await ReadFrameAsync(pipe, CancellationToken.None);
                var request = JsonSerializer.Deserialize<BrokerRequest>(bytes, _json)
                    ?? throw new InvalidDataException("Broker request was empty.");
                var response = await _service.HandleAsync(request, _json, CancellationToken.None);
                await WriteFrameAsync(pipe, JsonSerializer.SerializeToUtf8Bytes(response, _json), CancellationToken.None);
            }
            catch (Exception ex)
            {
                Trace.WriteLine(ex.ToString());
                try
                {
                    var response = BrokerResponse.Failure("broker-request-failed", ex.Message);
                    await WriteFrameAsync(pipe, JsonSerializer.SerializeToUtf8Bytes(response, _json), CancellationToken.None);
                }
                catch (Exception writeException)
                {
                    Trace.WriteLine(writeException.ToString());
                }
            }
        }
    }

    internal static async Task<byte[]> ReadFrameAsync(Stream stream, CancellationToken cancellationToken)
    {
        var header = new byte[sizeof(int)];
        await stream.ReadExactlyAsync(header, cancellationToken);
        var length = BitConverter.ToInt32(header, 0);
        if (length <= 0 || length > 4 * 1024 * 1024)
        {
            throw new InvalidDataException("Broker frame length is invalid.");
        }

        var payload = new byte[length];
        await stream.ReadExactlyAsync(payload, cancellationToken);
        return payload;
    }

    internal static async Task WriteFrameAsync(Stream stream, byte[] payload, CancellationToken cancellationToken)
    {
        if (payload.Length == 0 || payload.Length > 4 * 1024 * 1024)
        {
            throw new InvalidDataException("Broker response frame length is invalid.");
        }

        await stream.WriteAsync(BitConverter.GetBytes(payload.Length), cancellationToken);
        await stream.WriteAsync(payload, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        await _service.DisposeAsync();
        _mutex.Dispose();
    }
}

public sealed class BrokerService : IAsyncDisposable
{
    private readonly BrokerStore _store;
    private readonly WorkerJob _workerJob = new();
    private readonly object _gate = new();
    private readonly Dictionary<Guid, RunningWorker> _workers = [];
    private readonly string _hostInstanceId = Guid.NewGuid().ToString();
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };
    public BrokerService(string? root = null)
    {
        _store = new BrokerStore(root);
        ReconcileInheritedRuns();
    }

    public async Task<BrokerResponse> HandleAsync(BrokerRequest request, JsonSerializerOptions protocolJson, CancellationToken cancellationToken)
    {
        try
        {
            object result = request.Operation switch
            {
                "start_run" => await StartAsync(Deserialize<StartRunRequest>(request.Payload, protocolJson), cancellationToken),
                "get_run" => GetRun(Deserialize<RunQuery>(request.Payload, protocolJson)),
                "list_runs" => ListRuns(Deserialize<ListRunsRequest>(request.Payload, protocolJson)),
                "get_output" => GetOutput(Deserialize<OutputQuery>(request.Payload, protocolJson)),
                "cancel_run" => await CancelAsync(Deserialize<RunQuery>(request.Payload, protocolJson), cancellationToken),
                _ => throw new ArgumentException("Unsupported Broker operation.")
            };
            return BrokerResponse.Success(JsonSerializer.SerializeToElement(result, protocolJson));
        }
        catch (BrokerRequestException ex)
        {
            return BrokerResponse.Failure(ex.Code, ex.Message);
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
            return BrokerResponse.Failure("broker-operation-failed", ex.Message);
        }
    }

    private async Task<RunRecord> StartAsync(StartRunRequest request, CancellationToken cancellationToken)
    {
        ValidateStart(request);
        var run = new RunRecord(Guid.NewGuid(), request.ProviderId, Path.GetFullPath(request.WorkingDirectory),
            request.Prompt, request.ExecutionProfile, request.Repository, "Accepted", DateTimeOffset.UtcNow,
            null, null, null, false, null, null, null);
        run = run.WithExecutionIdentity(_hostInstanceId, _workerJob.JobId, run.RunId.ToString(),
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(request.Prompt))));
        _store.WriteRun(run);
        var worker = new RunningWorker(run.RunId);
        lock (_gate)
        {
            _workers.Add(run.RunId, worker);
        }
        _ = Task.Run(() => ExecuteAsync(run, worker, cancellationToken), CancellationToken.None);
        await Task.CompletedTask;
        return run;
    }

    private RunRecord GetRun(RunQuery query) => _store.ReadRun(query.RunId)
        ?? throw new BrokerRequestException("run-not-found", "The requested run does not exist.");

    private RunPage ListRuns(ListRunsRequest request)
    {
        var limit = request.Limit ?? BrokerProtocol.DefaultRunLimit;
        if (limit is < 1 or > BrokerProtocol.MaximumRunLimit)
        {
            throw new BrokerRequestException("invalid-limit", "list_runs limit is outside the supported range.");
        }

        return _store.ListRuns(limit, request.Cursor);
    }

    private OutputPage GetOutput(OutputQuery request)
    {
        var maxRecords = request.MaxRecords ?? BrokerProtocol.DefaultOutputRecords;
        var maxBytes = request.MaxBytes ?? BrokerProtocol.DefaultOutputBytes;
        if (maxRecords is < 1 or > BrokerProtocol.MaximumOutputRecords || maxBytes is < 1 or > BrokerProtocol.MaximumOutputBytes)
        {
            throw new BrokerRequestException("invalid-output-bound", "get_output bounds are outside the supported range.");
        }

        if (_store.ReadRun(request.RunId) is null)
        {
            throw new BrokerRequestException("run-not-found", "The requested run does not exist.");
        }

        return _store.ReadOutput(request.RunId, request.AfterSequence ?? 0, maxRecords, maxBytes);
    }

    private async Task<RunRecord> CancelAsync(RunQuery query, CancellationToken cancellationToken)
    {
        RunRecord run;
        lock (_gate)
        {
            run = GetRun(query);
            if (IsTerminal(run.State))
            {
                return run;
            }

            run = Transition(run with { CancelRequested = true, CancelDelivery = "Pending" }, "CancelRequested");
            _store.WriteRun(run);
            _workers.TryGetValue(query.RunId, out var worker);
            var process = worker?.Process;

            if (process is null || process.HasExited)
            {
                return run;
            }

            try
            {
                process.Kill(entireProcessTree: true);
                run = _store.ReadRun(query.RunId) ?? run;
                if (IsTerminal(run.State))
                {
                    return run;
                }

                run = run with { CancelDelivery = "Delivered" };
                _store.WriteRun(run);
            }
            catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                Trace.WriteLine(ex.ToString());
                run = _store.ReadRun(query.RunId) ?? run;
                if (IsTerminal(run.State))
                {
                    return run;
                }

                run = run with { CancelDelivery = "Failed", Diagnostic = ex.Message };
                _store.WriteRun(run);
                _store.AppendOutput(run.RunId, "diagnostic", $"Cancellation delivery failed: {ex.Message}");
            }
        }

        await Task.CompletedTask;
        return run;
    }

    private async Task ExecuteAsync(RunRecord accepted, RunningWorker worker, CancellationToken cancellationToken)
    {
        var run = accepted;
        Process process = null!;
        try
        {
            lock (_gate)
            {
                run = _store.ReadRun(accepted.RunId) ?? accepted;
                run = PrepareWorkerStart(run, _hostInstanceId);
                if (run.State == "CancelledBeforeStart")
                {
                    _store.WriteRun(run);
                    _store.PublishTerminal(run);
                    return;
                }

                _store.WriteRun(run);
                var startInfo = CopilotCliAdapter.CreateStartInfo(run);
                process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
                if (!process.Start())
                {
                    throw new InvalidOperationException("Copilot CLI did not start.");
                }

                worker.Process = process;
                _workerJob.Assign(process);
                run = Transition(run with { ProviderProcessId = process.Id }, "Running");
                _store.WriteRun(run);
            }
            var stdout = OutputCopy.CopyOutputAsync(process.StandardOutput, run.RunId, "structured", _store, cancellationToken);
            var stderr = OutputCopy.CopyOutputAsync(process.StandardError, run.RunId, "stderr", _store, cancellationToken);
            await Task.WhenAll(process.WaitForExitAsync(cancellationToken), stdout, stderr);

            lock (_gate)
            {
                var current = _store.ReadRun(run.RunId) ?? run;
                if (IsTerminal(current.State))
                {
                    return;
                }

                run = ObserveProcessExit(current, process.ExitCode, _hostInstanceId, DateTimeOffset.UtcNow);
                _store.WriteRun(run);
                _store.PublishTerminal(run);
            }
        }
        catch (OperationCanceledException ex)
        {
            Trace.WriteLine(ex.ToString());
            StopUnownedWorker(worker);
            FinalizeFailure(run, "HostStopping", ex.Message);
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
            StopUnownedWorker(worker);
            FinalizeFailure(run, "StartFailed", ex.Message);
        }
        finally
        {
            if (worker.Process is not null)
            {
                worker.Process.Dispose();
            }
            lock (_gate)
            {
                _workers.Remove(accepted.RunId);
            }
        }
    }

    private void FinalizeFailure(RunRecord run, string state, string diagnostic)
    {
        lock (_gate)
        {
            var current = _store.ReadRun(run.RunId) ?? run;
            if (IsTerminal(current.State))
            {
                return;
            }

            var final = Transition(current with { CompletedAt = DateTimeOffset.UtcNow, Diagnostic = diagnostic }, state);
            _store.WriteRun(final);
            _store.AppendOutput(final.RunId, "diagnostic", diagnostic);
            _store.PublishTerminal(final);
        }
    }

    private static void StopUnownedWorker(RunningWorker worker)
    {
        if (worker.Process is not { HasExited: false } process)
        {
            return;
        }

        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            Trace.WriteLine(ex.ToString());
        }
    }

    private void ReconcileInheritedRuns()
    {
        foreach (var run in _store.EnumerateRuns().Where(run => !IsTerminal(run.State)))
        {
            var reconciled = Transition(run with
            {
                CompletedAt = DateTimeOffset.UtcNow,
                Diagnostic = "The previous Host lost authority. Its worker Job Object was closed."
            }, "HostLostWorkerTreeTerminated");
            _store.WriteRun(reconciled);
            _store.PublishTerminal(reconciled);
        }
    }

    private static T Deserialize<T>(JsonElement payload, JsonSerializerOptions json) =>
        payload.Deserialize<T>(json) ?? throw new BrokerRequestException("invalid-request", "Broker request payload is invalid.");

    private static void ValidateStart(StartRunRequest request)
    {
        if (request.ProviderId != "github-copilot-cli")
        {
            throw new BrokerRequestException("unsupported-provider", "Only github-copilot-cli is available in Operational v0.");
        }
        if (request.ExecutionProfile != BrokerProtocol.CodingProfile)
        {
            throw new BrokerRequestException("unsupported-profile", "execution_profile must be coding-v1.");
        }
        if (!Path.IsPathFullyQualified(request.WorkingDirectory) || !Directory.Exists(request.WorkingDirectory))
        {
            throw new BrokerRequestException("invalid-working-directory", "working_directory must be an existing absolute directory.");
        }
        if (string.IsNullOrWhiteSpace(request.Prompt))
        {
            throw new BrokerRequestException("invalid-prompt", "prompt must not be empty.");
        }
        if (request.Repository is { Length: > 512 })
        {
            throw new BrokerRequestException("invalid-repository", "repository is too long.");
        }
    }

    private RunRecord Transition(RunRecord run, string state)
    {
        return AppendTransition(run, state, _hostInstanceId, DateTimeOffset.UtcNow);
    }

    internal static RunRecord PrepareWorkerStart(RunRecord run, string authority)
    {
        return run.CancelRequested
            ? AppendTransition(run with { CancelDelivery = "NotStarted", CompletedAt = DateTimeOffset.UtcNow }, "CancelledBeforeStart", authority, DateTimeOffset.UtcNow)
            : AppendTransition(run with { StartedAt = DateTimeOffset.UtcNow }, "Starting", authority, DateTimeOffset.UtcNow);
    }

    internal static string DetermineProcessExitState(bool cancelRequested, string? cancelDelivery) =>
        cancelRequested
            ? cancelDelivery == "Delivered" ? "CancelledByBroker" : cancelDelivery == "Failed" ? "ExitedAfterFailedCancel" : "Exited"
            : "Exited";

    internal static RunRecord ObserveProcessExit(RunRecord run, int exitCode, string authority, DateTimeOffset observedAt)
    {
        if (IsTerminal(run.State))
        {
            return run;
        }

        return AppendTransition(run with
        {
            CompletedAt = observedAt,
            ExitCode = exitCode
        }, DetermineProcessExitState(run.CancelRequested, run.CancelDelivery), authority, observedAt);
    }

    private static RunRecord AppendTransition(RunRecord run, string state, string authority, DateTimeOffset observedAt)
    {
        var transitions = run.StateTransitions.ToList();
        transitions.Add(new RunStateTransition(transitions.Count + 1, state, observedAt, authority));
        return run with { State = state, StateTransitions = transitions };
    }

    private static bool IsTerminal(string state) => state is "Exited" or "CancelledByBroker" or "CancelledBeforeStart" or "ExitedAfterFailedCancel" or "StartFailed" or "HostStopping" or "HostLostWorkerTreeTerminated";

    public ValueTask DisposeAsync()
    {
        _workerJob.Dispose();
        return ValueTask.CompletedTask;
    }

    private sealed class RunningWorker(Guid runId)
    {
        public Guid RunId { get; } = runId;
        public Process? Process { get; set; }
    }
}

public sealed class BrokerStore
{
    public const string HomeEnvironmentVariable = "AGENT_EXECUTION_BROKER_HOME";
    private readonly string _root;
    private readonly string _runsRoot;
    private static readonly Encoding Utf8WithoutBom = new UTF8Encoding(false);
    private static readonly JsonSerializerOptions LineJson = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };
    private readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };
    private readonly JsonSerializerOptions _runJson = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };
    private readonly object _writeGate = new();

    public BrokerStore(string? root = null)
    {
        _root = ResolveRoot(root);
        _runsRoot = Path.Combine(_root, "runs");
        Directory.CreateDirectory(_runsRoot);
    }

    public string RootPath => _root;

    public void WriteRun(RunRecord run)
    {
        lock (_writeGate)
        {
            var directory = RunDirectory(run.RunId);
            Directory.CreateDirectory(directory);
            WriteAtomic(Path.Combine(directory, "run.json"), JsonSerializer.Serialize(run, _runJson));
        }
    }

    public RunRecord? ReadRun(Guid runId)
    {
        var path = Path.Combine(RunDirectory(runId), "run.json");
        if (!File.Exists(path))
        {
            return null;
        }

        return JsonSerializer.Deserialize<RunRecord>(File.ReadAllText(path), _runJson);
    }

    public IEnumerable<RunRecord> EnumerateRuns()
    {
        if (!Directory.Exists(_runsRoot))
        {
            return [];
        }
        return Directory.EnumerateFiles(_runsRoot, "run.json", SearchOption.AllDirectories)
            .Select(path => JsonSerializer.Deserialize<RunRecord>(File.ReadAllText(path), _runJson))
            .OfType<RunRecord>();
    }

    public RunPage ListRuns(int limit, string? cursor)
    {
        var all = EnumerateRuns().OrderByDescending(run => run.AcceptedAt).ThenByDescending(run => run.RunId).ToArray();
        var offset = DecodeCursor(cursor);
        if (offset > all.Length)
        {
            throw new BrokerRequestException("invalid-cursor", "list_runs cursor is invalid.");
        }
        var runs = all.Skip(offset).Take(limit).ToArray();
        var next = offset + runs.Length;
        return new RunPage(runs, next < all.Length ? EncodeCursor(next) : null, next < all.Length);
    }

    public void AppendOutput(Guid runId, string stream, string text)
    {
        lock (_writeGate)
        {
            var path = Path.Combine(RunDirectory(runId), "broker-output-v1.jsonl");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var sequence = ReadLastSequence(path) + 1;
            foreach (var chunk in SplitUtf8(text, BrokerProtocol.MaximumOutputRecordBytes))
            {
                var output = new OutputRecord(sequence++, DateTimeOffset.UtcNow, stream, chunk);
                using var outputStream = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.Read);
                using var writer = new StreamWriter(outputStream, Utf8WithoutBom);
                writer.WriteLine(JsonSerializer.Serialize(output, LineJson));
            }
        }
    }

    public OutputPage ReadOutput(Guid runId, long afterSequence, int maxRecords, int maxBytes)
    {
        var path = Path.Combine(RunDirectory(runId), "broker-output-v1.jsonl");
        if (!File.Exists(path))
        {
            return new OutputPage(runId, [], afterSequence, false, null);
        }
        var records = new List<OutputRecord>();
        var bytes = 0;
        var hasMore = false;
        string? reason = null;
        foreach (var line in File.ReadLines(path, Encoding.UTF8))
        {
            var record = DeserializeOutputLine(line);
            if (record is null || record.Sequence <= afterSequence)
            {
                continue;
            }
            var recordBytes = Encoding.UTF8.GetByteCount(line) + Environment.NewLine.Length;
            if (records.Count == maxRecords)
            {
                hasMore = true;
                reason = "max_records";
                break;
            }
            if (records.Count > 0 && bytes + recordBytes > maxBytes)
            {
                hasMore = true;
                reason = "max_bytes";
                break;
            }
            records.Add(record);
            bytes += recordBytes;
        }
        return new OutputPage(runId, records, records.LastOrDefault()?.Sequence ?? afterSequence, hasMore, reason);
    }

    public void PublishTerminal(RunRecord run)
    {
        try
        {
            var spool = ResolveSpoolRoot();
            Directory.CreateDirectory(spool);
            var eventPath = Path.Combine(spool, $"agent-execution-terminal-{run.RunId:N}.json");
            if (File.Exists(eventPath))
            {
                return;
            }
            var terminal = new TerminalEventV1(1, "agent-execution-broker.run-terminal",
                $"agent-execution-broker:run:{run.RunId}:terminal", run.RunId, run.ProviderId, run.State,
                run.CompletedAt ?? DateTimeOffset.UtcNow, $"{run.ProviderId} run {run.State}",
                $"broker-run:{run.RunId}", run.Repository);
            WriteAtomic(eventPath, JsonSerializer.Serialize(terminal, _json));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            Trace.WriteLine(ex.ToString());
            var failed = run with { NotificationDisposition = "Failed", Diagnostic = ex.Message };
            WriteRun(failed);
            AppendOutput(run.RunId, "diagnostic", $"Terminal event publication failed: {ex.Message}");
        }
    }

    private string RunDirectory(Guid runId) => Path.Combine(_runsRoot, runId.ToString("N"));
    private long ReadLastSequence(string path) => !File.Exists(path) ? 0 : File.ReadLines(path, Encoding.UTF8)
        .Select(DeserializeOutputLine)
        .OfType<OutputRecord>().Select(record => record.Sequence).DefaultIfEmpty(0).Max();
    private OutputRecord? DeserializeOutputLine(string line) => JsonSerializer.Deserialize<OutputRecord>(line.TrimStart('\uFEFF'), _json);
    private static IEnumerable<string> SplitUtf8(string text, int maxBytes)
    {
        if (string.IsNullOrEmpty(text))
        {
            yield break;
        }
        var builder = new StringBuilder();
        var bytes = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            var value = rune.ToString();
            var size = Encoding.UTF8.GetByteCount(value);
            if (builder.Length > 0 && bytes + size > maxBytes)
            {
                yield return builder.ToString();
                builder.Clear();
                bytes = 0;
            }
            builder.Append(value);
            bytes += size;
        }
        if (builder.Length > 0) yield return builder.ToString();
    }
    private static string ResolveRoot(string? root)
    {
        var value = root ?? Environment.GetEnvironmentVariable(HomeEnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(value))
        {
            if (!Path.IsPathFullyQualified(value)) throw new ArgumentException($"{HomeEnvironmentVariable} must be an absolute path.");
            return Path.GetFullPath(value);
        }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AgentExecutionBroker");
    }
    private static string ResolveSpoolRoot()
    {
        var value = Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_SPOOL_HOME");
        if (!string.IsNullOrWhiteSpace(value))
        {
            if (!Path.IsPathFullyQualified(value)) throw new ArgumentException("CODEX_NOTIFICATION_SPOOL_HOME must be an absolute path.");
            return Path.GetFullPath(value);
        }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexNotificationRuntime", "spool");
    }
    private static void WriteAtomic(string path, string content)
    {
        var temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temporary, content, Utf8WithoutBom);
        File.Move(temporary, path, true);
    }
    private static string EncodeCursor(int offset) => Convert.ToBase64String(Encoding.UTF8.GetBytes(offset.ToString(System.Globalization.CultureInfo.InvariantCulture)));
    private static int DecodeCursor(string? cursor)
    {
        if (string.IsNullOrWhiteSpace(cursor)) return 0;
        try
        {
            return int.TryParse(Encoding.UTF8.GetString(Convert.FromBase64String(cursor)), out var value) && value >= 0 ? value : throw new FormatException();
        }
        catch (FormatException)
        {
            throw new BrokerRequestException("invalid-cursor", "list_runs cursor is invalid.");
        }
    }
}

public static class CopilotCliAdapter
{
    public static ProcessStartInfo CreateStartInfo(RunRecord run)
    {
        if (run.ExecutionProfile != BrokerProtocol.CodingProfile) throw new ArgumentException("Unsupported execution profile.");
        var info = new ProcessStartInfo("copilot")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = run.WorkingDirectory
        };
        info.ArgumentList.Add("-p");
        info.ArgumentList.Add(run.Prompt);
        info.ArgumentList.Add("-C");
        info.ArgumentList.Add(run.WorkingDirectory);
        info.ArgumentList.Add("--output-format");
        info.ArgumentList.Add("json");
        info.ArgumentList.Add("--no-ask-user");
        info.ArgumentList.Add("--no-auto-update");
        info.ArgumentList.Add("--session-id");
        info.ArgumentList.Add(run.RunId.ToString());
        info.ArgumentList.Add("--allow-tool=read,write,shell");
        return info;
    }
}

internal static class OutputCopy
{
    public static async Task CopyOutputAsync(StreamReader reader, Guid runId, string stream, BrokerStore store, CancellationToken cancellationToken)
    {
        while (await reader.ReadLineAsync(cancellationToken) is { } line)
        {
            store.AppendOutput(runId, stream, line + Environment.NewLine);
        }
    }
}

internal sealed class WorkerJob : IDisposable
{
    private readonly Microsoft.Win32.SafeHandles.SafeFileHandle _handle;
    public Guid JobId { get; } = Guid.NewGuid();
    public WorkerJob()
    {
        _handle = Native.CreateKillOnCloseJob();
    }
    public void Assign(Process process) => Native.Assign(_handle, process.SafeHandle);
    public void Dispose() => _handle.Dispose();
    private static class Native
    {
        private const uint JobObjectExtendedLimitInformation = 9;
        private const uint JobObjectLimitKillOnJobClose = 0x00002000;
        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateJobObject(IntPtr attributes, string? name);
        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)] private static extern bool SetInformationJobObject(Microsoft.Win32.SafeHandles.SafeFileHandle job, uint infoClass, IntPtr info, uint length);
        [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)] private static extern bool AssignProcessToJobObject(Microsoft.Win32.SafeHandles.SafeFileHandle job, Microsoft.Win32.SafeHandles.SafeProcessHandle process);
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] private struct BasicLimit { public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit; public long Affinity; public uint PriorityClass; public uint SchedulingClass; }
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] private struct IoCounters { public ulong ReadOperationCount; public ulong WriteOperationCount; public ulong OtherOperationCount; public ulong ReadTransferCount; public ulong WriteTransferCount; public ulong OtherTransferCount; }
        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] private struct ExtendedLimit { public BasicLimit BasicLimitInformation; public IoCounters IoInfo; public UIntPtr ProcessMemoryLimit; public UIntPtr JobMemoryLimit; public UIntPtr PeakProcessMemoryUsed; public UIntPtr PeakJobMemoryUsed; }
        public static Microsoft.Win32.SafeHandles.SafeFileHandle CreateKillOnCloseJob()
        {
            var raw = CreateJobObject(IntPtr.Zero, null);
            if (raw == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
            var handle = new Microsoft.Win32.SafeHandles.SafeFileHandle(raw, true);
            var settings = new ExtendedLimit { BasicLimitInformation = new BasicLimit { LimitFlags = JobObjectLimitKillOnJobClose } };
            var size = System.Runtime.InteropServices.Marshal.SizeOf<ExtendedLimit>();
            var pointer = System.Runtime.InteropServices.Marshal.AllocHGlobal(size);
            try
            {
                System.Runtime.InteropServices.Marshal.StructureToPtr(settings, pointer, false);
                if (!SetInformationJobObject(handle, JobObjectExtendedLimitInformation, pointer, (uint)size)) throw new System.ComponentModel.Win32Exception();
                return handle;
            }
            catch { handle.Dispose(); throw; }
            finally { System.Runtime.InteropServices.Marshal.FreeHGlobal(pointer); }
        }
        public static void Assign(Microsoft.Win32.SafeHandles.SafeFileHandle job, Microsoft.Win32.SafeHandles.SafeProcessHandle process)
        {
            if (!AssignProcessToJobObject(job, process)) throw new System.ComponentModel.Win32Exception();
        }
    }
}

internal sealed class BrokerRequestException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
