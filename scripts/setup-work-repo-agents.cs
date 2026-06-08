using System.Diagnostics;
using System.Linq;
using System.Text;

return await RepoAgentSetup.RunAsync(args);

internal static class RepoAgentSetup
{
    private const string VerbosePrefix = "VERBOSE: ";
    private const string SlicePrepFileName = "slice-prep.toml";
    private const string SliceImplFileName = "slice-impl.toml";
    private const string FrontmatterPhrase = "top-level frontmatter";
    private const string FrontmatterReplacement = "top-level TOML fields";

    private static readonly string[] SlicePrepOrder =
    [
        "model",
        "model_reasoning_effort",
        "sandbox_mode"
    ];

    private static readonly string[] SliceImplOrder = SlicePrepOrder;

    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);
    private const string OutputNewLine = "\r\n";

    private static readonly string[] ApmTargets =
    [
        "copilot,codex,agent-skills"
    ];

    private static readonly string[] ApmPackages =
    [
        "suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-guardrail-kernel-flow",
        "suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer"
    ];

    private static readonly IReadOnlyDictionary<string, string> SlicePrepDefaults = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["model"] = "gpt-5.4",
        ["model_reasoning_effort"] = "medium",
        ["sandbox_mode"] = "read-only"
    };

    private static readonly IReadOnlyDictionary<string, string> SliceImplDefaults = new Dictionary<string, string>(StringComparer.Ordinal)
    {
        ["model"] = "gpt-5.4",
        ["model_reasoning_effort"] = "medium",
        ["sandbox_mode"] = "workspace-write"
    };

    private sealed record Options(
        string TargetRoot,
        bool Force,
        bool DryRun,
        bool Check,
        bool Verbose);

    private sealed record KeyIssue(
        string Key,
        bool Exists,
        bool HasTopLevel,
        bool InCorrectPosition,
        bool HasDuplicate,
        string? CurrentValue,
        string ExpectedValue,
        bool NeedsRewrite,
        string Decision
    );

    private sealed record FileReport(
        string FilePath,
        bool Exists,
        bool Changed,
        bool ShouldFailCheck,
        bool Applied,
        List<KeyIssue> KeyIssues,
        string? FrontmatterFixLine
    );

    public static async Task<int> RunAsync(string[] args)
    {
        Options options;
        try
        {
            options = ParseArgs(args);
        }
        catch (ArgumentException ex)
        {
            if (string.Equals(ex.Message, "help", StringComparison.Ordinal))
            {
                PrintUsage();
                return 0;
            }

            Console.Error.WriteLine(ex.Message);
            PrintUsage();
            return 1;
        }

        if (!Directory.Exists(options.TargetRoot))
        {
            Console.Error.WriteLine($"Target root not found: {options.TargetRoot}");
            return 1;
        }

        if (options.DryRun || options.Check)
        {
            Console.WriteLine(options.DryRun
                ? "Dry-run mode: no command execution and no file writes."
                : "Check mode: no command execution and no file writes.");
        }
        else if (!await RunApmAsync(options.TargetRoot, options.Verbose))
        {
            return 1;
        }

        var noWrite = options.DryRun || options.Check;
        var reports = new List<FileReport>
        {
            await ProcessTomlFileAsync(
                options.TargetRoot,
                SlicePrepFileName,
                SlicePrepOrder,
                SlicePrepDefaults,
                options.Force,
                options.Verbose,
                noWrite),
            await ProcessTomlFileAsync(
                options.TargetRoot,
                SliceImplFileName,
                SliceImplOrder,
                SliceImplDefaults,
                options.Force,
                options.Verbose,
                noWrite)
        };

        var hasFailure = false;
        var hasChanges = false;
        foreach (var report in reports)
        {
            PrintFileReport(report);
            hasChanges |= report.Changed;
            hasFailure |= report.ShouldFailCheck;
        }

        Console.WriteLine();
        if (options.Check)
        {
            Console.WriteLine(hasFailure ? "Validation result: FAILED" : "Validation result: OK");
            if (hasFailure)
            {
                return 2;
            }

            return 0;
        }

        if (options.DryRun)
        {
            Console.WriteLine(hasChanges
                ? "Dry-run result: planned updates found above."
                : "Dry-run result: no changes are needed.");
            return 0;
        }

        if (hasFailure)
        {
            Console.WriteLine("Validation result: FAILED");
            return 1;
        }

        Console.WriteLine(hasChanges
            ? "TOML updates applied."
            : "TOML files were already compliant.");
        return 0;
    }

    private static Options ParseArgs(string[] args)
    {
        string? targetRoot = null;
        var force = false;
        var dryRun = false;
        var check = false;
        var verbose = false;

        foreach (var arg in args)
        {
            switch (arg)
            {
                case "--force":
                    force = true;
                    break;
                case "--dry-run":
                    dryRun = true;
                    break;
                case "--check":
                case "--check-only":
                    check = true;
                    break;
                case "--verbose":
                    verbose = true;
                    break;
                case "--help":
                case "-h":
                    throw new ArgumentException("help");
                default:
                    if (arg.StartsWith("-", StringComparison.Ordinal))
                    {
                        throw new ArgumentException($"Unknown option: {arg}");
                    }

                    if (targetRoot is not null)
                    {
                        throw new ArgumentException($"Unexpected argument: {arg}");
                    }

                    targetRoot = Path.GetFullPath(arg);
                    break;
            }
        }

        if (targetRoot is null)
        {
            throw new ArgumentException("targetRoot is required.");
        }

        if (dryRun && check)
        {
            throw new ArgumentException("--dry-run and --check cannot be used together.");
        }

        return new Options(targetRoot, force, dryRun, check, verbose);
    }

    private static async Task<bool> RunApmAsync(string workingDirectory, bool verbose)
    {
        var apmArgs = new List<string>
        {
            "install",
            "--update",
            "--target",
            ApmTargets[0],
            ApmPackages[0],
            ApmPackages[1]
        };

        if (verbose)
        {
            Console.WriteLine(VerbosePrefix + $"Running apm in {workingDirectory}");
            Console.WriteLine(VerbosePrefix + $"command: apm {string.Join(" ", apmArgs)}");
        }
        else
        {
            Console.WriteLine("Running apm install command.");
        }

        try
        {
            var startInfo = new ProcessStartInfo("apm")
            {
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };

            foreach (var arg in apmArgs)
            {
                startInfo.ArgumentList.Add(arg);
            }

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                Console.Error.WriteLine("Failed to start apm command.");
                return false;
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync();

            var stdout = await stdoutTask;
            var stderr = await stderrTask;

            if (!string.IsNullOrWhiteSpace(stderr))
            {
                Console.Error.WriteLine(stderr.TrimEnd());
            }

            if (process.ExitCode != 0)
            {
                if (!string.IsNullOrWhiteSpace(stdout))
                {
                    Console.Error.WriteLine(stdout.TrimEnd());
                }

                return false;
            }

            if (verbose && !string.IsNullOrWhiteSpace(stdout))
            {
                Console.WriteLine(stdout.TrimEnd());
            }

            return true;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            Console.Error.WriteLine("apm command not found. Ensure apm is installed and on PATH.");
            return false;
        }
    }

    private static async Task<FileReport> ProcessTomlFileAsync(
        string targetRoot,
        string fileName,
        IReadOnlyList<string> keyOrder,
        IReadOnlyDictionary<string, string> defaults,
        bool force,
        bool verbose,
        bool noWrite)
    {
        var filePath = Path.Combine(targetRoot, ".codex", "agents", fileName);
        if (!File.Exists(filePath))
        {
            return new FileReport(
                filePath,
                false,
                true,
                true,
                false,
                keyOrder.Select(key => new KeyIssue(key, false, false, false, false, null, Quote(defaults[key]), true, "missing")).ToList(),
                null);
        }

        var rawText = await ReadTomlTextAsync(filePath);
        var normalizedText = NormalizeNewlinesToLf(rawText);
        var lines = normalizedText.Split('\n');
        var firstSectionIndex = FindFirstSectionIndex(lines);
        var devInstructionsIndex = FindTopLevelKeyIndex(lines, "developer_instructions", firstSectionIndex);
        var insertAt = ResolveInsertIndex(lines, firstSectionIndex, devInstructionsIndex);
        var nameDescriptionAfterIndex = FindNameDescriptionAfter(lines, firstSectionIndex);
        if (insertAt < 0)
        {
            insertAt = nameDescriptionAfterIndex >= 0 ? nameDescriptionAfterIndex + 1 : 0;
        }

        if (verbose)
        {
            var target = devInstructionsIndex >= 0 ? $"before developer_instructions at line {devInstructionsIndex + 1}"
                : firstSectionIndex >= 0 ? $"before first section at line {firstSectionIndex + 1}"
                : nameDescriptionAfterIndex >= 0 ? $"after name/description at line {nameDescriptionAfterIndex + 1}"
                : "at start of file";
            Console.WriteLine(VerbosePrefix + $"{fileName}: {target}");
        }

        var issues = new List<KeyIssue>();
        var occurrences = CollectKeyOccurrences(lines, firstSectionIndex);
        var needsUpdate = false;
        var needsFailure = false;

        foreach (var key in keyOrder)
        {
            var hasTop = occurrences.TopLevel.ContainsKey(key);
            var hasAny = occurrences.All.ContainsKey(key);
            var topIndexes = hasTop ? occurrences.TopLevel[key] : new List<int>();
            var allIndexes = hasAny ? occurrences.All[key] : new List<int>();
            var hasDuplicate = allIndexes.Count > 1;

            var topPosition = hasTop ? topIndexes[0] : -1;
            var currentValue = hasAny ? ExtractValue(lines[allIndexes[0]]) : null;
            var expectedValue = Quote(defaults[key]);
            var shouldUpdate = false;
            var decision = string.Empty;
            var inCorrectPos = !hasTop
                ? false
                : devInstructionsIndex >= 0
                    ? topPosition < devInstructionsIndex
                    : firstSectionIndex < 0 || topPosition < firstSectionIndex;

            if (!hasTop)
            {
                shouldUpdate = true;
                decision = "add";
            }
            else if (force && currentValue is not null && !string.Equals(currentValue, expectedValue, StringComparison.Ordinal))
            {
                shouldUpdate = true;
                decision = "overwrite";
            }
            else if (hasDuplicate || !inCorrectPos || (firstSectionIndex >= 0 && topPosition >= firstSectionIndex))
            {
                shouldUpdate = true;
                decision = "relocate";
            }
            else
            {
                decision = "keep";
            }

            if (!hasTop || hasDuplicate || !inCorrectPos || decision is "overwrite")
            {
                needsUpdate = true;
            }

            if (!hasTop || hasDuplicate || !inCorrectPos)
            {
                needsFailure = true;
            }

            if (verbose)
            {
                if (hasTop)
                {
                    var loc = firstSectionIndex >= 0 && topPosition >= firstSectionIndex ? "in section" : inCorrectPos ? "top-level" : "misplaced";
                    Console.WriteLine(VerbosePrefix + $"{fileName}:{key} = {currentValue ?? "<none>"} [{loc}]");
                }
                else
                {
                    Console.WriteLine(VerbosePrefix + $"{fileName}:{key} is missing top-level");
                }
            }

            issues.Add(new KeyIssue(
                key,
                hasAny,
                hasTop,
                inCorrectPos,
                hasDuplicate,
                currentValue,
                expectedValue,
                shouldUpdate,
                decision));
        }

        if (issues.All(x => x.HasTopLevel))
        {
            var ordered = keyOrder
                .Where(key => occurrences.TopLevel.ContainsKey(key))
                .Select(key => occurrences.TopLevel[key][0])
                .ToList();
            for (var i = 1; i < ordered.Count; i++)
            {
                if (ordered[i - 1] >= ordered[i])
                {
                    needsUpdate = true;
                    needsFailure = true;
                }
            }
        }

        var fixedText = normalizedText.Replace(FrontmatterPhrase, FrontmatterReplacement);
        if (!string.Equals(fixedText, normalizedText, StringComparison.Ordinal))
        {
            needsUpdate = true;
            needsFailure = true;
        }

        var frontmatterFixLine = normalizedText.Contains(FrontmatterPhrase, StringComparison.Ordinal)
            ? "frontmatter"
            : null;

        if (noWrite || !needsUpdate)
        {
            return new FileReport(filePath, true, needsUpdate, needsFailure, false, issues, frontmatterFixLine);
        }

        var linesToWrite = new List<string>(lines);
        for (var i = 0; i < linesToWrite.Count; i++)
        {
            if (linesToWrite[i].Contains(FrontmatterPhrase, StringComparison.Ordinal))
            {
                linesToWrite[i] = linesToWrite[i].Replace(FrontmatterPhrase, FrontmatterReplacement);
            }
        }

        var toRemove = new List<int>();
        foreach (var key in keyOrder)
        {
            if (!occurrences.All.TryGetValue(key, out var keyIndexes))
            {
                continue;
            }

            toRemove.AddRange(keyIndexes);
        }

        var uniqueRemove = toRemove.Distinct().OrderByDescending(i => i).ToList();
        foreach (var index in uniqueRemove)
        {
            if (index >= 0 && index < linesToWrite.Count)
            {
                linesToWrite.RemoveAt(index);
                if (index < insertAt)
                {
                    insertAt--;
                }
            }
        }

        var refreshedFirstSectionIndex = FindFirstSectionIndex(linesToWrite);
        var refreshedDeveloperInstructionsIndex = FindTopLevelKeyIndex(linesToWrite, "developer_instructions", refreshedFirstSectionIndex);
        insertAt = AdjustInsertIndexAfterCleanup(linesToWrite, insertAt, refreshedFirstSectionIndex, refreshedDeveloperInstructionsIndex);
        var missingOrUpdatedLines = keyOrder
            .Select(key =>
            {
                var issue = issues.First(i => i.Key == key);
                var expected = defaults[key];
                var selectedValue = issue.CurrentValue is null || (force && issue.CurrentValue is not null && !string.Equals(issue.CurrentValue, Quote(expected), StringComparison.Ordinal))
                    ? Quote(expected)
                    : issue.CurrentValue!;
                return $"{key} = {selectedValue}";
            })
            .ToList();

        linesToWrite.InsertRange(insertAt, missingOrUpdatedLines);
        var finalText = string.Join(OutputNewLine, linesToWrite);
        finalText = EnsureNoUtf8Bom(finalText);
        await File.WriteAllTextAsync(filePath, finalText, Utf8NoBom);

        return new FileReport(
            filePath,
            true,
            true,
            false,
            true,
            issues,
            frontmatterFixLine);
    }

    private static int FindFirstSectionIndex(IReadOnlyList<string> lines)
    {
        for (var i = 0; i < lines.Count; i++)
        {
            var trimmed = lines[i].Trim();
            if (trimmed.StartsWith("[", StringComparison.Ordinal) && trimmed.EndsWith("]", StringComparison.Ordinal))
            {
                return i;
            }
        }

        return -1;
    }

    private static int FindTopLevelKeyIndex(IReadOnlyList<string> lines, string key, int firstSectionIndex)
    {
        var limit = firstSectionIndex >= 0 ? firstSectionIndex : lines.Count;
        for (var i = 0; i < limit; i++)
        {
            if (TryParseTopLevelKey(lines[i], out var parsedKey) && parsedKey == key)
            {
                return i;
            }
        }

        return -1;
    }

    private static int FindNameDescriptionAfter(IReadOnlyList<string> lines, int firstSectionIndex)
    {
        var limit = firstSectionIndex >= 0 ? firstSectionIndex : lines.Count;
        var nameIndex = -1;
        var descriptionIndex = -1;
        for (var i = 0; i < limit; i++)
        {
            if (!TryParseTopLevelKey(lines[i], out var key))
            {
                continue;
            }

            if (key == "name")
            {
                nameIndex = i;
            }
            else if (key == "description")
            {
                descriptionIndex = i;
            }
        }

        return Math.Max(nameIndex, descriptionIndex);
    }

    private static int ResolveInsertIndex(IReadOnlyList<string> lines, int firstSectionIndex, int developerIndex)
    {
        if (developerIndex >= 0)
        {
            return developerIndex;
        }

        var nameDescriptionIndex = FindNameDescriptionAfter(lines, firstSectionIndex);
        if (nameDescriptionIndex >= 0)
        {
            return nameDescriptionIndex + 1;
        }

        if (firstSectionIndex >= 0)
        {
            return firstSectionIndex;
        }

        return 0;
    }

    private static int AdjustInsertIndexAfterCleanup(
        IReadOnlyList<string> lines,
        int insertAt,
        int firstSectionIndex,
        int developerIndex)
    {
        var fallback = ResolveInsertIndex(lines, firstSectionIndex, developerIndex);
        if (insertAt < 0)
        {
            return fallback;
        }

        if (fallback >= 0)
        {
            return Math.Min(insertAt, Math.Max(0, Math.Min(fallback, lines.Count)));
        }

        return Math.Max(0, Math.Min(insertAt, lines.Count));
    }

    private static (Dictionary<string, List<int>> TopLevel, Dictionary<string, List<int>> All) CollectKeyOccurrences(
        IReadOnlyList<string> lines,
        int firstSectionIndex)
    {
        var all = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        var topLevel = new Dictionary<string, List<int>>(StringComparer.Ordinal);
        for (var i = 0; i < lines.Count; i++)
        {
            if (!TryParseTopLevelKey(lines[i], out var key))
            {
                continue;
            }

            if (!all.TryGetValue(key, out var allIndexes))
            {
                allIndexes = new List<int>();
                all[key] = allIndexes;
            }

            allIndexes.Add(i);

            var inTopLevel = firstSectionIndex < 0 || i < firstSectionIndex;
            if (inTopLevel)
            {
                if (!topLevel.TryGetValue(key, out var topIndexes))
                {
                    topIndexes = new List<int>();
                    topLevel[key] = topIndexes;
                }

                topIndexes.Add(i);
            }
        }

        return (topLevel, all);
    }

    private static bool TryParseTopLevelKey(string line, out string key)
    {
        key = string.Empty;
        var noComment = RemoveTrailingComment(line).Trim();
        if (noComment.Length == 0 || noComment.StartsWith("#", StringComparison.Ordinal))
        {
            return false;
        }

        if (noComment.StartsWith("[", StringComparison.Ordinal) && noComment.EndsWith("]", StringComparison.Ordinal))
        {
            return false;
        }

        var equals = noComment.IndexOf('=');
        if (equals <= 0)
        {
            return false;
        }

        key = noComment[..equals].Trim();
        return key.Length > 0;
    }

    private static string ExtractValue(string line)
    {
        var trimmed = RemoveTrailingComment(line).Trim();
        var equals = trimmed.IndexOf('=');
        if (equals < 0)
        {
            return trimmed;
        }

        return trimmed[(equals + 1)..].Trim();
    }

    private static string RemoveTrailingComment(string line)
    {
        var commentIndex = line.IndexOf('#');
        if (commentIndex < 0)
        {
            return line;
        }

        return line[..commentIndex];
    }

    private static string NormalizeNewlinesToLf(string text)
    {
        return text.Replace("\r\r\n", "\n").Replace("\r\n", "\n").Replace("\r", "\n");
    }

    private static async Task<string> ReadTomlTextAsync(string filePath)
    {
        await using var stream = File.OpenRead(filePath);
        using var reader = new StreamReader(stream, new UTF8Encoding(false), true);
        var text = await reader.ReadToEndAsync();
        return EnsureNoUtf8Bom(text);
    }

    private static string EnsureNoUtf8Bom(string text)
    {
        return text.StartsWith('\uFEFF') ? text[1..] : text;
    }

    private static string Quote(string value) => $"\"{value}\"";

    private static void PrintFileReport(FileReport report)
    {
        if (!report.Exists)
        {
            Console.WriteLine($"[MISSING] {report.FilePath}");
            Console.WriteLine("  - check: missing file");
            return;
        }

        var status = report.Applied
            ? "updated"
            : report.Changed
                ? "would-update"
                : "ok";

        Console.WriteLine($"[{status}] {report.FilePath}");
        foreach (var issue in report.KeyIssues)
        {
            var tag = issue.Decision switch
            {
                "overwrite" => "overwrite" ,
                "add" => "add",
                "relocate" => "relocate",
                _ => "keep"
            };
            Console.WriteLine($"  - {issue.Key}: {issue.CurrentValue ?? "<none>"} -> {issue.ExpectedValue} ({tag})");
        }

        if (report.FrontmatterFixLine is not null)
        {
            Console.WriteLine("  - developer_instructions wording: top-level frontmatter -> top-level TOML fields");
        }
    }

    private static void PrintUsage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("dotnet run --file scripts/setup-work-repo-agents.cs -- <targetRoot> [--force] [--dry-run] [--check] [--verbose]");
        Console.WriteLine("Options:");
        Console.WriteLine("  --force       overwrite existing runtime setting values");
        Console.WriteLine("  --dry-run     show planned changes only");
        Console.WriteLine("  --check       validate required keys and layout without changes (exit code 2 on failure)");
        Console.WriteLine("  --verbose     show parsed positions and planned changes");
    }
}
