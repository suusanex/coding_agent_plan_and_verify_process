#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Security.Cryptography;
using System.Text;
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
    var fixtureRoot = Path.GetFullPath(options.FixtureRoot!);
    if (!Directory.Exists(fixtureRoot)) throw new DirectoryNotFoundException($"Fixture root does not exist: {fixtureRoot}");
    var errors = ReplayValidator.Validate(fixtureRoot);
    WriteOutput(new ReplayOutput(1, errors.Count == 0 ? "PASS" : "FAIL", errors), options.Format);
    return errors.Count == 0 ? 0 : 2;
}
catch (Exception ex) when (ex is InvalidDataException or JsonException)
{
    WriteOutput(new ReplayOutput(1, "FAIL", [ex.Message]), options.Format);
    return 2;
}
catch (Exception ex)
{
    WriteOutput(new ReplayOutput(1, "ERROR", [ex.Message]), options.Format);
    return 1;
}

static void WriteOutput(ReplayOutput output, string format)
{
    if (format == "json")
    {
        Console.WriteLine(JsonSerializer.Serialize(output, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true
        }));
    }
    else
    {
        Console.WriteLine($"PRR-002 deterministic replay: {output.Status}");
        foreach (var error in output.Errors) Console.Error.WriteLine($"- {error}");
    }
}

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file scripts/validate-prr-002-contract.cs -- --fixture-root <path> --format json|text

The validator replays committed artifacts without calling an external model.
Exit codes: 0 valid, 1 operational failure, 2 contract violation.
""");
}

static class ReplayValidator
{
    private static readonly string[] RequiredArtifactRoles =
    [
        "review-context", "remote-patch", "goal-context-selection", "local-findings",
        "purpose-findings", "review-plan", "completion-notification", "adaptive-input"
    ];

    public static List<string> Validate(string fixtureRoot)
    {
        var errors = new List<string>();
        using var run = ReadJson(Contained(fixtureRoot, "run.json"));
        var root = run.RootElement;
        Equal(errors, "run schemaVersion", 2, Int(root, "schemaVersion"));
        Equal(errors, "fixtureId", "PRR-002", Text(root, "fixtureId"));
        Equal(errors, "evidenceMode", "deterministic-artifact-replay", Text(root, "evidenceMode"));
        Equal(errors, "externalModelExecution", false, Bool(root, "externalModelExecution"));
        Equal(errors, "productionCodeChanged", false, Bool(root, "productionCodeChanged"));

        var identity = Required(root, "identity");
        var repository = Text(identity, "repository");
        var pr = Int(identity, "pr");
        var prUrl = Text(identity, "url");
        var baseBranch = Text(identity, "baseBranch");
        var baseOid = Text(identity, "baseOid");
        var headBranch = Text(identity, "headBranch");
        var headOid = Text(identity, "headOid");
        var expectedVerdict = Text(root, "expectedVerdict");

        var artifacts = new Dictionary<string, Artifact>(StringComparer.Ordinal);
        foreach (var item in Required(root, "artifacts").EnumerateArray())
        {
            var artifact = new Artifact(Text(item, "role"), Text(item, "path"), Text(item, "normalizedSha256"));
            if (!artifacts.TryAdd(artifact.Role, artifact)) errors.Add($"Duplicate artifact role: {artifact.Role}");
        }
        foreach (var role in RequiredArtifactRoles)
        {
            if (!artifacts.ContainsKey(role)) errors.Add($"Missing required artifact role: {role}");
        }
        if (RequiredArtifactRoles.Any(role => !artifacts.ContainsKey(role))) return errors;
        foreach (var artifact in artifacts.Values)
        {
            var path = Contained(fixtureRoot, artifact.Path);
            if (!File.Exists(path))
            {
                errors.Add($"Artifact does not exist: {artifact.Role} -> {artifact.Path}");
                continue;
            }
            Equal(errors, $"artifact hash {artifact.Role}", artifact.NormalizedSha256, Hash(path));
        }

        var goalContext = Required(root, "goalContext");
        var goalArtifactPath = Text(goalContext, "artifactPath");
        var goalSelectionPath = Text(goalContext, "selectionPath");
        var goalRepositoryPath = Text(goalContext, "repositoryPath");
        var goalHash = Text(goalContext, "normalizedSha256");
        var goalPath = Contained(fixtureRoot, goalArtifactPath);
        if (!File.Exists(goalPath)) errors.Add($"Goal Context does not exist: {goalArtifactPath}");
        else Equal(errors, "Goal Context hash", goalHash, Hash(goalPath));

        if (!artifacts.TryGetValue("review-context", out var reviewArtifact)) return errors;
        using var reviewContext = ReadJson(Contained(fixtureRoot, reviewArtifact.Path));
        var reviewRoot = reviewContext.RootElement;
        Equal(errors, "review-context repository", repository, Text(reviewRoot, "repository"));
        var pullRequest = Required(reviewRoot, "pullRequest");
        Equal(errors, "review-context PR", pr, Int(pullRequest, "number"));
        Equal(errors, "review-context URL", prUrl, Text(pullRequest, "url"));
        Equal(errors, "review-context base branch", baseBranch, Text(pullRequest, "baseRefName"));
        Equal(errors, "review-context base OID", baseOid, Text(pullRequest, "baseRefOid"));
        Equal(errors, "review-context head branch", headBranch, Text(pullRequest, "headRefName"));
        Equal(errors, "review-context head OID", headOid, Text(pullRequest, "headRefOid"));

        var rawSourceIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var arrayName in new[] { "reviews", "inlineComments", "prComments", "checks" })
        {
            foreach (var item in Required(reviewRoot, arrayName).EnumerateArray())
            {
                var sourceId = Text(item, "sourceId");
                if (!rawSourceIds.Add(sourceId)) errors.Add($"Duplicate review-context sourceId: {sourceId}");
            }
        }
        var wait = Required(reviewRoot, "copilotReviewWait");
        var selectedReviewSource = $"review:{Int(wait, "selectedReviewId")}";
        if (!rawSourceIds.Contains(selectedReviewSource)) errors.Add($"selectedReviewId has no review source: {selectedReviewSource}");
        foreach (var id in Required(wait, "inlineCommentIds").EnumerateArray().Select(item => item.GetInt64()))
        {
            if (!rawSourceIds.Contains($"inline-comment:{id}")) errors.Add($"Copilot inlineCommentId has no source: {id}");
        }

        var bindingSourceIds = new HashSet<string>(StringComparer.Ordinal);
        var bindingFindingIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var binding in Required(root, "sourceBindings").EnumerateArray())
        {
            var sourceId = Text(binding, "sourceId");
            if (!bindingSourceIds.Add(sourceId)) errors.Add($"Duplicate source binding: {sourceId}");
            var findings = OptionalArray(binding, "findingIds").Select(item => item.GetString() ?? string.Empty).Where(value => value.Length > 0).ToList();
            var noActionReason = OptionalText(binding, "noActionReason");
            if (findings.Count == 0 == string.IsNullOrWhiteSpace(noActionReason))
            {
                errors.Add($"Source binding must declare findingIds or noActionReason, exclusively: {sourceId}");
            }
            foreach (var finding in findings) bindingFindingIds.Add(finding);
        }
        foreach (var sourceId in rawSourceIds.Except(bindingSourceIds)) errors.Add($"Review source is not covered: {sourceId}");
        foreach (var sourceId in bindingSourceIds.Except(rawSourceIds)) errors.Add($"Source binding does not exist in review-context: {sourceId}");

        var selectionText = ReadArtifact(fixtureRoot, artifacts, "goal-context-selection");
        using var selection = JsonDocument.Parse(selectionText);
        var selectionRoot = selection.RootElement;
        Equal(errors, "selection schemaVersion", 2, Int(selectionRoot, "schemaVersion"));
        Equal(errors, "selection status", "SELECTED", Text(selectionRoot, "selectionStatus"));
        Equal(errors, "selection path", goalSelectionPath, Text(selectionRoot, "selectedPath"));
        Equal(errors, "selection lifecycle", "human-reviewed", Text(selectionRoot, "lifecycleStatus"));
        Equal(errors, "selection sensitive review", "passed", Text(selectionRoot, "sensitiveDataReview"));
        Equal(errors, "selection validation", "PASS", Text(selectionRoot, "validation"));
        Equal(errors, "selection contract version", 1, Int(selectionRoot, "validationContractVersion"));
        Equal(errors, "selection validation mode", "strict", Text(selectionRoot, "validationMode"));
        Equal(errors, "selection content hash", goalHash, Text(selectionRoot, "contentSha256"));

        var local = ReadArtifact(fixtureRoot, artifacts, "local-findings");
        var purpose = ReadArtifact(fixtureRoot, artifacts, "purpose-findings");
        var plan = ReadArtifact(fixtureRoot, artifacts, "review-plan");
        foreach (var pair in new[] { ("local findings", local), ("purpose findings", purpose), ("review plan", plan) })
        {
            RequireContains(errors, pair.Item1, pair.Item2, $"- Repository: {repository}");
            RequireContains(errors, pair.Item1, pair.Item2, $"- PR: {pr}");
            RequireContains(errors, pair.Item1, pair.Item2, $"- Base branch / OID: {baseBranch} / {baseOid}");
            RequireContains(errors, pair.Item1, pair.Item2, $"- Head branch / OID: {headBranch} / {headOid}");
        }
        RequireContains(errors, "purpose findings", purpose, $"- Goal Context: {goalArtifactPath}");
        RequireContains(errors, "purpose findings", purpose, $"- Goal Context SHA-256: {goalHash}");
        RequireContains(errors, "review plan", plan, $"- Selected Goal Context: {goalArtifactPath}");
        RequireContains(errors, "review plan", plan, $"- Goal Context SHA-256: {goalHash}");
        RequireContains(errors, "review plan", plan, $"goal_context_reference: {goalRepositoryPath}");
        RequireContains(errors, "review plan", plan, $"- Verdict: {expectedVerdict}");

        var localFindingIds = FindingIds(local, "LR-");
        var purposeFindingIds = FindingIds(purpose, "PUR-");
        var ledger = ParseTable(plan, "## Finding Decision Ledger");
        var ledgerIds = new HashSet<string>(ledger.Select(row => row[0]), StringComparer.Ordinal);
        foreach (var id in localFindingIds.Concat(purposeFindingIds))
        {
            if (!ledgerIds.Contains(id)) errors.Add($"Reviewer finding is missing from decision ledger: {id}");
        }
        foreach (var id in bindingFindingIds)
        {
            if (!ledgerIds.Contains(id)) errors.Add($"Source binding finding is missing from decision ledger: {id}");
        }

        var ordered = ParseTable(plan, "## Ordered Remediation Plan");
        var scopeIds = new HashSet<string>(ordered.Select(row => row[1]), StringComparer.Ordinal);
        var acceptanceIds = new HashSet<string>(ordered.Select(row => row[2]), StringComparer.Ordinal);
        var graph = new Dictionary<string, List<string>>(StringComparer.Ordinal);
        foreach (var row in ledger)
        {
            if (row.Count < 9) { errors.Add("Decision ledger row has fewer than nine columns"); continue; }
            var id = row[0];
            graph.TryAdd(id, []);
            if (row[4] is not ("Apply" or "Hold" or "Reject")) errors.Add($"Invalid decision for {id}: {row[4]}");
            if (row[4] == "Apply")
            {
                var mapping = row[8].Split('/', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
                if (mapping.Length != 2 || !scopeIds.Contains(mapping[0]) || !acceptanceIds.Contains(mapping[1]))
                {
                    errors.Add($"Apply finding has invalid scope/acceptance mapping: {id} -> {row[8]}");
                }
            }
            foreach (var reference in References(row[6]).Concat(References(row[7])))
            {
                if (reference == id) errors.Add($"Finding cannot reference itself as duplicate/conflict: {id}");
                else if (!ledgerIds.Contains(reference)) errors.Add($"Finding references an unknown duplicate/conflict target: {id} -> {reference}");
                else graph[id].Add(reference);
            }
        }
        DetectCycles(errors, graph);

        var handoff = Required(root, "handoff");
        var planPath = Text(handoff, "planPath");
        var notificationPath = Text(handoff, "notificationPath");
        var adaptiveInputPath = Text(handoff, "adaptiveInputPath");
        Equal(errors, "review plan artifact path", artifacts["review-plan"].Path, RelativeArtifactPath(fixtureRoot, planPath));
        Equal(errors, "notification artifact path", artifacts["completion-notification"].Path, RelativeArtifactPath(fixtureRoot, notificationPath));
        Equal(errors, "adaptive input artifact path", artifacts["adaptive-input"].Path, RelativeArtifactPath(fixtureRoot, adaptiveInputPath));
        RequireContains(errors, "review plan implementation_intent", plan, $"plan_reference: {planPath}");
        RequireContains(errors, "review plan handoff", plan, planPath);

        var notification = ReadArtifact(fixtureRoot, artifacts, "completion-notification");
        RequireContains(errors, "completion notification", notification, $"Verdict: {expectedVerdict}");
        RequireContains(errors, "completion notification", notification, $"Review plan: {planPath}");
        var envelopeMatch = Regex.Match(notification, "(?ms)```completion-notification\\s*(?<json>\\{.*?\\})\\s*```");
        if (!envelopeMatch.Success) errors.Add("Completion notification has no JSON envelope");
        else
        {
            using var envelope = JsonDocument.Parse(envelopeMatch.Groups["json"].Value);
            Equal(errors, "notification observed status", expectedVerdict, Text(envelope.RootElement, "observed_status"));
            Equal(errors, "notification repository", repository, Text(envelope.RootElement, "repository"));
            Equal(errors, "notification result URI", prUrl, Text(envelope.RootElement, "result_uri"));
        }

        var adaptive = ReadArtifact(fixtureRoot, artifacts, "adaptive-input");
        RequireContains(errors, "Adaptive input", adaptive, "$completion-notification-decorator");
        RequireContains(errors, "Adaptive input", adaptive, "$adaptive-implementation-execution");
        RequireContains(errors, "Adaptive input", adaptive, planPath);
        if (adaptive.Contains("$goal-context-pr-review", StringComparison.Ordinal)) errors.Add("Adaptive input must not restart Goal Context review");
        return errors.Distinct(StringComparer.Ordinal).ToList();
    }

    private static string RelativeArtifactPath(string fixtureRoot, string repositoryPath)
    {
        const string prefix = "tests/pr-review-remediation/PRR-002/";
        if (!repositoryPath.StartsWith(prefix, StringComparison.Ordinal)) return repositoryPath;
        return repositoryPath[prefix.Length..];
    }

    private static string ReadArtifact(string root, Dictionary<string, Artifact> artifacts, string role) => Normalize(File.ReadAllText(Contained(root, artifacts[role].Path)));

    private static HashSet<string> FindingIds(string content, string prefix) => ParseTable(content, "## Findings")
        .Select(row => row[0])
        .Where(id => id.StartsWith(prefix, StringComparison.Ordinal))
        .ToHashSet(StringComparer.Ordinal);

    private static List<List<string>> ParseTable(string content, string heading)
    {
        var section = Regex.Match(content, $"(?ms)^{Regex.Escape(heading)}\\s*\\n(?<body>.*?)(?=^## |\\z)");
        if (!section.Success) return [];
        return section.Groups["body"].Value.Split('\n')
            .Where(line => line.TrimStart().StartsWith('|') && line.TrimEnd().EndsWith('|'))
            .Skip(2)
            .Select(Cells)
            .ToList();
    }

    private static List<string> Cells(string line) => Regex.Split(line.Trim()[1..^1], "(?<!\\\\)\\|").Select(cell => cell.Trim()).ToList();
    private static IEnumerable<string> References(string cell) => cell == "N/A" || cell.Length == 0 ? [] : cell.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    private static void DetectCycles(List<string> errors, Dictionary<string, List<string>> graph)
    {
        var visiting = new HashSet<string>(StringComparer.Ordinal);
        var visited = new HashSet<string>(StringComparer.Ordinal);
        bool Visit(string id)
        {
            if (visiting.Contains(id)) return true;
            if (!visited.Add(id)) return false;
            visiting.Add(id);
            foreach (var next in graph.GetValueOrDefault(id, [])) if (Visit(next)) return true;
            visiting.Remove(id);
            return false;
        }
        foreach (var id in graph.Keys) if (Visit(id)) { errors.Add("Duplicate/conflict references contain a cycle"); break; }
    }

    private static JsonDocument ReadJson(string path) => JsonDocument.Parse(File.ReadAllText(path));
    private static JsonElement Required(JsonElement element, string property) => element.TryGetProperty(property, out var value) ? value : throw new InvalidDataException($"Missing required property: {property}");
    private static string Text(JsonElement element, string property) => Required(element, property).GetString() ?? string.Empty;
    private static string OptionalText(JsonElement element, string property) => element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() ?? string.Empty : string.Empty;
    private static IEnumerable<JsonElement> OptionalArray(JsonElement element, string property) => element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.Array ? value.EnumerateArray().ToArray() : [];
    private static int Int(JsonElement element, string property) => Required(element, property).GetInt32();
    private static bool Bool(JsonElement element, string property) => Required(element, property).GetBoolean();

    private static string Contained(string root, string relative)
    {
        var full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        var path = Path.GetRelativePath(root, full);
        if (path == ".." || path.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal) || Path.IsPathRooted(path))
        {
            throw new InvalidDataException($"Fixture path escapes fixture root: {relative}");
        }
        return full;
    }

    private static string Hash(string path) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Normalize(File.ReadAllText(path))))).ToLowerInvariant();
    private static string Normalize(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
    private static void Equal<T>(List<string> errors, string label, T expected, T actual) where T : notnull
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) errors.Add($"{label} mismatch: expected '{expected}', found '{actual}'");
    }
    private static void RequireContains(List<string> errors, string label, string content, string expected)
    {
        if (!content.Contains(expected, StringComparison.Ordinal)) errors.Add($"{label} does not contain exact contract value: {expected}");
    }
}

sealed record Artifact(string Role, string Path, string NormalizedSha256);
sealed record ReplayOutput(int ContractVersion, string Status, IReadOnlyList<string> Errors);
sealed record Options(string? FixtureRoot, string Format, bool ShowHelp, bool Valid)
{
    public static Options Parse(string[] args)
    {
        string? fixtureRoot = null;
        var format = "text";
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
                case "--fixture-root": fixtureRoot = Next(); break;
                case "--format": format = Next() ?? format; break;
                case "--help":
                case "-h": help = true; break;
                default: valid = false; break;
            }
        }
        if (!help && string.IsNullOrWhiteSpace(fixtureRoot)) valid = false;
        if (format is not ("json" or "text")) valid = false;
        return new Options(fixtureRoot, format, help, valid);
    }
}
