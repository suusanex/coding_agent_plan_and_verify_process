#:property TargetFramework=net10.0-windows10.0.19041.0
#:property PublishAot=false
#:property WindowsPackageType=None
#:property WindowsAppSdkBootstrapInitialize=false
#:package Microsoft.WindowsAppSDK@1.8.260710003

using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using Microsoft.Windows.ApplicationModel.DynamicDependency;

if (args.Contains("--self-test", StringComparer.Ordinal))
{
    var allowed = new[] { "https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/57", "HTTPS://Example.com/result/1" }.All(IsAllowedResultUri) && IsAllowedResumeUri("codex://threads/thread-id");
    var rejected = new[] { "", "http://example.com/result/1", "https://user@example.com/result/1", "https://example.com/", "https://github.com/", "https://github.com/suusanex", "https://github.com/suusanex/coding_agent_plan_and_verify_process", "https://GitHub.com/suusanex/coding_agent_plan_and_verify_process" }.All(value => !IsAllowedResultUri(value));
    var withResult = BuildButtons(new CompletionEvent { ResumeUri = "codex://threads/review-thread", ResultUri = "https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/57" });
    var withoutResult = BuildButtons(new CompletionEvent { ResumeUri = "codex://threads/implementation-thread" });
    var buttonContract = withResult.SequenceEqual(new[]
    {
        new ButtonSpec("結果を開く", "https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/57"),
        new ButtonSpec("このタスクを開く", "codex://threads/review-thread")
    }) && withoutResult.SequenceEqual(new[] { new ButtonSpec("このタスクを開く", "codex://threads/implementation-thread") });
    if (!allowed || !rejected || IsAllowedResumeUri("codex://settings") || !buttonContract) Environment.Exit(2);
    Console.WriteLine("PASS provider self-test (URI validation and dual-button contract)");
    return;
}
if (args.Contains("--check-support", StringComparer.Ordinal))
{
    var hangPidPath = Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_TEST_PROVIDER_HANG_PID_FILE");
    if (Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_TEST_PROVIDER_HANG") == "1")
    {
        if (!string.IsNullOrWhiteSpace(hangPidPath)) File.WriteAllText(hangPidPath, Environment.ProcessId.ToString());
        await Task.Delay(Timeout.InfiniteTimeSpan);
    }
    var supported = false;
    var initialized = false;
    try
    {
        if (Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_TEST_PROVIDER_UNSUPPORTED") != "1")
        {
            Bootstrap.Initialize(0x00010008);
            initialized = true;
            supported = AppNotificationManager.IsSupported();
        }
    }
    catch { }
    finally { if (initialized) Bootstrap.Shutdown(); }
    Console.WriteLine(supported ? "supported" : "unsupported");
    Environment.ExitCode = supported ? 0 : 3;
    return;
}

var bootstrapInitialized = false;
try
{
    Bootstrap.Initialize(0x00010008);
    bootstrapInitialized = true;
    var json = await Console.In.ReadToEndAsync();
    var completion = JsonSerializer.Deserialize<CompletionEvent>(json, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower });
    if (completion is null || !AppNotificationManager.IsSupported()) Environment.Exit(2);
    AppNotificationManager.Default.Register();
    if (!IsAllowedResumeUri(completion.ResumeUri) || (completion.ResultUri is not null && !IsAllowedResultUri(completion.ResultUri))) Environment.Exit(2);
    var builder = new AppNotificationBuilder()
        .AddText(completion.Title)
        .AddText(completion.ObservedStatus);
    foreach (var button in BuildButtons(completion))
    {
        builder.AddButton(new AppNotificationButton(button.Label) { InvokeUri = new Uri(button.Uri) });
    }
    var notification = builder.BuildNotification();
    AppNotificationManager.Default.Show(notification);
}
catch
{
    Environment.ExitCode = 2;
}
finally
{
    if (bootstrapInitialized) Bootstrap.Shutdown();
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

static IReadOnlyList<ButtonSpec> BuildButtons(CompletionEvent completion)
{
    var buttons = new List<ButtonSpec>();
    if (completion.ResultUri is not null) buttons.Add(new ButtonSpec("結果を開く", completion.ResultUri));
    buttons.Add(new ButtonSpec("このタスクを開く", completion.ResumeUri));
    return buttons;
}

readonly record struct ButtonSpec(string Label, string Uri);

sealed class CompletionEvent { [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } [JsonPropertyName("source")] public string Source { get; set; } = ""; [JsonPropertyName("primary_process")] public string PrimaryProcess { get; set; } = ""; [JsonPropertyName("observed_status")] public string ObservedStatus { get; set; } = ""; [JsonPropertyName("occurred_at")] public DateTimeOffset OccurredAt { get; set; } [JsonPropertyName("title")] public string Title { get; set; } = ""; [JsonPropertyName("repository")] public string Repository { get; set; } = ""; [JsonPropertyName("resume_uri")] public string ResumeUri { get; set; } = ""; [JsonPropertyName("result_uri")] public string? ResultUri { get; set; } [JsonPropertyName("source_event_id")] public string SourceEventId { get; set; } = ""; [JsonPropertyName("notification_status")] public string NotificationStatus { get; set; } = ""; }
