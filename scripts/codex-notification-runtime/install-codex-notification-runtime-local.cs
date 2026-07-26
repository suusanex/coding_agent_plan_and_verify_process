#:property TargetFramework=net10.0
#:property PublishAot=false
#:package Tomlyn@2.10.1

using System.Diagnostics;
using System.Text.Json;
using Tomlyn;

var parsed = Parse(args);
if (parsed.Help || parsed.Error is not null)
{
    Console.WriteLine(parsed.Error ?? "Codex notification runtime installer");
    Console.WriteLine("dotnet run --file scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs -- [install] [--dry-run] [--check] [--codex-home <path>] [--target-marker <literal>]");
    return;
}

var codexHome = parsed.CodexHome ?? Environment.GetEnvironmentVariable("CODEX_HOME") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
var configPath = Path.Combine(codexHome, "config.toml");
var packageRoot = FindPackageRoot();
if (packageRoot is null) throw new InvalidOperationException("scripts/codex-notification-runtime が見つかるrepository rootから実行してください。");
var installRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexNotificationRuntime");
var runtimePath = Path.Combine(installRoot, "bin", "codex-notification-runtime.exe");
var providerPath = Path.Combine(installRoot, "bin", "windows-app-notification-provider.exe");

if (Directory.Exists(codexHome))
{
    var profiles = Directory.GetFiles(codexHome, "*.config.toml");
    if (profiles.Length > 0 && !parsed.AllowProfiles)
        throw new InvalidOperationException("profile別configが存在します。MVP installerはbase configのみを扱います。--allow-profiles を付けて確認済みとして続行してください。");
}

var configText = File.Exists(configPath) ? File.ReadAllText(configPath) : "";
var existing = FindTopLevelNotify(configText);
if (existing.Count > 1) throw new InvalidOperationException("top-level notify が複数あり、安全に合成できません。");
var currentNotify = existing.Count == 1 ? ParseNotifyArray(existing[0].Value) : null;
if (existing.Count == 1 && currentNotify is null) throw new InvalidOperationException("notify は一行のstring arrayである必要があります。multilineまたは不正な値は手動で解消してください。");
var targetNotify = new List<string> { runtimePath, "dispatch" };
var alreadyInstalled = currentNotify is not null && currentNotify.SequenceEqual(targetNotify, StringComparer.OrdinalIgnoreCase);
var runtimeConfigPath = Path.Combine(installRoot, "runtime-config.json");
var runtimeJsonOptions = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower, WriteIndented = true };
var stored = File.Exists(runtimeConfigPath) ? JsonSerializer.Deserialize<RuntimeConfig>(File.ReadAllText(runtimeConfigPath), runtimeJsonOptions) : null;
var chained = alreadyInstalled ? stored?.ChainedNotify : currentNotify is { Count: > 0 } ? new CommandSpec { Argv = currentNotify } : null;
if (alreadyInstalled && stored is null) throw new InvalidOperationException("runtimeを指すnotifyに対応するruntime-config.jsonがありません。再帰を避けるため停止しました。");

Console.WriteLine($"Codex home: {codexHome}");
Console.WriteLine($"Runtime root: {installRoot}");
Console.WriteLine(existing.Count == 0 ? "既存notify: なし" : "既存notify: 検出");
Console.WriteLine(chained is null ? "chain: なし" : "chain: 既存notifyを保持");
if (parsed.Check)
{
    var valid = File.Exists(runtimePath) && File.Exists(providerPath) && alreadyInstalled && stored is not null;
    Console.WriteLine(valid ? "PASS installer check" : "FAIL installer check");
    Environment.ExitCode = valid ? 0 : 2;
    return;
}
if (parsed.DryRun)
{
    Console.WriteLine("dry-run: publish、config書換え、user設定変更は行いません。");
    return;
}

Directory.CreateDirectory(codexHome);
Directory.CreateDirectory(installRoot);
var stage = Path.Combine(installRoot, "stage-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(stage);
try
{
    Publish(Path.Combine(packageRoot, "codex-notification-runtime.cs"), stage, "codex-notification-runtime");
    Publish(Path.Combine(packageRoot, "windows-app-notification-provider.cs"), stage, "windows-app-notification-provider");
    var marker = parsed.TargetMarker ?? "[completion-notification]";
    var runtimeConfig = new RuntimeConfig
    {
        TargetMarkers = [marker],
        ChainedNotify = chained,
        Providers = [new ProviderSpec { Name = "windows-app-notification", Argv = [Path.Combine(stage, "windows-app-notification-provider.exe")], TimeoutMs = 5000 }]
    };
    File.WriteAllText(Path.Combine(stage, "runtime-config.json"), JsonSerializer.Serialize(runtimeConfig, runtimeJsonOptions));
    var bin = Path.Combine(installRoot, "bin");
    if (Directory.Exists(bin)) Directory.Delete(bin, recursive: true);
    Directory.Move(stage, bin);
    runtimeConfig.Providers[0].Argv[0] = providerPath;
    File.WriteAllText(runtimeConfigPath, JsonSerializer.Serialize(runtimeConfig, runtimeJsonOptions));
    var backup = configPath + ".codex-notification-runtime.bak";
    if (File.Exists(configPath)) File.Copy(configPath, backup, overwrite: true);
    var replacement = "notify = [ " + string.Join(", ", targetNotify.Select(TomlString)) + " ]";
    var output = existing.Count == 0 ? configText.TrimEnd() + Environment.NewLine + replacement + Environment.NewLine : configText[..existing[0].Start] + replacement + configText[existing[0].End..];
    if (!TomlSerializer.TryDeserialize<Dictionary<string, object?>>(output, out _, new TomlSerializerOptions()))
        throw new InvalidOperationException("生成後のconfig.tomlがTOMLとして不正です。");
    File.WriteAllText(configPath + ".tmp", output);
    File.Move(configPath + ".tmp", configPath, overwrite: true);
    Console.WriteLine("インストール完了。Codexを新しく開始したturnから有効になります。");
}
finally
{
    if (Directory.Exists(stage)) Directory.Delete(stage, recursive: true);
}

static void Publish(string source, string output, string name)
{
    var info = new ProcessStartInfo("dotnet") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
    info.ArgumentList.Add("publish"); info.ArgumentList.Add(source); info.ArgumentList.Add("--output"); info.ArgumentList.Add(output); info.ArgumentList.Add("-p:AssemblyName=" + name);
    using var process = Process.Start(info) ?? throw new InvalidOperationException("dotnet publishを開始できません。");
    process.WaitForExit();
    if (process.ExitCode != 0) throw new InvalidOperationException(process.StandardError.ReadToEnd());
}

static string? FindPackageRoot()
{
    var directory = new DirectoryInfo(Environment.CurrentDirectory);
    while (directory is not null)
    {
        var candidate = Path.Combine(directory.FullName, "scripts", "codex-notification-runtime");
        if (File.Exists(Path.Combine(candidate, "codex-notification-runtime.cs"))) return candidate;
        directory = directory.Parent;
    }
    return null;
}

static List<NotifyLine> FindTopLevelNotify(string text)
{
    var result = new List<NotifyLine>(); var offset = 0; var inTable = false;
    foreach (var line in SplitLines(text))
    {
        var trimmed = line.Text.Trim();
        if (trimmed.StartsWith('[') && trimmed.EndsWith(']')) inTable = true;
        if (!inTable && trimmed.StartsWith("notify", StringComparison.Ordinal) && trimmed.Length > 6 && char.IsWhiteSpace(trimmed[6]) || (!inTable && trimmed.StartsWith("notify=", StringComparison.Ordinal)))
        {
            var equals = line.Text.IndexOf('='); if (equals > 0) result.Add(new NotifyLine(offset, offset + line.Text.Length, line.Text[(equals + 1)..].Trim()));
        }
        offset += line.Text.Length + line.NewLineLength;
    }
    return result;
}

static List<string>? ParseNotifyArray(string value)
{
    if (!TomlSerializer.TryDeserialize<NotifyOnly>("notify = " + value, out var parsed, new TomlSerializerOptions())) return null;
    return parsed?.Notify;
}
static string TomlString(string value) => "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
static InstallOptions Parse(string[] values)
{
    var option = new InstallOptions();
    for (var i = 0; i < values.Length; i++) switch (values[i])
    {
        case "install": break; case "--dry-run": option.DryRun = true; break; case "--check": option.Check = true; break; case "--allow-profiles": option.AllowProfiles = true; break; case "--help": case "-h": option.Help = true; break;
        case "--codex-home" when i + 1 < values.Length: option.CodexHome = values[++i]; break; case "--target-marker" when i + 1 < values.Length: option.TargetMarker = values[++i]; break;
        default: option.Error = "未知の引数: " + values[i]; break;
    }
    return option;
}

static IEnumerable<(string Text, int NewLineLength)> SplitLines(string value)
{
    var start = 0; for (var i = 0; i < value.Length; i++) if (value[i] == '\n') { var crlf = i > 0 && value[i - 1] == '\r'; var length = crlf ? i - start - 1 : i - start; yield return (value.Substring(start, length), crlf ? 2 : 1); start = i + 1; } if (start < value.Length) yield return (value[start..], 0);
}

sealed record NotifyLine(int Start, int End, string Value);
sealed class NotifyOnly { [Tomlyn.Serialization.TomlPropertyName("notify")] public List<string>? Notify { get; set; } }
sealed class InstallOptions { public bool DryRun { get; set; } public bool Check { get; set; } public bool AllowProfiles { get; set; } public bool Help { get; set; } public string? CodexHome { get; set; } public string? TargetMarker { get; set; } public string? Error { get; set; } }
sealed class RuntimeConfig { public List<string> TargetMarkers { get; set; } = []; public List<ProviderSpec> Providers { get; set; } = []; public CommandSpec? ChainedNotify { get; set; } }
sealed class ProviderSpec { public string Name { get; set; } = ""; public List<string> Argv { get; set; } = []; public int TimeoutMs { get; set; } = 5000; }
sealed class CommandSpec { public List<string> Argv { get; set; } = []; }
