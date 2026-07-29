#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

var runtimeHome = Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_RUNTIME_HOME");
runtimeHome ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexNotificationRuntime");
var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower, WriteIndented = false };

if (args.Contains("--self-test", StringComparer.Ordinal))
{
    SelfTest();
    return;
}

var rawPayload = args.LastOrDefault(static value => value.TrimStart().StartsWith('{'));
if (rawPayload is null)
{
    Environment.ExitCode = 0;
    return;
}

try
{
    Directory.CreateDirectory(runtimeHome);
    var config = LoadConfig(Path.Combine(runtimeHome, "runtime-config.json"));
    await ForwardExistingNotifyAsync(config.ChainedNotify, rawPayload);
    var payload = JsonSerializer.Deserialize<CodexPayload>(rawPayload, options);
    if (payload?.Type != "agent-turn-complete" || string.IsNullOrWhiteSpace(payload.ThreadId) || string.IsNullOrWhiteSpace(payload.TurnId))
    {
        WriteLog(runtimeHome, "ignored", null, null);
        return;
    }

    var candidate = CreateCandidate(payload, out var candidateStatus);
    WriteLog(runtimeHome, candidateStatus, Hash(payload.ThreadId + ":" + payload.TurnId), null);

    var eventHash = Hash(candidate.SourceEventId);
    var stateDirectory = Path.Combine(runtimeHome, "state");
    Directory.CreateDirectory(stateDirectory);
    CleanupState(stateDirectory);
    var claimPath = Path.Combine(stateDirectory, eventHash + ".claim");
    var deliveredPath = Path.Combine(stateDirectory, eventHash + ".delivered");
    if (File.Exists(deliveredPath) || !TryClaim(claimPath))
    {
        candidate.NotificationStatus = "DUPLICATE";
        WriteLog(runtimeHome, "duplicate", eventHash, null);
        return;
    }

    try
    {
        var delivered = false;
        foreach (var provider in config.Providers)
        {
            if (await InvokeProviderAsync(provider, candidate, options))
            {
                delivered = true;
                break;
            }
        }

        candidate.NotificationStatus = delivered ? "DELIVERED" : "FAILED";
        if (delivered)
        {
            File.Move(claimPath, deliveredPath, overwrite: true);
        }
        else
        {
            File.Delete(claimPath);
        }
        WriteLog(runtimeHome, candidate.NotificationStatus.ToLowerInvariant(), eventHash, null);
    }
    catch (Exception ex)
    {
        TryDelete(claimPath);
        candidate.NotificationStatus = "FAILED";
        WriteLog(runtimeHome, "failed", eventHash, ex.GetType().Name);
    }
}
catch (Exception ex)
{
    // Codex notify is observational. It must never fail the completed turn.
    WriteLog(runtimeHome, "runtime-error", null, ex.GetType().Name);
}

static RuntimeConfig LoadConfig(string path)
{
    if (!File.Exists(path)) return new RuntimeConfig();
    var config = JsonSerializer.Deserialize<RuntimeConfig>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower }) ?? new RuntimeConfig();
    config.TargetMarkers ??= [];
    config.Providers ??= [];
    config.Providers = config.Providers.Where(static provider => provider is not null).ToList();
    foreach (var provider in config.Providers) provider.Argv ??= [];
    if (config.ChainedNotify is not null) config.ChainedNotify.Argv ??= [];
    return config;
}

static CompletionEvent CreateCandidate(CodexPayload payload, out string status)
{
    var envelope = TryReadEnvelope(payload.LastAssistantMessage, out var invalidEnvelope);
    var repository = ResolveRepository(payload.Cwd);
    var primaryProcess = "codex";
    var observedStatus = "TURN_ENDED";
    var title = "Codex turn completed";
    string? resultUri = null;
    if (envelope is not null)
    {
        status = "enriched-candidate";
        repository = envelope.Repository ?? repository;
        primaryProcess = envelope.PrimaryProcess!;
        observedStatus = envelope.ObservedStatus!;
        title = envelope.Title ?? "Process completed";
        resultUri = envelope.ResultUri;
    }
    else
    {
        status = invalidEnvelope ? "generic-fallback-invalid-envelope" : "generic-candidate";
    }
    var resumeUri = "codex://threads/" + Uri.EscapeDataString(payload.ThreadId!);
    return new CompletionEvent
    {
        SchemaVersion = 1,
        Source = "codex.agent-turn-complete",
        PrimaryProcess = primaryProcess,
        ObservedStatus = observedStatus,
        OccurredAt = DateTimeOffset.UtcNow,
        Title = repository + " · " + primaryProcess + " · " + title,
        Repository = repository,
        ResumeUri = resumeUri,
        ResultUri = resultUri,
        SourceEventId = "codex:" + payload.ThreadId + ":" + payload.TurnId,
        NotificationStatus = "PENDING"
    };
}

static CompletionEnvelope? TryReadEnvelope(string? message, out bool invalid)
{
    invalid = false;
    if (string.IsNullOrWhiteSpace(message)) return null;
    const string start = "```completion-notification";
    var first = message.IndexOf(start, StringComparison.Ordinal);
    if (first < 0) return null;
    if (message.IndexOf(start, first + start.Length, StringComparison.Ordinal) >= 0) { invalid = true; return null; }
    var bodyStart = message.IndexOf('\n', first);
    var end = bodyStart >= 0 ? message.IndexOf("```", bodyStart + 1, StringComparison.Ordinal) : -1;
    if (bodyStart < 0 || end < 0 || end - bodyStart > 8192) { invalid = true; return null; }
    try
    {
        using var document = JsonDocument.Parse(message[(bodyStart + 1)..end]);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object) { invalid = true; return null; }
        var allowedProperties = new HashSet<string>(StringComparer.Ordinal)
        {
            "schema_version", "primary_process", "observed_status", "title", "repository", "result_uri"
        };
        if (root.EnumerateObject().Any(property => !allowedProperties.Contains(property.Name))) { invalid = true; return null; }
        var envelope = new CompletionEnvelope
        {
            SchemaVersion = root.TryGetProperty("schema_version", out var version) && version.TryGetInt32(out var number) ? number : 0,
            PrimaryProcess = root.TryGetProperty("primary_process", out var process) ? process.GetString() : null,
            ObservedStatus = root.TryGetProperty("observed_status", out var status) ? status.GetString() : null,
            Title = root.TryGetProperty("title", out var title) ? title.GetString() : null,
            Repository = root.TryGetProperty("repository", out var repository) ? repository.GetString() : null,
            ResultUri = root.TryGetProperty("result_uri", out var resultUri) ? resultUri.GetString() : null
        };
        if (envelope.SchemaVersion != 1 ||
            !IsSafeText(envelope.PrimaryProcess) ||
            !IsSafeText(envelope.ObservedStatus) ||
            (root.TryGetProperty("title", out _) && !IsSafeText(envelope.Title)) ||
            (root.TryGetProperty("repository", out _) && !IsSafeText(envelope.Repository)) ||
            (root.TryGetProperty("result_uri", out _) && !IsAllowedResultUri(envelope.ResultUri)))
        {
            invalid = true;
            return null;
        }
        return envelope;
    }
    catch { invalid = true; return null; }
}

static bool IsSafeText(string? value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 240 && value.All(character => !char.IsControl(character));
static bool IsAllowedResultUri(string? value)
{
    if (string.IsNullOrWhiteSpace(value) || value.Length > 2048 || !Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
    if (!string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) || !string.IsNullOrEmpty(uri.UserInfo)) return false;
    var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
    if (segments.Length == 0) return false;
    return !string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase) || segments.Length >= 4;
}
static string ResolveRepository(string? cwd)
{
    if (string.IsNullOrWhiteSpace(cwd)) return "unknown-repository";
    try
    {
        var info = new ProcessStartInfo("git") { RedirectStandardOutput = true, UseShellExecute = false, CreateNoWindow = true };
        info.ArgumentList.Add("-C"); info.ArgumentList.Add(cwd); info.ArgumentList.Add("config"); info.ArgumentList.Add("--get"); info.ArgumentList.Add("remote.origin.url");
        using var process = Process.Start(info);
        var origin = process?.StandardOutput.ReadToEnd().Trim();
        process?.WaitForExit(2000);
        if (!string.IsNullOrWhiteSpace(origin))
        {
            var trimmed = origin.Replace(".git", "", StringComparison.OrdinalIgnoreCase).TrimEnd('/');
            var slash = trimmed.LastIndexOf('/');
            var colon = trimmed.LastIndexOf(':');
            var separator = Math.Max(slash, colon);
            if (separator > 0) return trimmed[(trimmed[..separator].LastIndexOfAny(['/', ':']) + 1)..] + "/" + trimmed[(separator + 1)..];
        }
    }
    catch { }
    return Path.GetFileName(Path.TrimEndingDirectorySeparator(cwd));
}

static bool TryClaim(string path)
{
    try
    {
        if (File.Exists(path) && DateTimeOffset.UtcNow - File.GetLastWriteTimeUtc(path) > TimeSpan.FromMinutes(15)) TryDelete(path);
        using var _ = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        return true;
    }
    catch { return false; }
}
static void TryDelete(string path) { try { if (File.Exists(path)) File.Delete(path); } catch { } }
static void CleanupState(string directory)
{
    try
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var path in Directory.EnumerateFiles(directory, "*.*", SearchOption.TopDirectoryOnly))
        {
            var age = now - File.GetLastWriteTimeUtc(path);
            if ((path.EndsWith(".claim", StringComparison.Ordinal) && age > TimeSpan.FromMinutes(15)) ||
                (path.EndsWith(".delivered", StringComparison.Ordinal) && age > TimeSpan.FromDays(30))) TryDelete(path);
        }
    }
    catch { }
}
static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

static async Task ForwardExistingNotifyAsync(CommandSpec? command, string payload)
{
    if (command?.Argv is not { Count: > 0 }) return;
    try
    {
        var info = new ProcessStartInfo(command.Argv[0]) { UseShellExecute = false, CreateNoWindow = true };
        foreach (var argument in command.Argv.Skip(1)) info.ArgumentList.Add(argument);
        info.ArgumentList.Add(payload);
        using var process = Process.Start(info);
        if (process is not null)
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            try { await process.WaitForExitAsync(timeout.Token); }
            catch { TryKill(process); }
        }
    }
    catch { }
}

static async Task<bool> InvokeProviderAsync(ProviderSpec provider, CompletionEvent completionEvent, JsonSerializerOptions options)
{
    if (provider.Argv is not { Count: > 0 }) return false;
    try
    {
        var info = new ProcessStartInfo(provider.Argv[0]) { RedirectStandardInput = true, UseShellExecute = false, CreateNoWindow = true };
        foreach (var argument in provider.Argv.Skip(1)) info.ArgumentList.Add(argument);
        using var process = Process.Start(info);
        if (process is null) return false;
        await process.StandardInput.WriteAsync(JsonSerializer.Serialize(completionEvent, options));
        process.StandardInput.Close();
        using var timeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(Math.Clamp(provider.TimeoutMs, 1000, 30000)));
        try { await process.WaitForExitAsync(timeout.Token); }
        catch { TryKill(process); return false; }
        return process.ExitCode == 0;
    }
    catch { return false; }
}

static void TryKill(Process process) { try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { } }

static void WriteLog(string home, string status, string? eventHash, string? error)
{
    try
    {
        var path = Path.Combine(home, "runtime.log.jsonl");
        if (File.Exists(path) && new FileInfo(path).Length > 1_048_576)
        {
            var retained = File.ReadLines(path).TakeLast(500).ToArray();
            File.WriteAllLines(path, retained);
        }
        var line = JsonSerializer.Serialize(new { occurred_at = DateTimeOffset.UtcNow, status, event_hash = eventHash, error });
        File.AppendAllText(path, line + Environment.NewLine);
    }
    catch { }
}

static void SelfTest()
{
    var payload = new CodexPayload { Type = "agent-turn-complete", ThreadId = "thread", TurnId = "turn", Cwd = Path.GetTempPath(), InputMessages = ["[notify]"], LastAssistantMessage = null };
    var candidate = CreateCandidate(payload, out var candidateStatus);
    if (candidate.PrimaryProcess != "codex" || candidate.ObservedStatus != "TURN_ENDED" || candidateStatus != "generic-candidate" || candidate.ResumeUri != "codex://threads/thread") throw new InvalidOperationException("generic callback test failed");
    var message = "```completion-notification\n{\"schema_version\":1,\"primary_process\":\"test\",\"observed_status\":\"BLOCKED\",\"result_uri\":\"https://github.com/openai/codex/issues/1\"}\n```";
    payload.LastAssistantMessage = message;
    candidate = CreateCandidate(payload, out candidateStatus);
    if (candidate.ObservedStatus != "BLOCKED" || candidate.ResultUri != "https://github.com/openai/codex/issues/1" || candidateStatus != "enriched-candidate") throw new InvalidOperationException($"envelope test failed status={candidate.ObservedStatus} uri={candidate.ResultUri}");
    payload.LastAssistantMessage = "```completion-notification\n{\"schema_version\":1,\"primary_process\":\"test\",\"observed_status\":\"COMPLETED\",\"result_uri\":\"https://github.com/openai/codex\"}\n```";
    candidate = CreateCandidate(payload, out candidateStatus);
    if (candidate.PrimaryProcess != "codex" || candidate.ObservedStatus != "TURN_ENDED" || candidate.ResultUri is not null || candidateStatus != "generic-fallback-invalid-envelope") throw new InvalidOperationException("unsafe result URI must invalidate enrichment and fall back to generic event");
    payload.LastAssistantMessage = "```completion-notification\n{invalid}\n```";
    candidate = CreateCandidate(payload, out candidateStatus);
    if (candidate.PrimaryProcess != "codex" || candidateStatus != "generic-fallback-invalid-envelope") throw new InvalidOperationException("invalid envelope fallback test failed");
    payload.LastAssistantMessage = "```completion-notification\n{\"schema_version\":1,\"primary_process\":\"test\",\"observed_status\":\"COMPLETED\",\"resume_uri\":\"https://example.com/override\"}\n```";
    candidate = CreateCandidate(payload, out candidateStatus);
    if (candidate.ResumeUri != "codex://threads/thread" || candidate.PrimaryProcess != "codex" || candidateStatus != "generic-fallback-invalid-envelope") throw new InvalidOperationException("callback identity override was not rejected");
    if (!IsAllowedResultUri("HTTPS://Example.com/result/1") || IsAllowedResultUri("https://GitHub.com/openai/codex")) throw new InvalidOperationException("mixed-case URI contract failed");
    var temporaryConfig = Path.Combine(Path.GetTempPath(), "codex-notification-runtime-config-" + Guid.NewGuid().ToString("N") + ".json");
    try
    {
        File.WriteAllText(temporaryConfig, "{\"target_markers\":null,\"providers\":null,\"chained_notify\":{\"argv\":null}}");
        var normalized = LoadConfig(temporaryConfig);
        if (normalized.TargetMarkers.Count != 0 || normalized.Providers.Count != 0 || normalized.ChainedNotify?.Argv.Count != 0) throw new InvalidOperationException("runtime config normalization failed");
    }
    finally { TryDelete(temporaryConfig); }
    Console.WriteLine("PASS runtime self-test (9 cases)");
}

sealed class CodexPayload { [JsonPropertyName("type")] public string? Type { get; set; } [JsonPropertyName("thread-id")] public string? ThreadId { get; set; } [JsonPropertyName("turn-id")] public string? TurnId { get; set; } [JsonPropertyName("cwd")] public string? Cwd { get; set; } [JsonPropertyName("input-messages")] public List<string?>? InputMessages { get; set; } = []; [JsonPropertyName("last-assistant-message")] public string? LastAssistantMessage { get; set; } }
sealed class CompletionEnvelope { [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } [JsonPropertyName("primary_process")] public string? PrimaryProcess { get; set; } [JsonPropertyName("observed_status")] public string? ObservedStatus { get; set; } [JsonPropertyName("title")] public string? Title { get; set; } [JsonPropertyName("repository")] public string? Repository { get; set; } [JsonPropertyName("result_uri")] public string? ResultUri { get; set; } }
sealed class CompletionEvent { public int SchemaVersion { get; set; } public string Source { get; set; } = ""; public string PrimaryProcess { get; set; } = ""; public string ObservedStatus { get; set; } = ""; public DateTimeOffset OccurredAt { get; set; } public string Title { get; set; } = ""; public string Repository { get; set; } = ""; public string ResumeUri { get; set; } = ""; public string? ResultUri { get; set; } public string SourceEventId { get; set; } = ""; public string NotificationStatus { get; set; } = ""; }
sealed class RuntimeConfig { public List<string> TargetMarkers { get; set; } = []; public List<ProviderSpec> Providers { get; set; } = []; public CommandSpec? ChainedNotify { get; set; } }
sealed class ProviderSpec { public string Name { get; set; } = ""; public List<string> Argv { get; set; } = []; public int TimeoutMs { get; set; } = 5000; }
sealed class CommandSpec { public List<string> Argv { get; set; } = []; }
