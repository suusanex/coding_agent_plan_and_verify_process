#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower, WriteIndented = true };
if (args.Contains("--self-test", StringComparer.Ordinal))
{
    if (Project("A B/CON") != "a-b-con" || Hash("source").Length != 64) throw new InvalidOperationException("Local Spool self-test failed.");
    Console.WriteLine("PASS local spool provider self-test");
    return;
}

try
{
    var spoolRoot = ResolveSpoolRoot(args);
    var input = await Console.In.ReadToEndAsync();
    var item = ParseAndValidate(input, options);
    Directory.CreateDirectory(spoolRoot);
    var hash = Hash(item.SourceEventId);
    using var mutex = new Mutex(false, "Local\\CodexNotificationSpool-" + hash);
    var mutexAcquired = false;
    try
    {
        try { mutexAcquired = mutex.WaitOne(TimeSpan.FromSeconds(2)); }
        catch (AbandonedMutexException) { mutexAcquired = true; }
        if (!mutexAcquired) throw new IOException("mutex-timeout");
        if (FindSameEvent(spoolRoot, hash, item.SourceEventId))
        {
            WriteDiagnostic("idempotent-existing", hash, null);
            return;
        }
        var persisted = new SpoolItem(item.SchemaVersion, item.Source, item.SourceEventId, item.PrimaryProcess, item.ObservedStatus, item.OccurredAt.ToUniversalTime(), item.Title, item.Repository, item.ResumeUri, item.ResultUri);
        var lengths = new[] { 16, 24, 32, 64 };
        foreach (var length in lengths)
        {
            var fileName = BuildFileName(persisted, hash[..length]);
            var finalPath = Path.Combine(spoolRoot, fileName);
            if (File.Exists(finalPath))
            {
                if (FileHasEvent(finalPath, item.SourceEventId)) { WriteDiagnostic("idempotent-existing", hash, null); return; }
                continue;
            }
            var tempPath = Path.Combine(spoolRoot, "." + fileName + "." + Guid.NewGuid().ToString("N") + ".tmp");
            try
            {
                using (var stream = new FileStream(tempPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.None))
                {
                    InjectFailure("write");
                    JsonSerializer.Serialize(stream, persisted, options);
                    stream.Write("\n"u8);
                    InjectFailure("flush");
                    stream.Flush(flushToDisk: true);
                }
                InjectFailure("move");
                File.Move(tempPath, finalPath, overwrite: false);
                if (length != 16) WriteDiagnostic("filename-collision-disambiguated", hash, null);
                return;
            }
            catch (IOException) when (File.Exists(finalPath))
            {
                TryDelete(tempPath);
                if (FileHasEvent(finalPath, item.SourceEventId)) { WriteDiagnostic("idempotent-existing", hash, null); return; }
            }
            catch
            {
                TryDelete(tempPath);
                throw;
            }
        }
        WriteDiagnostic("identity-collision", hash, null);
        Environment.ExitCode = 3;
    }
    finally { if (mutexAcquired) mutex.ReleaseMutex(); }
}
catch (ArgumentException ex) { WriteDiagnostic(ex.Message, null, ex.GetType()); Environment.ExitCode = 2; }
catch (Exception ex) { WriteDiagnostic("publish-failed", null, ex.GetType()); Environment.ExitCode = 3; }

static string ResolveSpoolRoot(string[] args)
{
    string? value = null;
    for (var i = 0; i < args.Length; i++)
    {
        if (args[i] == "--spool-root") { if (++i >= args.Length) throw new ArgumentException("invalid-spool-root"); value = args[i]; }
        else throw new ArgumentException("invalid-argument");
    }
    value ??= Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_SPOOL_HOME");
    value ??= Path.Combine(Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_RUNTIME_HOME") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexNotificationRuntime"), "spool");
    if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value)) throw new ArgumentException("invalid-spool-root");
    return Path.GetFullPath(value);
}
static ProviderInput ParseAndValidate(string input, JsonSerializerOptions options)
{
    try
    {
        using var document = JsonDocument.Parse(input);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object) throw new ArgumentException("invalid-stdin");
        var required = new HashSet<string>(StringComparer.Ordinal)
        {
            "schema_version", "source", "source_event_id", "primary_process", "observed_status", "occurred_at",
            "title", "repository", "resume_uri", "result_uri", "notification_status"
        };
        var properties = root.EnumerateObject().ToArray();
        if (properties.Length != required.Count || properties.Any(property => !required.Contains(property.Name)) ||
            properties.Select(property => property.Name).Distinct(StringComparer.Ordinal).Count() != required.Count)
            throw new ArgumentException("invalid-stdin");

        if (!root.GetProperty("schema_version").TryGetInt32(out var schemaVersion) || schemaVersion != 1 ||
            GetRequiredString(root, "source") != "codex.agent-turn-complete" ||
            !IsText(GetRequiredString(root, "primary_process")) ||
            !IsText(GetRequiredString(root, "observed_status")) ||
            !IsText(GetRequiredString(root, "title")) ||
            !IsText(GetRequiredString(root, "repository")))
            throw new ArgumentException("invalid-stdin");

        var sourceEventId = GetRequiredString(root, "source_event_id");
        var occurredAtText = GetRequiredString(root, "occurred_at");
        var resumeUri = GetRequiredString(root, "resume_uri");
        var notificationStatus = GetRequiredString(root, "notification_status");
        if (!sourceEventId.StartsWith("codex:", StringComparison.Ordinal) || sourceEventId.Length == "codex:".Length ||
            !DateTimeOffset.TryParse(occurredAtText, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind, out _) ||
            !IsResumeUri(resumeUri) ||
            notificationStatus is not ("PENDING" or "DELIVERED" or "FAILED" or "DUPLICATE"))
            throw new ArgumentException("invalid-stdin");

        var resultElement = root.GetProperty("result_uri");
        if (resultElement.ValueKind != JsonValueKind.Null &&
            (resultElement.ValueKind != JsonValueKind.String || !IsAllowedResultUri(resultElement.GetString())))
            throw new ArgumentException("invalid-stdin");

        return JsonSerializer.Deserialize<ProviderInput>(root.GetRawText(), options) ?? throw new ArgumentException("invalid-stdin");
    }
    catch (JsonException)
    {
        throw new ArgumentException("invalid-stdin");
    }
    catch (InvalidOperationException)
    {
        throw new ArgumentException("invalid-stdin");
    }
    catch (FormatException)
    {
        throw new ArgumentException("invalid-stdin");
    }
}
static string GetRequiredString(JsonElement root, string name)
{
    var value = root.GetProperty(name);
    if (value.ValueKind != JsonValueKind.String) throw new ArgumentException("invalid-stdin");
    return value.GetString() ?? throw new ArgumentException("invalid-stdin");
}
static bool IsText(string value) => !string.IsNullOrWhiteSpace(value);
static bool IsResumeUri(string value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
    string.Equals(uri.Scheme, "codex", StringComparison.OrdinalIgnoreCase) &&
    string.Equals(uri.Host, "threads", StringComparison.OrdinalIgnoreCase) && uri.AbsolutePath.Length > 1;
static bool IsAllowedResultUri(string? value)
{
    if (string.IsNullOrWhiteSpace(value) || value.Length > 2048 || !Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
        uri.Scheme != Uri.UriSchemeHttps || !string.IsNullOrEmpty(uri.UserInfo)) return false;
    var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
    if (segments.Length == 0) return false;
    return !uri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase) || segments.Length >= 3;
}
static void InjectFailure(string stage)
{
    if (string.Equals(Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_TEST_PROVIDER_FAILURE"), stage, StringComparison.Ordinal))
        throw new IOException("injected-" + stage + "-failure");
}
static bool FindSameEvent(string root, string hash, string id) => Directory.EnumerateFiles(root, "*__" + hash[..16] + "*.json").Any(path => FileHasEvent(path, id));
static bool FileHasEvent(string path, string id) { try { return JsonSerializer.Deserialize<SpoolItem>(File.ReadAllText(path), new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower })?.SourceEventId == id; } catch { return false; } }
static string BuildFileName(SpoolItem item, string hash) => item.OccurredAt.ToUniversalTime().ToString("yyyyMMdd'T'HHmmss.fffffff'Z'") + "__" + Project(item.ObservedStatus, 24) + "__" + Project(item.Repository, 48) + "__" + hash + ".json";
static string Project(string value, int max = 48) { var normalized = value.Normalize(NormalizationForm.FormKC).ToLowerInvariant(); normalized = Regex.Replace(normalized, "[^a-z0-9]+", "-").Trim('-'); return (normalized.Length == 0 ? "unknown" : normalized)[..Math.Min(max, Math.Max(1, normalized.Length == 0 ? 7 : normalized.Length))]; }
static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
static void TryDelete(string path) { try { File.Delete(path); } catch { } }
static void WriteDiagnostic(string code, string? hash, Type? exception) => Console.Error.WriteLine(JsonSerializer.Serialize(new { code, event_hash = hash, exception_type = exception?.Name }));

sealed class ProviderInput { public int SchemaVersion { get; set; } public string Source { get; set; } = ""; public string SourceEventId { get; set; } = ""; public string PrimaryProcess { get; set; } = ""; public string ObservedStatus { get; set; } = ""; public DateTimeOffset OccurredAt { get; set; } public string Title { get; set; } = ""; public string Repository { get; set; } = ""; public string ResumeUri { get; set; } = ""; public string? ResultUri { get; set; } public string NotificationStatus { get; set; } = ""; }
sealed record SpoolItem(int SchemaVersion, string Source, string SourceEventId, string PrimaryProcess, string ObservedStatus, DateTimeOffset OccurredAt, string Title, string Repository, string ResumeUri, string? ResultUri);
