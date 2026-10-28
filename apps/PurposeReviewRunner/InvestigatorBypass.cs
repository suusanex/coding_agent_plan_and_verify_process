using System.Diagnostics;
using System.Security.Cryptography;

namespace PurposeReviewRunner;

public sealed record RepositoryChangeSize(int Files, int AddedLines, int DeletedLines, string Scope, IReadOnlyList<string> Paths);

/// <summary>Git が追跡するファイルと非ignored untracked fileの安全な比較用snapshotを作る。</summary>
public sealed class InvestigatorBypass(IProcessRunner processRunner, IExecutableResolver executableResolver)
{
    private const long MaximumBytes = 64L * 1024 * 1024;

    public async Task<string?> CaptureAsync(string repository, string runDirectory, int round, CancellationToken cancellationToken)
    {
        string? partial = null;
        try
        {
            var git = executableResolver.Resolve("git");
            var repositoryRoot = Path.GetFullPath(repository);
            var excludedRoot = Path.GetFullPath(runDirectory);
            var entries = (await GetEntries(git, repository, cancellationToken))
                .Where(path => !IsUnder(excludedRoot, Path.GetFullPath(Path.Combine(repositoryRoot, path))))
                .ToArray();
            if (entries.Length == 0) return null;
            var target = Path.Combine(runDirectory, "repository-snapshots", $"round-{round:D2}");
            if (Directory.Exists(target)) Directory.Delete(target, true);
            partial = target + ".partial-" + Guid.NewGuid().ToString("N");
            Directory.CreateDirectory(partial);
            long total = 0;
            foreach (var relative in entries)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var source = Path.GetFullPath(Path.Combine(repositoryRoot, relative));
                if (!IsUnder(repositoryRoot, source)) return null;
                if (!File.Exists(source)) continue;
                if (!HasOnlyRegularParents(repositoryRoot, source)) return null;
                var attributes = File.GetAttributes(source);
                if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory | FileAttributes.Device)) != 0) return null;
                var info = new FileInfo(source);
                total = checked(total + info.Length);
                if (total > MaximumBytes) return null;
                var destination = Path.Combine(partial, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                await using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true))
                await using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, true))
                {
                    await input.CopyToAsync(output, cancellationToken);
                    if (input.Length != info.Length || new FileInfo(source).Length != info.Length) return null;
                }
                if (IsBinary(destination)) return null;
                var sourceHash = await HashFileAsync(source, cancellationToken);
                var snapshotHash = await HashFileAsync(destination, cancellationToken);
                if (!CryptographicOperations.FixedTimeEquals(sourceHash, snapshotHash)) return null;
            }

            // 一度目と二度目のGit一覧が異なる場合は、比較中の変更として扱う。
            var after = await GetEntries(git, repository, cancellationToken);
            var filteredAfter = after.Where(path => !IsUnder(excludedRoot, Path.GetFullPath(Path.Combine(repositoryRoot, path)))).ToArray();
            if (!entries.SequenceEqual(filteredAfter, StringComparer.Ordinal)) return null;
            Directory.Move(partial, target);
            partial = null;
            return target;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return null;
        }
        finally
        {
            if (partial is not null && Directory.Exists(partial))
            {
                try { Directory.Delete(partial, true); }
                catch (Exception exception) { Trace.TraceError(exception.ToString()); }
            }
        }
    }

    public async Task<RepositoryChangeSize?> CompareAsync(string oldSnapshot, string newSnapshot, string repository, CancellationToken cancellationToken)
    {
        try
        {
            var git = executableResolver.Resolve("git");
            var result = await processRunner.RunAsync(new(git,
                ["--no-pager", "diff", "--no-index", "--no-renames", "--no-ext-diff", "--no-textconv", "--numstat", "-z", "--", oldSnapshot, newSnapshot], repository, null), cancellationToken);
            if (result.TimedOut || result.ExitCode is not (0 or 1))
            {
                Trace.TraceError($"Git snapshot comparison failed: exitCode={result.ExitCode}, timedOut={result.TimedOut}, stderr={result.StandardError}");
                return null;
            }
            var parsed = ParseNumstat(result.StandardOutput, oldSnapshot, newSnapshot);
            return parsed is null ? null : new(parsed.Value.Files, parsed.Value.Added, parsed.Value.Deleted, "tracked-and-nonignored-untracked", parsed.Value.Paths);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return null;
        }
    }

    private async Task<string[]> GetEntries(string git, string repository, CancellationToken cancellationToken)
    {
        var unresolved = await Run(git, repository, ["ls-files", "-u", "-z"], cancellationToken);
        if (!string.IsNullOrEmpty(unresolved)) throw new InvalidDataException("Repository contains unresolved index entries.");
        var staged = await Run(git, repository, ["ls-files", "--stage", "-z"], cancellationToken);
        var paths = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in SplitNul(staged))
        {
            var tab = entry.IndexOf('\t');
            if (tab < 0) throw new InvalidDataException("Git returned an invalid index entry.");
            var metadata = entry[..tab].Split(' ');
            if (metadata.Length != 3 || metadata[2] != "0" || metadata[0] is "160000" or "120000")
                throw new InvalidDataException("Repository contains a submodule or unresolved entry.");
            paths.Add(entry[(tab + 1)..]);
        }
        var untracked = await Run(git, repository, ["ls-files", "--others", "--exclude-standard", "-z"], cancellationToken);
        foreach (var path in SplitNul(untracked)) paths.Add(path);
        return paths.Order(StringComparer.Ordinal).ToArray();
    }

    private async Task<string> Run(string git, string repository, IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var result = await processRunner.RunAsync(new(git, arguments, repository, null), cancellationToken);
        if (result.TimedOut || result.ExitCode != 0) throw new InvalidOperationException("Git snapshot command failed.");
        return result.StandardOutput;
    }

    private static IEnumerable<string> SplitNul(string value) => value.Split('\0', StringSplitOptions.RemoveEmptyEntries);
    private static bool IsUnder(string root, string path) => path.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private static string NormalizeDiffPath(string path) => path.StartsWith("a/", StringComparison.Ordinal) || path.StartsWith("b/", StringComparison.Ordinal) ? path[2..] : path;
    private static (int Files, int Added, int Deleted, IReadOnlyList<string> Paths)? ParseNumstat(string output, string oldRoot, string newRoot)
    {
        var files = 0;
        var added = 0;
        var deleted = 0;
        var paths = new List<string>();
        var cursor = 0;
        while (cursor < output.Length)
        {
            var firstTab = output.IndexOf('\t', cursor);
            var secondTab = firstTab < 0 ? -1 : output.IndexOf('\t', firstTab + 1);
            if (firstTab < 0 || secondTab < 0) return null;
            if (!int.TryParse(output.AsSpan(cursor, firstTab - cursor), out var a) ||
                !int.TryParse(output.AsSpan(firstTab + 1, secondTab - firstTab - 1), out var d)) return null;
            cursor = secondTab + 1;
            string path;
            if (cursor < output.Length && output[cursor] == '\0')
            {
                cursor++;
                var oldEnd = output.IndexOf('\0', cursor);
                if (oldEnd < 0) return null;
                var oldPath = output[cursor..oldEnd];
                cursor = oldEnd + 1;
                var newEnd = output.IndexOf('\0', cursor);
                if (newEnd < 0) return null;
                var newPath = output[cursor..newEnd];
                cursor = newEnd + 1;
                path = oldPath == "/dev/null" ? newPath : newPath == "/dev/null" ? oldPath : newPath;
            }
            else
            {
                var end = output.IndexOf('\0', cursor);
                if (end < 0) return null;
                path = output[cursor..end];
                cursor = end + 1;
            }
            if (path.Length == 0) return null;
            path = NormalizeDiffPath(path);
            path = path.Replace('/', Path.DirectorySeparatorChar);
            var oldPrefix = Path.GetFullPath(oldRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var newPrefix = Path.GetFullPath(newRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (path.StartsWith(oldPrefix, StringComparison.OrdinalIgnoreCase)) path = Path.GetRelativePath(oldRoot, path);
            else if (path.StartsWith(newPrefix, StringComparison.OrdinalIgnoreCase)) path = Path.GetRelativePath(newRoot, path);
            else if (Path.IsPathRooted(path)) return null;
            files++;
            added = checked(added + a);
            deleted = checked(deleted + d);
            paths.Add(path.Replace(Path.DirectorySeparatorChar, '/'));
        }
        return (files, added, deleted, paths);
    }
    private static bool HasOnlyRegularParents(string root, string path)
    {
        var current = Path.GetDirectoryName(path);
        while (current is not null && IsUnder(root, current))
        {
            if ((File.GetAttributes(current) & (FileAttributes.ReparsePoint | FileAttributes.Device)) != 0) return false;
            current = Path.GetDirectoryName(current);
        }
        return true;
    }
    private static async Task<byte[]> HashFileAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
        return await SHA256.HashDataAsync(stream, cancellationToken);
    }
    private static bool IsBinary(string path)
    {
        using var stream = File.OpenRead(path);
        var buffer = new byte[8192];
        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
            if (buffer.AsSpan(0, read).Contains((byte)0)) return true;
        return false;
    }
}
