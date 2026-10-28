using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace PurposeReviewRunner.Tests;

[TestClass]
public sealed class InvestigatorBypassTests
{
    [TestMethod]
    public async Task CapturesTrackedAndNonIgnoredUntrackedFilesAndCountsNoIndexNumstat()
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-bypass-" + Guid.NewGuid().ToString("N"));
        var repo = Path.Combine(root, "repo");
        var run = Path.Combine(root, "run");
        Directory.CreateDirectory(repo);
        try
        {
            await Git(repo, "init", "-q");
            await Git(repo, "config", "user.email", "test@example.invalid");
            await Git(repo, "config", "user.name", "Test");
            await File.WriteAllTextAsync(Path.Combine(repo, "tracked.txt"), "one\ntwo\n");
            await Git(repo, "add", "tracked.txt");
            await Git(repo, "commit", "-qm", "initial");
            var service = new InvestigatorBypass(new SystemProcessRunner(TimeSpan.FromSeconds(15)), new ExecutableResolver());
            var old = await service.CaptureAsync(repo, run, 1, CancellationToken.None);
            Assert.IsNotNull(old);
            await File.WriteAllTextAsync(Path.Combine(repo, "tracked.txt"), "one\nchanged\n");
            await File.WriteAllTextAsync(Path.Combine(repo, "new.txt"), "new line\n");
            var current = await service.CaptureAsync(repo, run, 2, CancellationToken.None);
            Assert.IsNotNull(current);
            var size = await service.CompareAsync(old, current, repo, CancellationToken.None);
            Assert.IsNotNull(size);
            Assert.AreEqual(2, size.Files);
            Assert.AreEqual(2, size.AddedLines);
            Assert.AreEqual(1, size.DeletedLines);
        }
        finally
        {
            Cleanup(root);
        }
    }

    [TestMethod]
    public async Task CaptureDeclinesBinaryFilesAndSnapshotsAbove64MiB()
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-bypass-" + Guid.NewGuid().ToString("N"));
        var repo = Path.Combine(root, "repo");
        Directory.CreateDirectory(repo);
        try
        {
            await Git(repo, "init", "-q");
            var service = new InvestigatorBypass(new SystemProcessRunner(TimeSpan.FromSeconds(15)), new ExecutableResolver());
            await File.WriteAllBytesAsync(Path.Combine(repo, "binary.bin"), [1, 0, 2]);
            Assert.IsNull(await service.CaptureAsync(repo, Path.Combine(root, "run"), 1, CancellationToken.None));
            File.Delete(Path.Combine(repo, "binary.bin"));
            await using (var stream = File.Create(Path.Combine(repo, "large.txt")))
                stream.SetLength(64L * 1024 * 1024 + 1);
            Assert.IsNull(await service.CaptureAsync(repo, Path.Combine(root, "run"), 1, CancellationToken.None));
        }
        finally
        {
            Cleanup(root);
        }
    }

    [TestMethod]
    public async Task CaptureDeclinesUnresolvedIndexAndSubmoduleEntries()
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-bypass-" + Guid.NewGuid().ToString("N"));
        var repo = Path.Combine(root, "repo");
        Directory.CreateDirectory(repo);
        try
        {
            await Git(repo, "init", "-q");
            var service = new InvestigatorBypass(new SystemProcessRunner(TimeSpan.FromSeconds(15)), new ExecutableResolver());
            Directory.CreateDirectory(Path.Combine(root, "sub"));
            await Git(Path.Combine(root, "sub"), "init", "-q");
            await Git(Path.Combine(root, "sub"), "config", "user.email", "test@example.invalid");
            await Git(Path.Combine(root, "sub"), "config", "user.name", "Test");
            await File.WriteAllTextAsync(Path.Combine(root, "sub", "file.txt"), "submodule\n");
            await Git(Path.Combine(root, "sub"), "add", "file.txt");
            await Git(Path.Combine(root, "sub"), "commit", "-qm", "initial");
            await Git(repo, "-c", "protocol.file.allow=always", "submodule", "add", "-q", Path.Combine(root, "sub"), "module");
            Assert.IsNull(await service.CaptureAsync(repo, Path.Combine(root, "run"), 1, CancellationToken.None));
        }
        finally
        {
            Cleanup(root);
        }
    }

    [TestMethod]
    public async Task CaptureDeclinesUnmergedConflictEntries()
    {
        var root = Path.Combine(Path.GetTempPath(), "purpose-review-bypass-" + Guid.NewGuid().ToString("N"));
        var repo = Path.Combine(root, "repo");
        Directory.CreateDirectory(repo);
        try
        {
            await Git(repo, "init", "-q");
            var one = Path.Combine(repo, "one.txt");
            var two = Path.Combine(repo, "two.txt");
            await File.WriteAllTextAsync(one, "one\n");
            await File.WriteAllTextAsync(two, "two\n");
            var hashOne = (await GitOutput(repo, "hash-object", "-w", "one.txt")).Trim();
            var hashTwo = (await GitOutput(repo, "hash-object", "-w", "two.txt")).Trim();
            await GitWithInput(repo, $"100644 {hashOne} 1\tconflict.txt\0", "update-index", "-z", "--index-info");
            await GitWithInput(repo, $"100644 {hashTwo} 2\tconflict.txt\0", "update-index", "-z", "--index-info");
            var service = new InvestigatorBypass(new SystemProcessRunner(TimeSpan.FromSeconds(15)), new ExecutableResolver());
            Assert.IsNull(await service.CaptureAsync(repo, Path.Combine(root, "run"), 1, CancellationToken.None));
        }
        finally
        {
            Cleanup(root);
        }
    }

    private static async Task Git(string directory, params string[] arguments)
    {
        var runner = new SystemProcessRunner(TimeSpan.FromSeconds(15));
        var result = await runner.RunAsync(new("git", arguments, directory, null), CancellationToken.None);
        Assert.IsFalse(result.TimedOut, result.StandardError);
        Assert.AreEqual(0, result.ExitCode, result.StandardError);
    }

    private static async Task GitWithInput(string directory, string input, params string[] arguments)
    {
        var result = await new SystemProcessRunner(TimeSpan.FromSeconds(15)).RunAsync(new("git", arguments, directory, input), CancellationToken.None);
        Assert.IsFalse(result.TimedOut, result.StandardError);
        Assert.AreEqual(0, result.ExitCode, result.StandardError);
    }

    private static async Task<string> GitOutput(string directory, params string[] arguments)
    {
        var result = await new SystemProcessRunner(TimeSpan.FromSeconds(15)).RunAsync(new("git", arguments, directory, null), CancellationToken.None);
        Assert.IsFalse(result.TimedOut, result.StandardError);
        Assert.AreEqual(0, result.ExitCode, result.StandardError);
        return result.StandardOutput;
    }

    private static void Cleanup(string root)
    {
        if (!Directory.Exists(root)) return;
        foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            File.SetAttributes(file, FileAttributes.Normal);
        Directory.Delete(root, true);
    }
}
