#:property TargetFramework=net10.0-windows10.0.19041.0
#:property PublishAot=false
#:property WindowsPackageType=None
#:package Microsoft.WindowsAppSDK@1.8.260710003

using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

try
{
    var json = await Console.In.ReadToEndAsync();
    var completion = JsonSerializer.Deserialize<CompletionEvent>(json, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower });
    if (completion is null || !AppNotificationManager.IsSupported()) Environment.Exit(2);
    AppNotificationManager.Default.Register();
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

sealed class CompletionEvent { [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } [JsonPropertyName("source")] public string Source { get; set; } = ""; [JsonPropertyName("primary_process")] public string PrimaryProcess { get; set; } = ""; [JsonPropertyName("observed_status")] public string ObservedStatus { get; set; } = ""; [JsonPropertyName("occurred_at")] public DateTimeOffset OccurredAt { get; set; } [JsonPropertyName("title")] public string Title { get; set; } = ""; [JsonPropertyName("repository")] public string Repository { get; set; } = ""; [JsonPropertyName("resume_uri")] public string ResumeUri { get; set; } = ""; [JsonPropertyName("result_uri")] public string? ResultUri { get; set; } [JsonPropertyName("source_event_id")] public string SourceEventId { get; set; } = ""; [JsonPropertyName("notification_status")] public string NotificationStatus { get; set; } = ""; }
