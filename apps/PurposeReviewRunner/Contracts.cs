using System.Text.Json;
using System.Text.Json.Serialization;

namespace PurposeReviewRunner;

public static class Protocol
{
    public const int Version = 1;
    public const int MaximumRounds = 3;
    public const string RunnerVersion = "0.1.0";
}

public static class ExitCodes
{
    public const int Success = 0;
    public const int RuntimeError = 1;
    public const int ContractError = 2;
}

public static class ReviewStatuses
{
    public const string Findings = "FINDINGS";
    public const string Complete = "COMPLETE";
    public const string HumanDecisionRequired = "HUMAN_DECISION_REQUIRED";
    public const string Blocked = "BLOCKED";
    public const string Error = "ERROR";

    public static bool IsTerminal(string status) => status is Complete or HumanDecisionRequired or Blocked or Error;
}

public sealed record RunnerError(string Code, string Message);

public sealed record ReviewFinding(
    string Id,
    string Severity,
    string Title,
    string Summary,
    string Evidence,
    string RequiredChange);

public sealed record ReviewerResponse(
    string Status,
    IReadOnlyList<ReviewFinding> Findings,
    string? Message);

public sealed record RunnerOutput(
    int ProtocolVersion,
    string RunnerVersion,
    string? RunId,
    int? Round,
    string Status,
    bool Terminal,
    IReadOnlyList<ReviewFinding> Findings,
    string? Message,
    RunnerError? Error)
{
    public static RunnerOutput FromReview(string runId, int round, ReviewerResponse response) =>
        new(
            Protocol.Version,
            Protocol.RunnerVersion,
            runId,
            round,
            response.Status,
            ReviewStatuses.IsTerminal(response.Status),
            response.Findings,
            response.Message,
            null);

    public static RunnerOutput Version() =>
        new(Protocol.Version, Protocol.RunnerVersion, null, null, "COMPLETE", true, [], null, null);

    public static RunnerOutput FromError(string code, string message, string? runId = null, int? round = null) =>
        new(Protocol.Version, Protocol.RunnerVersion, runId, round, ReviewStatuses.Error, true, [], null, new(code, message));
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
    IReadOnlyList<string> ContextPaths,
    ProviderSnapshot Provider,
    string SessionHandle,
    int Round,
    string Status);

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
