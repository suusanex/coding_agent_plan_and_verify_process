#:property TargetFramework=net10.0

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

const string StartMarker = "<!-- copilot-fallback:start -->";
const string EndMarker = "<!-- copilot-fallback:end -->";

var options = ParseArguments(args);

if (options is null || options.ShowHelp || string.IsNullOrWhiteSpace(options.TargetRepoRoot))
{
    ShowUsage();
    Environment.Exit(options?.HasError == true ? 2 : 0);
}

var targetRepoRoot = Path.GetFullPath(options.TargetRepoRoot);
if (!Directory.Exists(targetRepoRoot))
{
    Console.WriteLine($"Error: target repository was not found: {targetRepoRoot}");
    Environment.Exit(2);
}

var packageRoot = ResolvePackageRoot(options.PackageRoot);
if (packageRoot is null)
{
    Console.WriteLine("Error: copilot fallback package root was not found.");
    Console.WriteLine("Run from this repository, or pass --package-root apm-packages\\copilot-fallback-ai-development-process.");
    Environment.Exit(2);
}

var logs = new List<string>();
var blockers = new List<string>();

if (options.DryRun)
{
    logs.Add("[dry-run] no files will be changed.");
}

try
{
    DetectExistingCustomizations(targetRepoRoot, logs);
    ApplyCopilotInstructions(packageRoot, targetRepoRoot, options, logs, blockers);
    if (options.DryRun || blockers.Count == 0)
    {
        CopyTemplateGroup(packageRoot, targetRepoRoot, options, "templates/github/instructions", ".github/instructions", "*.instructions.md", logs, blockers);
        CopyTemplateGroup(packageRoot, targetRepoRoot, options, "templates/github/agents", ".github/agents", "*.agent.md", logs, blockers);
        CopyTemplateGroup(packageRoot, targetRepoRoot, options, "templates/github/prompts", ".github/prompts", "*.prompt.md", logs, blockers);
        CopySingleTemplate(packageRoot, targetRepoRoot, options, "templates/codex-first-state.md", "templates/codex-first-state.md", logs, blockers);
    }
    else
    {
        logs.Add("stopped before copying template files because a blocker was detected.");
    }
}
catch (Exception ex)
{
    Console.WriteLine($"Error: {ex.Message}");
    if (options.Verbose)
    {
        Console.WriteLine(ex);
    }

    Environment.Exit(2);
}

Console.WriteLine("=== Copilot fallback install report ===");
foreach (var log in logs)
{
    Console.WriteLine(log);
}

if (blockers.Count > 0)
{
    Console.WriteLine();
    Console.WriteLine("=== Blockers ===");
    foreach (var blocker in blockers)
    {
        Console.WriteLine(blocker);
    }

    Console.WriteLine();
    Console.WriteLine("Resolve the blockers manually, or rerun with --force for same-name template overwrites.");
    Environment.Exit(2);
}

Console.WriteLine();
Console.WriteLine(options.DryRun ? "dry-run complete." : "install complete.");
Environment.Exit(0);

static InstallOptions ParseArguments(string[] args)
{
    var options = new InstallOptions();
    for (var i = 0; i < args.Length; i++)
    {
        var arg = args[i];
        switch (arg)
        {
            case "--dry-run":
            case "-n":
                options.DryRun = true;
                continue;
            case "--force":
            case "-f":
                options.Force = true;
                continue;
            case "--verbose":
            case "-v":
                options.Verbose = true;
                continue;
            case "--help":
            case "-h":
                options.ShowHelp = true;
                continue;
            case "--package-root":
            case "-p":
                if (i + 1 >= args.Length)
                {
                    options.HasError = true;
                    options.ShowHelp = true;
                    continue;
                }

                options.PackageRoot = args[++i];
                continue;
        }

        if (arg.StartsWith("-", StringComparison.Ordinal))
        {
            options.HasError = true;
            options.ShowHelp = true;
            continue;
        }

        if (string.IsNullOrWhiteSpace(options.TargetRepoRoot))
        {
            options.TargetRepoRoot = arg;
            continue;
        }

        options.HasError = true;
        options.ShowHelp = true;
    }

    return options;
}

static void ShowUsage()
{
    Console.WriteLine("Usage:");
    Console.WriteLine("  dotnet run --file apm-packages/copilot-fallback-ai-development-process/scripts/install-copilot-fallback-local.cs -- <target-repo-root> [options]");
    Console.WriteLine();
    Console.WriteLine("Options:");
    Console.WriteLine("  --dry-run, -n        show planned changes without writing files");
    Console.WriteLine("  --force, -f          overwrite same-name template files when content differs");
    Console.WriteLine("  --verbose, -v        show detailed error output");
    Console.WriteLine("  --package-root <dir> explicit package root");
    Console.WriteLine("  --help, -h           show this help");
}

static string? ResolvePackageRoot(string? overrideRoot)
{
    if (!string.IsNullOrWhiteSpace(overrideRoot))
    {
        var explicitRoot = Path.GetFullPath(overrideRoot);
        return IsPackageRoot(explicitRoot) ? explicitRoot : null;
    }

    var current = new DirectoryInfo(Path.GetFullPath(Directory.GetCurrentDirectory()));
    while (current is not null)
    {
        var candidate = Path.Combine(current.FullName, "apm-packages", "copilot-fallback-ai-development-process");
        if (IsPackageRoot(candidate))
        {
            return candidate;
        }

        current = current.Parent;
    }

    return null;
}

static bool IsPackageRoot(string dir)
{
    return File.Exists(Path.Combine(dir, "apm.yml"))
        && File.Exists(Path.Combine(dir, "templates", "github", "copilot-instructions.md"));
}

static void DetectExistingCustomizations(string targetRepoRoot, List<string> logs)
{
    var checks = new[]
    {
        "AGENTS.md",
        Path.Combine(".github", "copilot-instructions.md"),
        Path.Combine(".github", "instructions"),
        Path.Combine(".github", "agents"),
        Path.Combine(".github", "prompts")
    };

    foreach (var relative in checks)
    {
        var path = Path.Combine(targetRepoRoot, relative);
        if (File.Exists(path) || Directory.Exists(path))
        {
            logs.Add($"detected existing customization: {ToSlash(relative)}");
        }
    }
}

static void ApplyCopilotInstructions(
    string packageRoot,
    string targetRepoRoot,
    InstallOptions options,
    List<string> logs,
    List<string> blockers)
{
    var sourcePath = Path.Combine(packageRoot, "templates", "github", "copilot-instructions.md");
    var targetPath = Path.Combine(targetRepoRoot, ".github", "copilot-instructions.md");
    var sourceText = File.ReadAllText(sourcePath);

    if (!File.Exists(targetPath))
    {
        WriteOrDryRun(targetPath, sourceText, options.DryRun, logs, ".github/copilot-instructions.md: add");
        return;
    }

    var targetText = File.ReadAllText(targetPath);
    var start = targetText.IndexOf(StartMarker, StringComparison.Ordinal);
    var end = targetText.IndexOf(EndMarker, StringComparison.Ordinal);

    if (start >= 0 && end > start)
    {
        var existingBlock = targetText[start..(end + EndMarker.Length)];
        if (Normalize(existingBlock) == Normalize(sourceText))
        {
            logs.Add(".github/copilot-instructions.md: managed block already up to date");
            return;
        }

        if (!options.Force)
        {
            blockers.Add(".github/copilot-instructions.md: managed block differs; rerun with --force to replace only that block.");
            return;
        }

        var updated = targetText[..start] + sourceText + targetText[(end + EndMarker.Length)..];
        WriteOrDryRun(targetPath, updated, options.DryRun, logs, ".github/copilot-instructions.md: replace managed block");
        return;
    }

    if (targetText.Contains(StartMarker, StringComparison.Ordinal) || targetText.Contains(EndMarker, StringComparison.Ordinal))
    {
        blockers.Add(".github/copilot-instructions.md: marker is incomplete; manual repair is required.");
        return;
    }

    blockers.Add(".github/copilot-instructions.md: existing file has no copilot-fallback marker; manual merge required.");
}

static void CopyTemplateGroup(
    string packageRoot,
    string targetRepoRoot,
    InstallOptions options,
    string sourceRelativeDir,
    string targetRelativeDir,
    string pattern,
    List<string> logs,
    List<string> blockers)
{
    var sourceDir = Path.Combine(packageRoot, sourceRelativeDir);
    foreach (var sourcePath in Directory.GetFiles(sourceDir, pattern).OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
    {
        var targetPath = Path.Combine(targetRepoRoot, targetRelativeDir, Path.GetFileName(sourcePath));
        CopyFileWithConflictPolicy(sourcePath, targetPath, options, ToSlash(Path.Combine(targetRelativeDir, Path.GetFileName(sourcePath))), logs, blockers);
    }
}

static void CopySingleTemplate(
    string packageRoot,
    string targetRepoRoot,
    InstallOptions options,
    string sourceRelative,
    string targetRelative,
    List<string> logs,
    List<string> blockers)
{
    CopyFileWithConflictPolicy(
        Path.Combine(packageRoot, sourceRelative),
        Path.Combine(targetRepoRoot, targetRelative),
        options,
        ToSlash(targetRelative),
        logs,
        blockers);
}

static void CopyFileWithConflictPolicy(
    string sourcePath,
    string targetPath,
    InstallOptions options,
    string displayPath,
    List<string> logs,
    List<string> blockers)
{
    var sourceText = File.ReadAllText(sourcePath);
    if (!File.Exists(targetPath))
    {
        WriteOrDryRun(targetPath, sourceText, options.DryRun, logs, $"{displayPath}: add");
        return;
    }

    var targetText = File.ReadAllText(targetPath);
    if (Normalize(sourceText) == Normalize(targetText))
    {
        logs.Add($"{displayPath}: already up to date");
        return;
    }

    if (!options.Force)
    {
        blockers.Add($"{displayPath}: existing file differs; rerun with --force to overwrite this template.");
        return;
    }

    WriteOrDryRun(targetPath, sourceText, options.DryRun, logs, $"{displayPath}: overwrite");
}

static void WriteOrDryRun(string path, string content, bool dryRun, List<string> logs, string label)
{
    if (dryRun)
    {
        logs.Add($"[dry-run] {label}");
        return;
    }

    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    File.WriteAllText(path, content);
    logs.Add(label);
}

static string Normalize(string text)
{
    return text.Replace("\r\n", "\n").Replace('\r', '\n').Trim();
}

static string ToSlash(string path)
{
    return path.Replace('\\', '/');
}

sealed class InstallOptions
{
    public string? TargetRepoRoot { get; set; }
    public string? PackageRoot { get; set; }
    public bool DryRun { get; set; }
    public bool Force { get; set; }
    public bool Verbose { get; set; }
    public bool ShowHelp { get; set; }
    public bool HasError { get; set; }
}
