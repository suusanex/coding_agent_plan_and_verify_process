using System.Text.Json;
using System.Text.Json.Serialization;

namespace PurposeReviewRunner;

public static class Protocol
{
    public const int Version = 4;
    public const int JobSchemaVersion = 2;
    public const int MaximumRounds = 3;
    public const string RunnerVersion = "0.5.0";
    public const int InputSchemaVersion = 1;
    public const string ReviewKind = "purpose-design-alignment";
}

public sealed record PurposeDocument(string Version, IReadOnlyList<string> Sources, string Body, string Original, string Authority);
public sealed record ApprovedDesign(string Version, string Body, string Authority);
public sealed record ProposalDocument(string Version, string Body, string Delta);
public sealed record EvidenceItem(string Id, string Source, string Body);
public sealed record ResponseItem(string FindingId, string Body, IReadOnlyList<string> Evidence);
public sealed record ConformanceItem(string Owner, string Plan, IReadOnlyList<string> Evidence);
public sealed record UserDecision(string Body, string Authority);

public sealed record ReviewInput(
    int SchemaVersion,
    string TaskKey,
    string ChangeId,
    string? PreviousRunId,
    PurposeDocument Purpose,
    ApprovedDesign? ApprovedDesign,
    ProposalDocument Proposal,
    IReadOnlyList<EvidenceItem> Evidence,
    IReadOnlyList<ResponseItem> Responses,
    IReadOnlyList<ConformanceItem> Conformance,
    UserDecision? UserDecision = null,
    IReadOnlyList<ReviewHistoryEntry>? PriorReviewHistory = null);

public sealed record InputBinding(
    string PurposeHash,
    string PurposeVersion,
    string? ApprovedDesignHash,
    string? ApprovedDesignVersion,
    string ProposalHash,
    string ProposalVersion);

public static class ReviewNonGuarantees
{
    public static readonly IReadOnlyList<string> Items =
    [
        "implementation-conformance-not-assessed",
        "evidence-not-independently-verified",
        "tests-not-executed",
        "user-approval-not-implied",
        "runtime-purpose-achievement-not-verified",
        "release-readiness-not-assessed",
        "task-completion-not-certified"
    ];
}

public static class ExitCodes
{
    public const int Success = 0;
    public const int RuntimeError = 1;
    public const int ContractError = 2;
}

public static class ReviewStatuses
{
    public const string Running = "RUNNING";
    public const string Findings = "FINDINGS";
    public const string Complete = "COMPLETE";
    public const string HumanDecisionRequired = "HUMAN_DECISION_REQUIRED";
    public const string Blocked = "BLOCKED";
    public const string Error = "ERROR";

    public static bool IsTerminal(string status) => status is Complete or HumanDecisionRequired or Blocked or Error;
}

public static class JobStatuses
{
    public const string Running = "RUNNING";
    public const string Succeeded = "SUCCEEDED";
    public const string Failed = "FAILED";
}

public static class JobOperations
{
    public const string Start = "start";
    public const string Continue = "continue";
}

public sealed record RunnerError(string Code, string Message);

public sealed record ReviewFinding(
    string Id,
    string Severity,
    string Title,
    string Summary,
    string Evidence,
    string RequiredOutcome);

public sealed record InformationRequest(string Id, string Source, string Question, string WhyNeeded);

public sealed record ReviewerResponse(
    string Status,
    IReadOnlyList<ReviewFinding> Findings,
    string? Message,
    IReadOnlyList<InformationRequest> InformationRequests = null!);

public sealed record ReviewHistoryEntry(
    int Round,
    string Status,
    IReadOnlyList<ReviewFinding> Findings,
    string? Message,
    IReadOnlyList<InformationRequest> InformationRequests);

public sealed record RunnerOutput(
    int ProtocolVersion,
    string RunnerVersion,
    string? RunId,
    int? Round,
    string Status,
    bool Terminal,
    IReadOnlyList<ReviewFinding> Findings,
    string? Message,
    RunnerError? Error,
    string? JobStatus = null,
    string? ReviewKind = null,
    InputBinding? InputBinding = null,
    string? InputHash = null,
    IReadOnlyList<InformationRequest>? InformationRequests = null,
    IReadOnlyList<string>? NonGuarantees = null)
{
    public static RunnerOutput FromReview(string runId, int round, ReviewerResponse response, InputBinding binding, string inputHash) =>
        new(
            Protocol.Version,
            Protocol.RunnerVersion,
            runId,
            round,
            response.Status,
            ReviewStatuses.IsTerminal(response.Status),
            response.Findings,
            response.Message,
            null,
            JobStatuses.Succeeded,
            Protocol.ReviewKind,
            binding,
            inputHash,
            response.InformationRequests,
            ReviewNonGuarantees.Items);

    public static RunnerOutput Running(string runId, int round) =>
        new(Protocol.Version, Protocol.RunnerVersion, runId, round, ReviewStatuses.Running, false, [], null, null, JobStatuses.Running);

    public static RunnerOutput Version() =>
        new(Protocol.Version, Protocol.RunnerVersion, null, null, "COMPLETE", true, [], null, null);

    public static RunnerOutput FromError(string code, string message, string? runId = null, int? round = null, string? jobStatus = null) =>
        new(Protocol.Version, Protocol.RunnerVersion, runId, round, ReviewStatuses.Error, true, [], null, new(code, message), jobStatus);
}

public sealed record JobResult(RunnerOutput Output, int ExitCode);

public sealed record JobState(
    int SchemaVersion,
    string RunId,
    int Round,
    string Operation,
    string JobStatus,
    DateTimeOffset StartedAtUtc,
    int? Pid = null,
    DateTimeOffset? ProcessStartTimeUtc = null,
    DateTimeOffset? FinishedAtUtc = null,
    string? Repository = null,
    ProviderSnapshot? Provider = null,
    string? InputHash = null,
    int DurableSubmissions = 1);

public sealed record WorkerLaunchResult(int ProcessId, DateTimeOffset ProcessStartTimeUtc);

public interface IWorkerLauncher
{
    WorkerLaunchResult Launch(string runId);
}

public sealed record ExecutionResult(RunnerOutput Output, int ExitCode);

public sealed record RunnerConfig(
    int SchemaVersion,
    string Provider,
    string Executable,
    string Model,
    string ReasoningEffort,
    string? Profile);

public sealed record ProviderSnapshot(
    string Provider,
    string Executable,
    string Model,
    string ReasoningEffort,
    string? Profile);

public sealed record RunState(
    int ProtocolVersion,
    string RunId,
    string Repository,
    ProviderSnapshot Provider,
    string SessionHandle,
    int Round,
    string Status,
    string TaskKey = "",
    string ChangeId = "",
    string ReviewKind = Protocol.ReviewKind,
    InputBinding? InputBinding = null,
    int DurableSubmissions = 1,
    string? PreviousRunId = null,
    IReadOnlyList<ReviewHistoryEntry>? ReviewHistory = null);

public static class JsonDefaults
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
}

public sealed class RunnerException : Exception
{
    public RunnerException(string code, string message, int exitCode = ExitCodes.ContractError, Exception? innerException = null)
        : base(message, innerException)
    {
        Code = code;
        ExitCode = exitCode;
    }

    public string Code { get; }
    public int ExitCode { get; }
}
