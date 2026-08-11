using CodexLocalInbox.Models;

namespace CodexLocalInbox.Services;

public interface ISpoolFileSystem
{
    IEnumerable<string> EnumerateJsonFiles(string root);
    string ReadAllText(string path);
    void Delete(string path);
    bool FileExists(string path);
    bool DirectoryExists(string path);
}

public sealed class PhysicalSpoolFileSystem : ISpoolFileSystem
{
    public IEnumerable<string> EnumerateJsonFiles(string root) =>
        Directory.Exists(root)
            ? Directory.EnumerateFiles(root, "*.json", SearchOption.TopDirectoryOnly)
            : [];

    public string ReadAllText(string path) => File.ReadAllText(path);
    public void Delete(string path) => File.Delete(path);
    public bool FileExists(string path) => File.Exists(path);
    public bool DirectoryExists(string path) => Directory.Exists(path);
}

public sealed record DeleteResult(bool Succeeded, string? ErrorMessage);

public sealed class SpoolInboxService
{
    private readonly SpoolPathResolver _pathResolver;
    private readonly SpoolItemParser _parser;
    private readonly ISpoolFileSystem _fileSystem;

    public SpoolInboxService(
        SpoolPathResolver? pathResolver = null,
        SpoolItemParser? parser = null,
        ISpoolFileSystem? fileSystem = null)
    {
        _pathResolver = pathResolver ?? new SpoolPathResolver();
        _parser = parser ?? new SpoolItemParser();
        _fileSystem = fileSystem ?? new PhysicalSpoolFileSystem();
    }

    public string RootPath => _pathResolver.Resolve();

    public IReadOnlyList<InboxEntry> Scan()
    {
        var root = RootPath;
        if (!_fileSystem.DirectoryExists(root))
        {
            return [];
        }

        var entries = new List<InboxEntry>();
        foreach (var path in _fileSystem.EnumerateJsonFiles(root))
        {
            try
            {
                entries.Add(_parser.Parse(path, _fileSystem.ReadAllText(path)));
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                entries.Add(new InboxEntry(path, null, $"Unable to read file: {ex.Message}"));
            }
        }

        var canonicalBySourceEventId = entries
            .Where(entry => !entry.IsError)
            .GroupBy(entry => entry.SourceEventId, StringComparer.Ordinal)
            .ToDictionary(
                group => group.Key,
                group => group
                    .OrderBy(entry => Path.GetFullPath(entry.FilePath), StringComparer.OrdinalIgnoreCase)
                    .ThenBy(entry => Path.GetFullPath(entry.FilePath), StringComparer.Ordinal)
                    .First(),
                StringComparer.Ordinal);

        var deduplicatedEntries = entries.Select(entry =>
        {
            if (entry.IsError)
            {
                return entry;
            }

            var sourceEventId = entry.SourceEventId;
            var canonical = canonicalBySourceEventId[sourceEventId];
            if (ReferenceEquals(entry, canonical))
            {
                return entry;
            }

            return new InboxEntry(
                entry.FilePath,
                null,
                $"Duplicate source_event_id '{sourceEventId}'. The canonical file is '{Path.GetFullPath(canonical.FilePath)}'.");
        });

        return deduplicatedEntries
            .OrderByDescending(entry => entry.OccurredAt ?? DateTimeOffset.MinValue)
            .ThenBy(entry => entry.Identity, StringComparer.Ordinal)
            .ThenBy(entry => Path.GetFullPath(entry.FilePath), StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public DeleteResult Delete(InboxEntry entry)
    {
        try
        {
            var root = Path.GetFullPath(RootPath)
                .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            var fullPath = Path.GetFullPath(entry.FilePath);
            if (!fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase) ||
                !fullPath.EndsWith(".json", StringComparison.OrdinalIgnoreCase) ||
                !_fileSystem.FileExists(fullPath))
            {
                return new DeleteResult(false, "The file is no longer a final JSON file inside the spool folder.");
            }

            _fileSystem.Delete(fullPath);
            return new DeleteResult(true, null);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return new DeleteResult(false, $"Unable to delete the file: {ex.Message}");
        }
    }
}
