using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using PurposeReviewRunner;

return await MainAsync(args);

static async Task<int> MainAsync(string[] args)
{
    Trace.Listeners.Clear();
    Trace.Listeners.Add(new TextWriterTraceListener(Console.Error));
    Trace.AutoFlush = true;
    StreamWriter? workerLog = null;
    try
    {
        var paths = CreatePaths();
        var command = CliParser.Parse(args);
        if (command is WorkCommand work)
        {
            DetachCurrentUnixSession();
            workerLog = AttachWorkerLog(paths, work.RunId);
        }
        var application = new RunnerApplication(
            paths,
            new ExecutableResolver(),
            new SystemProcessRunner(TimeSpan.FromMinutes(10)),
            new DetachedWorkerLauncher(paths));
        var result = await application.ExecuteAsync(command, CancellationToken.None);
        Console.WriteLine(JsonSerializer.Serialize(result.Output, JsonDefaults.Options));
        return result.ExitCode;
    }
    catch (Exception exception)
    {
        Trace.TraceError(exception.ToString());
        var runnerException = exception as RunnerException;
        var exitCode = runnerException?.ExitCode ?? ExitCodes.RuntimeError;
        var code = runnerException?.Code ?? "UNEXPECTED_ERROR";
        var output = RunnerOutput.FromError(code, exception.Message);
        Console.WriteLine(JsonSerializer.Serialize(output, JsonDefaults.Options));
        return exitCode;
    }
    finally
    {
        workerLog?.Dispose();
    }
}

static RunnerPaths CreatePaths()
{
    var config = Environment.GetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_CONFIG_PATH");
    var state = Environment.GetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_STATE_ROOT");
    var configSet = !string.IsNullOrWhiteSpace(config);
    var stateSet = !string.IsNullOrWhiteSpace(state);
    if (configSet != stateSet)
    {
        throw new RunnerException("USER_PATH_UNAVAILABLE", "PURPOSE_REVIEW_RUNNER_CONFIG_PATH and PURPOSE_REVIEW_RUNNER_STATE_ROOT must be set together.");
    }
    if (configSet)
    {
        return new(Path.GetFullPath(config!), Path.GetFullPath(state!));
    }
    return RunnerPaths.CreateDefault();
}

static void DetachCurrentUnixSession()
{
    if (OperatingSystem.IsWindows())
    {
        return;
    }

    if (UnixNative.setsid() != -1)
    {
        return;
    }

    Trace.TraceError(new System.ComponentModel.Win32Exception(Marshal.GetLastPInvokeError()).ToString());
}

static StreamWriter AttachWorkerLog(RunnerPaths paths, string runId)
{
    if (!Guid.TryParseExact(runId, "D", out _))
    {
        throw new RunnerException("INVALID_RUN_ID", "run-id must be a canonical UUID.");
    }
    var directory = Path.Combine(paths.StateRoot, runId);
    Directory.CreateDirectory(directory);
    var stream = new FileStream(Path.Combine(directory, "worker.log"), FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
    var writer = new StreamWriter(stream, new System.Text.UTF8Encoding(false)) { AutoFlush = true };
    Trace.Listeners.Add(new TextWriterTraceListener(writer));
    Console.SetOut(writer);
    Console.SetError(writer);
    return writer;
}

static class UnixNative
{
    [DllImport("libc", SetLastError = true)]
    public static extern int setsid();
}
