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

    protected static async Task VerifyCliVersionAsync(
        ProviderRequest request,
        IProcessRunner runner,
        string provider,
        string version,
        CancellationToken cancellationToken)
    {
        var output = await RunCheckedAsync(
            new(request.Provider.Executable, ["--version"], request.RunDirectory, null),
            runner,
            cancellationToken);
        var versionText = output.StandardOutput + Environment.NewLine + output.StandardError;
        var expectedVersionLine = $"{provider} {version}";
        if (!versionText.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Any(line => line.Equals(expectedVersionLine, StringComparison.Ordinal) || line.Equals(expectedVersionLine + ".", StringComparison.Ordinal)))
        {
            throw new RunnerException("PROVIDER_VERSION_UNSUPPORTED", $"Only {provider} {version} has a verified isolated tool configuration.");
        }
    }
}

public sealed class CodexProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    public Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken) =>
        throw new RunnerException(
            "PROVIDER_RESTRICTION_UNSUPPORTED",
            "Codex host collaboration tools remained callable after disabling multi-agent features and removing the host routing environment variables. This provider is disabled until the host tool bridge can be suppressed.",
            ExitCodes.ContractError);
}

public sealed class CopilotProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    private const string VerifiedVersion = "1.0.105";
    private const string NoToolSentinel = "report_intent";
    private static readonly IReadOnlyDictionary<string, string?> IsolatedEnvironment =
        new Dictionary<string, string?>(StringComparer.Ordinal) { ["COPILOT_PLUGIN_DIR_ONLY"] = "true" };

    public async Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken)
    {
        ValidateProviderConfiguration(request, "copilot");
        await VerifyCliVersionAsync(request, processRunner, "GitHub Copilot CLI", VerifiedVersion, cancellationToken);
        var mcpServers = await ReadConfiguredMcpServersAsync(request, processRunner, cancellationToken);
        var session = request.SessionHandle ?? Guid.NewGuid().ToString("D");
        var arguments = new List<string>
        {
            "-C", request.RunDirectory, "--no-custom-instructions", "--no-remote-export",
            "--no-auto-update", "--no-ask-user", "--disable-builtin-mcps", "--disallow-temp-dir",
            "--no-color", "--silent", "--output-format", "json", "--stream", "off",
            "--model", request.Provider.Model, "--reasoning-effort", request.Provider.ReasoningEffort,
            // 空引数は全tool許可へ戻るため、未知のtool名だけを許可する。1.0.105実機でshell呼出し不可を確認済み。
            $"--available-tools={NoToolSentinel}", "--deny-tool=shell", "--deny-tool=write", "--deny-tool=task", "--deny-tool=edit"
        };
        foreach (var server in mcpServers)
        {
            arguments.Add($"--disable-mcp-server={server}");
        }
        arguments.Add(request.SessionHandle is null ? $"--session-id={session}" : $"--resume={session}");

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

    private static async Task<IReadOnlyList<string>> ReadConfiguredMcpServersAsync(
        ProviderRequest request,
        IProcessRunner processRunner,
        CancellationToken cancellationToken)
    {
        var result = await RunCheckedAsync(
            new(request.Provider.Executable, ["mcp", "list", "--json"], request.RunDirectory, null, IsolatedEnvironment),
            processRunner,
            cancellationToken);
        try
        {
            using var document = JsonDocument.Parse(result.StandardOutput);
            if (!document.RootElement.TryGetProperty("mcpServers", out var servers) || servers.ValueKind != JsonValueKind.Object)
            {
                throw new JsonException("mcpServers must be an object.");
            }
            var names = new List<string>();
            foreach (var server in servers.EnumerateObject())
            {
                if (string.IsNullOrWhiteSpace(server.Name) || server.Name.Any(char.IsControl))
                {
                    throw new JsonException("An MCP server name was empty or contained a control character.");
                }
                names.Add(server.Name);
            }
            return names;
        }
        catch (JsonException exception)
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException("PROVIDER_RESTRICTION_UNSUPPORTED", "Copilot MCP configuration could not be enumerated safely.", ExitCodes.ContractError, exception);
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
