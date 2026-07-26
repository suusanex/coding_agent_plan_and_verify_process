#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Diagnostics;
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

    var validatorPath = ResolveValidatorPath(repositoryRoot, options.ValidatorPath);
    var candidates = ResolveCandidates(repositoryRoot, options);
    if (candidates.Count == 0)
    {
        return Stop("NO_GOAL_CONTEXT", "No goal-context-*.md candidate was found. Create or select a valid Goal Context, or explicitly choose the baseline $pr-review-remediation Skill.");
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
    var validationMode = options.AllowDraft ? "draft" : "strict";
    var validation = RunCanonicalValidator(validatorPath, selected, validationMode);
    var validationErrors = validation.Errors.ToList();
    if (!options.AllowDraft && validation.LifecycleStatus == "draft")
    {
        validationErrors.Add("A draft Goal Context requires an exact --goal-context path plus explicit --allow-draft user override.");
    }
    if (options.AllowDraft && validation.LifecycleStatus != "draft")
    {
        validationErrors.Add("--allow-draft is only valid for a draft Goal Context.");
    }
    if (validation.Status != "PASS" || validationErrors.Count > 0)
    {
        Console.Error.WriteLine($"INVALID_GOAL_CONTEXT: {Relative(repositoryRoot, selected)}");
        foreach (var error in validationErrors)
        {
            Console.Error.WriteLine($"- {error}");
        }
        Console.Error.WriteLine("Do not substitute the Issue body for purpose review. Fix the Goal Context or explicitly choose the baseline $pr-review-remediation Skill.");
        return 2;
    }

    var outputPath = ResolveContainedPath(repositoryRoot, options.OutputPath, requireExists: false);
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
    var artifact = new SelectionArtifact(
        SchemaVersion: 2,
        SelectionStatus: "SELECTED",
        SelectedPath: Relative(repositoryRoot, selected),
        SelectionMode: options.GoalContextPath is null ? "auto-unique" : options.AllowDraft ? "user-specified-draft-override" : "user-specified",
        LifecycleStatus: validation.LifecycleStatus,
        SensitiveDataReview: validation.SensitiveReview,
        DraftOverride: validation.LifecycleStatus == "draft",
        Validation: "PASS",
        ValidationContractVersion: validation.ContractVersion,
        ValidationMode: validation.Mode,
        ContentSha256: validation.ContentSha256);
    File.WriteAllText(outputPath, JsonSerializer.Serialize(artifact, new JsonSerializerOptions
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    }) + "\n");
    Console.WriteLine($"Goal Context selection: SELECTED ({artifact.SelectionMode})");
    Console.WriteLine($"Goal Context: {artifact.SelectedPath}");
    Console.WriteLine($"Lifecycle: {artifact.LifecycleStatus}/{artifact.SensitiveDataReview}");
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
            else if (File.Exists(resolved) && Path.GetFileName(resolved).StartsWith("goal-context-", StringComparison.OrdinalIgnoreCase) && Path.GetExtension(resolved).Equals(".md", StringComparison.OrdinalIgnoreCase))
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

static CanonicalValidation RunCanonicalValidator(string validatorPath, string goalContextPath, string mode)
{
    var start = new ProcessStartInfo("dotnet")
    {
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true
    };
    foreach (var argument in new[]
    {
        "run", "--file", validatorPath, "--", "--goal-context", goalContextPath, "--mode", mode, "--format", "json"
    })
    {
        start.ArgumentList.Add(argument);
    }

    using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start the canonical Goal Context validator.");
    var stdout = process.StandardOutput.ReadToEnd();
    var stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();
    CanonicalValidation? validation;
    try
    {
        validation = JsonSerializer.Deserialize<CanonicalValidation>(stdout, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    }
    catch (JsonException ex)
    {
        throw new InvalidOperationException($"Canonical Goal Context validator returned invalid JSON: {ex.Message}");
    }
    if (validation is null)
    {
        throw new InvalidOperationException("Canonical Goal Context validator returned no result.");
    }
    if (process.ExitCode == 1)
    {
        throw new InvalidOperationException($"Canonical Goal Context validator failed operationally: {string.Join("; ", validation.Errors)} {stderr}".Trim());
    }
    if (process.ExitCode is not (0 or 2))
    {
        throw new InvalidOperationException($"Canonical Goal Context validator returned unexpected exit code {process.ExitCode}.");
    }
    return validation;
}

static string ResolveValidatorPath(string repositoryRoot, string? explicitPath)
{
    var candidates = new List<string>();
    if (!string.IsNullOrWhiteSpace(explicitPath)) candidates.Add(explicitPath);
    candidates.Add(Path.Combine(repositoryRoot, ".agents", "skills", "goal-context-authoring", "scripts", "validate-goal-context.cs"));
    candidates.Add(Path.Combine(repositoryRoot, "apm-packages", "goal-context-authoring", ".apm", "skills", "goal-context-authoring", "scripts", "validate-goal-context.cs"));
    foreach (var candidate in candidates)
    {
        var fullPath = Path.GetFullPath(candidate);
        if (File.Exists(fullPath)) return fullPath;
    }
    throw new FileNotFoundException("The canonical Goal Context validator is not installed. Install the goal-context-authoring Skill dependency or pass --validator.");
}

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
  dotnet run --file scripts/select-goal-context.cs -- --repository-root <path> [--goal-context <path> | --search-root <path>] --out <path> [--allow-draft] [--validator <path>]

Rules:
  --goal-context selects one exact repository-contained file.
  --search-root discovers goal-context-*.md and fails when zero or multiple candidates exist.
  --allow-draft requires --goal-context and records an explicit draft override.
  --validator overrides canonical validator discovery for package validation only.
  Existing symlink and junction targets must remain inside the canonical repository root.
  The canonical Goal Context Authoring validator defines naming, structure, provenance, tables, secrets, lifecycle, and human-review validity.
""");
}

sealed record CanonicalValidation(int ContractVersion, string Status, string Mode, string LifecycleStatus, string SensitiveReview, string ContentSha256, IReadOnlyList<string> Errors);

sealed record SelectionArtifact(
    int SchemaVersion,
    string SelectionStatus,
    string SelectedPath,
    string SelectionMode,
    string LifecycleStatus,
    string SensitiveDataReview,
    bool DraftOverride,
    string Validation,
    int ValidationContractVersion,
    string ValidationMode,
    string ContentSha256);

sealed record Options(
    string RepositoryRoot,
    string? GoalContextPath,
    string? SearchRoot,
    string OutputPath,
    string? ValidatorPath,
    bool AllowDraft,
    bool ShowHelp,
    bool Valid)
{
    public static Options Parse(string[] args)
    {
        var repositoryRoot = ".";
        string? goalContext = null;
        string? searchRoot = null;
        string? output = null;
        string? validator = null;
        var allowDraft = false;
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
                case "--validator": validator = Next(); break;
                case "--allow-draft": allowDraft = true; break;
                case "--help":
                case "-h": help = true; break;
                default: valid = false; break;
            }
        }
        if (goalContext is not null && searchRoot is not null) valid = false;
        if (allowDraft && goalContext is null) valid = false;
        if (string.IsNullOrWhiteSpace(output) && !help) valid = false;
        return new Options(repositoryRoot, goalContext, searchRoot, output ?? "goal-context-selection.json", validator, allowDraft, help, valid);
    }
}
