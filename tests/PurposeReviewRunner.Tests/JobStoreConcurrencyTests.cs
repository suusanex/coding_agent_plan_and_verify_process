using System.Collections.Concurrent;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PurposeReviewRunner;

namespace PurposeReviewRunnerTests;

[TestClass]
public sealed class JobStoreConcurrencyTests
{
    [TestMethod]
    public void SaveSucceedsWhileAnotherHandleReadsWithReplaceCompatibleShare()
    {
        using var directory = new TemporaryDirectory();
        var store = new JobStore(directory.Paths.StateRoot);
        var job = CreateJob(directory.Paths.StateRoot);
        store.Save(job);
        var path = Path.Combine(store.GetRunDirectory(job.RunId), "job.json");

        using var reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        store.Save(job with { Pid = 42, ProcessStartTimeUtc = DateTimeOffset.UtcNow });

        var reloaded = store.Load(job.RunId);
        Assert.AreEqual(42, reloaded.Pid);
    }

    [TestMethod]
    public void ExclusiveReadShareBlocksAtomicReplaceOnWindows()
    {
        if (!OperatingSystem.IsWindows())
        {
            Assert.Inconclusive("File.Move overwrite sharing is the Windows failure mode observed in CI.");
            return;
        }

        using var directory = new TemporaryDirectory();
        var store = new JobStore(directory.Paths.StateRoot);
        var job = CreateJob(directory.Paths.StateRoot);
        store.Save(job);
        var path = Path.Combine(store.GetRunDirectory(job.RunId), "job.json");

        using var blockingReader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var exception = Assert.ThrowsExactly<RunnerException>(() =>
            store.Save(job with { Pid = 7, ProcessStartTimeUtc = DateTimeOffset.UtcNow }));
        Assert.AreEqual("STATE_WRITE_FAILED", exception.Code);
        Assert.IsTrue(
            exception.InnerException is IOException or UnauthorizedAccessException,
            exception.InnerException?.ToString());
        blockingReader.Dispose();
        Assert.IsNull(store.Load(job.RunId).Pid);
    }

    [TestMethod]
    public void FailedReplacementLeavesPreviousJobState()
    {
        if (!OperatingSystem.IsWindows())
        {
            Assert.Inconclusive("Replacement sharing failures that leave dest untouched are the Windows durability case.");
            return;
        }

        using var directory = new TemporaryDirectory();
        var store = new JobStore(directory.Paths.StateRoot);
        var job = CreateJob(directory.Paths.StateRoot);
        store.Save(job);
        var path = Path.Combine(store.GetRunDirectory(job.RunId), "job.json");

        using var blockingReader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        var exception = Assert.ThrowsExactly<RunnerException>(() =>
            store.Save(job with { Pid = 9, ProcessStartTimeUtc = DateTimeOffset.UtcNow }));
        Assert.AreEqual("STATE_WRITE_FAILED", exception.Code);

        var reloaded = store.Load(job.RunId);
        Assert.IsNull(reloaded.Pid);
        Assert.AreEqual(JobStatuses.Running, reloaded.JobStatus);
    }

    [TestMethod]
    public async Task ConcurrentStatusStyleReadsDoNotFailWorkerSaves()
    {
        using var directory = new TemporaryDirectory();
        var store = new JobStore(directory.Paths.StateRoot);
        var job = CreateJob(directory.Paths.StateRoot);
        store.Save(job);
        using var cancellation = new CancellationTokenSource();
        var errors = new ConcurrentBag<Exception>();

        var reader = Task.Run(() =>
        {
            while (!cancellation.IsCancellationRequested)
            {
                try
                {
                    _ = store.Load(job.RunId);
                }
                catch (Exception exception)
                {
                    errors.Add(exception);
                }
            }
        });

        try
        {
            for (var index = 1; index <= 200; index++)
            {
                store.Save(job with { Pid = index, ProcessStartTimeUtc = DateTimeOffset.UtcNow });
            }
        }
        finally
        {
            await cancellation.CancelAsync();
            await reader;
        }

        Assert.IsEmpty(errors, string.Join(Environment.NewLine, errors.Select(error => error.ToString())));
        Assert.AreEqual(200, store.Load(job.RunId).Pid);
    }

    private static JobState CreateJob(string stateRoot) =>
        new(
            1,
            Guid.NewGuid().ToString("D"),
            1,
            JobOperations.Start,
            JobStatuses.Running,
            DateTimeOffset.UtcNow,
            Repository: Path.GetFullPath(Path.Combine(stateRoot, "repo")),
            ContextPaths: [Path.GetFullPath(Path.Combine(stateRoot, "goal.md"))],
            Provider: new ProviderSnapshot("grok", FakeExecutableResolver.Expected("grok"), "test-model", "high", null));
}
