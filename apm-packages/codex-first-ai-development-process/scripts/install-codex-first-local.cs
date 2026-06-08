#:property TargetFramework=net10.0

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using static System.Console;

const string StartMarker = "<!-- codex-first:start -->";
const string EndMarker = "<!-- codex-first:end -->";

var options = ParseArguments(args);

if (options is null || options.ShowHelp || string.IsNullOrWhiteSpace(options.TargetRepoRoot))
{
    ShowUsage();
    if (options?.HasError == true)
    {
        Environment.Exit(2);
    }

    Environment.Exit(0);
}

if (options.DryRun)
{
    WriteLine("[dry-run] ファイルは変更しません。実行計画だけを表示します。");
}
if (options.CheckOnly)
{
    WriteLine("[check-only] ファイルは変更しません。整合チェックのみを行い、問題があれば終了コード 2 で報告します。");
}

var targetRepoRoot = Path.GetFullPath(options.TargetRepoRoot);
if (!Directory.Exists(targetRepoRoot))
{
    WriteLine($"Error: 対象リポジトリが見つかりません: {targetRepoRoot}");
    Environment.Exit(2);
}

var packageRoot = ResolvePackageRoot(options.PackageRoot);
if (packageRoot is null)
{
    WriteLine("Error: codex-first package のソースを見つけられませんでした。");
    WriteLine("cwd または --package-root で apm-packages\\codex-first-ai-development-process を指定して実行してね。");
    Environment.Exit(2);
}

var sourceProfile = Path.Combine(packageRoot, "profiles", "codex-first");
var sourceConfig = Path.Combine(sourceProfile, "config.toml");
var sourceAgents = Path.Combine(sourceProfile, "agents");
var sourceTemplate = Path.Combine(packageRoot, "templates", "codex-first-state.md");

if (!Directory.Exists(sourceProfile) || !File.Exists(sourceConfig) || !Directory.Exists(sourceAgents) || !File.Exists(sourceTemplate))
{
    WriteLine($"Error: スクリプトの入力テンプレートが見つからない: {packageRoot}");
    Environment.Exit(2);
}

var logs = new List<string>();
var blockers = new List<string>();

try
{
    ApplyAgentsSection(
        targetRepoRoot,
        options.DryRun || options.CheckOnly,
        options.Force,
        options.Verbose,
        packageRoot,
        logs,
        blockers);

    MergeConfig(
        sourceConfig,
        targetRepoRoot,
        options.DryRun || options.CheckOnly,
        logs,
        blockers);

    CopyAgentFiles(
        sourceAgents,
        targetRepoRoot,
        options.DryRun,
        options.CheckOnly,
        options.Force,
        options.Verbose,
        logs,
        blockers);

    CopyTemplate(
        sourceTemplate,
        targetRepoRoot,
        options.DryRun || options.CheckOnly,
        options.Force,
        logs,
        blockers);
}
catch (Exception ex)
{
    WriteLine($"Error: {ex.Message}");
    if (options.Verbose)
    {
        WriteLine(ex);
    }

    Environment.Exit(2);
}

WriteLine();
WriteLine("=== 実行結果 ===");
foreach (var log in logs)
{
    WriteLine(log);
}

if (blockers.Count > 0)
{
    WriteLine();
    WriteLine("=== 修正が必要な箇所 ===");
    foreach (var blocker in blockers)
    {
        WriteLine(blocker);
    }

    WriteLine();
    WriteLine("--force を付けるか、対象ファイルを確認して再実行してね。");
    Environment.Exit(2);
}

if (options.DryRun || options.CheckOnly)
{
    WriteLine();
    WriteLine((options.CheckOnly ? "check-only 完了。問題がなければ次は --dry-run なしで実行してインストール可能。" : "dry-run 完了。実際に反映するには --dry-run を外して再実行してね。"));
}
else
{
    WriteLine();
    WriteLine("インストール完了。対象リポジトリで `codex status` 等を確認してね。");
}

Environment.Exit(0);

static InstallOptions ParseArguments(string[] args)
{
    var options = new InstallOptions();
    for (var i = 0; i < args.Length; i++)
    {
        var arg = args[i];
        if (arg == "--dry-run" || arg == "-n")
        {
            options.DryRun = true;
            continue;
        }

        if (arg == "--check" || arg == "--check-only")
        {
            options.CheckOnly = true;
            continue;
        }

        if (arg == "--force" || arg == "-f")
        {
            options.Force = true;
            continue;
        }

        if (arg == "--verbose" || arg == "-v")
        {
            options.Verbose = true;
            continue;
        }

        if (arg == "--help" || arg == "-h")
        {
            options.ShowHelp = true;
            continue;
        }

        if ((arg == "--package-root" || arg == "-p") && i + 1 < args.Length)
        {
            options.PackageRoot = args[++i];
            continue;
        }

        if (!string.IsNullOrWhiteSpace(arg) && arg.StartsWith("-", StringComparison.Ordinal))
        {
            options.HasError = true;
            continue;
        }

        if (string.IsNullOrWhiteSpace(options.TargetRepoRoot))
        {
            options.TargetRepoRoot = arg;
            continue;
        }

        options.HasError = true;
        options.ShowHelp = true;
    }

    if (options.DryRun && options.CheckOnly)
    {
        options.HasError = true;
        options.ShowHelp = true;
    }

    return options;
}

static void ShowUsage()
{
    WriteLine("Usage:");
    WriteLine("  dotnet run --file apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs -- <target-repo-root> [options]");
    WriteLine();
    WriteLine("Arguments:");
    WriteLine("  <target-repo-root>   導入先リポジトリのルートフォルダ");
    WriteLine();
    WriteLine("Options:");
    WriteLine("  --dry-run, -n        変更内容を表示だけ行う");
    WriteLine("  --check, --check-only 内容を検査だけ行う");
    WriteLine("  --force, -f          競合する既存ファイルを上書き");
    WriteLine("  --verbose, -v        詳細ログを表示");
    WriteLine("  --package-root <dir> スクリプト参照元の package ルートを明示");
    WriteLine("  --help, -h           この説明を表示");
}

static string? ResolvePackageRoot(string? overrideRoot)
{
    if (!string.IsNullOrWhiteSpace(overrideRoot))
    {
        var explicitRoot = Path.GetFullPath(overrideRoot);
        return IsPackageRoot(explicitRoot) ? explicitRoot : null;
    }

    var current = Path.GetFullPath(Directory.GetCurrentDirectory());
    var markerPath = Path.Combine("apm-packages", "codex-first-ai-development-process", "profiles", "codex-first", "config.toml");
    var dir = new DirectoryInfo(current);

    while (dir is not null)
    {
        var candidate = Path.Combine(dir.FullName, markerPath);
        if (File.Exists(candidate))
        {
            return Path.GetFullPath(Path.Combine(dir.FullName, "apm-packages", "codex-first-ai-development-process"));
        }

        dir = dir.Parent;
    }

    return null;
}

static bool IsPackageRoot(string dir)
{
    return File.Exists(Path.Combine(dir, "profiles", "codex-first", "config.toml"));
}

static void ApplyAgentsSection(
    string targetRepoRoot,
    bool dryRun,
    bool force,
    bool verbose,
    string packageRoot,
    List<string> logs,
    List<string> blockers)
{
    var agentsPath = Path.Combine(targetRepoRoot, "AGENTS.md");
    var section = BuildAgentsSection(packageRoot);

    if (!File.Exists(agentsPath))
    {
        AddOrReplace(agentsPath, section, dryRun, logs, "AGENTS.md を新規作成");
        return;
    }

    var original = File.ReadAllText(agentsPath);
    var start = original.IndexOf(StartMarker, StringComparison.Ordinal);
    var end = original.IndexOf(EndMarker, StringComparison.Ordinal);

    if (start >= 0 && end > start)
    {
        var existingBlock = original[start..(end + EndMarker.Length)];
        if (NormalizeForCompare(existingBlock) == NormalizeForCompare(section))
        {
            logs.Add("AGENTS.md: Codex-first section は既存のまま（変更なし）");
            return;
        }

        if (!force)
        {
            blockers.Add("AGENTS.md: codex-first:start/end ブロック内の内容が不一致です。--force か manual で調整してから再実行して。");
            return;
        }

        var updated = original[..start] + section + original[(end + EndMarker.Length)..];
        AddOrReplace(agentsPath, updated, dryRun, logs, "AGENTS.md: codex-first section を差し替え");
        return;
    }

    if (ContainsCodexFirstMarker(original))
    {
        blockers.Add("AGENTS.md: start/end マーカーが壊れているようです。片方だけある状態は manual で修正を推奨。");
        return;
    }

    if (original.Contains("Codex-first", StringComparison.OrdinalIgnoreCase))
    {
        var appended = AppendWithSpacing(original, section);
        AddOrReplace(agentsPath, appended, dryRun, logs, "AGENTS.md: 既存内容に Codex-first セクションを追加");
        return;
    }

    AddOrReplace(agentsPath, AppendWithSpacing(original, section), dryRun, logs, "AGENTS.md: codex-first section を追加");
}

static void MergeConfig(
    string sourceConfigPath,
    string targetRepoRoot,
    bool dryRun,
    List<string> logs,
    List<string> blockers)
{
    var targetPath = Path.Combine(targetRepoRoot, ".codex", "config.toml");
    var sourceText = File.ReadAllText(sourceConfigPath);
    var source = ParseTomlSimple(sourceText);

    if (!File.Exists(targetPath))
    {
        AddOrReplace(targetPath, sourceText, dryRun, logs, ".codex/config.toml を作成");
        return;
    }

    var targetText = File.ReadAllText(targetPath);
    var merged = MergeTomlContent(targetText, source);
    if (NormalizeForCompare(merged) == NormalizeForCompare(targetText))
    {
        logs.Add(".codex/config.toml: 既存の設定を保持（追加は不要）");
        return;
    }

    AddOrReplace(targetPath, merged, dryRun, logs, ".codex/config.toml を補完（既存値優先）");
}

static void CopyAgentFiles(
    string sourceAgentDir,
    string targetRepoRoot,
    bool dryRun,
    bool checkOnly,
    bool force,
    bool verbose,
    List<string> logs,
    List<string> blockers)
{
    var targetAgentDir = Path.Combine(targetRepoRoot, ".codex", "agents");
    Directory.CreateDirectory(targetAgentDir);
    foreach (var sourceFile in Directory.GetFiles(sourceAgentDir, "*.toml").OrderBy(p => p, StringComparer.OrdinalIgnoreCase))
    {
        var fileName = Path.GetFileName(sourceFile);
        var targetFile = Path.Combine(targetAgentDir, fileName);
        if (!File.Exists(targetFile))
        {
            if (dryRun)
            {
                logs.Add($"[dry-run] .codex/agents/{fileName}: 追加");
            }
            else if (checkOnly)
            {
                blockers.Add($".codex/agents/{fileName}: 既存インストールに対象ファイルがありません");
            }
            else
            {
                File.Copy(sourceFile, targetFile, overwrite: true);
                logs.Add($".codex/agents/{fileName}: 追加");
            }

            continue;
        }

        var sourceText = File.ReadAllText(sourceFile);
        var sourceForCompare = NormalizeForCompare(sourceText);
        var targetText = File.ReadAllText(targetFile);
        var targetForCompare = NormalizeForCompare(targetText);

        var sourceTopLevel = ParseTomlTopLevel(sourceText);
        var targetTopLevel = ParseTomlTopLevel(targetText);
        var noWrite = dryRun || checkOnly;
        var canRepair = force && !noWrite;
        var hasTopLevelIssues = ValidateAgentTopLevelKeys(
            fileName,
            targetTopLevel,
            sourceTopLevel,
            canRepair,
            noWrite,
            logs,
            blockers);

        if (sourceForCompare == targetForCompare && !hasTopLevelIssues)
        {
            logs.Add($".codex/agents/{fileName}: 既存同内容のため変更なし");
            continue;
        }

        if (!force || noWrite)
        {
            blockers.Add($".codex/agents/{fileName}: 既存ファイルと内容が異なるため、更新保留（--force で上書き）");
            continue;
        }

        if (dryRun)
        {
            logs.Add($"[dry-run] .codex/agents/{fileName}: 上書き予定");
        }
        else
        {
            File.Copy(sourceFile, targetFile, overwrite: true);
            logs.Add($".codex/agents/{fileName}: 上書き");
        }
    }
}

static void CopyTemplate(
    string sourceTemplate,
    string targetRepoRoot,
    bool dryRun,
    bool force,
    List<string> logs,
    List<string> blockers)
{
    var targetTemplate = Path.Combine(targetRepoRoot, "templates", "codex-first-state.md");
    Directory.CreateDirectory(Path.GetDirectoryName(targetTemplate)!);
    if (!File.Exists(targetTemplate))
    {
        CopyOrCopyDryRun(sourceTemplate, targetTemplate, dryRun, logs, "templates/codex-first-state.md を追加");
        return;
    }

    var sourceText = NormalizeForCompare(File.ReadAllText(sourceTemplate));
    var targetText = NormalizeForCompare(File.ReadAllText(targetTemplate));
    if (sourceText == targetText)
    {
        logs.Add("templates/codex-first-state.md: 既存同内容のため変更なし");
        return;
    }

    if (!force)
    {
        blockers.Add("templates/codex-first-state.md: 既存内容が異なるため上書き保留（--force が必要）");
        return;
    }

    CopyOrCopyDryRun(sourceTemplate, targetTemplate, dryRun, logs, "templates/codex-first-state.md を上書き");
}

static void CopyOrCopyDryRun(string source, string target, bool dryRun, List<string> logs, string label)
{
    if (dryRun)
    {
        logs.Add($"[dry-run] {label}");
    }
    else
    {
        File.Copy(source, target, overwrite: true);
        logs.Add(label);
    }
}

static void AddOrReplace(
    string path,
    string newContent,
    bool dryRun,
    List<string> logs,
    string logLabel)
{
    if (dryRun)
    {
        logs.Add($"[dry-run] {logLabel}");
        return;
    }

    var dir = Path.GetDirectoryName(path);
    if (!string.IsNullOrWhiteSpace(dir))
    {
        Directory.CreateDirectory(dir);
    }

    File.WriteAllText(path, newContent);
    logs.Add(logLabel);
}

static bool ValidateAgentTopLevelKeys(
    string fileName,
    Dictionary<string, string> targetTopLevel,
    Dictionary<string, string> sourceTopLevel,
    bool canRepair,
    bool dryRun,
    List<string> logs,
    List<string> blockers)
{
    var keys = new[] { "model", "model_reasoning_effort", "sandbox_mode" };
    var hasIssue = false;
    foreach (var key in keys)
    {
        if (!sourceTopLevel.TryGetValue(key, out var sourceValue))
        {
            continue;
        }

        if (!targetTopLevel.TryGetValue(key, out var targetValue))
        {
            hasIssue = true;
            if (canRepair)
            {
                logs.Add((dryRun ? "[dry-run] " : "") + $".codex/agents/{fileName}: top-level `{key}` を追加して `{sourceValue}` を反映（予定）");
            }
            else
            {
                blockers.Add($".codex/agents/{fileName}: top-level `{key}` が不足しており、値 `{sourceValue}` が必要");
            }

            continue;
        }

        if (!string.Equals(targetValue, sourceValue, StringComparison.Ordinal))
        {
            hasIssue = true;
            if (canRepair)
            {
                logs.Add((dryRun ? "[dry-run] " : "") + $".codex/agents/{fileName}: top-level `{key}` を `{targetValue}` から `{sourceValue}` に更新（予定）");
            }
            else
            {
                blockers.Add($".codex/agents/{fileName}: top-level `{key}` が `{targetValue}` で、package 期待値 `{sourceValue}` と異なる");
            }
        }
    }

    return hasIssue;
}

static string MergeTomlContent(string targetContent, Dictionary<string, string> sourceValues)
{
    var lines = targetContent.Split('\n').Select(NormalizeLine).ToList();

    bool HasTopLevel(string key) => lines
        .TakeWhile(line => !line.StartsWith("[", StringComparison.Ordinal))
        .Any(line => IsTomlAssignment(line, key));

    bool TryFindSection(string sectionName, out int startIndex, out int endIndex)
    {
        startIndex = -1;
        endIndex = lines.Count;
        for (var i = 0; i < lines.Count; i++)
        {
            if (lines[i].StartsWith("[", StringComparison.Ordinal) && IsSectionHeader(lines[i], sectionName))
            {
                startIndex = i;
                for (var j = i + 1; j < lines.Count; j++)
                {
                    if (lines[j].StartsWith("[", StringComparison.Ordinal))
                    {
                        endIndex = j;
                        break;
                    }
                }

                return true;
            }
        }

        return false;
    }

    static bool IsSectionHeader(string line, string sectionName)
    {
        return line.Equals($"[{sectionName}]", StringComparison.Ordinal);
    }

    var changed = new List<string>(lines);

    if (!HasTopLevel("model") && sourceValues.TryGetValue("model", out var modelValue))
    {
        var insertAt = changed.FindIndex(l => l.StartsWith("[", StringComparison.Ordinal));
        if (insertAt < 0)
        {
            insertAt = changed.Count;
        }

        changed.Insert(insertAt, string.Empty);
        changed.Insert(insertAt + 1, $"model = {modelValue}");
        changed.Insert(insertAt + 2, string.Empty);
    }

    if (!HasTopLevel("model_reasoning_effort") && sourceValues.TryGetValue("model_reasoning_effort", out var reasoningValue))
    {
        var insertAt = changed.FindIndex(l => l.StartsWith("[", StringComparison.Ordinal));
        if (insertAt < 0)
        {
            insertAt = changed.Count;
        }

        changed.Insert(insertAt, $"model_reasoning_effort = {reasoningValue}");
    }

    if (!TryFindSection("agents", out var agentsStart, out var agentsEnd))
    {
        changed.Add(string.Empty);
        changed.Add("[agents]");
        if (sourceValues.TryGetValue("max_threads", out var defaultMaxThreads))
        {
            changed.Add($"max_threads = {defaultMaxThreads}");
        }

        if (sourceValues.TryGetValue("max_depth", out var defaultMaxDepth))
        {
            changed.Add($"max_depth = {defaultMaxDepth}");
        }

        return string.Join(Environment.NewLine, changed);
    }

    var agentLines = changed.Skip(agentsStart + 1).Take(agentsEnd - agentsStart - 1).ToList();
    bool HasAgent(string key) => agentLines.Any(line => IsTomlAssignment(line, key));

    if (!HasAgent("max_threads") && sourceValues.TryGetValue("max_threads", out var maxThreads))
    {
        changed.Insert(agentsEnd, $"max_threads = {maxThreads}");
        if (agentsEnd < changed.Count)
        {
            agentsEnd++;
        }
    }

    if (!HasAgent("max_depth") && sourceValues.TryGetValue("max_depth", out var maxDepth))
    {
        changed.Insert(agentsEnd, $"max_depth = {maxDepth}");
    }

    return string.Join(Environment.NewLine, changed);
}

static Dictionary<string, string> ParseTomlSimple(string text)
{
    var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    var lines = text.Split('\n').Select(NormalizeLine).ToList();
    bool inAgents = false;

    foreach (var raw in lines)
    {
        var line = raw.Trim();
        if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal))
        {
            continue;
        }

        if (line.StartsWith("[", StringComparison.Ordinal))
        {
            inAgents = line.Equals("[agents]", StringComparison.OrdinalIgnoreCase);
            continue;
        }

        if (!TryParseAssignment(line, out var key, out var value))
        {
            continue;
        }

        if (!inAgents)
        {
            if (key is "model" or "model_reasoning_effort" or "sandbox_mode")
            {
                values[key] = value;
            }
        }
        else if (key is "max_threads" or "max_depth")
        {
            values[key] = value;
        }
    }

    return values;
}

static Dictionary<string, string> ParseTomlTopLevel(string text)
{
    var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    var lines = text.Split('\n').Select(NormalizeLine).ToList();

    foreach (var raw in lines)
    {
        var line = raw.Trim();
        if (line.Length == 0 || line.StartsWith("#", StringComparison.Ordinal))
        {
            continue;
        }

        if (line.StartsWith("[", StringComparison.Ordinal))
        {
            break;
        }

        if (!TryParseAssignment(line, out var key, out var value))
        {
            continue;
        }

        if (key is "model" or "model_reasoning_effort" or "sandbox_mode")
        {
            values[key] = value;
        }
    }

    return values;
}

static bool TryParseAssignment(string line, out string key, out string value)
{
    key = string.Empty;
    value = string.Empty;
    var idx = line.IndexOf('=');
    if (idx <= 0)
    {
        return false;
    }

    key = line[..idx].Trim();
    value = line[(idx + 1)..].Trim();
    return key.Length > 0 && value.Length > 0;
}

static bool IsTomlAssignment(string line, string key)
{
    var pattern = @"^\s*" + Regex.Escape(key) + @"\s*=";
    return Regex.IsMatch(line, pattern, RegexOptions.IgnoreCase);
}

static string BuildAgentsSection(string packageRoot)
{
    var packagePath = Path.GetFullPath(packageRoot);
    var line = Environment.NewLine;
    var relativePath = Path.Combine("apm-packages", "codex-first-ai-development-process", "scripts", "codex-first-start.ps1");
    var sb = new StringBuilder();
    sb.AppendLine(StartMarker);
    sb.AppendLine("## Codex-first");
    sb.AppendLine();
    sb.AppendLine("このリポジトリには Codex-first コスト意識ルーティングの導入手順を追加した。");
    sb.AppendLine("- 利用者は process 名・agent 名・model 名・full-coverage 分岐を選ぶ必要がない。");
    sb.AppendLine("- repo-local の AGENTS.md / 制約は引き続き最優先で読む。");
    sb.AppendLine("- README の指示と `.codex/config.toml` / `.codex/agents/*.toml` / `templates/codex-first-state.md` を使って `codex-first` 標準ルートを使う。");
    sb.AppendLine("- state artifact には Routing Plan、Edit Permission、Agent Usage Ledger、DelegationCompliance を記録する。");
    sb.AppendLine("- state artifact では execution_mode と、model tier / configured model / hook model / reported model / effective model を分けて記録する。");
    sb.AppendLine("- READY 後の通常実装は `standard-implementer`、通常 verification は `standard-verifier` へ serial delegation する。");
    sb.AppendLine("- `DelegationRequired = Yes` の gate は observed run または explicit human approval 付き `ParentDirectExecutionException` がない限り成功扱いしない。");
    sb.AppendLine("- 親が委譲予定の作業を直接実行した場合、cost-saving delegation 成功として扱わない。");
    sb.AppendLine("- write-heavy parallel editing を標準化しないことは、親が直接実装してよいことを意味しない。");
    sb.AppendLine();
    sb.AppendLine("`codex-first-start.ps1` は起動時のみ CODEX_HOME を切り替える一時 launcher なので、");
    sb.AppendLine("リポジトリごとの標準利用では、本インストーラで `.codex` と `AGENTS.md` を揃える。");
    sb.AppendLine();
    sb.AppendLine($"参考: {Path.Combine(packagePath, relativePath)}");
    sb.AppendLine();
    sb.AppendLine(EndMarker);

    var content = sb.ToString();
    if (!content.EndsWith(line))
    {
        content += line;
    }

    return content;
}

static string AppendWithSpacing(string original, string section)
{
    if (string.IsNullOrWhiteSpace(original))
    {
        return section;
    }

    if (original.EndsWith(Environment.NewLine, StringComparison.Ordinal))
    {
        return original + section;
    }

    return original + Environment.NewLine + Environment.NewLine + section;
}

static bool ContainsCodexFirstMarker(string text)
{
    return text.Contains(StartMarker, StringComparison.Ordinal) || text.Contains(EndMarker, StringComparison.Ordinal);
}

static string NormalizeForCompare(string input)
{
    return NormalizeLine(input).Trim();
}

static string NormalizeLine(string input)
{
    return input.Replace("\r\n", "\n").Replace('\r', '\n');
}

sealed class InstallOptions
{
    public string? TargetRepoRoot { get; set; }
    public bool DryRun { get; set; }
    public bool CheckOnly { get; set; }
    public bool Force { get; set; }
    public bool Verbose { get; set; }
    public bool ShowHelp { get; set; }
    public bool HasError { get; set; }
    public string? PackageRoot { get; set; }
}
