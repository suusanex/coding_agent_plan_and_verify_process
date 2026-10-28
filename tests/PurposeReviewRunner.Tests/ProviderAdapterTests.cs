using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using PurposeReviewRunner;

namespace PurposeReviewRunnerTests;

[TestClass]
public sealed class ProviderAdapterTests
{
    private const string SessionId = "22222222-2222-4222-8222-222222222222";
    private static readonly string[] ExpectedCodexDisabledFeatures =
    [
        "shell_tool", "browser_use", "browser_use_external", "browser_use_full_cdp_access", "standalone_web_search",
        "apps", "mcp_2026_07_28", "multi_agent", "multi_agent_v2", "code_mode", "code_mode_host",
        "image_generation", "view_image", "computer_use", "in_app_browser", "skill_search", "plugins", "hooks", "memories"
    ];

    [TestMethod]
    public async Task CodexInitialAndResumeUseReadOnlySandboxAndOnlySuppliedPayload()
    {
        using var fixture = new AdapterFixture();
        var adapter = new CodexProviderAdapter();
        var request = fixture.Request("codex", null);

        var initial = await adapter.ExecuteAsync(request, fixture.Runner, CancellationToken.None);
        var resumed = await adapter.ExecuteAsync(request with { SessionHandle = initial.SessionHandle, Round = 2 }, fixture.Runner, CancellationToken.None);

        Assert.AreEqual(SessionId, initial.SessionHandle);
        Assert.AreEqual(initial.SessionHandle, resumed.SessionHandle);
        Assert.AreEqual("BEGIN_PURPOSE_REVIEW\n{\"status\":\"COMPLETE\",\"findings\":[],\"message\":\"codex response\",\"informationRequests\":[]}\nEND_PURPOSE_REVIEW", initial.ReviewText);

        var calls = fixture.Runner.Requests.Where(call => call.Arguments.Contains("exec", StringComparer.Ordinal)).ToArray();
        Assert.AreEqual(2, calls.Length);
        foreach (var call in calls)
        {
            Assert.AreEqual(fixture.RunDirectory, call.WorkingDirectory);
            Assert.AreEqual(request.Payload, call.StandardInput);
            Assert.IsFalse(call.Arguments.Contains(request.Repository, StringComparer.Ordinal));
            Assert.IsFalse(call.StandardInput!.Contains(request.Repository, StringComparison.Ordinal));
            CollectionAssert.Contains(call.Arguments.ToArray(), "--ignore-user-config");
            CollectionAssert.Contains(call.Arguments.ToArray(), "--ignore-rules");
            CollectionAssert.Contains(call.Arguments.ToArray(), "--skip-git-repo-check");
            CollectionAssert.Contains(call.Arguments.ToArray(), "--disable");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "--dangerously-bypass-approvals-and-sandbox");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "--ephemeral");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "-p");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "--image");
            Assert.AreEqual("test-model", ValueAfter(call.Arguments, "--model"));
            Assert.IsTrue(call.Arguments.Contains("model_reasoning_effort=\"medium\"", StringComparer.Ordinal));
            Assert.IsTrue(call.Arguments.Contains("approval_policy=\"never\"", StringComparer.Ordinal));
            foreach (var feature in ExpectedCodexDisabledFeatures)
            {
                Assert.IsTrue(HasDisabledFeature(call.Arguments, feature), $"Expected feature disabled: {feature}");
            }
            var responsePath = ValueAfter(call.Arguments, "--output-last-message");
            Assert.AreEqual(Path.GetFullPath(fixture.RunDirectory), Path.GetDirectoryName(Path.GetFullPath(responsePath)));
            Assert.IsFalse(File.Exists(responsePath));
        }

        Assert.AreEqual("read-only", ValueAfter(calls[0].Arguments, "--sandbox"));
        Assert.AreEqual("resume", calls[1].Arguments[1]);
        Assert.AreEqual(initial.SessionHandle, calls[1].Arguments[2]);
        Assert.IsTrue(calls[1].Arguments.Contains("sandbox_mode=\"read-only\"", StringComparer.Ordinal));
        Assert.IsTrue(calls[1].Arguments.Contains("approval_policy=\"never\"", StringComparer.Ordinal));
        Assert.IsFalse(calls[1].Arguments.Contains("--sandbox", StringComparer.Ordinal));
    }

    [TestMethod]
    public async Task CodexRejectsUnverifiedCliVersionBeforeReviewInvocation()
    {
        using var fixture = new AdapterFixture(codexVersion: "codex-cli 0.165.1");

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            new CodexProviderAdapter().ExecuteAsync(fixture.Request("codex", null), fixture.Runner, CancellationToken.None));

        Assert.AreEqual("PROVIDER_VERSION_UNSUPPORTED", exception.Code);
        Assert.AreEqual(1, fixture.Runner.Requests.Count);
    }

    [TestMethod]
    public async Task CodexRequiresOutputAndMatchingSessionOnResume()
    {
        using (var fixture = new AdapterFixture(writeCodexOutput: false))
        {
            var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
                new CodexProviderAdapter().ExecuteAsync(fixture.Request("codex", null), fixture.Runner, CancellationToken.None));
            Assert.AreEqual("REVIEW_OUTPUT_MISSING", exception.Code);
        }

        using (var fixture = new AdapterFixture(codexResumeSession: "33333333-3333-4333-8333-333333333333"))
        {
            var adapter = new CodexProviderAdapter();
            var initial = await adapter.ExecuteAsync(fixture.Request("codex", null), fixture.Runner, CancellationToken.None);

            var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
                adapter.ExecuteAsync(fixture.Request("codex", initial.SessionHandle) with { Round = 2 }, fixture.Runner, CancellationToken.None));

            Assert.AreEqual("SESSION_MISMATCH", exception.Code);
        }
    }

    [TestMethod]
    public async Task CopilotInitialAndResumeUseInertToolAllowlistAndDisableConfiguredMcp()
    {
        using var fixture = new AdapterFixture();
        var adapter = new CopilotProviderAdapter();
        var request = fixture.Request("copilot", null);

        var first = await adapter.ExecuteAsync(request, fixture.Runner, CancellationToken.None);
        var resumed = await adapter.ExecuteAsync(request with { SessionHandle = first.SessionHandle, Round = 2 }, fixture.Runner, CancellationToken.None);

        Assert.IsFalse(string.IsNullOrWhiteSpace(first.SessionHandle));
        Assert.AreEqual(first.SessionHandle, resumed.SessionHandle);
        var calls = fixture.Runner.Requests.Where(call => call.Arguments.Contains("--available-tools=report_intent", StringComparer.Ordinal)).ToArray();
        Assert.AreEqual(2, calls.Length);
        foreach (var call in calls)
        {
            Assert.AreEqual(fixture.RunDirectory, call.WorkingDirectory);
            CollectionAssert.Contains(call.Arguments.ToArray(), "--disable-builtin-mcps");
            CollectionAssert.Contains(call.Arguments.ToArray(), "--no-custom-instructions");
            CollectionAssert.Contains(call.Arguments.ToArray(), "--disable-mcp-server=sample-server");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "--agent");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "--attachment");
            CollectionAssert.DoesNotContain(call.Arguments.ToArray(), "-p");
            Assert.AreEqual("true", call.EnvironmentVariables!["COPILOT_PLUGIN_DIR_ONLY"]);
            Assert.AreEqual(request.Payload, call.StandardInput);
            Assert.IsFalse(call.Arguments.Contains(request.Repository, StringComparer.Ordinal));
            Assert.IsFalse(call.StandardInput!.Contains(request.Repository, StringComparison.Ordinal));
        }
        var mcpCalls = fixture.Runner.Requests.Where(call => call.Arguments.SequenceEqual(["mcp", "list", "--json"], StringComparer.Ordinal)).ToArray();
        Assert.AreEqual(2, mcpCalls.Length);
        foreach (var mcpCall in mcpCalls)
        {
            Assert.AreEqual(fixture.RunDirectory, mcpCall.WorkingDirectory);
            Assert.AreEqual("true", mcpCall.EnvironmentVariables!["COPILOT_PLUGIN_DIR_ONLY"]);
        }
        CollectionAssert.Contains(calls[0].Arguments.ToArray(), $"--session-id={first.SessionHandle}");
        CollectionAssert.Contains(calls[1].Arguments.ToArray(), $"--resume={first.SessionHandle}");
    }

    [TestMethod]
    public async Task UnknownCliVersionFailsBeforeReviewInvocation()
    {
        using var fixture = new AdapterFixture(copilotVersion: "GitHub Copilot CLI 1.0.106.");
        await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            new CopilotProviderAdapter().ExecuteAsync(fixture.Request("copilot", null), fixture.Runner, CancellationToken.None));

        Assert.AreEqual(1, fixture.Runner.Requests.Count);
        CollectionAssert.AreEqual(new[] { "--version" }, fixture.Runner.Requests[0].Arguments.ToArray());
    }

    [TestMethod]
    public async Task CopilotRejectsVersionSuffixEvenWhenVerifiedVersionIsPrefix()
    {
        using var fixture = new AdapterFixture(copilotVersion: "GitHub Copilot CLI 1.0.105-beta.");

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            new CopilotProviderAdapter().ExecuteAsync(fixture.Request("copilot", null), fixture.Runner, CancellationToken.None));

        Assert.AreEqual("PROVIDER_VERSION_UNSUPPORTED", exception.Code);
        Assert.AreEqual(1, fixture.Runner.Requests.Count);
    }

    [TestMethod]
    public async Task CopilotFailsClosedBeforeAnyCliLaunchRegardlessOfProfile()
    {
        using var fixture = new AdapterFixture();
        var request = fixture.Request("copilot", null) with { Provider = fixture.Request("copilot", null).Provider with { Profile = "custom" } };

        var exception = await Assert.ThrowsExactlyAsync<RunnerException>(() =>
            new CopilotProviderAdapter().ExecuteAsync(request, fixture.Runner, CancellationToken.None));

        Assert.AreEqual("CONFIG_INVALID", exception.Code);
        Assert.AreEqual(0, fixture.Runner.Requests.Count);
    }

    [TestMethod]
    public void UnsupportedGrokProviderFailsClosed()
    {
        var exception = Assert.ThrowsExactly<RunnerException>(() => ProviderFactory.Create("grok"));
        Assert.AreEqual("CONFIG_INVALID", exception.Code);
    }

    private sealed class AdapterFixture : IDisposable
    {
        public AdapterFixture(
            string codexVersion = "codex-cli 0.165.0",
            string copilotVersion = "GitHub Copilot CLI 1.0.105.",
            bool writeCodexOutput = true,
            string? codexResumeSession = null)
        {
            Root = Path.Combine(Path.GetTempPath(), "purpose-review-adapter-tests", Guid.NewGuid().ToString("N"));
            RunDirectory = Path.Combine(Root, "external-run");
            Repository = Path.Combine(Root, "repository");
            Directory.CreateDirectory(RunDirectory);
            Directory.CreateDirectory(Repository);
            Runner = new ScriptedProviderProcessRunner(codexVersion, copilotVersion, writeCodexOutput, codexResumeSession);
        }

        public string Root { get; }
        public string RunDirectory { get; }
        public string Repository { get; }
        public ScriptedProviderProcessRunner Runner { get; }

        public ProviderRequest Request(string provider, string? session) => new(
            new ProviderSnapshot(provider, provider, "test-model", "medium", null),
            Repository,
            RunDirectory,
            "Only review supplied purpose/design text. Do not inspect repository.",
            session,
            session is null ? 1 : 2);

        public void Dispose()
        {
            try
            {
                Directory.Delete(Root, recursive: true);
            }
            catch (Exception exception)
            {
                System.Diagnostics.Trace.TraceError(exception.ToString());
            }
        }
    }

    private static bool HasDisabledFeature(IReadOnlyList<string> arguments, string feature)
    {
        for (var index = 0; index + 1 < arguments.Count; index++)
        {
            if (arguments[index] == "--disable" && arguments[index + 1] == feature)
            {
                return true;
            }
        }
        return false;
    }

    private static string ValueAfter(IReadOnlyList<string> arguments, string option)
    {
        var index = Array.IndexOf(arguments.ToArray(), option);
        Assert.IsGreaterThanOrEqualTo(0, index, $"Missing option: {option}");
        Assert.IsLessThan(arguments.Count, index + 1, $"Missing value for option: {option}");
        return arguments[index + 1];
    }

    private sealed class ScriptedProviderProcessRunner(
        string codexVersion,
        string copilotVersion,
        bool writeCodexOutput,
        string? codexResumeSession) : IProcessRunner
    {
        public List<ProcessRequest> Requests { get; } = [];

        public Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken)
        {
            Requests.Add(request);
            if (request.Arguments.SequenceEqual(["--version"], StringComparer.Ordinal))
            {
                var output = request.Executable == "codex" ? codexVersion : copilotVersion;
                return Task.FromResult(new ProcessResult(0, output, string.Empty, false));
            }

            if (request.Arguments.SequenceEqual(["mcp", "list", "--json"], StringComparer.Ordinal))
            {
                return Task.FromResult(new ProcessResult(0, "{\"mcpServers\":{\"sample-server\":{\"source\":\"user\",\"enabled\":true}}}", string.Empty, false));
            }

            if (request.Executable == "codex")
            {
                var outputPath = ValueAfter(request.Arguments, "--output-last-message");
                var resumed = request.Arguments.Count > 1 && request.Arguments[1] == "resume";
                if (writeCodexOutput)
                {
                    File.WriteAllText(outputPath, "BEGIN_PURPOSE_REVIEW\n{\"status\":\"COMPLETE\",\"findings\":[],\"message\":\"codex response\",\"informationRequests\":[]}\nEND_PURPOSE_REVIEW");
                }
                var codexSession = resumed ? codexResumeSession ?? SessionId : SessionId;
                return Task.FromResult(new ProcessResult(0, JsonSerializer.Serialize(new { type = "thread.started", thread_id = codexSession }), string.Empty, false));
            }

            var id = request.Arguments.Single(value => value.StartsWith("--session-id=", StringComparison.Ordinal) || value.StartsWith("--resume=", StringComparison.Ordinal));
            var session = id[(id.IndexOf('=') + 1)..];
            var events = string.Join(Environment.NewLine,
                JsonSerializer.Serialize(new { type = "assistant.message", data = new { content = "BEGIN_PURPOSE_REVIEW\n{\"status\":\"COMPLETE\",\"findings\":[],\"message\":\"bound snapshot\",\"informationRequests\":[]}\nEND_PURPOSE_REVIEW" } }),
                JsonSerializer.Serialize(new { type = "result", sessionId = session }));
            return Task.FromResult(new ProcessResult(0, events, string.Empty, false));
        }
    }
}
