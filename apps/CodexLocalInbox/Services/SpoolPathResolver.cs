namespace CodexLocalInbox.Services;

public sealed class SpoolPathResolver
{
    public const string EnvironmentVariable = "CODEX_NOTIFICATION_SPOOL_HOME";

    public string Resolve()
    {
        var configured = Environment.GetEnvironmentVariable(EnvironmentVariable);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            if (!Path.IsPathFullyQualified(configured))
            {
                throw new ArgumentException($"{EnvironmentVariable} must be an absolute path.", nameof(configured));
            }

            return Path.GetFullPath(configured);
        }

        return Path.GetFullPath(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CodexNotificationRuntime",
            "spool"));
    }
}
