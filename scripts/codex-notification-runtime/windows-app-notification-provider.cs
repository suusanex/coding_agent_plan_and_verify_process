#:property TargetFramework=net10.0-windows10.0.19041.0
#:property PublishAot=false
#:property WindowsPackageType=None
#:package Microsoft.WindowsAppSDK@1.8.260710003

using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

if (args.Contains("--self-test", StringComparer.Ordinal))
{
    var allowed = new[] { "https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/57", "HTTPS://Example.com/result/1" }.All(IsAllowedResultUri) && IsAllowedResumeUri("codex://threads/thread-id");
    var rejected = new[] { "", "http://example.com/result/1", "https://user@example.com/result/1", "https://example.com/", "https://github.com/", "https://github.com/suusanex", "https://github.com/suusanex/coding_agent_plan_and_verify_process", "https://GitHub.com/suusanex/coding_agent_plan_and_verify_process" }.All(value => !IsAllowedResultUri(value));
    if (!allowed || !rejected || IsAllowedResumeUri("codex://settings")) Environment.Exit(2);
    Console.WriteLine("PASS provider self-test (12 cases)");
    return;
}
if (args.Contains("--check-support", StringComparer.Ordinal))
{
    var supported = Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_TEST_PROVIDER_UNSUPPORTED") != "1" && AppNotificationManager.IsSupported();
    Console.WriteLine(supported ? "supported" : "unsupported");
    Environment.ExitCode = supported ? 0 : 3;
    return;
}

try
{
    var json = await Console.In.ReadToEndAsync();
    var completion = JsonSerializer.Deserialize<CompletionEvent>(json, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower });
    if (completion is null || !AppNotificationManager.IsSupported()) Environment.Exit(2);
    AppNotificationManager.Default.Register();
    if (!IsAllowedResumeUri(completion.ResumeUri) || (completion.ResultUri is not null && !IsAllowedResultUri(completion.ResultUri))) Environment.Exit(2);
    var destination = completion.ResultUri ?? completion.ResumeUri;
    var label = completion.ResultUri is null ? "Codex を開く" : "結果を開く";
    var button = new AppNotificationButton(label) { InvokeUri = new Uri(destination) };
    var notification = new AppNotificationBuilder()
        .AddText(completion.Title)
        .AddText(completion.ObservedStatus)
        .AddButton(button)
        .BuildNotification();
    AppNotificationManager.Default.Show(notification);
}
catch
{
    Environment.ExitCode = 2;
}

static bool IsAllowedResultUri(string? value)
{
    if (string.IsNullOrWhiteSpace(value) || value.Length > 2048 || !Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
    if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) || !string.IsNullOrEmpty(uri.UserInfo)) return false;
    var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
    return segments.Length > 0 && (!string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase) || segments.Length >= 4);
}

static bool IsAllowedResumeUri(string? value)
{
    if (string.IsNullOrWhiteSpace(value) || value.Length > 2048 || !Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
    return string.Equals(uri.Scheme, "codex", StringComparison.OrdinalIgnoreCase) && string.Equals(uri.Host, "threads", StringComparison.OrdinalIgnoreCase) &&
        string.IsNullOrEmpty(uri.UserInfo) && string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment) &&
        uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries).Length == 1;
}

sealed class CompletionEvent { [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } [JsonPropertyName("source")] public string Source { get; set; } = ""; [JsonPropertyName("primary_process")] public string PrimaryProcess { get; set; } = ""; [JsonPropertyName("observed_status")] public string ObservedStatus { get; set; } = ""; [JsonPropertyName("occurred_at")] public DateTimeOffset OccurredAt { get; set; } [JsonPropertyName("title")] public string Title { get; set; } = ""; [JsonPropertyName("repository")] public string Repository { get; set; } = ""; [JsonPropertyName("resume_uri")] public string ResumeUri { get; set; } = ""; [JsonPropertyName("result_uri")] public string? ResultUri { get; set; } [JsonPropertyName("source_event_id")] public string SourceEventId { get; set; } = ""; [JsonPropertyName("notification_status")] public string NotificationStatus { get; set; } = ""; }
