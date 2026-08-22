using System.Text.Json;

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
            if (args.Contains("--hang-without-reading-stdin", StringComparer.Ordinal))
            {
                await Task.Delay(TimeSpan.FromMinutes(1));
            }
            else if (args.FirstOrDefault() == "exec")
            {
                await RunCodexAsync(args);
            }
            else if (args.Contains("--prompt-file", StringComparer.Ordinal) || args.Contains("--cwd", StringComparer.Ordinal))
            {
                RunGrok(args);
            }
            else
            {
                RunCopilot(args);
            }
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.ToString());
            return 9;
        }
    }

    private static async Task RunCodexAsync(string[] args)
    {
        var resumed = args.Length > 1 && args[1] == "resume";
        Require(
            args.Contains("--dangerously-bypass-approvals-and-sandbox", StringComparer.Ordinal),
            "Codex sandbox bypass was not specified.");
        Require(
            !args.Contains("-s", StringComparer.Ordinal) &&
            !args.Contains("read-only", StringComparer.Ordinal) &&
            !args.Contains("sandbox_mode=\"read-only\"", StringComparer.Ordinal) &&
            !args.Contains("workspace-write", StringComparer.Ordinal),
            "Codex filesystem sandbox was specified.");
        var payload = await Console.In.ReadToEndAsync();
        ValidatePayload(payload, resumed);
        File.WriteAllText(ValueAfter(args, "-o"), Review(resumed));
        Console.WriteLine(JsonSerializer.Serialize(new { type = "thread.started", thread_id = SessionId }));
    }

    private static void RunGrok(string[] args)
    {
        var resumed = args.Contains("--resume", StringComparer.Ordinal);
        Require(!args.Contains("--sandbox", StringComparer.Ordinal) && !args.Contains("read-only", StringComparer.Ordinal), "Grok filesystem sandbox was specified.");
        Require(ValueAfter(args, "--tools") == "read,view,grep", "Grok tool allowlist was not fixed.");
        Require(ValueAfter(args, "--disallowed-tools") == "write,shell,task,edit_file,run_shell_command", "Grok write tools were not denied.");
        Require(args.Contains("--no-subagents", StringComparer.Ordinal), "Grok subagents were not disabled.");
        ValidatePayload(File.ReadAllText(ValueAfter(args, "--prompt-file")), resumed);
        Console.WriteLine(Review(resumed));
    }

    private static void RunCopilot(string[] args)
    {
        var sessionArgument = args.Single(value => value.StartsWith("--session-id=", StringComparison.Ordinal) || value.StartsWith("--resume=", StringComparison.Ordinal));
        var resumed = sessionArgument.StartsWith("--resume=", StringComparison.Ordinal);
        var sessionId = sessionArgument[(sessionArgument.IndexOf('=') + 1)..];
        Require(args.Contains("--available-tools=view,grep", StringComparer.Ordinal), "Copilot tool allowlist was not fixed.");
        Require(args.Contains("--deny-tool=write", StringComparer.Ordinal) && args.Contains("--deny-tool=shell", StringComparer.Ordinal), "Copilot write tools were not denied.");
        ValidatePayload(File.ReadAllText(ValueAfter(args, "--attachment")), resumed);
        Console.WriteLine(JsonSerializer.Serialize(new { type = "assistant.message", data = new { content = Review(resumed) } }));
        Console.WriteLine(JsonSerializer.Serialize(new { type = "result", sessionId }));
    }

    private static void ValidatePayload(string payload, bool resumed)
    {
        Require(!string.IsNullOrWhiteSpace(payload), "Review payload was empty.");
        Require(resumed != payload.Contains("FAKE-INTEGRATION-CONTEXT", StringComparison.Ordinal), "Context injection did not match the review round.");
    }

    private static string Review(bool resumed) => resumed
        ? "BEGIN_PURPOSE_REVIEW\n{\"status\":\"COMPLETE\",\"findings\":[],\"message\":null}\nEND_PURPOSE_REVIEW"
        : "BEGIN_PURPOSE_REVIEW\n{\"status\":\"FINDINGS\",\"findings\":[{\"id\":\"PUR-001\",\"severity\":\"HIGH\",\"title\":\"Purpose gap\",\"summary\":\"summary\",\"evidence\":\"evidence\",\"requiredChange\":\"change\"}],\"message\":null}\nEND_PURPOSE_REVIEW";

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
