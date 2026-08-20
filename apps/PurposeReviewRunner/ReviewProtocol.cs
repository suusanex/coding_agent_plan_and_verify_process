using System.Text.Json;
using System.Text.RegularExpressions;

namespace PurposeReviewRunner;

public static partial class ReviewProtocol
{
    private static readonly HashSet<string> AllowedStatuses = new(StringComparer.Ordinal)
    {
        ReviewStatuses.Findings,
        ReviewStatuses.Complete,
        ReviewStatuses.HumanDecisionRequired,
        ReviewStatuses.Blocked
    };

    private static readonly HashSet<string> AllowedSeverities = new(StringComparer.Ordinal)
    {
        "CRITICAL", "HIGH", "MEDIUM", "LOW"
    };

    public static ReviewerResponse Parse(string output)
    {
        if (string.IsNullOrWhiteSpace(output))
        {
            throw Invalid("Reviewer returned an empty response.");
        }
        var matches = ReviewBlockRegex().Matches(output);
        if (matches.Count != 1)
        {
            throw Invalid("Reviewer must return exactly one BEGIN_PURPOSE_REVIEW block.");
        }

        ReviewerResponse response;
        try
        {
            response = JsonSerializer.Deserialize<ReviewerResponse>(matches[0].Groups[1].Value, JsonDefaults.Options)
                ?? throw new JsonException("Review JSON was empty.");
        }
        catch (Exception exception) when (exception is JsonException or NotSupportedException)
        {
            throw new RunnerException("REVIEW_PARSE_FAILED", $"Reviewer JSON was invalid: {exception.Message}", ExitCodes.ContractError, exception);
        }

        if (!AllowedStatuses.Contains(response.Status))
        {
            throw Invalid($"Unsupported reviewer status: {response.Status}");
        }
        if (response.Findings is null)
        {
            throw Invalid("findings is required.");
        }
        if (response.Status == ReviewStatuses.Findings && response.Findings.Count == 0)
        {
            throw Invalid("FINDINGS requires at least one finding.");
        }
        if (response.Status == ReviewStatuses.Complete && response.Findings.Count != 0)
        {
            throw Invalid("COMPLETE must not include findings.");
        }
        if (response.Status is ReviewStatuses.HumanDecisionRequired or ReviewStatuses.Blocked && string.IsNullOrWhiteSpace(response.Message))
        {
            throw Invalid($"{response.Status} requires message.");
        }
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var finding in response.Findings)
        {
            if (string.IsNullOrWhiteSpace(finding.Id) || !ids.Add(finding.Id) ||
                string.IsNullOrWhiteSpace(finding.Title) || string.IsNullOrWhiteSpace(finding.Summary) ||
                string.IsNullOrWhiteSpace(finding.Evidence) || string.IsNullOrWhiteSpace(finding.RequiredChange) ||
                !AllowedSeverities.Contains(finding.Severity))
            {
                throw Invalid("Each finding requires a unique id, supported severity, title, summary, evidence, and requiredChange.");
            }
        }
        return response;
    }

    private static RunnerException Invalid(string message) =>
        new("REVIEW_PARSE_FAILED", message, ExitCodes.ContractError);

    [GeneratedRegex(@"BEGIN_PURPOSE_REVIEW\s*(\{.*?\})\s*END_PURPOSE_REVIEW", RegexOptions.Singleline | RegexOptions.CultureInvariant)]
    private static partial Regex ReviewBlockRegex();
}
