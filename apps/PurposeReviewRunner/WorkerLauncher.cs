using System.Diagnostics;

namespace PurposeReviewRunner;

public sealed class DetachedWorkerLauncher : IWorkerLauncher
{
    private readonly RunnerPaths paths;
    private readonly IWindowsJobInspector windowsJobInspector;
    private readonly IWindowsProcessLauncher windowsProcessLauncher;
    private readonly bool useWindowsLaunch;

    public DetachedWorkerLauncher(RunnerPaths paths)
        : this(paths, new WindowsJobInspector(), new WindowsProcessLauncher(), OperatingSystem.IsWindows())
    {
    }

    public DetachedWorkerLauncher(
        RunnerPaths paths,
        IWindowsJobInspector windowsJobInspector,
        IWindowsProcessLauncher windowsProcessLauncher,
        bool useWindowsLaunch)
    {
        this.paths = paths;
        this.windowsJobInspector = windowsJobInspector;
        this.windowsProcessLauncher = windowsProcessLauncher;
        this.useWindowsLaunch = useWindowsLaunch;
    }

    public WorkerLaunchResult Launch(string runId)
    {
        var executable = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executable) || !File.Exists(executable))
        {
            throw new RunnerException("WORKER_START_FAILED", "The runner executable path was not available.", ExitCodes.RuntimeError);
        }

        var runDirectory = Path.Combine(paths.StateRoot, runId);
        try
        {
            using var log = LauncherLogWriter.Open(runDirectory);
            log.WriteLaunchHeader();
            log.Write("runnerVersion", Protocol.RunnerVersion);
            log.Write("runId", runId);
            var round = TryReadRound(runId);
            if (round is int roundValue)
            {
                log.Write("round", roundValue);
            }

            log.Write("pid", Environment.ProcessId);
            log.Write("configPathOverrideSet", !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_CONFIG_PATH")));
            log.Write("stateRootOverrideSet", !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_STATE_ROOT")));
            log.Write("workerCommand", "work --run " + runId);

            return useWindowsLaunch
                ? LaunchWindows(executable, runId, log)
                : LaunchUnix(executable, runId, log);
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("WORKER_START_FAILED", $"The review worker process did not start: {exception.Message}", ExitCodes.RuntimeError, exception);
        }
    }

    private WorkerLaunchResult LaunchWindows(string executable, string runId, LauncherLogWriter log)
    {
        log.Write("os", "Windows");
        WindowsJobSnapshot snapshot;
        try
        {
            snapshot = windowsJobInspector.InspectCurrentProcess();
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            log.Write("inJob", "unknown");
            log.Write("jobInspectionFailed", true);
            log.Write("jobInspectionError", exception.Message);
            log.Write("failClosed", true);
            log.Write("failClosedReason", "Job object membership could not be queried; refusing to launch a worker inside an unknown job.");
            if (exception is RunnerException)
            {
                throw;
            }

            throw new RunnerException("WORKER_START_FAILED", $"The review worker process did not start: {exception.Message}", ExitCodes.RuntimeError, exception);
        }

        log.Write("inJob", snapshot.InJob);
        if (snapshot.LimitFlags is uint limitFlags)
        {
            log.WriteHex("limitFlags", limitFlags);
        }

        if (snapshot.BreakawayOk is bool breakawayOk)
        {
            log.Write("breakawayOk", breakawayOk);
        }

        if (snapshot.SilentBreakawayOk is bool silentBreakawayOk)
        {
            log.Write("silentBreakawayOk", silentBreakawayOk);
        }

        if (snapshot.KillOnJobClose is bool killOnJobClose)
        {
            log.Write("killOnJobClose", killOnJobClose);
        }

        if (snapshot.LimitQueryFailed)
        {
            log.Write("jobLimitQueryFailed", true);
            if (snapshot.LimitQueryNativeErrorCode is int nativeErrorCode)
            {
                log.Write("jobLimitQueryNativeErrorCode", nativeErrorCode);
            }

            if (!string.IsNullOrWhiteSpace(snapshot.LimitQueryNativeErrorMessage))
            {
                log.Write("jobLimitQueryNativeErrorMessage", snapshot.LimitQueryNativeErrorMessage);
            }
        }

        var strategy = WindowsWorkerLaunchStrategySelector.Select(snapshot);
        var creationFlags = WindowsWorkerLaunchStrategySelector.GetCreationFlags(strategy);
        log.Write("selectedStrategy", WindowsWorkerLaunchStrategySelector.ToLogName(strategy));
        log.Write("outsideJobIntended", true);
        log.WriteHex("creationFlags", creationFlags);

        var request = WindowsProcessLaunchRequest.ForWorker(executable, runId, creationFlags);
        var launched = WindowsWorkerLaunchStrategySelector.UsesCreateProcess(strategy)
            ? windowsProcessLauncher.CreateDetachedProcess(request)
            : windowsProcessLauncher.CreateExternalProcess(request);
        WriteLaunchResult(log, launched);
        if (strategy == WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate)
        {
            log.Write("environmentBlockPassed", true);
        }

        if (!launched.Success)
        {
            log.Write("failClosed", true);
            log.Write(
                "failClosedReason",
                strategy == WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate
                    ? "The process is in a job object and Win32_Process.Create with CREATE_BREAKAWAY_FROM_JOB could not start a worker outside that job chain."
                    : "The selected CreateProcess launch path failed.");
            throw new RunnerException("WORKER_START_FAILED", FormatPublicFailure(launched), ExitCodes.RuntimeError);
        }

        return ReadLaunchResult(launched.ProcessId!.Value);
    }

    private static WorkerLaunchResult LaunchUnix(string executable, string runId, LauncherLogWriter log)
    {
        log.Write("os", "Unix");
        log.Write("selectedStrategy", "unix-detached-exec");
        log.Write("outsideJobIntended", true);
        log.Write("launchApi", "Process.Start");

        const string shell = "/bin/sh";
        if (!File.Exists(shell))
        {
            log.Write("success", false);
            log.Write("failClosed", true);
            log.Write("failClosedReason", "sh was not found at /bin/sh.");
            throw new RunnerException("WORKER_START_FAILED", "sh was not found at /bin/sh.", ExitCodes.RuntimeError);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = shell,
            WorkingDirectory = Path.GetDirectoryName(executable) ?? Environment.CurrentDirectory,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        // exec で PID を worker に保ち、標準streamを親のpipeから切り離す。
        startInfo.ArgumentList.Add("-c");
        startInfo.ArgumentList.Add("exec \"$1\" work --run \"$2\" </dev/null >/dev/null 2>&1");
        startInfo.ArgumentList.Add("sh");
        startInfo.ArgumentList.Add(executable);
        startInfo.ArgumentList.Add(runId);

        try
        {
            var process = Process.Start(startInfo)
                ?? throw new RunnerException("WORKER_START_FAILED", "The review worker process did not start.", ExitCodes.RuntimeError);
            try
            {
                process.StandardInput.Close();
                process.StandardOutput.Close();
                process.StandardError.Close();
                log.Write("success", true);
                log.Write("nativeErrorCode", 0);
                log.Write("workerPid", process.Id);
                return ReadLaunchResult(process.Id);
            }
            finally
            {
                process.Dispose();
            }
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            log.Write("success", false);
            log.Write("nativeErrorMessage", exception.Message);
            log.Write("failClosed", true);
            log.Write("failClosedReason", "Unix detached worker launch failed.");
            if (exception is RunnerException)
            {
                throw;
            }
            throw new RunnerException("WORKER_START_FAILED", $"The review worker process did not start: {exception.Message}", ExitCodes.RuntimeError, exception);
        }
    }

    private static void WriteLaunchResult(LauncherLogWriter log, WindowsProcessLaunchResult launched)
    {
        log.Write("launchApi", launched.LaunchApi);
        log.WriteHex("creationFlags", launched.CreationFlags);
        log.Write("success", launched.Success);
        log.Write("nativeErrorCode", launched.NativeErrorCode);
        if (!string.IsNullOrWhiteSpace(launched.NativeErrorMessage))
        {
            log.Write("nativeErrorMessage", launched.NativeErrorMessage);
        }

        if (launched.WmiReturnValue is uint wmiReturnValue)
        {
            log.Write("wmiReturnValue", unchecked((int)wmiReturnValue));
        }

        if (launched.ProcessId is int processId)
        {
            log.Write("workerPid", processId);
        }
    }

    private static string FormatPublicFailure(WindowsProcessLaunchResult launched)
    {
        if (launched.LaunchApi == "Win32_Process.Create" && launched.WmiReturnValue is uint wmiReturnValue)
        {
            return $"The review worker process did not start: Win32_Process.Create returned {wmiReturnValue} ({launched.NativeErrorMessage}).";
        }

        if (launched.NativeErrorCode != 0)
        {
            return $"The review worker process did not start: {launched.NativeErrorMessage} (Win32 error {launched.NativeErrorCode}).";
        }

        return $"The review worker process did not start: {launched.NativeErrorMessage}";
    }

    private int? TryReadRound(string runId)
    {
        try
        {
            return new JobStore(paths.StateRoot).Load(runId).Round;
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return null;
        }
    }

    private static WorkerLaunchResult ReadLaunchResult(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            return new(processId, new DateTimeOffset(process.StartTime.ToUniversalTime()));
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return new(processId, DateTimeOffset.UtcNow);
        }
    }
}
