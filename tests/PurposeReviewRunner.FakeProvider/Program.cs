using System.Text.Json;
using System.Text;

namespace PurposeReviewRunnerFakeProvider;

public static class FakeProviderMarker
{
}

public static class Program
{
    private const string SessionId = "22222222-2222-4222-8222-222222222222";

    public static async Task<int> Main(string[] args)
    {
        try
        {
            if (args.Contains("--version", StringComparer.Ordinal))
            {
                Console.WriteLine("GitHub Copilot CLI 1.0.105.");
                return 0;
            }
            if (args.SequenceEqual(["mcp", "list", "--json"], StringComparer.Ordinal))
            {
                Console.WriteLine("{\"mcpServers\":{\"fake-provider-server\":{\"source\":\"user\",\"enabled\":true}}}");
                return 0;
            }
            var delayValue = Environment.GetEnvironmentVariable("PURPOSE_REVIEW_FAKE_PROVIDER_DELAY_MS");
            if (int.TryParse(delayValue, out var delayMilliseconds) && delayMilliseconds > 0)
            {
                await Task.Delay(TimeSpan.FromMilliseconds(delayMilliseconds));
            }
            var counterPath = Environment.GetEnvironmentVariable("PURPOSE_REVIEW_FAKE_PROVIDER_COUNTER");
            if (!string.IsNullOrWhiteSpace(counterPath))
            {
                File.AppendAllText(counterPath, DateTime.UtcNow.ToString("O") + Environment.NewLine);
            }
            if (args.Contains("--hang-without-reading-stdin", StringComparer.Ordinal))
            {
                await Task.Delay(TimeSpan.FromMinutes(1));
            }
            else if (args.Contains("--dump-stdin-bytes", StringComparer.Ordinal))
            {
                await DumpStdinBytesAsync(args);
            }
            else if (args.FirstOrDefault() == "exec")
            {
                await RunCodexAsync(args);
            }
            else
            {
                await RunCopilotAsync(args);
            }
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.ToString());
            var errorLogPath = Environment.GetEnvironmentVariable("PURPOSE_REVIEW_FAKE_PROVIDER_ERROR_LOG");
            if (!string.IsNullOrWhiteSpace(errorLogPath))
            {
                try
                {
                    File.AppendAllText(errorLogPath, exception.ToString() + Environment.NewLine);
                }
                catch (Exception loggingException)
                {
                    Console.Error.WriteLine(loggingException.ToString());
                }
            }
            return 9;
        }
    }

    private static async Task DumpStdinBytesAsync(string[] args)
    {
        var path = ValueAfter(args, "--dump-stdin-bytes");
        await using var input = Console.OpenStandardInput();
        await using var output = File.Create(path);
        await input.CopyToAsync(output);
    }

    private static async Task RunCodexAsync(string[] args)
    {
        var resumed = args.Length > 1 && args[1] == "resume";
        Require(!args.Contains("--dangerously-bypass-approvals-and-sandbox", StringComparer.Ordinal), "Codex sandbox bypass must not be specified.");
        Require(args.Contains("--ignore-user-config", StringComparer.Ordinal), "Codex user configuration must be ignored.");
        Require(args.Contains("--ignore-rules", StringComparer.Ordinal), "Codex rules must be ignored.");
        Require(args.Contains("--skip-git-repo-check", StringComparer.Ordinal), "Codex must run outside the repository.");
        Require(args.Contains("-", StringComparer.Ordinal), "Codex must receive the prompt through stdin.");
        Require(resumed || (args.Contains("--sandbox", StringComparer.Ordinal) && ValueAfter(args, "--sandbox") == "read-only"), "Codex initial run must use a read-only sandbox.");
        foreach (var feature in new[] { "shell_tool", "browser_use", "browser_use_external", "standalone_web_search", "apps", "enable_mcp_apps", "mcp_2026_07_28", "multi_agent", "multi_agent_v2", "multi_agent_v2_dynamic_tools", "code_mode", "code_mode_host", "code_mode_interrupt", "code_mode_only", "code_mode_only_strict_3p_tools", "code_mode_tool_search", "image_generation", "view_image", "computer_use", "in_app_browser", "in_app_chat", "in_app_voice", "skill_search", "plugins", "hooks", "memories" })
        {
            Require(HasDisabledFeature(args, feature), $"Codex feature was not disabled: {feature}");
        }
        var payload = await Console.In.ReadToEndAsync();
        ValidatePayload(payload);
        File.WriteAllText(ValueAfter(args, "-o"), Review(resumed));
        Console.WriteLine(JsonSerializer.Serialize(new { type = "thread.started", thread_id = SessionId }));
    }

    private static async Task RunCopilotAsync(string[] args)
    {
        var sessionArgument = args.Single(value => value.StartsWith("--session-id=", StringComparison.Ordinal) || value.StartsWith("--resume=", StringComparison.Ordinal));
        var resumed = sessionArgument.StartsWith("--resume=", StringComparison.Ordinal);
        var sessionId = sessionArgument[(sessionArgument.IndexOf('=') + 1)..];
        Require(args.Contains("--available-tools=report_intent", StringComparer.Ordinal), "Copilot must use the verified inert tool allowlist.");
        Require(args.Contains("--disable-builtin-mcps", StringComparer.Ordinal), "Copilot builtin MCP servers must be disabled.");
        Require(args.Contains("--disable-mcp-server=fake-provider-server", StringComparer.Ordinal), "Copilot did not disable the dynamically enumerated MCP server.");
        Require(Environment.GetEnvironmentVariable("COPILOT_PLUGIN_DIR_ONLY") == "true", "Copilot plugin discovery was not isolated.");
        Require(args.Contains("--no-custom-instructions", StringComparer.Ordinal), "Copilot custom instructions must be disabled.");
        Require(args.Contains("--deny-tool=shell", StringComparer.Ordinal), "Copilot shell permission must be denied.");
        Require(args.Contains("--deny-tool=write", StringComparer.Ordinal) && args.Contains("--deny-tool=task", StringComparer.Ordinal), "Copilot write/delegation permissions must be denied.");
        Require(!args.Contains("--attachment", StringComparer.Ordinal) && !args.Contains("-p", StringComparer.Ordinal), "Copilot payload must not use command-line or attachment transport.");
        await using var standardInput = Console.OpenStandardInput();
        using var reader = new StreamReader(
            standardInput,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true),
            detectEncodingFromByteOrderMarks: false);
        var payload = await reader.ReadToEndAsync();
        Require(!payload.StartsWith('\uFEFF'), "Copilot stdin payload must not contain a UTF-8 BOM.");
        ValidatePayload(payload);
        if (payload.Contains("FAKE-INTEGRATION-CONTEXT", StringComparison.Ordinal))
        {
            Require(payload.Contains("FAKE-JAPANESE-END-\\u7D42\\u7AEF", StringComparison.Ordinal), "Copilot stdin payload was truncated or incorrectly encoded.");
        }
        Console.WriteLine(JsonSerializer.Serialize(new { type = "assistant.message", data = new { content = Review(resumed) } }));
        Console.WriteLine(JsonSerializer.Serialize(new { type = "result", sessionId }));
    }

    private static bool HasDisabledFeature(string[] args, string feature)
    {
        for (var index = 0; index + 1 < args.Length; index++)
        {
            if (args[index] == "--disable" && args[index + 1] == feature)
            {
                return true;
            }
        }
        return false;
    }

    private static void ValidatePayload(string payload)
    {
        Require(!string.IsNullOrWhiteSpace(payload), "Review payload was empty.");
        Require(payload.Contains("\"schemaVersion\":", StringComparison.Ordinal), "Versioned review input was missing.");
        Require(payload.Contains("\"purpose\":", StringComparison.Ordinal), "Purpose input was missing.");
    }

    private static string Review(bool resumed) => resumed
        ? "BEGIN_PURPOSE_REVIEW\n{\"status\":\"COMPLETE\",\"findings\":[],\"message\":null,\"informationRequests\":[]}\nEND_PURPOSE_REVIEW"
        : "BEGIN_PURPOSE_REVIEW\n{\"status\":\"FINDINGS\",\"findings\":[{\"id\":\"PUR-001\",\"severity\":\"HIGH\",\"title\":\"Purpose gap\",\"summary\":\"summary\",\"evidence\":\"evidence\",\"requiredOutcome\":\"change\"}],\"message\":null,\"informationRequests\":[]}\nEND_PURPOSE_REVIEW";

    private static string ValueAfter(string[] args, string option)
    {
        var index = Array.IndexOf(args, option);
        Require(index >= 0 && index + 1 < args.Length, $"Missing option: {option}");
        return args[index + 1];
    }

    private static void Require(bool condition, string message)
    {
        if (!condition)
        {
            throw new InvalidOperationException(message);
        }
    }
}
