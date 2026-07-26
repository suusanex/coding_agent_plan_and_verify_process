#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

var options = Options.Parse(args);

if (options.ShowHelp)
{
    ShowUsage();
    return 0;
}

try
{
    options.Validate();
    var outputDirectory = Path.GetFullPath(options.OutputDirectory);
    var result = await CollectAsync(options);
    var patch = await RunGhAsync(
        options.GhExecutable,
        "pr", "diff", options.PullRequestNumber.ToString(),
        "--repo", options.Repository,
        "--patch");
    var finalIdentityJson = await FetchPullRequestAsync(options);
    ValidateJsonObject(finalIdentityJson, "final gh pr view");
    EnsureIdentityUnchanged(result.Identity, ReadAndValidateIdentity(finalIdentityJson, options));

    Directory.CreateDirectory(outputDirectory);
    var jsonPath = Path.Combine(outputDirectory, "review-context.json");
    var markdownPath = Path.Combine(outputDirectory, "review-context.md");
    var patchPath = Path.Combine(outputDirectory, "pr-diff.patch");

    File.WriteAllText(jsonPath, BuildJson(options, result), Encoding.UTF8);
    File.WriteAllText(markdownPath, BuildMarkdown(options, result), Encoding.UTF8);
    File.WriteAllText(patchPath, patch, Encoding.UTF8);

    Console.WriteLine("PR review context collected.");
    Console.WriteLine($"JSON: {jsonPath}");
    Console.WriteLine($"Markdown: {markdownPath}");
    Console.WriteLine($"Remote patch: {patchPath}");
    return 0;
}
catch (Exception ex)
{
    Trace.WriteLine(ex.ToString());
    Console.Error.WriteLine("Error: failed to collect PR review context.");
    Console.Error.WriteLine(ex.Message);
    return 1;
}

static async Task<CollectionResult> CollectAsync(Options options)
{
    var startedAt = DateTimeOffset.UtcNow;
    var snapshot = await FetchSnapshotAsync(options);
    var identity = ReadAndValidateIdentity(snapshot.PullRequestJson, options);

    if (!options.WaitForCopilot)
    {
        var observation = AnalyzeCopilot(snapshot, identity.HeadOid);
        return new CollectionResult(
            snapshot,
            identity,
            BuildWaitResult("disabled", false, startedAt, DateTimeOffset.UtcNow, options, observation, 0));
    }

    string? previousSignature = null;
    var stableSamples = 0;

    while (true)
    {
        var currentIdentity = ReadAndValidateIdentity(snapshot.PullRequestJson, options);
        EnsureIdentityUnchanged(identity, currentIdentity);
        var observation = AnalyzeCopilot(snapshot, identity.HeadOid);

        if (observation.IsComplete)
        {
            if (string.Equals(previousSignature, observation.Signature, StringComparison.Ordinal))
            {
                stableSamples++;
            }
            else
            {
                previousSignature = observation.Signature;
                stableSamples = 1;
            }

            if (stableSamples >= options.CopilotStableSamples)
            {
                return new CollectionResult(
                    snapshot,
                    identity,
                    BuildWaitResult("completed", false, startedAt, DateTimeOffset.UtcNow, options, observation, stableSamples));
            }
        }
        else
        {
            previousSignature = null;
            stableSamples = 0;
        }

        var elapsed = DateTimeOffset.UtcNow - startedAt;
        var timeout = TimeSpan.FromSeconds(options.CopilotTimeoutSeconds);
        if (elapsed >= timeout)
        {
            return new CollectionResult(
                snapshot,
                identity,
                BuildWaitResult("timeout", true, startedAt, DateTimeOffset.UtcNow, options, observation, stableSamples));
        }

        var delay = TimeSpan.FromSeconds(options.CopilotPollIntervalSeconds);
        var remaining = timeout - elapsed;
        if (delay > remaining)
        {
            delay = remaining;
        }

        await Task.Delay(delay);
        snapshot = await FetchSnapshotAsync(options);
    }
}

static async Task<SnapshotData> FetchSnapshotAsync(Options options)
{
    var pullRequest = await FetchPullRequestAsync(options);

    var reviews = await FetchPaginatedArrayAsync(
        options,
        $"repos/{options.Owner}/{options.Name}/pulls/{options.PullRequestNumber}/reviews");
    var issueComments = await FetchPaginatedArrayAsync(
        options,
        $"repos/{options.Owner}/{options.Name}/issues/{options.PullRequestNumber}/comments");
    var inlineComments = await FetchPaginatedArrayAsync(
        options,
        $"repos/{options.Owner}/{options.Name}/pulls/{options.PullRequestNumber}/comments");

    ValidateJsonObject(pullRequest, "gh pr view");
    ValidateJsonArray(reviews, "pull request reviews");
    ValidateJsonArray(issueComments, "pull request issue comments");
    ValidateJsonArray(inlineComments, "pull request inline comments");
    return new SnapshotData(pullRequest, reviews, issueComments, inlineComments);
}

static Task<string> FetchPullRequestAsync(Options options)
{
    return RunGhAsync(
        options.GhExecutable,
        "pr", "view", options.PullRequestNumber.ToString(),
        "--repo", options.Repository,
        "--json",
        "number,title,state,author,body,url,baseRefName,baseRefOid,headRefName,headRefOid,isDraft,mergeable,reviewDecision,statusCheckRollup,files");
}

static async Task<string> FetchPaginatedArrayAsync(Options options, string endpoint)
{
    var raw = await RunGhAsync(options.GhExecutable, "api", endpoint, "--paginate", "--slurp");
    using var document = JsonDocument.Parse(raw);
    if (document.RootElement.ValueKind != JsonValueKind.Array)
    {
        throw new InvalidOperationException($"Expected a paginated JSON array from {endpoint}.");
    }

    using var stream = new MemoryStream();
    using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
    {
        writer.WriteStartArray();
        foreach (var page in document.RootElement.EnumerateArray())
        {
            if (page.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in page.EnumerateArray())
                {
                    item.WriteTo(writer);
                }
            }
            else if (page.ValueKind == JsonValueKind.Object)
            {
                page.WriteTo(writer);
            }
            else
            {
                throw new InvalidOperationException($"Unexpected paginated JSON item from {endpoint}.");
            }
        }

        writer.WriteEndArray();
    }

    return Encoding.UTF8.GetString(stream.ToArray());
}

static TargetIdentity ReadAndValidateIdentity(string pullRequestJson, Options options)
{
    using var document = JsonDocument.Parse(pullRequestJson);
    var root = document.RootElement;
    var identity = new TargetIdentity(
        Number: GetInt64(root, "number"),
        Url: GetString(root, "url"),
        State: GetString(root, "state"),
        IsDraft: GetBoolean(root, "isDraft"),
        BaseBranch: GetString(root, "baseRefName"),
        BaseOid: GetString(root, "baseRefOid"),
        HeadBranch: GetString(root, "headRefName"),
        HeadOid: GetString(root, "headRefOid"));

    if (identity.Number != options.PullRequestNumber)
    {
        throw new InvalidOperationException($"Resolved PR number {identity.Number} does not match requested PR {options.PullRequestNumber}.");
    }

    if (!string.Equals(identity.State, "OPEN", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException($"The target PR is not open. Current state: {identity.State}.");
    }

    if (identity.IsDraft)
    {
        throw new InvalidOperationException("The target PR is a draft. GitHub Copilot review does not run for draft PRs. Mark it ready for review before collecting review context.");
    }

    foreach (var value in new[] { identity.Url, identity.BaseBranch, identity.BaseOid, identity.HeadBranch, identity.HeadOid })
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException("The target PR does not have a complete base/head identity.");
        }
    }

    return identity;
}

static void EnsureIdentityUnchanged(TargetIdentity expected, TargetIdentity actual)
{
    if (expected != actual)
    {
        throw new InvalidOperationException(
            "The target PR identity changed during review context collection. Discard this collection attempt and rerun from the current base/head state.");
    }
}

static CopilotObservation AnalyzeCopilot(SnapshotData snapshot, string headOid)
{
    using var reviewsDocument = JsonDocument.Parse(snapshot.ReviewsJson);
    using var inlineDocument = JsonDocument.Parse(snapshot.InlineCommentsJson);

    var reviews = reviewsDocument.RootElement.EnumerateArray()
        .Where(review => IsCopilotLogin(GetNestedString(review, "user", "login")))
        .Where(review => string.Equals(GetString(review, "commit_id"), headOid, StringComparison.OrdinalIgnoreCase))
        .Select(review => new CopilotReview(
            Id: GetInt64(review, "id"),
            State: GetString(review, "state"),
            Body: GetString(review, "body"),
            SubmittedAt: GetString(review, "submitted_at")))
        .OrderByDescending(review => ParseDate(review.SubmittedAt))
        .ToList();

    var selected = reviews.FirstOrDefault();
    var inlineComments = inlineDocument.RootElement.EnumerateArray()
        .Where(comment => IsCopilotLogin(GetNestedString(comment, "user", "login")))
        .Where(comment => IsInlineForSelectedReview(comment, selected, headOid))
        .Select(comment => GetInt64(comment, "id"))
        .Where(id => id > 0)
        .Distinct()
        .OrderBy(id => id)
        .ToArray();

    var expectedInlineCount = ExtractExpectedInlineCount(selected?.Body ?? string.Empty);
    var reviewIsTerminal = selected is not null && IsTerminalReviewState(selected.State);
    var isComplete = reviewIsTerminal
        && (expectedInlineCount is null || inlineComments.Length >= expectedInlineCount.Value);
    var observed = selected is not null && inlineComments.Length > 0
        ? "reviewAndInline"
        : selected is not null
            ? "reviewOnly"
            : inlineComments.Length > 0
                ? "inlineOnly"
                : "none";
    var signature = string.Join(
        "|",
        selected?.Id.ToString() ?? "none",
        selected?.State ?? string.Empty,
        selected?.Body ?? string.Empty,
        string.Join(",", inlineComments));

    return new CopilotObservation(
        observed,
        selected?.Id,
        selected?.State ?? string.Empty,
        selected?.SubmittedAt ?? string.Empty,
        expectedInlineCount,
        inlineComments,
        reviewIsTerminal,
        isComplete,
        signature);
}

static bool IsInlineForSelectedReview(JsonElement comment, CopilotReview? selected, string headOid)
{
    if (selected is not null)
    {
        return GetInt64(comment, "pull_request_review_id") == selected.Id;
    }

    var commitId = GetString(comment, "commit_id");
    var originalCommitId = GetString(comment, "original_commit_id");
    return string.Equals(commitId, headOid, StringComparison.OrdinalIgnoreCase)
        || string.Equals(originalCommitId, headOid, StringComparison.OrdinalIgnoreCase);
}

static CopilotWaitResult BuildWaitResult(
    string waitStatus,
    bool timedOut,
    DateTimeOffset startedAt,
    DateTimeOffset completedAt,
    Options options,
    CopilotObservation observation,
    int stableSamples)
{
    return new CopilotWaitResult(
        waitStatus,
        observation.ObservedReviewState,
        timedOut,
        startedAt,
        completedAt,
        Math.Round((completedAt - startedAt).TotalSeconds, 3),
        options.CopilotTimeoutSeconds,
        options.CopilotPollIntervalSeconds,
        options.CopilotStableSamples,
        stableSamples,
        observation.SelectedReviewId,
        observation.ReviewState,
        observation.ReviewSubmittedAt,
        observation.ExpectedInlineCommentCount,
        observation.InlineCommentIds);
}

static string BuildJson(Options options, CollectionResult result)
{
    using var pullRequest = JsonDocument.Parse(result.Snapshot.PullRequestJson);
    using var reviews = JsonDocument.Parse(result.Snapshot.ReviewsJson);
    using var issueComments = JsonDocument.Parse(result.Snapshot.IssueCommentsJson);
    using var inlineComments = JsonDocument.Parse(result.Snapshot.InlineCommentsJson);

    var root = new Dictionary<string, object?>
    {
        ["schemaVersion"] = "1.0",
        ["generatedAt"] = DateTimeOffset.UtcNow,
        ["target"] = new Dictionary<string, object?>
        {
            ["repository"] = options.Repository,
            ["pullRequest"] = result.Identity.Number,
            ["url"] = result.Identity.Url,
            ["state"] = result.Identity.State,
            ["isDraft"] = result.Identity.IsDraft,
            ["baseRefName"] = result.Identity.BaseBranch,
            ["baseRefOid"] = result.Identity.BaseOid,
            ["headRefName"] = result.Identity.HeadBranch,
            ["headRefOid"] = result.Identity.HeadOid
        },
        ["copilotReviewWait"] = result.Wait.ToDictionary(),
        ["artifacts"] = new Dictionary<string, object?>
        {
            ["remotePatch"] = "pr-diff.patch"
        },
        ["sources"] = new Dictionary<string, object?>
        {
            ["pullRequest"] = pullRequest.RootElement.Clone(),
            ["reviews"] = WithSourceIds(reviews.RootElement, "review", result.Identity.HeadOid),
            ["issueComments"] = WithSourceIds(issueComments.RootElement, "pr-comment", result.Identity.HeadOid),
            ["inlineComments"] = WithSourceIds(inlineComments.RootElement, "inline-comment", result.Identity.HeadOid),
            ["checks"] = pullRequest.RootElement.TryGetProperty("statusCheckRollup", out var checks)
                ? WithSourceIds(checks, "check", result.Identity.HeadOid)
                : Array.Empty<object>()
        }
    };

    return JsonSerializer.Serialize(root, new JsonSerializerOptions { WriteIndented = true });
}

static IReadOnlyList<Dictionary<string, object?>> WithSourceIds(JsonElement items, string kind, string headOid)
{
    if (items.ValueKind != JsonValueKind.Array) return [];
    return items.EnumerateArray().Select(item =>
    {
        var normalized = item.EnumerateObject().ToDictionary(
            property => property.Name,
            property => (object?)property.Value.Clone(),
            StringComparer.Ordinal);
        normalized["sourceId"] = StableSourceId(item, kind, headOid);
        return normalized;
    }).ToList();
}

static string StableSourceId(JsonElement item, string kind, string headOid)
{
    var id = GetInt64(item, "id");
    if (id <= 0) id = GetInt64(item, "databaseId");
    if (id > 0) return $"{kind}:{id}";
    if (kind != "check") throw new InvalidDataException($"GitHub {kind} source has no stable numeric ID.");

    var name = GetString(item, "name");
    if (string.IsNullOrWhiteSpace(name)) name = GetString(item, "context");
    var canonicalKey = string.Join("|", headOid, name, GetString(item, "workflowName"), GetString(item, "detailsUrl"));
    var digest = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonicalKey))).ToLowerInvariant();
    return $"check:{digest[..16]}";
}

static string BuildMarkdown(Options options, CollectionResult result)
{
    using var pullRequest = JsonDocument.Parse(result.Snapshot.PullRequestJson);
    using var reviews = JsonDocument.Parse(result.Snapshot.ReviewsJson);
    using var issueComments = JsonDocument.Parse(result.Snapshot.IssueCommentsJson);
    using var inlineComments = JsonDocument.Parse(result.Snapshot.InlineCommentsJson);
    var builder = new StringBuilder();

    builder.AppendLine("# PR Review Context");
    builder.AppendLine();
    builder.AppendLine("## Target Identity");
    builder.AppendLine();
    builder.AppendLine($"- Repository: {options.Repository}");
    builder.AppendLine($"- PR: {result.Identity.Number}");
    builder.AppendLine($"- URL: {result.Identity.Url}");
    builder.AppendLine($"- Base: {result.Identity.BaseBranch} @ {result.Identity.BaseOid}");
    builder.AppendLine($"- Head: {result.Identity.HeadBranch} @ {result.Identity.HeadOid}");
    builder.AppendLine("- Draft: false");
    builder.AppendLine("- Diff source: remote PR (`pr-diff.patch`)");
    builder.AppendLine("- Working-tree or unpushed changes: excluded from the remote PR diff");
    builder.AppendLine();
    builder.AppendLine("## GitHub Copilot Review Wait");
    builder.AppendLine();
    builder.AppendLine($"- Wait status: {result.Wait.WaitStatus}");
    builder.AppendLine($"- Observed review state: {result.Wait.ObservedReviewState}");
    builder.AppendLine($"- Timed out: {result.Wait.TimedOut.ToString().ToLowerInvariant()}");
    builder.AppendLine($"- Elapsed seconds: {result.Wait.ElapsedSeconds}");
    builder.AppendLine($"- Selected review ID: {result.Wait.SelectedReviewId?.ToString() ?? "N/A"}");
    builder.AppendLine($"- Expected inline comments: {result.Wait.ExpectedInlineCommentCount?.ToString() ?? "unknown"}");
    builder.AppendLine($"- Actual correlated inline comments: {result.Wait.InlineCommentIds.Length}");
    builder.AppendLine($"- Stable samples: {result.Wait.StableSamplesObserved}/{result.Wait.RequiredStableSamples}");
    if (result.Wait.WaitStatus is "timeout" or "disabled" || result.Wait.ObservedReviewState == "none")
    {
        builder.AppendLine("- Interpretation: This is not evidence that GitHub Copilot had no findings.");
    }

    builder.AppendLine();
    builder.AppendLine("## PR Body");
    builder.AppendLine();
    builder.AppendLine(GetString(pullRequest.RootElement, "body"));
    AppendItems(builder, "Reviews", reviews.RootElement, item =>
        $"- source=review:{GetInt64(item, "id")} {GetNestedString(item, "user", "login")} [{GetString(item, "state")}] review={GetInt64(item, "id")} commit={GetString(item, "commit_id")}: {OneLine(GetString(item, "body"))}");
    AppendItems(builder, "PR Comments", issueComments.RootElement, item =>
        $"- source=pr-comment:{GetInt64(item, "id")} {GetNestedString(item, "user", "login")} comment={GetInt64(item, "id")}: {OneLine(GetString(item, "body"))}");
    AppendItems(builder, "Inline Comments", inlineComments.RootElement, item =>
        $"- source=inline-comment:{GetInt64(item, "id")} {GetNestedString(item, "user", "login")} comment={GetInt64(item, "id")} review={GetInt64(item, "pull_request_review_id")} {GetString(item, "path")}:{GetInt64(item, "line")}: {OneLine(GetString(item, "body"))}");

    builder.AppendLine("## Checks");
    builder.AppendLine();
    if (pullRequest.RootElement.TryGetProperty("statusCheckRollup", out var checks)
        && checks.ValueKind == JsonValueKind.Array
        && checks.GetArrayLength() > 0)
    {
        foreach (var check in checks.EnumerateArray())
        {
            var name = GetString(check, "name");
            if (string.IsNullOrWhiteSpace(name))
            {
                name = GetString(check, "context");
            }
            builder.AppendLine($"- source={StableSourceId(check, "check", result.Identity.HeadOid)} {name}: status={GetString(check, "status")} conclusion={GetString(check, "conclusion")} state={GetString(check, "state")}");
        }
    }
    else
    {
        builder.AppendLine("- No check records were returned. Treat checks as uncollected or unavailable, not successful.");
    }

    return builder.ToString();
}

static void AppendItems(StringBuilder builder, string heading, JsonElement items, Func<JsonElement, string> formatter)
{
    builder.AppendLine();
    builder.AppendLine($"## {heading}");
    builder.AppendLine();
    if (items.ValueKind != JsonValueKind.Array || items.GetArrayLength() == 0)
    {
        builder.AppendLine("- None collected.");
        return;
    }

    foreach (var item in items.EnumerateArray())
    {
        builder.AppendLine(formatter(item));
    }
}

static async Task<string> RunGhAsync(string executable, params string[] arguments)
{
    var startInfo = new ProcessStartInfo
    {
        FileName = executable,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        CreateNoWindow = true,
        StandardOutputEncoding = Encoding.UTF8,
        StandardErrorEncoding = Encoding.UTF8
    };
    foreach (var argument in arguments)
    {
        startInfo.ArgumentList.Add(argument);
    }

    using var process = Process.Start(startInfo)
        ?? throw new InvalidOperationException($"Failed to start GitHub CLI executable: {executable}");
    var outputTask = process.StandardOutput.ReadToEndAsync();
    var errorTask = process.StandardError.ReadToEndAsync();
    await process.WaitForExitAsync();
    var output = await outputTask;
    var error = await errorTask;
    if (process.ExitCode != 0)
    {
        throw new InvalidOperationException($"gh {string.Join(' ', arguments)} failed with exit code {process.ExitCode}. {error}".Trim());
    }

    return output;
}

static void ValidateJsonObject(string json, string source)
{
    using var document = JsonDocument.Parse(json);
    if (document.RootElement.ValueKind != JsonValueKind.Object)
    {
        throw new InvalidOperationException($"Expected a JSON object from {source}.");
    }
}

static void ValidateJsonArray(string json, string source)
{
    using var document = JsonDocument.Parse(json);
    if (document.RootElement.ValueKind != JsonValueKind.Array)
    {
        throw new InvalidOperationException($"Expected a JSON array from {source}.");
    }
}

static JsonElement? TryCloneProperty(JsonElement element, string propertyName)
{
    return element.TryGetProperty(propertyName, out var property) ? property.Clone() : null;
}

static string GetString(JsonElement element, string propertyName)
{
    if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(propertyName, out var property))
    {
        return string.Empty;
    }

    return property.ValueKind switch
    {
        JsonValueKind.String => property.GetString() ?? string.Empty,
        JsonValueKind.Number => property.ToString(),
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        _ => string.Empty
    };
}

static string GetNestedString(JsonElement element, string objectName, string propertyName)
{
    return element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(objectName, out var nested)
        ? GetString(nested, propertyName)
        : string.Empty;
}

static long GetInt64(JsonElement element, string propertyName)
{
    if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(propertyName, out var property))
    {
        return 0;
    }

    if (property.ValueKind == JsonValueKind.Number && property.TryGetInt64(out var number))
    {
        return number;
    }

    return property.ValueKind == JsonValueKind.String && long.TryParse(property.GetString(), out number) ? number : 0;
}

static bool GetBoolean(JsonElement element, string propertyName)
{
    if (element.ValueKind != JsonValueKind.Object || !element.TryGetProperty(propertyName, out var property))
    {
        throw new InvalidOperationException($"Required boolean field is missing: {propertyName}");
    }

    return property.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        _ => throw new InvalidOperationException($"Required field is not boolean: {propertyName}")
    };
}

static bool IsCopilotLogin(string login) => string.Equals(
    login,
    "copilot-pull-request-reviewer[bot]",
    StringComparison.OrdinalIgnoreCase);

static bool IsTerminalReviewState(string state) => state is "COMMENTED" or "APPROVED" or "CHANGES_REQUESTED";

static int? ExtractExpectedInlineCount(string body)
{
    var match = Regex.Match(body, @"generated\s+(\d+)\s+comments?", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    return match.Success && int.TryParse(match.Groups[1].Value, out var count) ? count : null;
}

static DateTimeOffset ParseDate(string value) => DateTimeOffset.TryParse(value, out var parsed) ? parsed : DateTimeOffset.MinValue;

static string OneLine(string value) => Regex.Replace(value ?? string.Empty, @"\s+", " ").Trim();

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file scripts/collect-pr-review-context.cs -- --repo owner/name --pr 123 --out .review/pr-123

Options:
  --repo owner/name                      GitHub repository.
  --pr number                            Ready-for-review pull request number.
  --out directory                        Output directory for context and remote patch artifacts.
  --no-wait-for-copilot                  Disable the standard Copilot review wait.
  --copilot-timeout-seconds seconds      Wait timeout. Default: 180.
  --copilot-poll-interval-seconds value  Poll interval. Default: 10.
  --copilot-stable-samples count         Consecutive stable samples. Default: 2.
  --gh-executable path                   GitHub CLI executable. Default: gh.
  --include-checks                       Accepted for migration compatibility; checks are always collected.
  --help                                 Show this help.
""");
}

sealed class Options
{
    public string Repository { get; set; } = string.Empty;
    public string Owner { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int PullRequestNumber { get; set; }
    public string OutputDirectory { get; set; } = string.Empty;
    public bool WaitForCopilot { get; set; } = true;
    public int CopilotTimeoutSeconds { get; set; } = 180;
    public int CopilotPollIntervalSeconds { get; set; } = 10;
    public int CopilotStableSamples { get; set; } = 2;
    public string GhExecutable { get; set; } = "gh";
    public bool ShowHelp { get; set; }

    public static Options Parse(string[] args)
    {
        var options = new Options();
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--repo":
                    options.Repository = ReadValue(args, ref i, "--repo");
                    break;
                case "--pr":
                    options.PullRequestNumber = ReadPositiveInt(args, ref i, "--pr");
                    break;
                case "--out":
                    options.OutputDirectory = ReadValue(args, ref i, "--out");
                    break;
                case "--no-wait-for-copilot":
                    options.WaitForCopilot = false;
                    break;
                case "--copilot-timeout-seconds":
                    options.CopilotTimeoutSeconds = ReadPositiveInt(args, ref i, "--copilot-timeout-seconds");
                    break;
                case "--copilot-poll-interval-seconds":
                    options.CopilotPollIntervalSeconds = ReadPositiveInt(args, ref i, "--copilot-poll-interval-seconds");
                    break;
                case "--copilot-stable-samples":
                    options.CopilotStableSamples = ReadPositiveInt(args, ref i, "--copilot-stable-samples");
                    break;
                case "--gh-executable":
                    options.GhExecutable = ReadValue(args, ref i, "--gh-executable");
                    break;
                case "--include-checks":
                    break;
                case "--help":
                case "-h":
                    options.ShowHelp = true;
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {args[i]}");
            }
        }

        return options;
    }

    public void Validate()
    {
        var parts = Repository.Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length != 2)
        {
            throw new ArgumentException("--repo must be in owner/name format.");
        }

        if (PullRequestNumber <= 0)
        {
            throw new ArgumentException("--pr is required.");
        }

        if (string.IsNullOrWhiteSpace(OutputDirectory))
        {
            throw new ArgumentException("--out is required.");
        }

        if (string.IsNullOrWhiteSpace(GhExecutable))
        {
            throw new ArgumentException("--gh-executable cannot be empty.");
        }

        Owner = parts[0];
        Name = parts[1];
    }

    static string ReadValue(string[] args, ref int index, string option)
    {
        if (index + 1 >= args.Length)
        {
            throw new ArgumentException($"{option} requires a value.");
        }

        return args[++index];
    }

    static int ReadPositiveInt(string[] args, ref int index, string option)
    {
        var value = ReadValue(args, ref index, option);
        if (!int.TryParse(value, out var number) || number <= 0)
        {
            throw new ArgumentException($"{option} must be a positive integer.");
        }

        return number;
    }
}

sealed record SnapshotData(string PullRequestJson, string ReviewsJson, string IssueCommentsJson, string InlineCommentsJson);

sealed record TargetIdentity(long Number, string Url, string State, bool IsDraft, string BaseBranch, string BaseOid, string HeadBranch, string HeadOid);

sealed record CopilotReview(long Id, string State, string Body, string SubmittedAt);

sealed record CopilotObservation(
    string ObservedReviewState,
    long? SelectedReviewId,
    string ReviewState,
    string ReviewSubmittedAt,
    int? ExpectedInlineCommentCount,
    long[] InlineCommentIds,
    bool ReviewIsTerminal,
    bool IsComplete,
    string Signature);

sealed record CopilotWaitResult(
    string WaitStatus,
    string ObservedReviewState,
    bool TimedOut,
    DateTimeOffset StartedAt,
    DateTimeOffset CompletedAt,
    double ElapsedSeconds,
    int TimeoutSeconds,
    int PollIntervalSeconds,
    int RequiredStableSamples,
    int StableSamplesObserved,
    long? SelectedReviewId,
    string ReviewState,
    string ReviewSubmittedAt,
    int? ExpectedInlineCommentCount,
    long[] InlineCommentIds)
{
    public Dictionary<string, object?> ToDictionary() => new()
    {
        ["waitStatus"] = WaitStatus,
        ["observedReviewState"] = ObservedReviewState,
        ["timedOut"] = TimedOut,
        ["startedAt"] = StartedAt,
        ["completedAt"] = CompletedAt,
        ["elapsedSeconds"] = ElapsedSeconds,
        ["timeoutSeconds"] = TimeoutSeconds,
        ["pollIntervalSeconds"] = PollIntervalSeconds,
        ["requiredStableSamples"] = RequiredStableSamples,
        ["stableSamplesObserved"] = StableSamplesObserved,
        ["selectedReviewId"] = SelectedReviewId,
        ["reviewState"] = ReviewState,
        ["reviewSubmittedAt"] = ReviewSubmittedAt,
        ["expectedInlineCommentCount"] = ExpectedInlineCommentCount,
        ["actualInlineCommentCount"] = InlineCommentIds.Length,
        ["inlineCommentIds"] = InlineCommentIds
    };
}

sealed record CollectionResult(SnapshotData Snapshot, TargetIdentity Identity, CopilotWaitResult Wait);
