using System.Diagnostics;
using System.Text.Json;

namespace PurposeReviewRunner;

public sealed record ProviderRequest(
    ProviderSnapshot Provider,
    string Repository,
    string RunDirectory,
    string Payload,
    string? SessionHandle,
    int Round);

public sealed record ProviderResult(string SessionHandle, string ReviewText);

public interface IProviderAdapter
{
    Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken);
}

public static class ProviderFactory
{
    public static IProviderAdapter Create(string provider) => provider switch
    {
        "codex" => new CodexProviderAdapter(),
        "copilot" => new CopilotProviderAdapter(),
        _ => throw new RunnerException("CONFIG_INVALID", $"Unsupported provider: {provider}")
    };
}

public abstract class ProviderAdapterBase
{
    protected static readonly TimeSpan DiscoveryTimeout = TimeSpan.FromSeconds(15);

    protected static async Task<ProcessResult> RunCheckedAsync(ProcessRequest request, IProcessRunner runner, CancellationToken cancellationToken)
    {
        var result = await runner.RunAsync(request, cancellationToken);
        if (result.TimedOut)
        {
            throw new RunnerException("PROVIDER_TIMEOUT", "Provider process timed out.", ExitCodes.RuntimeError);
        }
        if (result.ExitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(result.StandardError))
            {
                Trace.TraceError($"Provider process stderr:{Environment.NewLine}{result.StandardError.TrimEnd()}");
            }
            throw new RunnerException("PROVIDER_FAILED", $"Provider process exited with code {result.ExitCode}.", ExitCodes.RuntimeError);
        }
        return result;
    }

    // 事前capability discoveryはbest-effortで実行し、非0終了・例外・timeout時はトレースへ記録して残りのguardrailで続行する。
    protected static async Task<ProcessResult?> TryRunDiscoveryAsync(ProcessRequest request, IProcessRunner runner, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var discoveryCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        discoveryCts.CancelAfter(DiscoveryTimeout);
        try
        {
            var result = await runner.RunAsync(request, discoveryCts.Token);
            if (result.TimedOut)
            {
                Trace.TraceError($"Provider capability discovery timed out: {request.Executable} {string.Join(' ', request.Arguments)}");
                return null;
            }
            if (result.ExitCode != 0)
            {
                Trace.TraceError($"Provider capability discovery exited with code {result.ExitCode}: {result.StandardError.TrimEnd()}");
                return null;
            }
            return result;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return null;
        }
    }

    protected static bool IsOptionSupported(IReadOnlySet<string>? supportedOptions, string option) =>
        supportedOptions is null || supportedOptions.Contains(option);

    protected static void DeleteTemporary(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
        }
    }

    protected static void ValidateProviderConfiguration(ProviderRequest request, string provider)
    {
        if (request.Provider.Provider != provider || request.Provider.Profile is not null)
        {
            throw new RunnerException("CONFIG_INVALID", $"Only the verified {provider} configuration without a profile is supported.");
        }
        if (string.IsNullOrWhiteSpace(request.Provider.Model) || string.IsNullOrWhiteSpace(request.Provider.ReasoningEffort))
        {
            throw new RunnerException("CONFIG_INVALID", $"The verified {provider} model and reasoning effort are required.");
        }
    }
}

public sealed class CodexProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    // 実機検証済みの基準CLI版（runtime hard-fail gateではなく記録・診断用メタデータとして保持する）。
    public const string LastQualifiedVersion = "0.165.0";

    private static readonly string[] DisabledFeatures =
    [
        "shell_tool", "browser_use", "browser_use_external", "browser_use_full_cdp_access", "standalone_web_search",
        "apps", "mcp_2026_07_28", "multi_agent", "multi_agent_v2", "code_mode", "code_mode_host",
        "image_generation", "view_image", "computer_use", "in_app_browser", "skill_search", "plugins", "hooks", "memories"
    ];

    public static IReadOnlyList<string> TargetDisabledFeatures => DisabledFeatures;

    public async Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken)
    {
        ValidateProviderConfiguration(request, "codex");
        Directory.CreateDirectory(request.RunDirectory);
        var disabledFeatures = await DiscoverDisabledFeaturesAsync(request, processRunner, cancellationToken);

        var responsePath = Path.Combine(request.RunDirectory, $"codex-response-{request.Round}-{Guid.NewGuid():N}.md");
        try
        {
            var arguments = request.SessionHandle is null
                ? BuildInitialArguments(request, responsePath, disabledFeatures)
                : BuildResumeArguments(request, responsePath, disabledFeatures);
            var process = await RunCheckedAsync(
                new(request.Provider.Executable, arguments, request.RunDirectory, request.Payload),
                processRunner,
                cancellationToken);
            if (!File.Exists(responsePath))
            {
                throw new RunnerException("REVIEW_OUTPUT_MISSING", "Codex did not create the final response file.", ExitCodes.ContractError);
            }
            var reviewText = await File.ReadAllTextAsync(responsePath, cancellationToken);
            if (string.IsNullOrWhiteSpace(reviewText))
            {
                throw new RunnerException("REVIEW_OUTPUT_MISSING", "Codex created an empty final response file.", ExitCodes.ContractError);
            }

            var observedSession = ParseCodexSession(process.StandardOutput);
            if (observedSession is null)
            {
                throw new RunnerException("SESSION_NOT_FOUND", "Codex output did not contain a session identity.", ExitCodes.ContractError);
            }
            if (request.SessionHandle is not null && observedSession != request.SessionHandle)
            {
                throw new RunnerException("SESSION_MISMATCH", "Codex resumed a different session.", ExitCodes.ContractError);
            }
            return new(request.SessionHandle ?? observedSession, reviewText);
        }
        finally
        {
            DeleteTemporary(responsePath);
        }
    }

    public static IReadOnlyList<string> BuildInitialArguments(
        ProviderRequest request,
        string responsePath,
        IEnumerable<string> disabledFeatures,
        IReadOnlySet<string>? supportedOptions = null)
    {
        var arguments = new List<string>
        {
            "exec", "--json", "--color", "never"
        };
        AddOptionalFlags(arguments, supportedOptions, "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check");
        if (IsOptionSupported(supportedOptions, "--sandbox"))
        {
            arguments.Add("--sandbox");
            arguments.Add("read-only");
        }
        arguments.AddRange(
        [
            "-C", request.RunDirectory,
            "--model", request.Provider.Model,
            "--config", "approval_policy=\"never\"",
            "--config", $"model_reasoning_effort=\"{request.Provider.ReasoningEffort}\"",
            "--output-last-message", responsePath
        ]);
        if (IsOptionSupported(supportedOptions, "--disable"))
        {
            AddDisabledFeatures(arguments, disabledFeatures);
        }
        arguments.Add("-");
        return arguments;
    }

    public static IReadOnlyList<string> BuildResumeArguments(
        ProviderRequest request,
        string responsePath,
        IEnumerable<string> disabledFeatures,
        IReadOnlySet<string>? supportedOptions = null)
    {
        var arguments = new List<string>
        {
            "exec", "resume", request.SessionHandle!, "--json"
        };
        AddOptionalFlags(arguments, supportedOptions, "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check");
        arguments.AddRange(
        [
            "--model", request.Provider.Model,
            "--config", "sandbox_mode=\"read-only\"",
            "--config", "approval_policy=\"never\"",
            "--config", $"model_reasoning_effort=\"{request.Provider.ReasoningEffort}\"",
            "--output-last-message", responsePath
        ]);
        if (IsOptionSupported(supportedOptions, "--disable"))
        {
            AddDisabledFeatures(arguments, disabledFeatures);
        }
        arguments.Add("-");
        return arguments;
    }

    private static void AddOptionalFlags(List<string> arguments, IReadOnlySet<string>? supportedOptions, params string[] flags)
    {
        foreach (var flag in flags)
        {
            if (IsOptionSupported(supportedOptions, flag))
            {
                arguments.Add(flag);
            }
        }
    }

    private static void AddDisabledFeatures(List<string> arguments, IEnumerable<string> disabledFeatures)
    {
        foreach (var feature in disabledFeatures)
        {
            arguments.Add("--disable");
            arguments.Add(feature);
        }
    }

    private static async Task<IReadOnlyList<string>> DiscoverDisabledFeaturesAsync(
        ProviderRequest request,
        IProcessRunner processRunner,
        CancellationToken cancellationToken)
    {
        var result = await TryRunDiscoveryAsync(
            new(request.Provider.Executable, ["features", "list"], request.RunDirectory, null),
            processRunner,
            cancellationToken);
        if (result is null)
        {
            return [];
        }

        var available = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in result.StandardOutput.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var tokens = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (tokens.Length >= 3 && (tokens[^1] == "true" || tokens[^1] == "false"))
            {
                available.Add(tokens[0]);
            }
        }

        if (available.Count == 0)
        {
            Trace.TraceError("Codex features list output did not contain any recognized feature rows; continuing without --disable flags.");
            return [];
        }

        return DisabledFeatures.Where(available.Contains).ToArray();
    }

    private static string? ParseCodexSession(string stdout)
    {
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var line in stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            try
            {
                using var document = JsonDocument.Parse(line);
                if (document.RootElement.TryGetProperty("thread_id", out var property) && property.ValueKind == JsonValueKind.String)
                {
                    ids.Add(property.GetString()!);
                }
            }
            catch (JsonException exception)
            {
                Trace.TraceError(exception.ToString());
            }
        }
        if (ids.Count > 1)
        {
            throw new RunnerException("SESSION_MISMATCH", "Codex emitted multiple session identities.", ExitCodes.ContractError);
        }
        return ids.SingleOrDefault();
    }
}

public sealed class CopilotProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    // 実機検証済みの基準CLI版（runtime hard-fail gateではなく記録・診断用メタデータとして保持する）。
    public const string LastQualifiedVersion = "1.0.105";

    private const string NoToolSentinel = "report_intent";
    private static readonly IReadOnlyDictionary<string, string?> IsolatedEnvironment =
        new Dictionary<string, string?>(StringComparer.Ordinal) { ["COPILOT_PLUGIN_DIR_ONLY"] = "true" };

    public async Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken)
    {
        ValidateProviderConfiguration(request, "copilot");
        var mcpServers = await DiscoverConfiguredMcpServersAsync(request, processRunner, cancellationToken);
        var session = request.SessionHandle ?? Guid.NewGuid().ToString("D");
        var arguments = BuildArguments(request, session, mcpServers);

        var process = await RunCheckedAsync(
            new(request.Provider.Executable, arguments, request.RunDirectory, request.Payload, IsolatedEnvironment),
            processRunner,
            cancellationToken);
        var parsed = ParseCopilot(process.StandardOutput);
        if (parsed.SessionIds.Count != 1 || parsed.SessionIds[0] != session)
        {
            throw new RunnerException("SESSION_MISMATCH", "Copilot did not confirm the requested session identity.", ExitCodes.ContractError);
        }
        return new(session, parsed.ReviewText);
    }

    public static IReadOnlyList<string> BuildArguments(
        ProviderRequest request,
        string session,
        IEnumerable<string> mcpServers,
        IReadOnlySet<string>? supportedOptions = null)
    {
        var arguments = new List<string> { "-C", request.RunDirectory };
        foreach (var flag in new[]
        {
            "--no-custom-instructions",
            "--no-remote-export",
            "--no-auto-update",
            "--no-ask-user",
            "--disable-builtin-mcps",
            "--disallow-temp-dir",
            "--no-color",
            "--silent"
        })
        {
            if (IsOptionSupported(supportedOptions, flag))
            {
                arguments.Add(flag);
            }
        }
        arguments.AddRange(
        [
            "--output-format", "json", "--stream", "off",
            "--model", request.Provider.Model, "--reasoning-effort", request.Provider.ReasoningEffort
        ]);
        if (IsOptionSupported(supportedOptions, "--available-tools"))
        {
            // 空引数は全tool許可へ戻るため、未知のtool名だけを許可する。1.0.105実機でshell呼出し不可を確認済み。
            arguments.Add($"--available-tools={NoToolSentinel}");
        }
        if (IsOptionSupported(supportedOptions, "--deny-tool"))
        {
            arguments.AddRange(["--deny-tool=shell", "--deny-tool=write", "--deny-tool=task", "--deny-tool=edit"]);
        }
        if (IsOptionSupported(supportedOptions, "--disable-mcp-server"))
        {
            foreach (var server in mcpServers)
            {
                arguments.Add($"--disable-mcp-server={server}");
            }
        }
        arguments.Add(request.SessionHandle is null ? $"--session-id={session}" : $"--resume={session}");
        return arguments;
    }

    private static async Task<IReadOnlyList<string>> DiscoverConfiguredMcpServersAsync(
        ProviderRequest request,
        IProcessRunner processRunner,
        CancellationToken cancellationToken)
    {
        var result = await TryRunDiscoveryAsync(
            new(request.Provider.Executable, ["mcp", "list", "--json"], request.RunDirectory, null, IsolatedEnvironment),
            processRunner,
            cancellationToken);
        if (result is null)
        {
            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (!document.RootElement.TryGetProperty("mcpServers", out var servers) || servers.ValueKind != JsonValueKind.Object)
            {
                Trace.TraceError("Copilot mcp list output did not contain an mcpServers object; continuing without per-server MCP disable flags.");
                return [];
            }
            var names = new List<string>();
            foreach (var server in servers.EnumerateObject())
            {
                if (string.IsNullOrWhiteSpace(server.Name) || server.Name.Any(char.IsControl))
                {
                    Trace.TraceError("Skipped an invalid Copilot MCP server name that was empty or contained a control character.");
                    continue;
                }
                names.Add(server.Name);
            }
            return names;
        }
        catch (JsonException exception)
        {
            Trace.TraceError(exception.ToString());
            return [];
        }
    }

    private static (IReadOnlyList<string> SessionIds, string ReviewText) ParseCopilot(string stdout)
    {
        var sessions = new HashSet<string>(StringComparer.Ordinal);
        string? reviewText = null;
        foreach (var line in stdout.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                var type = root.TryGetProperty("type", out var typeProperty) ? typeProperty.GetString() : null;
                if (type == "assistant.message" && root.TryGetProperty("data", out var messageData) &&
                    messageData.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.String)
                {
                    reviewText = content.GetString();
                }
                if (type == "result")
                {
                    if (root.TryGetProperty("sessionId", out var directSession) && directSession.ValueKind == JsonValueKind.String)
                    {
                        sessions.Add(directSession.GetString()!);
                    }
                    if (root.TryGetProperty("data", out var data) && data.TryGetProperty("sessionId", out var nestedSession) && nestedSession.ValueKind == JsonValueKind.String)
                    {
                        sessions.Add(nestedSession.GetString()!);
                    }
                }
            }
            catch (JsonException exception)
            {
                Trace.TraceError(exception.ToString());
            }
        }
        if (string.IsNullOrWhiteSpace(reviewText))
        {
            throw new RunnerException("REVIEW_OUTPUT_MISSING", "Copilot output did not contain an assistant message.", ExitCodes.ContractError);
        }
        return (sessions.ToArray(), reviewText);
    }
}
