#:property TargetFramework=net10.0
#:property PublishAot=false

using System.ComponentModel;
using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

// Win32Exception is System.ComponentModel.Win32Exception

var options = Options.Parse(args);
if (options.Help)
{
    ShowUsage();
    return 0;
}

try
{
    var result = ReviewerExecutor.Execute(options);
    WriteOutput(result, options.Format);
    return result.ExitStatus == "succeeded" ? 0 : 2;
}
catch (Exception ex) when (
    ex is ContractException
        or IOException
        or JsonException
        or InvalidOperationException
        or TimeoutException
        or Win32Exception)
{
    var failed = ExecutionResult.Failed(
        options.ExecutionApp ?? "unknown",
        options.Model ?? "unknown",
        options.ReviewerRole ?? "unknown",
        ReviewerExecutor.ClassifyFailure(ex),
        ex.Message,
        limitations: ["Deterministic executor failed before final raw artifact publication."]);
    WriteOutput(failed, options.Format);
    return 2;
}

static void ShowUsage()
{
    Console.WriteLine("""
Usage:
  dotnet run --file .agents/skills/goal-context-pr-review/scripts/execute-reviewer.cs -- \
    --execution-app codex-exec|copilot-cli \
    --model <supported-model-or-alias> \
    --reviewer-role local-reviewer|purpose-reviewer \
    --run-root <same-thread-run-root> \
    --round <number> \
    [--timeout-seconds <positive-int>] \
    [--repository-root <path>] \
    [--skill-root <path>] \
    [--codex-executable <path>] \
    [--copilot-executable <path>] \
    [--additional-context-path <path>] \
    [--format json|text]

Deterministic reviewer executor:
  Builds reviewer-role input from existing same-parent round artifacts, invokes a typed
  execution-app adapter (Codex exec or GitHub Copilot CLI), waits with timeout, extracts
  the final review body, and atomically publishes round-NNN/{role}.raw.md plus
  {role}.execution.json metadata together. Does not assess findings or transition run state.

Rejected:
  arbitrary raw command strings, unknown apps/roles/options, unsupported models,
  local-reviewer on purpose-only rounds, empty/malformed success publication,
  repository writes observed during reviewer execution.

Exit codes: 0 succeeded, 2 fail-closed execution or contract failure.
""");
}

static void WriteOutput(ExecutionResult result, string format)
{
    if (format == "json")
    {
        Console.WriteLine(JsonSerializer.Serialize(result, JsonOptions.Default));
        return;
    }

    Console.WriteLine($"Reviewer execution: {result.ExitStatus}");
    Console.WriteLine($"Execution app: {result.ExecutionApp}");
    Console.WriteLine($"Reviewer role: {result.ReviewerRole}");
    Console.WriteLine($"Requested model: {result.RequestedModel}");
    Console.WriteLine($"Observed model: {result.ObservedModel}");
    if (!string.IsNullOrWhiteSpace(result.RawOutputPath)) Console.WriteLine($"Raw output: {result.RawOutputPath}");
    if (!string.IsNullOrWhiteSpace(result.MetadataPath)) Console.WriteLine($"Metadata: {result.MetadataPath}");
    if (!string.IsNullOrWhiteSpace(result.Error)) Console.Error.WriteLine($"Error: {result.Error}");
    foreach (var limitation in result.Limitations) Console.WriteLine($"Limitation: {limitation}");
}

static class ReviewerExecutor
{
    private static readonly HashSet<string> SupportedApps = new(StringComparer.OrdinalIgnoreCase)
    {
        "codex-exec",
        "copilot-cli"
    };

    private static readonly HashSet<string> SupportedRoles = new(StringComparer.OrdinalIgnoreCase)
    {
        "local-reviewer",
        "purpose-reviewer"
    };

    private static readonly Dictionary<string, string> CodexModelAliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["gpt-5.6-terra"] = "gpt-5.6-terra",
        ["gpt-5.4"] = "gpt-5.4",
        ["o4-mini"] = "o4-mini",
        ["o3"] = "o3"
    };

    private static readonly Dictionary<string, string> CopilotModelAliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["gpt-5.4"] = "gpt-5.4",
        ["gpt-5.6-terra"] = "gpt-5.6-terra",
        ["gpt-4.1"] = "gpt-4.1",
        ["claude-sonnet-4"] = "claude-sonnet-4",
        ["auto"] = "auto"
    };

    public static ExecutionResult Execute(Options options)
    {
        ValidateOptions(options);
        var runRoot = ResolveExistingDirectory(options.RunRoot!);
        var repositoryRoot = ResolveRepositoryRoot(runRoot, options.RepositoryRoot);
        var skillRoot = ResolveSkillRoot(repositoryRoot, options.SkillRoot);
        var roundRoot = ResolveRoundRoot(runRoot, options.Round);
        var role = options.ReviewerRole!;
        var app = options.ExecutionApp!;
        var requestedModel = ResolveModel(app, options.Model!);
        EnsureRoleAllowedForRound(runRoot, options.Round, role);
        EnsureRoundArtifacts(roundRoot, role);

        var rawFileName = $"{role}.raw.md";
        var finalRawPath = Path.Combine(roundRoot, rawFileName);
        var metadataPath = Path.Combine(roundRoot, $"{role}.execution.json");
        if (File.Exists(finalRawPath))
            throw new ContractException($"Final raw artifact already exists and will not be overwritten: {Relative(runRoot, finalRawPath)}");
        if (File.Exists(metadataPath))
            throw new ContractException($"Execution metadata already exists and will not be overwritten: {Relative(runRoot, metadataPath)}");

        var startedAt = DateTimeOffset.UtcNow;
        var input = ReviewerInputBuilder.Build(
            repositoryRoot,
            skillRoot,
            runRoot,
            roundRoot,
            role,
            options.Round,
            app,
            options.AdditionalContextPath);

        var workDir = Path.Combine(roundRoot, $".executor-{role}-{Guid.NewGuid():N}");
        Directory.CreateDirectory(workDir);
        try
        {
            var before = WorktreeSnapshot.Capture(repositoryRoot);
            var adapter = CreateAdapter(app, options);
            AdapterResult invocation;
            try
            {
                invocation = adapter.Invoke(new AdapterRequest(
                    repositoryRoot,
                    workDir,
                    requestedModel,
                    role,
                    input,
                    options.TimeoutSeconds));
            }
            catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or IOException)
            {
                invocation = AdapterResult.Fail(
                    "process_start_failure",
                    "unknown",
                    executableLabel(app, options),
                    $"Could not start reviewer process: {ex.Message}",
                    ["Process start failure is not interpreted as no findings."]);
            }

            var after = WorktreeSnapshot.Capture(repositoryRoot);
            var completedAt = DateTimeOffset.UtcNow;
            if (!before.Equals(after))
            {
                invocation = AdapterResult.Fail(
                    "write_detected",
                    invocation.ObservedModel,
                    invocation.CommandShape,
                    $"Reviewer write detected in repository worktree or index. before={before.Describe()} after={after.Describe()}",
                    ["Observed repository mutation fails closed and is not interpreted as no findings."]);
            }

            if (!string.Equals(invocation.ExitStatus, "succeeded", StringComparison.Ordinal))
            {
                var failed = new ExecutionResult
                {
                    ExecutionApp = app,
                    RequestedModel = requestedModel,
                    ObservedModel = invocation.ObservedModel,
                    ReviewerRole = role,
                    StartedAt = startedAt,
                    CompletedAt = completedAt,
                    ExitStatus = invocation.ExitStatus,
                    RawOutputPath = null,
                    MetadataPath = Relative(runRoot, metadataPath + ".failed.json"),
                    Error = invocation.Error,
                    Limitations = MergeLimitations(adapter.Limitations, invocation.Limitations),
                    CommandShape = Redact(invocation.CommandShape)
                };
                AtomicWriteJson(metadataPath + ".failed.json", failed);
                return failed;
            }

            // Post-adapter steps: extract response, build result, publish pair.
            // If any of these fail (e.g., malformed output, missing markers, publish failure),
            // we must still write .failed.json so that evidence is deterministic.
            try
            {
                var body = FinalResponseExtractor.Extract(invocation, role);
                var result = new ExecutionResult
                {
                    ExecutionApp = app,
                    RequestedModel = requestedModel,
                    ObservedModel = invocation.ObservedModel,
                    ReviewerRole = role,
                    StartedAt = startedAt,
                    CompletedAt = completedAt,
                    ExitStatus = "succeeded",
                    RawOutputPath = Relative(runRoot, finalRawPath),
                    MetadataPath = Relative(runRoot, metadataPath),
                    Error = null,
                    Limitations = MergeLimitations(adapter.Limitations, invocation.Limitations),
                    CommandShape = Redact(invocation.CommandShape)
                };
                PublishPair(finalRawPath, body, metadataPath, result);
                return result;
            }
            catch (Exception ex) when (ex is ContractException or IOException)
            {
                // Adapter reported success, but post-processing failed.
                // Clean up any partial raw artifact that may have been created.
                TryDelete(finalRawPath);
                var failedPost = new ExecutionResult
                {
                    ExecutionApp = app,
                    RequestedModel = requestedModel,
                    ObservedModel = invocation.ObservedModel,
                    ReviewerRole = role,
                    StartedAt = startedAt,
                    CompletedAt = DateTimeOffset.UtcNow,
                    ExitStatus = ClassifyFailure(ex),
                    RawOutputPath = null,
                    MetadataPath = Relative(runRoot, metadataPath + ".failed.json"),
                    Error = ex.Message,
                    Limitations = MergeLimitations(adapter.Limitations, invocation.Limitations),
                    CommandShape = Redact(invocation.CommandShape)
                };
                AtomicWriteJson(metadataPath + ".failed.json", failedPost);
                return failedPost;
            }
        }
        finally
        {
            try { if (Directory.Exists(workDir)) Directory.Delete(workDir, recursive: true); } catch { /* best effort */ }
        }
    }

    private static string executableLabel(string app, Options options) => app.ToLowerInvariant() switch
    {
        "codex-exec" => options.CodexExecutable ?? "codex",
        "copilot-cli" => options.CopilotExecutable ?? "copilot",
        _ => app
    };

    private static void ValidateOptions(Options options)
    {
        Require(!string.IsNullOrWhiteSpace(options.ExecutionApp), "--execution-app is required.");
        Require(SupportedApps.Contains(options.ExecutionApp!), $"Unsupported execution app: {options.ExecutionApp}");
        Require(!string.IsNullOrWhiteSpace(options.Model), "--model is required.");
        Require(!string.IsNullOrWhiteSpace(options.ReviewerRole), "--reviewer-role is required.");
        Require(SupportedRoles.Contains(options.ReviewerRole!), $"Unsupported reviewer role: {options.ReviewerRole}");
        _ = ResolveModel(options.ExecutionApp!, options.Model!);
        Require(!string.IsNullOrWhiteSpace(options.RunRoot), "--run-root is required.");
        Require(options.Round is >= 1 and <= 3, "--round must be 1, 2, or 3.");
        Require(options.TimeoutSeconds > 0, "--timeout-seconds must be positive.");
        Require(options.Format is "text" or "json", "--format must be text or json.");
    }

    private static string ResolveModel(string app, string model)
    {
        var map = app.Equals("codex-exec", StringComparison.OrdinalIgnoreCase) ? CodexModelAliases : CopilotModelAliases;
        if (map.TryGetValue(model.Trim(), out var resolved)) return resolved;
        throw new ContractException($"Unsupported model for {app}: {model}");
    }

    private static IReviewerAdapter CreateAdapter(string app, Options options) => app.ToLowerInvariant() switch
    {
        "codex-exec" => new CodexExecAdapter(options.CodexExecutable ?? "codex"),
        "copilot-cli" => new CopilotCliAdapter(options.CopilotExecutable ?? "copilot"),
        _ => throw new ContractException($"Unsupported execution app: {app}")
    };

    private static void EnsureRoleAllowedForRound(string runRoot, int round, string role)
    {
        if (role.Equals("local-reviewer", StringComparison.OrdinalIgnoreCase) && round > 1)
            throw new ContractException("local-reviewer is not allowed on purpose-only rounds 2/3.");

        var statePath = Path.Combine(runRoot, "run-state.json");
        if (!File.Exists(statePath)) return;
        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(statePath));
            if (doc.RootElement.TryGetProperty("rounds", out var rounds) && rounds.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in rounds.EnumerateArray())
                {
                    if (!item.TryGetProperty("number", out var numberEl) || !numberEl.TryGetInt32(out var number) || number != round)
                        continue;
                    if (item.TryGetProperty("mode", out var modeEl) &&
                        string.Equals(modeEl.GetString(), "purpose-only", StringComparison.OrdinalIgnoreCase) &&
                        role.Equals("local-reviewer", StringComparison.OrdinalIgnoreCase))
                    {
                        throw new ContractException("local-reviewer is not allowed when round mode is purpose-only.");
                    }
                }
            }
        }
        catch (ContractException) { throw; }
        catch { /* state is optional pre-check; assess remains authoritative */ }
    }

    private static void EnsureRoundArtifacts(string roundRoot, string role)
    {
        Require(File.Exists(Path.Combine(roundRoot, "review-context.json")), "round review-context.json is missing.");
        Require(File.Exists(Path.Combine(roundRoot, "pr-diff.patch")), "round pr-diff.patch is missing.");
        if (role.Equals("purpose-reviewer", StringComparison.OrdinalIgnoreCase))
            Require(File.Exists(Path.Combine(roundRoot, "goal-context-selection.json")), "round goal-context-selection.json is missing.");
    }

    private static string ResolveRoundRoot(string runRoot, int round)
    {
        var path = Path.Combine(runRoot, $"round-{round:000}");
        Require(Directory.Exists(path), $"Round directory does not exist: round-{round:000}");
        return path;
    }

    private static string ResolveRepositoryRoot(string runRoot, string? explicitRoot)
    {
        if (!string.IsNullOrWhiteSpace(explicitRoot)) return ResolveExistingDirectory(explicitRoot);
        var current = new DirectoryInfo(runRoot);
        while (current is not null)
        {
            if (current.Name == ".review" && current.Parent is not null) return current.Parent.FullName;
            current = current.Parent;
        }
        throw new ContractException("Run root is not under a repository .review directory; pass --repository-root.");
    }

    private static string ResolveSkillRoot(string repositoryRoot, string? explicitRoot)
    {
        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(explicitRoot)) candidates.Add(explicitRoot);
        candidates.Add(Path.Combine(repositoryRoot, ".agents", "skills", "goal-context-pr-review"));
        candidates.Add(Path.Combine(repositoryRoot, "apm-packages", "pr-review-remediation", ".apm", "skills", "goal-context-pr-review"));
        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(Path.Combine(full, "SKILL.md"))) return full;
        }
        throw new ContractException("The goal-context-pr-review Skill root could not be resolved.");
    }

    private static List<string> MergeLimitations(IEnumerable<string> left, IEnumerable<string> right)
    {
        var set = new List<string>();
        foreach (var item in left.Concat(right))
        {
            if (string.IsNullOrWhiteSpace(item)) continue;
            if (!set.Contains(item, StringComparer.Ordinal)) set.Add(item);
        }
        return set;
    }

    private static string Redact(string commandShape)
    {
        if (string.IsNullOrWhiteSpace(commandShape)) return commandShape;
        return Regex.Replace(commandShape, "(?i)(token|password|secret|authorization)=\\S+", "$1=***");
    }

    private static void PublishPair(string rawPath, string rawBody, string metadataPath, ExecutionResult result)
    {
        var directory = Path.GetDirectoryName(rawPath) ?? throw new ContractException($"Invalid path: {rawPath}");
        Directory.CreateDirectory(directory);
        var token = Guid.NewGuid().ToString("N");
        var rawTemp = rawPath + ".partial-" + token;
        var metaTemp = metadataPath + ".partial-" + token;
        try
        {
            var normalized = NormalizeLineEndings(rawBody).TrimEnd() + "\n";
            File.WriteAllText(rawTemp, normalized, new UTF8Encoding(false));
            if (new FileInfo(rawTemp).Length == 0) throw new ContractException("Refusing to publish empty final raw artifact.");
            var json = JsonSerializer.Serialize(result, JsonOptions.Default) + "\n";
            File.WriteAllText(metaTemp, json, new UTF8Encoding(false));
            File.Move(rawTemp, rawPath, overwrite: false);
            try
            {
                File.Move(metaTemp, metadataPath, overwrite: false);
            }
            catch
            {
                TryDelete(rawPath);
                throw;
            }
        }
        finally
        {
            TryDelete(rawTemp);
            TryDelete(metaTemp);
        }
    }

    private static void AtomicWriteJson(string path, ExecutionResult result)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new ContractException($"Invalid path: {path}");
        Directory.CreateDirectory(directory);
        var temp = path + ".partial-" + Guid.NewGuid().ToString("N");
        var json = JsonSerializer.Serialize(result, JsonOptions.Default) + "\n";
        File.WriteAllText(temp, json, new UTF8Encoding(false));
        File.Move(temp, path, overwrite: true);
    }

    private static void TryDelete(string path) { try { if (File.Exists(path)) File.Delete(path); } catch { } }
    private static string NormalizeLineEndings(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
    private static string ResolveExistingDirectory(string path) { var full = Path.GetFullPath(path); if (!Directory.Exists(full)) throw new ContractException($"Directory does not exist: {path}"); return full; }
    private static string Relative(string root, string path) => Path.GetRelativePath(root, path).Replace('\\', '/');
    private static void Require(bool condition, string message) { if (!condition) throw new ContractException(message); }

    public static string ClassifyFailure(Exception ex) => ex switch
    {
        TimeoutException => "timeout",
        Win32Exception => "process_start_failure",
        ContractException ce when ce.Message.Contains("auth", StringComparison.OrdinalIgnoreCase) => "auth_failure",
        ContractException ce when ce.Message.Contains("Unsupported", StringComparison.OrdinalIgnoreCase) => "unsupported",
        ContractException ce when ce.Message.Contains("empty", StringComparison.OrdinalIgnoreCase) => "empty_output",
        ContractException ce when ce.Message.Contains("malformed", StringComparison.OrdinalIgnoreCase) => "malformed_output",
        ContractException ce when ce.Message.Contains("Could not start", StringComparison.OrdinalIgnoreCase) => "process_start_failure",
        ContractException ce when ce.Message.Contains("process start", StringComparison.OrdinalIgnoreCase) => "process_start_failure",
        ContractException ce when ce.Message.Contains("write detected", StringComparison.OrdinalIgnoreCase) => "write_detected",
        _ => "failed"
    };
}

static class WorktreeSnapshot
{
    public static WorktreeState Capture(string repositoryRoot)
    {
        try
        {
            var status = ProcessRunner.RunCapture("git", ["status", "--porcelain"], repositoryRoot, 30);
            var head = ProcessRunner.RunCapture("git", ["rev-parse", "HEAD"], repositoryRoot, 30).Trim();
            var tree = ProcessRunner.RunCapture("git", ["write-tree"], repositoryRoot, 30).Trim();
            return new WorktreeState(head, tree, Normalize(status));
        }
        catch
        {
            // Non-git fixtures still get a best-effort directory fingerprint.
            return new WorktreeState("nogit", DirectoryFingerprint(repositoryRoot), "");
        }
    }

    private static string Normalize(string value) => value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Trim();

    private static string DirectoryFingerprint(string root)
    {
        var sb = new StringBuilder();
        foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
                     .Where(path => !path.Contains($"{Path.DirectorySeparatorChar}.executor-", StringComparison.Ordinal)
                                    && !path.Contains($"{Path.DirectorySeparatorChar}.review{Path.DirectorySeparatorChar}", StringComparison.Ordinal))
                     .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                     .Take(5000))
        {
            var info = new FileInfo(file);
            sb.Append(Path.GetRelativePath(root, file).Replace('\\', '/'));
            sb.Append('\t');
            sb.Append(info.Length);
            sb.Append('\t');
            sb.Append(info.LastWriteTimeUtc.Ticks);
            sb.Append('\n');
        }
        return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString()))).ToLowerInvariant();
    }
}

readonly record struct WorktreeState(string Head, string Tree, string Status)
{
    public bool Equals(WorktreeState other) =>
        string.Equals(Head, other.Head, StringComparison.Ordinal) &&
        string.Equals(Tree, other.Tree, StringComparison.Ordinal) &&
        string.Equals(Status, other.Status, StringComparison.Ordinal);

    public override int GetHashCode() => HashCode.Combine(Head, Tree, Status);

    public string Describe() => $"head={Head};tree={Tree};status={(string.IsNullOrEmpty(Status) ? "<clean>" : Status.Replace('\n', '|'))}";
}

static class ReviewerInputBuilder
{
    public static ReviewerInput Build(
        string repositoryRoot,
        string skillRoot,
        string runRoot,
        string roundRoot,
        string role,
        int round,
        string executionApp,
        string? additionalContextPath)
    {
        var contractPath = ResolveRoleContract(repositoryRoot, role);
        var contract = File.ReadAllText(contractPath);
        string? profilePath = null;
        var profileInstructions = "";
        var reasoningEffort = "high";
        var sandboxMode = "read-only";
        if (executionApp.Equals("codex-exec", StringComparison.OrdinalIgnoreCase))
        {
            profilePath = ResolveRoleProfile(repositoryRoot, role);
            profileInstructions = ReadTomlMultiline(profilePath, "developer_instructions") ?? "";
            reasoningEffort = ReadTomlString(profilePath, "model_reasoning_effort") ?? "high";
            sandboxMode = ReadTomlString(profilePath, "sandbox_mode") ?? "read-only";
        }
        else
        {
            // Copilot path may optionally use a Codex profile when present, but must not require it.
            profilePath = TryResolveRoleProfile(repositoryRoot, role);
            if (profilePath is not null)
            {
                profileInstructions = ReadTomlMultiline(profilePath, "developer_instructions") ?? "";
                reasoningEffort = ReadTomlString(profilePath, "model_reasoning_effort") ?? "high";
            }
        }

        var contextPath = Path.Combine(roundRoot, "review-context.json");
        var patchPath = Path.Combine(roundRoot, "pr-diff.patch");
        var contextJson = File.ReadAllText(contextPath);
        if (string.IsNullOrWhiteSpace(File.ReadAllText(patchPath)))
            throw new ContractException("round pr-diff.patch is empty.");

        var sb = new StringBuilder();
        sb.AppendLine($"You are executing the read-only reviewer role `{role}` through a deterministic process executor.");
        sb.AppendLine("Do not edit production code, tests, review artifacts, GitHub state, commits, or branches.");
        sb.AppendLine("Return only the final review markdown body. Always include the exact line: Production code changed: No");
        sb.AppendLine("Read every referenced artifact file in full. Do not skip unread sections.");
        sb.AppendLine();
        sb.AppendLine("## Role contract");
        sb.AppendLine(contract.Trim());
        sb.AppendLine();
        if (!string.IsNullOrWhiteSpace(profileInstructions))
        {
            sb.AppendLine("## Profile developer instructions");
            sb.AppendLine(profileInstructions.Trim());
            sb.AppendLine();
        }
        sb.AppendLine("## Round identity");
        sb.AppendLine($"- round: {round}");
        sb.AppendLine($"- reviewer_role: {role}");
        sb.AppendLine($"- execution_app: {executionApp}");
        sb.AppendLine($"- repository_root: {repositoryRoot}");
        sb.AppendLine($"- run_root: {runRoot}");
        sb.AppendLine($"- round_root: {roundRoot}");
        sb.AppendLine($"- review_context_path: {contextPath}");
        sb.AppendLine($"- pr_diff_patch_path: {patchPath}");
        sb.AppendLine();
        sb.AppendLine("## review-context.json");
        sb.AppendLine("```json");
        sb.AppendLine(contextJson.Trim());
        sb.AppendLine("```");
        sb.AppendLine();
        sb.AppendLine("## pr-diff.patch");
        sb.AppendLine($"Read the complete patch from file path: {patchPath}");
        sb.AppendLine("The full remote PR diff is authoritative. Do not invent unread hunks.");

        if (role.Equals("purpose-reviewer", StringComparison.OrdinalIgnoreCase))
        {
            var selectionPath = Path.Combine(roundRoot, "goal-context-selection.json");
            var selectionJson = File.ReadAllText(selectionPath);
            sb.AppendLine();
            sb.AppendLine("## goal-context-selection.json");
            sb.AppendLine("```json");
            sb.AppendLine(selectionJson.Trim());
            sb.AppendLine("```");

            var selectedPath = TryReadSelectedPath(selectionJson);
            if (!string.IsNullOrWhiteSpace(selectedPath))
            {
                var goalPath = Path.IsPathRooted(selectedPath)
                    ? selectedPath
                    : Path.GetFullPath(Path.Combine(repositoryRoot, selectedPath));
                if (File.Exists(goalPath))
                {
                    sb.AppendLine();
                    sb.AppendLine("## Selected Goal Context");
                    sb.AppendLine($"path: {goalPath}");
                    sb.AppendLine("```markdown");
                    sb.AppendLine(File.ReadAllText(goalPath).TrimEnd());
                    sb.AppendLine("```");
                }
            }

            var statePath = Path.Combine(runRoot, "run-state.json");
            if (File.Exists(statePath))
            {
                sb.AppendLine();
                sb.AppendLine("## run-state.json");
                sb.AppendLine("```json");
                sb.AppendLine(File.ReadAllText(statePath).Trim());
                sb.AppendLine("```");
            }

            if (round > 1)
            {
                var priorRound = round - 1;
                var priorRaw = Path.Combine(runRoot, $"round-{priorRound:000}", "purpose-reviewer.raw.md");
                if (File.Exists(priorRaw))
                {
                    sb.AppendLine();
                    sb.AppendLine($"## Prior purpose-reviewer raw (round {priorRound:000})");
                    sb.AppendLine($"path: {priorRaw}");
                    sb.AppendLine(File.ReadAllText(priorRaw).TrimEnd());
                }
            }
        }

        if (!string.IsNullOrWhiteSpace(additionalContextPath))
        {
            var full = Path.GetFullPath(additionalContextPath);
            Require(File.Exists(full), $"--additional-context-path does not exist: {additionalContextPath}");
            sb.AppendLine();
            sb.AppendLine("## Additional parent context");
            sb.AppendLine(File.ReadAllText(full).TrimEnd());
        }

        var templatePath = role.Equals("local-reviewer", StringComparison.OrdinalIgnoreCase)
            ? Path.Combine(skillRoot, "..", "pr-review-remediation", "templates", "local-review-findings.md")
            : Path.Combine(skillRoot, "templates", "purpose-review-findings.md");
        templatePath = Path.GetFullPath(templatePath);
        if (File.Exists(templatePath))
        {
            sb.AppendLine();
            sb.AppendLine("## Output template");
            sb.AppendLine(File.ReadAllText(templatePath).TrimEnd());
        }

        return new ReviewerInput(sb.ToString(), reasoningEffort, sandboxMode, contractPath, profilePath, patchPath, contextPath);
    }

    private static string ResolveRoleContract(string repositoryRoot, string role)
    {
        var candidates = new List<string>
        {
            Path.Combine(repositoryRoot, ".github", "agents", $"{role}.agent.md"),
            Path.Combine(repositoryRoot, "apm-packages", "pr-review-remediation", "..", "..", ".github", "agents", $"{role}.agent.md")
        };
        candidates.AddRange(FindApmCanonicalAgents(repositoryRoot, $"{role}.agent.md"));
        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(full)) return full;
        }
        throw new ContractException($"Role contract not found for {role}.");
    }

    private static string ResolveRoleProfile(string repositoryRoot, string role)
        => TryResolveRoleProfile(repositoryRoot, role)
           ?? throw new ContractException($"Role profile not found for {role}.");

    private static string? TryResolveRoleProfile(string repositoryRoot, string role)
    {
        var candidates = new[]
        {
            Path.Combine(repositoryRoot, ".codex", "agents", $"{role}.toml"),
            Path.Combine(repositoryRoot, "apm-packages", "pr-review-remediation", "codex-agents", $"{role}.toml")
        };
        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(full)) return full;
        }
        return null;
    }

    private static IEnumerable<string> FindApmCanonicalAgents(string repositoryRoot, string fileName)
    {
        var modulesRoot = Path.Combine(repositoryRoot, "apm_modules");
        if (!Directory.Exists(modulesRoot)) yield break;
        foreach (var path in Directory.EnumerateFiles(modulesRoot, fileName, SearchOption.AllDirectories))
        {
            var agentsDir = new DirectoryInfo(Path.GetDirectoryName(path)!);
            if (!string.Equals(agentsDir.Name, "agents", StringComparison.OrdinalIgnoreCase)) continue;
            if (agentsDir.Parent is null || !string.Equals(agentsDir.Parent.Name, ".apm", StringComparison.OrdinalIgnoreCase)) continue;
            yield return path;
        }
    }

    private static string? TryReadSelectedPath(string selectionJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(selectionJson);
            if (doc.RootElement.TryGetProperty("selectedPath", out var path) && path.ValueKind == JsonValueKind.String)
                return path.GetString();
            if (doc.RootElement.TryGetProperty("SelectedPath", out path) && path.ValueKind == JsonValueKind.String)
                return path.GetString();
        }
        catch { }
        return null;
    }

    private static string? ReadTomlString(string path, string key)
    {
        if (!File.Exists(path)) return null;
        foreach (var line in File.ReadLines(path))
        {
            var trimmed = line.Trim();
            if (trimmed.StartsWith("#", StringComparison.Ordinal)) continue;
            var prefix = key + " = ";
            if (!trimmed.StartsWith(prefix, StringComparison.Ordinal)) continue;
            var raw = trimmed[prefix.Length..].Trim();
            if (raw.StartsWith('"') && raw.EndsWith('"') && raw.Length >= 2) return raw[1..^1];
            return raw;
        }
        return null;
    }

    private static string? ReadTomlMultiline(string path, string key)
    {
        if (!File.Exists(path)) return null;
        var text = File.ReadAllText(path);
        var marker = key + " = \"\"\"";
        var start = text.IndexOf(marker, StringComparison.Ordinal);
        if (start < 0) return ReadTomlString(path, key);
        start += marker.Length;
        var end = text.IndexOf("\"\"\"", start, StringComparison.Ordinal);
        if (end < 0) return null;
        return text[start..end].Trim();
    }

    private static void Require(bool condition, string message) { if (!condition) throw new ContractException(message); }
}

static class FinalResponseExtractor
{
    private static readonly Regex ProductionNoWrite = new("(?im)^-?\\s*Production code changed:\\s*No\\s*$", RegexOptions.CultureInvariant);

    public static string Extract(AdapterResult invocation, string role)
    {
        var body = invocation.FinalText?.Trim();
        if (string.IsNullOrWhiteSpace(body))
            throw new ContractException("Final answer extraction produced empty output.");
        if (body.Length < 40)
            throw new ContractException("Final answer extraction produced malformed output that is too short to be a review body.");
        if (!ProductionNoWrite.IsMatch(body))
            throw new ContractException("malformed final review body: missing required marker 'Production code changed: No'.");
        if (LooksLikeCliNoise(body))
            throw new ContractException("malformed final review body: output looks like CLI banner/error noise rather than a review.");
        if (role.Equals("local-reviewer", StringComparison.OrdinalIgnoreCase) &&
            !Regex.IsMatch(body, "(?i)local|LR-|No findings|REVIEWED|BLOCKED"))
        {
            throw new ContractException("malformed final review body: local-reviewer contract markers were not found.");
        }
        if (role.Equals("purpose-reviewer", StringComparison.OrdinalIgnoreCase) &&
            !Regex.IsMatch(body, "(?i)purpose|PUR-|No findings|PURPOSE_REVIEWED|HUMAN_DECISION_REQUIRED|BLOCKED"))
        {
            throw new ContractException("malformed final review body: purpose-reviewer contract markers were not found.");
        }
        return body;
    }

    private static bool LooksLikeCliNoise(string body)
    {
        var first = body.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).FirstOrDefault() ?? "";
        return first.StartsWith("Usage:", StringComparison.OrdinalIgnoreCase)
               || first.StartsWith("Error:", StringComparison.OrdinalIgnoreCase)
               || first.Contains("unknown option", StringComparison.OrdinalIgnoreCase);
    }
}

interface IReviewerAdapter
{
    IReadOnlyList<string> Limitations { get; }
    AdapterResult Invoke(AdapterRequest request);
}

sealed class CodexExecAdapter(string executable) : IReviewerAdapter
{
    public IReadOnlyList<string> Limitations { get; } =
    [
        "Uses top-level codex exec rather than native subagent spawn_agent.",
        "Does not inherit parent session settings, child thread UI, or project-scoped custom agent profile selection UI.",
        "Sandbox is requested as read-only; OS-level write impossibility is not proven.",
        "Reviewer prompt is delivered on stdin, not argv."
    ];

    public AdapterResult Invoke(AdapterRequest request)
    {
        var outputPath = Path.Combine(request.WorkDirectory, "codex-final.md");

        const string developerInstructions =
            "Use the reviewer assignment delivered on stdin. Return only the final review markdown. Always include: Production code changed: No. Do not edit files or GitHub state.";

        var arguments = new List<string>
        {
            "exec",
            "--json",
            "--strict-config",
            "--ignore-user-config",
            "-C", request.RepositoryRoot,
            "-m", request.Model,
            "-s", request.Input.SandboxMode,
            "-c", $"model_reasoning_effort=\"{request.Input.ReasoningEffort}\"",
            "-c", "developer_instructions=" + CollapseForConfig(developerInstructions),
            "-o", outputPath
            // Prompt intentionally omitted from argv; delivered via stdin.
        };

        var commandShape = BuildCommandShape(executable, arguments) + " <stdin:prompt>";
        ProcessRunResult processResult;
        try
        {
            processResult = ProcessRunner.Run(
                executable,
                arguments,
                request.RepositoryRoot,
                request.TimeoutSeconds,
                "codex exec",
                stdin: request.Input.Prompt);
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException)
        {
            return AdapterResult.Fail("process_start_failure", "unknown", commandShape,
                $"Could not start codex exec: {ex.Message}",
                ["Process start failure is not interpreted as no findings."]);
        }

        if (processResult.TimedOut)
        {
            return AdapterResult.Fail("timeout", "unknown", commandShape, "codex exec timed out.",
                ["Timeout does not mean no findings."]);
        }

        if (processResult.ExitCode != 0)
        {
            var detail = OneLine(string.IsNullOrWhiteSpace(processResult.StdErr) ? processResult.StdOut : processResult.StdErr);
            var status = detail.Contains("auth", StringComparison.OrdinalIgnoreCase) || detail.Contains("login", StringComparison.OrdinalIgnoreCase)
                ? "auth_failure"
                : "non_zero_exit";
            return AdapterResult.Fail(status, "unknown", commandShape, $"codex exec failed ({processResult.ExitCode}): {detail}",
                ["Non-zero exit is not interpreted as no findings."]);
        }

        var observed = TryObserveCodexModel(processResult.StdOut) ?? "unknown";
        if (!CodexJsonlLooksClean(processResult.StdOut))
        {
            return AdapterResult.Fail("malformed_output", observed, commandShape,
                "codex exec JSONL did not prove a clean completed turn.",
                ["Malformed or incomplete JSONL is not interpreted as no findings."]);
        }

        string finalText;
        if (File.Exists(outputPath) && new FileInfo(outputPath).Length > 0)
            finalText = File.ReadAllText(outputPath);
        else
            finalText = TryExtractCodexAssistantText(processResult.StdOut) ?? "";

        if (string.IsNullOrWhiteSpace(finalText))
        {
            return AdapterResult.Fail("empty_output", observed, commandShape,
                "codex exec completed without extractable final review text.",
                ["Empty output is not interpreted as no findings."]);
        }

        return AdapterResult.Ok(finalText, observed, commandShape, Limitations.ToList());
    }

    private static bool CodexJsonlLooksClean(string stdout)
    {
        var started = false;
        var completed = false;
        var errors = 0;
        foreach (var line in stdout.Split('\n'))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith('{')) continue;
            try
            {
                using var doc = JsonDocument.Parse(trimmed);
                if (!doc.RootElement.TryGetProperty("type", out var typeEl)) continue;
                var type = typeEl.GetString();
                if (type == "thread.started") started = true;
                if (type == "turn.completed") completed = true;
                if (type == "error") errors++;
                if (doc.RootElement.TryGetProperty("item", out var item) &&
                    item.ValueKind == JsonValueKind.Object &&
                    item.TryGetProperty("type", out var itemType) &&
                    itemType.GetString() == "error")
                {
                    errors++;
                }
            }
            catch { }
        }
        return started && completed && errors == 0;
    }

    private static string? TryObserveCodexModel(string stdout)
    {
        foreach (var line in stdout.Split('\n'))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith('{')) continue;
            try
            {
                using var doc = JsonDocument.Parse(trimmed);
                if (doc.RootElement.TryGetProperty("model", out var model) && model.ValueKind == JsonValueKind.String)
                    return model.GetString();
                if (doc.RootElement.TryGetProperty("thread", out var thread) &&
                    thread.ValueKind == JsonValueKind.Object &&
                    thread.TryGetProperty("model", out model) &&
                    model.ValueKind == JsonValueKind.String)
                {
                    return model.GetString();
                }
            }
            catch { }
        }
        return null;
    }

    private static string? TryExtractCodexAssistantText(string stdout)
    {
        string? last = null;
        foreach (var line in stdout.Split('\n'))
        {
            var trimmed = line.Trim();
            if (!trimmed.StartsWith('{')) continue;
            try
            {
                using var doc = JsonDocument.Parse(trimmed);
                if (doc.RootElement.TryGetProperty("item", out var item) &&
                    item.ValueKind == JsonValueKind.Object &&
                    item.TryGetProperty("type", out var type) &&
                    type.GetString() is "agent_message" or "message")
                {
                    if (item.TryGetProperty("text", out var text) && text.ValueKind == JsonValueKind.String)
                        last = text.GetString();
                }
            }
            catch { }
        }
        return last;
    }

    private static string CollapseForConfig(string value)
    {
        var oneLine = Regex.Replace(value, "\\s+", " ").Trim();
        if (oneLine.Length > 4000) oneLine = oneLine[..4000];
        return oneLine.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);
    }

    private static string BuildCommandShape(string executable, IReadOnlyList<string> arguments)
    {
        var parts = new List<string> { executable };
        foreach (var arg in arguments)
        {
            if (arg.StartsWith("developer_instructions=", StringComparison.Ordinal)) { parts.Add("developer_instructions=<redacted>"); continue; }
            parts.Add(arg.Contains(' ', StringComparison.Ordinal) ? $"\"{arg}\"" : arg);
        }
        return string.Join(' ', parts);
    }

    private static string OneLine(string value) => Regex.Replace(value, "\\s+", " ").Trim();
}

sealed class CopilotCliAdapter(string executable) : IReviewerAdapter
{
    // Keep the available tool set intentionally narrow and read-oriented.
    private static readonly string[] ReadOnlyTools =
    [
        "view",
        "grep",
        "glob",
        "read_file",
        "list_dir",
        "search_codebase"
    ];

    public IReadOnlyList<string> Limitations { get; } =
    [
        "Uses GitHub Copilot CLI non-interactive -p/--prompt mode rather than VS Code UI.",
        "Read-only intent is requested via --available-tools allowlist, denied write/shell/git mutations, disabled built-in MCPs, and pre/post worktree comparison.",
        "OS-level write impossibility is not proven; observed writes fail closed.",
        "Observed model may remain unknown when the CLI does not echo the selected model.",
        "Reviewer prompt is delivered via short -p plus prompt file under --add-dir, not full argv payload.",
        "Does not share Codex native subagent identity or parent conversation history isolation guarantees."
    ];

    public AdapterResult Invoke(AdapterRequest request)
    {
        var promptPath = Path.Combine(request.WorkDirectory, "prompt.md");
        File.WriteAllText(promptPath, request.Input.Prompt, new UTF8Encoding(false));
        var promptArg =
            $"Read the reviewer assignment at '{promptPath}' and the referenced artifact files (especially the full pr-diff.patch). Produce only the final review markdown body. Always include: Production code changed: No. Do not edit files or GitHub state.";

        var arguments = new List<string>
        {
            "-p", promptArg,
            "--model", request.Model,
            "-C", request.RepositoryRoot,
            "-s",
            "--output-format", "text",
            "--no-ask-user",
            "--no-custom-instructions",
            "--disable-builtin-mcps",
            "--add-dir", request.WorkDirectory,
            "--available-tools", string.Join(',', ReadOnlyTools),
            "--deny-tool", "write",
            "--deny-tool", "shell",
            "--deny-tool", "task",
            "--deny-tool", "memory",
            "--deny-tool", "shell(git)",
            "--deny-url", "*"
        };

        var commandShape = BuildCommandShape(executable, arguments);
        ProcessRunResult processResult;
        try
        {
            processResult = ProcessRunner.Run(executable, arguments, request.RepositoryRoot, request.TimeoutSeconds, "copilot cli");
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException)
        {
            return AdapterResult.Fail("process_start_failure", "unknown", commandShape,
                $"Could not start GitHub Copilot CLI: {ex.Message}",
                ["Process start failure is not interpreted as no findings."]);
        }

        if (processResult.TimedOut)
        {
            return AdapterResult.Fail("timeout", "unknown", commandShape, "GitHub Copilot CLI timed out.",
                ["Timeout does not mean no findings."]);
        }

        if (processResult.ExitCode != 0)
        {
            var detail = OneLine(string.IsNullOrWhiteSpace(processResult.StdErr) ? processResult.StdOut : processResult.StdErr);
            var status = detail.Contains("auth", StringComparison.OrdinalIgnoreCase) ||
                         detail.Contains("login", StringComparison.OrdinalIgnoreCase) ||
                         detail.Contains("not authenticated", StringComparison.OrdinalIgnoreCase)
                ? "auth_failure"
                : "non_zero_exit";
            return AdapterResult.Fail(status, "unknown", commandShape, $"GitHub Copilot CLI failed ({processResult.ExitCode}): {detail}",
                ["Non-zero exit is not interpreted as no findings."]);
        }

        var finalText = processResult.StdOut.Trim();
        if (string.IsNullOrWhiteSpace(finalText))
        {
            return AdapterResult.Fail("empty_output", "unknown", commandShape,
                "GitHub Copilot CLI completed without extractable final review text.",
                ["Empty output is not interpreted as no findings."]);
        }

        return AdapterResult.Ok(finalText, "unknown", commandShape, Limitations.ToList());
    }

    private static string BuildCommandShape(string executable, IReadOnlyList<string> arguments)
    {
        var parts = new List<string> { executable };
        for (var i = 0; i < arguments.Count; i++)
        {
            var arg = arguments[i];
            if (arg is "-p" or "--prompt")
            {
                parts.Add(arg);
                if (i + 1 < arguments.Count) { parts.Add("<short-prompt-ref>"); i++; }
                continue;
            }
            parts.Add(arg.Contains(' ', StringComparison.Ordinal) ? $"\"{arg}\"" : arg);
        }
        return string.Join(' ', parts);
    }

    private static string OneLine(string value) => Regex.Replace(value, "\\s+", " ").Trim();
}

static class ProcessRunner
{
    public static string RunCapture(string executable, IReadOnlyList<string> arguments, string workingDirectory, int timeoutSeconds)
    {
        var result = Run(executable, arguments, workingDirectory, timeoutSeconds, executable);
        if (result.TimedOut) throw new TimeoutException($"{executable} timed out.");
        if (result.ExitCode != 0) throw new ContractException($"{executable} failed: {result.StdErr}");
        return result.StdOut;
    }

    public static ProcessRunResult Run(
        string executable,
        IReadOnlyList<string> arguments,
        string workingDirectory,
        int timeoutSeconds,
        string description,
        string? stdin = null)
    {
        var start = new ProcessStartInfo(executable)
        {
            WorkingDirectory = workingDirectory,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = stdin is not null,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            CreateNoWindow = true
        };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);

        Process process;
        try
        {
            process = Process.Start(start) ?? throw new ContractException($"Could not start {description}.");
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException)
        {
            throw new ContractException($"Could not start {description}: {ex.Message}");
        }

        using (process)
        {
            // Start stdout/stderr async reads immediately so pipe buffers drain
            // even while stdin is being written or the child is not consuming.
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();

            // Write stdin asynchronously to avoid blocking the parent when
            // the child pipe buffer is full. Stdin, stdout/stderr, and exit
            // all share the same timeout boundary below.
            Task? stdinTask = null;
            if (stdin is not null)
            {
                stdinTask = Task.Run(async () =>
                {
                    try
                    {
                        await process.StandardInput.WriteAsync(stdin).ConfigureAwait(false);
                        process.StandardInput.Close();
                    }
                    catch
                    {
                        try { process.StandardInput.Close(); } catch { }
                    }
                });
            }

            var exited = process.WaitForExit(timeoutSeconds * 1000);
            if (!exited)
            {
                // Close stdin first to unblock any pending async writer, then kill the tree.
                if (stdin is not null) { try { process.StandardInput.Close(); } catch { } }
                try { process.Kill(entireProcessTree: true); } catch { }
                try { process.WaitForExit(5000); } catch { }
                // Drain stdout/stderr with a short grace period.
                try { Task.WaitAll(new[] { stdoutTask, stderrTask }, 5000); } catch { }
                return new ProcessRunResult(-1,
                    stdoutTask.Status == TaskStatus.RanToCompletion ? stdoutTask.Result : "",
                    stderrTask.Status == TaskStatus.RanToCompletion ? stderrTask.Result : "",
                    TimedOut: true);
            }

            Task.WaitAll(stdoutTask, stderrTask);
            return new ProcessRunResult(process.ExitCode, stdoutTask.Result, stderrTask.Result, TimedOut: false);
        }
    }
}

sealed class Options
{
    public string? ExecutionApp { get; private set; }
    public string? Model { get; private set; }
    public string? ReviewerRole { get; private set; }
    public string? RunRoot { get; private set; }
    public int Round { get; private set; }
    public int TimeoutSeconds { get; private set; } = 600;
    public string? RepositoryRoot { get; private set; }
    public string? SkillRoot { get; private set; }
    public string? CodexExecutable { get; private set; }
    public string? CopilotExecutable { get; private set; }
    public string? AdditionalContextPath { get; private set; }
    public string Format { get; private set; } = "json";
    public bool Help { get; private set; }

    public static Options Parse(string[] args)
    {
        var o = new Options();
        if (args.Length == 0) { o.Help = true; return o; }
        for (var i = 0; i < args.Length; i++)
        {
            string Next() => ++i < args.Length ? args[i] : throw new ContractException($"Missing value after {args[i - 1]}.");
            switch (args[i])
            {
                case "--help":
                case "-h":
                    o.Help = true;
                    break;
                case "--execution-app":
                    o.ExecutionApp = Next();
                    break;
                case "--model":
                    o.Model = Next();
                    break;
                case "--reviewer-role":
                    o.ReviewerRole = Next();
                    break;
                case "--run-root":
                    o.RunRoot = Next();
                    break;
                case "--round":
                    o.Round = int.TryParse(Next(), out var round) ? round : 0;
                    break;
                case "--timeout-seconds":
                    o.TimeoutSeconds = int.TryParse(Next(), out var timeout) && timeout > 0
                        ? timeout
                        : throw new ContractException("--timeout-seconds must be positive.");
                    break;
                case "--repository-root":
                    o.RepositoryRoot = Next();
                    break;
                case "--skill-root":
                    o.SkillRoot = Next();
                    break;
                case "--codex-executable":
                    o.CodexExecutable = Next();
                    break;
                case "--copilot-executable":
                    o.CopilotExecutable = Next();
                    break;
                case "--additional-context-path":
                    o.AdditionalContextPath = Next();
                    break;
                case "--format":
                    o.Format = Next();
                    break;
                case "--command":
                    throw new ContractException("Arbitrary raw command configuration is not allowed.");
                default:
                    throw new ContractException($"Unknown argument: {args[i]}");
            }
        }
        if (o.Format is not ("text" or "json")) throw new ContractException("--format must be text or json.");
        return o;
    }
}

static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };
}

sealed record ReviewerInput(
    string Prompt,
    string ReasoningEffort,
    string SandboxMode,
    string ContractPath,
    string? ProfilePath,
    string PatchPath,
    string ContextPath);
sealed record AdapterRequest(string RepositoryRoot, string WorkDirectory, string Model, string Role, ReviewerInput Input, int TimeoutSeconds);
sealed record ProcessRunResult(int ExitCode, string StdOut, string StdErr, bool TimedOut);

sealed class AdapterResult
{
    public string ExitStatus { get; init; } = "";
    public string ObservedModel { get; init; } = "unknown";
    public string? FinalText { get; init; }
    public string CommandShape { get; init; } = "";
    public string? Error { get; init; }
    public List<string> Limitations { get; init; } = [];

    public static AdapterResult Ok(string finalText, string observedModel, string commandShape, List<string> limitations) => new()
    {
        ExitStatus = "succeeded",
        ObservedModel = observedModel,
        FinalText = finalText,
        CommandShape = commandShape,
        Limitations = limitations
    };

    public static AdapterResult Fail(string status, string observedModel, string commandShape, string error, List<string> limitations) => new()
    {
        ExitStatus = status,
        ObservedModel = observedModel,
        CommandShape = commandShape,
        Error = error,
        Limitations = limitations
    };
}

sealed class ExecutionResult
{
    public string ExecutionApp { get; init; } = "";
    public string RequestedModel { get; init; } = "";
    public string ObservedModel { get; init; } = "unknown";
    public string ReviewerRole { get; init; } = "";
    public DateTimeOffset StartedAt { get; init; }
    public DateTimeOffset CompletedAt { get; init; }
    public string ExitStatus { get; init; } = "";
    public string? RawOutputPath { get; init; }
    public string? MetadataPath { get; init; }
    public string? Error { get; init; }
    public List<string> Limitations { get; init; } = [];
    public string? CommandShape { get; init; }

    public static ExecutionResult Failed(
        string app,
        string model,
        string role,
        string status,
        string error,
        List<string>? limitations = null) => new()
    {
        ExecutionApp = app,
        RequestedModel = model,
        ObservedModel = "unknown",
        ReviewerRole = role,
        StartedAt = DateTimeOffset.UtcNow,
        CompletedAt = DateTimeOffset.UtcNow,
        ExitStatus = status,
        Error = error,
        Limitations = limitations ?? []
    };
}

sealed class ContractException(string message) : Exception(message);
