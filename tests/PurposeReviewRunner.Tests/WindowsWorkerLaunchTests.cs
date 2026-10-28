using System.Diagnostics;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PurposeReviewRunner;
using PurposeReviewRunnerFakeProvider;

namespace PurposeReviewRunnerTests;

[TestClass]
[DoNotParallelize]
public sealed class WindowsWorkerLaunchTests
{
    [TestMethod]
    public void JobSnapshotClassifiesNotInJobAndBreakawayStates()
    {
        var notInJob = WindowsJobSnapshot.NotInJob();
        Assert.IsFalse(notInJob.InJob);
        Assert.IsNull(notInJob.LimitFlags);
        Assert.IsNull(notInJob.BreakawayOk);
        Assert.IsNull(notInJob.SilentBreakawayOk);
        Assert.IsNull(notInJob.KillOnJobClose);

        var breakaway = WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.BreakawayOkFlag);
        Assert.IsTrue(breakaway.InJob);
        Assert.IsTrue(breakaway.BreakawayOk);
        Assert.IsFalse(breakaway.SilentBreakawayOk);
        Assert.IsFalse(breakaway.KillOnJobClose);

        var silent = WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.SilentBreakawayOkFlag);
        Assert.IsTrue(silent.SilentBreakawayOk);
        Assert.IsFalse(silent.BreakawayOk);

        var restrictive = WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.KillOnJobCloseFlag);
        Assert.AreEqual(0x00002000u, restrictive.LimitFlags);
        Assert.IsFalse(restrictive.BreakawayOk);
        Assert.IsFalse(restrictive.SilentBreakawayOk);
        Assert.IsTrue(restrictive.KillOnJobClose);
    }

    [TestMethod]
    public void LaunchStrategyUsesWmiForAnyJobIncludingBreakawayPermittedNestedJobs()
    {
        Assert.AreEqual(
            WindowsWorkerLaunchStrategy.DetachedCreateProcess,
            WindowsWorkerLaunchStrategySelector.Select(WindowsJobSnapshot.NotInJob()));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate,
            WindowsWorkerLaunchStrategySelector.Select(WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.BreakawayOkFlag)));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate,
            WindowsWorkerLaunchStrategySelector.Select(WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.SilentBreakawayOkFlag)));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate,
            WindowsWorkerLaunchStrategySelector.Select(WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.KillOnJobCloseFlag)));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate,
            WindowsWorkerLaunchStrategySelector.Select(WindowsJobSnapshot.FromLimitFlags(0)));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate,
            WindowsWorkerLaunchStrategySelector.Select(WindowsJobSnapshot.FromLimitFlags(
                WindowsJobSnapshot.BreakawayOkFlag | WindowsJobSnapshot.KillOnJobCloseFlag)));
        Assert.IsTrue(WindowsWorkerLaunchStrategySelector.UsesCreateProcess(WindowsWorkerLaunchStrategy.DetachedCreateProcess));
        Assert.IsFalse(WindowsWorkerLaunchStrategySelector.UsesCreateProcess(WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategySelector.BaseCreationFlags,
            WindowsWorkerLaunchStrategySelector.GetCreationFlags(WindowsWorkerLaunchStrategy.DetachedCreateProcess));
        Assert.AreEqual(
            WindowsWorkerLaunchStrategySelector.BaseCreationFlags | WindowsWorkerLaunchStrategySelector.CreateBreakawayFromJob,
            WindowsWorkerLaunchStrategySelector.GetCreationFlags(WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate));
    }

    [TestMethod]
    public void JobLimitQueryFailureIsWrittenToLauncherLogAndStillUsesWmi()
    {
        using var root = new TemporaryDirectory();
        var inspector = new FakeWindowsJobInspector(WindowsJobSnapshot.InJobWithFailedLimitQuery(5, "Access is denied"));
        var processLauncher = new FakeWindowsProcessLauncher
        {
            ExternalResult = SucceededLaunch("Win32_Process.Create"),
            DetachedResult = SucceededLaunch("CreateProcess")
        };
        var launcher = CreateLauncher(root.Paths, inspector, processLauncher);
        var runId = PrepareJob(root.Paths);

        var launched = launcher.Launch(runId);

        Assert.AreEqual(Environment.ProcessId, launched.ProcessId);
        Assert.AreEqual(1, processLauncher.ExternalCallCount);
        Assert.AreEqual(0, processLauncher.DetachedCallCount);
        var log = File.ReadAllText(LauncherLogPath(root.Paths, runId));
        StringAssert.Contains(log, "inJob=true");
        StringAssert.Contains(log, "jobLimitQueryFailed=true");
        StringAssert.Contains(log, "jobLimitQueryNativeErrorCode=5");
        StringAssert.Contains(log, "jobLimitQueryNativeErrorMessage=Access is denied");
        StringAssert.Contains(log, "selectedStrategy=external-win32-process-create");
    }

    [TestMethod]
    public void NotInJobLaunchUsesDetachedCreateProcess()
    {
        using var root = new TemporaryDirectory();
        var inspector = new FakeWindowsJobInspector(WindowsJobSnapshot.NotInJob());
        var processLauncher = new FakeWindowsProcessLauncher
        {
            DetachedResult = SucceededLaunch("CreateProcess"),
            ExternalResult = SucceededLaunch("Win32_Process.Create")
        };
        var launcher = CreateLauncher(root.Paths, inspector, processLauncher);
        var runId = PrepareJob(root.Paths);

        var launched = launcher.Launch(runId);

        Assert.AreEqual(Environment.ProcessId, launched.ProcessId);
        Assert.AreEqual(1, processLauncher.DetachedCallCount);
        Assert.AreEqual(0, processLauncher.ExternalCallCount);
        var log = File.ReadAllText(LauncherLogPath(root.Paths, runId));
        StringAssert.Contains(log, "selectedStrategy=detached-create-process");
        StringAssert.Contains(log, "inJob=false");
        StringAssert.Contains(log, "launchApi=CreateProcess");
    }

    [TestMethod]
    [DataRow(WindowsJobSnapshot.KillOnJobCloseFlag)]
    [DataRow(WindowsJobSnapshot.BreakawayOkFlag)]
    [DataRow(WindowsJobSnapshot.SilentBreakawayOkFlag)]
    [DataRow(WindowsJobSnapshot.BreakawayOkFlag | WindowsJobSnapshot.KillOnJobCloseFlag)]
    public void InJobLaunchUsesExternalPathAndDoesNotCallCreateProcess(uint limitFlags)
    {
        using var root = new TemporaryDirectory();
        var inspector = new FakeWindowsJobInspector(WindowsJobSnapshot.FromLimitFlags(limitFlags));
        var processLauncher = new FakeWindowsProcessLauncher
        {
            ExternalResult = SucceededLaunch("Win32_Process.Create"),
            DetachedResult = SucceededLaunch("CreateProcess")
        };
        var launcher = CreateLauncher(root.Paths, inspector, processLauncher);
        var runId = PrepareJob(root.Paths);

        var launched = launcher.Launch(runId);

        Assert.AreEqual(Environment.ProcessId, launched.ProcessId);
        Assert.AreEqual(1, processLauncher.ExternalCallCount);
        Assert.AreEqual(0, processLauncher.DetachedCallCount);
        Assert.AreEqual(
            WindowsWorkerLaunchStrategySelector.BaseCreationFlags | WindowsWorkerLaunchStrategySelector.CreateBreakawayFromJob,
            processLauncher.LastExternalRequest!.CreationFlags);
        StringAssert.Contains(File.ReadAllText(LauncherLogPath(root.Paths, runId)), "selectedStrategy=external-win32-process-create");
    }

    [TestMethod]
    [DoNotParallelize]
    public async Task WorkerLaunchFailureWritesLauncherLogAndKeepsProtocolV4Json()
    {
        const string secret = "super-secret-value-xyz";
        using var root = new TemporaryDirectory();
        Environment.SetEnvironmentVariable("PURPOSE_REVIEW_TEST_TOKEN", secret);
        try
        {
            var inspector = new FakeWindowsJobInspector(WindowsJobSnapshot.FromLimitFlags(WindowsJobSnapshot.KillOnJobCloseFlag));
            var processLauncher = new FakeWindowsProcessLauncher
            {
                ExternalResult = new WindowsProcessLaunchResult(
                    false,
                    null,
                    5,
                    "Access is denied",
                    "Win32_Process.Create",
                    WindowsWorkerLaunchStrategySelector.GetCreationFlags(WindowsWorkerLaunchStrategy.ExternalWin32ProcessCreate),
                    2)
            };
            var launcher = CreateLauncher(root.Paths, inspector, processLauncher);
            root.WriteConfig();
            File.WriteAllText(Path.Combine(root.Repository, "goal.md"), "goal");
            var application = new RunnerApplication(
                root.Paths,
                new FakeExecutableResolver(),
                new ScriptedProcessRunner("copilot"),
                launcher);

            var inputPath = Path.Combine(root.Root, "review-input.json");
            File.WriteAllText(inputPath, JsonSerializer.Serialize(RunnerFixture.CreateInput(), JsonDefaults.Options));
            var result = await application.ExecuteAsync(new StartCommand(root.Repository, inputPath), CancellationToken.None);

            Assert.AreEqual("WORKER_START_FAILED", result.Output.Error?.Code);
            Assert.AreEqual(Protocol.Version, result.Output.ProtocolVersion);
            Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
            StringAssert.Contains(result.Output.Error!.Message, "Win32_Process.Create returned 2");
            Assert.AreEqual(0, processLauncher.DetachedCallCount);
            Assert.AreEqual(1, processLauncher.ExternalCallCount);

            var log = File.ReadAllText(LauncherLogPath(root.Paths, result.Output.RunId!));
            StringAssert.Contains(log, "inJob=true");
            StringAssert.Contains(log, "limitFlags=0x00002000");
            StringAssert.Contains(log, "breakawayOk=false");
            StringAssert.Contains(log, "silentBreakawayOk=false");
            StringAssert.Contains(log, "killOnJobClose=true");
            StringAssert.Contains(log, "selectedStrategy=external-win32-process-create");
            StringAssert.Contains(log, "launchApi=Win32_Process.Create");
            StringAssert.Contains(log, "nativeErrorCode=5");
            StringAssert.Contains(log, "wmiReturnValue=2");
            StringAssert.Contains(log, "outsideJobIntended=true");
            StringAssert.Contains(log, "failClosed=true");
            Assert.IsFalse(log.Contains("fallback=true", StringComparison.Ordinal));
            Assert.IsFalse(log.Contains(secret, StringComparison.Ordinal));
            Assert.IsFalse(log.Contains("PURPOSE_REVIEW_TEST_TOKEN", StringComparison.Ordinal));
        }
        finally
        {
            Environment.SetEnvironmentVariable("PURPOSE_REVIEW_TEST_TOKEN", null);
        }
    }

    [TestMethod]
    [DoNotParallelize]
    public void EnvironmentCaptureIncludesRunnerOverridesAndSkipsEqualsPrefixedNames()
    {
        var configPath = Path.Combine(Path.GetTempPath(), "purpose-review-config.json");
        var stateRoot = Path.Combine(Path.GetTempPath(), "purpose-review-state");
        Environment.SetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_CONFIG_PATH", configPath);
        Environment.SetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_STATE_ROOT", stateRoot);
        try
        {
            var block = WindowsProcessLauncher.CaptureCurrentEnvironmentBlock();
            CollectionAssert.Contains(block, "PURPOSE_REVIEW_RUNNER_CONFIG_PATH=" + configPath);
            CollectionAssert.Contains(block, "PURPOSE_REVIEW_RUNNER_STATE_ROOT=" + stateRoot);
            Assert.IsFalse(block.Any(value => value.StartsWith('=')));
        }
        finally
        {
            Environment.SetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_CONFIG_PATH", null);
            Environment.SetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_STATE_ROOT", null);
        }
    }

    [TestMethod]
    [DoNotParallelize]
    public async Task RestrictiveJobObjectDoesNotKillDurableWorker()
    {
        if (!OperatingSystem.IsWindows() ||
            !string.Equals(Environment.GetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_WINDOWS_JOB_QUALIFICATION"), "1", StringComparison.Ordinal))
        {
            Assert.Inconclusive("Opt-in Windows Job Object qualification. Set PURPOSE_REVIEW_RUNNER_WINDOWS_JOB_QUALIFICATION=1 to run it.");
            return;
        }

        var root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-job-tests", Guid.NewGuid().ToString("N"));
        var repository = Path.Combine(root, "repository");
        var configPath = Path.Combine(root, "config", "config.json");
        var stateRoot = Path.Combine(root, "state", "runs");
        var providerErrorLog = Path.Combine(root, "fake-provider-errors.log");
        Directory.CreateDirectory(repository);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        var input = RunnerFixture.CreateInput() with
        {
            Purpose = RunnerFixture.CreateInput().Purpose with
            {
                Body = "FAKE-INTEGRATION-CONTEXT\nFAKE-JAPANESE-END-終端",
                Original = "FAKE-INTEGRATION-CONTEXT\nFAKE-JAPANESE-END-終端"
            }
        };
        var inputPath = Path.Combine(root, "review-input.json");
        File.WriteAllText(inputPath, JsonSerializer.Serialize(input, JsonDefaults.Options));
        var executable = CreateFakeProviderLauncher(root);
        File.WriteAllText(
            configPath,
            JsonSerializer.Serialize(new RunnerConfig(1, "copilot", executable, "test-model", "high", null), JsonDefaults.Options));
        var runnerPath = Path.Combine(
            Path.GetDirectoryName(typeof(RunnerApplication).Assembly.Location)!,
            "purpose-review-runner.exe");
        var helperPath = Path.Combine(
            Path.GetDirectoryName(typeof(WindowsWorkerLaunchTests).Assembly.Location)!,
            "purpose-review-restrictive-job-helper.exe");

        try
        {
            var helper = await RunHelperAsync(
                helperPath,
                runnerPath,
                repository,
                inputPath,
                configPath,
                stateRoot,
                new Dictionary<string, string>
                {
                    ["PURPOSE_REVIEW_FAKE_PROVIDER_DELAY_MS"] = "4000",
                    ["PURPOSE_REVIEW_FAKE_PROVIDER_ERROR_LOG"] = providerErrorLog
                });
            Assert.AreEqual(0, helper.ExitCode, helper.StandardOutput + helper.StandardError);
            using var startDocument = JsonDocument.Parse(helper.StandardOutput.Trim());
            Assert.AreEqual(JobStatuses.Running, startDocument.RootElement.GetProperty("jobStatus").GetString());
            var runId = startDocument.RootElement.GetProperty("runId").GetString();
            Assert.IsFalse(string.IsNullOrWhiteSpace(runId));

            var jobPath = Path.Combine(stateRoot, runId!, "job.json");
            var pidDeadline = DateTime.UtcNow + TimeSpan.FromSeconds(10);
            int? workerPid = null;
            while (DateTime.UtcNow < pidDeadline)
            {
                using var jobDocument = JsonDocument.Parse(File.ReadAllText(jobPath));
                if (jobDocument.RootElement.TryGetProperty("pid", out var pidElement) && pidElement.ValueKind == JsonValueKind.Number)
                {
                    workerPid = pidElement.GetInt32();
                    break;
                }

                if (jobDocument.RootElement.GetProperty("jobStatus").GetString() != JobStatuses.Running)
                {
                    Assert.Fail("Worker reached a terminal job state before its process id was recorded: " + jobDocument.RootElement.GetProperty("jobStatus").GetString());
                }

                await Task.Delay(100);
            }

            Assert.IsNotNull(workerPid, "The durable worker did not record its process id while running.");
            using (var worker = Process.GetProcessById(workerPid.Value))
            {
                Assert.IsFalse(worker.HasExited, "Worker was killed with the restrictive job helper.");
            }

            var log = File.ReadAllText(Path.Combine(stateRoot, runId!, "launcher.log"));
            StringAssert.Contains(log, "selectedStrategy=external-win32-process-create");
            StringAssert.Contains(log, "outsideJobIntended=true");
            StringAssert.Contains(log, "success=true");
            StringAssert.Contains(log, "configPathOverrideSet=true");
            StringAssert.Contains(log, "stateRootOverrideSet=true");
            Assert.IsFalse(Directory.Exists(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "purpose-review-runner",
                "runs",
                runId!)));

            var completed = await PollStatusAsync(runnerPath, runId!, configPath, stateRoot, TimeSpan.FromSeconds(30), providerErrorLog);
            if (completed.RootElement.GetProperty("status").GetString() != ReviewStatuses.Findings && File.Exists(providerErrorLog))
            {
                Assert.Fail(File.ReadAllText(providerErrorLog));
            }
            Assert.AreEqual(ReviewStatuses.Findings, completed.RootElement.GetProperty("status").GetString());
            Assert.AreEqual(JobStatuses.Succeeded, completed.RootElement.GetProperty("jobStatus").GetString());
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, true);
            }
        }
    }

    private static DetachedWorkerLauncher CreateLauncher(
        RunnerPaths paths,
        IWindowsJobInspector inspector,
        IWindowsProcessLauncher processLauncher) =>
        new(paths, inspector, processLauncher, useWindowsLaunch: true);

    private static string PrepareJob(RunnerPaths paths)
    {
        var runId = Guid.NewGuid().ToString("D");
        new JobStore(paths.StateRoot).Save(new JobState(
            Protocol.JobSchemaVersion,
            runId,
            1,
            JobOperations.Start,
            JobStatuses.Running,
            DateTimeOffset.UtcNow,
            Repository: Path.GetFullPath(Path.Combine(paths.StateRoot, "repo")),
            Provider: new ProviderSnapshot("copilot", FakeExecutableResolver.Expected("copilot"), "test-model", "high", null),
            InputHash: "test-input-hash"));
        return runId;
    }

    private static string LauncherLogPath(RunnerPaths paths, string runId) =>
        Path.Combine(paths.StateRoot, runId, "launcher.log");

    private static WindowsProcessLaunchResult SucceededLaunch(string api) =>
        new(
            true,
            Environment.ProcessId,
            0,
            string.Empty,
            api,
            WindowsWorkerLaunchStrategySelector.BaseCreationFlags);

    private static string CreateFakeProviderLauncher(string root)
    {
        var assemblyPath = typeof(FakeProviderMarker).Assembly.Location;
        var path = Path.Combine(root, "fake-provider.cmd");
        File.WriteAllText(path, $"@echo off\r\ndotnet \"{assemblyPath}\" %*\r\n");
        return path;
    }

    private static async Task<(int ExitCode, string StandardOutput, string StandardError)> RunHelperAsync(
        string helperPath,
        string runnerPath,
        string repository,
        string inputPath,
        string configPath,
        string stateRoot,
        IReadOnlyDictionary<string, string> extraEnvironment)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = helperPath,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        startInfo.ArgumentList.Add("--runner");
        startInfo.ArgumentList.Add(runnerPath);
        startInfo.ArgumentList.Add("--repository");
        startInfo.ArgumentList.Add(repository);
        startInfo.ArgumentList.Add("--input");
        startInfo.ArgumentList.Add(inputPath);
        startInfo.Environment["PURPOSE_REVIEW_RUNNER_CONFIG_PATH"] = configPath;
        startInfo.Environment["PURPOSE_REVIEW_RUNNER_STATE_ROOT"] = stateRoot;
        foreach (var pair in extraEnvironment)
        {
            startInfo.Environment[pair.Key] = pair.Value;
        }

        using var process = Process.Start(startInfo) ?? throw new AssertFailedException("Restrictive job helper did not start.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return (process.ExitCode, await stdout, await stderr);
    }

    private static async Task<JsonDocument> PollStatusAsync(
        string runnerPath,
        string runId,
        string configPath,
        string stateRoot,
        TimeSpan timeout,
        string? diagnosticFile = null)
    {
        var deadline = DateTime.UtcNow + timeout;
        string? lastOutput = null;
        while (DateTime.UtcNow < deadline)
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = runnerPath,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            startInfo.ArgumentList.Add("status");
            startInfo.ArgumentList.Add("--run");
            startInfo.ArgumentList.Add(runId);
            startInfo.Environment["PURPOSE_REVIEW_RUNNER_CONFIG_PATH"] = configPath;
            startInfo.Environment["PURPOSE_REVIEW_RUNNER_STATE_ROOT"] = stateRoot;
            using var process = Process.Start(startInfo) ?? throw new AssertFailedException("status process did not start.");
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();
            var stdout = await stdoutTask;
            await stderrTask;
            lastOutput = stdout;
            if (process.ExitCode == 0)
            {
                var document = JsonDocument.Parse(stdout.Trim());
                if (document.RootElement.GetProperty("jobStatus").GetString() != JobStatuses.Running)
                {
                    return document;
                }

                document.Dispose();
            }

            await Task.Delay(500);
        }

        var diagnostics = diagnosticFile is not null && File.Exists(diagnosticFile)
            ? Environment.NewLine + "Fake provider stderr:" + Environment.NewLine + File.ReadAllText(diagnosticFile)
            : string.Empty;
        throw new AssertFailedException("Timed out waiting for durable job completion. Last output:" + Environment.NewLine + lastOutput + diagnostics);
    }
}

internal sealed class FakeWindowsJobInspector : IWindowsJobInspector
{
    public FakeWindowsJobInspector(WindowsJobSnapshot snapshot) => Snapshot = snapshot;

    public WindowsJobSnapshot Snapshot { get; }

    public WindowsJobSnapshot InspectCurrentProcess() => Snapshot;
}

internal sealed class FakeWindowsProcessLauncher : IWindowsProcessLauncher
{
    public WindowsProcessLaunchResult DetachedResult { get; set; } =
        new(false, null, 1, "CreateProcess should not be used.", "CreateProcess", 0);

    public WindowsProcessLaunchResult ExternalResult { get; set; } =
        new(false, null, 1, "Win32_Process.Create was not configured.", "Win32_Process.Create", 0);

    public int DetachedCallCount { get; private set; }

    public int ExternalCallCount { get; private set; }

    public WindowsProcessLaunchRequest? LastExternalRequest { get; private set; }

    public WindowsProcessLaunchResult CreateDetachedProcess(WindowsProcessLaunchRequest request)
    {
        DetachedCallCount++;
        return DetachedResult;
    }

    public WindowsProcessLaunchResult CreateExternalProcess(WindowsProcessLaunchRequest request)
    {
        ExternalCallCount++;
        LastExternalRequest = request;
        return ExternalResult;
    }
}

internal sealed class TemporaryDirectory : IDisposable
{
    public TemporaryDirectory()
    {
        Root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-launch-tests", Guid.NewGuid().ToString("N"));
        Repository = Path.Combine(Root, "repo");
        Directory.CreateDirectory(Repository);
        Paths = new(Path.Combine(Root, "config", "config.json"), Path.Combine(Root, "state", "runs"));
        Directory.CreateDirectory(Path.GetDirectoryName(Paths.ConfigPath)!);
    }

    public string Root { get; }
    public string Repository { get; }
    public RunnerPaths Paths { get; }

    public void WriteConfig() =>
        File.WriteAllText(
            Paths.ConfigPath,
            JsonSerializer.Serialize(new RunnerConfig(1, "copilot", "copilot", "test-model", "high", null), JsonDefaults.Options));

    public void Dispose()
    {
        if (Directory.Exists(Root))
        {
            Directory.Delete(Root, true);
        }
    }
}
