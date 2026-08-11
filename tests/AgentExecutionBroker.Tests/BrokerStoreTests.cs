using AgentExecutionBroker.Contracts;
using AgentExecutionBroker.Host;

namespace AgentExecutionBroker.Tests;

[TestClass]
[DoNotParallelize]
public sealed class BrokerStoreTests
{
    private string _root = null!;

    [TestInitialize]
    public void Initialize()
    {
        _root = Path.Combine(Path.GetTempPath(), "AgentExecutionBrokerTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        Environment.SetEnvironmentVariable("CODEX_NOTIFICATION_SPOOL_HOME", Path.Combine(_root, "spool"));
    }

    [TestCleanup]
    public void Cleanup()
    {
        Environment.SetEnvironmentVariable("CODEX_NOTIFICATION_SPOOL_HOME", null);
        try { Directory.Delete(_root, true); } catch { }
    }

    [TestMethod]
    public void RunRecordKeepsExecutionIdentityAndTransitionEvidenceSeparate()
    {
        var run = RunRecordFor(Guid.NewGuid()).WithExecutionIdentity(
            "host-1", Guid.NewGuid(), "provider-session-1", "digest");

        Assert.AreEqual("host-1", run.HostInstanceId);
        Assert.IsNotNull(run.JobId);
        Assert.AreEqual("provider-session-1", run.ProviderSessionId);
        Assert.AreEqual("digest", run.PromptDigest);
        Assert.AreEqual(1, run.StateTransitions.Count);
        Assert.AreEqual("Accepted", run.StateTransitions[0].State);
        Assert.IsNull(run.AgentReportedResult);
    }

    [TestMethod]
    public async Task CancelRequestIsDurableBeforeWorkerObservation()
    {
        var store = new BrokerStore(_root);
        var run = RunRecordFor(Guid.NewGuid());
        await using var service = new BrokerService(_root);
        store.WriteRun(run);
        var json = new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web);
        var request = new BrokerRequest("cancel_run", System.Text.Json.JsonSerializer.SerializeToElement(new RunQuery(run.RunId), json));

        var response = await service.HandleAsync(request, json, CancellationToken.None);
        var saved = store.ReadRun(run.RunId);

        Assert.IsTrue(response.Succeeded);
        Assert.IsNotNull(saved);
        Assert.AreEqual("CancelRequested", saved.State);
        Assert.IsTrue(saved.CancelRequested);
        Assert.AreEqual("Pending", saved.CancelDelivery);
        Assert.AreEqual("CancelRequested", saved.StateTransitions[^1].State);
    }

    [TestMethod]
    public void WorkerStartGuardDoesNotStartAWorkerAfterCancelRequest()
    {
        var run = RunRecordFor(Guid.NewGuid()) with
        {
            State = "CancelRequested",
            CancelRequested = true,
            CancelDelivery = "Pending",
            StateTransitions = [new RunStateTransition(1, "Accepted", DateTimeOffset.UtcNow, "host-1"), new RunStateTransition(2, "CancelRequested", DateTimeOffset.UtcNow, "host-1")]
        };

        var prepared = BrokerService.PrepareWorkerStart(run, "host-1");

        Assert.AreEqual("CancelledBeforeStart", prepared.State);
        Assert.AreEqual("NotStarted", prepared.CancelDelivery);
        Assert.AreEqual("CancelledBeforeStart", prepared.StateTransitions[^1].State);
        Assert.IsFalse(prepared.StateTransitions.Any(transition => transition.State == "Starting"));
    }

    [TestMethod]
    public void CodingProfileBuildsOnlyTheFixedAllowlist()
    {
        var run = RunRecordFor(Guid.NewGuid());
        var startInfo = CopilotCliAdapter.CreateStartInfo(run);

        CollectionAssert.AreEqual(
            new[] { "-p", "implement the requested change", "-C", run.WorkingDirectory, "--output-format", "json", "--no-ask-user", "--no-auto-update", "--session-id", run.RunId.ToString(), "--allow-tool=read,write,shell" },
            startInfo.ArgumentList.ToArray());
        Assert.IsFalse(startInfo.ArgumentList.Any(argument => argument.Contains("allow-all", StringComparison.OrdinalIgnoreCase)));
    }

    [TestMethod]
    public void OutputReadUsesCursorAndExplicitBounds()
    {
        var store = new BrokerStore(_root);
        var run = RunRecordFor(Guid.NewGuid());
        store.WriteRun(run);
        store.AppendOutput(run.RunId, "structured", "first");
        store.AppendOutput(run.RunId, "stderr", "second");
        store.AppendOutput(run.RunId, "structured", "third");

        var firstPage = store.ReadOutput(run.RunId, 0, 2, BrokerProtocol.MaximumOutputBytes);

        Assert.AreEqual(2, firstPage.Records.Count);
        Assert.AreEqual(2L, firstPage.NextAfterSequence);
        Assert.IsTrue(firstPage.HasMore);
        Assert.AreEqual("max_records", firstPage.TruncationReason);
        var secondPage = store.ReadOutput(run.RunId, firstPage.NextAfterSequence, 2, BrokerProtocol.MaximumOutputBytes);
        Assert.AreEqual(1, secondPage.Records.Count);
        Assert.AreEqual("third", secondPage.Records[0].Text);
        Assert.IsFalse(secondPage.HasMore);
    }

    [TestMethod]
    public void OutputWriterFramesUtf8RecordsAtSixteenKiB()
    {
        var store = new BrokerStore(_root);
        var run = RunRecordFor(Guid.NewGuid());
        store.WriteRun(run);
        store.AppendOutput(run.RunId, "structured", new string('x', BrokerProtocol.MaximumOutputRecordBytes + 1));

        var page = store.ReadOutput(run.RunId, 0, BrokerProtocol.MaximumOutputRecords, BrokerProtocol.MaximumOutputBytes);

        Assert.AreEqual(2, page.Records.Count);
        Assert.IsTrue(page.Records.All(record => System.Text.Encoding.UTF8.GetByteCount(record.Text) <= BrokerProtocol.MaximumOutputRecordBytes));
    }

    [TestMethod]
    public void ListRunsUsesOpaqueCursorWithoutChangingRunIdentity()
    {
        var store = new BrokerStore(_root);
        var first = RunRecordFor(Guid.NewGuid()) with { AcceptedAt = DateTimeOffset.UtcNow.AddMinutes(-1) };
        var second = RunRecordFor(Guid.NewGuid()) with { AcceptedAt = DateTimeOffset.UtcNow };
        store.WriteRun(first);
        store.WriteRun(second);

        var page = store.ListRuns(1, null);
        var next = store.ListRuns(1, page.NextCursor);

        Assert.AreEqual(1, page.Runs.Count);
        Assert.AreEqual(second.RunId, page.Runs[0].RunId);
        Assert.IsTrue(page.HasMore);
        Assert.AreEqual(first.RunId, next.Runs[0].RunId);
    }

    [TestMethod]
    public void TerminalEventUsesDeterministicIdentityAndOptionalRepository()
    {
        var spool = Path.Combine(_root, "spool");
        Environment.SetEnvironmentVariable("CODEX_NOTIFICATION_SPOOL_HOME", spool);
        try
        {
            var store = new BrokerStore(_root);
            var run = RunRecordFor(Guid.NewGuid()) with { State = "Exited", CompletedAt = DateTimeOffset.UtcNow, Repository = null };
            store.WriteRun(run);
            store.PublishTerminal(run);

            var eventJson = File.ReadAllText(Directory.EnumerateFiles(spool, "*.json").Single());
            StringAssert.Contains(eventJson, $"agent-execution-broker:run:{run.RunId}:terminal");
            Assert.IsFalse(eventJson.Contains("repository", StringComparison.Ordinal));
        }
        finally
        {
            Environment.SetEnvironmentVariable("CODEX_NOTIFICATION_SPOOL_HOME", null);
        }
    }

    [TestMethod]
    public async Task ServiceReconcilesInheritedNonterminalRunAsHostLostWorkerTreeTerminated()
    {
        var store = new BrokerStore(_root);
        var run = RunRecordFor(Guid.NewGuid()) with { State = "Running", StartedAt = DateTimeOffset.UtcNow };
        store.WriteRun(run);

        await using var service = new BrokerService(_root);

        var reconciled = store.ReadRun(run.RunId);
        Assert.IsNotNull(reconciled);
        Assert.AreEqual("HostLostWorkerTreeTerminated", reconciled.State);
        Assert.IsNull(reconciled.ExitCode);
        StringAssert.Contains(reconciled.Diagnostic!, "lost authority");
    }

    [TestMethod]
    public async Task ServiceRejectsInvalidAdmissionBeforeAnyWorkerCanStart()
    {
        await using var service = new BrokerService(_root);
        var json = new System.Text.Json.JsonSerializerOptions(System.Text.Json.JsonSerializerDefaults.Web);
        var request = new BrokerRequest("start_run", System.Text.Json.JsonSerializer.SerializeToElement(
            new StartRunRequest("unknown", Path.GetTempPath(), "prompt", BrokerProtocol.CodingProfile, null), json));

        var response = await service.HandleAsync(request, json, CancellationToken.None);

        Assert.IsFalse(response.Succeeded);
        Assert.AreEqual("unsupported-provider", response.ErrorCode);
        Assert.AreEqual(0, Directory.EnumerateFiles(Path.Combine(_root, "runs"), "run.json", SearchOption.AllDirectories).Count());
    }

    private static RunRecord RunRecordFor(Guid runId) => new(
        runId, "github-copilot-cli", Path.GetTempPath(), "implement the requested change", BrokerProtocol.CodingProfile,
        "owner/repository", "Accepted", DateTimeOffset.UtcNow, null, null, null, false, null, null, null);
}
