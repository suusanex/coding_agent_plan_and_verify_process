#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Security.Cryptography;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

Options options;
try
{
    options = Options.Parse(args);
}
catch (ContractException ex)
{
    var requestedFormat = args.Select((value, index) => (value, index))
        .Any(item => item.value == "--format" && item.index + 1 < args.Length && args[item.index + 1] == "json")
        ? "json" : "text";
    WriteOutput(new CommandOutput(1, "FAIL", null, null, null, [ex.Message]), requestedFormat);
    return 2;
}
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
    var result = options.Command switch
    {
        "start" => ReviewCycleManager.Start(options),
        "complete" => ReviewCycleManager.Complete(options),
        "resolve" => ReviewCycleManager.Resolve(options),
        "validate" => ReviewCycleManager.Validate(options),
        _ => throw new ContractException($"Unknown command: {options.Command}")
    };
    WriteOutput(result, options.Format);
    return result.Status == "PASS" ? 0 : 2;
}
catch (ContractException ex)
{
    WriteOutput(new CommandOutput(1, "FAIL", null, null, null, [ex.Message]), options.Format);
    return 2;
}
catch (Exception ex) when (ex is JsonException or InvalidDataException)
{
    WriteOutput(new CommandOutput(1, "FAIL", null, null, null, [ex.Message]), options.Format);
    return 2;
}
catch (Exception ex)
{
    WriteOutput(new CommandOutput(1, "ERROR", null, null, null, [ex.Message]), options.Format);
    return 1;
}

static void WriteOutput(CommandOutput output, string format)
{
    if (format == "json")
    {
        Console.WriteLine(JsonSerializer.Serialize(output, Json.Options));
        return;
    }

    Console.WriteLine($"Review cycle: {output.Status}");
    if (output.RoundNumber is not null) Console.WriteLine($"Round: {output.RoundNumber:000}");
    if (!string.IsNullOrWhiteSpace(output.Verdict)) Console.WriteLine($"Verdict: {output.Verdict}");
    if (!string.IsNullOrWhiteSpace(output.ArtifactDirectory)) Console.WriteLine($"Artifact directory: {output.ArtifactDirectory}");
    foreach (var error in output.Errors) Console.Error.WriteLine($"- {error}");
}

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-review-cycle.cs -- start --cycle <path> --repository owner/name --pr <number> --goal-context-path <path> --goal-context-sha <sha256> --base-oid <oid> --head-oid <oid> --started-at <ISO-8601> --review-thread-id <task-id> --implementation-thread-id <task-id> [--adaptive-result-reference <path-or-uri> --adaptive-thread-id <task-id>] [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-review-cycle.cs -- complete --cycle <path> --round-result <path> [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-review-cycle.cs -- resolve --cycle <path> --resolve-decision <decision-id> --decision-resolution <text> --decision-approved-by <identity> --decision-approved-at <ISO-8601> --approved-plan <path> [override options] [--format json|text]
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/manage-review-cycle.cs -- validate --cycle <path> [--format json|text]

Override options (all required together):
  --override-maximum-rounds <number>
  --override-approved-by <identity>
  --override-approved-at <ISO-8601>
  --override-reason <text>

Decision resolution (all required by resolve after HUMAN_DECISION_REQUIRED):
  --resolve-decision <decision-id>
  --decision-resolution <text>
  --decision-approved-by <identity>
  --decision-approved-at <ISO-8601>
  --approved-plan <candidate-path>

Rules:
  The default maximum is 3 rounds. A fourth or later round requires a recorded human override.
  A cycle fixes one Review Thread and one distinct Implementation Thread at round 1. Every later round must use the same IDs.
  If either task cannot be resumed, stop this cycle and require manual handling outside this utility.
  HUMAN_DECISION_REQUIRED never carries an executable Adaptive plan. Resolve records approval and copies a validated plan before Adaptive may run.
  Every round targets a new PR head OID and writes to a new round-NNN directory.
  This utility manages evidence only. It never starts review agents, Adaptive Implementation, or another round.

Exit codes: 0 success, 1 runtime error, 2 contract violation.
""");
}

static class ReviewCycleManager
{
    private const int SchemaVersion = 2;
    private const int LegacySchemaVersion = 1;
    private const string FullReviewMode = "full";
    private const string PurposeOnlyReviewMode = "purpose-only";
    private const int DefaultMaximumRounds = 3;
    private static readonly HashSet<string> FindingStates = new(StringComparer.Ordinal)
    {
        "new", "persistent", "resolved", "reopened"
    };
    private static readonly HashSet<string> ActiveFindingStates = new(StringComparer.Ordinal)
    {
        "new", "persistent", "reopened"
    };
    private static readonly string[] SharedCompletedArtifactRoles =
    [
        "review-context", "remote-patch", "goal-context-selection",
        "purpose-findings", "review-result", "completion-notification"
    ];

    public static CommandOutput Start(Options options)
    {
        RequireStartArguments(options);
        var requestedCyclePath = Path.GetFullPath(options.CyclePath!);
        var requestedCycleRoot = Path.GetDirectoryName(requestedCyclePath) ?? throw new ContractException("Cycle path has no parent directory.");
        RejectLinkedRootEntry(requestedCycleRoot);
        Directory.CreateDirectory(requestedCycleRoot);
        var cyclePath = Contained(requestedCycleRoot, Path.GetFileName(requestedCyclePath));
        var cycleRoot = Path.GetDirectoryName(cyclePath)!;

        ReviewCycle cycle;
        if (File.Exists(cyclePath))
        {
            cycle = ReadCycle(cyclePath);
            if (cycle.SchemaVersion == LegacySchemaVersion)
            {
                throw new ContractException("review-cycle schemaVersion 1 is read-only historical evidence; start a new schemaVersion 2 cycle instead of appending a round.");
            }
            ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: true);
            Equal("repository", cycle.Repository, options.Repository!);
            Equal("pull request", cycle.PullRequest, options.PullRequest);
            Equal("Goal Context path", cycle.GoalContext.Path, NormalizeSlash(options.GoalContextPath!));
            Equal("Goal Context SHA-256", cycle.GoalContext.NormalizedSha256, options.GoalContextSha!);
        }
        else
        {
            var reviewBinding = NewThreadBinding(options.ReviewThreadId!, "review-thread-id");
            var implementationBinding = NewThreadBinding(options.ImplementationThreadId!, "implementation-thread-id");
            EnsureDistinctRoleThreads(reviewBinding.ThreadId, implementationBinding.ThreadId);
            cycle = new ReviewCycle
            {
                SchemaVersion = SchemaVersion,
                Repository = options.Repository!,
                PullRequest = options.PullRequest,
                GoalContext = new GoalContextIdentity
                {
                    Path = NormalizeSlash(options.GoalContextPath!),
                    NormalizedSha256 = options.GoalContextSha!
                },
                DefaultMaximumRounds = DefaultMaximumRounds,
                EffectiveMaximumRounds = DefaultMaximumRounds,
                Status = "NOT_STARTED",
                RoleThreads = new RoleThreads { Review = reviewBinding, Implementation = implementationBinding }
            };
        }

        var nextRound = cycle.Rounds.Count + 1;
        if (cycle.Rounds.Count > 0)
        {
            var previous = cycle.Rounds[^1];
            if (previous.Status == "IN_PROGRESS") throw new ContractException("The current review round is still in progress.");
            if (previous.Verdict is "REVIEW_COMPLETE" or "BLOCKED")
            {
                throw new ContractException($"A new round cannot start after {previous.Verdict}.");
            }
            EnsurePreviousDecisionResolved(cycle, previous, nextRound);
            if (string.IsNullOrWhiteSpace(options.AdaptiveResultReference))
            {
                throw new ContractException("Round 2 or later requires --adaptive-result-reference from the separately completed Adaptive turn.");
            }
            if (string.IsNullOrWhiteSpace(options.AdaptiveThreadId))
            {
                throw new ContractException("Round 2 or later requires --adaptive-thread-id identifying the explicit Implementation Thread turn.");
            }
        }
        else if (!string.IsNullOrWhiteSpace(options.AdaptiveResultReference))
        {
            throw new ContractException("Round 1 cannot declare a previous Adaptive result reference.");
        }
        else if (!string.IsNullOrWhiteSpace(options.AdaptiveThreadId))
        {
            throw new ContractException("Round 1 cannot declare a previous Adaptive thread ID.");
        }
        else
        {
            RejectStartOnlyHumanOptions(options);
        }
        ValidateStartThreadIdentity(cycle, options, nextRound);
        if (nextRound > cycle.EffectiveMaximumRounds)
        {
            throw new ContractException($"Round {nextRound} exceeds effective maximum {cycle.EffectiveMaximumRounds}; a complete human override is required.");
        }
        if (cycle.Rounds.Any(round => string.Equals(round.HeadOid, options.HeadOid, StringComparison.OrdinalIgnoreCase)))
        {
            throw new ContractException($"The PR head {options.HeadOid} was already reviewed; duplicate same-head rounds are not allowed.");
        }

        var roundDirectoryName = $"round-{nextRound:000}";
        var roundDirectory = Contained(cycleRoot, roundDirectoryName);
        if (Directory.Exists(roundDirectory) || File.Exists(roundDirectory))
        {
            throw new ContractException($"Round artifact directory already exists and will not be overwritten: {roundDirectoryName}");
        }

        var startedAt = ParseTimestamp(options.StartedAt!, "started-at");
        if (cycle.Rounds.LastOrDefault() is { } previousRound)
        {
            if (startedAt < ParseTimestamp(previousRound.CompletedAt!, "previous round completedAt"))
            {
                throw new ContractException("New round startedAt precedes the previous round completion.");
            }
            if (previousRound.Verdict == "HUMAN_DECISION_REQUIRED")
            {
                var decision = cycle.HumanDecisions.Single(item => item.RoundNumber == previousRound.RoundNumber && item.Status == "RESOLVED");
                if (startedAt < ParseTimestamp(decision.ApprovedAt!, "human decision approvedAt"))
                {
                    throw new ContractException("New round startedAt precedes the human decision approval and approved Adaptive handoff.");
                }
            }
        }
        var roundRecord = new RoundRecord
        {
            RoundNumber = nextRound,
            ReviewMode = ReviewModeFor(nextRound),
            ArtifactDirectory = roundDirectoryName,
            BaseOid = options.BaseOid!,
            HeadOid = options.HeadOid!,
            PreviousRound = nextRound == 1 ? null : nextRound - 1,
            StartedAt = startedAt.ToString("O"),
            Status = "IN_PROGRESS",
            AdaptiveResultReference = EmptyToNull(options.AdaptiveResultReference),
            ReviewThreadId = options.ReviewThreadId!,
            AdaptiveThreadId = EmptyToNull(options.AdaptiveThreadId)
        };

        Directory.CreateDirectory(roundDirectory);
        try
        {
            cycle.Rounds.Add(roundRecord);
            cycle.CurrentRound = nextRound;
            cycle.Status = "IN_PROGRESS";
            ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: false);
            SaveCycle(cyclePath, cycle);
        }
        catch
        {
            if (!Directory.EnumerateFileSystemEntries(roundDirectory).Any()) Directory.Delete(roundDirectory);
            throw;
        }

        return new CommandOutput(1, "PASS", nextRound, null, NormalizeSlash(Path.GetRelativePath(cycleRoot, roundDirectory)), []);
    }

    public static CommandOutput Complete(Options options)
    {
        if (string.IsNullOrWhiteSpace(options.CyclePath) || string.IsNullOrWhiteSpace(options.RoundResultPath))
        {
            throw new ContractException("complete requires --cycle and --round-result.");
        }

        var requestedCyclePath = Path.GetFullPath(options.CyclePath);
        var requestedCycleRoot = Path.GetDirectoryName(requestedCyclePath) ?? throw new ContractException("Cycle path has no parent directory.");
        var cyclePath = Contained(requestedCycleRoot, Path.GetFileName(requestedCyclePath));
        var cycle = ReadCycle(cyclePath);
        RejectLegacyMutation(cycle, "complete");
        ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: false);
        if (cycle.Rounds.Count == 0 || cycle.Rounds[^1].Status != "IN_PROGRESS")
        {
            throw new ContractException("No in-progress review round is available to complete.");
        }

        var round = cycle.Rounds[^1];
        var cycleRoot = Path.GetDirectoryName(cyclePath)!;
        var expectedRoundDirectory = Contained(cycleRoot, round.ArtifactDirectory);
        var resultPath = Contained(cycleRoot, Path.GetFullPath(options.RoundResultPath));
        if (!File.Exists(resultPath)) throw new ContractException($"Round result does not exist: {resultPath}");
        if (!IsContained(expectedRoundDirectory, resultPath)) throw new ContractException("Round result must be inside the current round directory.");

        var result = ReadJson<RoundResult>(resultPath);
        if (result.SchemaVersion != SchemaVersion) throw new ContractException("round-result schemaVersion must be 2.");
        Equal("round-result round number", round.RoundNumber, result.RoundNumber);
        Equal("round-result review mode", round.ReviewMode, result.ReviewMode);
        Equal("round-result base OID", round.BaseOid, result.BaseOid);
        Equal("round-result head OID", round.HeadOid, result.HeadOid);
        var completedAt = ParseTimestamp(result.CompletedAt, "completedAt");
        if (completedAt < ParseTimestamp(round.StartedAt, "round startedAt")) throw new ContractException("completedAt precedes startedAt.");

        if (!string.IsNullOrWhiteSpace(result.BlockedReason) && !string.IsNullOrWhiteSpace(result.HumanDecisionReason))
        {
            throw new ContractException("round-result cannot declare blockedReason and humanDecisionReason together.");
        }
        var artifactRecords = ValidateArtifacts(cycleRoot, expectedRoundDirectory, result.Artifacts);
        List<FindingDeltaEntry> delta;
        if (!string.IsNullOrWhiteSpace(result.BlockedReason))
        {
            if (result.FindingDelta.Count != 0) throw new ContractException("BLOCKED round must not declare finding transitions.");
            delta = [];
        }
        else
        {
            delta = ValidateFindingDelta(cycle, round, result.FindingDelta);
        }
        var actionableCount = delta.Count(item => ActiveFindingStates.Contains(item.State));
        var verdict = ComputeVerdict(cycle, round.RoundNumber, actionableCount, result.BlockedReason, result.HumanDecisionReason);
        Equal("round-result verdict", verdict, result.Verdict);
        ValidateArtifactRoles(round.ReviewMode, verdict, actionableCount, artifactRecords);
        ValidateSourceCoverage(delta, result.SourceCoverage);
        ValidateArtifactContents(cycle, round, result, cycleRoot, artifactRecords);
        ValidateNotification(cycle, round.RoundNumber, verdict, result.Notification);
        ValidateNotificationArtifact(cycleRoot, artifactRecords, round.RoundNumber, verdict, result.Notification.ResultUri);

        artifactRecords.Add(new ArtifactRecord
        {
            Role = "round-result",
            Path = NormalizeSlash(Path.GetRelativePath(cycleRoot, resultPath)),
            NormalizedSha256 = Hash(resultPath)
        });

        round.CompletedAt = completedAt.ToString("O");
        round.Status = "COMPLETED";
        round.Verdict = verdict;
        round.ActionableFindingCount = actionableCount;
        round.Artifacts = artifactRecords;
        round.Notification = result.Notification;
        round.FindingDelta = delta;
        round.SourceCoverage = result.SourceCoverage;
        round.HumanDecisionReason = EmptyToNull(result.HumanDecisionReason ?? result.BlockedReason);
        cycle.Status = verdict;
        UpdateFindingLedger(cycle, round.RoundNumber, delta);

        if (verdict == "HUMAN_DECISION_REQUIRED")
        {
            cycle.HumanDecisions.Add(new HumanDecision
            {
                DecisionId = $"HD-{round.RoundNumber:000}",
                RoundNumber = round.RoundNumber,
                Status = "PENDING",
                Reason = !string.IsNullOrWhiteSpace(result.HumanDecisionReason)
                    ? result.HumanDecisionReason!
                    : $"Actionable findings remain at effective maximum round {cycle.EffectiveMaximumRounds}."
            });
        }

        ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: false);
        SaveCycle(cyclePath, cycle);
        return new CommandOutput(1, "PASS", round.RoundNumber, verdict, round.ArtifactDirectory, []);
    }

    public static CommandOutput Resolve(Options options)
    {
        RequireResolveArguments(options);
        var requestedCyclePath = Path.GetFullPath(options.CyclePath!);
        var requestedCycleRoot = Path.GetDirectoryName(requestedCyclePath) ?? throw new ContractException("Cycle path has no parent directory.");
        var cyclePath = Contained(requestedCycleRoot, Path.GetFileName(requestedCyclePath));
        var cycleRoot = Path.GetDirectoryName(cyclePath)!;
        var cycle = ReadCycle(cyclePath);
        RejectLegacyMutation(cycle, "resolve");
        ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: true);

        var round = cycle.Rounds.LastOrDefault()
            ?? throw new ContractException("Human decision resolution requires a completed review round.");
        if (round.Verdict != "HUMAN_DECISION_REQUIRED")
        {
            throw new ContractException("Decision resolution is allowed only after HUMAN_DECISION_REQUIRED.");
        }
        var pending = cycle.HumanDecisions.Where(item => item.Status == "PENDING").ToList();
        if (pending.Count != 1) throw new ContractException($"Expected exactly one pending human decision, observed {pending.Count}.");
        var decision = pending[0];
        Equal("resolved human decision ID", decision.DecisionId, options.ResolveDecision!);
        Equal("resolved human decision round", round.RoundNumber, decision.RoundNumber);

        var approvedAt = ParseTimestamp(options.DecisionApprovedAt!, "decision-approved-at");
        if (approvedAt < ParseTimestamp(round.CompletedAt!, "decision-producing round completedAt"))
        {
            throw new ContractException("Human decision approval precedes the decision-producing round completion.");
        }

        var nextRound = round.RoundNumber + 1;
        var canonicalPlanReference = $"{round.ArtifactDirectory}/approved-review-plan.md";
        var canonicalPlanPath = Contained(cycleRoot, canonicalPlanReference);
        var roundDirectory = Contained(cycleRoot, round.ArtifactDirectory);
        if (!IsContained(roundDirectory, canonicalPlanPath)) throw new ContractException("Approved plan must stay inside the decision-producing round directory.");
        if (File.Exists(canonicalPlanPath) || Directory.Exists(canonicalPlanPath))
        {
            throw new ContractException($"Approved plan already exists and will not be overwritten: {canonicalPlanReference}");
        }

        var candidatePath = Path.GetFullPath(options.ApprovedPlan!);
        if (!File.Exists(candidatePath)) throw new ContractException($"Approved plan candidate does not exist: {candidatePath}");
        ValidateReviewPlan(cycle, round, new RoundResult
        {
            Verdict = "APPROVED_FOR_ADAPTIVE_IMPLEMENTATION",
            FindingDelta = round.FindingDelta,
            SourceCoverage = round.SourceCoverage
        }, candidatePath, canonicalPlanReference);

        decision.Status = "RESOLVED";
        decision.Resolution = options.DecisionResolution;
        decision.ApprovedBy = options.DecisionApprovedBy;
        decision.ApprovedAt = approvedAt.ToString("O");
        decision.ResolvedForRound = nextRound;
        decision.ApprovedPlanReference = canonicalPlanReference;
        ApplyOverride(options, cycle, round, decision, nextRound);

        try
        {
            File.Copy(candidatePath, canonicalPlanPath, overwrite: false);
            decision.ApprovedPlanNormalizedSha256 = Hash(canonicalPlanPath);
            cycle.Status = "APPROVED_FOR_ADAPTIVE_IMPLEMENTATION";
            ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: true);
            SaveCycle(cyclePath, cycle);
        }
        catch
        {
            if (File.Exists(canonicalPlanPath)) File.Delete(canonicalPlanPath);
            throw;
        }

        return new CommandOutput(1, "PASS", round.RoundNumber, "APPROVED_FOR_ADAPTIVE_IMPLEMENTATION", round.ArtifactDirectory, []);
    }

    public static CommandOutput Validate(Options options)
    {
        if (string.IsNullOrWhiteSpace(options.CyclePath)) throw new ContractException("validate requires --cycle.");
        var requestedCyclePath = Path.GetFullPath(options.CyclePath);
        var requestedCycleRoot = Path.GetDirectoryName(requestedCyclePath) ?? throw new ContractException("Cycle path has no parent directory.");
        var cyclePath = Contained(requestedCycleRoot, Path.GetFileName(requestedCyclePath));
        var cycle = ReadCycle(cyclePath);
        if (cycle.SchemaVersion == LegacySchemaVersion)
        {
            ValidateLegacyCycleReadOnly(cyclePath, cycle);
            var legacyCurrent = cycle.Rounds.LastOrDefault();
            return new CommandOutput(1, "PASS", legacyCurrent?.RoundNumber, legacyCurrent?.Verdict, legacyCurrent?.ArtifactDirectory, []);
        }
        ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: false);
        var current = cycle.Rounds.LastOrDefault();
        return new CommandOutput(1, "PASS", current?.RoundNumber, current?.Verdict, current?.ArtifactDirectory, []);
    }

    private static void RequireStartArguments(Options options)
    {
        if (string.IsNullOrWhiteSpace(options.CyclePath) || string.IsNullOrWhiteSpace(options.Repository)
            || options.PullRequest <= 0 || string.IsNullOrWhiteSpace(options.GoalContextPath)
            || string.IsNullOrWhiteSpace(options.GoalContextSha) || string.IsNullOrWhiteSpace(options.BaseOid)
            || string.IsNullOrWhiteSpace(options.HeadOid) || string.IsNullOrWhiteSpace(options.StartedAt)
            || string.IsNullOrWhiteSpace(options.ReviewThreadId) || string.IsNullOrWhiteSpace(options.ImplementationThreadId))
        {
            throw new ContractException("start requires cycle, repository, PR, Goal Context identity, base/head OID, started-at, review-thread-id, and implementation-thread-id.");
        }
        if (!Regex.IsMatch(options.Repository, @"^[^/\s]+/[^/\s]+$")) throw new ContractException("repository must be owner/name.");
        if (!Regex.IsMatch(options.GoalContextSha, "^[0-9a-f]{64}$")) throw new ContractException("goal-context-sha must be lowercase SHA-256.");
        RequireOid(options.BaseOid, "base-oid");
        RequireOid(options.HeadOid, "head-oid");
        RequireThreadId(options.ReviewThreadId, "review-thread-id");
        RequireThreadId(options.ImplementationThreadId, "implementation-thread-id");
        if (!string.IsNullOrWhiteSpace(options.AdaptiveThreadId)) RequireThreadId(options.AdaptiveThreadId, "adaptive-thread-id");
        RejectStartOnlyHumanOptions(options);
    }

    private static void RequireResolveArguments(Options options)
    {
        if (string.IsNullOrWhiteSpace(options.CyclePath) || string.IsNullOrWhiteSpace(options.ResolveDecision)
            || string.IsNullOrWhiteSpace(options.DecisionResolution) || string.IsNullOrWhiteSpace(options.DecisionApprovedBy)
            || string.IsNullOrWhiteSpace(options.DecisionApprovedAt) || string.IsNullOrWhiteSpace(options.ApprovedPlan))
        {
            throw new ContractException("resolve requires cycle, decision ID, resolution, approver, approval timestamp, and approved plan candidate.");
        }
        if (!string.IsNullOrWhiteSpace(options.AdaptiveResultReference))
        {
            throw new ContractException("resolve records human approval before Adaptive execution and cannot accept an Adaptive result reference.");
        }
    }

    private static void ApplyOverride(Options options, ReviewCycle cycle, RoundRecord previous, HumanDecision decision, int nextRound)
    {
        var supplied = new[]
        {
            options.OverrideMaximumRounds > 0,
            !string.IsNullOrWhiteSpace(options.OverrideApprovedBy),
            !string.IsNullOrWhiteSpace(options.OverrideApprovedAt),
            !string.IsNullOrWhiteSpace(options.OverrideReason)
        };
        if (supplied.Any(value => value) && supplied.Any(value => !value))
        {
            throw new ContractException("All maximum-round override fields are required together.");
        }
        if (!supplied.All(value => value))
        {
            if (nextRound > cycle.EffectiveMaximumRounds)
            {
                throw new ContractException("Resolving a maximum-round decision requires a complete maximum-round override before Adaptive execution.");
            }
            return;
        }
        if (nextRound < 4)
        {
            throw new ContractException("Maximum-round override is accepted only for round 4 or later.");
        }
        if (previous.Verdict != "HUMAN_DECISION_REQUIRED" || previous.RoundNumber < cycle.EffectiveMaximumRounds)
        {
            throw new ContractException("Maximum-round override requires the previous round to reach the effective maximum with HUMAN_DECISION_REQUIRED.");
        }
        if (options.OverrideMaximumRounds <= cycle.EffectiveMaximumRounds || options.OverrideMaximumRounds < nextRound)
        {
            throw new ContractException("override maximum must increase the effective maximum and include the next round.");
        }

        var approvedAt = ParseTimestamp(options.OverrideApprovedAt!, "override-approved-at");
        if (approvedAt < ParseTimestamp(decision.ApprovedAt!, "decision-approved-at"))
        {
            throw new ContractException("Maximum-round override approval precedes the human decision approval.");
        }
        cycle.Overrides.Add(new RoundOverride
        {
            StartingRound = nextRound,
            DecisionId = decision.DecisionId,
            ApprovedBy = options.OverrideApprovedBy!,
            ApprovedAt = approvedAt.ToString("O"),
            Reason = options.OverrideReason!,
            MaximumRounds = options.OverrideMaximumRounds
        });
        cycle.EffectiveMaximumRounds = options.OverrideMaximumRounds;
    }

    private static void EnsurePreviousDecisionResolved(ReviewCycle cycle, RoundRecord previous, int nextRound)
    {
        if (previous.Verdict != "HUMAN_DECISION_REQUIRED") return;
        var decision = cycle.HumanDecisions.SingleOrDefault(item => item.RoundNumber == previous.RoundNumber && item.Status == "RESOLVED");
        if (decision is null || decision.ResolvedForRound != nextRound || string.IsNullOrWhiteSpace(decision.ApprovedPlanReference))
        {
            throw new ContractException("A pending human decision must be resolved with a validated approved plan before Adaptive execution and the next round.");
        }
    }

    private static void RejectStartOnlyHumanOptions(Options options)
    {
        if (DecisionResolutionFields(options).Any(value => value) || OverrideFields(options).Any(value => value)
            || !string.IsNullOrWhiteSpace(options.ApprovedPlan))
        {
            throw new ContractException("Human decision resolution and maximum-round override must use the separate resolve command before Adaptive execution.");
        }
    }

    private static bool[] DecisionResolutionFields(Options options) =>
    [
        !string.IsNullOrWhiteSpace(options.ResolveDecision),
        !string.IsNullOrWhiteSpace(options.DecisionResolution),
        !string.IsNullOrWhiteSpace(options.DecisionApprovedBy),
        !string.IsNullOrWhiteSpace(options.DecisionApprovedAt)
    ];

    private static bool[] OverrideFields(Options options) =>
    [
        options.OverrideMaximumRounds > 0,
        !string.IsNullOrWhiteSpace(options.OverrideApprovedBy),
        !string.IsNullOrWhiteSpace(options.OverrideApprovedAt),
        !string.IsNullOrWhiteSpace(options.OverrideReason)
    ];

    private static List<ArtifactRecord> ValidateArtifacts(string cycleRoot, string roundDirectory, List<ArtifactRecord> artifacts)
    {
        var results = new List<ArtifactRecord>();
        var roles = new HashSet<string>(StringComparer.Ordinal);
        foreach (var artifact in artifacts)
        {
            if (string.IsNullOrWhiteSpace(artifact.Role) || !roles.Add(artifact.Role))
            {
                throw new ContractException($"Artifact roles must be non-empty and unique: {artifact.Role}");
            }
            if (!Regex.IsMatch(artifact.NormalizedSha256 ?? string.Empty, "^[0-9a-f]{64}$"))
            {
                throw new ContractException($"Artifact hash is invalid for role {artifact.Role}.");
            }
            var path = Contained(cycleRoot, artifact.Path);
            if (!IsContained(roundDirectory, path)) throw new ContractException($"Artifact must stay inside the current round directory: {artifact.Path}");
            if (!File.Exists(path)) throw new ContractException($"Artifact does not exist: {artifact.Path}");
            Equal($"artifact hash {artifact.Role}", artifact.NormalizedSha256, Hash(path));
            results.Add(new ArtifactRecord
            {
                Role = artifact.Role,
                Path = NormalizeSlash(Path.GetRelativePath(cycleRoot, path)),
                NormalizedSha256 = artifact.NormalizedSha256!
            });
        }
        return results;
    }

    private static void ValidateArtifactContents(ReviewCycle cycle, RoundRecord round, RoundResult result, string cycleRoot, List<ArtifactRecord> artifacts)
    {
        var byRole = artifacts.ToDictionary(item => item.Role, StringComparer.Ordinal);
        var observedSources = new HashSet<string>(StringComparer.Ordinal);
        if (result.Verdict != "BLOCKED")
        {
            var externalSources = ValidateReviewContext(
                cycle,
                round,
                ArtifactPath(cycleRoot, byRole, "review-context"),
                ArtifactPath(cycleRoot, byRole, "remote-patch"),
                observedSources);
            ValidateGoalContextSelection(cycle, ArtifactPath(cycleRoot, byRole, "goal-context-selection"));
            if (round.ReviewMode == FullReviewMode)
            {
                ValidateReviewMarkdown(cycle, round, result.Verdict, ArtifactPath(cycleRoot, byRole, "local-findings"), false, observedSources, result.FindingDelta);
            }
            ValidateReviewMarkdown(cycle, round, result.Verdict, ArtifactPath(cycleRoot, byRole, "purpose-findings"), true, observedSources, result.FindingDelta);
            if (round.ReviewMode == PurposeOnlyReviewMode)
            {
                ValidatePurposeOnlySourceCoverage(externalSources, result.SourceCoverage);
            }
            if (byRole.TryGetValue("review-plan", out var reviewPlan))
            {
                ValidateReviewPlan(cycle, round, result, ArtifactPath(cycleRoot, byRole, "review-plan"), reviewPlan.Path);
            }
        }

        var reviewResult = ReadJson<ReviewResultArtifact>(ArtifactPath(cycleRoot, byRole, "review-result"));
        if (reviewResult.SchemaVersion != SchemaVersion) throw new ContractException("review-result schemaVersion must be 2.");
        Equal("review-result repository", cycle.Repository, reviewResult.Repository);
        Equal("review-result pull request", cycle.PullRequest, reviewResult.PullRequest);
        Equal("review-result round number", round.RoundNumber, reviewResult.RoundNumber);
        Equal("review-result review mode", round.ReviewMode, reviewResult.ReviewMode);
        Equal("review-result base OID", round.BaseOid, reviewResult.BaseOid);
        Equal("review-result head OID", round.HeadOid, reviewResult.HeadOid);
        Equal("review-result Goal Context path", cycle.GoalContext.Path, reviewResult.GoalContext.Path);
        Equal("review-result Goal Context SHA-256", cycle.GoalContext.NormalizedSha256, reviewResult.GoalContext.NormalizedSha256);
        Equal("review-result verdict", result.Verdict, reviewResult.Verdict);
        EqualFindingDelta("review-result finding delta", result.FindingDelta, reviewResult.FindingDelta);
        EqualSourceCoverage("review-result source coverage", result.SourceCoverage, reviewResult.SourceCoverage);

        var expectedBindings = artifacts
            .Where(item => item.Role is not ("review-result" or "round-result" or "completion-notification"))
            .ToDictionary(item => item.Role, item => item.NormalizedSha256, StringComparer.Ordinal);
        if (reviewResult.ArtifactBindings.Count != expectedBindings.Count) throw new ContractException("review-result artifact bindings do not cover the exact planner inputs and outputs.");
        foreach (var binding in reviewResult.ArtifactBindings)
        {
            if (!expectedBindings.Remove(binding.Role, out var expectedHash)) throw new ContractException($"review-result has an unknown or duplicate artifact binding: {binding.Role}");
            Equal($"review-result artifact binding {binding.Role}", expectedHash, binding.NormalizedSha256);
        }
        if (expectedBindings.Count != 0) throw new ContractException($"review-result is missing artifact bindings: {string.Join(", ", expectedBindings.Keys)}");

        if (result.Verdict != "BLOCKED")
        {
            var coveredSources = result.SourceCoverage.Select(item => item.SourceId).ToHashSet(StringComparer.Ordinal);
            if (!observedSources.SetEquals(coveredSources))
            {
                var missing = observedSources.Except(coveredSources, StringComparer.Ordinal);
                var extra = coveredSources.Except(observedSources, StringComparer.Ordinal);
                throw new ContractException($"Round source coverage does not exactly match review artifacts; missing [{string.Join(", ", missing)}], extra [{string.Join(", ", extra)}].");
            }
        }
    }

    private static string ArtifactPath(string cycleRoot, Dictionary<string, ArtifactRecord> artifacts, string role)
    {
        if (!artifacts.TryGetValue(role, out var artifact)) throw new ContractException($"Missing artifact needed for content validation: {role}");
        return Contained(cycleRoot, artifact.Path);
    }

    private static HashSet<string> ValidateReviewContext(ReviewCycle cycle, RoundRecord round, string path, string remotePatchPath, HashSet<string> observedSources)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        Equal("review-context schema version", "1.0", RequiredString(root, "schemaVersion", "review-context"));
        var target = RequiredObject(root, "target", "review-context");
        Equal("review-context repository", cycle.Repository, RequiredString(target, "repository", "review-context target"));
        Equal("review-context pull request", cycle.PullRequest, RequiredInt(target, "pullRequest", "review-context target"));
        Equal("review-context base OID", round.BaseOid, RequiredString(target, "baseRefOid", "review-context target"));
        Equal("review-context head OID", round.HeadOid, RequiredString(target, "headRefOid", "review-context target"));

        var contextArtifacts = RequiredObject(root, "artifacts", "review-context");
        var remotePatchPointer = RequiredString(contextArtifacts, "remotePatch", "review-context artifacts");
        if (Path.IsPathRooted(remotePatchPointer)) throw new ContractException("review-context artifacts.remotePatch must be relative to review-context.json.");
        var expectedRemotePatchPointer = NormalizeSlash(Path.GetRelativePath(Path.GetDirectoryName(path)!, remotePatchPath));
        Equal("review-context remote patch path", expectedRemotePatchPointer, NormalizeSlash(remotePatchPointer));

        var sources = RequiredObject(root, "sources", "review-context");
        var pullRequest = RequiredObject(sources, "pullRequest", "review-context sources");
        Equal("review-context source PR", cycle.PullRequest, RequiredInt(pullRequest, "number", "review-context pullRequest"));
        Equal("review-context source base OID", round.BaseOid, RequiredString(pullRequest, "baseRefOid", "review-context pullRequest"));
        Equal("review-context source head OID", round.HeadOid, RequiredString(pullRequest, "headRefOid", "review-context pullRequest"));

        var externalSources = new HashSet<string>(StringComparer.Ordinal);
        foreach (var collectionName in new[] { "reviews", "issueComments", "inlineComments", "checks" })
        {
            if (!sources.TryGetProperty(collectionName, out var collection) || collection.ValueKind != JsonValueKind.Array)
            {
                throw new ContractException($"review-context sources.{collectionName} must be an array.");
            }
            foreach (var source in collection.EnumerateArray())
            {
                var sourceId = RequiredString(source, "sourceId", $"review-context {collectionName}");
                if (!observedSources.Add(sourceId)) throw new ContractException($"Duplicate source ID in review-context: {sourceId}");
                externalSources.Add(sourceId);
                _ = ClassifySourceHeadRelationship(cycle, round, source, sourceId);
                ValidateOptionalSourceOid(source, "original_commit_id", sourceId);
            }
        }
        if (round.ReviewMode == PurposeOnlyReviewMode)
        {
            var wait = RequiredObject(root, "copilotReviewWait", "review-context");
            Equal("purpose-only Copilot wait status", "disabled", RequiredString(wait, "waitStatus", "review-context copilotReviewWait"));
        }
        return externalSources;
    }

    private static string ClassifySourceHeadRelationship(ReviewCycle cycle, RoundRecord round, JsonElement source, string sourceId)
    {
        if (!source.TryGetProperty("commit_id", out var commit) || commit.ValueKind == JsonValueKind.Null) return "unknown";
        if (commit.ValueKind != JsonValueKind.String) throw new ContractException($"review-context {sourceId} commit_id must be a string or null.");
        var commitOid = commit.GetString();
        if (string.IsNullOrWhiteSpace(commitOid)) return "unknown";
        RequireOid(commitOid, $"review-context {sourceId} commit_id");
        if (string.Equals(commitOid, round.HeadOid, StringComparison.Ordinal)) return "current";
        if (cycle.Rounds.Any(item => item.RoundNumber < round.RoundNumber && string.Equals(item.HeadOid, commitOid, StringComparison.Ordinal)))
        {
            return "historical";
        }
        return "unknown";
    }

    private static void ValidateOptionalSourceOid(JsonElement source, string property, string sourceId)
    {
        if (!source.TryGetProperty(property, out var value) || value.ValueKind == JsonValueKind.Null) return;
        if (value.ValueKind != JsonValueKind.String) throw new ContractException($"review-context {sourceId} {property} must be a string or null.");
        var oid = value.GetString();
        if (!string.IsNullOrWhiteSpace(oid)) RequireOid(oid, $"review-context {sourceId} {property}");
    }

    private static void ValidateGoalContextSelection(ReviewCycle cycle, string path)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var root = document.RootElement;
        Equal("Goal Context selection schema version", 2, RequiredInt(root, "schemaVersion", "goal-context-selection"));
        Equal("Goal Context selection status", "SELECTED", RequiredString(root, "selectionStatus", "goal-context-selection"));
        Equal("Goal Context selection path", cycle.GoalContext.Path, RequiredString(root, "selectedPath", "goal-context-selection"));
        Equal("Goal Context selection SHA-256", cycle.GoalContext.NormalizedSha256, RequiredString(root, "contentSha256", "goal-context-selection"));
        Equal("Goal Context selection validation", "PASS", RequiredString(root, "validation", "goal-context-selection"));
        _ = RequiredString(root, "selectionMode", "goal-context-selection");
        if (RequiredInt(root, "validationContractVersion", "goal-context-selection") <= 0)
        {
            throw new ContractException("Goal Context selection validationContractVersion must be positive.");
        }
        var validationMode = RequiredString(root, "validationMode", "goal-context-selection");
        var lifecycleStatus = RequiredString(root, "lifecycleStatus", "goal-context-selection");
        Equal("Goal Context selection sensitive data review", "passed", RequiredString(root, "sensitiveDataReview", "goal-context-selection"));
        var draftOverride = RequiredBool(root, "draftOverride", "goal-context-selection");
        if (validationMode == "strict")
        {
            Equal("strict Goal Context lifecycle", "human-reviewed", lifecycleStatus);
            Equal("strict Goal Context draft override", false, draftOverride);
        }
        else if (validationMode == "draft")
        {
            Equal("draft Goal Context lifecycle", "draft", lifecycleStatus);
            Equal("draft Goal Context override", true, draftOverride);
        }
        else
        {
            throw new ContractException($"Goal Context selection validationMode is invalid: {validationMode}");
        }
    }

    private static void ValidateReviewMarkdown(ReviewCycle cycle, RoundRecord round, string roundVerdict, string path, bool purpose, HashSet<string> observedSources, List<FindingDeltaEntry> delta)
    {
        var content = File.ReadAllText(path);
        var reviewVerdict = MarkdownValue(content, "Verdict");
        if (!purpose)
        {
            Equal("local findings verdict", "REVIEWED", reviewVerdict);
        }
        else if (reviewVerdict != "PURPOSE_REVIEWED" && !(roundVerdict == "HUMAN_DECISION_REQUIRED" && reviewVerdict == "HUMAN_DECISION_REQUIRED"))
        {
            throw new ContractException($"Purpose findings verdict {reviewVerdict} is incompatible with round verdict {roundVerdict}.");
        }
        Equal($"{(purpose ? "purpose" : "local")} findings repository", cycle.Repository, MarkdownValue(content, "Repository"));
        Equal($"{(purpose ? "purpose" : "local")} findings PR", cycle.PullRequest.ToString(), MarkdownValue(content, "PR"));
        RequireMarkdownOid(content, "Base branch / OID", round.BaseOid);
        RequireMarkdownOid(content, "Head branch / OID", round.HeadOid);
        if (purpose)
        {
            Equal("purpose findings Goal Context", cycle.GoalContext.Path, MarkdownValue(content, "Goal Context"));
            Equal("purpose findings Goal Context SHA-256", cycle.GoalContext.NormalizedSha256, MarkdownValue(content, "Goal Context SHA-256"));
            if (round.ReviewMode == PurposeOnlyReviewMode)
            {
                ValidatePriorFindingAssessments(cycle, round, content, delta);
            }
        }
        var prefix = purpose ? "PUR" : "LR";
        foreach (Match match in Regex.Matches(content, $@"(?m)^\|\s*(?<id>{prefix}-\d+)\s*\|"))
        {
            if (!observedSources.Add(match.Groups["id"].Value)) throw new ContractException($"Duplicate reviewer finding source ID: {match.Groups["id"].Value}");
        }
    }

    private static string MarkdownValue(string content, string label)
    {
        var match = Regex.Match(content, $@"(?m)^-\s*{Regex.Escape(label)}:\s*(?<value>\S.*?)\s*$");
        if (!match.Success) throw new ContractException($"Review artifact is missing a non-empty '{label}' identity field.");
        return match.Groups["value"].Value.Trim();
    }

    private static void RequireMarkdownOid(string content, string label, string expectedOid)
    {
        var value = MarkdownValue(content, label);
        if (!Regex.IsMatch(value, $@"/\s*{Regex.Escape(expectedOid)}$")) throw new ContractException($"Review artifact {label} does not match OID {expectedOid}.");
    }

    private static void ValidateReviewPlan(ReviewCycle cycle, RoundRecord round, RoundResult result, string path, string relativePath)
    {
        var content = File.ReadAllText(path);
        Equal("review plan verdict", result.Verdict, MarkdownValue(content, "Verdict"));
        Equal("review plan repository", cycle.Repository, MarkdownValue(content, "Repository"));
        Equal("review plan PR", cycle.PullRequest.ToString(), MarkdownValue(content, "PR"));
        RequireMarkdownOid(content, "Base branch / OID", round.BaseOid);
        RequireMarkdownOid(content, "Head branch / OID", round.HeadOid);
        Equal("review plan Goal Context", cycle.GoalContext.Path, MarkdownValue(content, "Selected Goal Context"));
        Equal("review plan Goal Context SHA-256", cycle.GoalContext.NormalizedSha256, MarkdownValue(content, "Goal Context SHA-256"));

        var intentMatch = Regex.Match(content, @"(?ms)^```yaml\s*\n(?<yaml>.*?)^```\s*$");
        if (!intentMatch.Success || !Regex.IsMatch(intentMatch.Groups["yaml"].Value, @"(?m)^implementation_intent:\s*$"))
        {
            throw new ContractException("Review plan must contain the canonical implementation_intent YAML block.");
        }
        var yaml = intentMatch.Groups["yaml"].Value;
        var goal = IntentField(yaml, "goal");
        var scope = IntentField(yaml, "scope");
        var acceptance = IntentField(yaml, "acceptance");
        var planReference = IntentField(yaml, "plan_reference");
        var goalContextReference = IntentField(yaml, "goal_context_reference");
        if (string.IsNullOrWhiteSpace(goal) || string.IsNullOrWhiteSpace(scope) || string.IsNullOrWhiteSpace(acceptance))
        {
            throw new ContractException("Review plan implementation_intent requires non-empty goal, scope, and acceptance.");
        }
        Equal("review plan implementation_intent plan_reference", NormalizeSlash(relativePath), NormalizeSlash(planReference));
        Equal("review plan implementation_intent goal_context_reference", cycle.GoalContext.Path, NormalizeSlash(goalContextReference));

        var planSection = MarkdownSection(content, "Ordered Remediation Plan");
        var mappedFindingIds = new HashSet<string>(StringComparer.Ordinal);
        var scopeIds = new HashSet<string>(StringComparer.Ordinal);
        var acceptanceIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in planSection.Split('\n'))
        {
            if (!line.TrimStart().StartsWith('|')) continue;
            var cells = line.Trim().Trim('|').Split('|').Select(cell => cell.Trim()).ToArray();
            if (cells.Length < 8 || cells[0] == "Step" || cells.All(cell => Regex.IsMatch(cell, "^-+$"))) continue;
            if (!Regex.IsMatch(cells[1], "^SI-\\d+$") || !Regex.IsMatch(cells[2], "^AC-\\d+$"))
            {
                throw new ContractException("Review plan remediation rows require SI-* scope and AC-* acceptance IDs.");
            }
            scopeIds.Add(cells[1]);
            acceptanceIds.Add(cells[2]);
            foreach (var findingId in cells[3].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (!mappedFindingIds.Add(findingId)) throw new ContractException($"Review plan maps finding ID more than once: {findingId}");
            }
        }

        var activeFindingIds = result.FindingDelta
            .Where(entry => ActiveFindingStates.Contains(entry.State))
            .SelectMany(entry => entry.FindingIds)
            .ToHashSet(StringComparer.Ordinal);
        if (!activeFindingIds.SetEquals(mappedFindingIds))
        {
            var missing = activeFindingIds.Except(mappedFindingIds, StringComparer.Ordinal);
            var extra = mappedFindingIds.Except(activeFindingIds, StringComparer.Ordinal);
            throw new ContractException($"Review plan active finding mapping mismatch; missing [{string.Join(", ", missing)}], extra [{string.Join(", ", extra)}].");
        }
        var intentScopeIds = IntentIds(scope, "SI", "scope");
        if (!scopeIds.SetEquals(intentScopeIds)) throw new ContractException("Review plan ordered remediation and implementation_intent scope ID sets must match exactly.");
        var intentAcceptanceIds = IntentIds(acceptance, "AC", "acceptance");
        if (!acceptanceIds.SetEquals(intentAcceptanceIds)) throw new ContractException("Review plan ordered remediation and implementation_intent acceptance ID sets must match exactly.");

        var handoff = MarkdownSection(content, "Explicit Implementation Turn Handoff");
        const string adaptiveSkill = "$adaptive-" + "implementation-execution";
        if (!handoff.Contains(adaptiveSkill, StringComparison.Ordinal)
            || !handoff.Contains(NormalizeSlash(planReference), StringComparison.Ordinal)
            || !handoff.Contains("implementation_intent", StringComparison.Ordinal))
        {
            throw new ContractException("Review plan must contain an explicit-turn Adaptive handoff bound to its plan_reference and implementation_intent.");
        }
        Equal("review plan role thread contract", "fixed", MarkdownValue(handoff, "Multi-round role threads"));
        var review = cycle.RoleThreads.Review;
        var implementation = cycle.RoleThreads.Implementation;
        EnsureDistinctRoleThreads(review.ThreadId, implementation.ThreadId);
        Equal("review plan target Implementation Thread ID", implementation.ThreadId, MarkdownValue(handoff, "Target Implementation Thread ID"));
        Equal("review plan target Implementation Thread URI", implementation.ResumeUri, MarkdownValue(handoff, "Target Implementation Thread URI"));
        Equal("review plan return Review Thread ID", review.ThreadId, MarkdownValue(handoff, "Return Review Thread ID"));
        Equal("review plan return Review Thread URI", review.ResumeUri, MarkdownValue(handoff, "Return Review Thread URI"));
    }

    private static string IntentField(string yaml, string field)
    {
        var match = Regex.Match(yaml, $@"(?m)^  {Regex.Escape(field)}:[ \t]*(?<inline>[^\r\n]*)");
        if (!match.Success) throw new ContractException($"Review plan implementation_intent is missing {field}.");
        var inline = match.Groups["inline"].Value.Trim();
        if (!string.IsNullOrWhiteSpace(inline)) return inline;
        var remainder = yaml[(match.Index + match.Length)..].TrimStart('\r', '\n');
        var nested = new List<string>();
        foreach (var line in remainder.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n'))
        {
            if (line.StartsWith("    ", StringComparison.Ordinal)) nested.Add(line);
            else if (string.IsNullOrWhiteSpace(line)) nested.Add(line);
            else break;
        }
        return string.Join("\n", nested).TrimEnd();
    }

    private static HashSet<string> IntentIds(string fieldContent, string prefix, string fieldName)
    {
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in fieldContent.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n'))
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            var match = Regex.Match(line.Trim(), $@"^-\s*(?<id>{Regex.Escape(prefix)}-\d+):\s*\S");
            if (!match.Success) throw new ContractException($"Review plan implementation_intent {fieldName} entries must use non-empty {prefix}-* IDs.");
            var id = match.Groups["id"].Value;
            if (!ids.Add(id)) throw new ContractException($"Review plan implementation_intent {fieldName} contains duplicate ID {id}.");
        }
        if (ids.Count == 0) throw new ContractException($"Review plan implementation_intent {fieldName} requires at least one {prefix}-* entry.");
        return ids;
    }

    private static string MarkdownSection(string content, string heading)
    {
        var match = Regex.Match(content, $@"(?ms)^##\s+{Regex.Escape(heading)}\s*$\r?\n(?<body>.*?)(?=^##\s+|\z)");
        if (!match.Success || string.IsNullOrWhiteSpace(match.Groups["body"].Value))
        {
            throw new ContractException($"Review plan is missing a non-empty '{heading}' section.");
        }
        return match.Groups["body"].Value;
    }

    private static string ReviewModeFor(int roundNumber) => roundNumber == 1 ? FullReviewMode : PurposeOnlyReviewMode;

    private static void ValidateStartThreadIdentity(ReviewCycle cycle, Options options, int roundNumber)
    {
        var reviewThreadId = RequireThreadId(options.ReviewThreadId!, "review-thread-id");
        var implementationThreadId = RequireThreadId(options.ImplementationThreadId!, "implementation-thread-id");
        Equal("Review Thread ID", cycle.RoleThreads.Review.ThreadId, reviewThreadId);
        Equal("Implementation Thread ID", cycle.RoleThreads.Implementation.ThreadId, implementationThreadId);
        EnsureDistinctRoleThreads(reviewThreadId, implementationThreadId);
        if (roundNumber > 1)
        {
            Equal("Adaptive Implementation Thread ID", implementationThreadId, RequireThreadId(options.AdaptiveThreadId!, "adaptive-thread-id"));
        }
    }

    private static ThreadBinding NewThreadBinding(string threadId, string name)
    {
        threadId = RequireThreadId(threadId, name);
        return new ThreadBinding
        {
            ThreadId = threadId,
            ResumeUri = ThreadUri(threadId)
        };
    }

    private static string RequireThreadId(string value, string name)
    {
        if (!Guid.TryParse(value, out var parsed)) throw new ContractException($"{name} must be a Codex task UUID.");
        return parsed.ToString();
    }

    private static string ThreadUri(string threadId) => $"codex://threads/{Uri.EscapeDataString(threadId)}";

    private static void EnsureDistinctRoleThreads(string reviewThreadId, string implementationThreadId)
    {
        if (string.Equals(reviewThreadId, implementationThreadId, StringComparison.OrdinalIgnoreCase))
        {
            throw new ContractException("Review Thread and Implementation Thread must be different Codex tasks.");
        }
    }


    private static void RejectLegacyMutation(ReviewCycle cycle, string operation)
    {
        if (cycle.SchemaVersion == LegacySchemaVersion)
        {
            throw new ContractException($"review-cycle schemaVersion 1 is read-only historical evidence and cannot be used with {operation}; start a new schemaVersion 2 cycle.");
        }
    }

    private static void ValidatePurposeOnlySourceCoverage(HashSet<string> externalSources, List<SourceCoverageEntry> coverage)
    {
        var bySource = coverage.ToDictionary(item => item.SourceId, StringComparer.Ordinal);
        foreach (var sourceId in externalSources)
        {
            if (!bySource.TryGetValue(sourceId, out var entry)
                || entry.Disposition != "noAction"
                || entry.TrackingIds.Count != 0
                || string.IsNullOrWhiteSpace(entry.Reason))
            {
                throw new ContractException($"Purpose-only external source must be retained as reasoned noAction audit evidence: {sourceId}");
            }
        }
    }

    private static void ValidatePriorFindingAssessments(ReviewCycle cycle, RoundRecord round, string content, List<FindingDeltaEntry> delta)
    {
        var priorStates = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var priorRound in cycle.Rounds.Where(item => item.RoundNumber < round.RoundNumber && item.Status == "COMPLETED"))
        {
            foreach (var entry in priorRound.FindingDelta) priorStates[entry.TrackingId] = entry.State;
        }
        var activePrior = priorStates.Where(item => ActiveFindingStates.Contains(item.Value)).ToDictionary(item => item.Key, item => item.Value, StringComparer.Ordinal);
        var section = MarkdownSection(content, "Prior Finding Assessment");
        var assessed = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in section.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n'))
        {
            if (!line.TrimStart().StartsWith("| TRK-", StringComparison.Ordinal)) continue;
            var cells = line.Trim().Trim('|').Split('|').Select(cell => cell.Trim()).ToArray();
            if (cells.Length < 6) throw new ContractException("Prior Finding Assessment rows require tracking ID, previous/current state, Adaptive reference, evidence, and rationale.");
            var trackingId = cells[0];
            if (!assessed.Add(trackingId)) throw new ContractException($"Prior Finding Assessment contains duplicate tracking ID {trackingId}.");
            if (!activePrior.TryGetValue(trackingId, out var previousState)) throw new ContractException($"Prior Finding Assessment contains an unknown or inactive tracking ID {trackingId}.");
            Equal($"prior finding assessment previous state {trackingId}", previousState, cells[1]);
            var mapped = delta.SingleOrDefault(item => item.TrackingId == trackingId)
                ?? throw new ContractException($"Prior Finding Assessment has no findingDelta entry for {trackingId}.");
            Equal($"prior finding assessment current state {trackingId}", mapped.State, cells[2]);
            Equal($"prior finding assessment Adaptive result {trackingId}", round.AdaptiveResultReference, cells[3]);
            if (string.IsNullOrWhiteSpace(cells[4]) || string.IsNullOrWhiteSpace(cells[5]))
            {
                throw new ContractException($"Prior Finding Assessment requires evidence and rationale for {trackingId}.");
            }
        }
        if (!assessed.SetEquals(activePrior.Keys))
        {
            var missing = activePrior.Keys.Except(assessed, StringComparer.Ordinal);
            var extra = assessed.Except(activePrior.Keys, StringComparer.Ordinal);
            throw new ContractException($"Prior Finding Assessment coverage mismatch; missing [{string.Join(", ", missing)}], extra [{string.Join(", ", extra)}].");
        }
    }

    private static void ValidateLegacyCycleReadOnly(string cyclePath, ReviewCycle cycle)
    {
        if (cycle.SchemaVersion != LegacySchemaVersion) throw new ContractException("Legacy review-cycle validation requires schemaVersion 1.");
        if (!Regex.IsMatch(cycle.Repository ?? string.Empty, @"^[^/\s]+/[^/\s]+$")) throw new ContractException("Legacy cycle repository must be owner/name.");
        if (cycle.PullRequest <= 0) throw new ContractException("Legacy cycle pullRequest must be positive.");
        if (!Regex.IsMatch(cycle.GoalContext.NormalizedSha256 ?? string.Empty, "^[0-9a-f]{64}$")) throw new ContractException("Legacy cycle Goal Context SHA-256 is invalid.");
        var cycleRoot = Path.GetDirectoryName(cyclePath)!;
        for (var index = 0; index < cycle.Rounds.Count; index++)
        {
            var round = cycle.Rounds[index];
            var expectedNumber = index + 1;
            Equal("legacy sequential round number", expectedNumber, round.RoundNumber);
            Equal("legacy round artifact directory", $"round-{expectedNumber:000}", round.ArtifactDirectory);
            var directory = Contained(cycleRoot, round.ArtifactDirectory);
            if (!Directory.Exists(directory)) throw new ContractException($"Legacy round artifact directory is missing: {round.ArtifactDirectory}");
            foreach (var artifact in round.Artifacts)
            {
                var path = Contained(cycleRoot, artifact.Path);
                if (!IsContained(directory, path) || !File.Exists(path)) throw new ContractException($"Legacy artifact is missing or outside its round: {artifact.Path}");
                Equal($"legacy artifact hash {artifact.Role}", artifact.NormalizedSha256, Hash(path));
            }
        }
    }

    private static void ValidateThreadContract(ReviewCycle cycle)
    {
        ValidateThreadBinding(cycle.RoleThreads.Review, "Review Thread");
        ValidateThreadBinding(cycle.RoleThreads.Implementation, "Implementation Thread");
        EnsureDistinctRoleThreads(cycle.RoleThreads.Review.ThreadId, cycle.RoleThreads.Implementation.ThreadId);
    }

    private static void ValidateThreadBinding(ThreadBinding binding, string context)
    {
        var threadId = RequireThreadId(binding.ThreadId, context);
        Equal($"{context} resume URI", ThreadUri(threadId), binding.ResumeUri);
    }

    private static JsonElement RequiredObject(JsonElement parent, string property, string context)
    {
        if (!parent.TryGetProperty(property, out var value) || value.ValueKind != JsonValueKind.Object) throw new ContractException($"{context}.{property} must be an object.");
        return value;
    }

    private static string RequiredString(JsonElement parent, string property, string context)
    {
        if (!parent.TryGetProperty(property, out var value) || value.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(value.GetString()))
        {
            throw new ContractException($"{context}.{property} must be a non-empty string.");
        }
        return value.GetString()!;
    }

    private static int RequiredInt(JsonElement parent, string property, string context)
    {
        if (!parent.TryGetProperty(property, out var value) || !value.TryGetInt32(out var result)) throw new ContractException($"{context}.{property} must be an integer.");
        return result;
    }

    private static bool RequiredBool(JsonElement parent, string property, string context)
    {
        if (!parent.TryGetProperty(property, out var value) || value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            throw new ContractException($"{context}.{property} must be a boolean.");
        }
        return value.GetBoolean();
    }

    private static void EqualFindingDelta(string context, List<FindingDeltaEntry> expected, List<FindingDeltaEntry> actual)
    {
        if (expected.Count != actual.Count) throw new ContractException($"{context} count mismatch.");
        for (var index = 0; index < expected.Count; index++)
        {
            Equal($"{context} tracking ID", expected[index].TrackingId, actual[index].TrackingId);
            Equal($"{context} state", expected[index].State, actual[index].State);
            if (!expected[index].FindingIds.SequenceEqual(actual[index].FindingIds, StringComparer.Ordinal)
                || !expected[index].SourceIds.SequenceEqual(actual[index].SourceIds, StringComparer.Ordinal))
            {
                throw new ContractException($"{context} evidence mismatch for {expected[index].TrackingId}.");
            }
        }
    }

    private static void EqualSourceCoverage(string context, List<SourceCoverageEntry> expected, List<SourceCoverageEntry> actual)
    {
        if (expected.Count != actual.Count) throw new ContractException($"{context} count mismatch.");
        for (var index = 0; index < expected.Count; index++)
        {
            Equal($"{context} source ID", expected[index].SourceId, actual[index].SourceId);
            Equal($"{context} disposition", expected[index].Disposition, actual[index].Disposition);
            Equal($"{context} reason", expected[index].Reason, actual[index].Reason);
            if (!expected[index].TrackingIds.SequenceEqual(actual[index].TrackingIds, StringComparer.Ordinal))
            {
                throw new ContractException($"{context} tracking IDs mismatch for {expected[index].SourceId}.");
            }
        }
    }

    private static List<FindingDeltaEntry> ValidateFindingDelta(ReviewCycle cycle, RoundRecord round, List<FindingDeltaEntry> entries)
    {
        var roundNumber = round.RoundNumber;
        var current = new Dictionary<string, FindingDeltaEntry>(StringComparer.Ordinal);
        var ledger = cycle.FindingLedger.ToDictionary(item => item.TrackingId, StringComparer.Ordinal);
        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.TrackingId) || !current.TryAdd(entry.TrackingId, entry))
            {
                throw new ContractException($"Finding tracking IDs must be non-empty and unique: {entry.TrackingId}");
            }
            if (!FindingStates.Contains(entry.State)) throw new ContractException($"Invalid finding state: {entry.State}");
            if ((entry.SourceIds.Count == 0 && !(round.ReviewMode == PurposeOnlyReviewMode && entry.State == "resolved")) || entry.SourceIds.Any(string.IsNullOrWhiteSpace))
            {
                throw new ContractException($"Finding {entry.TrackingId} must retain at least one source ID.");
            }
            if (ActiveFindingStates.Contains(entry.State) && (entry.FindingIds.Count == 0 || entry.FindingIds.Any(string.IsNullOrWhiteSpace)))
            {
                throw new ContractException($"Active finding {entry.TrackingId} must have finding IDs.");
            }
            if (round.ReviewMode == PurposeOnlyReviewMode
                && entry.FindingIds.Concat(entry.SourceIds).Any(id => !Regex.IsMatch(id, @"^PUR-\d+$")))
            {
                throw new ContractException($"Purpose-only finding {entry.TrackingId} may use only current PUR-* evidence IDs.");
            }

            var existed = ledger.TryGetValue(entry.TrackingId, out var previous);
            if (roundNumber == 1 && entry.State != "new") throw new ContractException("Round 1 finding states must all be new.");
            if (entry.State == "new" && existed) throw new ContractException($"Finding {entry.TrackingId} already exists and cannot be new.");
            if (entry.State is "persistent" or "resolved")
            {
                if (!existed || !ActiveFindingStates.Contains(previous!.CurrentState))
                {
                    throw new ContractException($"Finding {entry.TrackingId} cannot transition to {entry.State} from {previous?.CurrentState ?? "missing"}.");
                }
            }
            if (entry.State == "reopened" && (!existed || previous!.CurrentState != "resolved"))
            {
                throw new ContractException($"Finding {entry.TrackingId} can be reopened only after resolved.");
            }
        }

        if (roundNumber > 1)
        {
            foreach (var active in ledger.Values.Where(item => ActiveFindingStates.Contains(item.CurrentState)))
            {
                if (!current.TryGetValue(active.TrackingId, out var mapped) || mapped.State is not ("persistent" or "resolved"))
                {
                    throw new ContractException($"Previously active finding is missing persistent/resolved mapping: {active.TrackingId}");
                }
            }
        }
        return entries;
    }

    private static string ComputeVerdict(ReviewCycle cycle, int roundNumber, int actionableCount, string? blockedReason, string? humanReason)
    {
        if (!string.IsNullOrWhiteSpace(blockedReason)) return "BLOCKED";
        if (!string.IsNullOrWhiteSpace(humanReason)) return "HUMAN_DECISION_REQUIRED";
        if (actionableCount == 0) return "REVIEW_COMPLETE";
        return roundNumber >= cycle.EffectiveMaximumRounds
            ? "HUMAN_DECISION_REQUIRED"
            : "READY_FOR_ADAPTIVE_IMPLEMENTATION";
    }

    private static void ValidateArtifactRoles(string reviewMode, string verdict, int actionableCount, List<ArtifactRecord> artifacts)
    {
        var roles = artifacts.Select(item => item.Role).ToHashSet(StringComparer.Ordinal);
        if (verdict == "BLOCKED")
        {
            foreach (var role in new[] { "review-result", "completion-notification" })
            {
                if (!roles.Contains(role)) throw new ContractException($"BLOCKED round is missing required evidence role: {role}");
            }
            if (roles.Contains("review-plan")) throw new ContractException("BLOCKED must not include an Adaptive review-plan artifact.");
            return;
        }
        foreach (var role in SharedCompletedArtifactRoles)
        {
            if (!roles.Contains(role)) throw new ContractException($"Missing required round artifact role: {role}");
        }
        if (reviewMode == FullReviewMode && !roles.Contains("local-findings")) throw new ContractException("Full review round requires local-findings.");
        if (reviewMode == PurposeOnlyReviewMode && roles.Contains("local-findings")) throw new ContractException("Purpose-only review round must not include local-findings.");
        if (verdict == "READY_FOR_ADAPTIVE_IMPLEMENTATION" && !roles.Contains("review-plan"))
        {
            throw new ContractException("READY_FOR_ADAPTIVE_IMPLEMENTATION requires a review-plan artifact.");
        }
        if ((verdict is "REVIEW_COMPLETE" or "HUMAN_DECISION_REQUIRED") && roles.Contains("review-plan"))
        {
            throw new ContractException($"{verdict} must not include an executable Adaptive review-plan artifact.");
        }
    }

    private static void ValidateSourceCoverage(List<FindingDeltaEntry> delta, List<SourceCoverageEntry> coverage)
    {
        var trackingIds = delta.Select(item => item.TrackingId).ToHashSet(StringComparer.Ordinal);
        var expectedMappings = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var entry in delta)
        {
            foreach (var sourceId in entry.SourceIds.Concat(entry.FindingIds).Distinct(StringComparer.Ordinal))
            {
                if (!expectedMappings.TryGetValue(sourceId, out var mapped))
                {
                    mapped = [];
                    expectedMappings[sourceId] = mapped;
                }
                mapped.Add(entry.TrackingId);
            }
        }
        var coveredSources = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in coverage)
        {
            if (string.IsNullOrWhiteSpace(item.SourceId) || !coveredSources.Add(item.SourceId))
            {
                throw new ContractException($"Source coverage IDs must be non-empty and unique: {item.SourceId}");
            }
            if (item.Disposition == "finding")
            {
                if (item.TrackingIds.Count == 0 || item.TrackingIds.Distinct(StringComparer.Ordinal).Count() != item.TrackingIds.Count
                    || item.TrackingIds.Any(id => !trackingIds.Contains(id)))
                {
                    throw new ContractException($"Source {item.SourceId} must bind to an existing finding tracking ID.");
                }
                if (!expectedMappings.TryGetValue(item.SourceId, out var expected)
                    || !expected.SetEquals(item.TrackingIds))
                {
                    throw new ContractException($"Source-to-tracking mapping mismatch for {item.SourceId}.");
                }
            }
            else if (item.Disposition == "noAction")
            {
                if (item.TrackingIds.Count != 0 || string.IsNullOrWhiteSpace(item.Reason))
                {
                    throw new ContractException($"noAction source {item.SourceId} requires a reason and no tracking IDs.");
                }
                if (expectedMappings.ContainsKey(item.SourceId)) throw new ContractException($"Finding source {item.SourceId} cannot be marked noAction.");
            }
            else
            {
                throw new ContractException($"Invalid source coverage disposition for {item.SourceId}: {item.Disposition}");
            }
        }
        foreach (var sourceId in expectedMappings.Keys)
        {
            if (!coveredSources.Contains(sourceId)) throw new ContractException($"Finding source is missing source coverage: {sourceId}");
        }
    }

    private static void ValidateNotification(ReviewCycle cycle, int roundNumber, string verdict, NotificationRecord notification)
    {
        Equal("notification round number", roundNumber, notification.RoundNumber);
        Equal("notification observed status", verdict, notification.ObservedStatus);
        var prUrl = $"https://github.com/{cycle.Repository}/pull/{cycle.PullRequest}";
        if (!string.Equals(notification.ResultUri, prUrl, StringComparison.Ordinal))
        {
            throw new ContractException($"Notification result URI must link directly to the target PR: {prUrl}");
        }
    }

    private static void ValidateNotificationArtifact(string cycleRoot, List<ArtifactRecord> artifacts, int roundNumber, string verdict, string resultUri)
    {
        var artifact = artifacts.Single(item => item.Role == "completion-notification");
        var content = File.ReadAllText(Contained(cycleRoot, artifact.Path));
        if (!content.Contains(verdict, StringComparison.Ordinal)) throw new ContractException("Completion notification artifact does not contain the observed verdict.");
        if (!content.Contains(resultUri, StringComparison.Ordinal)) throw new ContractException("Completion notification artifact does not contain the target PR direct link.");
        if (!Regex.IsMatch(content, $@"(?i)round[-_\s]*0*{roundNumber}(?!\d)"))
        {
            throw new ContractException($"Completion notification artifact does not identify round-{roundNumber:000}.");
        }
    }

    private static void UpdateFindingLedger(ReviewCycle cycle, int roundNumber, List<FindingDeltaEntry> delta)
    {
        var ledger = cycle.FindingLedger.ToDictionary(item => item.TrackingId, StringComparer.Ordinal);
        foreach (var entry in delta)
        {
            if (!ledger.TryGetValue(entry.TrackingId, out var item))
            {
                item = new FindingLedgerEntry { TrackingId = entry.TrackingId };
                cycle.FindingLedger.Add(item);
                ledger.Add(entry.TrackingId, item);
            }
            item.CurrentState = entry.State;
            item.LastRound = roundNumber;
            item.History.Add(new FindingHistoryEntry
            {
                RoundNumber = roundNumber,
                State = entry.State,
                FindingIds = entry.FindingIds.Distinct(StringComparer.Ordinal).ToList(),
                SourceIds = entry.SourceIds.Distinct(StringComparer.Ordinal).ToList()
            });
        }
    }

    private static void ValidateCycle(string cyclePath, ReviewCycle cycle, bool requireCompletedCurrentRound)
    {
        if (cycle.SchemaVersion != SchemaVersion) throw new ContractException("review-cycle schemaVersion must be 2.");
        if (!Regex.IsMatch(cycle.Repository ?? string.Empty, @"^[^/\s]+/[^/\s]+$")) throw new ContractException("Cycle repository must be owner/name.");
        if (cycle.PullRequest <= 0) throw new ContractException("Cycle pullRequest must be positive.");
        if (!Regex.IsMatch(cycle.GoalContext.NormalizedSha256 ?? string.Empty, "^[0-9a-f]{64}$")) throw new ContractException("Cycle Goal Context SHA-256 is invalid.");
        if (cycle.DefaultMaximumRounds != DefaultMaximumRounds) throw new ContractException("defaultMaximumRounds must be 3.");
        if (cycle.EffectiveMaximumRounds < DefaultMaximumRounds) throw new ContractException("effectiveMaximumRounds cannot be below 3.");
        if (cycle.CurrentRound != cycle.Rounds.Count) throw new ContractException("currentRound must equal the number of round records.");
        ValidateThreadContract(cycle);
        ValidateHumanDecisions(cyclePath, cycle);

        var expectedEffectiveMaximum = DefaultMaximumRounds;
        var lastOverrideRound = 0;
        foreach (var roundOverride in cycle.Overrides)
        {
            if (roundOverride.StartingRound < 4 || roundOverride.StartingRound <= lastOverrideRound
                || roundOverride.MaximumRounds < roundOverride.StartingRound || roundOverride.MaximumRounds <= expectedEffectiveMaximum
                || string.IsNullOrWhiteSpace(roundOverride.ApprovedBy) || string.IsNullOrWhiteSpace(roundOverride.Reason)
                || string.IsNullOrWhiteSpace(roundOverride.DecisionId))
            {
                throw new ContractException("Cycle contains an invalid or non-increasing human round override.");
            }
            var decision = cycle.HumanDecisions.SingleOrDefault(item => item.DecisionId == roundOverride.DecisionId && item.Status == "RESOLVED");
            if (decision is null || decision.RoundNumber != roundOverride.StartingRound - 1 || decision.ResolvedForRound != roundOverride.StartingRound)
            {
                throw new ContractException($"Override for round {roundOverride.StartingRound} is not bound to the resolved maximum-round decision.");
            }
            ParseTimestamp(roundOverride.ApprovedAt, "override approvedAt");
            expectedEffectiveMaximum = roundOverride.MaximumRounds;
            lastOverrideRound = roundOverride.StartingRound;
        }
        Equal("effective maximum rounds", expectedEffectiveMaximum, cycle.EffectiveMaximumRounds);

        var cycleRoot = Path.GetDirectoryName(cyclePath)!;
        var heads = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var priorStates = new Dictionary<string, string>(StringComparer.Ordinal);
        var maximumAtRound = DefaultMaximumRounds;
        for (var index = 0; index < cycle.Rounds.Count; index++)
        {
            var round = cycle.Rounds[index];
            var expectedNumber = index + 1;
            Equal("sequential round number", expectedNumber, round.RoundNumber);
            Equal("round review mode", ReviewModeFor(expectedNumber), round.ReviewMode);
            Equal("round artifact directory", $"round-{expectedNumber:000}", round.ArtifactDirectory);
            Equal("previous round reference", expectedNumber == 1 ? null : expectedNumber - 1, round.PreviousRound);
            RequireOid(round.BaseOid, $"round {expectedNumber} base OID");
            RequireOid(round.HeadOid, $"round {expectedNumber} head OID");
            var observedReviewThread = RequireThreadId(round.ReviewThreadId, $"round {expectedNumber} reviewThreadId");
            Equal($"round {expectedNumber} Review Thread ID", cycle.RoleThreads.Review.ThreadId, observedReviewThread);
            if (!heads.Add(round.HeadOid)) throw new ContractException($"Duplicate reviewed head OID in cycle: {round.HeadOid}");
            if (expectedNumber == 1 && (!string.IsNullOrWhiteSpace(round.AdaptiveResultReference) || !string.IsNullOrWhiteSpace(round.AdaptiveThreadId)))
            {
                throw new ContractException("Round 1 cannot have an Adaptive result reference or Adaptive Thread ID.");
            }
            if (expectedNumber > 1)
            {
                if (string.IsNullOrWhiteSpace(round.AdaptiveResultReference)) throw new ContractException($"Round {expectedNumber} is missing its previous Adaptive result reference.");
                var observedAdaptiveThread = RequireThreadId(round.AdaptiveThreadId ?? string.Empty, $"round {expectedNumber} adaptiveThreadId");
                EnsureDistinctRoleThreads(observedReviewThread, observedAdaptiveThread);
                Equal($"round {expectedNumber} Implementation Thread ID", cycle.RoleThreads.Implementation.ThreadId, observedAdaptiveThread);
            }
            foreach (var roundOverride in cycle.Overrides.Where(item => item.StartingRound == expectedNumber)) maximumAtRound = roundOverride.MaximumRounds;
            if (expectedNumber > maximumAtRound) throw new ContractException($"Round {expectedNumber} lacks a human override permitting it.");
            var directory = Contained(cycleRoot, round.ArtifactDirectory);
            if (!Directory.Exists(directory)) throw new ContractException($"Round artifact directory is missing: {round.ArtifactDirectory}");
            if (round.Status == "COMPLETED")
            {
                if (string.IsNullOrWhiteSpace(round.Verdict) || string.IsNullOrWhiteSpace(round.CompletedAt))
                {
                    throw new ContractException($"Completed round {expectedNumber} is missing verdict or completedAt.");
                }
                foreach (var artifact in round.Artifacts)
                {
                    var path = Contained(cycleRoot, artifact.Path);
                    if (!IsContained(directory, path) || !File.Exists(path)) throw new ContractException($"Historical artifact is missing or outside its round: {artifact.Path}");
                    Equal($"historical artifact hash {artifact.Role}", artifact.NormalizedSha256, Hash(path));
                }
                if (round.Verdict == "BLOCKED")
                {
                    if (round.FindingDelta.Count != 0) throw new ContractException($"BLOCKED round {expectedNumber} must not contain finding transitions.");
                }
                else
                {
                    ValidateHistoricalFindingDelta(round, priorStates);
                }
                ValidateSourceCoverage(round.FindingDelta, round.SourceCoverage);
                var actionable = round.FindingDelta.Count(item => ActiveFindingStates.Contains(item.State));
                Equal($"round {expectedNumber} actionable finding count", actionable, round.ActionableFindingCount);
                string expectedVerdict;
                if (!string.IsNullOrWhiteSpace(round.HumanDecisionReason))
                {
                    if (round.Verdict is not ("BLOCKED" or "HUMAN_DECISION_REQUIRED"))
                    {
                        throw new ContractException($"Round {expectedNumber} has a human/blocked reason with incompatible verdict {round.Verdict}.");
                    }
                    expectedVerdict = round.Verdict;
                }
                else
                {
                    expectedVerdict = actionable == 0
                        ? "REVIEW_COMPLETE"
                        : expectedNumber >= maximumAtRound ? "HUMAN_DECISION_REQUIRED" : "READY_FOR_ADAPTIVE_IMPLEMENTATION";
                }
                Equal($"round {expectedNumber} verdict", expectedVerdict, round.Verdict);
                ValidateArtifactRoles(round.ReviewMode, round.Verdict!, actionable, round.Artifacts);
                ValidateArtifactContents(cycle, round, new RoundResult
                {
                    SchemaVersion = SchemaVersion,
                    ReviewMode = round.ReviewMode,
                    Verdict = round.Verdict!,
                    FindingDelta = round.FindingDelta,
                    SourceCoverage = round.SourceCoverage
                }, cycleRoot, round.Artifacts);
                if (round.Notification is null) throw new ContractException($"Completed round {expectedNumber} is missing notification evidence.");
                ValidateNotification(cycle, expectedNumber, round.Verdict!, round.Notification);
                ValidateNotificationArtifact(cycleRoot, round.Artifacts, expectedNumber, round.Verdict!, round.Notification.ResultUri);
                if (expectedNumber < cycle.Rounds.Count && round.Verdict is "REVIEW_COMPLETE" or "BLOCKED")
                {
                    throw new ContractException($"Round history continues after terminal verdict {round.Verdict}.");
                }
            }
            else if (round.Status != "IN_PROGRESS" || index != cycle.Rounds.Count - 1)
            {
                throw new ContractException($"Round {expectedNumber} has invalid status or is not the current round.");
            }
        }

        if (requireCompletedCurrentRound && cycle.Rounds.LastOrDefault()?.Status == "IN_PROGRESS")
        {
            throw new ContractException("Current round must be completed before starting another round.");
        }
        ValidateLedgerConsistency(cycle);
        var expectedStatus = cycle.Rounds.LastOrDefault() is { } current
            ? current.Status == "IN_PROGRESS"
                ? "IN_PROGRESS"
                : current.Verdict == "HUMAN_DECISION_REQUIRED"
                    && cycle.HumanDecisions.Any(item => item.RoundNumber == current.RoundNumber && item.Status == "RESOLVED")
                        ? "APPROVED_FOR_ADAPTIVE_IMPLEMENTATION"
                        : current.Verdict
            : "NOT_STARTED";
        Equal("cycle status", expectedStatus, cycle.Status);
    }

    private static void ValidateHumanDecisions(string cyclePath, ReviewCycle cycle)
    {
        var cycleRoot = Path.GetDirectoryName(cyclePath)!;
        var decisionIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var decision in cycle.HumanDecisions)
        {
            var decisionId = decision.DecisionId ?? string.Empty;
            if (!Regex.IsMatch(decisionId, "^HD-[0-9]{3}$") || !decisionIds.Add(decisionId))
            {
                throw new ContractException($"Human decision ID is invalid or duplicated: {decision.DecisionId}");
            }
            var round = cycle.Rounds.SingleOrDefault(item => item.RoundNumber == decision.RoundNumber);
            if (round is null || round.Status != "COMPLETED" || round.Verdict != "HUMAN_DECISION_REQUIRED")
            {
                throw new ContractException($"Human decision {decision.DecisionId} does not correspond to a HUMAN_DECISION_REQUIRED round.");
            }
            if (string.IsNullOrWhiteSpace(decision.Reason) || decision.Status is not ("PENDING" or "RESOLVED"))
            {
                throw new ContractException($"Human decision {decision.DecisionId} has invalid status or reason.");
            }
            if (decision.Status == "PENDING")
            {
                if (decision.ResolvedForRound is not null || decision.ApprovedAt is not null || decision.ApprovedBy is not null
                    || decision.Resolution is not null || decision.ApprovedPlanReference is not null
                    || decision.ApprovedPlanNormalizedSha256 is not null)
                {
                    throw new ContractException($"Pending human decision {decision.DecisionId} contains resolution evidence.");
                }
                if (cycle.Rounds.Any(item => item.RoundNumber > decision.RoundNumber))
                {
                    throw new ContractException($"Cycle continued past unresolved human decision {decision.DecisionId}.");
                }
            }
            else
            {
                if (string.IsNullOrWhiteSpace(decision.Resolution) || string.IsNullOrWhiteSpace(decision.ApprovedBy)
                    || string.IsNullOrWhiteSpace(decision.ApprovedAt) || decision.ResolvedForRound != decision.RoundNumber + 1
                    || string.IsNullOrWhiteSpace(decision.ApprovedPlanReference)
                    || !Regex.IsMatch(decision.ApprovedPlanNormalizedSha256 ?? string.Empty, "^[0-9a-f]{64}$"))
                {
                    throw new ContractException($"Resolved human decision {decision.DecisionId} lacks complete approval evidence.");
                }
                ParseTimestamp(decision.ApprovedAt, $"human decision {decision.DecisionId} approvedAt");
                var expectedPlanReference = $"{round.ArtifactDirectory}/approved-review-plan.md";
                Equal($"human decision {decision.DecisionId} approved plan reference", expectedPlanReference, NormalizeSlash(decision.ApprovedPlanReference));
                var approvedPlanPath = Contained(cycleRoot, decision.ApprovedPlanReference);
                var roundDirectory = Contained(cycleRoot, round.ArtifactDirectory);
                if (!IsContained(roundDirectory, approvedPlanPath) || !File.Exists(approvedPlanPath))
                {
                    throw new ContractException($"Resolved human decision {decision.DecisionId} approved plan is missing or outside its round.");
                }
                Equal($"human decision {decision.DecisionId} approved plan hash", decision.ApprovedPlanNormalizedSha256, Hash(approvedPlanPath));
                ValidateReviewPlan(cycle, round, new RoundResult
                {
                    Verdict = "APPROVED_FOR_ADAPTIVE_IMPLEMENTATION",
                    FindingDelta = round.FindingDelta,
                    SourceCoverage = round.SourceCoverage
                }, approvedPlanPath, decision.ApprovedPlanReference);
                var nextRound = cycle.Rounds.SingleOrDefault(item => item.RoundNumber == decision.ResolvedForRound);
                if (nextRound is null && cycle.Rounds.Count > decision.RoundNumber)
                {
                    throw new ContractException($"Resolved human decision {decision.DecisionId} does not lead to its recorded next round.");
                }
            }
        }

        foreach (var round in cycle.Rounds.Where(item => item.Status == "COMPLETED" && item.Verdict == "HUMAN_DECISION_REQUIRED"))
        {
            if (cycle.HumanDecisions.Count(item => item.RoundNumber == round.RoundNumber) != 1)
            {
                throw new ContractException($"HUMAN_DECISION_REQUIRED round {round.RoundNumber} must have exactly one decision record.");
            }
        }
    }

    private static void ValidateHistoricalFindingDelta(RoundRecord round, Dictionary<string, string> priorStates)
    {
        var current = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in round.FindingDelta)
        {
            if (string.IsNullOrWhiteSpace(entry.TrackingId) || !current.Add(entry.TrackingId)) throw new ContractException($"Round {round.RoundNumber} has duplicate or empty tracking IDs.");
            if (!FindingStates.Contains(entry.State)) throw new ContractException($"Round {round.RoundNumber} has invalid finding state {entry.State}.");
            priorStates.TryGetValue(entry.TrackingId, out var previous);
            if (round.RoundNumber == 1 && entry.State != "new") throw new ContractException("Round 1 finding states must all be new.");
            if (entry.State == "new" && previous is not null) throw new ContractException($"Historical finding {entry.TrackingId} cannot become new again.");
            if (entry.State is "persistent" or "resolved" && (previous is null || !ActiveFindingStates.Contains(previous)))
            {
                throw new ContractException($"Historical finding {entry.TrackingId} has an invalid {entry.State} transition.");
            }
            if (entry.State == "reopened" && previous != "resolved") throw new ContractException($"Historical finding {entry.TrackingId} has an invalid reopened transition.");
        }
        foreach (var prior in priorStates.Where(item => ActiveFindingStates.Contains(item.Value)))
        {
            var mapped = round.FindingDelta.FirstOrDefault(item => item.TrackingId == prior.Key);
            if (mapped is null || mapped.State is not ("persistent" or "resolved")) throw new ContractException($"Historical active finding is missing a transition: {prior.Key}");
        }
        foreach (var entry in round.FindingDelta) priorStates[entry.TrackingId] = entry.State;
    }

    private static void ValidateLedgerConsistency(ReviewCycle cycle)
    {
        var expected = new Dictionary<string, List<FindingHistoryEntry>>(StringComparer.Ordinal);
        foreach (var round in cycle.Rounds.Where(item => item.Status == "COMPLETED"))
        {
            foreach (var delta in round.FindingDelta)
            {
                if (!expected.TryGetValue(delta.TrackingId, out var history))
                {
                    history = [];
                    expected.Add(delta.TrackingId, history);
                }
                history.Add(new FindingHistoryEntry
                {
                    RoundNumber = round.RoundNumber,
                    State = delta.State,
                    FindingIds = delta.FindingIds.Distinct(StringComparer.Ordinal).ToList(),
                    SourceIds = delta.SourceIds.Distinct(StringComparer.Ordinal).ToList()
                });
            }
        }

        if (expected.Count != cycle.FindingLedger.Count) throw new ContractException("findingLedger does not cover every tracked finding.");
        foreach (var item in cycle.FindingLedger)
        {
            if (!expected.TryGetValue(item.TrackingId, out var history)) throw new ContractException($"findingLedger has unknown tracking ID: {item.TrackingId}");
            Equal($"finding ledger history count {item.TrackingId}", history.Count, item.History.Count);
            var last = history[^1];
            Equal($"finding ledger current state {item.TrackingId}", last.State, item.CurrentState);
            Equal($"finding ledger last round {item.TrackingId}", last.RoundNumber, item.LastRound);
            for (var i = 0; i < history.Count; i++)
            {
                Equal($"finding history round {item.TrackingId}", history[i].RoundNumber, item.History[i].RoundNumber);
                Equal($"finding history state {item.TrackingId}", history[i].State, item.History[i].State);
                if (!history[i].FindingIds.SequenceEqual(item.History[i].FindingIds, StringComparer.Ordinal)
                    || !history[i].SourceIds.SequenceEqual(item.History[i].SourceIds, StringComparer.Ordinal))
                {
                    throw new ContractException($"findingLedger history evidence mismatch: {item.TrackingId}");
                }
            }
        }
    }

    private static ReviewCycle ReadCycle(string path)
    {
        if (!File.Exists(path)) throw new ContractException($"Review cycle does not exist: {path}");
        return ReadJson<ReviewCycle>(path);
    }

    private static T ReadJson<T>(string path) where T : class
        => JsonSerializer.Deserialize<T>(File.ReadAllText(path), Json.Options)
           ?? throw new ContractException($"JSON deserialized to null: {path}");

    private static void SaveCycle(string path, ReviewCycle cycle)
    {
        var text = JsonSerializer.Serialize(cycle, Json.Options) + "\n";
        var temp = path + ".tmp-" + Guid.NewGuid().ToString("N");
        File.WriteAllText(temp, text, new UTF8Encoding(false));
        File.Move(temp, path, true);
    }

    private static string Hash(string path)
    {
        var normalized = File.ReadAllText(path).Replace("\r\n", "\n").Replace("\r", "\n");
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalized))).ToLowerInvariant();
    }

    private static string Contained(string root, string path)
    {
        var fullRoot = Path.GetFullPath(root);
        var fullPath = Path.GetFullPath(Path.IsPathRooted(path) ? path : Path.Combine(fullRoot, path));
        if (!IsContained(fullRoot, fullPath)) throw new ContractException($"Path escapes review cycle root: {path}");
        RejectLinkedBoundaryRoot(fullRoot);
        var physicalRoot = ResolvePhysicalPath(fullRoot);
        var physicalPath = ResolvePhysicalPath(fullPath);
        if (!IsContained(physicalRoot, physicalPath)) throw new ContractException($"Path resolves outside review cycle root through a symlink or junction: {path}");
        return physicalPath;
    }

    private static void RejectLinkedBoundaryRoot(string root)
    {
        if (!Directory.Exists(root)) throw new ContractException($"Review cycle root does not exist: {root}");
        RejectLinkedRootEntry(root);
    }

    private static void RejectLinkedRootEntry(string root)
    {
        if (TryGetAttributes(root, out var attributes) && (attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new ContractException($"Review cycle root must not be a symlink or junction: {root}");
        }
    }

    private static string ResolvePhysicalPath(string path)
    {
        var fullPath = Path.GetFullPath(path);
        var pathRoot = Path.GetPathRoot(fullPath) ?? throw new ContractException($"Path has no filesystem root: {path}");
        var relative = fullPath[pathRoot.Length..];
        var current = pathRoot;
        foreach (var component in relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Where(value => value.Length > 0))
        {
            var next = Path.Combine(current, component);
            if (TryGetAttributes(next, out var attributes))
            {
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    try
                    {
                        FileSystemInfo entry = (attributes & FileAttributes.Directory) != 0 || Directory.Exists(next)
                            ? new DirectoryInfo(next) : new FileInfo(next);
                        var target = entry.ResolveLinkTarget(returnFinalTarget: true)
                            ?? throw new ContractException($"Unable to resolve symlink or junction: {next}");
                        current = Path.GetFullPath(target.FullName);
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                    {
                        throw new ContractException($"Unable to resolve symlink or junction: {next}");
                    }
                    continue;
                }
            }
            current = next;
        }
        return Path.GetFullPath(current);
    }

    private static bool TryGetAttributes(string path, out FileAttributes attributes)
    {
        try
        {
            attributes = File.GetAttributes(path);
            return true;
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
        {
            attributes = default;
            return false;
        }
    }

    private static bool IsContained(string root, string path)
    {
        var relative = Path.GetRelativePath(Path.GetFullPath(root), Path.GetFullPath(path));
        return relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal)
               && !Path.IsPathRooted(relative);
    }

    private static void RequireOid(string? value, string name)
    {
        if (!Regex.IsMatch(value ?? string.Empty, "^[0-9a-f]{40}$")) throw new ContractException($"{name} must be a lowercase 40-character Git OID.");
    }

    private static DateTimeOffset ParseTimestamp(string value, string name)
    {
        var formats = new[]
        {
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'",
            "yyyy-MM-dd'T'HH:mm:sszzz",
            "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFzzz"
        };
        if (!DateTimeOffset.TryParseExact(
                value,
                formats,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var parsed))
        {
            throw new ContractException($"{name} must be an ISO-8601 timestamp with an explicit Z or UTC offset.");
        }
        return parsed;
    }

    private static void Equal<T>(string name, T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new ContractException($"{name} mismatch: expected '{expected}', observed '{actual}'.");
        }
    }

    private static string NormalizeSlash(string value) => value.Replace('\\', '/');
    private static string? EmptyToNull(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;
}

sealed class Options
{
    public string Command { get; private set; } = string.Empty;
    public string? CyclePath { get; private set; }
    public string? Repository { get; private set; }
    public int PullRequest { get; private set; }
    public string? GoalContextPath { get; private set; }
    public string? GoalContextSha { get; private set; }
    public string? BaseOid { get; private set; }
    public string? HeadOid { get; private set; }
    public string? StartedAt { get; private set; }
    public string? AdaptiveResultReference { get; private set; }
    public string? ReviewThreadId { get; private set; }
    public string? ImplementationThreadId { get; private set; }
    public string? AdaptiveThreadId { get; private set; }
    public string? RoundResultPath { get; private set; }
    public int OverrideMaximumRounds { get; private set; }
    public string? OverrideApprovedBy { get; private set; }
    public string? OverrideApprovedAt { get; private set; }
    public string? OverrideReason { get; private set; }
    public string? ResolveDecision { get; private set; }
    public string? DecisionResolution { get; private set; }
    public string? DecisionApprovedBy { get; private set; }
    public string? DecisionApprovedAt { get; private set; }
    public string? ApprovedPlan { get; private set; }
    public string Format { get; private set; } = "text";
    public bool ShowHelp { get; private set; }
    public bool Valid { get; private set; } = true;

    public static Options Parse(string[] args)
    {
        var options = new Options();
        if (args.Length == 0) { options.Valid = false; return options; }
        if (args.Length == 1 && args[0] is "--help" or "-h")
        {
            options.ShowHelp = true;
            return options;
        }
        options.Command = args[0].ToLowerInvariant();
        for (var i = 1; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--cycle": options.CyclePath = Value(args, ref i, "--cycle"); break;
                case "--repository": options.Repository = Value(args, ref i, "--repository"); break;
                case "--pr": options.PullRequest = PositiveInt(args, ref i, "--pr"); break;
                case "--goal-context-path": options.GoalContextPath = Value(args, ref i, "--goal-context-path"); break;
                case "--goal-context-sha": options.GoalContextSha = Value(args, ref i, "--goal-context-sha"); break;
                case "--base-oid": options.BaseOid = Value(args, ref i, "--base-oid"); break;
                case "--head-oid": options.HeadOid = Value(args, ref i, "--head-oid"); break;
                case "--started-at": options.StartedAt = Value(args, ref i, "--started-at"); break;
                case "--adaptive-result-reference": options.AdaptiveResultReference = Value(args, ref i, "--adaptive-result-reference"); break;
                case "--review-thread-id": options.ReviewThreadId = Value(args, ref i, "--review-thread-id"); break;
                case "--implementation-thread-id": options.ImplementationThreadId = Value(args, ref i, "--implementation-thread-id"); break;
                case "--adaptive-thread-id": options.AdaptiveThreadId = Value(args, ref i, "--adaptive-thread-id"); break;
                case "--round-result": options.RoundResultPath = Value(args, ref i, "--round-result"); break;
                case "--override-maximum-rounds": options.OverrideMaximumRounds = PositiveInt(args, ref i, "--override-maximum-rounds"); break;
                case "--override-approved-by": options.OverrideApprovedBy = Value(args, ref i, "--override-approved-by"); break;
                case "--override-approved-at": options.OverrideApprovedAt = Value(args, ref i, "--override-approved-at"); break;
                case "--override-reason": options.OverrideReason = Value(args, ref i, "--override-reason"); break;
                case "--resolve-decision": options.ResolveDecision = Value(args, ref i, "--resolve-decision"); break;
                case "--decision-resolution": options.DecisionResolution = Value(args, ref i, "--decision-resolution"); break;
                case "--decision-approved-by": options.DecisionApprovedBy = Value(args, ref i, "--decision-approved-by"); break;
                case "--decision-approved-at": options.DecisionApprovedAt = Value(args, ref i, "--decision-approved-at"); break;
                case "--approved-plan": options.ApprovedPlan = Value(args, ref i, "--approved-plan"); break;
                case "--format":
                    options.Format = Value(args, ref i, "--format").ToLowerInvariant();
                    if (options.Format is not ("json" or "text")) options.Valid = false;
                    break;
                case "--help":
                case "-h": options.ShowHelp = true; break;
                default: options.Valid = false; break;
            }
        }
        if (options.Command is not ("start" or "complete" or "resolve" or "validate")) options.Valid = false;
        return options;
    }

    private static string Value(string[] args, ref int index, string option)
    {
        if (index + 1 >= args.Length) throw new ContractException($"{option} requires a value.");
        return args[++index];
    }

    private static int PositiveInt(string[] args, ref int index, string option)
    {
        var value = Value(args, ref index, option);
        if (!int.TryParse(value, out var parsed) || parsed <= 0) throw new ContractException($"{option} requires a positive integer.");
        return parsed;
    }
}

static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        WriteIndented = true
    };
}

sealed record CommandOutput(int ContractVersion, string Status, int? RoundNumber, string? Verdict, string? ArtifactDirectory, List<string> Errors);
sealed class ContractException(string message) : Exception(message);

sealed class ReviewCycle
{
    public int SchemaVersion { get; set; }
    public string Repository { get; set; } = string.Empty;
    public int PullRequest { get; set; }
    public GoalContextIdentity GoalContext { get; set; } = new();
    public int DefaultMaximumRounds { get; set; }
    public int EffectiveMaximumRounds { get; set; }
    public int CurrentRound { get; set; }
    public string Status { get; set; } = string.Empty;
    public RoleThreads RoleThreads { get; set; } = new();
    public List<RoundOverride> Overrides { get; set; } = [];
    public List<RoundRecord> Rounds { get; set; } = [];
    public List<FindingLedgerEntry> FindingLedger { get; set; } = [];
    public List<HumanDecision> HumanDecisions { get; set; } = [];
}

sealed class GoalContextIdentity
{
    public string Path { get; set; } = string.Empty;
    public string NormalizedSha256 { get; set; } = string.Empty;
}

sealed class RoleThreads
{
    public ThreadBinding Review { get; set; } = new();
    public ThreadBinding Implementation { get; set; } = new();
}

sealed class ThreadBinding
{
    public string ThreadId { get; set; } = string.Empty;
    public string ResumeUri { get; set; } = string.Empty;
}

sealed class RoundRecord
{
    public int RoundNumber { get; set; }
    public string ReviewMode { get; set; } = string.Empty;
    public string ArtifactDirectory { get; set; } = string.Empty;
    public string BaseOid { get; set; } = string.Empty;
    public string HeadOid { get; set; } = string.Empty;
    public int? PreviousRound { get; set; }
    public string StartedAt { get; set; } = string.Empty;
    public string? CompletedAt { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? Verdict { get; set; }
    public string? AdaptiveResultReference { get; set; }
    public string ReviewThreadId { get; set; } = string.Empty;
    public string? AdaptiveThreadId { get; set; }
    public int ActionableFindingCount { get; set; }
    public List<ArtifactRecord> Artifacts { get; set; } = [];
    public NotificationRecord? Notification { get; set; }
    public List<FindingDeltaEntry> FindingDelta { get; set; } = [];
    public List<SourceCoverageEntry> SourceCoverage { get; set; } = [];
    public string? HumanDecisionReason { get; set; }
}

sealed class RoundResult
{
    public int SchemaVersion { get; set; }
    public int RoundNumber { get; set; }
    public string ReviewMode { get; set; } = string.Empty;
    public string BaseOid { get; set; } = string.Empty;
    public string HeadOid { get; set; } = string.Empty;
    public string CompletedAt { get; set; } = string.Empty;
    public string Verdict { get; set; } = string.Empty;
    public string? HumanDecisionReason { get; set; }
    public string? BlockedReason { get; set; }
    public List<ArtifactRecord> Artifacts { get; set; } = [];
    public NotificationRecord Notification { get; set; } = new();
    public List<FindingDeltaEntry> FindingDelta { get; set; } = [];
    public List<SourceCoverageEntry> SourceCoverage { get; set; } = [];
}

sealed class ReviewResultArtifact
{
    public int SchemaVersion { get; set; }
    public string Repository { get; set; } = string.Empty;
    public int PullRequest { get; set; }
    public int RoundNumber { get; set; }
    public string ReviewMode { get; set; } = string.Empty;
    public string BaseOid { get; set; } = string.Empty;
    public string HeadOid { get; set; } = string.Empty;
    public GoalContextIdentity GoalContext { get; set; } = new();
    public string Verdict { get; set; } = string.Empty;
    public List<FindingDeltaEntry> FindingDelta { get; set; } = [];
    public List<SourceCoverageEntry> SourceCoverage { get; set; } = [];
    public List<ArtifactBinding> ArtifactBindings { get; set; } = [];
}

sealed class ArtifactBinding
{
    public string Role { get; set; } = string.Empty;
    public string NormalizedSha256 { get; set; } = string.Empty;
}

sealed class ArtifactRecord
{
    public string Role { get; set; } = string.Empty;
    public string Path { get; set; } = string.Empty;
    public string NormalizedSha256 { get; set; } = string.Empty;
}

sealed class NotificationRecord
{
    public int RoundNumber { get; set; }
    public string ObservedStatus { get; set; } = string.Empty;
    public string ResultUri { get; set; } = string.Empty;
}

sealed class FindingDeltaEntry
{
    public string TrackingId { get; set; } = string.Empty;
    public string State { get; set; } = string.Empty;
    public List<string> FindingIds { get; set; } = [];
    public List<string> SourceIds { get; set; } = [];
}

sealed class FindingLedgerEntry
{
    public string TrackingId { get; set; } = string.Empty;
    public string CurrentState { get; set; } = string.Empty;
    public int LastRound { get; set; }
    public List<FindingHistoryEntry> History { get; set; } = [];
}

sealed class FindingHistoryEntry
{
    public int RoundNumber { get; set; }
    public string State { get; set; } = string.Empty;
    public List<string> FindingIds { get; set; } = [];
    public List<string> SourceIds { get; set; } = [];
}

sealed class RoundOverride
{
    public int StartingRound { get; set; }
    public string DecisionId { get; set; } = string.Empty;
    public string ApprovedBy { get; set; } = string.Empty;
    public string ApprovedAt { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public int MaximumRounds { get; set; }
}

sealed class SourceCoverageEntry
{
    public string SourceId { get; set; } = string.Empty;
    public string Disposition { get; set; } = string.Empty;
    public List<string> TrackingIds { get; set; } = [];
    public string? Reason { get; set; }
}

sealed class HumanDecision
{
    public string DecisionId { get; set; } = string.Empty;
    public int RoundNumber { get; set; }
    public string Status { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public string? ApprovedBy { get; set; }
    public string? ApprovedAt { get; set; }
    public string? Resolution { get; set; }
    public int? ResolvedForRound { get; set; }
    public string? ApprovedPlanReference { get; set; }
    public string? ApprovedPlanNormalizedSha256 { get; set; }
}
