#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Text.Json;
using System.Text.RegularExpressions;

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
    var repositoryRoot = Path.GetFullPath(options.RepositoryRoot);
    if (!Directory.Exists(repositoryRoot))
    {
        throw new DirectoryNotFoundException($"Repository root does not exist: {repositoryRoot}");
    }

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
    var validation = ValidateGoalContext(selected, options.AllowDraft);
    if (validation.Errors.Count > 0)
    {
        Console.Error.WriteLine($"INVALID_GOAL_CONTEXT: {Relative(repositoryRoot, selected)}");
        foreach (var error in validation.Errors)
        {
            Console.Error.WriteLine($"- {error}");
        }
        Console.Error.WriteLine("Do not substitute the Issue body for purpose review. Fix the Goal Context or explicitly choose the baseline $pr-review-remediation Skill.");
        return 2;
    }

    var outputPath = ResolveContainedPath(repositoryRoot, options.OutputPath);
    Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
    var artifact = new SelectionArtifact(
        SchemaVersion: 1,
        SelectionStatus: "SELECTED",
        SelectedPath: Relative(repositoryRoot, selected),
        SelectionMode: options.GoalContextPath is null ? "auto-unique" : options.AllowDraft ? "user-specified-draft-override" : "user-specified",
        LifecycleStatus: validation.Status,
        SensitiveDataReview: validation.SensitiveDataReview,
        DraftOverride: validation.Status == "draft",
        Validation: "PASS",
        RequiredSections: GetRequiredSections());
    File.WriteAllText(outputPath, JsonSerializer.Serialize(artifact, new JsonSerializerOptions { WriteIndented = true }) + "\n");
    Console.WriteLine($"Goal Context selection: SELECTED ({artifact.SelectionMode})");
    Console.WriteLine($"Goal Context: {artifact.SelectedPath}");
    Console.WriteLine($"Lifecycle: {artifact.LifecycleStatus}/{artifact.SensitiveDataReview}");
    Console.WriteLine($"Artifact: {Relative(repositoryRoot, outputPath)}");
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"BLOCKED: {ex.Message}");
    return 1;
}

static string[] GetRequiredSections() =>
[
    "Document control and source boundary",
    "Original problem",
    "Desired outcome",
    "Concrete user situation and user scenarios",
    "Scope and boundaries",
    "Decisions and reasoning",
    "Constraints and invariants",
    "Success scenarios",
    "Acceptance evidence",
    "Superficially compliant but wrong",
    "Review questions",
    "Open questions and assumptions",
    "Conversation corrections and priority changes",
    "Provenance and inference ledger",
    "Human review record"
];

static int Stop(string status, string message)
{
    Console.Error.WriteLine($"HUMAN_DECISION_REQUIRED: {status}: {message}");
    return 2;
}

static List<string> ResolveCandidates(string repositoryRoot, Options options)
{
    if (options.GoalContextPath is not null)
    {
        var exact = ResolveContainedPath(repositoryRoot, options.GoalContextPath);
        if (!File.Exists(exact))
        {
            throw new FileNotFoundException("Selected Goal Context does not exist.", exact);
        }
        return [exact];
    }

    var searchRoot = ResolveContainedPath(repositoryRoot, options.SearchRoot ?? (Directory.Exists(Path.Combine(repositoryRoot, "docs")) ? "docs" : "."));
    if (!Directory.Exists(searchRoot))
    {
        throw new DirectoryNotFoundException($"Goal Context search root does not exist: {searchRoot}");
    }

    return Directory.EnumerateFiles(searchRoot, "goal-context-*.md", SearchOption.AllDirectories)
        .Where(path => !HasExcludedSegment(Path.GetRelativePath(repositoryRoot, path)))
        .Select(Path.GetFullPath)
        .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
        .ToList();
}

static bool HasExcludedSegment(string relativePath)
{
    var excluded = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        ".git", ".agents", ".apm", "apm_modules", "apm-packages", "bin", "obj", "tests"
    };
    return relativePath.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Any(excluded.Contains);
}

static ValidationResult ValidateGoalContext(string path, bool allowDraft)
{
    var errors = new List<string>();
    var fileName = Path.GetFileName(path);
    if (!Regex.IsMatch(fileName, "^goal-context-[a-z0-9]+(?:-[a-z0-9]+)*\\.md$", RegexOptions.CultureInvariant))
    {
        errors.Add("Filename must use lowercase kebab-case goal-context-<topic-summary>.md.");
    }
    if (Regex.IsMatch(fileName, "^goal-context-(?:issue|pr|pull-request|ticket|task|work-item)(?:-|$)|^goal-context-\\d", RegexOptions.CultureInvariant))
    {
        errors.Add("Filename must describe a durable topic rather than an Issue, PR, ticket, task, or number.");
    }

    var content = File.ReadAllText(path).Replace("\r\n", "\n");
    var frontmatterMatch = Regex.Match(content, "\\A---\\s*\\n(?<frontmatter>.*?)\\n---\\s*\\n", RegexOptions.Singleline);
    var frontmatter = frontmatterMatch.Success ? frontmatterMatch.Groups["frontmatter"].Value : string.Empty;
    if (!frontmatterMatch.Success)
    {
        errors.Add("Missing YAML frontmatter at the beginning of the document.");
    }

    var documentType = FrontmatterValue(frontmatter, "document_type");
    var status = FrontmatterValue(frontmatter, "status");
    var topic = FrontmatterValue(frontmatter, "topic");
    var createdAt = FrontmatterValue(frontmatter, "created_at");
    var sourceScope = FrontmatterValue(frontmatter, "source_scope");
    var sensitiveDataReview = FrontmatterValue(frontmatter, "sensitive_data_review");
    foreach (var pair in new[]
    {
        ("document_type", documentType), ("status", status), ("topic", topic), ("created_at", createdAt),
        ("source_scope", sourceScope), ("sensitive_data_review", sensitiveDataReview)
    })
    {
        if (string.IsNullOrWhiteSpace(pair.Item2))
        {
            errors.Add($"Missing or empty frontmatter field: {pair.Item1}.");
        }
    }

    if (documentType.Length > 0 && documentType != "goal-context")
    {
        errors.Add("document_type must be goal-context.");
    }
    if (status is not ("draft" or "human-reviewed"))
    {
        errors.Add("status must be draft or human-reviewed.");
    }
    if (status == "human-reviewed" && sensitiveDataReview != "passed")
    {
        errors.Add("status human-reviewed requires sensitive_data_review: passed.");
    }
    if (status == "draft" && sensitiveDataReview != "pending")
    {
        errors.Add("status draft requires sensitive_data_review: pending.");
    }
    if (status == "draft" && !allowDraft)
    {
        errors.Add("A draft Goal Context requires an exact --goal-context path plus explicit --allow-draft user override.");
    }
    if (allowDraft && status != "draft")
    {
        errors.Add("--allow-draft is only valid for a draft Goal Context.");
    }
    if (!Regex.IsMatch(createdAt, "^\\d{4}-\\d{2}-\\d{2}$", RegexOptions.CultureInvariant))
    {
        errors.Add("created_at must use YYYY-MM-DD.");
    }
    if (!Regex.IsMatch(content, "(?m)^# Goal Context:\\s+\\S.+$", RegexOptions.CultureInvariant))
    {
        errors.Add("Missing non-empty title: # Goal Context: <Topic>.");
    }

    foreach (var section in GetRequiredSections())
    {
        var match = Regex.Match(content, $"(?ms)^## {Regex.Escape(section)}\\s*$\\n(?<body>.*?)(?=^## |\\z)");
        if (!match.Success || string.IsNullOrWhiteSpace(match.Groups["body"].Value))
        {
            errors.Add($"Missing or empty required section: {section}.");
        }
    }

    if (status == "human-reviewed")
    {
        var humanReview = Regex.Match(content, "(?ms)^## Human review record\\s*$\\n(?<body>.*?)(?=^## |\\z)").Groups["body"].Value;
        if (!Regex.IsMatch(humanReview, "(?im)^- Review status:\\s*Complete\\s*$"))
        {
            errors.Add("status human-reviewed requires Review status: Complete.");
        }
        if (Regex.IsMatch(humanReview, "(?im)^- Reviewer:\\s*(?:Pending|TBD|Unknown)?\\s*$"))
        {
            errors.Add("status human-reviewed requires a non-pending Reviewer.");
        }
    }

    return new ValidationResult(status, sensitiveDataReview, errors);
}

static string FrontmatterValue(string frontmatter, string key)
{
    var match = Regex.Match(frontmatter, $"(?m)^{Regex.Escape(key)}:\\s*(?<value>[^#\\r\\n]+?)\\s*$");
    return match.Success ? match.Groups["value"].Value.Trim().Trim('"', '\'') : string.Empty;
}

static string ResolveContainedPath(string root, string path)
{
    var resolved = Path.GetFullPath(Path.IsPathRooted(path) ? path : Path.Combine(root, path));
    var relative = Path.GetRelativePath(root, resolved);
    if (relative == ".." || relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) || Path.IsPathRooted(relative))
    {
        throw new InvalidOperationException($"Path must remain inside the repository root: {path}");
    }
    return resolved;
}

static string Relative(string root, string path) => Path.GetRelativePath(root, path).Replace('\\', '/');

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file scripts/select-goal-context.cs -- --repository-root <path> [--goal-context <path> | --search-root <path>] --out <path> [--allow-draft]

Rules:
  --goal-context selects one exact repository-contained file.
  --search-root discovers goal-context-*.md and fails when zero or multiple candidates exist.
  --allow-draft requires --goal-context and records an explicit draft override.
  The selector validates naming, frontmatter, lifecycle, required sections, and human-review state.
""");
}

sealed record ValidationResult(string Status, string SensitiveDataReview, List<string> Errors);

sealed record SelectionArtifact(
    int SchemaVersion,
    string SelectionStatus,
    string SelectedPath,
    string SelectionMode,
    string LifecycleStatus,
    string SensitiveDataReview,
    bool DraftOverride,
    string Validation,
    IReadOnlyList<string> RequiredSections);

sealed record Options(
    string RepositoryRoot,
    string? GoalContextPath,
    string? SearchRoot,
    string OutputPath,
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
        var allowDraft = false;
        var help = false;
        var valid = true;

        for (var index = 0; index < args.Length; index++)
        {
            var arg = args[index];
            string? Next()
            {
                if (++index >= args.Length) { valid = false; return null; }
                return args[index];
            }

            switch (arg)
            {
                case "--repository-root": repositoryRoot = Next() ?? repositoryRoot; break;
                case "--goal-context": goalContext = Next(); break;
                case "--search-root": searchRoot = Next(); break;
                case "--out": output = Next(); break;
                case "--allow-draft": allowDraft = true; break;
                case "--help":
                case "-h": help = true; break;
                default: valid = false; break;
            }
        }

        if (goalContext is not null && searchRoot is not null) valid = false;
        if (allowDraft && goalContext is null) valid = false;
        if (string.IsNullOrWhiteSpace(output) && !help) valid = false;
        return new Options(repositoryRoot, goalContext, searchRoot, output ?? "goal-context-selection.json", allowDraft, help, valid);
    }
}
