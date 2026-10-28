using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PurposeReviewRunner;
using PurposeReviewRunnerFakeProvider;

namespace PurposeReviewRunnerTests;

[TestClass]
public sealed class RunnerApplicationTests
{
    [TestMethod]
    public async Task StartAndContinueUseSameCopilotSessionAndReplayOnlyVersionedInput()
    {
        using var fixture = new RunnerFixture("copilot");
        var relativeContext = Path.Combine("docs", "goal.md");
        var absoluteContext = Path.Combine(fixture.ExternalRoot, "decision.md");
        fixture.WriteRepositoryFile(relativeContext, "GOAL-CONTEXT-ALPHA");
        File.WriteAllText(absoluteContext, "ACCEPTED-DECISION-BETA");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));

        var start = await fixture.Application.ExecuteAsync(
            fixture.StartCommand("GOAL-CONTEXT-ALPHA ACCEPTED-DECISION-BETA"),
            CancellationToken.None);
        var continuation = await fixture.Application.ExecuteAsync(
            fixture.ContinueCommand(start.Output.RunId!),
            CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, start.Output.Status);
        Assert.AreEqual(JobStatuses.Succeeded, start.Output.JobStatus);
        Assert.AreEqual(ReviewStatuses.Complete, continuation.Output.Status);
        Assert.AreEqual(JobStatuses.Succeeded, continuation.Output.JobStatus);
        Assert.AreEqual(2, continuation.Output.Round);
        Assert.AreEqual(2, fixture.Process.Requests.Count);
        var inputStore = new ReviewInputStore(fixture.Paths.StateRoot);
        Assert.AreEqual(inputStore.Load(start.Output.RunId!, 1).Hash, start.Output.InputHash);
        Assert.AreEqual(inputStore.Load(start.Output.RunId!, 2).Hash, continuation.Output.InputHash);
        Assert.AreEqual("purpose-v1", start.Output.InputBinding!.PurposeVersion);
        Assert.AreEqual("design-v1", start.Output.InputBinding.ApprovedDesignVersion);
        Assert.AreEqual("proposal-v1", start.Output.InputBinding.ProposalVersion);
        Assert.AreEqual("purpose-v1", continuation.Output.InputBinding!.PurposeVersion);
        Assert.AreEqual("proposal-v1", continuation.Output.InputBinding.ProposalVersion);
        CollectionAssert.Contains(continuation.Output.NonGuarantees!.ToArray(), "runtime-purpose-achievement-not-verified");
        CollectionAssert.Contains(continuation.Output.NonGuarantees!.ToArray(), "release-readiness-not-assessed");
        CollectionAssert.Contains(continuation.Output.NonGuarantees!.ToArray(), "task-completion-not-certified");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "GOAL-CONTEXT-ALPHA");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "ACCEPTED-DECISION-BETA");
        StringAssert.Contains(fixture.Process.Requests[1].StandardInput!, "GOAL-CONTEXT-ALPHA");
        StringAssert.Contains(fixture.Process.Requests[1].StandardInput!, "ACCEPTED-DECISION-BETA");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "BEGIN_PURPOSE_REVIEW");
        StringAssert.Contains(fixture.Process.Requests[1].StandardInput!, "BEGIN_PURPOSE_REVIEW");
        var initialSession = fixture.Process.Requests[0].Arguments.Single(argument => argument.StartsWith("--session-id=", StringComparison.Ordinal));
        var resumedSession = fixture.Process.Requests[1].Arguments.Single(argument => argument.StartsWith("--resume=", StringComparison.Ordinal));
        Assert.AreEqual(initialSession["--session-id=".Length..], resumedSession["--resume=".Length..]);
        CollectionAssert.Contains(fixture.Process.Requests[0].Arguments.ToArray(), "--available-tools=report_intent");
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "--available-tools=report_intent");
        CollectionAssert.Contains(fixture.Process.Requests[0].Arguments.ToArray(), "--disable-builtin-mcps");
        CollectionAssert.Contains(fixture.Process.Requests[0].Arguments.ToArray(), "--disable-mcp-server=test-server");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[0].Arguments.ToArray(), "--allow-tool=shell");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[0].Arguments.ToArray(), "--available-tools=");
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "test-model");

        var transcriptDirectory = TranscriptDirectory(fixture, start.Output.RunId!);
        Assert.AreEqual(fixture.Process.Requests[0].StandardInput, File.ReadAllText(Path.Combine(transcriptDirectory, "round-01-prompt.md")));
        Assert.AreEqual(fixture.Process.Requests[1].StandardInput, File.ReadAllText(Path.Combine(transcriptDirectory, "round-02-prompt.md")));
        Assert.AreEqual(fixture.Process.ReviewTexts[0], File.ReadAllText(Path.Combine(transcriptDirectory, "round-01-response.md")));
        Assert.AreEqual(fixture.Process.ReviewTexts[1], File.ReadAllText(Path.Combine(transcriptDirectory, "round-02-response.md")));
    }

    [TestMethod]
    public void StartAndContinuePromptsReviewVersionedPurposeAndApprovedDesignOnly()
    {
        var input = RunnerFixture.CreateInput();
        var prompts = new[]
        {
            PromptBuilder.BuildStart(input),
            PromptBuilder.BuildContinue(input, 2)
        };

        foreach (var prompt in prompts)
        {
            StringAssert.Contains(prompt, "purpose.authority");
            StringAssert.Contains(prompt, "approvedDesign");
            StringAssert.Contains(prompt, "実装適合");
            StringAssert.Contains(prompt, "BEGIN_PURPOSE_REVIEW");
            StringAssert.Contains(prompt, "独立して確認できるfindingがあれば保持できます");
            StringAssert.Contains(prompt, "subagentや他のagentへ調査を委任せず");
            StringAssert.Contains(prompt, "`COMPLETE` はfindingsを空にしてください");
            Assert.IsFalse(prompt.Contains("repository path", StringComparison.OrdinalIgnoreCase));
        }
    }

    [TestMethod]
    public async Task MalformedReviewerResponseIsSavedBeforeProtocolParse()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        const string malformed = "malformed response with {not-json}";
        fixture.Process.Reviews.Enqueue(malformed);

        var result = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        Assert.AreEqual("REVIEW_PARSE_FAILED", result.Output.Error?.Code);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
        var runDirectory = Path.Combine(fixture.Paths.StateRoot, result.Output.RunId!);
        Assert.AreEqual(malformed, File.ReadAllText(Path.Combine(runDirectory, "transcript", "round-01-response.md")));
    }

    [TestMethod]
    public async Task ContinueUsesConfigurationSnapshotAfterUserConfigChanges()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        fixture.WriteConfig("copilot", "changed-copilot", "changed-model");
        await fixture.Application.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(FakeExecutableResolver.Expected("copilot"), fixture.Process.Requests[1].Executable);
        Assert.IsTrue(fixture.Process.Requests[1].Arguments.Any(argument => argument.StartsWith("--resume=", StringComparison.Ordinal)));
        CollectionAssert.DoesNotContain(fixture.Process.Requests[1].Arguments.ToArray(), "changed-model");
    }

    [TestMethod]
    [DataRow(null)]
    [DataRow("Compared base abc and HEAD def; prior uncommitted content is unavailable. PUR-002 was withdrawn.")]
    public async Task RoundThreeFindingsBecomeTerminalHumanDecisionRequired(string? reviewMessage)
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue("BEGIN_PURPOSE_REVIEW\n" + JsonSerializer.Serialize(
            new ReviewerResponse(ReviewStatuses.Findings, [Finding("PUR-001")], reviewMessage, []), JsonDefaults.Options) + "\nEND_PURPOSE_REVIEW");
        var first = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        await fixture.Application.ExecuteAsync(fixture.ContinueCommand(first.Output.RunId!), CancellationToken.None);
        var third = await fixture.Application.ExecuteAsync(fixture.ContinueCommand(first.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.HumanDecisionRequired, third.Output.Status);
        Assert.IsTrue(third.Output.Terminal);
        Assert.AreEqual(3, third.Output.Round);
        Assert.AreEqual(1, third.Output.Findings.Count);
        StringAssert.Contains(third.Output.Message!, "maximum of three durable submissions");
        if (reviewMessage is not null)
        {
            StringAssert.Contains(third.Output.Message!, reviewMessage);
        }
        var stored = await fixture.Application.ExecuteAsync(new StatusCommand(first.Output.RunId!), CancellationToken.None);
        Assert.AreEqual(third.Output.Message, stored.Output.Message);
        await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(fixture.ContinueCommand(first.Output.RunId!), CancellationToken.None));
    }

    [TestMethod]
    public async Task CodexStartAndContinueUseSameVersionBoundReadOnlySession()
    {
        using var fixture = new RunnerFixture("codex");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Findings, Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));

        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand("codex purpose"), CancellationToken.None);
        var continuation = await fixture.Application.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, start.Output.Status);
        Assert.AreEqual(JobStatuses.Succeeded, start.Output.JobStatus);
        Assert.AreEqual(ReviewStatuses.Complete, continuation.Output.Status);
        Assert.AreEqual(JobStatuses.Succeeded, continuation.Output.JobStatus);
        Assert.AreEqual(2, continuation.Output.Round);
        Assert.AreEqual(2, fixture.Process.Requests.Count);
        var runState = new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!);
        Assert.AreEqual(fixture.Process.CodexSessionId, runState.SessionHandle);
        Assert.AreEqual(runState.SessionHandle, new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!).SessionHandle);
        var inputStore = new ReviewInputStore(fixture.Paths.StateRoot);
        Assert.AreEqual(inputStore.Load(start.Output.RunId!, 1).Hash, start.Output.InputHash);
        Assert.AreEqual(inputStore.Load(start.Output.RunId!, 2).Hash, continuation.Output.InputHash);
        Assert.AreEqual("purpose-v1", start.Output.InputBinding!.PurposeVersion);
        Assert.AreEqual("design-v1", start.Output.InputBinding.ApprovedDesignVersion);
        Assert.AreEqual("proposal-v1", start.Output.InputBinding.ProposalVersion);
        Assert.AreEqual("purpose-v1", continuation.Output.InputBinding!.PurposeVersion);
        Assert.AreEqual("proposal-v1", continuation.Output.InputBinding.ProposalVersion);
        var initialRequest = fixture.Process.Requests[0];
        var resumedRequest = fixture.Process.Requests[1];
        CollectionAssert.AreEqual(new[] { "exec" }, initialRequest.Arguments.Take(1).ToArray());
        CollectionAssert.AreEqual(new[] { "exec", "resume", runState.SessionHandle }, resumedRequest.Arguments.Take(3).ToArray());
        CollectionAssert.Contains(initialRequest.Arguments.ToArray(), "--sandbox");
        CollectionAssert.Contains(initialRequest.Arguments.ToArray(), "read-only");
        CollectionAssert.Contains(initialRequest.Arguments.ToArray(), "approval_policy=\"never\"");
        CollectionAssert.Contains(resumedRequest.Arguments.ToArray(), "sandbox_mode=\"read-only\"");
        CollectionAssert.Contains(resumedRequest.Arguments.ToArray(), "approval_policy=\"never\"");
        var disabledKnownTools = new[]
        {
            "shell_tool", "browser_use", "browser_use_external", "browser_use_full_cdp_access", "standalone_web_search",
            "apps", "mcp_2026_07_28", "multi_agent", "multi_agent_v2", "code_mode", "code_mode_host",
            "image_generation", "view_image", "computer_use", "in_app_browser", "skill_search", "plugins", "hooks", "memories"
        };
        foreach (var request in fixture.Process.Requests)
        {
            Assert.AreNotEqual(fixture.Repository, request.WorkingDirectory);
            Assert.IsFalse(request.WorkingDirectory.StartsWith(fixture.Repository, StringComparison.OrdinalIgnoreCase));
            Assert.IsFalse(request.StandardInput!.Contains(fixture.Repository, StringComparison.OrdinalIgnoreCase));
            CollectionAssert.DoesNotContain(request.Arguments.ToArray(), "--ephemeral");
            foreach (var feature in disabledKnownTools)
            {
                CollectionAssert.Contains(request.Arguments.ToArray(), feature);
            }
        }
        Assert.AreEqual(ReviewStatuses.Complete, new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!).Status);
    }

    [TestMethod]
    public async Task ProviderFailureDoesNotCreateValidState()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "auth failed", false);

        var result = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        Assert.AreEqual("PROVIDER_FAILED", result.Output.Error?.Code);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
        Assert.AreEqual(ExitCodes.RuntimeError, result.ExitCode);
        Assert.IsEmpty(Directory.GetFiles(fixture.Paths.StateRoot, "state.json", SearchOption.AllDirectories));
        var runDirectory = Path.Combine(fixture.Paths.StateRoot, result.Output.RunId!);
        Assert.IsTrue(File.Exists(Path.Combine(runDirectory, "transcript", "round-01-prompt.md")));
        Assert.IsFalse(File.Exists(Path.Combine(runDirectory, "transcript", "round-01-response.md")));
        var status = await fixture.Application.ExecuteAsync(new StatusCommand(result.Output.RunId!), CancellationToken.None);
        Assert.AreEqual("PROVIDER_FAILED", status.Output.Error?.Code);
        Assert.AreEqual(1, fixture.Process.Requests.Count);
    }

    [TestMethod]
    public async Task MalformedReviewFailsClosed()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue("not a review block");

        var result = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        Assert.AreEqual("REVIEW_PARSE_FAILED", result.Output.Error?.Code);
        Assert.AreEqual(ExitCodes.ContractError, result.ExitCode);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
    }

    [TestMethod]
    public async Task MalformedContinuationMakesRunTerminalBeforeProviderCanBeRetried()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue("not a review block");
        var start = await fixture.Application.ExecuteAsync(
            fixture.StartCommand(),
            CancellationToken.None);

        var malformed = await fixture.Application.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None);
        var state = new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!);
        var retry = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("REVIEW_PARSE_FAILED", malformed.Output.Error?.Code);
        Assert.AreEqual(JobStatuses.Failed, malformed.Output.JobStatus);
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
    public async Task SystemLevelOutcomeWithoutImplementationStepsSurvivesPublicAndStoredResults()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "User-approved structure controls downstream generation.");
        const string outcome = "The user-approved structure remains authoritative for all downstream generation and cannot be overwritten by an LLM outline.";
        fixture.Process.Reviews.Enqueue("""
            BEGIN_PURPOSE_REVIEW
            {"status":"FINDINGS","findings":[{"id":"PUR-001","severity":"HIGH","title":"Authority is inverted across the pipeline","summary":"Generation overrides the structure approved by the user.","evidence":"purpose.body v1 and proposal.delta v1 conflict.","requiredOutcome":"The user-approved structure remains authoritative for all downstream generation and cannot be overwritten by an LLM outline."}],"message":"The conflict spans the design boundary; implementation design belongs to the parent.","informationRequests":[]}
            END_PURPOSE_REVIEW
            """);
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var stored = await fixture.Application.ExecuteAsync(new StatusCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, stored.Output.Status);
        Assert.AreEqual(outcome, stored.Output.Findings.Single().RequiredOutcome);
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(stored.Output, JsonDefaults.Options));
        Assert.AreEqual(4, document.RootElement.GetProperty("protocolVersion").GetInt32());
        var finding = document.RootElement.GetProperty("findings")[0];
        Assert.AreEqual(outcome, finding.GetProperty("requiredOutcome").GetString());
        Assert.IsFalse(finding.TryGetProperty("requiredChange", out _));
    }

    [TestMethod]
    [DataRow("missing")]
    [DataRow("null")]
    [DataRow("empty")]
    [DataRow("whitespace")]
    [DataRow("legacy")]
    [DataRow("mixed")]
    public void ReviewerProtocolRejectsMissingOutcomeAndLegacyChangeFields(string mutation)
    {
        var response = JsonSerializer.SerializeToNode(new ReviewerResponse(ReviewStatuses.Findings, [Finding("PUR-001")], null, []), JsonDefaults.Options)!;
        var finding = response["findings"]![0]!.AsObject();
        switch (mutation)
        {
            case "missing":
                finding.Remove("requiredOutcome");
                break;
            case "null":
                finding["requiredOutcome"] = null;
                break;
            case "empty":
                finding["requiredOutcome"] = "";
                break;
            case "whitespace":
                finding["requiredOutcome"] = "  ";
                break;
            case "legacy":
                finding.Remove("requiredOutcome");
                finding["requiredChange"] = "Add a check.";
                break;
            case "mixed":
                finding["requiredChange"] = "Add a check.";
                break;
        }
        var exception = Assert.ThrowsExactly<RunnerException>(() => ReviewProtocol.Parse(
            "BEGIN_PURPOSE_REVIEW\n" + response.ToJsonString(JsonDefaults.Options) + "\nEND_PURPOSE_REVIEW"));

        Assert.AreEqual("REVIEW_PARSE_FAILED", exception.Code);
    }

    [TestMethod]
    public async Task ContinueRejectsProtocolTwoStateWithoutStartingAnotherReview()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var store = new StateStore(fixture.Paths.StateRoot);
        store.Save(store.Load(start.Output.RunId!) with { ProtocolVersion = 2 });

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() => fixture.Application.ExecuteAsync(
            fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("STATE_INCOMPATIBLE", exception.Code);
        Assert.HasCount(1, fixture.Process.Requests);
    }

    [TestMethod]
    public async Task StatusRejectsProtocolTwoResultEvenWithoutFindings()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var store = new JobStore(fixture.Paths.StateRoot);
        var original = store.LoadResult(start.Output.RunId!);
        store.SaveResult(start.Output.RunId!, original with { Output = original.Output with { ProtocolVersion = 2 } });

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() => fixture.Application.ExecuteAsync(
            new StatusCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("STATE_INCOMPATIBLE", exception.Code);
        Assert.HasCount(1, fixture.Process.Requests);
        using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(store.GetRunDirectory(start.Output.RunId!), "result.json")));
        Assert.AreEqual(2, document.RootElement.GetProperty("output").GetProperty("protocolVersion").GetInt32());
    }

    [TestMethod]
    [DoNotParallelize]
    public async Task ProviderStderrIsTracedButExcludedFromPublicError()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        const string privateDiagnostic = "PRIVATE-PROVIDER-DIAGNOSTIC";
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, privateDiagnostic, false);
        using var traceText = new StringWriter();
        using var listener = new TextWriterTraceListener(traceText);
        Trace.Listeners.Add(listener);
        try
        {
            var result = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
            listener.Flush();
            var publicOutput = JsonSerializer.Serialize(result.Output, JsonDefaults.Options);

            StringAssert.Contains(traceText.ToString(), privateDiagnostic);
            Assert.AreEqual("PROVIDER_FAILED", result.Output.Error?.Code);
            Assert.IsFalse(result.Output.Error!.Message.Contains(privateDiagnostic, StringComparison.Ordinal));
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
        using var fixture = new RunnerFixture("copilot");
        var store = new StateStore(fixture.Paths.StateRoot);
        var runId = Guid.NewGuid().ToString("D");
        using var first = store.AcquireLock(runId);

        var exception = Assert.ThrowsExactly<RunnerException>(() => store.AcquireLock(runId));

        Assert.AreEqual("RUN_BUSY", exception.Code);
    }

    [TestMethod]
    public void ConfigRejectsUnknownProtocolOptions()
    {
        using var fixture = new RunnerFixture("copilot");
        File.WriteAllText(fixture.Paths.ConfigPath, """
            {"schemaVersion":1,"provider":"codex","executable":"codex","model":"m","reasoningEffort":"high","profile":null,"maxRounds":4}
            """);

        var exception = Assert.ThrowsExactly<RunnerException>(() => ConfigLoader.Load(fixture.Paths.ConfigPath));

        Assert.AreEqual("CONFIG_INVALID", exception.Code);
    }

    [TestMethod]
    public void CliRequiresExactCommandsAndSingleInputFile()
    {
        var parsed = (StartCommand)CliParser.Parse(["start", "--repository", ".", "--input", "review.json"]);
        Assert.AreEqual("review.json", parsed.InputPath);
        var runId = Guid.NewGuid().ToString("D");
        Assert.IsInstanceOfType<ContinueCommand>(CliParser.Parse(["continue", "--run", runId, "--input", "review.json"]));
        Assert.IsInstanceOfType<StatusCommand>(CliParser.Parse(["status", "--run", runId]));
        Assert.IsInstanceOfType<WorkCommand>(CliParser.Parse(["work", "--run", runId]));
        Assert.IsInstanceOfType<VersionCommand>(CliParser.Parse(["version"]));
        Assert.ThrowsExactly<RunnerException>(() => CliParser.Parse(["start", "--repository", "."]));
        Assert.ThrowsExactly<RunnerException>(() => CliParser.Parse(["start", "--repository", ".", "--context", "goal.md"]));
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
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.ForcedResult = new ProcessResult(-1, string.Empty, string.Empty, true);

        var result = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        Assert.AreEqual("PROVIDER_TIMEOUT", result.Output.Error?.Code);
        Assert.AreEqual(ExitCodes.RuntimeError, result.ExitCode);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
        Assert.IsEmpty(Directory.GetFiles(fixture.Paths.StateRoot, "state.json", SearchOption.AllDirectories));
    }

    [TestMethod]
    public async Task ProcessRunnerWritesUtf8WithoutBomToStandardInput()
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-stdin-utf8-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var dumpPath = Path.Combine(root, "stdin.bin");
        var executable = Path.Combine(
            Path.GetDirectoryName(typeof(FakeProviderMarker).Assembly.Location)!,
            OperatingSystem.IsWindows() ? "purpose-review-fake-provider.exe" : "purpose-review-fake-provider");
        var prompt = PromptBuilder.BuildStart(RunnerFixture.CreateInput());
        var runner = new SystemProcessRunner(TimeSpan.FromSeconds(15));

        try
        {
            var result = await runner.RunAsync(
                new ProcessRequest(executable, ["--dump-stdin-bytes", dumpPath], root, prompt),
                CancellationToken.None);

            Assert.AreEqual(0, result.ExitCode, result.StandardError);
            var actual = await File.ReadAllBytesAsync(dumpPath);
            CollectionAssert.AreEqual(new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(prompt), actual);
            // あ (U+3042) の UTF-8 は E3 81 82。CP932 なら 82 A0、UTF-8 BOM なら EF BB BF。
            Assert.IsFalse(actual.AsSpan().StartsWith(Encoding.UTF8.Preamble));
            Assert.IsTrue(actual.AsSpan().IndexOf(Encoding.UTF8.GetBytes("目的")) >= 0);
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
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var result = await fixture.Application.ExecuteAsync(
            fixture.StartCommand(),
            CancellationToken.None);

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(fixture.ContinueCommand(result.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("RUN_TERMINAL", exception.Code);
        Assert.HasCount(1, fixture.Process.Requests);
    }

    [TestMethod]
    public async Task StateSaveIsAtomicAndRetainsReviewerHistoryWithoutRawInput()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "UNIQUE-CONTEXT-BODY");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var result = await fixture.Application.ExecuteAsync(
            fixture.StartCommand(),
            CancellationToken.None);

        var runDirectory = Path.Combine(fixture.Paths.StateRoot, result.Output.RunId!);
        Assert.IsEmpty(Directory.GetFiles(runDirectory, "state.json.tmp-*"));
        var stateText = File.ReadAllText(Path.Combine(runDirectory, "state.json"));
        Assert.IsFalse(stateText.Contains("UNIQUE-CONTEXT-BODY", StringComparison.Ordinal));
        Assert.IsTrue(stateText.Contains("Purpose gap", StringComparison.Ordinal));
        var state = JsonSerializer.Deserialize<RunState>(stateText, JsonDefaults.Options);
        Assert.IsNotNull(state);
        Assert.AreEqual(1, state.Round);
        Assert.AreEqual(FakeExecutableResolver.Expected("copilot"), state.Provider.Executable);
    }

    [TestMethod]
    public async Task InvalidPurposeInputFailsBeforeProviderExecution()
    {
        using var fixture = new RunnerFixture("copilot");
        var missing = fixture.Input with { Purpose = null! };
        var empty = fixture.Input with { Purpose = fixture.Input.Purpose with { Body = " " } };

        var missingResult = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, fixture.WriteInput(missing)), CancellationToken.None));
        var emptyResult = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, fixture.WriteInput(empty)), CancellationToken.None));

        Assert.AreEqual("INPUT_INVALID", missingResult.Code);
        Assert.AreEqual("INPUT_INVALID", emptyResult.Code);
        Assert.IsEmpty(fixture.Process.Requests);
    }

    [TestMethod]
    public async Task ErrorRetriesAcrossRunsShareThreeDurableSubmissionBudget()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "provider failed", false);
        var currentInput = fixture.Input;
        string? previousRunId = null;
        for (var submission = 1; submission <= Protocol.MaximumRounds; submission++)
        {
            currentInput = currentInput with { PreviousRunId = previousRunId };
            var result = await fixture.Application.ExecuteAsync(
                new StartCommand(fixture.Repository, fixture.WriteInput(currentInput)),
                CancellationToken.None);
            Assert.AreEqual(ReviewStatuses.Error, result.Output.Status);
            Assert.AreEqual(submission, new TaskLineageStore(fixture.Paths.StateRoot).Load(fixture.Repository, currentInput.TaskKey)!.DurableSubmissions);
            previousRunId = result.Output.RunId;
        }

        currentInput = currentInput with { PreviousRunId = previousRunId };
        var rejected = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, fixture.WriteInput(currentInput)), CancellationToken.None));
        Assert.AreEqual("MAX_SUBMISSIONS_REACHED", rejected.Code);
        Assert.AreEqual(3, fixture.Process.Requests.Count);
    }

    [TestMethod]
    public async Task ReservedSubmissionWithoutJobFailsClosedAndKeepsConsumedBudget()
    {
        using var fixture = new RunnerFixture("copilot");
        var reservedRunId = Guid.NewGuid().ToString("D");
        var storedInput = ReviewInputStore.Snapshot(fixture.Input);
        var lineageStore = new TaskLineageStore(fixture.Paths.StateRoot);
        lineageStore.Save(new TaskLineage(
            fixture.Repository,
            fixture.Input.TaskKey,
            fixture.Input.ChangeId,
            reservedRunId,
            ReviewStatuses.Running,
            DurableSubmissions: 2,
            InputHash: storedInput.Hash));

        var retry = fixture.Input with { PreviousRunId = reservedRunId };
        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, fixture.WriteInput(retry)), CancellationToken.None));

        Assert.AreEqual("SUBMISSION_INCOMPLETE", exception.Code);
        Assert.AreEqual(2, lineageStore.Load(fixture.Repository, fixture.Input.TaskKey)!.DurableSubmissions);
        Assert.IsEmpty(fixture.Process.Requests);
    }

    [TestMethod]
    public async Task ContinueCountsTowardDurableSubmissionBudget()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var continuation = await fixture.Application.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None);
        var state = new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!);

        Assert.AreEqual(2, state.DurableSubmissions);
        Assert.AreEqual(ReviewStatuses.Findings, continuation.Output.Status);
        Assert.AreEqual(2, continuation.Output.Round);
    }

    [TestMethod]
    public async Task ErrorThenRetryFindingsThenContinueConsumesSharedBudgetAndRequiresHumanDecision()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "temporary provider failure", false);
        var failed = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        fixture.Process.ForcedResult = null;
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Findings, Finding("PUR-001")));
        var retryInput = fixture.Input with { PreviousRunId = failed.Output.RunId };
        var retried = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(retryInput)),
            CancellationToken.None);
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Findings, Finding("PUR-001")));
        var continued = await fixture.Application.ExecuteAsync(fixture.ContinueCommand(retried.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Error, failed.Output.Status);
        Assert.AreEqual(ReviewStatuses.Findings, retried.Output.Status);
        Assert.AreEqual(ReviewStatuses.HumanDecisionRequired, continued.Output.Status);
        Assert.AreEqual(3, new StateStore(fixture.Paths.StateRoot).Load(retried.Output.RunId!).DurableSubmissions);
    }

    [TestMethod]
    public async Task FindingsFromBeforeProviderErrorAreCarriedIntoNewRunHistory()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Findings, Finding("PUR-001")));
        var initial = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "temporary provider failure", false);
        var failed = await fixture.Application.ExecuteAsync(fixture.ContinueCommand(initial.Output.RunId!), CancellationToken.None);

        fixture.Process.ForcedResult = null;
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var retryInput = fixture.Input with { PreviousRunId = failed.Output.RunId };
        var retried = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(retryInput)),
            CancellationToken.None);
        var state = new StateStore(fixture.Paths.StateRoot).Load(retried.Output.RunId!);

        Assert.AreEqual(ReviewStatuses.Error, failed.Output.Status);
        Assert.AreEqual(ReviewStatuses.Complete, retried.Output.Status);
        Assert.AreEqual("PUR-001", state.ReviewHistory![0].Findings.Single().Id);
        StringAssert.Contains(fixture.Process.Requests[^1].StandardInput!, "priorReviewHistory");
        StringAssert.Contains(fixture.Process.Requests[^1].StandardInput!, "PUR-001");
    }

    [TestMethod]
    public async Task BlockedFindingsAndRequestsSurviveProviderErrorInLinkedRetry()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Blocked, Finding("PUR-001")));
        var blocked = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "temporary provider failure", false);
        var retryInput = fixture.Input with { PreviousRunId = blocked.Output.RunId };
        var failed = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(retryInput)),
            CancellationToken.None);

        fixture.Process.ForcedResult = null;
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Findings, Finding("PUR-002")));
        var finalInput = fixture.Input with { PreviousRunId = failed.Output.RunId };
        var final = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(finalInput)),
            CancellationToken.None);
        var state = new StateStore(fixture.Paths.StateRoot).Load(final.Output.RunId!);
        Assert.AreEqual(2, state.ReviewHistory!.Count, "Original BLOCKED review history must survive an ERROR-linked retry.");
        var initialHistory = state.ReviewHistory!.First(entry => entry.Status == ReviewStatuses.Blocked);

        Assert.AreEqual(ReviewStatuses.Blocked, blocked.Output.Status);
        Assert.AreEqual(ReviewStatuses.Error, failed.Output.Status);
        Assert.AreEqual(ReviewStatuses.HumanDecisionRequired, final.Output.Status);
        Assert.AreEqual(3, state.DurableSubmissions);
        Assert.AreEqual("PUR-001", initialHistory.Findings.Single().Id);
        Assert.AreEqual("INFO-001", initialHistory.InformationRequests.Single().Id);
        StringAssert.Contains(fixture.Process.Requests[^1].StandardInput!, "priorReviewHistory");
        StringAssert.Contains(fixture.Process.Requests[^1].StandardInput!, "PUR-001");
        StringAssert.Contains(fixture.Process.Requests[^1].StandardInput!, "INFO-001");
    }

    [TestMethod]
    public async Task SuccessfulResultRestoresHistoryWhenRunStateIsMissing()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Blocked, Finding("PUR-001")));
        var successful = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        File.Delete(Path.Combine(fixture.Paths.StateRoot, successful.Output.RunId!, "state.json"));

        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, "temporary provider failure", false);
        var retryInput = fixture.Input with { PreviousRunId = successful.Output.RunId };
        var failed = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(retryInput)),
            CancellationToken.None);
        var failedInput = new ReviewInputStore(fixture.Paths.StateRoot).Load(failed.Output.RunId!, 1).Input;
        var restoredHistory = failedInput.PriorReviewHistory!;

        Assert.AreEqual(ReviewStatuses.Blocked, successful.Output.Status);
        Assert.AreEqual(ReviewStatuses.Error, failed.Output.Status);
        Assert.HasCount(1, restoredHistory);
        Assert.AreEqual("PUR-001", restoredHistory[0].Findings.Single().Id);
        Assert.AreEqual("INFO-001", restoredHistory[0].InformationRequests.Single().Id);
    }

    [TestMethod]
    public async Task SuccessfulResultWithMismatchedSnapshotFailsClosedWhenRunStateIsMissing()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var successful = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var statePath = Path.Combine(fixture.Paths.StateRoot, successful.Output.RunId!, "state.json");
        File.Delete(statePath);

        var jobStore = new JobStore(fixture.Paths.StateRoot);
        var job = jobStore.Load(successful.Output.RunId!);
        jobStore.Save(job with { InputHash = new string('a', 64) });
        var changedInput = fixture.Input with
        {
            ChangeId = "change-2",
            PreviousRunId = successful.Output.RunId
        };
        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(
                new StartCommand(fixture.Repository, fixture.WriteInput(changedInput)),
                CancellationToken.None));

        Assert.AreEqual("STATE_INCOMPATIBLE", exception.Code);
        Assert.AreEqual(1, fixture.Process.Requests.Count);
    }

    [TestMethod]
    public async Task ContinueFreezesApprovedDesignAndRequiresProposalVersionForChanges()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Findings, Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var baseline = fixture.Input;

        var changedDesign = baseline with { ApprovedDesign = baseline.ApprovedDesign! with { Body = "replacement" } };
        var designError = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!, fixture.WriteInput(changedDesign)), CancellationToken.None));
        Assert.AreEqual("INPUT_MISMATCH", designError.Code);

        var changedProposalWithoutVersion = baseline with { Proposal = baseline.Proposal with { Body = "revised proposal" } };
        var versionError = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!, fixture.WriteInput(changedProposalWithoutVersion)), CancellationToken.None));
        Assert.AreEqual("INPUT_VERSION_MISMATCH", versionError.Code);

        var changedProposal = changedProposalWithoutVersion with { Proposal = changedProposalWithoutVersion.Proposal with { Version = "proposal-v2" } };
        var completed = await fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!, fixture.WriteInput(changedProposal)), CancellationToken.None);
        Assert.AreEqual("proposal-v2", completed.Output.InputBinding!.ProposalVersion);
        Assert.IsNotNull(completed.Output.InputBinding.ApprovedDesignHash);
    }

    [TestMethod]
    public async Task NewChangeAfterCompleteGetsFreshBudgetButChangedDesignNeedsUserDecision()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var complete = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        var nextChange = fixture.Input with
        {
            ChangeId = "change-2",
            PreviousRunId = complete.Output.RunId,
            ApprovedDesign = fixture.Input.ApprovedDesign! with { Body = "new approved design" }
        };
        var rejected = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, fixture.WriteInput(nextChange)), CancellationToken.None));
        Assert.AreEqual("USER_DECISION_REQUIRED", rejected.Code);

        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        nextChange = nextChange with { UserDecision = new UserDecision("Approve the new design baseline", "user") };
        var next = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, fixture.WriteInput(nextChange)), CancellationToken.None);
        Assert.AreEqual(ReviewStatuses.Complete, next.Output.Status);
        Assert.AreEqual(1, new StateStore(fixture.Paths.StateRoot).Load(next.Output.RunId!).DurableSubmissions);
    }

    [TestMethod]
    public async Task CompleteRequiresDecisionForNewApprovedDesignButNotForSameBaseline()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var originalInput = fixture.Input with { ApprovedDesign = null };
        var complete = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(originalInput)),
            CancellationToken.None);

        var changedBaseline = originalInput with
        {
            ChangeId = "change-2",
            PreviousRunId = complete.Output.RunId,
            ApprovedDesign = new ApprovedDesign("design-v2", "user-approved design", "user")
        };
        var missingDecision = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            fixture.Application.ExecuteAsync(
                new StartCommand(fixture.Repository, fixture.WriteInput(changedBaseline)),
                CancellationToken.None));
        Assert.AreEqual("USER_DECISION_REQUIRED", missingDecision.Code);

        changedBaseline = changedBaseline with
        {
            UserDecision = new UserDecision("Approve the new design baseline", "user")
        };
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var approved = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(changedBaseline)),
            CancellationToken.None);
        var approvedState = new StateStore(fixture.Paths.StateRoot).Load(approved.Output.RunId!);
        var approvedSnapshot = new ReviewInputStore(fixture.Paths.StateRoot).Load(approved.Output.RunId!, 1);

        Assert.AreEqual(ReviewStatuses.Complete, approved.Output.Status);
        Assert.AreEqual("test-task", approvedState.TaskKey);
        Assert.AreEqual("change-2", approvedState.ChangeId);
        Assert.AreEqual(complete.Output.RunId, approvedState.PreviousRunId);
        Assert.AreEqual(1, approvedState.DurableSubmissions);
        Assert.AreEqual(approvedSnapshot.Hash, approved.Output.InputHash);
        Assert.AreEqual("design-v2", approved.Output.InputBinding!.ApprovedDesignVersion);
        Assert.AreEqual("design-v2", approvedSnapshot.Binding.ApprovedDesignVersion);

        var sameBaselineNewChange = changedBaseline with
        {
            ChangeId = "change-3",
            PreviousRunId = approved.Output.RunId,
            UserDecision = null
        };
        fixture.Process.Reviews.Enqueue(Review(ReviewStatuses.Complete));
        var acceptedWithoutRepeatedDecision = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, fixture.WriteInput(sameBaselineNewChange)),
            CancellationToken.None);
        var nextState = new StateStore(fixture.Paths.StateRoot).Load(acceptedWithoutRepeatedDecision.Output.RunId!);

        Assert.AreEqual(ReviewStatuses.Complete, acceptedWithoutRepeatedDecision.Output.Status);
        Assert.AreEqual("change-3", nextState.ChangeId);
        Assert.AreEqual(approved.Output.RunId, nextState.PreviousRunId);
        Assert.AreEqual(1, nextState.DurableSubmissions);
    }

    [TestMethod]
    [DataRow("copilot")]
    [DataRow("codex")]
    public async Task FakeProviderExecutableCompletesNewAndResumeProcessBoundary(string provider)
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-process-tests", Guid.NewGuid().ToString("N"));
        var repository = Path.Combine(root, "repository");
        var configPath = Path.Combine(root, "config", "config.json");
        var stateRoot = Path.Combine(root, "state", "runs");
        Directory.CreateDirectory(repository);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        var purpose = provider == "copilot"
            ? "FAKE-INTEGRATION-CONTEXT\n" + new string('あ', 10_000) + "\nFAKE-JAPANESE-END-終端"
            : "FAKE-INTEGRATION-CONTEXT";
        var input = RunnerFixture.CreateInput() with
        {
            Purpose = RunnerFixture.CreateInput().Purpose with { Body = purpose, Original = purpose }
        };
        var inputPath = Path.Combine(root, "review-input.json");
        File.WriteAllText(inputPath, JsonSerializer.Serialize(input, JsonDefaults.Options));
        var executable = CreateFakeProviderLauncher(root);
        File.WriteAllText(
            configPath,
            JsonSerializer.Serialize(new RunnerConfig(1, provider, executable, "test-model", "high", null), JsonDefaults.Options));
        var launcher = new InProcessWorkerLauncher();
        var application = new RunnerApplication(
            new RunnerPaths(configPath, stateRoot),
            new ExecutableResolver(),
            new SystemProcessRunner(TimeSpan.FromSeconds(15)),
            launcher);
        launcher.Application = application;

        try
        {
            var first = await application.ExecuteAsync(new StartCommand(repository, inputPath), CancellationToken.None);
            var nextInputPath = Path.Combine(root, "continue-input.json");
            File.WriteAllText(nextInputPath, JsonSerializer.Serialize(input, JsonDefaults.Options));
            var second = await application.ExecuteAsync(new ContinueCommand(first.Output.RunId!, nextInputPath), CancellationToken.None);

            Assert.AreEqual(ReviewStatuses.Findings, first.Output.Status);
            Assert.AreEqual(JobStatuses.Succeeded, first.Output.JobStatus);
            Assert.AreEqual(ReviewStatuses.Complete, second.Output.Status);
            Assert.AreEqual(2, second.Output.Round);
            var inputStore = new ReviewInputStore(stateRoot);
            Assert.AreEqual(inputStore.Load(first.Output.RunId!, 1).Hash, first.Output.InputHash);
            Assert.AreEqual(inputStore.Load(first.Output.RunId!, 2).Hash, second.Output.InputHash);
            Assert.AreEqual("purpose-v1", first.Output.InputBinding!.PurposeVersion);
            Assert.AreEqual("design-v1", first.Output.InputBinding.ApprovedDesignVersion);
            Assert.AreEqual("proposal-v1", first.Output.InputBinding.ProposalVersion);
            Assert.AreEqual("purpose-v1", second.Output.InputBinding!.PurposeVersion);
            Assert.AreEqual("proposal-v1", second.Output.InputBinding.ProposalVersion);
            var state = new StateStore(stateRoot).Load(first.Output.RunId!);
            Assert.AreEqual(provider == "codex" ? "22222222-2222-4222-8222-222222222222" : state.SessionHandle, state.SessionHandle);
            Assert.IsFalse(string.IsNullOrWhiteSpace(state.SessionHandle));
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
    [DoNotParallelize]
    public async Task WorkerStartFailureIsTraced()
    {
        using var fixture = new RunnerFixture("copilot", new ThrowingWorkerLauncher());
        fixture.WriteRepositoryFile("goal.md", "goal");
        using var traceText = new StringWriter();
        using var listener = new TextWriterTraceListener(traceText);
        Trace.Listeners.Add(listener);
        try
        {
            var result = await fixture.Application.ExecuteAsync(
                fixture.StartCommand(),
                CancellationToken.None);
            listener.Flush();

            Assert.AreEqual("WORKER_START_FAILED", result.Output.Error?.Code);
            Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
            StringAssert.Contains(traceText.ToString(), nameof(RunnerException));
            StringAssert.Contains(traceText.ToString(), "The review worker process did not start.");
        }
        finally
        {
            Trace.Listeners.Remove(listener);
        }
    }

    [TestMethod]
    public async Task StartReturnsWithoutWaitingWhenWorkerIsDetachedFromSubmit()
    {
        var launcher = new RecordingWorkerLauncher();
        using var fixture = new RunnerFixture("copilot", launcher);
        fixture.WriteRepositoryFile("goal.md", "goal");
        var stopwatch = Stopwatch.StartNew();

        var submitted = await fixture.Application.ExecuteAsync(
            fixture.StartCommand(),
            CancellationToken.None);

        stopwatch.Stop();
        Assert.AreEqual(JobStatuses.Running, submitted.Output.JobStatus);
        Assert.AreEqual(ReviewStatuses.Running, submitted.Output.Status);
        Assert.IsFalse(submitted.Output.Terminal);
        Assert.AreEqual(1, launcher.LaunchCount);
        Assert.IsEmpty(fixture.Process.Requests);
        Assert.IsLessThan(TimeSpan.FromSeconds(2), stopwatch.Elapsed);
        var status = await fixture.Application.ExecuteAsync(new StatusCommand(submitted.Output.RunId!), CancellationToken.None);
        Assert.AreEqual(JobStatuses.Running, status.Output.JobStatus);
        Assert.IsEmpty(fixture.Process.Requests);
    }

    [TestMethod]
    public async Task StatusDoesNotRerunProviderAndCompletedResultIsRepeatable()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var first = await fixture.Application.ExecuteAsync(new StatusCommand(start.Output.RunId!), CancellationToken.None);
        var second = await fixture.Application.ExecuteAsync(new StatusCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, start.Output.Status);
        Assert.AreEqual(start.Output.Status, first.Output.Status);
        Assert.AreEqual(start.Output.Status, second.Output.Status);
        Assert.AreEqual(start.Output.Findings[0].Id, second.Output.Findings[0].Id);
        Assert.AreEqual(JobStatuses.Succeeded, second.Output.JobStatus);
        Assert.HasCount(1, fixture.Process.Requests);
    }

    [TestMethod]
    public async Task DuplicateContinueIsRejectedWhileJobIsRunning()
    {
        var launcher = new RecordingWorkerLauncher();
        using var fixture = new RunnerFixture("copilot", launcher);
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var inProcess = new InProcessWorkerLauncher();
        var prepared = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, inProcess);
        inProcess.Application = prepared;
        var start = await prepared.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);

        var runningFixture = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, launcher);
        var firstContinue = await runningFixture.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None);
        var duplicate = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => runningFixture.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual(JobStatuses.Running, firstContinue.Output.JobStatus);
        Assert.AreEqual(2, firstContinue.Output.Round);
        Assert.AreEqual("JOB_IN_PROGRESS", duplicate.Code);
        Assert.AreEqual(1, launcher.LaunchCount);
        Assert.HasCount(1, fixture.Process.Requests);
    }

    [TestMethod]
    public async Task ContinueReturnsRunningWithoutWaitingWhenWorkerIsDetachedFromSubmit()
    {
        var launcher = new RecordingWorkerLauncher();
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var continueApp = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, launcher);
        var stopwatch = Stopwatch.StartNew();

        var submitted = await continueApp.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None);

        stopwatch.Stop();
        Assert.AreEqual(JobStatuses.Running, submitted.Output.JobStatus);
        Assert.AreEqual(2, submitted.Output.Round);
        Assert.AreEqual(1, launcher.LaunchCount);
        Assert.HasCount(1, fixture.Process.Requests);
        Assert.IsLessThan(TimeSpan.FromSeconds(2), stopwatch.Elapsed);
    }

    [TestMethod]
    public async Task StatusMarksAbandonedWorkerAsTerminalErrorAndBlocksContinue()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(fixture.StartCommand(), CancellationToken.None);
        var jobStore = new JobStore(fixture.Paths.StateRoot);
        File.Delete(Path.Combine(fixture.Paths.StateRoot, start.Output.RunId!, "result.json"));
        jobStore.Save(new JobState(
            Protocol.JobSchemaVersion,
            start.Output.RunId!,
            2,
            JobOperations.Continue,
            JobStatuses.Running,
            DateTimeOffset.UtcNow.AddMinutes(-5),
            Pid: 999_999_999,
            ProcessStartTimeUtc: DateTimeOffset.UtcNow.AddMinutes(-5),
            Repository: fixture.Repository));

        var status = await fixture.Application.ExecuteAsync(new StatusCommand(start.Output.RunId!), CancellationToken.None);
        var state = new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!);
        var continuation = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(fixture.ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("WORKER_ABANDONED", status.Output.Error?.Code);
        Assert.AreEqual(JobStatuses.Failed, status.Output.JobStatus);
        Assert.AreEqual(ExitCodes.RuntimeError, status.ExitCode);
        Assert.AreEqual(ReviewStatuses.Error, state.Status);
        Assert.AreEqual("RUN_TERMINAL", continuation.Code);
        Assert.HasCount(1, fixture.Process.Requests);
    }

    [TestMethod]
    public async Task DetachedStartReturnsBeforeProviderAndStatusReadsDurableResult()
    {
        if (OperatingSystem.IsWindows() &&
            !string.Equals(Environment.GetEnvironmentVariable("PURPOSE_REVIEW_RUNNER_WINDOWS_JOB_QUALIFICATION"), "1", StringComparison.Ordinal))
        {
            Assert.Inconclusive("Windows process-level durable launch uses real Job Object/WMI and is opt-in. Set PURPOSE_REVIEW_RUNNER_WINDOWS_JOB_QUALIFICATION=1 to run it.");
            return;
        }

        var root = Path.Combine(Path.GetTempPath(), "purpose-review-runner-detach-tests", Guid.NewGuid().ToString("N"));
        var repository = Path.Combine(root, "repository");
        var configPath = Path.Combine(root, "config", "config.json");
        var stateRoot = Path.Combine(root, "state", "runs");
        var counterPath = Path.Combine(root, "provider-counter.txt");
        Directory.CreateDirectory(repository);
        Directory.CreateDirectory(Path.GetDirectoryName(configPath)!);
        var input = RunnerFixture.CreateInput() with
        {
            Purpose = RunnerFixture.CreateInput().Purpose with { Body = "FAKE-INTEGRATION-CONTEXT\nFAKE-JAPANESE-END-終端", Original = "FAKE-INTEGRATION-CONTEXT\nFAKE-JAPANESE-END-終端" }
        };
        var inputPath = Path.Combine(root, "review-input.json");
        File.WriteAllText(inputPath, JsonSerializer.Serialize(input, JsonDefaults.Options));
        var executable = CreateFakeProviderLauncher(root);
        File.WriteAllText(
            configPath,
            JsonSerializer.Serialize(new RunnerConfig(1, "copilot", executable, "test-model", "high", null), JsonDefaults.Options));
        var runnerPath = Path.Combine(
            Path.GetDirectoryName(typeof(RunnerApplication).Assembly.Location)!,
            OperatingSystem.IsWindows() ? "purpose-review-runner.exe" : "purpose-review-runner");

        try
        {
            var startWatch = Stopwatch.StartNew();
            var start = await RunRunnerCliAsync(
                runnerPath,
                ["start", "--repository", repository, "--input", inputPath],
                configPath,
                stateRoot,
                new Dictionary<string, string>
                {
                    ["PURPOSE_REVIEW_FAKE_PROVIDER_DELAY_MS"] = "31000",
                    ["PURPOSE_REVIEW_FAKE_PROVIDER_COUNTER"] = counterPath
                });
            startWatch.Stop();
            Assert.IsLessThan(TimeSpan.FromSeconds(5), startWatch.Elapsed);

            Assert.AreEqual(0, start.ExitCode, start.StandardOutput + start.StandardError);
            using var startDocument = JsonDocument.Parse(start.StandardOutput.Trim());
            Assert.AreEqual(JobStatuses.Running, startDocument.RootElement.GetProperty("jobStatus").GetString());
            Assert.AreEqual(ReviewStatuses.Running, startDocument.RootElement.GetProperty("status").GetString());
            var runId = startDocument.RootElement.GetProperty("runId").GetString();
            Assert.IsFalse(string.IsNullOrWhiteSpace(runId));
            var launcherLog = File.ReadAllText(Path.Combine(stateRoot, runId!, "launcher.log"));
            StringAssert.Contains(launcherLog, "outsideJobIntended=true");
            StringAssert.Contains(launcherLog, "success=true");
            StringAssert.Contains(launcherLog, "configPathOverrideSet=true");
            StringAssert.Contains(launcherLog, "stateRootOverrideSet=true");
            Assert.IsFalse(launcherLog.Contains("FAKE-INTEGRATION-CONTEXT", StringComparison.Ordinal));

            var running = await RunRunnerCliAsync(runnerPath, ["status", "--run", runId!], configPath, stateRoot);
            Assert.AreEqual(0, running.ExitCode, running.StandardError);
            using var runningDocument = JsonDocument.Parse(running.StandardOutput.Trim());
            Assert.AreEqual(JobStatuses.Running, runningDocument.RootElement.GetProperty("jobStatus").GetString());

            var completed = await PollStatusAsync(runnerPath, runId!, configPath, stateRoot, TimeSpan.FromSeconds(50));
            Assert.AreEqual(ReviewStatuses.Findings, completed.RootElement.GetProperty("status").GetString());
            Assert.AreEqual(JobStatuses.Succeeded, completed.RootElement.GetProperty("jobStatus").GetString());

            var repeated = await RunRunnerCliAsync(runnerPath, ["status", "--run", runId!], configPath, stateRoot);
            using var repeatedDocument = JsonDocument.Parse(repeated.StandardOutput.Trim());
            Assert.AreEqual(ReviewStatuses.Findings, repeatedDocument.RootElement.GetProperty("status").GetString());
            Assert.AreEqual(1, File.ReadAllLines(counterPath).Length);

            var continueWatch = Stopwatch.StartNew();
            var continuation = await RunRunnerCliAsync(
                runnerPath,
                ["continue", "--run", runId!, "--input", inputPath],
                configPath,
                stateRoot,
                new Dictionary<string, string>
                {
                    ["PURPOSE_REVIEW_FAKE_PROVIDER_DELAY_MS"] = "3000",
                    ["PURPOSE_REVIEW_FAKE_PROVIDER_COUNTER"] = counterPath
                });
            continueWatch.Stop();
            Assert.AreEqual(0, continuation.ExitCode, continuation.StandardError);
            using var continueDocument = JsonDocument.Parse(continuation.StandardOutput.Trim());
            Assert.AreEqual(JobStatuses.Running, continueDocument.RootElement.GetProperty("jobStatus").GetString());
            Assert.IsLessThan(TimeSpan.FromSeconds(5), continueWatch.Elapsed);

            var continued = await PollStatusAsync(runnerPath, runId!, configPath, stateRoot, TimeSpan.FromSeconds(20));
            Assert.AreEqual(ReviewStatuses.Complete, continued.RootElement.GetProperty("status").GetString());
            Assert.AreEqual(2, continued.RootElement.GetProperty("round").GetInt32());
            Assert.AreEqual(2, File.ReadAllLines(counterPath).Length);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, true);
            }
        }
    }

    private static async Task<JsonDocument> PollStatusAsync(
        string runnerPath,
        string runId,
        string configPath,
        string stateRoot,
        TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        string? lastOutput = null;
        while (DateTime.UtcNow < deadline)
        {
            var status = await RunRunnerCliAsync(runnerPath, ["status", "--run", runId], configPath, stateRoot);
            lastOutput = status.StandardOutput;
            if (status.ExitCode == 0)
            {
                var document = JsonDocument.Parse(status.StandardOutput.Trim());
                if (document.RootElement.GetProperty("jobStatus").GetString() != JobStatuses.Running)
                {
                    return document;
                }
                document.Dispose();
            }
            await Task.Delay(500);
        }
        throw new AssertFailedException($"Timed out waiting for durable job completion. Last output:{Environment.NewLine}{lastOutput}");
    }

    private static async Task<(int ExitCode, string StandardOutput, string StandardError)> RunRunnerCliAsync(
        string runnerPath,
        IReadOnlyList<string> arguments,
        string configPath,
        string stateRoot,
        IReadOnlyDictionary<string, string>? extraEnvironment = null)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = runnerPath,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        startInfo.Environment["PURPOSE_REVIEW_RUNNER_CONFIG_PATH"] = configPath;
        startInfo.Environment["PURPOSE_REVIEW_RUNNER_STATE_ROOT"] = stateRoot;
        if (extraEnvironment is not null)
        {
            foreach (var pair in extraEnvironment)
            {
                startInfo.Environment[pair.Key] = pair.Value;
            }
        }
        using var process = Process.Start(startInfo) ?? throw new AssertFailedException("Runner process did not start.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        return (process.ExitCode, await stdout, await stderr);
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

    private static string TranscriptDirectory(RunnerFixture fixture, string runId) =>
        Path.Combine(fixture.Paths.StateRoot, runId, "transcript");

    private static string Review(string status, params ReviewFinding[] findings)
    {
        var message = status is "BLOCKED" or "HUMAN_DECISION_REQUIRED" ? "decision required" : null;
        var requests = status == ReviewStatuses.Blocked
            ? new[] { new InformationRequest("INFO-001", "user", "Confirm the authority", "The source is needed to assess approval.") }
            : [];
        var body = JsonSerializer.Serialize(new ReviewerResponse(status, findings, message, requests), JsonDefaults.Options);
        return $"BEGIN_PURPOSE_REVIEW\n{body}\nEND_PURPOSE_REVIEW";
    }
}

internal sealed class InProcessWorkerLauncher : IWorkerLauncher
{
    public RunnerApplication? Application { get; set; }

    public WorkerLaunchResult Launch(string runId)
    {
        if (Application is null)
        {
            throw new InvalidOperationException("Application was not assigned.");
        }
        Application.ExecuteAsync(new WorkCommand(runId), CancellationToken.None).GetAwaiter().GetResult();
        var process = Process.GetCurrentProcess();
        return new(process.Id, new DateTimeOffset(process.StartTime.ToUniversalTime()));
    }
}

internal sealed class ThrowingWorkerLauncher : IWorkerLauncher
{
    public WorkerLaunchResult Launch(string runId) =>
        throw new RunnerException("WORKER_START_FAILED", "The review worker process did not start.", ExitCodes.RuntimeError);
}

internal sealed class RecordingWorkerLauncher : IWorkerLauncher
{
    public int LaunchCount { get; private set; }

    public WorkerLaunchResult Launch(string runId)
    {
        LaunchCount++;
        var process = Process.GetCurrentProcess();
        return new(process.Id, new DateTimeOffset(process.StartTime.ToUniversalTime()));
    }
}

internal sealed class RunnerFixture : IDisposable
{
    public RunnerFixture(string provider, IWorkerLauncher? workerLauncher = null)
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
        if (workerLauncher is null)
        {
            var inProcess = new InProcessWorkerLauncher();
            Application = new(Paths, new FakeExecutableResolver(), Process, inProcess);
            inProcess.Application = Application;
        }
        else
        {
            Application = new(Paths, new FakeExecutableResolver(), Process, workerLauncher);
        }
    }

    public string Root { get; }
    public string Repository { get; }
    public string ExternalRoot { get; }
    public RunnerPaths Paths { get; }
    public ScriptedProcessRunner Process { get; }
    public RunnerApplication Application { get; }

    public ReviewInput Input { get; private set; } = CreateInput();

    public StartCommand StartCommand(string purposeBody = "test purpose")
    {
        Input = Input with { Purpose = Input.Purpose with { Body = purposeBody, Original = purposeBody } };
        return new(Repository, WriteInput(Input));
    }

    public ContinueCommand ContinueCommand(string runId)
    {
        var state = new StateStore(Paths.StateRoot).Load(runId);
        Input = new ReviewInputStore(Paths.StateRoot).Load(runId, state.Round).Input with { PriorReviewHistory = null };
        return new(runId, WriteInput(Input));
    }

    public string WriteInput(ReviewInput input)
    {
        Input = input;
        var path = Path.Combine(Root, "review-input.json");
        File.WriteAllText(path, JsonSerializer.Serialize(input, JsonDefaults.Options));
        return path;
    }

    public static ReviewInput CreateInput() => new(
        Protocol.InputSchemaVersion,
        "test-task",
        "change-1",
        null,
        new PurposeDocument("purpose-v1", ["user brief"], "test purpose", "test purpose", "user"),
        new ApprovedDesign("design-v1", "approved design", "user"),
        new ProposalDocument("proposal-v1", "proposed change", "initial proposal"),
        [new EvidenceItem("evidence-1", "user supplied", "supporting evidence")],
        [], [], null);

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
    public List<string> ReviewTexts { get; } = [];
    public List<ProcessRequest> Requests { get; } = [];
    public ProcessResult? ForcedResult { get; set; }
    public string CodexSessionId { get; } = "11111111-1111-4111-8111-111111111111";

    public Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken)
    {
        if (request.Arguments.SequenceEqual(["--version"], StringComparer.Ordinal))
        {
            var version = provider == "codex" ? "codex-cli 0.165.0" : "GitHub Copilot CLI 1.0.105";
            return Task.FromResult(new ProcessResult(0, version, string.Empty, false));
        }
        if (request.Arguments.SequenceEqual(["mcp", "list", "--json"], StringComparer.Ordinal))
        {
            return Task.FromResult(new ProcessResult(0, "{\"mcpServers\":{\"test-server\":{\"source\":\"user\",\"enabled\":true}}}", string.Empty, false));
        }
        Requests.Add(request);
        if (ForcedResult is not null)
        {
            return Task.FromResult(ForcedResult);
        }
        var review = Reviews.Dequeue();
        ReviewTexts.Add(review);
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
        var outputIndex = Array.IndexOf(arguments, "--output-last-message");
        File.WriteAllText(arguments[outputIndex + 1], review);
        return new(0, JsonSerializer.Serialize(new { type = "thread.started", thread_id = CodexSessionId }), string.Empty, false);
    }

    private ProcessResult CopilotResult(ProcessRequest request, string review)
    {
        var sessionArgument = request.Arguments.Single(argument => argument.StartsWith("--session-id=", StringComparison.Ordinal) || argument.StartsWith("--resume=", StringComparison.Ordinal));
        var requested = sessionArgument[(sessionArgument.IndexOf('=') + 1)..];
        copilotSession = sessionArgument.StartsWith("--session-id=", StringComparison.Ordinal)
            ? requested
            : copilotSession;
        var output = string.Join("\n",
            JsonSerializer.Serialize(new { type = "assistant.message", data = new { content = review, model = "test-model" } }),
            JsonSerializer.Serialize(new { type = "result", sessionId = copilotSession }));
        return new(0, output, string.Empty, false);
    }
}
