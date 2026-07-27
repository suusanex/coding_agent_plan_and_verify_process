#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Security.Cryptography;
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
  dotnet run --file scripts/manage-review-cycle.cs -- start --cycle <path> --repository owner/name --pr <number> --goal-context-path <path> --goal-context-sha <sha256> --base-oid <oid> --head-oid <oid> --started-at <ISO-8601> [--adaptive-result-reference <path-or-uri>] [override options] [--format json|text]
  dotnet run --file scripts/manage-review-cycle.cs -- complete --cycle <path> --round-result <path> [--format json|text]
  dotnet run --file scripts/manage-review-cycle.cs -- validate --cycle <path> [--format json|text]

Override options (all required together):
  --override-maximum-rounds <number>
  --override-approved-by <identity>
  --override-approved-at <ISO-8601>
  --override-reason <text>

Rules:
  The default maximum is 3 rounds. A fourth or later round requires a recorded human override.
  Every round targets a new PR head OID and writes to a new round-NNN directory.
  This utility manages evidence only. It never starts review agents, Adaptive Implementation, or another round.

Exit codes: 0 success, 1 runtime error, 2 contract violation.
""");
}

static class ReviewCycleManager
{
    private const int SchemaVersion = 1;
    private const int DefaultMaximumRounds = 3;
    private static readonly HashSet<string> FindingStates = new(StringComparer.Ordinal)
    {
        "new", "persistent", "resolved", "reopened"
    };
    private static readonly HashSet<string> ActiveFindingStates = new(StringComparer.Ordinal)
    {
        "new", "persistent", "reopened"
    };
    private static readonly string[] RequiredCompletedArtifactRoles =
    [
        "review-context", "remote-patch", "goal-context-selection", "local-findings",
        "purpose-findings", "review-result", "completion-notification"
    ];

    public static CommandOutput Start(Options options)
    {
        RequireStartArguments(options);
        var cyclePath = Path.GetFullPath(options.CyclePath!);
        var cycleRoot = Path.GetDirectoryName(cyclePath) ?? throw new ContractException("Cycle path has no parent directory.");
        Directory.CreateDirectory(cycleRoot);

        ReviewCycle cycle;
        if (File.Exists(cyclePath))
        {
            cycle = ReadCycle(cyclePath);
            ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: true);
            Equal("repository", cycle.Repository, options.Repository!);
            Equal("pull request", cycle.PullRequest, options.PullRequest);
            Equal("Goal Context path", cycle.GoalContext.Path, NormalizeSlash(options.GoalContextPath!));
            Equal("Goal Context SHA-256", cycle.GoalContext.NormalizedSha256, options.GoalContextSha!);
        }
        else
        {
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
                Status = "NOT_STARTED"
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
            if (string.IsNullOrWhiteSpace(options.AdaptiveResultReference))
            {
                throw new ContractException("Round 2 or later requires --adaptive-result-reference from the separately completed Adaptive turn.");
            }
        }
        else if (!string.IsNullOrWhiteSpace(options.AdaptiveResultReference))
        {
            throw new ContractException("Round 1 cannot declare a previous Adaptive result reference.");
        }

        ApplyOverride(options, cycle, nextRound);
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
        var roundRecord = new RoundRecord
        {
            RoundNumber = nextRound,
            ArtifactDirectory = roundDirectoryName,
            BaseOid = options.BaseOid!,
            HeadOid = options.HeadOid!,
            PreviousRound = nextRound == 1 ? null : nextRound - 1,
            StartedAt = startedAt.ToString("O"),
            Status = "IN_PROGRESS",
            AdaptiveResultReference = EmptyToNull(options.AdaptiveResultReference)
        };

        Directory.CreateDirectory(roundDirectory);
        try
        {
            cycle.Rounds.Add(roundRecord);
            cycle.CurrentRound = nextRound;
            cycle.Status = "IN_PROGRESS";
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

        var cyclePath = Path.GetFullPath(options.CyclePath);
        var cycle = ReadCycle(cyclePath);
        ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: false);
        if (cycle.Rounds.Count == 0 || cycle.Rounds[^1].Status != "IN_PROGRESS")
        {
            throw new ContractException("No in-progress review round is available to complete.");
        }

        var round = cycle.Rounds[^1];
        var cycleRoot = Path.GetDirectoryName(cyclePath)!;
        var expectedRoundDirectory = Contained(cycleRoot, round.ArtifactDirectory);
        var resultPath = Contained(expectedRoundDirectory, Path.GetRelativePath(expectedRoundDirectory, Path.GetFullPath(options.RoundResultPath)));
        if (!File.Exists(resultPath)) throw new ContractException($"Round result does not exist: {resultPath}");
        if (!IsContained(expectedRoundDirectory, resultPath)) throw new ContractException("Round result must be inside the current round directory.");

        var result = ReadJson<RoundResult>(resultPath);
        if (result.SchemaVersion != SchemaVersion) throw new ContractException("round-result schemaVersion must be 1.");
        Equal("round-result round number", round.RoundNumber, result.RoundNumber);
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
            delta = ValidateFindingDelta(cycle, round.RoundNumber, result.FindingDelta);
        }
        var actionableCount = delta.Count(item => ActiveFindingStates.Contains(item.State));
        var verdict = ComputeVerdict(cycle, round.RoundNumber, actionableCount, result.BlockedReason, result.HumanDecisionReason);
        Equal("round-result verdict", verdict, result.Verdict);
        ValidateArtifactRoles(verdict, actionableCount, artifactRecords);
        ValidateSourceCoverage(delta, result.SourceCoverage);
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
                RoundNumber = round.RoundNumber,
                Status = "PENDING",
                Reason = !string.IsNullOrWhiteSpace(result.HumanDecisionReason)
                    ? result.HumanDecisionReason!
                    : $"Actionable findings remain at effective maximum round {cycle.EffectiveMaximumRounds}."
            });
        }

        SaveCycle(cyclePath, cycle);
        return new CommandOutput(1, "PASS", round.RoundNumber, verdict, round.ArtifactDirectory, []);
    }

    public static CommandOutput Validate(Options options)
    {
        if (string.IsNullOrWhiteSpace(options.CyclePath)) throw new ContractException("validate requires --cycle.");
        var cyclePath = Path.GetFullPath(options.CyclePath);
        var cycle = ReadCycle(cyclePath);
        ValidateCycle(cyclePath, cycle, requireCompletedCurrentRound: false);
        var current = cycle.Rounds.LastOrDefault();
        return new CommandOutput(1, "PASS", current?.RoundNumber, current?.Verdict, current?.ArtifactDirectory, []);
    }

    private static void RequireStartArguments(Options options)
    {
        if (string.IsNullOrWhiteSpace(options.CyclePath) || string.IsNullOrWhiteSpace(options.Repository)
            || options.PullRequest <= 0 || string.IsNullOrWhiteSpace(options.GoalContextPath)
            || string.IsNullOrWhiteSpace(options.GoalContextSha) || string.IsNullOrWhiteSpace(options.BaseOid)
            || string.IsNullOrWhiteSpace(options.HeadOid) || string.IsNullOrWhiteSpace(options.StartedAt))
        {
            throw new ContractException("start requires cycle, repository, PR, Goal Context identity, base/head OID, and started-at.");
        }
        if (!Regex.IsMatch(options.Repository, @"^[^/\s]+/[^/\s]+$")) throw new ContractException("repository must be owner/name.");
        if (!Regex.IsMatch(options.GoalContextSha, "^[0-9a-f]{64}$")) throw new ContractException("goal-context-sha must be lowercase SHA-256.");
        RequireOid(options.BaseOid, "base-oid");
        RequireOid(options.HeadOid, "head-oid");
    }

    private static void ApplyOverride(Options options, ReviewCycle cycle, int nextRound)
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
        if (!supplied.All(value => value)) return;
        if (options.OverrideMaximumRounds <= cycle.EffectiveMaximumRounds || options.OverrideMaximumRounds < nextRound)
        {
            throw new ContractException("override maximum must increase the effective maximum and include the next round.");
        }

        var approvedAt = ParseTimestamp(options.OverrideApprovedAt!, "override-approved-at");
        cycle.Overrides.Add(new RoundOverride
        {
            StartingRound = nextRound,
            ApprovedBy = options.OverrideApprovedBy!,
            ApprovedAt = approvedAt.ToString("O"),
            Reason = options.OverrideReason!,
            MaximumRounds = options.OverrideMaximumRounds
        });
        cycle.EffectiveMaximumRounds = options.OverrideMaximumRounds;
        cycle.HumanDecisions.Add(new HumanDecision
        {
            RoundNumber = nextRound,
            Status = "APPROVED",
            Reason = $"Maximum rounds overridden to {options.OverrideMaximumRounds}: {options.OverrideReason}",
            ApprovedBy = options.OverrideApprovedBy,
            ApprovedAt = approvedAt.ToString("O")
        });
    }

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

    private static List<FindingDeltaEntry> ValidateFindingDelta(ReviewCycle cycle, int roundNumber, List<FindingDeltaEntry> entries)
    {
        var current = new Dictionary<string, FindingDeltaEntry>(StringComparer.Ordinal);
        var ledger = cycle.FindingLedger.ToDictionary(item => item.TrackingId, StringComparer.Ordinal);
        foreach (var entry in entries)
        {
            if (string.IsNullOrWhiteSpace(entry.TrackingId) || !current.TryAdd(entry.TrackingId, entry))
            {
                throw new ContractException($"Finding tracking IDs must be non-empty and unique: {entry.TrackingId}");
            }
            if (!FindingStates.Contains(entry.State)) throw new ContractException($"Invalid finding state: {entry.State}");
            if (entry.SourceIds.Count == 0 || entry.SourceIds.Any(string.IsNullOrWhiteSpace))
            {
                throw new ContractException($"Finding {entry.TrackingId} must retain at least one source ID.");
            }
            if (ActiveFindingStates.Contains(entry.State) && (entry.FindingIds.Count == 0 || entry.FindingIds.Any(string.IsNullOrWhiteSpace)))
            {
                throw new ContractException($"Active finding {entry.TrackingId} must have finding IDs.");
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

    private static void ValidateArtifactRoles(string verdict, int actionableCount, List<ArtifactRecord> artifacts)
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
        foreach (var role in RequiredCompletedArtifactRoles)
        {
            if (!roles.Contains(role)) throw new ContractException($"Missing required round artifact role: {role}");
        }
        if (actionableCount > 0 && !roles.Contains("review-plan"))
        {
            throw new ContractException("Actionable findings require a review-plan artifact.");
        }
        if (verdict == "REVIEW_COMPLETE" && roles.Contains("review-plan"))
        {
            throw new ContractException("REVIEW_COMPLETE must not include an Adaptive review-plan artifact.");
        }
    }

    private static void ValidateSourceCoverage(List<FindingDeltaEntry> delta, List<SourceCoverageEntry> coverage)
    {
        var trackingIds = delta.Select(item => item.TrackingId).ToHashSet(StringComparer.Ordinal);
        var coveredSources = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in coverage)
        {
            if (string.IsNullOrWhiteSpace(item.SourceId) || !coveredSources.Add(item.SourceId))
            {
                throw new ContractException($"Source coverage IDs must be non-empty and unique: {item.SourceId}");
            }
            if (item.Disposition == "finding")
            {
                if (item.TrackingIds.Count == 0 || item.TrackingIds.Any(id => !trackingIds.Contains(id)))
                {
                    throw new ContractException($"Source {item.SourceId} must bind to an existing finding tracking ID.");
                }
            }
            else if (item.Disposition == "noAction")
            {
                if (item.TrackingIds.Count != 0 || string.IsNullOrWhiteSpace(item.Reason))
                {
                    throw new ContractException($"noAction source {item.SourceId} requires a reason and no tracking IDs.");
                }
            }
            else
            {
                throw new ContractException($"Invalid source coverage disposition for {item.SourceId}: {item.Disposition}");
            }
        }
        foreach (var sourceId in delta.SelectMany(item => item.SourceIds).Distinct(StringComparer.Ordinal))
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
        if (cycle.SchemaVersion != SchemaVersion) throw new ContractException("review-cycle schemaVersion must be 1.");
        if (!Regex.IsMatch(cycle.Repository ?? string.Empty, @"^[^/\s]+/[^/\s]+$")) throw new ContractException("Cycle repository must be owner/name.");
        if (cycle.PullRequest <= 0) throw new ContractException("Cycle pullRequest must be positive.");
        if (!Regex.IsMatch(cycle.GoalContext.NormalizedSha256 ?? string.Empty, "^[0-9a-f]{64}$")) throw new ContractException("Cycle Goal Context SHA-256 is invalid.");
        if (cycle.DefaultMaximumRounds != DefaultMaximumRounds) throw new ContractException("defaultMaximumRounds must be 3.");
        if (cycle.EffectiveMaximumRounds < DefaultMaximumRounds) throw new ContractException("effectiveMaximumRounds cannot be below 3.");
        if (cycle.CurrentRound != cycle.Rounds.Count) throw new ContractException("currentRound must equal the number of round records.");

        var expectedEffectiveMaximum = DefaultMaximumRounds;
        var lastOverrideRound = 0;
        foreach (var roundOverride in cycle.Overrides)
        {
            if (roundOverride.StartingRound < 4 || roundOverride.StartingRound <= lastOverrideRound
                || roundOverride.MaximumRounds < roundOverride.StartingRound || roundOverride.MaximumRounds <= expectedEffectiveMaximum
                || string.IsNullOrWhiteSpace(roundOverride.ApprovedBy) || string.IsNullOrWhiteSpace(roundOverride.Reason))
            {
                throw new ContractException("Cycle contains an invalid or non-increasing human round override.");
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
            Equal("round artifact directory", $"round-{expectedNumber:000}", round.ArtifactDirectory);
            Equal("previous round reference", expectedNumber == 1 ? null : expectedNumber - 1, round.PreviousRound);
            RequireOid(round.BaseOid, $"round {expectedNumber} base OID");
            RequireOid(round.HeadOid, $"round {expectedNumber} head OID");
            if (!heads.Add(round.HeadOid)) throw new ContractException($"Duplicate reviewed head OID in cycle: {round.HeadOid}");
            if (expectedNumber == 1 && !string.IsNullOrWhiteSpace(round.AdaptiveResultReference)) throw new ContractException("Round 1 cannot have an Adaptive result reference.");
            if (expectedNumber > 1 && string.IsNullOrWhiteSpace(round.AdaptiveResultReference)) throw new ContractException($"Round {expectedNumber} is missing its previous Adaptive result reference.");
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
                ValidateArtifactRoles(round.Verdict!, actionable, round.Artifacts);
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
            ? current.Status == "IN_PROGRESS" ? "IN_PROGRESS" : current.Verdict
            : "NOT_STARTED";
        Equal("cycle status", expectedStatus, cycle.Status);
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
        return fullPath;
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
        if (!DateTimeOffset.TryParse(value, out var parsed)) throw new ContractException($"{name} must be an ISO-8601 timestamp.");
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
    public string? RoundResultPath { get; private set; }
    public int OverrideMaximumRounds { get; private set; }
    public string? OverrideApprovedBy { get; private set; }
    public string? OverrideApprovedAt { get; private set; }
    public string? OverrideReason { get; private set; }
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
                case "--round-result": options.RoundResultPath = Value(args, ref i, "--round-result"); break;
                case "--override-maximum-rounds": options.OverrideMaximumRounds = PositiveInt(args, ref i, "--override-maximum-rounds"); break;
                case "--override-approved-by": options.OverrideApprovedBy = Value(args, ref i, "--override-approved-by"); break;
                case "--override-approved-at": options.OverrideApprovedAt = Value(args, ref i, "--override-approved-at"); break;
                case "--override-reason": options.OverrideReason = Value(args, ref i, "--override-reason"); break;
                case "--format":
                    options.Format = Value(args, ref i, "--format").ToLowerInvariant();
                    if (options.Format is not ("json" or "text")) options.Valid = false;
                    break;
                case "--help":
                case "-h": options.ShowHelp = true; break;
                default: options.Valid = false; break;
            }
        }
        if (options.Command is not ("start" or "complete" or "validate")) options.Valid = false;
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

sealed class RoundRecord
{
    public int RoundNumber { get; set; }
    public string ArtifactDirectory { get; set; } = string.Empty;
    public string BaseOid { get; set; } = string.Empty;
    public string HeadOid { get; set; } = string.Empty;
    public int? PreviousRound { get; set; }
    public string StartedAt { get; set; } = string.Empty;
    public string? CompletedAt { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? Verdict { get; set; }
    public string? AdaptiveResultReference { get; set; }
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
    public int RoundNumber { get; set; }
    public string Status { get; set; } = string.Empty;
    public string Reason { get; set; } = string.Empty;
    public string? ApprovedBy { get; set; }
    public string? ApprovedAt { get; set; }
}
