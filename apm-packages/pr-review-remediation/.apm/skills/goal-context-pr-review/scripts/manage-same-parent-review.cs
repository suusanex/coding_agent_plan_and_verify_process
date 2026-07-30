#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

var options = Options.Parse(args);
if (options.Help)
{
    ShowUsage();
    return 0;
}

try
{
    var output = options.Command switch
    {
        "start" => SameParentReview.Start(options),
        "assess" => SameParentReview.Assess(options),
        "next-round" => SameParentReview.NextRound(options),
        "block" => SameParentReview.Block(options),
        "validate" => SameParentReview.Validate(options),
        _ => throw new ContractException($"Unknown command: {options.Command}")
    };
    WriteOutput(output, options.Format);
    return output.Status == "Blocked" ? 2 : 0;
}
catch (Exception ex) when (ex is ContractException or IOException or JsonException or InvalidOperationException)
{
    if (!string.IsNullOrWhiteSpace(options.RunRoot) && Directory.Exists(Path.GetFullPath(options.RunRoot)))
    {
        try { SameParentReview.RecordBlock(Path.GetFullPath(options.RunRoot), ex.Message); } catch { }
    }
    WriteOutput(new CommandOutput("Blocked", null, null, ex.Message), options.Format);
    return 2;
}

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- start [--repository-root <path>] [--pr <number-or-url>] [--goal-context <repository-relative-path>] [--search-root <path>] [--gh-executable <path>] [--skill-root <path>] [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- assess --run <run-root> --round <number> --assessment <path> [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- next-round --run <run-root> [--gh-executable <path>] [--skill-root <path>] [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- block --run <run-root> --reason <text> [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs -- validate --run <run-root> [--format json|text]

Canonical normal path:
  start resolves the current GitHub repository, prefers the current branch Ready PR, then falls back to a unique repository-wide Ready PR.
  Use --pr with a short PR number or URL only when the target remains ambiguous.
  Goal Context is arbitrary readable natural-language text; no filename, headings, frontmatter, lifecycle, approval, or creation-source contract is imposed.
  It creates .review/pr-N/same-thread/<run-id>/ automatically. Users do not supply task IDs, artifact paths, hashes, JSON, or result references.
  Round 1 requests GitHub Copilot review, then requires collector-complete current-head Copilot, local-reviewer, and purpose-reviewer evidence.
  Rounds 2 and 3 require a new current head and purpose-reviewer evidence only.
  The original parent is the only production/tests/docs write owner. This utility's only GitHub mutation is the round 1 Copilot review request.
  Complete, HumanDecisionRequired, and Blocked are terminal. A fourth round is never started automatically.

Exit codes: 0 success, 2 fail-closed blocker or contract violation.
""");
}

static void WriteOutput(CommandOutput output, string format)
{
    if (format == "json")
    {
        Console.WriteLine(JsonSerializer.Serialize(output, JsonOptions.Default));
        return;
    }
    Console.WriteLine($"Same-parent review: {output.Status}");
    if (!string.IsNullOrWhiteSpace(output.RunRoot)) Console.WriteLine($"Run root: {output.RunRoot}");
    if (output.Round is not null) Console.WriteLine($"Round: {output.Round:000}");
    if (!string.IsNullOrWhiteSpace(output.Blocker)) Console.Error.WriteLine($"Blocker: {output.Blocker}");
}

static class SameParentReview
{
    private const int SchemaVersion = 1;
    private const int MaximumRounds = 3;
    private static readonly Regex SafeRunId = new("^[0-9]{8}T[0-9]{6}Z-[a-f0-9]{8}$", RegexOptions.CultureInvariant);
    private static readonly Regex SafeFindingId = new("^TRK-[0-9]{3,}$", RegexOptions.CultureInvariant);
    private static readonly Regex ReviewerNoWrite = new("(?im)^-?\\s*Production code changed:\\s*No\\s*$", RegexOptions.CultureInvariant);

    public static CommandOutput Start(Options options)
    {
        var repositoryRoot = ResolveExistingDirectory(options.RepositoryRoot ?? ".");
        var skillRoot = ResolveSkillRoot(repositoryRoot, options.SkillRoot);
        var gh = options.GhExecutable ?? "gh";
        var repository = ResolveRepository(gh, repositoryRoot);
        var pullRequest = ResolveTargetReadyPullRequest(gh, repositoryRoot, repository, options.PullRequest);
        var runId = $"{DateTimeOffset.UtcNow:yyyyMMdd'T'HHmmss'Z'}-{Guid.NewGuid():N}"[..25];
        if (!SafeRunId.IsMatch(runId)) throw new ContractException("Generated run ID is invalid.");
        var runRoot = Path.Combine(repositoryRoot, ".review", $"pr-{pullRequest.Number}", "same-thread", runId);
        if (Directory.Exists(runRoot)) throw new ContractException("The generated same-parent run root already exists.");
        Directory.CreateDirectory(runRoot);

        try
        {
            var roundRoot = CreateRoundDirectory(runRoot, 1);
            var selectionPath = Path.Combine(roundRoot, "goal-context-selection.json");
            RunSelector(repositoryRoot, skillRoot, selectionPath, options);
            var selection = ReadSelection(selectionPath);
            RequestCopilotReview(gh, repositoryRoot, repository, pullRequest.Number);
            RunCollector(skillRoot, repositoryRoot, repository, pullRequest.Number, roundRoot, gh, waitForCopilot: true, options.CopilotTimeoutSeconds);
            var context = ReadContext(Path.Combine(roundRoot, "review-context.json"));
            EnsureContext(context, repository, pullRequest.Number, requireCopilot: true);
            EnsureEqual("preflight head OID", pullRequest.HeadOid, context.HeadOid);

            var state = new RunState
            {
                SchemaVersion = SchemaVersion,
                RunId = runId,
                Repository = repository,
                PullRequest = new PullRequestState(pullRequest.Number, pullRequest.Url, context.BaseOid, context.HeadOid),
                GoalContext = new GoalContextState(selection.SelectedPath, selection.ContentSha256),
                Status = "Round1Reviewing",
                CurrentRound = 1,
                MaximumRounds = MaximumRounds,
                ReviewerExecutions = [],
                Findings = [],
                Rounds =
                [
                    new RoundState(1, "full", context.BaseOid, context.HeadOid, Relative(runRoot, roundRoot), "AwaitingReviewers", [])
                ]
            };
            SaveState(runRoot, state);
            return new CommandOutput(state.Status, Relative(repositoryRoot, runRoot), 1, null);
        }
        catch
        {
            if (!File.Exists(StatePath(runRoot))) Directory.Delete(runRoot, recursive: true);
            throw;
        }
    }

    public static CommandOutput Assess(Options options)
    {
        Require(!string.IsNullOrWhiteSpace(options.RunRoot), "--run is required.");
        Require(options.Round > 0, "--round is required.");
        Require(!string.IsNullOrWhiteSpace(options.AssessmentPath), "--assessment is required.");
        var runRoot = ResolveExistingDirectory(options.RunRoot!);
        var state = ReadState(runRoot);
        EnsureMutable(state);
        Require(state.CurrentRound == options.Round, $"Assessment round {options.Round} does not match current round {state.CurrentRound}.");
        var round = state.Rounds.SingleOrDefault(item => item.Number == options.Round)
            ?? throw new ContractException("Current round is missing from run state.");
        var assessmentPath = ResolveContainedFile(runRoot, options.AssessmentPath!);
        var assessment = ReadJson<RoundAssessment>(assessmentPath);
        ValidateAssessment(runRoot, state, round, assessment);

        foreach (var source in assessment.MandatorySources.Where(item => item.Source is "local-reviewer" or "purpose-reviewer"))
        {
            state.ReviewerExecutions.Add(new ReviewerExecution(options.Round, source.Source, round.HeadOid, source.Artifact));
        }

        ApplyFindingProjection(state, assessment);
        round.AssessmentArtifact = Relative(runRoot, assessmentPath);
        round.MandatorySources = assessment.MandatorySources.Select(item => item.Source).Order(StringComparer.Ordinal).ToList();
        round.Status = "Assessed";

        if (assessment.Findings.Any(item => item.State == "NeedsHumanDecision"))
        {
            state.Status = "HumanDecisionRequired";
        }
        else if (state.Findings.All(item => item.State == "Resolved") || state.Findings.Count == 0)
        {
            state.Status = "Complete";
        }
        else if (state.CurrentRound >= state.MaximumRounds)
        {
            state.Status = "HumanDecisionRequired";
        }
        else
        {
            state.Status = "Remediating";
        }

        if (IsTerminal(state.Status)) WriteTerminalProjection(runRoot, state, null);
        SaveState(runRoot, state);
        return new CommandOutput(state.Status, runRoot, state.CurrentRound, null);
    }

    public static CommandOutput NextRound(Options options)
    {
        Require(!string.IsNullOrWhiteSpace(options.RunRoot), "--run is required.");
        var runRoot = ResolveExistingDirectory(options.RunRoot!);
        var state = ReadState(runRoot);
        Require(state.Status == "Remediating", "next-round requires Remediating state after parent-owned changes and validation.");
        Require(state.CurrentRound < state.MaximumRounds, "Automatic round 4 is forbidden.");
        var repositoryRoot = ResolveRepositoryRootFromRun(runRoot);
        var skillRoot = ResolveSkillRoot(repositoryRoot, options.SkillRoot);
        var gh = options.GhExecutable ?? "gh";
        var remote = ResolvePullRequest(gh, repositoryRoot, state.Repository, state.PullRequest.Number);
        Require(remote.State == "OPEN", "The current PR is no longer open.");
        Require(!remote.IsDraft, "The current PR is Draft; make it Ready before continuing.");
        Require(!string.Equals(remote.HeadOid, state.PullRequest.HeadOid, StringComparison.OrdinalIgnoreCase),
            "The current PR head has not changed after remediation; purpose review would use stale evidence.");
        Require(IsGitOid(remote.HeadOid), "The current PR head OID is invalid.");

        var nextRound = state.CurrentRound + 1;
        var roundRoot = CreateRoundDirectory(runRoot, nextRound);
        RunCollector(skillRoot, repositoryRoot, state.Repository, state.PullRequest.Number, roundRoot, gh, waitForCopilot: false, options.CopilotTimeoutSeconds);
        var context = ReadContext(Path.Combine(roundRoot, "review-context.json"));
        EnsureContext(context, state.Repository, state.PullRequest.Number, requireCopilot: false);
        EnsureEqual("current remote head OID", remote.HeadOid, context.HeadOid);
        CopyGoalContextSelection(runRoot, roundRoot);

        state.PullRequest = state.PullRequest with { BaseOid = context.BaseOid, HeadOid = context.HeadOid };
        state.CurrentRound = nextRound;
        state.Status = "PurposeReviewing";
        state.Rounds.Add(new RoundState(nextRound, "purpose-only", context.BaseOid, context.HeadOid, Relative(runRoot, roundRoot), "AwaitingPurposeReviewer", []));
        SaveState(runRoot, state);
        return new CommandOutput(state.Status, runRoot, nextRound, null);
    }

    public static CommandOutput Block(Options options)
    {
        Require(!string.IsNullOrWhiteSpace(options.RunRoot), "--run is required.");
        Require(!string.IsNullOrWhiteSpace(options.Reason), "--reason is required.");
        var runRoot = ResolveExistingDirectory(options.RunRoot!);
        RecordBlock(runRoot, options.Reason!);
        var state = ReadState(runRoot);
        return new CommandOutput(state.Status, runRoot, state.CurrentRound, state.Blocker);
    }

    public static void RecordBlock(string runRoot, string reason)
    {
        var state = ReadState(runRoot);
        if (IsTerminal(state.Status)) return;
        state.Status = "Blocked";
        state.Blocker = OneLine(reason);
        WriteTerminalProjection(runRoot, state, state.Blocker);
        SaveState(runRoot, state);
    }

    public static CommandOutput Validate(Options options)
    {
        Require(!string.IsNullOrWhiteSpace(options.RunRoot), "--run is required.");
        var runRoot = ResolveExistingDirectory(options.RunRoot!);
        var state = ReadState(runRoot);
        ValidateState(runRoot, state);
        return new CommandOutput(state.Status, runRoot, state.CurrentRound, state.Blocker);
    }

    private static void ValidateAssessment(string runRoot, RunState state, RoundState round, RoundAssessment assessment)
    {
        assessment.MandatorySources ??= [];
        assessment.PriorAssessments ??= [];
        assessment.Findings ??= [];
        Require(assessment.SchemaVersion == 1, "Assessment schemaVersion must be 1.");
        Require(assessment.RoundNumber == round.Number, "Assessment roundNumber does not match current round.");
        EnsureEqual("assessment reviewed head OID", round.HeadOid, assessment.ReviewedHeadOid);
        Require(!assessment.ProductionCodeChangedByReviewer, "Reviewer evidence reports a production write; only the original parent may write production/tests/docs.");
        var expected = round.Mode == "full"
            ? new[] { "github-copilot", "local-reviewer", "purpose-reviewer" }
            : new[] { "purpose-reviewer" };
        var actual = assessment.MandatorySources.Select(item => item.Source).Order(StringComparer.Ordinal).ToArray();
        Require(actual.SequenceEqual(expected.Order(StringComparer.Ordinal)),
            $"Mandatory source coverage for {round.Mode} must be exactly: {string.Join(", ", expected)}.");
        Require(assessment.MandatorySources.All(item => item.Status == "Complete"), "Every mandatory source status must be Complete.");

        foreach (var source in assessment.MandatorySources)
        {
            var artifact = ResolveContainedFile(runRoot, source.Artifact);
            var expectedRoundRoot = Path.Combine(runRoot, round.Directory);
            Require(IsContained(expectedRoundRoot, artifact), $"Mandatory source artifact must remain inside round-{round.Number:000}: {source.Artifact}");
            if (source.Source is "local-reviewer" or "purpose-reviewer")
            {
                var raw = File.ReadAllText(artifact);
                Require(ReviewerNoWrite.IsMatch(raw), $"{source.Source} raw output must contain 'Production code changed: No'.");
                var requiredPrefix = source.Source == "local-reviewer" ? "LR-" : "PUR-";
                Require(raw.Contains(requiredPrefix, StringComparison.Ordinal) || raw.Contains("No findings", StringComparison.OrdinalIgnoreCase),
                    $"{source.Source} raw output must preserve stable {requiredPrefix} evidence or explicitly state No findings.");
            }
        }

        var roundRoot = Path.Combine(runRoot, round.Directory);
        if (round.Mode == "purpose-only")
        {
            Require(!File.Exists(Path.Combine(roundRoot, "local-reviewer.raw.md")), "purpose-only round must not contain local-reviewer output.");
            Require(assessment.Findings.SelectMany(item => item.SourceIds).All(id => id.StartsWith("PUR-", StringComparison.Ordinal)),
                "purpose-only actionable evidence must use current PUR-* source IDs only.");
            var activeBefore = state.Findings.Where(item => item.State == "Active").Select(item => item.TrackingId).Order(StringComparer.Ordinal).ToArray();
            var assessed = assessment.PriorAssessments.Select(item => item.TrackingId).Order(StringComparer.Ordinal).ToArray();
            Require(activeBefore.SequenceEqual(assessed), "Prior assessments must cover every previously active tracking ID exactly once.");
            Require(assessment.PriorAssessments.All(item => item.Disposition is "persistent" or "resolved"),
                "Prior assessment disposition must be persistent or resolved.");
            Require(assessment.PriorAssessments.All(item => item.EvidenceSourceId.StartsWith("PUR-", StringComparison.Ordinal)),
                "Prior assessment evidence must be a current PUR-* source ID.");
        }
        else
        {
            Require(assessment.PriorAssessments.Count == 0, "Round 1 must not contain prior assessments.");
        }

        var duplicate = assessment.Findings.GroupBy(item => item.TrackingId, StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1);
        Require(duplicate is null, $"Duplicate tracking ID in assessment: {duplicate?.Key}");
        foreach (var finding in assessment.Findings)
        {
            finding.SourceIds ??= [];
            Require(SafeFindingId.IsMatch(finding.TrackingId), $"Invalid tracking ID: {finding.TrackingId}");
            Require(finding.State is "Active" or "Resolved" or "NeedsHumanDecision", $"Invalid finding state: {finding.State}");
            Require(finding.SourceIds.Count > 0, $"Finding {finding.TrackingId} requires source IDs.");
            Require(!string.IsNullOrWhiteSpace(finding.Summary), $"Finding {finding.TrackingId} requires a summary.");
        }
    }

    private static void ApplyFindingProjection(RunState state, RoundAssessment assessment)
    {
        foreach (var prior in assessment.PriorAssessments)
        {
            var existing = state.Findings.Single(item => item.TrackingId == prior.TrackingId);
            existing.State = prior.Disposition == "resolved" ? "Resolved" : "Active";
            existing.LastEvidenceSourceIds = [prior.EvidenceSourceId];
            existing.LastAssessedRound = assessment.RoundNumber;
        }
        foreach (var projected in assessment.Findings)
        {
            var existing = state.Findings.SingleOrDefault(item => item.TrackingId == projected.TrackingId);
            if (existing is null)
            {
                state.Findings.Add(new FindingState(projected.TrackingId, projected.State, projected.Summary, projected.SourceIds, assessment.RoundNumber));
            }
            else
            {
                existing.State = projected.State;
                existing.Summary = projected.Summary;
                existing.LastEvidenceSourceIds = projected.SourceIds;
                existing.LastAssessedRound = assessment.RoundNumber;
            }
        }
    }

    private static void ValidateState(string runRoot, RunState state)
    {
        Require(state.SchemaVersion == SchemaVersion, "Run state schemaVersion is unsupported.");
        Require(SafeRunId.IsMatch(state.RunId), "Run ID is invalid.");
        Require(state.MaximumRounds == MaximumRounds, "Maximum rounds must remain 3.");
        Require(state.CurrentRound is >= 1 and <= MaximumRounds, "Current round is outside 1..3.");
        Require(state.Rounds.Count == state.CurrentRound, "Round history must be contiguous.");
        Require(state.Rounds.Select(item => item.Number).SequenceEqual(Enumerable.Range(1, state.CurrentRound)), "Round numbers are not contiguous.");
        Require(state.Rounds[0].Mode == "full", "Round 1 must be full.");
        Require(state.Rounds.Skip(1).All(item => item.Mode == "purpose-only"), "Rounds 2 and 3 must be purpose-only.");
        Require(state.Rounds.Select(item => item.HeadOid).Distinct(StringComparer.OrdinalIgnoreCase).Count() == state.Rounds.Count,
            "Each round must use a new current PR head.");
        Require(state.ReviewerExecutions.Where(item => item.Round == 1).Select(item => item.Role).Distinct().Order(StringComparer.Ordinal)
            .SequenceEqual(state.CurrentRound == 1 && state.Rounds[0].Status.StartsWith("Awaiting", StringComparison.Ordinal)
                ? Array.Empty<string>() : new[] { "local-reviewer", "purpose-reviewer" }),
            "Round 1 reviewer roles are incomplete or invalid.");
        Require(state.ReviewerExecutions.Where(item => item.Round > 1).All(item => item.Role == "purpose-reviewer"),
            "Rounds 2 and 3 may record purpose-reviewer only.");
        foreach (var round in state.Rounds)
        {
            var directory = ResolveContainedDirectory(runRoot, round.Directory);
            Require(File.Exists(Path.Combine(directory, "review-context.json")), $"Round {round.Number} review context is missing.");
            Require(File.Exists(Path.Combine(directory, "pr-diff.patch")), $"Round {round.Number} remote patch is missing.");
            Require(File.Exists(Path.Combine(directory, "goal-context-selection.json")), $"Round {round.Number} Goal Context selection is missing.");
            if (round.Mode == "purpose-only") Require(!File.Exists(Path.Combine(directory, "local-reviewer.raw.md")), "purpose-only round contains local-reviewer output.");
        }
        if (IsTerminal(state.Status))
        {
            var projectionPath = Path.Combine(runRoot, "terminal-projection.json");
            var notificationPath = Path.Combine(runRoot, "completion-notification.txt");
            Require(File.Exists(projectionPath), "Terminal run is missing terminal-projection.json.");
            Require(File.Exists(notificationPath), "Terminal run is missing completion-notification.txt.");
            using var projection = JsonDocument.Parse(File.ReadAllText(projectionPath));
            var names = projection.RootElement.EnumerateObject().Select(item => item.Name).Order(StringComparer.Ordinal).ToArray();
            Require(names.SequenceEqual(new[] { "observed_status", "primary_process", "result_uri", "schema_version", "title" }),
                "Terminal projection must contain only schema/process/status/title/current PR URI.");
            Require(!projection.RootElement.TryGetProperty("thread-id", out _) && !projection.RootElement.TryGetProperty("turn-id", out _),
                "Terminal projection must not contain callback identity.");
            var expectedNotification = $"```completion-notification\n{NormalizeLineEndings(File.ReadAllText(projectionPath)).TrimEnd('\n')}\n```\n";
            Require(NormalizeLineEndings(File.ReadAllText(notificationPath)) == NormalizeLineEndings(expectedNotification),
                "completion-notification.txt must contain exactly the fenced terminal projection.");
        }
    }

    private static void WriteTerminalProjection(string runRoot, RunState state, string? blocker)
    {
        var title = state.Status switch
        {
            "Complete" => "Goal Context PR review completed",
            "HumanDecisionRequired" => "Goal Context PR review needs a human decision",
            _ => "Goal Context PR review blocked"
        };
        var projection = new Dictionary<string, object?>
        {
            ["schema_version"] = 1,
            ["primary_process"] = "goal-context-pr-review",
            ["observed_status"] = state.Status,
            ["title"] = title,
            ["result_uri"] = state.PullRequest.Url
        };
        var json = JsonSerializer.Serialize(projection, JsonOptions.Default);
        File.WriteAllText(Path.Combine(runRoot, "terminal-projection.json"), json + "\n", Encoding.UTF8);
        File.WriteAllText(Path.Combine(runRoot, "completion-notification.txt"), $"```completion-notification\n{json}\n```\n", Encoding.UTF8);
    }

    private static void SaveState(string runRoot, RunState state)
    {
        ValidateBasicState(state);
        File.WriteAllText(StatePath(runRoot), JsonSerializer.Serialize(state, JsonOptions.Default) + "\n", Encoding.UTF8);
        WriteSummary(runRoot, state);
    }

    private static void WriteSummary(string runRoot, RunState state)
    {
        var b = new StringBuilder();
        b.AppendLine("# Same-parent Goal Context PR review run");
        b.AppendLine();
        b.AppendLine($"- Status: {state.Status}");
        b.AppendLine($"- Repository: {state.Repository}");
        b.AppendLine($"- Pull request: {state.PullRequest.Url}");
        b.AppendLine($"- Current head OID: {state.PullRequest.HeadOid}");
        b.AppendLine($"- Goal Context: {state.GoalContext.Path}");
        b.AppendLine($"- Current round: {state.CurrentRound} / {state.MaximumRounds}");
        b.AppendLine("- Production write owner: original parent only");
        b.AppendLine("- Raw evidence precedence: raw reviewer and collector artifacts outrank this summary");
        if (!string.IsNullOrWhiteSpace(state.Blocker)) b.AppendLine($"- Blocker: {state.Blocker}");
        b.AppendLine();
        b.AppendLine("## Reviewer execution ledger");
        b.AppendLine();
        b.AppendLine("| Round | Role | Reviewed head | Raw artifact |");
        b.AppendLine("| --- | --- | --- | --- |");
        foreach (var execution in state.ReviewerExecutions)
            b.AppendLine($"| {execution.Round} | {execution.Role} | `{execution.HeadOid}` | `{execution.RawArtifact}` |");
        if (state.ReviewerExecutions.Count == 0) b.AppendLine("| N/A | Awaiting reviewers | N/A | N/A |");
        b.AppendLine();
        b.AppendLine("## Finding projection");
        b.AppendLine();
        b.AppendLine("| Tracking ID | State | Last assessed round | Evidence | Summary |");
        b.AppendLine("| --- | --- | --- | --- | --- |");
        foreach (var finding in state.Findings.OrderBy(item => item.TrackingId, StringComparer.Ordinal))
            b.AppendLine($"| {finding.TrackingId} | {finding.State} | {finding.LastAssessedRound} | {string.Join(", ", finding.LastEvidenceSourceIds)} | {EscapeCell(finding.Summary)} |");
        if (state.Findings.Count == 0) b.AppendLine("| N/A | None | N/A | N/A | No projected findings |");
        File.WriteAllText(Path.Combine(runRoot, "run-summary.md"), b.ToString(), Encoding.UTF8);
    }

    private static void ValidateBasicState(RunState state)
    {
        Require(state.SchemaVersion == SchemaVersion, "Run state schemaVersion is invalid.");
        Require(IsRepository(state.Repository), "Run repository identity is invalid.");
        Require(state.PullRequest.Number > 0 && IsConcretePullRequestUri(state.PullRequest.Url), "Run PR identity is invalid.");
        Require(IsGitOid(state.PullRequest.BaseOid) && IsGitOid(state.PullRequest.HeadOid), "Run base/head OID is invalid.");
        Require(state.MaximumRounds == MaximumRounds, "Maximum rounds must remain 3.");
    }

    private static RunState ReadState(string runRoot)
    {
        var state = ReadJson<RunState>(StatePath(runRoot));
        ValidateBasicState(state);
        return state;
    }

    private static string StatePath(string runRoot) => Path.Combine(runRoot, "run-state.json");

    private static string ResolveRepository(string gh, string cwd)
    {
        using var doc = RunJson(gh, ["repo", "view", "--json", "nameWithOwner"], cwd);
        var repository = RequiredString(doc.RootElement, "nameWithOwner");
        Require(IsRepository(repository), "Current GitHub repository could not be resolved to owner/name.");
        return repository;
    }

    private static PullRequestCandidate ResolveTargetReadyPullRequest(string gh, string cwd, string repository, string? explicitReference)
    {
        if (!string.IsNullOrWhiteSpace(explicitReference))
        {
            var number = ParsePullRequestReference(explicitReference!, repository);
            var selected = ResolvePullRequest(gh, cwd, repository, number);
            Require(selected.State == "OPEN", $"PR #{selected.Number} is not open; select an open Ready PR.");
            Require(!selected.IsDraft, $"PR #{selected.Number} is Draft; select a Ready PR.");
            return selected;
        }

        var branch = Run("git", ["branch", "--show-current"], cwd, "current Git branch resolution").Trim();
        if (!string.IsNullOrWhiteSpace(branch))
        {
            var branchCandidates = ListOpenPullRequests(gh, cwd, repository, branch);
            var branchReady = branchCandidates.Where(item => !item.IsDraft).ToList();
            Require(branchReady.Count <= 1,
                $"{branchReady.Count} Ready PRs target the current branch '{branch}'; re-run start with --pr <number-or-url>.");
            if (branchReady.Count == 1) return branchReady[0];
        }

        var candidates = ListOpenPullRequests(gh, cwd, repository, null);
        var ready = candidates.Where(item => !item.IsDraft).ToList();
        if (ready.Count == 0 && candidates.Count == 1 && candidates[0].IsDraft)
            throw new ContractException($"PR #{candidates[0].Number} is Draft; no Ready PR can be selected.");
        Require(ready.Count == 1, ready.Count == 0
            ? "No Ready PR exists in the current repository."
            : $"{ready.Count} Ready PRs exist in the current repository; re-run start with --pr <number-or-url>.");
        return ready[0];
    }

    private static List<PullRequestCandidate> ListOpenPullRequests(string gh, string cwd, string repository, string? headBranch)
    {
        var arguments = new List<string> { "pr", "list", "--repo", repository, "--state", "open" };
        if (!string.IsNullOrWhiteSpace(headBranch)) { arguments.Add("--head"); arguments.Add(headBranch); }
        arguments.AddRange(["--json", "number,url,state,isDraft,baseRefOid,headRefOid", "--limit", "100"]);
        using var doc = RunJson(gh, arguments, cwd);
        Require(doc.RootElement.ValueKind == JsonValueKind.Array, "GitHub PR list did not return an array.");
        return doc.RootElement.EnumerateArray().Select(ReadPullRequestCandidate).ToList();
    }

    private static int ParsePullRequestReference(string value, string repository)
    {
        if (int.TryParse(value, out var number) && number > 0) return number;
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri)
            && uri.Scheme == Uri.UriSchemeHttps
            && string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase))
        {
            var match = Regex.Match(uri.AbsolutePath, "^/(?<repository>[^/]+/[^/]+)/pull/(?<number>[1-9][0-9]*)$", RegexOptions.CultureInvariant);
            if (match.Success && string.Equals(match.Groups["repository"].Value, repository, StringComparison.OrdinalIgnoreCase))
                return int.Parse(match.Groups["number"].Value);
        }
        throw new ContractException("--pr must be a positive PR number or a concrete HTTPS GitHub PR URL for the current repository.");
    }

    private static PullRequestCandidate ResolvePullRequest(string gh, string cwd, string repository, int number)
    {
        using var doc = RunJson(gh, ["pr", "view", number.ToString(), "--repo", repository, "--json", "number,url,state,isDraft,baseRefOid,headRefOid"], cwd);
        return ReadPullRequestCandidate(doc.RootElement);
    }

    private static PullRequestCandidate ReadPullRequestCandidate(JsonElement root)
    {
        var candidate = new PullRequestCandidate(
            RequiredInt(root, "number"), RequiredString(root, "url"),
            root.TryGetProperty("isDraft", out var draft) && draft.GetBoolean(),
            RequiredString(root, "state"),
            RequiredString(root, "baseRefOid"), RequiredString(root, "headRefOid"));
        Require(IsConcretePullRequestUri(candidate.Url), $"PR #{candidate.Number} URL is not a concrete HTTPS pull URI.");
        Require(IsGitOid(candidate.BaseOid) && IsGitOid(candidate.HeadOid), $"PR #{candidate.Number} has invalid base/head OIDs.");
        return candidate;
    }

    private static void RunSelector(string repositoryRoot, string skillRoot, string outputPath, Options options)
    {
        var arguments = new List<string> { "run", "--file", Path.Combine(skillRoot, "scripts", "select-goal-context.cs"), "--", "--repository-root", repositoryRoot, "--out", outputPath };
        if (!string.IsNullOrWhiteSpace(options.GoalContext)) { arguments.Add("--goal-context"); arguments.Add(options.GoalContext!); }
        else if (!string.IsNullOrWhiteSpace(options.SearchRoot)) { arguments.Add("--search-root"); arguments.Add(options.SearchRoot!); }
        Run("dotnet", arguments, repositoryRoot, "Goal Context selection");
    }

    private static void RunCollector(string skillRoot, string repositoryRoot, string repository, int pullRequest, string outputRoot, string gh, bool waitForCopilot, int timeoutSeconds)
    {
        var collector = Path.GetFullPath(Path.Combine(skillRoot, "..", "pr-review-remediation", "scripts", "collect-pr-review-context.cs"));
        Require(File.Exists(collector), "The shared PR context collector is not installed beside goal-context-pr-review.");
        var arguments = new List<string>
        {
            "run", "--file", collector, "--", "--repo", repository, "--pr", pullRequest.ToString(), "--out", outputRoot,
            "--gh-executable", gh
        };
        if (waitForCopilot)
        {
            arguments.Add("--copilot-timeout-seconds"); arguments.Add(timeoutSeconds.ToString());
            arguments.Add("--copilot-poll-interval-seconds"); arguments.Add("1");
            arguments.Add("--copilot-stable-samples"); arguments.Add("1");
        }
        else arguments.Add("--no-wait-for-copilot");
        Run("dotnet", arguments, repositoryRoot, waitForCopilot ? "round 1 PR context collection" : "purpose-only PR context refresh");
    }

    private static void RequestCopilotReview(string gh, string repositoryRoot, string repository, int pullRequest)
    {
        Run(gh, ["pr", "edit", pullRequest.ToString(), "--repo", repository, "--add-reviewer", "@copilot"],
            repositoryRoot, "GitHub Copilot review request");
    }

    private static GoalContextSelection ReadSelection(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        var root = doc.RootElement;
        Require(RequiredString(root, "selectionStatus") == "SELECTED", "Goal Context selection did not return SELECTED.");
        Require(RequiredString(root, "validation") == "PASS", "Goal Context readable free-form validation did not pass.");
        return new GoalContextSelection(RequiredString(root, "selectedPath"), RequiredString(root, "contentSha256"));
    }

    private static ReviewContext ReadContext(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        var root = doc.RootElement;
        var target = root.GetProperty("target");
        var wait = root.GetProperty("copilotReviewWait");
        return new ReviewContext(RequiredString(target, "repository"), RequiredInt(target, "pullRequest"), RequiredString(target, "baseRefOid"),
            RequiredString(target, "headRefOid"), target.GetProperty("isDraft").GetBoolean(), RequiredString(wait, "observedReviewState"),
            wait.GetProperty("timedOut").GetBoolean(), wait.GetProperty("isComplete").GetBoolean());
    }

    private static void EnsureContext(ReviewContext context, string repository, int pullRequest, bool requireCopilot)
    {
        EnsureEqual("collector repository", repository, context.Repository);
        Require(context.PullRequest == pullRequest, "Collector PR number does not match resolved Ready PR.");
        Require(!context.IsDraft, "Collector resolved a Draft PR.");
        Require(IsGitOid(context.BaseOid) && IsGitOid(context.HeadOid), "Collector returned invalid base/head OIDs.");
        if (requireCopilot)
            Require(!context.CopilotTimedOut && context.CopilotIsComplete
                && context.CopilotObservedState is "reviewOnly" or "reviewAndInline",
                "GitHub Copilot review collection did not complete for the current head.");
    }

    private static void CopyGoalContextSelection(string runRoot, string roundRoot)
    {
        var source = Path.Combine(runRoot, "round-001", "goal-context-selection.json");
        Require(File.Exists(source), "Round 1 Goal Context selection is missing.");
        File.Copy(source, Path.Combine(roundRoot, "goal-context-selection.json"), overwrite: false);
    }

    private static string CreateRoundDirectory(string runRoot, int round)
    {
        var path = Path.Combine(runRoot, $"round-{round:000}");
        Require(!Directory.Exists(path), $"round-{round:000} already exists and will not be overwritten.");
        Directory.CreateDirectory(path);
        return path;
    }

    private static string ResolveSkillRoot(string repositoryRoot, string? explicitRoot)
    {
        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(explicitRoot)) candidates.Add(explicitRoot);
        candidates.Add(Path.Combine(repositoryRoot, ".agents", "skills", "goal-context-pr-review"));
        candidates.Add(Path.Combine(repositoryRoot, "apm-packages", "pr-review-remediation", ".apm", "skills", "goal-context-pr-review"));
        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(Path.Combine(full, "SKILL.md")) && File.Exists(Path.Combine(full, "scripts", "select-goal-context.cs"))) return full;
        }
        throw new ContractException("The installed goal-context-pr-review Skill root could not be resolved.");
    }

    private static string ResolveRepositoryRootFromRun(string runRoot)
    {
        var current = new DirectoryInfo(runRoot);
        while (current is not null)
        {
            if (current.Name == ".review" && current.Parent is not null) return current.Parent.FullName;
            current = current.Parent;
        }
        throw new ContractException("Run root is not under a repository .review directory.");
    }

    private static void EnsureMutable(RunState state) => Require(!IsTerminal(state.Status), $"Run is terminal: {state.Status}.");
    private static bool IsTerminal(string status) => status is "Complete" or "HumanDecisionRequired" or "Blocked";
    private static bool IsRepository(string value) => Regex.IsMatch(value, "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", RegexOptions.CultureInvariant);
    private static bool IsGitOid(string value) => Regex.IsMatch(value, "^[a-fA-F0-9]{40}$", RegexOptions.CultureInvariant);
    private static bool IsConcretePullRequestUri(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps &&
        Regex.IsMatch(uri.AbsolutePath, "^/[^/]+/[^/]+/pull/[1-9][0-9]*$", RegexOptions.CultureInvariant);
    private static string OneLine(string value) => Regex.Replace(value, "\\s+", " ").Trim();
    private static string NormalizeLineEndings(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
    private static string EscapeCell(string value) => OneLine(value).Replace("|", "\\|", StringComparison.Ordinal);
    private static void EnsureEqual(string name, string expected, string actual) => Require(string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase), $"{name} mismatch: expected {expected}, actual {actual}.");
    private static void Require(bool condition, string message) { if (!condition) throw new ContractException(message); }

    private static JsonDocument RunJson(string executable, IReadOnlyList<string> arguments, string cwd)
    {
        var output = Run(executable, arguments, cwd, $"{executable} {string.Join(' ', arguments.Take(2))}");
        try { return JsonDocument.Parse(output); }
        catch (JsonException ex) { throw new ContractException($"GitHub command returned invalid JSON: {ex.Message}"); }
    }

    private static string Run(string executable, IReadOnlyList<string> arguments, string cwd, string description)
    {
        var start = new ProcessStartInfo(executable)
        {
            WorkingDirectory = cwd,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            CreateNoWindow = true
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new ContractException($"Could not start {description}.");
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = process.StandardError.ReadToEnd();
        process.WaitForExit();
        if (process.ExitCode != 0) throw new ContractException($"{description} failed: {OneLine(string.IsNullOrWhiteSpace(stderr) ? stdout : stderr)}");
        return stdout;
    }

    private static T ReadJson<T>(string path) where T : class
        => JsonSerializer.Deserialize<T>(File.ReadAllText(path), JsonOptions.Default) ?? throw new ContractException($"JSON artifact is empty: {path}");
    private static string RequiredString(JsonElement root, string name) => root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(value.GetString())
        ? value.GetString()! : throw new ContractException($"Missing required JSON string: {name}");
    private static int RequiredInt(JsonElement root, string name) => root.TryGetProperty(name, out var value) && value.TryGetInt32(out var number) && number > 0
        ? number : throw new ContractException($"Missing required positive JSON number: {name}");
    private static string ResolveExistingDirectory(string path) { var full = Path.GetFullPath(path); if (!Directory.Exists(full)) throw new ContractException($"Directory does not exist: {path}"); return full; }
    private static string ResolveContainedDirectory(string root, string path) { var full = Path.GetFullPath(Path.Combine(root, path)); Require(IsContained(root, full) && Directory.Exists(full), $"Directory must exist inside run root: {path}"); return full; }
    private static string ResolveContainedFile(string root, string path) { var full = Path.GetFullPath(Path.IsPathRooted(path) ? path : Path.Combine(root, path)); Require(IsContained(root, full) && File.Exists(full), $"File must exist inside run root: {path}"); return full; }
    private static bool IsContained(string root, string path) { var r = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar; var p = Path.GetFullPath(path); return p.StartsWith(r, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal); }
    private static string Relative(string root, string path) => Path.GetRelativePath(root, path).Replace('\\', '/');
}

sealed class Options
{
    public string Command { get; private set; } = "";
    public string? RepositoryRoot { get; private set; }
    public string? PullRequest { get; private set; }
    public string? GoalContext { get; private set; }
    public string? SearchRoot { get; private set; }
    public string? GhExecutable { get; private set; }
    public string? SkillRoot { get; private set; }
    public string? RunRoot { get; private set; }
    public string? AssessmentPath { get; private set; }
    public string? Reason { get; private set; }
    public int Round { get; private set; }
    public int CopilotTimeoutSeconds { get; private set; } = 180;
    public string Format { get; private set; } = "text";
    public bool Help { get; private set; }

    public static Options Parse(string[] args)
    {
        var o = new Options();
        if (args.Length == 0) { o.Help = true; return o; }
        if (args[0] is "--help" or "-h") { o.Help = true; return o; }
        o.Command = args[0];
        for (var i = 1; i < args.Length; i++)
        {
            string Next() => ++i < args.Length ? args[i] : throw new ContractException($"Missing value after {args[i - 1]}.");
            switch (args[i])
            {
                case "--repository-root": o.RepositoryRoot = Next(); break;
                case "--pr": o.PullRequest = Next(); break;
                case "--goal-context": o.GoalContext = Next(); break;
                case "--search-root": o.SearchRoot = Next(); break;
                case "--gh-executable": o.GhExecutable = Next(); break;
                case "--validator": _ = Next(); break;
                case "--skill-root": o.SkillRoot = Next(); break;
                case "--run": o.RunRoot = Next(); break;
                case "--assessment": o.AssessmentPath = Next(); break;
                case "--reason": o.Reason = Next(); break;
                case "--round": o.Round = int.TryParse(Next(), out var round) ? round : 0; break;
                case "--copilot-timeout-seconds": o.CopilotTimeoutSeconds = int.TryParse(Next(), out var timeout) && timeout > 0 ? timeout : throw new ContractException("--copilot-timeout-seconds must be positive."); break;
                case "--format": o.Format = Next(); break;
                case "--help": case "-h": o.Help = true; break;
                default: throw new ContractException($"Unknown argument: {args[i]}");
            }
        }
        if (o.Format is not ("text" or "json")) throw new ContractException("--format must be text or json.");
        return o;
    }
}

static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
}

sealed record CommandOutput(string Status, string? RunRoot, int? Round, string? Blocker);
sealed record PullRequestCandidate(int Number, string Url, bool IsDraft, string State, string BaseOid, string HeadOid);
sealed record ReviewContext(string Repository, int PullRequest, string BaseOid, string HeadOid, bool IsDraft, string CopilotObservedState, bool CopilotTimedOut, bool CopilotIsComplete);
sealed record GoalContextSelection(string SelectedPath, string ContentSha256);
sealed record PullRequestState(int Number, string Url, string BaseOid, string HeadOid);
sealed record GoalContextState(string Path, string ContentSha256);
sealed record ReviewerExecution(int Round, string Role, string HeadOid, string RawArtifact);

sealed class RunState
{
    public int SchemaVersion { get; set; }
    public string RunId { get; set; } = "";
    public string Repository { get; set; } = "";
    public PullRequestState PullRequest { get; set; } = new(0, "", "", "");
    public GoalContextState GoalContext { get; set; } = new("", "");
    public string Status { get; set; } = "";
    public int CurrentRound { get; set; }
    public int MaximumRounds { get; set; }
    public string? Blocker { get; set; }
    public List<ReviewerExecution> ReviewerExecutions { get; set; } = [];
    public List<FindingState> Findings { get; set; } = [];
    public List<RoundState> Rounds { get; set; } = [];
}

sealed class RoundState(int number, string mode, string baseOid, string headOid, string directory, string status, List<string> mandatorySources)
{
    public int Number { get; set; } = number;
    public string Mode { get; set; } = mode;
    public string BaseOid { get; set; } = baseOid;
    public string HeadOid { get; set; } = headOid;
    public string Directory { get; set; } = directory;
    public string Status { get; set; } = status;
    public string? AssessmentArtifact { get; set; }
    public List<string> MandatorySources { get; set; } = mandatorySources;
}

sealed class FindingState
{
    public FindingState() { }
    public FindingState(string trackingId, string state, string summary, List<string> evidence, int round)
    {
        TrackingId = trackingId;
        State = state;
        Summary = summary;
        LastEvidenceSourceIds = evidence;
        LastAssessedRound = round;
    }
    public string TrackingId { get; set; } = "";
    public string State { get; set; } = "";
    public string Summary { get; set; } = "";
    public List<string> LastEvidenceSourceIds { get; set; } = [];
    public int LastAssessedRound { get; set; }
}

sealed class RoundAssessment
{
    public int SchemaVersion { get; set; }
    public int RoundNumber { get; set; }
    public string ReviewedHeadOid { get; set; } = "";
    public bool ProductionCodeChangedByReviewer { get; set; }
    public List<MandatorySource> MandatorySources { get; set; } = [];
    public List<PriorAssessment> PriorAssessments { get; set; } = [];
    public List<AssessmentFinding> Findings { get; set; } = [];
}

sealed class MandatorySource { public string Source { get; set; } = ""; public string Artifact { get; set; } = ""; public string Status { get; set; } = ""; }
sealed class PriorAssessment { public string TrackingId { get; set; } = ""; public string Disposition { get; set; } = ""; public string EvidenceSourceId { get; set; } = ""; }
sealed class AssessmentFinding { public string TrackingId { get; set; } = ""; public string State { get; set; } = ""; public string Summary { get; set; } = ""; public List<string> SourceIds { get; set; } = []; }
sealed class ContractException(string message) : Exception(message);
