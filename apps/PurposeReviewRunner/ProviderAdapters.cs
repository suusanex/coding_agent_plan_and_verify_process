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
        "grok" => new GrokProviderAdapter(),
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

    protected static string WritePayload(ProviderRequest request)
    {
        Directory.CreateDirectory(request.RunDirectory);
        var path = Path.Combine(request.RunDirectory, $"payload-{request.Round}-{Guid.NewGuid():N}.md");
        File.WriteAllText(path, request.Payload, new System.Text.UTF8Encoding(false));
        return path;
    }

    protected static void DeleteTemporary(string? path)
    {
        if (path is null || !File.Exists(path))
        {
            return;
        }
        try
        {
            File.Delete(path);
        }
        catch (Exception exception)
        {
            System.Diagnostics.Trace.TraceError(exception.ToString());
        }
    }
}

public sealed class CodexProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    public async Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken)
    {
        var responsePath = Path.Combine(request.RunDirectory, $"response-{request.Round}-{Guid.NewGuid():N}.md");
        try
        {
            var arguments = request.SessionHandle is null
                ? NewArguments(request, responsePath)
                : ResumeArguments(request, responsePath);
            var process = await RunCheckedAsync(
                new(request.Provider.Executable, arguments, request.Repository, request.Payload),
                processRunner,
                cancellationToken);
            if (!File.Exists(responsePath))
            {
                throw new RunnerException("REVIEW_OUTPUT_MISSING", "Codex did not create the final response file.", ExitCodes.ContractError);
            }
            var reviewText = File.ReadAllText(responsePath);
            var observedSession = ParseCodexSession(process.StandardOutput);
            if (request.SessionHandle is null && observedSession is null)
            {
                throw new RunnerException("SESSION_NOT_FOUND", "Codex output did not contain a session identity.", ExitCodes.ContractError);
            }
            if (request.SessionHandle is not null && observedSession is not null && observedSession != request.SessionHandle)
            {
                throw new RunnerException("SESSION_MISMATCH", "Codex resumed a different session.", ExitCodes.ContractError);
            }
            return new(request.SessionHandle ?? observedSession!, reviewText);
        }
        finally
        {
            DeleteTemporary(responsePath);
        }
    }

    private static IReadOnlyList<string> NewArguments(ProviderRequest request, string responsePath)
    {
        var arguments = new List<string>
        {
            "exec", "--json", "--color", "never", "--ignore-user-config", "--ignore-rules",
            "-C", request.Repository, "-m", request.Provider.Model,
            "-c", $"model_reasoning_effort=\"{request.Provider.ReasoningEffort}\"", "-o", responsePath, "-"
        };
        if (!string.IsNullOrWhiteSpace(request.Provider.Profile))
        {
            arguments.InsertRange(6, ["-p", request.Provider.Profile]);
        }
        return arguments;
    }

    private static IReadOnlyList<string> ResumeArguments(ProviderRequest request, string responsePath) =>
        [
            "exec", "resume", request.SessionHandle!, "--json", "--ignore-user-config", "--ignore-rules",
            "-m", request.Provider.Model,
            "-c", $"model_reasoning_effort=\"{request.Provider.ReasoningEffort}\"",
            "-o", responsePath, "-"
        ];

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

public sealed class GrokProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    public async Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken)
    {
        var payloadPath = WritePayload(request);
        var session = request.SessionHandle ?? Guid.NewGuid().ToString("D");
        try
        {
            var arguments = new List<string>
            {
                "--cwd", request.Repository, "--no-memory", "--no-subagents", "--permission-mode", "plan",
                "--disable-web-search", "--tools", "read,view,grep",
                "--disallowed-tools", "write,shell,task,edit_file,run_shell_command", "--model", request.Provider.Model,
                "--reasoning-effort", request.Provider.ReasoningEffort, "--output-format", "plain", "--verbatim"
            };
            if (!string.IsNullOrWhiteSpace(request.Provider.Profile))
            {
                arguments.AddRange(["--agent", request.Provider.Profile]);
            }
            arguments.AddRange(request.SessionHandle is null ? ["--session-id", session] : ["--resume", session]);
            arguments.AddRange(["--prompt-file", payloadPath]);
            var process = await RunCheckedAsync(new(request.Provider.Executable, arguments, request.Repository, null), processRunner, cancellationToken);
            return new(session, process.StandardOutput);
        }
        finally
        {
            DeleteTemporary(payloadPath);
        }
    }
}

public sealed class CopilotProviderAdapter : ProviderAdapterBase, IProviderAdapter
{
    public async Task<ProviderResult> ExecuteAsync(ProviderRequest request, IProcessRunner processRunner, CancellationToken cancellationToken)
    {
        var payloadPath = WritePayload(request);
        var session = request.SessionHandle ?? Guid.NewGuid().ToString("D");
        try
        {
            var arguments = new List<string>
            {
                "-C", request.Repository, "--no-custom-instructions", "--no-remote", "--no-remote-export",
                "--no-auto-update", "--no-ask-user", "--disable-builtin-mcps", "--disallow-temp-dir",
                "--no-color", "--silent", "--output-format", "json", "--stream", "off",
                "--model", request.Provider.Model, "--effort", request.Provider.ReasoningEffort,
                "--available-tools=view,grep", "--allow-tool=view", "--allow-tool=grep",
                "--deny-tool=write", "--deny-tool=shell", "--deny-tool=task", "--deny-tool=edit"
            };
            if (!string.IsNullOrWhiteSpace(request.Provider.Profile))
            {
                arguments.AddRange(["--agent", request.Provider.Profile]);
            }
            arguments.Add(request.SessionHandle is null ? $"--session-id={session}" : $"--resume={session}");
            arguments.AddRange(["--attachment", payloadPath, "-p", "Follow the attached purpose-review payload exactly."]);
            var process = await RunCheckedAsync(new(request.Provider.Executable, arguments, request.Repository, null), processRunner, cancellationToken);
            var parsed = ParseCopilot(process.StandardOutput);
            if (parsed.SessionIds.Count != 1 || parsed.SessionIds[0] != session)
            {
                throw new RunnerException("SESSION_MISMATCH", "Copilot did not confirm the requested session identity.", ExitCodes.ContractError);
            }
            return new(session, parsed.ReviewText);
        }
        finally
        {
            DeleteTemporary(payloadPath);
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
