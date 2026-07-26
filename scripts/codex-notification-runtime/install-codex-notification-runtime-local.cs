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
    Console.WriteLine("dotnet run --file scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs -- [install] [--dry-run] [--check] [--codex-home <path>] [--install-root <path>] [--target-marker <literal>]");
    return;
}
if (parsed.SelfTest)
{
    InstallerSelfTest();
    return;
}

var codexHome = parsed.CodexHome ?? Environment.GetEnvironmentVariable("CODEX_HOME") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
var configPath = Path.Combine(codexHome, "config.toml");
var packageRoot = FindPackageRoot();
if (packageRoot is null) throw new InvalidOperationException("scripts/codex-notification-runtime が見つかるrepository rootから実行してください。");
var installRoot = parsed.InstallRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexNotificationRuntime");
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
if (IsSelfCommand(chained, runtimePath)) throw new InvalidOperationException("保存された既存notifyがruntime自身を参照しています。再帰を避けるため停止しました。");

Console.WriteLine($"Codex home: {codexHome}");
Console.WriteLine($"Runtime root: {installRoot}");
Console.WriteLine(existing.Count == 0 ? "既存notify: なし" : "既存notify: 検出");
Console.WriteLine(chained is null ? "chain: なし" : "chain: 既存notifyを保持");
if (parsed.Check)
{
    var runtimeExists = File.Exists(runtimePath);
    var providerExists = File.Exists(providerPath);
    var configExists = stored is not null;
    var notifyConfigured = alreadyInstalled;
    var selfWrapAbsent = !IsSelfCommand(stored?.ChainedNotify, runtimePath);
    var providerSupport = providerExists ? RunCheck(providerPath, "--check-support") : null;
    Console.WriteLine($"runtime_binary: {(runtimeExists ? "PASS" : "FAIL")}");
    Console.WriteLine($"provider_binary: {(providerExists ? "PASS" : "FAIL")}");
    Console.WriteLine($"runtime_config: {(configExists ? "PASS" : "FAIL")}");
    Console.WriteLine($"notify_target: {(notifyConfigured ? "PASS" : "FAIL")}");
    Console.WriteLine($"self_wrap_absent: {(selfWrapAbsent ? "PASS" : "FAIL")}");
    Console.WriteLine($"provider_support: {(providerSupport == 0 ? "supported" : providerSupport == 3 ? "unsupported" : "check-failed")}");
    var structurallyValid = runtimeExists && providerExists && configExists && notifyConfigured && selfWrapAbsent;
    if (!structurallyValid)
    {
        Console.WriteLine("FAIL installer check");
        Environment.ExitCode = 2;
    }
    else if (providerSupport != 0)
    {
        Console.WriteLine("DEGRADED installer check: configured provider is unavailable");
        Environment.ExitCode = 3;
    }
    else
    {
        Console.WriteLine("PASS installer check");
        Environment.ExitCode = 0;
    }
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
var bin = Path.Combine(installRoot, "bin");
var previousBin = Path.Combine(installRoot, "bin.previous-" + Guid.NewGuid().ToString("N"));
var previousRuntimeConfig = runtimeConfigPath + ".previous-" + Guid.NewGuid().ToString("N");
var backup = configPath + ".codex-notification-runtime.bak";
var backupCreated = false;
var binSwapped = false;
var runtimeConfigSwapped = false;
try
{
    await PublishAsync(Path.Combine(packageRoot, "codex-notification-runtime.cs"), stage, "codex-notification-runtime");
    await PublishAsync(Path.Combine(packageRoot, "windows-app-notification-provider.cs"), stage, "windows-app-notification-provider");
    EnsureExitCode(Path.Combine(stage, "codex-notification-runtime.exe"), "--self-test", 0);
    EnsureExitCode(Path.Combine(stage, "windows-app-notification-provider.exe"), "--self-test", 0);
    var marker = parsed.TargetMarker ?? "[completion-notification]";
    var runtimeConfig = new RuntimeConfig
    {
        TargetMarkers = [marker],
        ChainedNotify = chained,
        Providers = [new ProviderSpec { Name = "windows-app-notification", Argv = [providerPath], TimeoutMs = 5000 }],
        OriginalConfigExisted = alreadyInstalled ? stored!.OriginalConfigExisted : File.Exists(configPath)
    };
    var replacement = "notify = [ " + string.Join(", ", targetNotify.Select(TomlString)) + " ]";
    var output = existing.Count == 0 ? InsertTopLevelNotify(configText, replacement) : configText[..existing[0].Start] + replacement + configText[existing[0].End..];
    if (!TomlSerializer.TryDeserialize<Dictionary<string, object?>>(output, out _, new TomlSerializerOptions()))
        throw new InvalidOperationException("生成後のconfig.tomlがTOMLとして不正です。");

    if (!alreadyInstalled && File.Exists(configPath))
    {
        if (File.Exists(backup)) throw new InvalidOperationException($"既存backupがあるため上書きしません: {backup}");
        File.Copy(configPath, backup, overwrite: false);
        backupCreated = true;
    }
    if (Directory.Exists(bin)) Directory.Move(bin, previousBin);
    Directory.Move(stage, bin);
    binSwapped = true;
    if (Environment.GetEnvironmentVariable("CODEX_NOTIFICATION_TEST_FAIL_AFTER_BIN_SWAP") == "1") throw new InvalidOperationException("Injected failure after bin swap.");
    if (File.Exists(runtimeConfigPath)) File.Move(runtimeConfigPath, previousRuntimeConfig);
    WriteAtomic(runtimeConfigPath, JsonSerializer.Serialize(runtimeConfig, runtimeJsonOptions));
    runtimeConfigSwapped = true;
    File.WriteAllText(configPath + ".tmp", output);
    File.Move(configPath + ".tmp", configPath, overwrite: true);
    TryDeleteDirectory(previousBin);
    TryDelete(previousRuntimeConfig);
    Console.WriteLine("インストール完了。Codexを新しく開始したturnから有効になります。");
}
catch
{
    TryDelete(configPath + ".tmp");
    if (binSwapped && Directory.Exists(bin)) Directory.Delete(bin, recursive: true);
    if (Directory.Exists(previousBin)) Directory.Move(previousBin, bin);
    if (runtimeConfigSwapped) TryDelete(runtimeConfigPath);
    if (File.Exists(previousRuntimeConfig)) File.Move(previousRuntimeConfig, runtimeConfigPath, overwrite: true);
    if (backupCreated) TryDelete(backup);
    throw;
}
finally
{
    if (Directory.Exists(stage)) Directory.Delete(stage, recursive: true);
    TryDeleteDirectory(previousBin);
    TryDelete(previousRuntimeConfig);
}

static async Task PublishAsync(string source, string output, string name)
{
    var info = new ProcessStartInfo("dotnet") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
    info.ArgumentList.Add("publish"); info.ArgumentList.Add(source); info.ArgumentList.Add("--output"); info.ArgumentList.Add(output); info.ArgumentList.Add("-p:AssemblyName=" + name);
    using var process = Process.Start(info) ?? throw new InvalidOperationException("dotnet publishを開始できません。");
    var stdout = process.StandardOutput.ReadToEndAsync();
    var stderr = process.StandardError.ReadToEndAsync();
    await process.WaitForExitAsync();
    var standardOutput = await stdout;
    var standardError = await stderr;
    if (process.ExitCode != 0) throw new InvalidOperationException(string.IsNullOrWhiteSpace(standardError) ? standardOutput : standardError);
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

static string InsertTopLevelNotify(string text, string replacement)
{
    var tableStart = -1;
    var offset = 0;
    foreach (var line in SplitLines(text))
    {
        var trimmed = line.Text.TrimStart();
        if (trimmed.StartsWith('[')) { tableStart = offset; break; }
        offset += line.Text.Length + line.NewLineLength;
    }
    var newline = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
    if (tableStart < 0) return text.TrimEnd('\r', '\n') + (text.Length == 0 ? "" : newline) + replacement + newline;
    var prefix = text[..tableStart];
    if (prefix.Length > 0 && !prefix.EndsWith(newline, StringComparison.Ordinal)) prefix += newline;
    return prefix + replacement + newline + text[tableStart..];
}

static void WriteAtomic(string path, string content)
{
    var temporary = path + ".tmp";
    File.WriteAllText(temporary, content);
    File.Move(temporary, path, overwrite: true);
}

static int? RunCheck(string executable, string argument)
{
    try
    {
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true };
        info.ArgumentList.Add(argument);
        using var process = Process.Start(info);
        process?.WaitForExit(5000);
        return process?.HasExited == true ? process.ExitCode : null;
    }
    catch { return null; }
}

static void EnsureExitCode(string executable, string argument, int expected)
{
    var actual = RunCheck(executable, argument);
    if (actual != expected) throw new InvalidOperationException($"staged binary check failed: {Path.GetFileName(executable)} exit={actual?.ToString() ?? "timeout"}");
}

static bool IsSelfCommand(CommandSpec? command, string runtimePath)
{
    if (command?.Argv is not { Count: > 0 }) return false;
    try { return string.Equals(Path.GetFullPath(command.Argv[0]), Path.GetFullPath(runtimePath), StringComparison.OrdinalIgnoreCase); }
    catch { return true; }
}

static void TryDelete(string path) { try { if (File.Exists(path)) File.Delete(path); } catch { } }
static void TryDeleteDirectory(string path) { try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); } catch { } }

static void InstallerSelfTest()
{
    var original = "model_provider = \"openai\"\r\n\r\n[features]\r\nweb_search = true\r\n";
    var replacement = "notify = [ \"C:\\\\runtime.exe\", \"dispatch\" ]";
    var output = InsertTopLevelNotify(original, replacement);
    if (output.IndexOf(replacement, StringComparison.Ordinal) > output.IndexOf("[features]", StringComparison.Ordinal)) throw new InvalidOperationException("notify was not inserted before the first table");
    var matches = FindTopLevelNotify(output);
    if (matches.Count != 1 || ParseNotifyArray(matches[0].Value) is not { Count: 2 }) throw new InvalidOperationException("inserted notify is not a valid top-level argv");
    var empty = InsertTopLevelNotify("", replacement);
    if (FindTopLevelNotify(empty).Count != 1) throw new InvalidOperationException("empty config insertion failed");
    Console.WriteLine("PASS installer self-test (3 cases)");
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
        case "install": break; case "--dry-run": option.DryRun = true; break; case "--check": option.Check = true; break; case "--self-test": option.SelfTest = true; break; case "--allow-profiles": option.AllowProfiles = true; break; case "--help": case "-h": option.Help = true; break;
        case "--codex-home" when i + 1 < values.Length: option.CodexHome = values[++i]; break; case "--target-marker" when i + 1 < values.Length: option.TargetMarker = values[++i]; break;
        case "--install-root" when i + 1 < values.Length: option.InstallRoot = values[++i]; break;
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
sealed class InstallOptions { public bool DryRun { get; set; } public bool Check { get; set; } public bool SelfTest { get; set; } public bool AllowProfiles { get; set; } public bool Help { get; set; } public string? CodexHome { get; set; } public string? InstallRoot { get; set; } public string? TargetMarker { get; set; } public string? Error { get; set; } }
sealed class RuntimeConfig { public List<string> TargetMarkers { get; set; } = []; public List<ProviderSpec> Providers { get; set; } = []; public CommandSpec? ChainedNotify { get; set; } public bool OriginalConfigExisted { get; set; } }
sealed class ProviderSpec { public string Name { get; set; } = ""; public List<string> Argv { get; set; } = []; public int TimeoutMs { get; set; } = 5000; }
sealed class CommandSpec { public List<string> Argv { get; set; } = []; }
