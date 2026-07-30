#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

var options = Options.Parse(args);
if (options.ShowHelp)
{
    ShowUsage();
    return 0;
}

if (!options.Valid)
{
    ShowUsage();
    return 2;
}

try
{
    var repositoryRoot = ResolveExistingPath(Path.GetFullPath(options.RepositoryRoot));
    if (!Directory.Exists(repositoryRoot))
    {
        throw new DirectoryNotFoundException($"Repository root does not exist: {repositoryRoot}");
    }

    var candidates = ResolveCandidates(repositoryRoot, options);
    if (candidates.Count == 0)
    {
        return Stop("NO_GOAL_CONTEXT", "No goal-context-*.md candidate was found. Select a readable Goal Context with --goal-context, or explicitly choose the baseline $pr-review-remediation Skill.");
    }

    if (candidates.Count > 1)
    {
        Console.Error.WriteLine("HUMAN_DECISION_REQUIRED: multiple Goal Context candidates were found; select one with --goal-context.");
        foreach (var candidate in candidates)
        {
            Console.Error.WriteLine($"- {Relative(repositoryRoot, candidate)}");
        }
        return 2;
    }

    var selected = candidates[0];
    var content = Normalize(File.ReadAllText(selected));
    if (string.IsNullOrWhiteSpace(content))
    {
        throw new InvalidDataException("Selected Goal Context is empty.");
    }
    if (content.IndexOf('\0') >= 0)
    {
        throw new InvalidDataException("Selected Goal Context contains NUL characters and is not readable text.");
    }

    var outputPath = ResolveContainedPath(repositoryRoot, options.OutputPath, requireExists: false);
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
    var artifact = new SelectionArtifact(
        SchemaVersion: 3,
        SelectionStatus: "SELECTED",
        SelectedPath: Relative(repositoryRoot, selected),
        SelectionMode: options.GoalContextPath is null ? "auto-unique" : "user-specified",
        Validation: "PASS",
        ValidationContract: "readable-free-form",
        ContentSha256: Sha256(content));
    File.WriteAllText(outputPath, JsonSerializer.Serialize(artifact, new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    }) + "\n");
    Console.WriteLine($"Goal Context selection: SELECTED ({artifact.SelectionMode})");
    Console.WriteLine($"Goal Context: {artifact.SelectedPath}");
    Console.WriteLine("Validation: readable non-empty free-form text");
    Console.WriteLine($"Content SHA-256: {artifact.ContentSha256}");
    Console.WriteLine($"Artifact: {Relative(repositoryRoot, outputPath)}");
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"BLOCKED: {ex.Message}");
    return 1;
}

static int Stop(string status, string message)
{
    Console.Error.WriteLine($"HUMAN_DECISION_REQUIRED: {status}: {message}");
    return 2;
}

static List<string> ResolveCandidates(string repositoryRoot, Options options)
{
    if (options.GoalContextPath is not null)
    {
        var exact = ResolveContainedPath(repositoryRoot, options.GoalContextPath, requireExists: true);
        if (!File.Exists(exact))
        {
            throw new FileNotFoundException("Selected Goal Context does not exist or is not a file.", exact);
        }
        return [exact];
    }

    var defaultRoot = Directory.Exists(Path.Combine(repositoryRoot, "docs")) ? "docs" : ".";
    var searchRoot = ResolveContainedPath(repositoryRoot, options.SearchRoot ?? defaultRoot, requireExists: true);
    if (!Directory.Exists(searchRoot))
    {
        throw new DirectoryNotFoundException($"Goal Context search root does not exist: {searchRoot}");
    }

    var candidates = new HashSet<string>(GetPathComparer());
    var visitedDirectories = new HashSet<string>(GetPathComparer());
    var pending = new Stack<string>();
    pending.Push(searchRoot);
    while (pending.Count > 0)
    {
        var directory = pending.Pop();
        if (!visitedDirectories.Add(directory)) continue;
        foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
        {
            var lexicalRelative = Relative(repositoryRoot, entry);
            if (HasExcludedSegment(lexicalRelative)) continue;
            var resolved = ResolveContainedPath(repositoryRoot, entry, requireExists: true);
            if (Directory.Exists(resolved))
            {
                pending.Push(resolved);
            }
            else if (File.Exists(resolved)
                && Path.GetFileName(resolved).StartsWith("goal-context-", StringComparison.OrdinalIgnoreCase)
                && Path.GetExtension(resolved).Equals(".md", StringComparison.OrdinalIgnoreCase))
            {
                candidates.Add(resolved);
            }
        }
    }

    return candidates.OrderBy(path => path, GetPathComparer()).ToList();
}

static bool HasExcludedSegment(string relativePath)
{
    var excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".git", ".agents", ".apm", "apm_modules", "apm-packages", "bin", "obj", "tests"
    };
    return relativePath.Split('/', '\\').Any(excluded.Contains);
}

static string Normalize(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');

static string Sha256(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

static string ResolveContainedPath(string canonicalRoot, string path, bool requireExists)
{
    var lexical = Path.GetFullPath(Path.IsPathRooted(path) ? path : Path.Combine(canonicalRoot, path));
    var resolved = ResolvePathComponents(lexical, requireExists);
    if (!IsContained(canonicalRoot, resolved))
    {
        throw new InvalidOperationException($"Path must remain inside the canonical repository root: {path}");
    }
    return resolved;
}

static string ResolveExistingPath(string path) => ResolvePathComponents(path, requireExists: true);

static string ResolvePathComponents(string path, bool requireExists)
{
    var fullPath = Path.GetFullPath(path);
    var root = Path.GetPathRoot(fullPath) ?? throw new InvalidOperationException($"Path has no root: {path}");
    var segments = fullPath[root.Length..].Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
    var current = root;
    for (var index = 0; index < segments.Length; index++)
    {
        var candidate = Path.Combine(current, segments[index]);
        var isDirectory = Directory.Exists(candidate);
        var isFile = File.Exists(candidate);
        if (!isDirectory && !isFile)
        {
            if (requireExists) throw new FileNotFoundException("Path does not exist or contains a broken link.", candidate);
            current = Path.Combine(current, Path.Combine(segments[index..]));
            break;
        }

        FileSystemInfo info = isDirectory ? new DirectoryInfo(candidate) : new FileInfo(candidate);
        if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            var target = info.ResolveLinkTarget(returnFinalTarget: true) ?? throw new InvalidOperationException($"Could not resolve link target: {candidate}");
            current = Path.GetFullPath(target.FullName);
        }
        else
        {
            current = Path.GetFullPath(candidate);
        }
    }
    return Path.GetFullPath(current);
}

static bool IsContained(string root, string path)
{
    var relative = Path.GetRelativePath(root, path);
    return relative != ".." && !relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) && !Path.IsPathRooted(relative);
}

static string Relative(string root, string path) => Path.GetRelativePath(root, path).Replace('\\', '/');

static StringComparer GetPathComparer() => OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/select-goal-context.cs -- --repository-root <path> [--goal-context <path> | --search-root <path>] --out <path>

Rules:
  --goal-context selects one exact repository-contained readable text file. Its filename, headings, frontmatter, lifecycle, and creation source are unrestricted.
  --search-root is only a convenience discovery convention for goal-context-*.md and fails when zero or multiple candidates exist.
  Existing symlink and junction targets must remain inside the canonical repository root.
  Selection validates only that the chosen file is readable, non-empty text and records its normalized SHA-256 identity.
  --validator and --allow-draft are accepted as ignored compatibility options; they never impose structure or lifecycle rules.
""");
}

sealed record SelectionArtifact(
    int SchemaVersion,
    string SelectionStatus,
    string SelectedPath,
    string SelectionMode,
    string Validation,
    string ValidationContract,
    string ContentSha256);

sealed record Options(
    string RepositoryRoot,
    string? GoalContextPath,
    string? SearchRoot,
    string OutputPath,
    bool ShowHelp,
    bool Valid)
{
    public static Options Parse(string[] args)
    {
        var repositoryRoot = ".";
        string? goalContext = null;
        string? searchRoot = null;
        string? output = null;
        var help = false;
        var valid = true;
        for (var index = 0; index < args.Length; index++)
        {
            string? Next()
            {
                if (++index >= args.Length) { valid = false; return null; }
                return args[index];
            }
            switch (args[index])
            {
                case "--repository-root": repositoryRoot = Next() ?? repositoryRoot; break;
                case "--goal-context": goalContext = Next(); break;
                case "--search-root": searchRoot = Next(); break;
                case "--out": output = Next(); break;
                case "--validator": _ = Next(); break;
                case "--allow-draft": break;
                case "--help":
                case "-h": help = true; break;
                default: valid = false; break;
            }
        }
        if (goalContext is not null && searchRoot is not null) valid = false;
        if (string.IsNullOrWhiteSpace(output) && !help) valid = false;
        return new Options(repositoryRoot, goalContext, searchRoot, output ?? "goal-context-selection.json", help, valid);
    }
}
