namespace CodexLocalInbox.Models;

public sealed record InboxEntry(
    string FilePath,
    SpoolItemV1? Item,
    string? ErrorMessage)
{
    public BrokerTerminalEventV1? BrokerItem { get; init; }
    public bool IsError => Item is null && BrokerItem is null;
    public string Identity => Item?.SourceEventId ?? BrokerItem?.SourceEventId ?? FilePath;
    public string SourceEventId => Item?.SourceEventId ?? BrokerItem?.SourceEventId ?? FilePath;
    public string Title => Item?.Title ?? BrokerItem?.Title ?? "Unreadable notification";
    public string Repository => Item?.Repository ?? BrokerItem?.Repository ?? "Local spool";
    public string ObservedStatus => Item?.ObservedStatus ?? BrokerItem?.ObservedStatus ?? "Error";
    public DateTimeOffset? OccurredAt => Item?.OccurredAt ?? BrokerItem?.OccurredAt;
    public string? ResumeUri => Item?.ResumeUri;
    public string? ResultUri => Item?.ResultUri;
    public string? ResultLocator => BrokerItem?.ResultLocator;
    public bool HasResultLocator => !string.IsNullOrEmpty(ResultLocator);
    public string DisplayError => ErrorMessage ?? "The file could not be read.";
    public bool HasResult => !string.IsNullOrEmpty(ResultUri);
    public string OccurredDisplay => OccurredAt is { } value
        ? value.ToLocalTime().ToString("g")
        : "Unavailable";
    public string EntryAutomationId
    {
        get
        {
            var hash = System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(Identity));
            return "Entry_" + Convert.ToHexString(hash)[..12];
        }
    }

    public string ResumeAutomationId => $"{EntryAutomationId}_Resume";
    public string ResultAutomationId => $"{EntryAutomationId}_OpenResult";
    public string CopyLocatorAutomationId => $"{EntryAutomationId}_CopyLocator";
    public string DeleteAutomationId => $"{EntryAutomationId}_Delete";
}
