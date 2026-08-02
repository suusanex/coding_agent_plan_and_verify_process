namespace CodexLocalInbox.Services;

public static class UriLaunchPolicy
{
    public static bool TryGetResumeUri(string? value, out Uri uri)
    {
        uri = null!;
        if (string.IsNullOrWhiteSpace(value) ||
            !Uri.TryCreate(value, UriKind.Absolute, out var candidate) ||
            !candidate.Scheme.Equals("codex", StringComparison.OrdinalIgnoreCase) ||
            !candidate.Host.Equals("threads", StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrEmpty(candidate.UserInfo) ||
            candidate.Port != -1 ||
            candidate.Query.Length != 0 ||
            candidate.Fragment.Length != 0)
        {
            return false;
        }

        var path = candidate.AbsolutePath;
        if (path.Length <= 1 || path[0] != '/' || path[1..].Contains('/'))
        {
            return false;
        }

        uri = candidate;
        return true;
    }

    public static bool TryGetResultUri(string? value, out Uri uri)
    {
        uri = null!;
        if (string.IsNullOrWhiteSpace(value) ||
            !Uri.TryCreate(value, UriKind.Absolute, out var candidate) ||
            !candidate.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.Ordinal) ||
            !string.IsNullOrEmpty(candidate.UserInfo) ||
            string.IsNullOrWhiteSpace(candidate.Host))
        {
            return false;
        }

        uri = candidate;
        return true;
    }
}
