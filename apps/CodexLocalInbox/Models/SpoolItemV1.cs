namespace CodexLocalInbox.Models;

public sealed record SpoolItemV1(
    int SchemaVersion,
    string Source,
    string SourceEventId,
    string PrimaryProcess,
    string ObservedStatus,
    DateTimeOffset OccurredAt,
    string Title,
    string Repository,
    string ResumeUri,
    string? ResultUri);
