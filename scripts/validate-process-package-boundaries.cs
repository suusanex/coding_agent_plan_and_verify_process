#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;

return await ProgramEntry.RunAsync(args);

internal static class ProgramEntry
{
    private const string ClassifierPath = "scripts/validate-process-package-boundaries.cs";
    private const string DependencyVersionPinPattern = @"(?:Plan Coverage|Adaptive)(?: package)? version\s+\d+(?:\.\d+)+(?:[-+][0-9A-Za-z.-]+)?";

    private static readonly string[] ConnectedPackages =
    [
        "adaptive-implementation-execution",
        "design-pair-implementation-execution",
        "plan-coverage-residual-flow"
    ];

    private static readonly string[] PortablePackages =
    [
        "adaptive-implementation-execution",
        "design-pair-implementation-execution",
        "goal-context-authoring",
        "pr-review-remediation",
        "persistent-purpose-review",
        "plan-coverage-residual-flow"
    ];

    public static async Task<int> RunAsync(string[] args)
    {
        try
        {
            if (args.Length == 0 || args[0] is "validate")
            {
                ValidateBoundaries(GetRepositoryRoot());
                Console.WriteLine("Process package compatibility validation: PASS");
                return 0;
            }

            if (args[0] is "self-test")
            {
                RunSelfTest();
                Console.WriteLine("Process package validation scope self-test: PASS");
                return 0;
            }

            if (args[0] is "scope")
            {
                var options = ParseOptions(args[1..]);
                var repositoryRoot = GetRepositoryRoot();
                var changedPaths = await GetChangedPathsAsync(repositoryRoot, options["base"], options["head"]);
                var scope = Classify(changedPaths);
                WriteScope(scope, options["github-output"]);
                return 0;
            }

            throw new InvalidOperationException($"Unknown command: {args[0]}");
        }
        catch (Exception ex)
        {
            Trace.TraceError(ex.ToString());
            Console.Error.WriteLine(ex.ToString());
            return 1;
        }
    }

    private static Dictionary<string, string> ParseOptions(string[] args)
    {
        var options = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var index = 0; index < args.Length; index += 2)
        {
            if (index + 1 >= args.Length || !args[index].StartsWith("--", StringComparison.Ordinal))
            {
                throw new InvalidOperationException("scope requires --base, --head, and --github-output values.");
            }

            options.Add(args[index][2..], args[index + 1]);
        }

        foreach (var required in new[] { "base", "head", "github-output" })
        {
            if (!options.ContainsKey(required) || string.IsNullOrWhiteSpace(options[required]))
            {
                throw new InvalidOperationException($"Missing required option: --{required}");
            }
        }

        return options;
    }

    private static void ValidateBoundaries(string repositoryRoot)
    {
        var failures = new List<string>();

        var adaptiveManifest = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/apm.yml");
        var designPairManifest = Read(repositoryRoot, "apm-packages/design-pair-implementation-execution/apm.yml");
        var planCoverageManifest = Read(repositoryRoot, "apm-packages/plan-coverage-residual-flow/apm.yml");
        Require(adaptiveManifest, @"(?ms)dependencies:\s*\n\s*apm:\s*\n\s*-\s*git:\s*parent\s*\n\s*path:\s*apm-packages/codex-profile-finalizer\s*$", "Adaptive must depend on the Codex profile finalizer package boundary.", failures);
        Require(designPairManifest, @"(?ms)dependencies:\s*\n\s*apm:\s*\n(?:\s*#[^\n]*\n)*\s*-\s*git:\s*parent\s*\n\s*path:\s*apm-packages/adaptive-implementation-execution\s*$", "Design Pair must depend on the Adaptive package boundary.", failures);
        Require(planCoverageManifest, @"(?ms)dependencies:\s*\n\s*apm:\s*\n(?:\s*#[^\n]*\n)*\s*-\s*git:\s*parent\s*\n\s*path:\s*apm-packages/adaptive-implementation-execution\s*$", "Plan Coverage must depend on the Adaptive package boundary.", failures);
        Reject(string.Join('\n', adaptiveManifest, designPairManifest, planCoverageManifest), @"path:\s*apm-packages/[^\s]+/\.apm/", "Package manifests must not depend on another package's internal .apm path.", failures);

        var adaptiveSkill = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md");
        var adaptiveHandoff = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md");
        var adaptiveDecisionOwner = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/.apm/agents/decision-surface-implementation-owner.agent.md");
        var adaptiveResidualOwner = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/.apm/agents/bounded-residual-implementation-owner.agent.md");
        var adaptiveOverlay = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/codex-profile-overlays.json");
        var adaptiveUsage = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/docs/usage-guide.md");
        var finalizer = Read(repositoryRoot, "apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs");

        Require(adaptiveDecisionOwner, @"(?m)^name:\s*decision-surface-implementation-owner\s*$", "Adaptive must publish the decision-surface owner identity.", failures);
        Require(adaptiveResidualOwner, @"(?m)^name:\s*bounded-residual-implementation-owner\s*$", "Adaptive must publish the bounded-residual owner identity.", failures);
        Require(adaptiveSkill, @"READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION", "Adaptive must publish the bounded-residual transfer verdict.", failures);
        Require(adaptiveSkill, @"NEEDS_DECISION_SURFACE_REENTRY", "Adaptive must publish the decision-surface re-entry verdict.", failures);
        Require(adaptiveHandoff, @"Ownership transfer basis:\s*bounded-residual-work-only", "Adaptive must publish the bounded-residual transfer basis.", failures);
        Require(adaptiveResidualOwner, @"(?s)UNPERSISTED_PARENT_PAYLOAD.*reentry_handoff_path.*output_contract:\s*parent-persisted-handoff-payload", "Adaptive must publish the parent-persisted re-entry payload boundary.", failures);
        foreach (var owner in new[] { "decision-surface-implementation-owner", "bounded-residual-implementation-owner" })
        {
            Require(adaptiveOverlay, Regex.Escape(owner), $"Adaptive profile overlay must publish {owner}.", failures);
            Require(finalizer, Regex.Escape(owner), $"Codex profile finalizer must consume {owner}.", failures);
        }

        var designPairSkill = Read(repositoryRoot, "apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md");
        var designPairHandoff = Read(repositoryRoot, "apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/handoff.md");
        Require(designPairSkill, @"implementation_route:\s*design-pair", "Design Pair must publish its route identity.", failures);
        Require(designPairSkill, @"利用者が Design Pair route を明示的に選択した場合だけ", "Design Pair must remain explicit-selection-only.", failures);
        Require(designPairHandoff, @"Adaptive Implementation Result", "Design Pair handoff must expose the Adaptive result boundary.", failures);
        Require(designPairHandoff, @"Adaptive Implementation verdict sequence", "Design Pair handoff must expose the Adaptive verdict sequence.", failures);
        Require(adaptiveUsage, @"(?s)Design Pair:.*implementation_route:\s*design-pair.*design_pair_handoff:\s*plans/<slug>-design-pair-implementation-handoff\.md", "Adaptive usage must consume the Design Pair route and handoff path.", failures);

        var planCoverageSkill = Read(repositoryRoot, "apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md");
        Require(planCoverageSkill, @"decision-surface-implementation-owner\.agent\.md", "Plan Coverage must invoke the Adaptive decision-surface owner.", failures);
        Require(planCoverageSkill, @"bounded-residual-implementation-owner", "Plan Coverage must invoke the Adaptive bounded-residual owner.", failures);
        Require(planCoverageSkill, @"(?s)output_contract:\s*parent-persisted-handoff-payload.*unpersisted parent payload", "Plan Coverage must consume the parent-persisted re-entry payload.", failures);
        Require(planCoverageSkill, @"The `design-pair-implementation-execution` package remains a separate package", "Plan Coverage must preserve Design Pair package ownership.", failures);
        Require(planCoverageSkill, @"both packages are installed for the same target and the user explicitly selects Design Pair", "Plan Coverage must require explicit same-target Design Pair selection.", failures);
        Require(planCoverageSkill, @"While Design Pair is waiting, do not fall back to Adaptive", "Plan Coverage must not bypass a waiting Design Pair route.", failures);

        var adaptiveValidator = Read(repositoryRoot, "apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1");
        var designPairValidator = Read(repositoryRoot, "apm-packages/design-pair-implementation-execution/scripts/validate.ps1");
        var planCoverageValidator = Read(repositoryRoot, "apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1");
        Reject(adaptiveValidator, @"apm-packages/codex-profile-finalizer|\.github/workflows/", "Adaptive package-local validator must not inspect dependency internals or workflow wiring.", failures);
        Reject(designPairValidator, @"apm-packages/(?:adaptive-implementation-execution|plan-coverage-residual-flow)/(?:(?:\.apm|scripts|docs|apm\.yml))|apm-packages/codex-profile-finalizer|\.github/workflows/", "Design Pair package-local validator must not inspect provider or peer internals.", failures);
        Reject(designPairValidator, DependencyVersionPinPattern, "Design Pair package-local validator must not pin current dependency versions.", failures);
        Reject(planCoverageValidator, @"scripts/validate-adaptive-implementation-execution\.ps1|design-pair-implementation-execution/scripts/validate\.ps1|boundedResidualOwner|\.github/workflows/", "Plan Coverage package-local validator must not inspect provider validators, provider agent bodies, or workflow wiring.", failures);

        var adaptiveWorkflow = Read(repositoryRoot, ".github/workflows/validate-adaptive-implementation-execution.yml");
        var designPairWorkflow = Read(repositoryRoot, ".github/workflows/validate-design-pair-implementation-execution.yml");
        var planCoverageWorkflow = Read(repositoryRoot, ".github/workflows/validate-plan-coverage-residual-flow.yml");
        var compatibilityWorkflow = Read(repositoryRoot, ".github/workflows/validate-process-package-compatibility.yml");
        var agentPluginWorkflow = Read(repositoryRoot, ".github/workflows/validate-agent-plugin-packages.yml");
        Reject(string.Join('\n', adaptiveWorkflow, designPairWorkflow, planCoverageWorkflow), @"validate-(?:adaptive-implementation-apm-smoke|dp-apm-smoke|plan-coverage-residual-flow-apm-smoke)\.ps1", "Package-local workflows must not own remote distribution smoke.", failures);
        foreach (var smoke in new[] { "validate-adaptive-implementation-apm-smoke.ps1", "validate-dp-apm-smoke.ps1", "validate-plan-coverage-residual-flow-apm-smoke.ps1" })
        {
            Require(compatibilityWorkflow, Regex.Escape(smoke), $"Compatibility workflow must own {smoke}.", failures);
        }
        foreach (var triggerInput in new[]
        {
            ".github/workflows/validate-adaptive-implementation-execution.yml",
            ".github/workflows/validate-design-pair-implementation-execution.yml",
            ".github/workflows/validate-plan-coverage-residual-flow.yml",
            ".github/workflows/validate-agent-plugin-packages.yml",
            "apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1",
            "apm-packages/design-pair-implementation-execution/scripts/validate.ps1",
            "apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow.ps1"
        })
        {
            RequireOccurrences(compatibilityWorkflow, triggerInput, 2, $"Compatibility workflow must trigger for pull requests and main pushes that change {triggerInput}.", failures);
        }
        RequireOccurrences(planCoverageWorkflow, ClassifierPath, 2, "Plan Coverage workflow must trigger for pull requests and main pushes that change the scope classifier.", failures);
        RequireOccurrences(agentPluginWorkflow, ClassifierPath, 2, "Agent Plugin workflow must trigger for pull requests and main pushes that change the scope classifier.", failures);
        Reject(agentPluginWorkflow, @"validate-no-root-projections\.ps1", "Agent Plugin workflow must not duplicate repository layout validation.", failures);

        if (failures.Count > 0)
        {
            throw new InvalidOperationException("Process package compatibility validation failed:\n- " + string.Join("\n- ", failures));
        }
    }

    private static void RunSelfTest()
    {
        if (!Regex.IsMatch("Adaptive package version 0.7.0", DependencyVersionPinPattern, RegexOptions.CultureInvariant))
        {
            throw new InvalidOperationException("Dependency version pin pattern must reject future version values.");
        }

        AssertScope(
            [ClassifierPath],
            ConnectedPackages,
            PortablePackages,
            true,
            true,
            true);
        AssertScope(
            ["apm-packages/design-pair-implementation-execution/docs/usage-guide.md"],
            [],
            [],
            false,
            false,
            false);
        AssertScope(
            ["apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md"],
            ["design-pair-implementation-execution"],
            ["design-pair-implementation-execution"],
            false,
            false,
            false);
        AssertScope(
            ["apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md"],
            ["adaptive-implementation-execution", "design-pair-implementation-execution", "plan-coverage-residual-flow"],
            ["adaptive-implementation-execution"],
            false,
            false,
            false);
        AssertScope(
            ["scripts/agent-plugins/AgentPlugin.Common.ps1"],
            [],
            PortablePackages,
            false,
            false,
            false);
        AssertScope(
            [".github/workflows/validate-agent-plugin-packages.yml"],
            [],
            PortablePackages,
            false,
            false,
            false);
        AssertScope(
            ["./.github/workflows/validate-plan-coverage-residual-flow.yml"],
            [],
            [],
            true,
            true,
            true);
        AssertScope(
            ["docs/plan-coverage-runtime-qualification.md"],
            [],
            [],
            false,
            true,
            false);
        AssertScope(
            ["apm-packages/plan-coverage-residual-flow/scripts/plan-coverage-copilot-scenario-lib.ps1"],
            [],
            [],
            false,
            true,
            false);
        AssertScope(
            ["apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1"],
            [],
            [],
            false,
            true,
            false);
        AssertScope(
            ["apm-packages/plan-coverage-residual-flow/scripts/PlanCoverageAgentPlugin.Common.ps1"],
            [],
            [],
            false,
            false,
            true);
        AssertScope(
            ["apm-packages/plan-coverage-residual-flow/tests/full-coverage-standalone/PCF-001/expected.json"],
            [],
            [],
            true,
            false,
            false);
        AssertScope(
            ["README.md"],
            [],
            [],
            false,
            false,
            false);
    }

    private static void AssertScope(string[] paths, string[] distribution, string[] agentPlugins, bool planE2E, bool planRuntime, bool planPluginPoc)
    {
        var actual = Classify(paths);
        if (!actual.DistributionPackages.SequenceEqual(distribution.Order(StringComparer.Ordinal)) ||
            !actual.AgentPluginPackages.SequenceEqual(agentPlugins.Order(StringComparer.Ordinal)) ||
            actual.PlanE2E != planE2E ||
            actual.PlanRuntimeEvidence != planRuntime ||
            actual.PlanPluginPoc != planPluginPoc)
        {
            throw new InvalidOperationException($"Scope mismatch for {string.Join(',', paths)}. Distribution={string.Join(',', actual.DistributionPackages)}; AgentPlugins={string.Join(',', actual.AgentPluginPackages)}; PlanE2E={actual.PlanE2E}; PlanRuntime={actual.PlanRuntimeEvidence}; PlanPluginPoc={actual.PlanPluginPoc}");
        }
    }

    private static ValidationScope Classify(IEnumerable<string> changedPaths)
    {
        var paths = changedPaths.Select(NormalizePath).Where(path => path.Length > 0).Distinct(StringComparer.Ordinal).ToArray();
        var distribution = new HashSet<string>(StringComparer.Ordinal);
        var agentPlugins = new HashSet<string>(StringComparer.Ordinal);
        var planE2E = false;
        var planRuntimeEvidence = false;
        var planPluginPoc = false;

        foreach (var path in paths)
        {
            if (path == ClassifierPath)
            {
                distribution.UnionWith(ConnectedPackages);
                agentPlugins.UnionWith(PortablePackages);
                planE2E = true;
                planRuntimeEvidence = true;
                planPluginPoc = true;
                continue;
            }

            var adaptiveDistribution = IsCanonicalOrManifest(path, "adaptive-implementation-execution") ||
                path == "apm-packages/adaptive-implementation-execution/codex-profile-overlays.json" ||
                path == "apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-apm-smoke.ps1" ||
                path.StartsWith("apm-packages/codex-profile-finalizer/", StringComparison.Ordinal);
            if (adaptiveDistribution)
            {
                distribution.UnionWith(["adaptive-implementation-execution", "design-pair-implementation-execution", "plan-coverage-residual-flow"]);
            }
            if (IsCanonicalOrManifest(path, "design-pair-implementation-execution") || path == "apm-packages/design-pair-implementation-execution/scripts/validate-dp-apm-smoke.ps1")
            {
                distribution.Add("design-pair-implementation-execution");
            }
            if (IsCanonicalOrManifest(path, "plan-coverage-residual-flow") || path == "apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1")
            {
                distribution.Add("plan-coverage-residual-flow");
            }

            if (path.StartsWith("scripts/agent-plugins/", StringComparison.Ordinal) ||
                path.StartsWith("tests/agent-plugins/", StringComparison.Ordinal) ||
                path == ".github/workflows/validate-agent-plugin-packages.yml")
            {
                agentPlugins.UnionWith(PortablePackages);
                continue;
            }

            foreach (var package in PortablePackages)
            {
                if (IsCanonicalOrManifest(path, package) || path.StartsWith($"apm-packages/{package}/tests/agent-plugin/", StringComparison.Ordinal))
                {
                    agentPlugins.Add(package);
                }
            }

            var planCanonical = IsCanonicalOrManifest(path, "plan-coverage-residual-flow");
            if (planCanonical ||
                path == ".github/workflows/validate-plan-coverage-residual-flow.yml" ||
                path == "apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-full-coverage-e2e.ps1" ||
                path.StartsWith("apm-packages/plan-coverage-residual-flow/tests/full-coverage-standalone/", StringComparison.Ordinal))
            {
                planE2E = true;
            }
            if (planCanonical ||
                path == ".github/workflows/validate-plan-coverage-residual-flow.yml" ||
                path == "docs/plan-coverage-runtime-qualification.md" ||
                path.StartsWith("apm-packages/plan-coverage-residual-flow/tests/runtime-qualification/", StringComparison.Ordinal) ||
                path.Contains("plan-coverage-runtime-qualification", StringComparison.Ordinal) ||
                path.EndsWith("PlanCoverageRuntimeQualification.Common.ps1", StringComparison.Ordinal) ||
                path == "apm-packages/plan-coverage-residual-flow/scripts/plan-coverage-copilot-scenario-lib.ps1" ||
                path == "apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1")
            {
                planRuntimeEvidence = true;
            }
            if (planCanonical ||
                path == ".github/workflows/validate-plan-coverage-residual-flow.yml" ||
                path == "docs/plan-coverage-agent-plugin-poc.md" ||
                path == "docs/agent-plugin-adoption-strategy.md" ||
                path.StartsWith("apm-packages/plan-coverage-residual-flow/tests/agent-plugin-poc/", StringComparison.Ordinal) ||
                (path.StartsWith("apm-packages/plan-coverage-residual-flow/scripts/", StringComparison.Ordinal) &&
                    (path.Contains("agent-plugin", StringComparison.OrdinalIgnoreCase) || path.EndsWith("PlanCoverageAgentPlugin.Common.ps1", StringComparison.Ordinal))))
            {
                planPluginPoc = true;
            }
        }

        return new ValidationScope(distribution.Order(StringComparer.Ordinal).ToArray(), agentPlugins.Order(StringComparer.Ordinal).ToArray(), planE2E, planRuntimeEvidence, planPluginPoc);
    }

    private static bool IsCanonicalOrManifest(string path, string package) =>
        path == $"apm-packages/{package}/apm.yml" || path.StartsWith($"apm-packages/{package}/.apm/", StringComparison.Ordinal);

    private static async Task<string[]> GetChangedPathsAsync(string repositoryRoot, string baseSha, string headSha)
    {
        var zeroSha = new string('0', 40);
        var arguments = baseSha == zeroSha
            ? new[] { "diff-tree", "--root", "--no-commit-id", "--name-only", "-r", headSha }
            : new[] { "diff", "--name-only", $"{baseSha}...{headSha}" };
        var output = await RunGitAsync(repositoryRoot, arguments);
        return output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(NormalizePath)
            .ToArray();
    }

    private static async Task<string> RunGitAsync(string repositoryRoot, string[] arguments)
    {
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo("git")
        {
            WorkingDirectory = repositoryRoot,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };
        foreach (var argument in arguments)
        {
            process.StartInfo.ArgumentList.Add(argument);
        }
        process.Start();
        var stdout = await process.StandardOutput.ReadToEndAsync();
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"git {string.Join(' ', arguments)} failed with exit code {process.ExitCode}: {stderr}");
        }
        return stdout;
    }

    private static void WriteScope(ValidationScope scope, string githubOutputPath)
    {
        var distributionMatrix = JsonSerializer.Serialize(new { package = scope.DistributionPackages });
        var agentPluginMatrix = JsonSerializer.Serialize(new { package = scope.AgentPluginPackages });
        File.AppendAllLines(githubOutputPath,
        [
            $"has_distribution={(scope.DistributionPackages.Length > 0).ToString().ToLowerInvariant()}",
            $"distribution_matrix={distributionMatrix}",
            $"has_agent_plugins={(scope.AgentPluginPackages.Length > 0).ToString().ToLowerInvariant()}",
            $"agent_plugin_matrix={agentPluginMatrix}",
            $"plan_e2e={scope.PlanE2E.ToString().ToLowerInvariant()}",
            $"plan_runtime_evidence={scope.PlanRuntimeEvidence.ToString().ToLowerInvariant()}",
            $"plan_plugin_poc={scope.PlanPluginPoc.ToString().ToLowerInvariant()}"
        ]);
        Console.WriteLine($"Distribution packages: {string.Join(',', scope.DistributionPackages)}");
        Console.WriteLine($"Agent Plugin packages: {string.Join(',', scope.AgentPluginPackages)}");
    }

    private static string GetRepositoryRoot()
    {
        var current = new DirectoryInfo(Directory.GetCurrentDirectory());
        while (current is not null)
        {
            if (File.Exists(Path.Combine(current.FullName, ".git")) || Directory.Exists(Path.Combine(current.FullName, ".git")))
            {
                return current.FullName;
            }
            current = current.Parent;
        }
        throw new DirectoryNotFoundException("Repository root was not found from the current directory.");
    }

    private static string Read(string repositoryRoot, string relativePath)
    {
        var fullPath = Path.Combine(repositoryRoot, relativePath.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(fullPath))
        {
            throw new FileNotFoundException($"Required file was not found: {relativePath}", fullPath);
        }
        return File.ReadAllText(fullPath).Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
    }

    private static void Require(string text, string pattern, string message, List<string> failures)
    {
        if (!Regex.IsMatch(text, pattern, RegexOptions.CultureInvariant))
        {
            failures.Add(message);
        }
    }

    private static void Reject(string text, string pattern, string message, List<string> failures)
    {
        if (Regex.IsMatch(text, pattern, RegexOptions.CultureInvariant))
        {
            failures.Add(message);
        }
    }

    private static void RequireOccurrences(string text, string value, int expectedCount, string message, List<string> failures)
    {
        if (Regex.Matches(text, Regex.Escape(value), RegexOptions.CultureInvariant).Count < expectedCount)
        {
            failures.Add(message);
        }
    }

    private static string NormalizePath(string path)
    {
        var normalized = path.Replace('\\', '/');
        return normalized.StartsWith("./", StringComparison.Ordinal) ? normalized[2..] : normalized;
    }

    private sealed record ValidationScope(string[] DistributionPackages, string[] AgentPluginPackages, bool PlanE2E, bool PlanRuntimeEvidence, bool PlanPluginPoc);
}
