namespace CodexLocalInbox.Models;

public sealed record InboxEntry(
    string FilePath,
    SpoolItemV1? Item,
    string? ErrorMessage)
{
    public bool IsError => Item is null;
    public string Identity => Item?.SourceEventId ?? FilePath;
    public string Title => Item?.Title ?? "Unreadable notification";
    public string Repository => Item?.Repository ?? "Local spool";
    public string ObservedStatus => Item?.ObservedStatus ?? "Error";
    public DateTimeOffset? OccurredAt => Item?.OccurredAt;
    public string? ResumeUri => Item?.ResumeUri;
    public string? ResultUri => Item?.ResultUri;
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
    public string DeleteAutomationId => $"{EntryAutomationId}_Delete";
}
