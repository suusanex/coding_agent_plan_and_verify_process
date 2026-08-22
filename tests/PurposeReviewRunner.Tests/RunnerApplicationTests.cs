using System.Text.Json;
using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PurposeReviewRunner;
using PurposeReviewRunnerFakeProvider;

namespace PurposeReviewRunnerTests;

[TestClass]
public sealed class RunnerApplicationTests
{
    [TestMethod]
    public async Task StartAndContinueUseSameCodexSessionAndDoNotReplayContext()
    {
        using var fixture = new RunnerFixture("codex");
        var relativeContext = Path.Combine("docs", "goal.md");
        var absoluteContext = Path.Combine(fixture.ExternalRoot, "decision.md");
        fixture.WriteRepositoryFile(relativeContext, "GOAL-CONTEXT-ALPHA");
        File.WriteAllText(absoluteContext, "ACCEPTED-DECISION-BETA");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));

        var start = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, [relativeContext, absoluteContext]),
            CancellationToken.None);
        var continuation = await fixture.Application.ExecuteAsync(
            new ContinueCommand(start.Output.RunId!),
            CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, start.Output.Status);
        Assert.AreEqual(ReviewStatuses.Complete, continuation.Output.Status);
        Assert.AreEqual(2, continuation.Output.Round);
        Assert.AreEqual(2, fixture.Process.Requests.Count);
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "GOAL-CONTEXT-ALPHA");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "ACCEPTED-DECISION-BETA");
        Assert.IsFalse(fixture.Process.Requests[1].StandardInput!.Contains("GOAL-CONTEXT-ALPHA", StringComparison.Ordinal));
        Assert.IsFalse(fixture.Process.Requests[1].StandardInput!.Contains("ACCEPTED-DECISION-BETA", StringComparison.Ordinal));
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), fixture.Process.CodexSessionId);
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "sandbox_mode=\"read-only\"");
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "test-model");
    }

    [TestMethod]
    public async Task ContinueUsesConfigurationSnapshotAfterUserConfigChanges()
    {
        using var fixture = new RunnerFixture("codex");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

        fixture.WriteConfig("grok", "changed-grok", "changed-model");
        await fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(FakeExecutableResolver.Expected("codex"), fixture.Process.Requests[1].Executable);
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "resume");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[1].Arguments.ToArray(), "changed-model");
    }

    [TestMethod]
    public async Task RoundThreeFindingsBecomeTerminalHumanDecisionRequired()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var first = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);
        var third = await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.HumanDecisionRequired, third.Output.Status);
        Assert.IsTrue(third.Output.Terminal);
        Assert.AreEqual(3, third.Output.Round);
        Assert.AreEqual(1, third.Output.Findings.Count);
        await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None));
    }

    [TestMethod]
    public async Task CopilotUsesGeneratedSessionAndReadOnlyToolContract()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var first = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

        var startArguments = fixture.Process.Requests[0].Arguments.ToArray();
        var resumeArguments = fixture.Process.Requests[1].Arguments.ToArray();
        Assert.IsTrue(startArguments.Any(value => value.StartsWith("--session-id=", StringComparison.Ordinal)));
        Assert.IsTrue(resumeArguments.Any(value => value.StartsWith("--resume=", StringComparison.Ordinal)));
        CollectionAssert.Contains(startArguments, "--available-tools=view,grep");
        CollectionAssert.Contains(startArguments, "--deny-tool=write");
        CollectionAssert.Contains(startArguments, "--deny-tool=shell");
        CollectionAssert.Contains(startArguments, "--disable-builtin-mcps");
        CollectionAssert.Contains(startArguments, "--attachment");
    }

    [TestMethod]
    public async Task GrokUsesReadOnlySessionAndResumeContract()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var first = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

        var startArguments = fixture.Process.Requests[0].Arguments.ToArray();
        var resumeArguments = fixture.Process.Requests[1].Arguments.ToArray();
        CollectionAssert.Contains(startArguments, "--session-id");
        CollectionAssert.Contains(resumeArguments, "--resume");
        CollectionAssert.Contains(startArguments, "--permission-mode");
        CollectionAssert.Contains(startArguments, "read-only");
        CollectionAssert.Contains(startArguments, "--no-memory");
        CollectionAssert.Contains(startArguments, "--no-subagents");
        CollectionAssert.Contains(startArguments, "--disable-web-search");
    }

    [TestMethod]
    public async Task ProviderFailureDoesNotCreateValidState()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "auth failed", false);

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None));

        Assert.AreEqual("PROVIDER_FAILED", exception.Code);
        Assert.IsEmpty(Directory.GetFiles(fixture.Paths.StateRoot, "state.json", SearchOption.AllDirectories));
    }

    [TestMethod]
    public async Task MalformedReviewFailsClosed()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue("not a review block");

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None));

        Assert.AreEqual("REVIEW_PARSE_FAILED", exception.Code);
        Assert.AreEqual(ExitCodes.ContractError, exception.ExitCode);
    }

    [TestMethod]
    public async Task MalformedContinuationMakesRunTerminalBeforeProviderCanBeRetried()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue("not a review block");
        var start = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, ["goal.md"]),
            CancellationToken.None);

        var malformed = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None));
        var state = new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!);
        var retry = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("REVIEW_PARSE_FAILED", malformed.Code);
        Assert.AreEqual(2, state.Round);
        Assert.AreEqual(ReviewStatuses.Error, state.Status);
        Assert.AreEqual("RUN_TERMINAL", retry.Code);
        Assert.HasCount(2, fixture.Process.Requests);
    }

    [TestMethod]
    public void NullFindingFailsAsReviewerProtocolError()
    {
        const string response = """
            BEGIN_PURPOSE_REVIEW
            {"status":"FINDINGS","findings":[null],"message":null}
            END_PURPOSE_REVIEW
            """;

        var exception = Assert.ThrowsExactly<RunnerException>(() => ReviewProtocol.Parse(response));

        Assert.AreEqual("REVIEW_PARSE_FAILED", exception.Code);
        Assert.AreEqual(ExitCodes.ContractError, exception.ExitCode);
    }

    [TestMethod]
    [DoNotParallelize]
    public async Task ProviderStderrIsTracedButExcludedFromPublicError()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        const string privateDiagnostic = "PRIVATE-PROVIDER-DIAGNOSTIC";
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, privateDiagnostic, false);
        using var traceText = new StringWriter();
        using var listener = new TextWriterTraceListener(traceText);
        Trace.Listeners.Add(listener);
        try
        {
            var exception = await Assert.ThrowsExactlyAsync<RunnerException>(
                () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None));
            listener.Flush();
            var publicOutput = JsonSerializer.Serialize(
                RunnerOutput.FromError(exception.Code, exception.Message),
                JsonDefaults.Options);

            StringAssert.Contains(traceText.ToString(), privateDiagnostic);
            Assert.IsFalse(exception.Message.Contains(privateDiagnostic, StringComparison.Ordinal));
            Assert.IsFalse(publicOutput.Contains(privateDiagnostic, StringComparison.Ordinal));
            StringAssert.Contains(publicOutput, "Provider process exited with code 7.");
        }
        finally
        {
            Trace.Listeners.Remove(listener);
        }
    }

    [TestMethod]
    public void RunLockRejectsConcurrentMutation()
    {
        using var fixture = new RunnerFixture("codex");
        var store = new StateStore(fixture.Paths.StateRoot);
        var runId = Guid.NewGuid().ToString("D");
        using var first = store.AcquireLock(runId);

        var exception = Assert.ThrowsExactly<RunnerException>(() => store.AcquireLock(runId));

        Assert.AreEqual("RUN_BUSY", exception.Code);
    }

    [TestMethod]
    public void ConfigRejectsUnknownProtocolOptions()
    {
        using var fixture = new RunnerFixture("codex");
        File.WriteAllText(fixture.Paths.ConfigPath, """
            {"schemaVersion":1,"provider":"codex","executable":"codex","model":"m","reasoningEffort":"high","profile":null,"maxRounds":4}
            """);

        var exception = Assert.ThrowsExactly<RunnerException>(() => ConfigLoader.Load(fixture.Paths.ConfigPath));

        Assert.AreEqual("CONFIG_INVALID", exception.Code);
    }

    [TestMethod]
    public void CliRequiresExactCommandsAndRepeatableContext()
    {
        var parsed = (StartCommand)CliParser.Parse(["start", "--repository", ".", "--context", "a.md", "--context", "b.md"]);
        Assert.HasCount(2, parsed.ContextPaths);
        Assert.IsInstanceOfType<ContinueCommand>(CliParser.Parse(["continue", "--run", Guid.NewGuid().ToString("D")]));
        Assert.IsInstanceOfType<VersionCommand>(CliParser.Parse(["version"]));
        Assert.ThrowsExactly<RunnerException>(() => CliParser.Parse(["start", "--repository", "."]));
    }

    [TestMethod]
    public async Task VersionProcessWritesOneJsonObjectToStdout()
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.Combine(
                Path.GetDirectoryName(typeof(RunnerApplication).Assembly.Location)!,
                OperatingSystem.IsWindows() ? "purpose-review-runner.exe" : "purpose-review-runner"),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        startInfo.ArgumentList.Add("version");
        using var process = Process.Start(startInfo) ?? throw new AssertFailedException("Runner process did not start.");
        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        Assert.AreEqual(0, process.ExitCode, stderr);
        var lines = stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
        Assert.HasCount(1, lines);
        using var document = JsonDocument.Parse(lines[0]);
        Assert.AreEqual(Protocol.Version, document.RootElement.GetProperty("protocolVersion").GetInt32());
        Assert.AreEqual(Protocol.RunnerVersion, document.RootElement.GetProperty("runnerVersion").GetString());
    }

    [TestMethod]
    public async Task InvalidArgumentsProcessWritesErrorJsonAndExitTwo()
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = Path.Combine(
                Path.GetDirectoryName(typeof(RunnerApplication).Assembly.Location)!,
                OperatingSystem.IsWindows() ? "purpose-review-runner.exe" : "purpose-review-runner"),
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        startInfo.ArgumentList.Add("unknown");
        using var process = Process.Start(startInfo) ?? throw new AssertFailedException("Runner process did not start.");
        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        Assert.AreEqual(ExitCodes.ContractError, process.ExitCode);
        StringAssert.Contains(stderr, nameof(RunnerException));
        var lines = stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries);
        Assert.HasCount(1, lines);
        using var document = JsonDocument.Parse(lines[0]);
        Assert.AreEqual(ReviewStatuses.Error, document.RootElement.GetProperty("status").GetString());
        Assert.AreEqual("INVALID_ARGUMENTS", document.RootElement.GetProperty("error").GetProperty("code").GetString());
    }

    [TestMethod]
    public async Task ReleaseTagValidationRequiresExactRunnerVersion()
    {
        var runnerPath = Path.Combine(
            Path.GetDirectoryName(typeof(RunnerApplication).Assembly.Location)!,
            OperatingSystem.IsWindows() ? "purpose-review-runner.exe" : "purpose-review-runner");
        var scriptPath = Path.Combine(AppContext.BaseDirectory, "assert-release-tag.ps1");

        var matching = await RunProcessAsync(
            "pwsh",
            ["-NoProfile", "-File", scriptPath, "-RunnerPath", runnerPath, "-Tag", $"purpose-review-runner-v{Protocol.RunnerVersion}"]);
        var mismatching = await RunProcessAsync(
            "pwsh",
            ["-NoProfile", "-File", scriptPath, "-RunnerPath", runnerPath, "-Tag", "purpose-review-runner-v9.9.9"]);

        Assert.AreEqual(0, matching.ExitCode, matching.StandardError);
        Assert.AreNotEqual(0, mismatching.ExitCode);
        StringAssert.Contains(mismatching.StandardError, "does not match Runner version");
    }

    [TestMethod]
    public async Task TimeoutFailsWithRuntimeErrorAndDoesNotSaveState()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.ForcedResult = new ProcessResult(-1, string.Empty, string.Empty, true);

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None));

        Assert.AreEqual("PROVIDER_TIMEOUT", exception.Code);
        Assert.AreEqual(ExitCodes.RuntimeError, exception.ExitCode);
        Assert.IsEmpty(Directory.GetFiles(fixture.Paths.StateRoot, "state.json", SearchOption.AllDirectories));
    }

    [TestMethod]
    public async Task ProcessTimeoutIncludesBlockedStandardInputWrite()
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-stdin-timeout-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var executable = CreateFakeProviderLauncher(root);
        var runner = new SystemProcessRunner(TimeSpan.FromMilliseconds(500));
        var request = new ProcessRequest(
            executable,
            ["--hang-without-reading-stdin"],
            root,
            new string('x', 8 * 1024 * 1024));
        var stopwatch = Stopwatch.StartNew();

        try
        {
            var result = await runner.RunAsync(request, CancellationToken.None);

            stopwatch.Stop();
            Assert.IsTrue(result.TimedOut);
            Assert.AreEqual(-1, result.ExitCode);
            Assert.IsLessThan(TimeSpan.FromSeconds(5), stopwatch.Elapsed);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, true);
            }
        }
    }

    [TestMethod]
    public async Task TerminalRunCannotBeContinued()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var result = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, ["goal.md"]),
            CancellationToken.None);

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new ContinueCommand(result.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("RUN_TERMINAL", exception.Code);
        Assert.HasCount(1, fixture.Process.Requests);
    }

    [TestMethod]
    public async Task StateSaveIsAtomicAndContainsOnlyRunControlData()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "UNIQUE-CONTEXT-BODY");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var result = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, ["goal.md"]),
            CancellationToken.None);

        var runDirectory = Path.Combine(fixture.Paths.StateRoot, result.Output.RunId!);
        Assert.IsEmpty(Directory.GetFiles(runDirectory, "state.json.tmp-*"));
        var stateText = File.ReadAllText(Path.Combine(runDirectory, "state.json"));
        Assert.IsFalse(stateText.Contains("UNIQUE-CONTEXT-BODY", StringComparison.Ordinal));
        Assert.IsFalse(stateText.Contains("Purpose gap", StringComparison.Ordinal));
        var state = JsonSerializer.Deserialize<RunState>(stateText, JsonDefaults.Options);
        Assert.IsNotNull(state);
        Assert.AreEqual(1, state.Round);
        Assert.AreEqual(FakeExecutableResolver.Expected("grok"), state.Provider.Executable);
    }

    [TestMethod]
    public async Task MissingAndEmptyContextsFailBeforeProviderExecution()
    {
        using var fixture = new RunnerFixture("codex");
        fixture.WriteRepositoryFile("empty.md", "   ");

        var missing = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["missing.md"]), CancellationToken.None));
        var empty = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["empty.md"]), CancellationToken.None));

        Assert.AreEqual("CONTEXT_NOT_FOUND", missing.Code);
        Assert.AreEqual("CONTEXT_EMPTY", empty.Code);
        Assert.IsEmpty(fixture.Process.Requests);
    }

    [TestMethod]
    [DataRow("codex")]
    [DataRow("grok")]
    [DataRow("copilot")]
    public async Task FakeProviderExecutableCompletesNewAndResumeProcessBoundary(string provider)
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-process-tests", Guid.NewGuid().ToString("N"));
        var repository = Path.Combine(root, "repository");
        var configPath = Path.Combine(root, "config", "config.json");
        var stateRoot = Path.Combine(root, "state", "runs");
        Directory.CreateDirectory(repository);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        File.WriteAllText(Path.Combine(repository, "purpose.md"), "FAKE-INTEGRATION-CONTEXT");
        var executable = CreateFakeProviderLauncher(root);
        File.WriteAllText(
            configPath,
            JsonSerializer.Serialize(new RunnerConfig(1, provider, executable, "test-model", "high", null), JsonDefaults.Options));
        var application = new RunnerApplication(
            new RunnerPaths(configPath, stateRoot),
            new ExecutableResolver(),
            new SystemProcessRunner(TimeSpan.FromSeconds(15)));

        try
        {
            var first = await application.ExecuteAsync(new StartCommand(repository, ["purpose.md"]), CancellationToken.None);
            var second = await application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

            Assert.AreEqual(ReviewStatuses.Findings, first.Output.Status);
            Assert.AreEqual(ReviewStatuses.Complete, second.Output.Status);
            Assert.AreEqual(2, second.Output.Round);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, true);
            }
        }
    }

    private static string CreateFakeProviderLauncher(string root)
    {
        var assemblyPath = typeof(FakeProviderMarker).Assembly.Location;
        if (OperatingSystem.IsWindows())
        {
            var path = Path.Combine(root, "fake-provider.cmd");
            File.WriteAllText(path, $"@echo off\r\ndotnet \"{assemblyPath}\" %*\r\n");
            return path;
        }

        var scriptPath = Path.Combine(root, "fake-provider");
        var escapedAssemblyPath = assemblyPath.Replace("'", "'\"'\"'", StringComparison.Ordinal);
        File.WriteAllText(scriptPath, $"#!/bin/sh\nexec dotnet '{escapedAssemblyPath}' \"$@\"\n");
        File.SetUnixFileMode(
            scriptPath,
            UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        return scriptPath;
    }

    private static async Task<(int ExitCode, string StandardOutput, string StandardError)> RunProcessAsync(
        string executable,
        IReadOnlyList<string> arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        using var process = Process.Start(startInfo) ?? throw new AssertFailedException($"Process did not start: {executable}");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return (process.ExitCode, await stdout, await stderr);
    }

    private static ReviewFinding Finding(string id) => new(id, "HIGH", "Purpose gap", "summary", "evidence", "required change");

    private static string Review(string status, params ReviewFinding[] findings)
    {
        var message = status is "BLOCKED" or "HUMAN_DECISION_REQUIRED" ? "decision required" : null;
        var body = JsonSerializer.Serialize(new ReviewerResponse(status, findings, message), JsonDefaults.Options);
        return $"BEGIN_PURPOSE_REVIEW\n{body}\nEND_PURPOSE_REVIEW";
    }
}

internal sealed class RunnerFixture : IDisposable
{
    public RunnerFixture(string provider)
    {
        Root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-tests", Guid.NewGuid().ToString("N"));
        Repository = Path.Combine(Root, "repo");
        ExternalRoot = Path.Combine(Root, "external");
        Directory.CreateDirectory(Repository);
        Directory.CreateDirectory(ExternalRoot);
        Paths = new(Path.Combine(Root, "config", "config.json"), Path.Combine(Root, "state", "runs"));
        Directory.CreateDirectory(Path.GetDirectoryName(Paths.ConfigPath)!);
        WriteConfig(provider, provider, "test-model");
        Process = new ScriptedProcessRunner(provider);
        Application = new(Paths, new FakeExecutableResolver(), Process);
    }

    public string Root { get; }
    public string Repository { get; }
    public string ExternalRoot { get; }
    public RunnerPaths Paths { get; }
    public ScriptedProcessRunner Process { get; }
    public RunnerApplication Application { get; }

    public void WriteRepositoryFile(string relativePath, string content)
    {
        var path = Path.Combine(Repository, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
    }

    public void WriteConfig(string provider, string executable, string model)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Paths.ConfigPath)!);
        File.WriteAllText(Paths.ConfigPath, JsonSerializer.Serialize(new RunnerConfig(1, provider, executable, model, "high", null), JsonDefaults.Options));
    }

    public void Dispose()
    {
        if (Directory.Exists(Root))
        {
            Directory.Delete(Root, true);
        }
    }
}

internal sealed class FakeExecutableResolver : IExecutableResolver
{
    public static string Expected(string executable) => Path.Combine(Path.GetTempPath(), "resolved-" + executable);

    public string Resolve(string executable) => Expected(executable);
}

internal sealed class ScriptedProcessRunner : IProcessRunner
{
    private readonly string provider;
    private string? copilotSession;

    public ScriptedProcessRunner(string provider) => this.provider = provider;

    public Queue<string> Reviews { get; } = new();
    public List<ProcessRequest> Requests { get; } = [];
    public ProcessResult? ForcedResult { get; set; }
    public string CodexSessionId { get; } = "11111111-1111-4111-8111-111111111111";

    public Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        if (ForcedResult is not null)
        {
            return Task.FromResult(ForcedResult);
        }
        var review = Reviews.Dequeue();
        return Task.FromResult(provider switch
        {
            "codex" => CodexResult(request, review),
            "copilot" => CopilotResult(request, review),
            _ => new ProcessResult(0, review, string.Empty, false)
        });
    }

    private ProcessResult CodexResult(ProcessRequest request, string review)
    {
        var arguments = request.Arguments.ToArray();
        var outputIndex = Array.IndexOf(arguments, "-o");
        File.WriteAllText(arguments[outputIndex + 1], review);
        return new(0, JsonSerializer.Serialize(new { type = "thread.started", thread_id = CodexSessionId }), string.Empty, false);
    }

    private ProcessResult CopilotResult(ProcessRequest request, string review)
    {
        var sessionArgument = request.Arguments.Single(argument => argument.StartsWith("--session-id=", StringComparison.Ordinal) || argument.StartsWith("--resume=", StringComparison.Ordinal));
        var requested = sessionArgument[(sessionArgument.IndexOf('=') + 1)..];
        copilotSession ??= requested;
        var output = string.Join("\n",
            JsonSerializer.Serialize(new { type = "assistant.message", data = new { content = review, model = "test-model" } }),
            JsonSerializer.Serialize(new { type = "result", sessionId = copilotSession }));
        return new(0, output, string.Empty, false);
    }
}
