namespace CodexLocalInbox.Models;

public sealed record BrokerTerminalEventV1(
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
