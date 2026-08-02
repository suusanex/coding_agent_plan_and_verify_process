using System.Text.Json;
using CodexLocalInbox.Services;

namespace CodexLocalInbox.Tests;

[TestClass]
[DoNotParallelize]
public sealed class SpoolInboxTests
{
    private string _root = null!;

    [TestInitialize]
    public void Initialize()
    {
        _root = Path.Combine(Path.GetTempPath(), "CodexLocalInboxTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
        Environment.SetEnvironmentVariable(SpoolPathResolver.EnvironmentVariable, _root);
    }

    [TestCleanup]
    public void Cleanup()
    {
        Environment.SetEnvironmentVariable(SpoolPathResolver.EnvironmentVariable, null);
        try { Directory.Delete(_root, true); } catch { }
    }

    [TestMethod]
    public void PathResolverUsesAbsoluteOverride()
    {
        var resolved = new SpoolPathResolver().Resolve();
        Assert.AreEqual(Path.GetFullPath(_root), resolved);

        Environment.SetEnvironmentVariable(SpoolPathResolver.EnvironmentVariable, "relative-spool");
        Assert.Throws<ArgumentException>(() => new SpoolPathResolver().Resolve());
    }

    [TestMethod]
    public void ParserRequiresExactTenFieldsAndAllowedUris()
    {
        var parser = new SpoolItemParser();
        var valid = parser.Parse("valid.json", Item("event-1", "2026-08-02T10:00:00Z"));
        Assert.IsFalse(valid.IsError);
        Assert.AreEqual("event-1", valid.Item!.SourceEventId);

        using var document = JsonDocument.Parse(Item("event-2", "2026-08-02T10:00:00Z"));
        var values = document.RootElement.EnumerateObject()
            .ToDictionary(property => property.Name, property => property.Value.Clone());
        values["extra"] = JsonDocument.Parse("\"not allowed\"").RootElement.Clone();
        var extra = parser.Parse("extra.json", JsonSerializer.Serialize(values));
        Assert.IsTrue(extra.IsError);

        var unsafeUri = parser.Parse("unsafe.json", Item("event-3", "2026-08-02T10:00:00Z", resume: "https://example.test"));
        Assert.IsTrue(unsafeUri.IsError);
    }

    [TestMethod]
    public async Task MonitorPublishesStartupSnapshot()
    {
        File.WriteAllText(Path.Combine(_root, "startup.json"), Item("event-monitor", "2026-08-02T10:00:00Z"));
        IReadOnlyList<CodexLocalInbox.Models.InboxEntry>? published = null;
        using var monitor = new SpoolMonitor(
            new SpoolInboxService(),
            snapshot =>
            {
                published = snapshot;
                return Task.CompletedTask;
            },
            debounce: TimeSpan.FromMilliseconds(20),
            period: TimeSpan.FromSeconds(10));

        await monitor.StartAsync();

        Assert.IsNotNull(published);
        Assert.AreEqual("event-monitor", published![0].Item!.SourceEventId);
    }

    [TestMethod]
    public void ScanIgnoresNonJsonAndSortsByContentWithDeterministicTies()
    {
        File.WriteAllText(Path.Combine(_root, "later-name.json"), Item("b", "2026-08-02T10:00:00Z"));
        File.WriteAllText(Path.Combine(_root, "earlier-name.json"), Item("a", "2026-08-02T10:00:00Z"));
        File.WriteAllText(Path.Combine(_root, "newer.json"), Item("c", "2026-08-03T10:00:00Z"));
        File.WriteAllText(Path.Combine(_root, "ignore.tmp"), Item("ignored", "2026-08-04T10:00:00Z"));
        File.WriteAllText(Path.Combine(_root, "invalid.json"), "{ nope");

        var entries = new SpoolInboxService().Scan();

        Assert.AreEqual(4, entries.Count);
        Assert.AreEqual("c", entries[0].Item!.SourceEventId);
        Assert.AreEqual("a", entries[1].Item!.SourceEventId);
        Assert.AreEqual("b", entries[2].Item!.SourceEventId);
        Assert.IsTrue(entries[3].IsError);
    }

    [TestMethod]
    public void DeleteRemovesValidFileAndRetainsOnFailure()
    {
        var path = Path.Combine(_root, "item.json");
        File.WriteAllText(path, Item("event-delete", "2026-08-02T10:00:00Z"));
        var service = new SpoolInboxService();
        var entry = service.Scan().Single();

        var deleted = service.Delete(entry);

        Assert.IsTrue(deleted.Succeeded);
        Assert.IsFalse(File.Exists(path));

        File.WriteAllText(path, Item("event-failure", "2026-08-02T10:00:00Z"));
        var failing = new SpoolInboxService(fileSystem: new FailingDeleteFileSystem());
        var failureEntry = failing.Scan().Single();
        var result = failing.Delete(failureEntry);
        Assert.IsFalse(result.Succeeded);
        Assert.IsTrue(File.Exists(path));
    }

    [TestMethod]
    public void UriPolicyAcceptsOnlyStrictResumeAndHttpsWithoutUserInfo()
    {
        Assert.IsTrue(UriLaunchPolicy.TryGetResumeUri("codex://threads/thread-1", out _));
        Assert.IsFalse(UriLaunchPolicy.TryGetResumeUri("codex://threads/a/b", out _));
        Assert.IsTrue(UriLaunchPolicy.TryGetResultUri("https://example.test/result", out _));
        Assert.IsFalse(UriLaunchPolicy.TryGetResultUri("https://user:pass@example.test/result", out _));
        Assert.IsFalse(UriLaunchPolicy.TryGetResultUri("http://example.test/result", out _));
    }

    [TestMethod]
    public void CardActionAutomationIdsAreDistinctAndStablePerEntry()
    {
        var item = new CodexLocalInbox.Models.SpoolItemV1(
            1,
            "codex.agent-turn-complete",
            "event-actions",
            "codex",
            "TURN_ENDED",
            DateTimeOffset.Parse("2026-08-02T10:00:00Z"),
            "Test notification",
            "owner/repository",
            "codex://threads/thread-1",
            "https://example.test/result");
        var entry = new CodexLocalInbox.Models.InboxEntry(
            Path.Combine(_root, "item.json"),
            item,
            null);
        var sameIdentity = new CodexLocalInbox.Models.InboxEntry(
            Path.Combine(_root, "renamed-item.json"),
            item,
            null);

        var actionIds = new[]
        {
            entry.ResumeAutomationId,
            entry.ResultAutomationId,
            entry.DeleteAutomationId
        };

        Assert.AreEqual(3, actionIds.Distinct(StringComparer.Ordinal).Count());
        CollectionAssert.AreEqual(
            actionIds,
            new[]
            {
                sameIdentity.ResumeAutomationId,
                sameIdentity.ResultAutomationId,
                sameIdentity.DeleteAutomationId
            });
    }

    private static string Item(
        string eventId,
        string occurredAt,
        string resume = "codex://threads/thread-1") =>
        $$"""
        {
          "schema_version": 1,
          "source": "codex.agent-turn-complete",
          "source_event_id": "{{eventId}}",
          "primary_process": "codex",
          "observed_status": "TURN_ENDED",
          "occurred_at": "{{occurredAt}}",
          "title": "Test notification",
          "repository": "owner/repository",
          "resume_uri": "{{resume}}",
          "result_uri": "https://example.test/result"
        }
        """;

    private sealed class FailingDeleteFileSystem : ISpoolFileSystem
    {
        private readonly PhysicalSpoolFileSystem _inner = new();
        public IEnumerable<string> EnumerateJsonFiles(string root) => _inner.EnumerateJsonFiles(root);
        public string ReadAllText(string path) => _inner.ReadAllText(path);
        public void Delete(string path) => throw new IOException("test delete failure");
        public bool FileExists(string path) => _inner.FileExists(path);
        public bool DirectoryExists(string path) => _inner.DirectoryExists(path);
    }
}
