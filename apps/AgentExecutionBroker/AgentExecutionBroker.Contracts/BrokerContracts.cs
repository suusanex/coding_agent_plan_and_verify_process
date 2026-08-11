using System.Text.Json;

namespace AgentExecutionBroker.Contracts;

public static class BrokerProtocol
{
    public const string PipeName = "agent-execution-broker.v1";
    public const string CodingProfile = "coding-v1";
    public const int DefaultOutputRecords = 200;
    public const int MaximumOutputRecords = 500;
    public const int DefaultOutputBytes = 256 * 1024;
    public const int MaximumOutputBytes = 1024 * 1024;
    public const int DefaultRunLimit = 50;
    public const int MaximumRunLimit = 100;
    public const int MaximumOutputRecordBytes = 16 * 1024;
}

public sealed record BrokerRequest(string Operation, JsonElement Payload);
public sealed record BrokerResponse(bool Succeeded, JsonElement? Result, string? ErrorCode, string? ErrorMessage)
{
    public static BrokerResponse Success(JsonElement result) => new(true, result, null, null);
    public static BrokerResponse Failure(string code, string message) => new(false, null, code, message);
}

public sealed record StartRunRequest(
    string ProviderId,
    string WorkingDirectory,
    string Prompt,
    string ExecutionProfile,
    string? Repository);

public sealed record RunQuery(Guid RunId);
public sealed record ListRunsRequest(int? Limit, string? Cursor);
public sealed record OutputQuery(Guid RunId, long? AfterSequence, int? MaxRecords, int? MaxBytes);

public sealed record RunRecord(
    Guid RunId,
    string ProviderId,
    string WorkingDirectory,
    string Prompt,
    string ExecutionProfile,
    string? Repository,
    string State,
    DateTimeOffset AcceptedAt,
    DateTimeOffset? StartedAt,
    DateTimeOffset? CompletedAt,
    int? ExitCode,
    bool CancelRequested,
    string? CancelDelivery,
    string? Diagnostic,
    string? NotificationDisposition);

public sealed record OutputRecord(long Sequence, DateTimeOffset OccurredAt, string Stream, string Text);
public sealed record OutputPage(
    Guid RunId,
    IReadOnlyList<OutputRecord> Records,
    long NextAfterSequence,
    bool HasMore,
    string? TruncationReason);

public sealed record RunPage(IReadOnlyList<RunRecord> Runs, string? NextCursor, bool HasMore);

public sealed record TerminalEventV1(
    int SchemaVersion,
    string Source,
    string SourceEventId,
    Guid RunId,
    string ProviderId,
    string ObservedStatus,
    DateTimeOffset OccurredAt,
    string Title,
    string ResultLocator,
    string? Repository);
