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
    public void SchemaTwoConfigLoadsLeadAndInvestigatorSnapshotsAndAllowsExplicitBypass()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".json");
        try
        {
            File.WriteAllText(path, """
                {"schemaVersion":2,"reviewLead":{"provider":"grok","executable":"grok","model":"lead","reasoningEffort":"high","profile":null},"investigator":{"provider":"copilot","executable":"copilot","model":"investigator","reasoningEffort":"medium","profile":null}}
                """);
            var config = ConfigLoader.Load(path);
            Assert.AreEqual("grok", config.Provider);
            Assert.AreEqual("copilot", config.Investigator?.Provider);
            File.WriteAllText(path, """
                {"schemaVersion":2,"reviewLead":{"provider":"codex","executable":"codex","model":"lead","reasoningEffort":"high","profile":null},"investigator":null}
                """);
            Assert.IsNull(ConfigLoader.Load(path).Investigator);
            File.WriteAllText(path, """
                {"schemaVersion":2,"provider":null,"reviewLead":{"provider":"codex","executable":"codex","model":"lead","reasoningEffort":"high","profile":null},"investigator":null}
                """);
            Assert.ThrowsExactly<RunnerException>(() => ConfigLoader.Load(path));
            File.WriteAllText(path, """
                {"schemaVersion":1,"provider":"codex","executable":"codex","model":"lead","reasoningEffort":"high","profile":null,"investigator":null}
                """);
            Assert.ThrowsExactly<RunnerException>(() => ConfigLoader.Load(path));
        }
        finally { File.Delete(path); }
    }

    [TestMethod]
    public async Task InvalidInvestigatorReportFallsBackWithoutTreatingItAsAcceptedEvidence()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "purpose");
        File.WriteAllText(fixture.Paths.ConfigPath, JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            reviewLead = new ProviderSnapshot("grok", "grok", "lead", "high", null),
            investigator = new ProviderSnapshot("grok", "grok", "investigator", "medium", null)
        }, JsonDefaults.Options));
        fixture.Process.Reviews.Enqueue("not-json");
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));

        var result = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Complete, result.Output.Status);
        StringAssert.Contains(fixture.Process.ProviderPayloads.Last(), "INVESTIGATOR_UNAVAILABLE");
        Assert.IsFalse(fixture.Process.ProviderPayloads.Last().Contains("investigator-report-1.json", StringComparison.Ordinal));
        Assert.AreEqual("not-json", File.ReadAllText(Path.Combine(fixture.Paths.StateRoot, result.Output.RunId!, "investigator", "transcript", "round-01-response.md")));
    }

    [TestMethod]
    public void InvestigatorReportRejectsMissingFieldsAndUnknownEvidenceReferences()
    {
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate("""{"schemaVersion":1,"evidence":[],"checked_scope":[],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[]}"""));
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate("""{"schemaVersion":1,"evidence":[{"id":"e1","path":"src/a.cs","startLine":1,"description":"code"}],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[{"id":"x","title":"x","summary":"x","evidence_ids":["missing"]}]}"""));
    }

    [TestMethod]
    [DataRow("""{"schemaVersion":1,"evidence":[],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[{"id":"x","title":"x","summary":"x"}]}""")]
    [DataRow("""{"schemaVersion":2,"evidence":[],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[]}""")]
    [DataRow("""{"schemaVersion":1,"evidence":[null],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[]}""")]
    [DataRow("""{"schemaVersion":1,"evidence":[],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[null]}""")]
    [DataRow("""{"schemaVersion":1,"evidence":null,"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[]}""")]
    [DataRow("""{"schemaVersion":1,"evidence":[],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[],"candidate_findings":[]}""")]
    [DataRow("""{"schemaVersion":1,"evidence":[{"id":"e1","path":"src/a.cs","startLine":0,"endLine":-1,"description":"code"}],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[]}""")]
    [DataRow("""{"schemaVersion":1,"evidence":[],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[{"id":"x","title":"x","summary":"x","evidence_ids":[] }]}""")]
    public void InvestigatorReportRejectsInvalidSchemaShapes(string json) =>
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate(json));

    [TestMethod]
    public void InvestigatorReportAcceptsOnlyJsonInsideSingleOrderedInvestigationBlock()
    {
        var json = ValidInvestigatorReport().Replace("source", "Protocol text mentions BEGIN_PURPOSE_INVESTIGATION and END_PURPOSE_INVESTIGATION markers.", StringComparison.Ordinal);
        var framed = "provider commentary: 調査しています; marker BEGIN_PURPOSE_INVESTIGATION is text\nBEGIN_PURPOSE_INVESTIGATION\n" + json + "\nEND_PURPOSE_INVESTIGATION\nprovider completion notice: END_PURPOSE_INVESTIGATION";
        var parsed = InvestigatorReportValidator.ParseAndValidate(framed);
        Assert.AreEqual(1, parsed.SchemaVersion);
        Assert.AreEqual(1, InvestigatorReportValidator.ParseAndValidate(json).SchemaVersion);
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate("BEGIN_PURPOSE_INVESTIGATION\n" + ValidInvestigatorReport()));
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate("END_PURPOSE_INVESTIGATION\n" + ValidInvestigatorReport() + "\nBEGIN_PURPOSE_INVESTIGATION"));
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate("BEGIN_PURPOSE_INVESTIGATION\n" + ValidInvestigatorReport() + "\nEND_PURPOSE_INVESTIGATION\nBEGIN_PURPOSE_INVESTIGATION\n{}\nEND_PURPOSE_INVESTIGATION"));
        Assert.ThrowsExactly<RunnerException>(() => InvestigatorReportValidator.ParseAndValidate("BEGIN_PURPOSE_INVESTIGATION" + ValidInvestigatorReport() + "END_PURPOSE_INVESTIGATION"));
        Assert.AreEqual(1, InvestigatorReportValidator.ParseAndValidate("progress BEGIN_PURPOSE_INVESTIGATION\n" + ValidInvestigatorReport() + "\nEND_PURPOSE_INVESTIGATION").SchemaVersion);
    }

    [TestMethod]
    public void InvestigatorReportParsesCapturedGrokResponseWithConcatenatedProgressPrefix()
    {
        var responsePath = Path.Combine(AppContext.BaseDirectory, "Fixtures", "grok-investigator-response.md");
        var rawResponse = File.ReadAllText(responsePath);

        var report = InvestigatorReportValidator.ParseAndValidate(rawResponse);

        Assert.AreEqual(1, report.SchemaVersion);
        Assert.AreEqual(6, report.Evidence.Count);
        Assert.AreEqual(3, report.CandidateFindings.Count);
    }

    [TestMethod]
    public async Task SchemaTwoUsesFreshInvestigatorEachRoundAndRetainsInitialPurposeSnapshot()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "INITIAL-PURPOSE");
        var lead = new ProviderSnapshot("grok", "grok", "lead-model", "high", "lead-profile");
        var investigator = new ProviderSnapshot("grok", "grok", "investigator-model", "medium", "investigator-profile");
        File.WriteAllText(fixture.Paths.ConfigPath, JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            reviewLead = lead,
            investigator
        }, JsonDefaults.Options));
        fixture.Process.Reviews.Enqueue(ValidInvestigatorReport());
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(ValidInvestigatorReport());
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(ValidInvestigatorReport());
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));

        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        fixture.WriteRepositoryFile("goal.md", "CHANGED-PURPOSE-FILE");
        fixture.WriteConfig("grok", "changed-grok", "changed-model");
        var continuation = await fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);
        var final = await fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(6, fixture.Process.ProviderRequests.Count);
        var investigatorRequests = fixture.Process.ProviderRequests.Where(request => request.Arguments.Contains("investigator-model")).ToArray();
        var leadRequests = fixture.Process.ProviderRequests.Where(request => request.Arguments.Contains("lead-model")).ToArray();
        Assert.AreEqual(3, investigatorRequests.Length);
        Assert.AreEqual(3, leadRequests.Length);
        Assert.AreEqual(4, fixture.Process.ProviderPayloads.Count(payload => payload.Contains("INITIAL-PURPOSE", StringComparison.Ordinal)));
        Assert.IsFalse(fixture.Process.ProviderPayloads.Any(payload => payload.Contains("CHANGED-PURPOSE-FILE", StringComparison.Ordinal)));
        Assert.AreEqual(3, investigatorRequests.Select(SessionArgument).Distinct(StringComparer.Ordinal).Count());
        Assert.AreEqual(1, leadRequests.Select(SessionArgument).Distinct(StringComparer.Ordinal).Count());
        Assert.AreEqual(ReviewStatuses.HumanDecisionRequired, final.Output.Status);
    }

    [TestMethod]
    public async Task CrossProviderInvestigatorFailureDoesNotStopPersistentLead()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "PURPOSE");
        File.WriteAllText(fixture.Paths.ConfigPath, JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            reviewLead = new ProviderSnapshot("grok", "grok", "lead", "high", null),
            investigator = new ProviderSnapshot("copilot", "copilot", "investigator", "medium", null)
        }, JsonDefaults.Options));
        fixture.Process.Reviews.Enqueue(ValidInvestigatorReport());
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue("not-json");
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));

        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        var continuation = await fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, start.Output.Status);
        Assert.AreEqual(ReviewStatuses.Complete, continuation.Output.Status);
        Assert.AreEqual(4, fixture.Process.ProviderRequests.Count);
        var investigatorRequests = fixture.Process.ProviderRequests.Where(request => request.Executable == FakeExecutableResolver.Expected("copilot")).ToArray();
        var leadRequests = fixture.Process.ProviderRequests.Where(request => request.Executable == FakeExecutableResolver.Expected("grok")).ToArray();
        Assert.AreEqual(2, investigatorRequests.Length);
        Assert.AreEqual(2, leadRequests.Length);
        Assert.AreEqual(2, investigatorRequests.Select(SessionArgument).Distinct(StringComparer.Ordinal).Count());
        Assert.AreEqual(1, leadRequests.Select(SessionArgument).Distinct(StringComparer.Ordinal).Count());
        Assert.IsTrue(File.Exists(Path.Combine(fixture.Paths.StateRoot, start.Output.RunId!, "investigator-report-1.json")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Paths.StateRoot, start.Output.RunId!, "investigator-report-2.json")));
        StringAssert.Contains(fixture.Process.ProviderPayloads[^1], "INVESTIGATOR_UNAVAILABLE");
    }

    [TestMethod]
    public async Task GitMetadataCollectorUsesDeterministicHeadStatusAndDiffCommands()
    {
        var process = new GitRecordingProcessRunner();
        var collector = new GitChangeMetadataCollector(process, new FakeExecutableResolver());
        var metadata = await collector.CollectAsync("C:\\repo", CancellationToken.None);

        StringAssert.Contains(metadata, "base: unknown");
        StringAssert.Contains(metadata, "HEAD: commit-id");
        Assert.AreEqual(4, process.Requests.Count);
        CollectionAssert.AreEqual(new[] { "rev-parse", "status", "--no-pager", "--no-pager" }, process.Requests.Select(request => request.Arguments[0]).ToArray());
        CollectionAssert.Contains(process.Requests[1].Arguments.ToArray(), "-uall");
        Assert.IsTrue(process.Requests[2].Arguments.Contains("--no-ext-diff"));
        Assert.IsTrue(process.Requests[2].Arguments.Contains("--no-textconv"));
        Assert.IsTrue(process.Requests[3].Arguments.Contains("--stat"));

        var unavailable = await new GitChangeMetadataCollector(new GitRecordingProcessRunner(exitCode: 1), new FakeExecutableResolver())
            .CollectAsync("C:\\repo", CancellationToken.None);
        StringAssert.Contains(unavailable, "Git metadata unavailable");
        StringAssert.Contains(unavailable, "Base: unknown");
    }

    [TestMethod]
    public void InvestigatorRunAndJobRejectMissingInitialPurposeSnapshot()
    {
        using var fixture = new RunnerFixture("grok");
        var runId = Guid.NewGuid().ToString("D");
        fixture.WriteRepositoryFile("goal.md", "purpose");
        var provider = new ProviderSnapshot("grok", FakeExecutableResolver.Expected("grok"), "model", "high", null);
        var investigator = new ProviderSnapshot("copilot", "copilot", "investigator", "medium", null);
        var runState = new RunState(Protocol.Version, runId, fixture.Repository, [Path.Combine(fixture.Repository, "goal.md")], provider, "session", 1, ReviewStatuses.Findings, investigator);
        Assert.ThrowsExactly<RunnerException>(() => new StateStore(fixture.Paths.StateRoot).Save(runState));

        var job = new JobState(1, runId, 1, JobOperations.Start, JobStatuses.Running, DateTimeOffset.UtcNow,
            Repository: fixture.Repository,
            ContextPaths: [Path.Combine(fixture.Repository, "goal.md")],
            Provider: provider,
            Investigator: investigator);
        Assert.ThrowsExactly<RunnerException>(() => new JobStore(fixture.Paths.StateRoot).Save(job));
    }

    [TestMethod]
    public async Task WorkerDoesNotSwallowCancellationDuringMetadataCollection()
    {
        using var fixture = new RunnerFixture("grok", new RecordingWorkerLauncher());
        fixture.WriteRepositoryFile("goal.md", "purpose");
        var app = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, new RecordingWorkerLauncher(), new CancelingChangeMetadataCollector());
        var start = await app.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() => app.ExecuteAsync(new WorkCommand(start.Output.RunId!), cancellation.Token));
    }

    private static string SessionArgument(ProcessRequest request)
    {
        var args = request.Arguments.ToArray();
        var argumentIndex = Array.FindIndex(args, argument => argument is "--session-id" or "--resume" || argument.StartsWith("--session-id=", StringComparison.Ordinal) || argument.StartsWith("--resume=", StringComparison.Ordinal));
        return args[argumentIndex].Contains('=') ? args[argumentIndex][(args[argumentIndex].IndexOf('=') + 1)..] : args[argumentIndex + 1];
    }

    private static string ValidInvestigatorReport() => """{"schemaVersion":1,"evidence":[{"id":"E1","path":"src/a.cs","startLine":1,"description":"source"}],"checked_scope":["src"],"unchecked_scope":[],"uncertainties":[],"candidate_findings":[]}""";

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
        Assert.AreEqual(JobStatuses.Succeeded, start.Output.JobStatus);
        Assert.AreEqual(ReviewStatuses.Complete, continuation.Output.Status);
        Assert.AreEqual(JobStatuses.Succeeded, continuation.Output.JobStatus);
        Assert.AreEqual(2, continuation.Output.Round);
        Assert.AreEqual(2, fixture.Process.Requests.Count);
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "GOAL-CONTEXT-ALPHA");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "ACCEPTED-DECISION-BETA");
        Assert.IsFalse(fixture.Process.Requests[1].StandardInput!.Contains("GOAL-CONTEXT-ALPHA", StringComparison.Ordinal));
        Assert.IsFalse(fixture.Process.Requests[1].StandardInput!.Contains("ACCEPTED-DECISION-BETA", StringComparison.Ordinal));
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "ファイルを変更しないでください");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "変更を伴わない調査");
        StringAssert.Contains(fixture.Process.Requests[1].StandardInput!, "ファイルを変更しないでください");
        StringAssert.Contains(fixture.Process.Requests[1].StandardInput!, "意図的に再送していません");
        StringAssert.Contains(fixture.Process.Requests[0].StandardInput!, "BEGIN_PURPOSE_REVIEW");
        StringAssert.Contains(fixture.Process.Requests[1].StandardInput!, "BEGIN_PURPOSE_REVIEW");
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), fixture.Process.CodexSessionId);
        CollectionAssert.Contains(fixture.Process.Requests[0].Arguments.ToArray(), "--dangerously-bypass-approvals-and-sandbox");
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "--dangerously-bypass-approvals-and-sandbox");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[0].Arguments.ToArray(), "-s");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[0].Arguments.ToArray(), "read-only");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[0].Arguments.ToArray(), "workspace-write");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[1].Arguments.ToArray(), "-s");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[1].Arguments.ToArray(), "sandbox_mode=\"read-only\"");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[1].Arguments.ToArray(), "read-only");
        CollectionAssert.DoesNotContain(fixture.Process.Requests[1].Arguments.ToArray(), "workspace-write");
        CollectionAssert.Contains(fixture.Process.Requests[1].Arguments.ToArray(), "test-model");

        var transcriptDirectory = TranscriptDirectory(fixture, start.Output.RunId!);
        Assert.AreEqual(fixture.Process.Requests[0].StandardInput, File.ReadAllText(Path.Combine(transcriptDirectory, "round-01-prompt.md")));
        Assert.AreEqual(fixture.Process.Requests[1].StandardInput, File.ReadAllText(Path.Combine(transcriptDirectory, "round-02-prompt.md")));
        Assert.AreEqual(fixture.Process.ReviewTexts[0], File.ReadAllText(Path.Combine(transcriptDirectory, "round-01-response.md")));
        Assert.AreEqual(fixture.Process.ReviewTexts[1], File.ReadAllText(Path.Combine(transcriptDirectory, "round-02-response.md")));
    }

    [TestMethod]
    public void StartAndContinuePromptsSeparateManualTestHandoffFromImplementationReview()
    {
        var prompts = new[]
        {
            PromptBuilder.BuildStart("C:\\repository", [("goal.md", "PURPOSE")]),
            PromptBuilder.BuildContinue(2)
        };

        foreach (var prompt in prompts)
        {
            StringAssert.Contains(prompt, "残りの実装レビューを継続してください");
            StringAssert.Contains(prompt, "未実施であることだけを理由にFINDINGSやBLOCKEDにしないでください");
            StringAssert.Contains(prompt, "確認対象の目的・要件");
            StringAssert.Contains(prompt, "実施主体と実施時点");
            StringAssert.Contains(prompt, "期待結果と合否基準");
            StringAssert.Contains(prompt, "結果の記録先と失敗時に修正へ戻す方法");
            StringAssert.Contains(prompt, "人手で必要な作業と申し送り先");
            StringAssert.Contains(prompt, "COMPLETEは未実施テストの成功、実環境での目的達成、リリース条件の充足を意味しません");
            StringAssert.Contains(prompt, "現工程で実行可能かつ許可済みの必要なテストの省略");
            StringAssert.Contains(prompt, "決定済みのテストを人が実施するだけならHUMAN_DECISION_REQUIREDではありません");
            StringAssert.Contains(prompt, "再レビューでも、この条件を満たす同じ未実施テストを不合格理由として繰り返さないでください");
        }
    }

    [TestMethod]
    public async Task MalformedReviewerResponseIsSavedBeforeProtocolParse()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        const string malformed = "malformed response with {not-json}";
        fixture.Process.Reviews.Enqueue(malformed);

        var result = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

        Assert.AreEqual("REVIEW_PARSE_FAILED", result.Output.Error?.Code);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
        var runDirectory = Directory.GetDirectories(fixture.Paths.StateRoot).Single();
        Assert.AreEqual(malformed, File.ReadAllText(Path.Combine(runDirectory, "transcript", "round-01-response.md")));
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
    [DataRow(null)]
    [DataRow("Compared base abc and HEAD def; prior uncommitted content is unavailable. PUR-002 was withdrawn.")]
    public async Task RoundThreeFindingsBecomeTerminalHumanDecisionRequired(string? reviewMessage)
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue("BEGIN_PURPOSE_REVIEW\n" + JsonSerializer.Serialize(
            new ReviewerResponse(ReviewStatuses.Findings, [Finding("PUR-001")], reviewMessage), JsonDefaults.Options) + "\nEND_PURPOSE_REVIEW");
        var first = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);
        var third = await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.HumanDecisionRequired, third.Output.Status);
        Assert.IsTrue(third.Output.Terminal);
        Assert.AreEqual(3, third.Output.Round);
        Assert.AreEqual(1, third.Output.Findings.Count);
        StringAssert.Contains(third.Output.Message!, "maximum of three review rounds");
        if (reviewMessage is not null)
        {
            StringAssert.Contains(third.Output.Message!, reviewMessage);
        }
        var stored = await fixture.Application.ExecuteAsync(new StatusCommand(first.Output.RunId!), CancellationToken.None);
        Assert.AreEqual(third.Output.Message, stored.Output.Message);
        await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None));
    }

    [TestMethod]
    public async Task CopilotUsesGeneratedSessionAndToolRestrictionContract()
    {
        using var fixture = new RunnerFixture("copilot");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var first = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        await fixture.Application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

        var startArguments = fixture.Process.Requests[0].Arguments.ToArray();
        var resumeArguments = fixture.Process.Requests[1].Arguments.ToArray();
        var startSession = startArguments.Single(value => value.StartsWith("--session-id=", StringComparison.Ordinal));
        var resumeSession = resumeArguments.Single(value => value.StartsWith("--resume=", StringComparison.Ordinal));
        Assert.AreEqual(startSession["--session-id=".Length..], resumeSession["--resume=".Length..]);
        foreach (var arguments in new[] { startArguments, resumeArguments })
        {
            var availableTools = arguments.Single(value => value.StartsWith("--available-tools=", StringComparison.Ordinal))
                ["--available-tools=".Length..].Split(',');
            foreach (var tool in new[] { "view", "grep", "bash", "powershell", "read_bash", "read_powershell", "list_bash", "list_powershell", "write_bash", "write_powershell", "stop_bash", "stop_powershell" })
            {
                CollectionAssert.Contains(availableTools, tool);
            }
            foreach (var tool in new[] { "create", "edit", "apply_patch", "task" })
            {
                CollectionAssert.DoesNotContain(availableTools, tool);
            }
            CollectionAssert.Contains(arguments, "--allow-tool=shell");
            CollectionAssert.DoesNotContain(arguments, "--deny-tool=shell");
            CollectionAssert.Contains(arguments, "--deny-tool=write");
            CollectionAssert.Contains(arguments, "--deny-tool=task");
        }
        CollectionAssert.Contains(startArguments, "--disable-builtin-mcps");
        CollectionAssert.DoesNotContain(startArguments, "--attachment");
        CollectionAssert.DoesNotContain(startArguments, "-p");
        CollectionAssert.DoesNotContain(resumeArguments, "--attachment");
        CollectionAssert.DoesNotContain(resumeArguments, "-p");
        var runDirectory = Path.Combine(fixture.Paths.StateRoot, first.Output.RunId!);
        Assert.AreEqual(
            File.ReadAllText(Path.Combine(runDirectory, "transcript", "round-01-prompt.md")),
            fixture.Process.Requests[0].StandardInput);
        Assert.AreEqual(
            File.ReadAllText(Path.Combine(runDirectory, "transcript", "round-02-prompt.md")),
            fixture.Process.Requests[1].StandardInput);
    }

    [TestMethod]
    public async Task GrokUsesToolRestrictionAndResumeContract()
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
        CollectionAssert.DoesNotContain(startArguments, "--sandbox");
        CollectionAssert.DoesNotContain(startArguments, "read-only");
        CollectionAssert.DoesNotContain(resumeArguments, "--sandbox");
        CollectionAssert.DoesNotContain(resumeArguments, "read-only");
        foreach (var arguments in new[] { startArguments, resumeArguments })
        {
            Assert.AreEqual("bypassPermissions", arguments[Array.IndexOf(arguments, "--permission-mode") + 1]);
            var availableTools = arguments[Array.IndexOf(arguments, "--tools") + 1].Split(',');
            var deniedTools = arguments[Array.IndexOf(arguments, "--disallowed-tools") + 1].Split(',');
            CollectionAssert.Contains(availableTools, "shell");
            CollectionAssert.DoesNotContain(deniedTools, "shell");
            CollectionAssert.DoesNotContain(deniedTools, "run_shell_command");
            foreach (var tool in new[] { "write", "task", "edit_file" })
            {
                CollectionAssert.Contains(deniedTools, tool);
                CollectionAssert.DoesNotContain(availableTools, tool);
            }
        }
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

        var result = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

        Assert.AreEqual("PROVIDER_FAILED", result.Output.Error?.Code);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
        Assert.AreEqual(ExitCodes.RuntimeError, result.ExitCode);
        Assert.IsEmpty(Directory.GetFiles(fixture.Paths.StateRoot, "state.json", SearchOption.AllDirectories));
        var runDirectory = Directory.GetDirectories(fixture.Paths.StateRoot).Single();
        Assert.IsTrue(File.Exists(Path.Combine(runDirectory, "transcript", "round-01-prompt.md")));
        Assert.IsFalse(File.Exists(Path.Combine(runDirectory, "transcript", "round-01-response.md")));
        var status = await fixture.Application.ExecuteAsync(new StatusCommand(result.Output.RunId!), CancellationToken.None);
        Assert.AreEqual("PROVIDER_FAILED", status.Output.Error?.Code);
        Assert.AreEqual(1, fixture.Process.Requests.Count);
    }

    [TestMethod]
    public async Task MalformedReviewFailsClosed()
    {
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue("not a review block");

        var result = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

        Assert.AreEqual("REVIEW_PARSE_FAILED", result.Output.Error?.Code);
        Assert.AreEqual(ExitCodes.ContractError, result.ExitCode);
        Assert.AreEqual(JobStatuses.Failed, result.Output.JobStatus);
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

        var malformed = await fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);
        var state = new StateStore(fixture.Paths.StateRoot).Load(start.Output.RunId!);
        var retry = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None));

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
        using var fixture = new RunnerFixture("codex");
        fixture.WriteRepositoryFile("goal.md", "User-approved structure controls downstream generation.");
        const string outcome = "The user-approved structure remains authoritative for all downstream generation and cannot be overwritten by an LLM outline.";
        fixture.Process.Reviews.Enqueue("""
            BEGIN_PURPOSE_REVIEW
            {"status":"FINDINGS","findings":[{"id":"PUR-001","severity":"HIGH","title":"Authority is inverted across the pipeline","summary":"Generation overrides the structure approved by the user.","evidence":"goal.md; the approved structure flows through OutlineGenerator.cs and SectionWriter.cs, but the generated outline replaces it.","requiredOutcome":"The user-approved structure remains authoritative for all downstream generation and cannot be overwritten by an LLM outline."}],"message":"The conflict spans the pipeline; implementation design belongs to the parent."}
            END_PURPOSE_REVIEW
            """);
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        var stored = await fixture.Application.ExecuteAsync(new StatusCommand(start.Output.RunId!), CancellationToken.None);

        Assert.AreEqual(ReviewStatuses.Findings, stored.Output.Status);
        Assert.AreEqual(outcome, stored.Output.Findings.Single().RequiredOutcome);
        using var document = JsonDocument.Parse(JsonSerializer.Serialize(stored.Output, JsonDefaults.Options));
        Assert.AreEqual(3, document.RootElement.GetProperty("protocolVersion").GetInt32());
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
        var response = JsonSerializer.SerializeToNode(new ReviewerResponse(ReviewStatuses.Findings, [Finding("PUR-001")], null), JsonDefaults.Options)!;
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
        using var fixture = new RunnerFixture("codex");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        var store = new StateStore(fixture.Paths.StateRoot);
        store.Save(store.Load(start.Output.RunId!) with { ProtocolVersion = 2 });

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() => fixture.Application.ExecuteAsync(
            new ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual("STATE_INCOMPATIBLE", exception.Code);
        Assert.HasCount(1, fixture.Process.Requests.Where(request => request.Executable == FakeExecutableResolver.Expected("codex")));
    }

    [TestMethod]
    public async Task StatusRejectsProtocolTwoResultEvenWithoutFindings()
    {
        using var fixture = new RunnerFixture("codex");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("COMPLETE"));
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
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
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        const string privateDiagnostic = "PRIVATE-PROVIDER-DIAGNOSTIC";
        fixture.Process.ForcedResult = new ProcessResult(7, string.Empty, privateDiagnostic, false);
        using var traceText = new StringWriter();
        using var listener = new TextWriterTraceListener(traceText);
        Trace.Listeners.Add(listener);
        try
        {
            var result = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
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
        var runId = Guid.NewGuid().ToString("D");
        Assert.IsInstanceOfType<ContinueCommand>(CliParser.Parse(["continue", "--run", runId]));
        Assert.IsInstanceOfType<StatusCommand>(CliParser.Parse(["status", "--run", runId]));
        Assert.IsInstanceOfType<WorkCommand>(CliParser.Parse(["work", "--run", runId]));
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

        var result = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

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
        var prompt = PromptBuilder.BuildStart(root, [("goal.md", "PURPOSE")]);
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
            Assert.AreEqual(0xE3, actual[0]);
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
        StringAssert.Contains(stateText, "UNIQUE-CONTEXT-BODY");
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
        var purpose = provider == "copilot"
            ? "FAKE-INTEGRATION-CONTEXT\n" + new string('あ', 10_000) + "\nFAKE-JAPANESE-END-終端"
            : "FAKE-INTEGRATION-CONTEXT";
        File.WriteAllText(Path.Combine(repository, "purpose.md"), purpose);
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
            var first = await application.ExecuteAsync(new StartCommand(repository, ["purpose.md"]), CancellationToken.None);
            var second = await application.ExecuteAsync(new ContinueCommand(first.Output.RunId!), CancellationToken.None);

            Assert.AreEqual(ReviewStatuses.Findings, first.Output.Status);
            Assert.AreEqual(JobStatuses.Succeeded, first.Output.JobStatus);
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

    [TestMethod]
    [DoNotParallelize]
    public async Task WorkerStartFailureIsTraced()
    {
        using var fixture = new RunnerFixture("grok", new ThrowingWorkerLauncher());
        fixture.WriteRepositoryFile("goal.md", "goal");
        using var traceText = new StringWriter();
        using var listener = new TextWriterTraceListener(traceText);
        Trace.Listeners.Add(listener);
        try
        {
            var result = await fixture.Application.ExecuteAsync(
                new StartCommand(fixture.Repository, ["goal.md"]),
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
        using var fixture = new RunnerFixture("grok", launcher);
        fixture.WriteRepositoryFile("goal.md", "goal");
        var stopwatch = Stopwatch.StartNew();

        var submitted = await fixture.Application.ExecuteAsync(
            new StartCommand(fixture.Repository, ["goal.md"]),
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
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
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
        using var fixture = new RunnerFixture("grok", launcher);
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var inProcess = new InProcessWorkerLauncher();
        var prepared = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, inProcess);
        inProcess.Application = prepared;
        var start = await prepared.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);

        var runningFixture = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, launcher);
        var firstContinue = await runningFixture.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);
        var duplicate = await Assert.ThrowsExactlyAsync<RunnerException>(
            () => runningFixture.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None));

        Assert.AreEqual(JobStatuses.Running, firstContinue.Output.JobStatus);
        Assert.AreEqual(2, firstContinue.Output.Round);
        Assert.AreEqual("JOB_IN_PROGRESS", duplicate.Code);
        Assert.AreEqual(1, launcher.LaunchCount);
        Assert.HasCount(1, fixture.Process.Requests.Where(request => request.Executable == FakeExecutableResolver.Expected("grok")));
    }

    [TestMethod]
    public async Task ContinueReturnsRunningWithoutWaitingWhenWorkerIsDetachedFromSubmit()
    {
        var launcher = new RecordingWorkerLauncher();
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        var continueApp = new RunnerApplication(fixture.Paths, new FakeExecutableResolver(), fixture.Process, launcher);
        var stopwatch = Stopwatch.StartNew();

        var submitted = await continueApp.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None);

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
        using var fixture = new RunnerFixture("grok");
        fixture.WriteRepositoryFile("goal.md", "goal");
        fixture.Process.Reviews.Enqueue(Review("FINDINGS", Finding("PUR-001")));
        var start = await fixture.Application.ExecuteAsync(new StartCommand(fixture.Repository, ["goal.md"]), CancellationToken.None);
        var jobStore = new JobStore(fixture.Paths.StateRoot);
        File.Delete(Path.Combine(fixture.Paths.StateRoot, start.Output.RunId!, "result.json"));
        jobStore.Save(new JobState(
            1,
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
            () => fixture.Application.ExecuteAsync(new ContinueCommand(start.Output.RunId!), CancellationToken.None));

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
        File.WriteAllText(Path.Combine(repository, "purpose.md"), "FAKE-INTEGRATION-CONTEXT");
        var executable = CreateFakeProviderLauncher(root);
        File.WriteAllText(
            configPath,
            JsonSerializer.Serialize(new RunnerConfig(1, "grok", executable, "test-model", "high", null), JsonDefaults.Options));
        var runnerPath = Path.Combine(
            Path.GetDirectoryName(typeof(RunnerApplication).Assembly.Location)!,
            OperatingSystem.IsWindows() ? "purpose-review-runner.exe" : "purpose-review-runner");

        try
        {
            var startWatch = Stopwatch.StartNew();
            var start = await RunRunnerCliAsync(
                runnerPath,
                ["start", "--repository", repository, "--context", "purpose.md"],
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
                ["continue", "--run", runId!],
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
        var body = JsonSerializer.Serialize(new ReviewerResponse(status, findings, message), JsonDefaults.Options);
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
            Application = new(Paths, new FakeExecutableResolver(), Process, inProcess, new EmptyChangeMetadataCollector());
            inProcess.Application = Application;
        }
        else
        {
            Application = new(Paths, new FakeExecutableResolver(), Process, workerLauncher, new EmptyChangeMetadataCollector());
        }
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

internal sealed class EmptyChangeMetadataCollector : IChangeMetadataCollector
{
    public Task<string> CollectAsync(string repository, CancellationToken cancellationToken) => Task.FromResult("Git metadata unavailable in test fixture; base: unknown.");
}

internal sealed class CancelingChangeMetadataCollector : IChangeMetadataCollector
{
    public Task<string> CollectAsync(string repository, CancellationToken cancellationToken) => Task.FromCanceled<string>(cancellationToken);
}

internal sealed class FakeExecutableResolver : IExecutableResolver
{
    public static string Expected(string executable) => Path.Combine(Path.GetTempPath(), "resolved-" + executable);

    public string Resolve(string executable) => Expected(executable);
}

internal sealed class ScriptedProcessRunner : IProcessRunner
{
    private readonly string provider;

    public ScriptedProcessRunner(string provider) => this.provider = provider;

    public Queue<string> Reviews { get; } = new();
    public List<string> ReviewTexts { get; } = [];
    public List<ProcessRequest> Requests { get; } = [];
    public List<ProcessRequest> ProviderRequests { get; } = [];
    public List<string> ProviderPayloads { get; } = [];
    public ProcessResult? ForcedResult { get; set; }
    public string CodexSessionId { get; } = "11111111-1111-4111-8111-111111111111";

    public Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        if (request.Executable == FakeExecutableResolver.Expected("git"))
        {
            return Task.FromResult(new ProcessResult(0, request.Arguments.Contains("rev-parse") ? "test-head" : string.Empty, string.Empty, false));
        }
        ProviderRequests.Add(request);
        if (request.StandardInput is not null) ProviderPayloads.Add(request.StandardInput);
        else if (request.Arguments.Contains("--prompt-file"))
        {
            var promptIndex = Array.IndexOf(request.Arguments.ToArray(), "--prompt-file");
            ProviderPayloads.Add(File.ReadAllText(request.Arguments[promptIndex + 1]));
        }
        if (ForcedResult is not null)
        {
            return Task.FromResult(ForcedResult);
        }
        var review = Reviews.Dequeue();
        ReviewTexts.Add(review);
        return Task.FromResult(request.Arguments.Contains("--stream") ? CopilotResult(request, review) : provider == "codex" ? CodexResult(request, review) : new ProcessResult(0, review, string.Empty, false));
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
        var output = string.Join("\n",
            JsonSerializer.Serialize(new { type = "assistant.message", data = new { content = review, model = "test-model" } }),
            JsonSerializer.Serialize(new { type = "result", sessionId = requested }));
        return new(0, output, string.Empty, false);
    }
}

internal sealed class GitRecordingProcessRunner : IProcessRunner
{
    private readonly int exitCode;
    public GitRecordingProcessRunner(int exitCode = 0) => this.exitCode = exitCode;
    public List<ProcessRequest> Requests { get; } = [];
    public Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        return Task.FromResult(new ProcessResult(exitCode, request.Arguments.Contains("rev-parse") ? "commit-id" : "git-output", string.Empty, false));
    }
}
