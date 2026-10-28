using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Diagnostics;

namespace PurposeReviewRunner;

public sealed record StoredReviewInput(ReviewInput Input, string Hash, InputBinding Binding);

public sealed class ReviewInputStore
{
    private readonly string root;

    public ReviewInputStore(string root) => this.root = Path.GetFullPath(root);

    public StoredReviewInput ReadAndValidate(string path)
    {
        ReviewInput input;
        try
        {
            input = JsonSerializer.Deserialize<ReviewInput>(File.ReadAllText(path), JsonDefaults.Options)
                ?? throw new JsonException("Input JSON was empty.");
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("INPUT_INVALID", $"Review input could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }

        Validate(input, allowRunnerHistory: false);
        return Snapshot(input);
    }

    public void Save(string runId, int round, StoredReviewInput stored)
    {
        var path = GetInputPath(runId, round);
        try
        {
            SharedStateFile.WriteAtomic(path, JsonSerializer.Serialize(stored, JsonDefaults.Options) + Environment.NewLine);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("STATE_WRITE_FAILED", "Review input snapshot could not be saved.", ExitCodes.ContractError, exception);
        }
    }

    public StoredReviewInput Load(string runId, int round)
    {
        try
        {
            var stored = JsonSerializer.Deserialize<StoredReviewInput>(SharedStateFile.ReadAllText(GetInputPath(runId, round)), JsonDefaults.Options)
                ?? throw new JsonException("Input snapshot was empty.");
            Validate(stored.Input, allowRunnerHistory: true);
            if (stored.Hash != Hash(stored.Input) || stored.Binding != Binding(stored.Input))
            {
                throw new RunnerException("STATE_INCOMPATIBLE", "Review input snapshot integrity check failed.");
            }
            return stored;
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("INPUT_INVALID", $"Review input snapshot could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }
    }

    public static StoredReviewInput Snapshot(ReviewInput input) => new(input, Hash(input), Binding(input));

    public string GetInputPath(string runId, int round)
    {
        if (!Guid.TryParseExact(runId, "D", out _) || round is < 1 or > Protocol.MaximumRounds)
        {
            throw new RunnerException("JOB_INVALID", "Input snapshot identity is invalid.");
        }
        return Path.Combine(root, runId, $"input-{round}.json");
    }

    private static void Validate(ReviewInput input, bool allowRunnerHistory)
    {
        static bool Text(string? value) => !string.IsNullOrWhiteSpace(value);
        if (input.SchemaVersion != Protocol.InputSchemaVersion || !Text(input.TaskKey) || !Text(input.ChangeId) ||
            (input.PreviousRunId is not null && !Guid.TryParseExact(input.PreviousRunId, "D", out _)) ||
            input.Purpose is null || !Text(input.Purpose.Version) || input.Purpose.Sources is null || input.Purpose.Sources.Count == 0 ||
            input.Purpose.Sources.Any(source => !Text(source)) || !Text(input.Purpose.Body) || !Text(input.Purpose.Original) || !Text(input.Purpose.Authority) ||
            input.Proposal is null || !Text(input.Proposal.Version) || !Text(input.Proposal.Body) || !Text(input.Proposal.Delta) ||
            input.Evidence is null || input.Responses is null || input.Conformance is null ||
            (!allowRunnerHistory && input.PriorReviewHistory is { Count: > 0 }))
        {
            throw new RunnerException("INPUT_INVALID", "Review input is missing required fields or has an unsupported schema version.");
        }
        if (input.ApprovedDesign is { } design && (!Text(design.Version) || !Text(design.Body) || !Text(design.Authority)))
        {
            throw new RunnerException("INPUT_INVALID", "approvedDesign requires version, body, and authority.");
        }
        if (input.UserDecision is { } decision && (!Text(decision.Body) || !Text(decision.Authority)))
        {
            throw new RunnerException("INPUT_INVALID", "userDecision requires body and authority.");
        }
        var evidenceIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var evidence in input.Evidence)
        {
            if (evidence is null || !Text(evidence.Id) || !evidenceIds.Add(evidence.Id) || !Text(evidence.Source) || !Text(evidence.Body))
            {
                throw new RunnerException("INPUT_INVALID", "Each evidence item requires a unique id, source, and body.");
            }
        }
        if (input.Responses.Any(response => response is null || !Text(response.FindingId) || !Text(response.Body) || response.Evidence is null || response.Evidence.Any(id => !evidenceIds.Contains(id))) ||
            input.Conformance.Any(item => item is null || !Text(item.Owner) || !Text(item.Plan) || item.Evidence is null || item.Evidence.Any(id => !evidenceIds.Contains(id))))
        {
            throw new RunnerException("INPUT_INVALID", "Responses and conformance entries must contain text and reference supplied evidence ids.");
        }
    }

    private static string Hash<T>(T value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value, JsonDefaults.Options)))).ToLowerInvariant();
    private static string Hash(ReviewInput input) => Hash<ReviewInput>(input);
    private static InputBinding Binding(ReviewInput input) => new(
        Hash(input.Purpose), input.Purpose.Version,
        input.ApprovedDesign is null ? null : Hash(input.ApprovedDesign),
        input.ApprovedDesign?.Version,
        Hash(input.Proposal), input.Proposal.Version);
}

public sealed record TaskLineage(string Repository, string TaskKey, string ChangeId, string LatestRunId, string LatestStatus, int DurableSubmissions, string InputHash);

public sealed class TaskLineageStore
{
    private readonly string root;
    public TaskLineageStore(string root) => this.root = Path.Combine(Path.GetFullPath(root), "lineages");

    public IDisposable Acquire(string repository, string taskKey)
    {
        var directory = GetDirectory(repository, taskKey);
        Directory.CreateDirectory(directory);
        try
        {
            return new FileStream(Path.Combine(directory, "lineage.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException exception)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("TASK_BUSY", "Another submission is updating this task lineage.", ExitCodes.ContractError, exception);
        }
    }

    public TaskLineage? Load(string repository, string taskKey)
    {
        var path = Path.Combine(GetDirectory(repository, taskKey), "lineage.json");
        if (!File.Exists(path)) return null;
        try
        {
            return JsonSerializer.Deserialize<TaskLineage>(SharedStateFile.ReadAllText(path), JsonDefaults.Options)
                ?? throw new JsonException("Lineage JSON was empty.");
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("STATE_INVALID", $"Task lineage could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }
    }

    public void Save(TaskLineage lineage)
    {
        try
        {
            SharedStateFile.WriteAtomic(Path.Combine(GetDirectory(lineage.Repository, lineage.TaskKey), "lineage.json"), JsonSerializer.Serialize(lineage, JsonDefaults.Options) + Environment.NewLine);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("STATE_WRITE_FAILED", "Task lineage could not be saved.", ExitCodes.ContractError, exception);
        }
    }

    private string GetDirectory(string repository, string taskKey)
    {
        var normalizedRepository = Path.TrimEndingDirectorySeparator(Path.GetFullPath(repository));
        if (OperatingSystem.IsWindows()) normalizedRepository = normalizedRepository.ToUpperInvariant();
        var identity = normalizedRepository + "\n" + taskKey;
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(identity))).ToLowerInvariant();
        return Path.Combine(root, hash);
    }
}
