#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Text.RegularExpressions;

const string PackageName = "pr-review-remediation";
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
    var packageRoot = ResolvePackageRoot(GetSourceFilePath());
    var targetRoot = Path.GetFullPath(options.TargetRoot);
    var sourceAgentRoot = Path.Combine(packageRoot, "codex-agents");
    var targetAgentRoot = Path.Combine(targetRoot, ".codex", "agents");
    var operations = new List<string>();
    var conflicts = new List<string>();
    var adaptiveProblems = new List<string>();

    if (!Directory.Exists(targetRoot))
    {
        throw new DirectoryNotFoundException($"Target repository does not exist: {targetRoot}");
    }

    foreach (var fileName in new[] { "local-reviewer.toml", "purpose-reviewer.toml", "review-planner.toml" })
    {
        ProcessAgent(
            Path.Combine(sourceAgentRoot, fileName),
            Path.Combine(targetAgentRoot, fileName),
            targetRoot,
            options,
            operations,
            conflicts);
    }

    if (options.Check)
    {
        adaptiveProblems.AddRange(ValidateAdaptiveInstallation(targetRoot));
        foreach (var problem in adaptiveProblems)
        {
            conflicts.Add(problem);
        }
    }

    foreach (var operation in operations)
    {
        Console.WriteLine(operation);
    }

    if (conflicts.Count > 0)
    {
        Console.Error.WriteLine("PR Review Remediation profile validation failed:");
        foreach (var conflict in conflicts)
        {
            Console.Error.WriteLine($"- {conflict}");
        }

        if (adaptiveProblems.Count > 0)
        {
            Console.Error.WriteLine("Run the existing Adaptive helper because Adaptive assets or profiles are missing or invalid:");
            Console.Error.WriteLine("dotnet run --file apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs -- .");
        }
        return 1;
    }

    Console.WriteLine(options.Check
        ? "PR Review Remediation profile check: PASS"
        : options.DryRun
            ? "PR Review Remediation profile dry-run: PASS"
            : options.Remove
                ? "PR Review Remediation profile removal: PASS"
                : "PR Review Remediation profile synchronization: PASS");
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Error: {ex.Message}");
    return 1;
}

static void ProcessAgent(
    string sourcePath,
    string targetPath,
    string targetRoot,
    Options options,
    List<string> operations,
    List<string> conflicts)
{
    if (!File.Exists(sourcePath))
    {
        throw new FileNotFoundException("Canonical review profile was not found.", sourcePath);
    }

    var display = Path.GetRelativePath(targetRoot, targetPath).Replace('\\', '/');
    var source = Normalize(File.ReadAllText(sourcePath));
    ValidateCanonicalProfile(sourcePath, source);

    if (options.Remove)
    {
        if (!File.Exists(targetPath))
        {
            operations.Add($"[unchanged] {display}: absent");
            return;
        }

        var target = Normalize(File.ReadAllText(targetPath));
        if (!string.Equals(source, target, StringComparison.Ordinal)
            && !IsCompletedApmProfile(target, source)
            && !options.Force)
        {
            conflicts.Add($"{display} differs from the canonical review profile and will not be removed without --force.");
            return;
        }

        if (options.DryRun)
        {
            operations.Add($"[dry-run] {display}: remove");
            return;
        }

        File.Delete(targetPath);
        operations.Add($"[removed] {display}");
        return;
    }

    if (!File.Exists(targetPath))
    {
        if (options.Check)
        {
            conflicts.Add($"{display} is missing.");
            return;
        }

        if (options.DryRun)
        {
            operations.Add($"[dry-run] {display}: add");
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(targetPath)!);
        File.WriteAllText(targetPath, source);
        operations.Add($"[added] {display}");
        return;
    }

    var current = Normalize(File.ReadAllText(targetPath));
    if (string.Equals(source, current, StringComparison.Ordinal)
        || IsCompletedApmProfile(current, source))
    {
        operations.Add($"[unchanged] {display}");
        return;
    }

    var isApmGeneratedStub = IsApmGeneratedStub(current, source);
    if (!options.Force && !isApmGeneratedStub)
    {
        conflicts.Add($"{display} differs from the canonical review profile; use --force to overwrite.");
        return;
    }

    if (options.Check)
    {
        conflicts.Add($"{display} does not match the canonical review profile.");
        return;
    }

    if (options.DryRun)
    {
        operations.Add($"[dry-run] {display}: update");
        return;
    }

    File.WriteAllText(targetPath, isApmGeneratedStub ? CompleteApmGeneratedStub(current, source) : source);
    operations.Add($"[updated] {display}");
}

static void ValidateCanonicalProfile(string path, string content)
{
    foreach (var required in new[]
    {
        ("model", "gpt-5.6-terra"),
        ("model_reasoning_effort", "high"),
        ("sandbox_mode", "read-only")
    })
    {
        var actual = GetTomlString(content, required.Item1);
        if (!string.Equals(actual, required.Item2, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{path} {required.Item1} must be {required.Item2}, got {actual}.");
        }
    }
}

static List<string> ValidateAdaptiveInstallation(string targetRoot)
{
    var problems = new List<string>();
    var requiredFiles = new[]
    {
        Path.Combine(targetRoot, ".agents", "skills", "adaptive-implementation-execution", "SKILL.md"),
        Path.Combine(targetRoot, ".codex", "agents", "high-implementation-starter.toml"),
        Path.Combine(targetRoot, ".codex", "agents", "standard-implementation-completer.toml")
    };

    foreach (var path in requiredFiles)
    {
        if (!File.Exists(path))
        {
            problems.Add($"Adaptive dependency is missing: {Path.GetRelativePath(targetRoot, path).Replace('\\', '/')}");
        }
    }

    foreach (var fileName in new[]
    {
        "high-implementation-starter.agent.md",
        "standard-implementation-completer.agent.md"
    })
    {
        var repositoryAgent = Path.Combine(targetRoot, ".github", "agents", fileName);
        if (!File.Exists(repositoryAgent) && !HasApmCanonicalAgent(targetRoot, fileName))
        {
            problems.Add($"Adaptive canonical agent is missing: .github/agents/{fileName} or apm_modules/**/.apm/agents/{fileName}");
        }
    }

    foreach (var fileName in new[] { "high-implementation-starter.toml", "standard-implementation-completer.toml" })
    {
        var path = Path.Combine(targetRoot, ".codex", "agents", fileName);
        if (!File.Exists(path))
        {
            continue;
        }

        var content = File.ReadAllText(path);
        if (string.IsNullOrWhiteSpace(GetTomlString(content, "model")))
        {
            problems.Add($"Adaptive profile has no concrete model: .codex/agents/{fileName}");
        }

        if (!string.Equals(GetTomlString(content, "sandbox_mode"), "workspace-write", StringComparison.Ordinal))
        {
            problems.Add($"Adaptive profile sandbox_mode must be workspace-write: .codex/agents/{fileName}");
        }
    }

    return problems;
}

static bool IsApmGeneratedStub(string content, string source)
{
    if (!string.Equals(GetTomlString(content, "name"), GetTomlString(source, "name"), StringComparison.Ordinal)
        || !string.Equals(GetTomlString(content, "description"), GetTomlString(source, "description"), StringComparison.Ordinal))
    {
        return false;
    }

    if (!string.IsNullOrWhiteSpace(GetTomlString(content, "model"))
        || !string.IsNullOrWhiteSpace(GetTomlString(content, "model_reasoning_effort"))
        || !string.IsNullOrWhiteSpace(GetTomlString(content, "sandbox_mode")))
    {
        return false;
    }

    var keys = Regex.Matches(content, @"(?m)^([A-Za-z_][A-Za-z0-9_]*)\s*=")
        .Select(match => match.Groups[1].Value)
        .ToHashSet(StringComparer.Ordinal);
    return keys.All(key => key is "name" or "description" or "developer_instructions");
}

static bool IsCompletedApmProfile(string content, string source)
{
    foreach (var key in new[] { "name", "description", "model", "model_reasoning_effort", "sandbox_mode" })
    {
        if (!string.Equals(GetTomlString(content, key), GetTomlString(source, key), StringComparison.Ordinal))
        {
            return false;
        }
    }

    var expectedHeading = GetTomlString(source, "name") switch
    {
        "local-reviewer" => "# Local Reviewer\\n",
        "purpose-reviewer" => "# Purpose Reviewer\\n",
        "review-planner" => "# Review Planner\\n",
        _ => string.Empty
    };
    if (expectedHeading.Length == 0
        || !GetTomlString(content, "developer_instructions").StartsWith(expectedHeading, StringComparison.Ordinal))
    {
        return false;
    }

    var keys = Regex.Matches(content, @"(?m)^([A-Za-z_][A-Za-z0-9_]*)\s*=")
        .Select(match => match.Groups[1].Value)
        .ToHashSet(StringComparer.Ordinal);
    return keys.SetEquals(new[]
    {
        "name", "description", "model", "model_reasoning_effort", "sandbox_mode", "developer_instructions"
    });
}

static string CompleteApmGeneratedStub(string stub, string source)
{
    var lines = stub.TrimEnd().Split('\n').ToList();
    var insertionIndex = lines.FindIndex(line => line.StartsWith("developer_instructions", StringComparison.Ordinal));
    if (insertionIndex < 0)
    {
        throw new InvalidOperationException("APM-generated review profile has no developer_instructions field.");
    }

    lines.InsertRange(insertionIndex, new[]
    {
        $"model = \"{GetTomlString(source, "model")}\"",
        $"model_reasoning_effort = \"{GetTomlString(source, "model_reasoning_effort")}\"",
        $"sandbox_mode = \"{GetTomlString(source, "sandbox_mode")}\""
    });
    return string.Join('\n', lines) + "\n";
}

static bool HasApmCanonicalAgent(string targetRoot, string fileName)
{
    var modulesRoot = Path.Combine(targetRoot, "apm_modules");
    if (!Directory.Exists(modulesRoot))
    {
        return false;
    }

    return Directory.EnumerateFiles(modulesRoot, fileName, SearchOption.AllDirectories)
        .Any(path => string.Equals(
            new DirectoryInfo(Path.GetDirectoryName(path)!).Name,
            "agents",
            StringComparison.OrdinalIgnoreCase)
            && string.Equals(
                new DirectoryInfo(Path.GetDirectoryName(Path.GetDirectoryName(path)!)!).Name,
                ".apm",
                StringComparison.OrdinalIgnoreCase));
}

static string GetTomlString(string content, string key)
{
    var match = Regex.Match(content, $"(?m)^{Regex.Escape(key)}\\s*=\\s*\"((?:\\\\.|[^\"\\\\])*)\"\\s*$");
    return match.Success ? match.Groups[1].Value : string.Empty;
}

static string ResolvePackageRoot(string sourceFilePath)
{
    var current = new DirectoryInfo(Path.GetDirectoryName(Path.GetFullPath(sourceFilePath))!);
    while (current is not null)
    {
        var manifest = Path.Combine(current.FullName, "apm.yml");
        if (File.Exists(manifest)
            && File.ReadAllText(manifest).Contains($"name: {PackageName}", StringComparison.Ordinal))
        {
            return current.FullName;
        }

        current = current.Parent;
    }

    throw new DirectoryNotFoundException($"Could not resolve the {PackageName} package root.");
}

static string GetSourceFilePath([System.Runtime.CompilerServices.CallerFilePath] string path = "") => path;

static string Normalize(string text) => text.Replace("\r\n", "\n").TrimEnd() + "\n";

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs -- [target-repository] [--dry-run | --check] [--force] [--remove]

Options:
  --dry-run, -n     Show review profile changes without writing.
  --check           Verify review profiles and required Adaptive assets/profiles without writing.
  --force, -f       Overwrite or remove conflicting review profile files.
  --remove          Remove package-owned review profiles. Adaptive profiles are never removed.
  --help, -h        Show this help.

This helper never reads or writes AGENTS.md or .codex/config.toml.
Use the existing Adaptive helper for Adaptive profile installation and repair.
""");
}

sealed record Options(
    string TargetRoot,
    bool DryRun,
    bool Check,
    bool Force,
    bool Remove,
    bool ShowHelp,
    bool Valid)
{
    public static Options Parse(string[] args)
    {
        var target = ".";
        var targetSet = false;
        var dryRun = false;
        var check = false;
        var force = false;
        var remove = false;
        var help = false;
        var valid = true;

        foreach (var arg in args)
        {
            switch (arg)
            {
                case "--dry-run":
                case "-n":
                    dryRun = true;
                    break;
                case "--check":
                    check = true;
                    break;
                case "--force":
                case "-f":
                    force = true;
                    break;
                case "--remove":
                    remove = true;
                    break;
                case "--help":
                case "-h":
                    help = true;
                    break;
                default:
                    if (arg.StartsWith('-') || targetSet)
                    {
                        valid = false;
                    }
                    else
                    {
                        target = arg;
                        targetSet = true;
                    }
                    break;
            }
        }

        if ((dryRun && check) || (remove && check))
        {
            valid = false;
        }

        return new Options(target, dryRun, check, force, remove, help, valid);
    }
}
