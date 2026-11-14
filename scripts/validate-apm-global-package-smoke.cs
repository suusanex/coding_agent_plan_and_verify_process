#:property TargetFramework=net10.0
#:property PublishAot=false
#:package Tomlyn@2.10.1

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Tomlyn;
using Tomlyn.Model;

return await GlobalPackageSmoke.RunAsync(args);

internal static class GlobalPackageSmoke
{
    private static readonly string[] RequiredPackages =
    [
        "adaptive-implementation-execution",
        "design-pair-implementation-execution",
        "plan-coverage-residual-flow",
        "pr-review-remediation",
        "goal-context-authoring",
        "persistent-purpose-review"
    ];

    public static async Task<int> RunAsync(string[] args)
    {
        string? scratch = null;
        try
        {
            if (args is ["--help"])
            {
                Console.WriteLine("Usage: dotnet run --file scripts/validate-apm-global-package-smoke.cs -- --package <name> --repository <owner/repository> --ref <commit-sha-or-branch> [--update-ref <branch>] [--apm <path>]");
                return 0;
            }

            var options = ParseArguments(args);
            if (!RequiredPackages.Contains(options.Package, StringComparer.Ordinal))
            {
                throw new ArgumentException($"Unsupported global package smoke target: {options.Package}");
            }

            scratch = Path.Combine(Path.GetTempPath(), "apm-global-smoke-" + Guid.NewGuid().ToString("N"));
            var userHome = Path.Combine(scratch, "user");
            var codexHome = Path.Combine(userHome, ".codex");
            var copilotHome = Path.Combine(userHome, ".copilot");
            var appData = Path.Combine(scratch, "appdata");
            var localAppData = Path.Combine(scratch, "local-appdata");
            var dotnetHome = Path.Combine(scratch, "dotnet-home");
            var nugetPackages = Path.Combine(scratch, "nuget-packages");
            var nugetHttpCache = Path.Combine(scratch, "nuget-http-cache");
            foreach (var directory in new[] { userHome, codexHome, copilotHome, appData, localAppData, dotnetHome, nugetPackages, nugetHttpCache })
            {
                Directory.CreateDirectory(directory);
            }

            var protectedFiles = CreateProtectedFiles(userHome, scratch);

            var environment = new Dictionary<string, string?>
            {
                ["HOME"] = userHome,
                ["USERPROFILE"] = userHome,
                ["CODEX_HOME"] = null,
                ["COPILOT_HOME"] = null,
                ["APM_HOME"] = null,
                ["XDG_CONFIG_HOME"] = null,
                ["XDG_DATA_HOME"] = null,
                ["APPDATA"] = appData,
                ["LOCALAPPDATA"] = localAppData,
                ["DOTNET_CLI_HOME"] = dotnetHome,
                ["NUGET_PACKAGES"] = nugetPackages,
                ["NUGET_HTTP_CACHE_PATH"] = nugetHttpCache,
                ["GIT_TERMINAL_PROMPT"] = "0",
                ["APM_NO_SCRIPTS"] = "1",
                ["APM_LOG_LEVEL"] = "INFO"
            };

            var apmVersion = await RunProcessAsync(options.ApmExecutable, ["--version"], scratch, environment, "version check");
            if (!Regex.IsMatch(apmVersion, @"\b0\.26\.0\b", RegexOptions.CultureInvariant))
            {
                throw new InvalidOperationException($"This smoke requires APM 0.26.0. Actual version output: {apmVersion.Trim()}");
            }

            var candidateSha = await ResolveCandidateShaAsync(options, scratch, environment);
            var updateRef = string.IsNullOrWhiteSpace(options.UpdateRef)
                ? IsFullSha(options.Ref) ? throw new ArgumentException("--update-ref is required when --ref is a commit SHA.") : options.Ref
                : options.UpdateRef;
            options = options with { CandidateSha = candidateSha, UpdateRef = updateRef };

            var candidatePackageSpec = $"{options.Repository}/apm-packages/{options.Package}#{options.CandidateSha}";
            await RunIndependentTargetSmokeAsync(options, candidatePackageSpec, scratch, environment, "codex");
            await RunIndependentTargetSmokeAsync(options, candidatePackageSpec, scratch, environment, "copilot");
            await RunIndependentTargetSmokeAsync(options, candidatePackageSpec, scratch, environment, "agent-skills");
            await VerifyUpdateRefAsync(options, scratch, environment, "before mixed lifecycle install");
            var updatePackageSpec = $"{options.Repository}/apm-packages/{options.Package}#{options.UpdateRef}";
            await RunProcessAsync(options.ApmExecutable,
                ["install", updatePackageSpec, "--global", "--target", "codex,copilot,agent-skills", "--https", "--no-audit"],
                scratch, environment, "global install");

            var apmHome = Path.Combine(userHome, ".apm");
            var moduleRoot = Path.Combine(apmHome, "apm_modules");
            var lockPath = Path.Combine(apmHome, "apm.lock.yaml");
            if (!File.Exists(lockPath))
            {
                throw new InvalidOperationException($"Global APM lockfile was not created: {lockPath}");
            }

            var installedPackage = FindInstalledPackage(moduleRoot, options.Package);
            VerifyPrimitiveProjections(installedPackage, userHome, codexHome, copilotHome);
            VerifyPackageClosure(lockPath, options.Package);
            VerifyDependencyArtifacts(moduleRoot, userHome, options.Package);
            VerifyProtectedFiles(protectedFiles, scratch);

            string? finalizer = null;
            if (InstalledPackageExists(moduleRoot, "codex-profile-finalizer"))
            {
                var finalizerPackage = FindInstalledPackage(moduleRoot, "codex-profile-finalizer");
                finalizer = Path.Combine(finalizerPackage, "scripts", "finalize-codex-agent-profiles.cs");
                if (!File.Exists(finalizer))
                {
                    throw new InvalidOperationException($"Installed Finalizer package is missing its documented script path: {finalizer}");
                }
            }
            if (finalizer is not null)
            {
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global"], scratch, environment, "global Codex profile completion");
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global", "--check"], scratch, environment, "global Codex profile check");
                var firstCompletionHashes = CaptureCodexAgentHashes(codexHome);
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global"], scratch, environment, "global Codex profile idempotency re-run");
                var repeatedCompletionHashes = CaptureCodexAgentHashes(codexHome);
                VerifyIdenticalHashes(firstCompletionHashes, repeatedCompletionHashes, "Finalizer re-run");
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global", "--check"], scratch, environment, "global Codex profile check after idempotency re-run");
                Console.WriteLine($"Installed Finalizer script: {Path.GetRelativePath(apmHome, finalizer)}");
            }

            if (options.Package == "plan-coverage-residual-flow")
            {
                VerifyPlanCoverageSharedGuardrails(installedPackage, userHome);
            }

            if (options.Package == "plan-coverage-residual-flow")
            {
                var checkoutRoot = GetCheckoutRoot();
                var e2eScript = Path.Combine(checkoutRoot, "apm-packages", options.Package, "scripts", "validate-plan-coverage-full-coverage-e2e.ps1");
                await RunProcessAsync("pwsh", ["-File", e2eScript, "-InstalledRoot", userHome], scratch, environment, "global installed Plan Coverage full-coverage E2E");
            }

            var profilesBeforeReinstall = CaptureCodexAgentHashes(codexHome);
            await RunProcessAsync(options.ApmExecutable,
                ["install", "--global", "--target", "codex,copilot,agent-skills", "--frozen"],
                scratch, environment, "global reinstall");
            if (finalizer is not null)
            {
                var profilesAfterReinstall = CaptureCodexAgentHashes(codexHome);
                var changedProfiles = FindChangedHashes(profilesBeforeReinstall, profilesAfterReinstall);
                Console.WriteLine(changedProfiles.Length == 0
                    ? "APM frozen reinstall preserved all Codex agent profile hashes."
                    : $"APM frozen reinstall changed Codex agent profile hashes: {string.Join(", ", changedProfiles)}");
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global"], scratch, environment, "global Codex profile completion after reinstall");
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global", "--check"], scratch, environment, "global Codex profile check after reinstall completion");
            }

            await RunProcessAsync(options.ApmExecutable,
                ["update", "--global", "--yes", "--target", "codex,copilot,agent-skills"],
                scratch, environment, "global update");
            await VerifyUpdateRefAsync(options, scratch, environment, "after global update");
            if (finalizer is not null)
            {
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global"], scratch, environment, "global Codex profile completion after update");
                await RunProcessAsync("dotnet", ["run", "--file", finalizer, "--", "--global", "--check"], scratch, environment, "global Codex profile re-check");
            }

            foreach (var workRepository in new[] { "work-repository-a", "work-repository-b" })
            {
                var workRoot = Path.Combine(scratch, workRepository);
                Directory.CreateDirectory(workRoot);
                var resolvedWorkRoot = Path.GetFullPath(workRoot);
                await RunProcessAsync("git", ["-C", resolvedWorkRoot, "init", "--quiet"], scratch, environment, $"temporary {workRepository} initialization");
                var discoveredRoot = (await RunProcessAsync("git", ["-C", resolvedWorkRoot, "rev-parse", "--show-toplevel"], scratch, environment, $"temporary {workRepository} root verification")).Trim();
                if (!string.Equals(Path.GetFullPath(discoveredRoot), resolvedWorkRoot, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException($"Git identified an unexpected temporary workspace root: {discoveredRoot}");
                }

                var dependencies = await RunProcessAsync(options.ApmExecutable, ["deps", "list", "--global"], workRoot, environment, $"global package discovery from {workRepository}");
                if (!dependencies.Contains("APM Dependencies (Global)", StringComparison.Ordinal) ||
                    !dependencies.Contains("github", StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidOperationException($"Global APM dependency listing did not report GitHub package metadata from {workRepository}.");
                }

                VerifyNoProjectLocalProjections(workRoot);
                VerifyPrimitiveProjections(installedPackage, userHome, codexHome, copilotHome);
            }

            Console.WriteLine("Global package metadata and user-scope projections were observed from two workspaces; no runtime agent process was launched.");

            await RunProcessAsync(options.ApmExecutable,
                ["uninstall", updatePackageSpec, "--global"], scratch, environment, "global uninstall");
            await VerifyUpdateRefAsync(options, scratch, environment, "after global uninstall");
            if (Directory.Exists(installedPackage))
            {
                throw new InvalidOperationException($"Global uninstall retained package files: {installedPackage}");
            }

            VerifyProtectedFiles(protectedFiles, scratch);
            Console.WriteLine($"APM global package smoke passed: {options.Package}");
            return 0;
        }
        catch (Exception exception)
        {
            Trace.WriteLine(exception.ToString());
            Console.Error.WriteLine(exception.ToString());
            return 1;
        }
        finally
        {
            if (scratch is not null && Directory.Exists(scratch))
            {
                var tempRoot = Path.GetFullPath(Path.GetTempPath());
                var resolvedScratch = Path.GetFullPath(scratch);
                if (!resolvedScratch.StartsWith(Path.Combine(tempRoot, "apm-global-smoke-"), StringComparison.OrdinalIgnoreCase))
                {
                    var exception = new InvalidOperationException($"Refusing to remove a smoke directory outside its generated temp root: {resolvedScratch}");
                    Trace.WriteLine(exception.ToString());
                    throw exception;
                }
                else
                {
                    try
                    {
                        ResetReadOnlyAttributesForCleanup(resolvedScratch);
                        Directory.Delete(resolvedScratch, recursive: true);
                    }
                    catch (Exception exception)
                    {
                        Trace.WriteLine(exception.ToString());
                        throw;
                    }
                }
            }
        }
    }

    private static SmokeOptions ParseArguments(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var index = 0; index < args.Length; index++)
        {
            if (args[index] is not ("--package" or "--repository" or "--ref" or "--update-ref" or "--apm"))
            {
                throw new ArgumentException($"Unknown argument: {args[index]}");
            }

            if (++index >= args.Length || args[index].StartsWith("--", StringComparison.Ordinal))
            {
                throw new ArgumentException($"Missing value for {args[index - 1]}");
            }

            if (args[index - 1] == "--help")
            {
                throw new ArgumentException("--help does not accept a value.");
            }

            values[args[index - 1]] = args[index];
        }

        foreach (var required in new[] { "--package", "--repository", "--ref" })
        {
            if (!values.TryGetValue(required, out var value) || string.IsNullOrWhiteSpace(value))
            {
                throw new ArgumentException($"Required argument is missing: {required}");
            }
        }

        if (!Regex.IsMatch(values["--repository"], @"^[^/]+/[^/]+$", RegexOptions.CultureInvariant) || values["--ref"].Contains('#') ||
            values.GetValueOrDefault("--update-ref", "").Contains('#'))
        {
            throw new ArgumentException("Repository must be owner/repository and refs must not contain '#'.");
        }

        return new SmokeOptions(values["--package"], values["--repository"], values["--ref"], values.GetValueOrDefault("--update-ref", ""), "", values.GetValueOrDefault("--apm", "apm"));
    }

    private static async Task<string> RunProcessAsync(string fileName, IReadOnlyList<string> arguments, string workingDirectory,
        IReadOnlyDictionary<string, string?> environment, string description)
    {
        var startInfo = new ProcessStartInfo(fileName)
        {
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        foreach (var (key, value) in environment)
        {
            startInfo.Environment[key] = value;
        }

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Could not start {fileName}.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        var output = await stdoutTask;
        var error = await stderrTask;
        if (!string.IsNullOrWhiteSpace(output)) Console.Write(output);
        if (!string.IsNullOrWhiteSpace(error)) Console.Error.Write(error);
        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"APM {description} failed with exit code {process.ExitCode}.");
        }

        return output;
    }

    private static async Task<string> ResolveCandidateShaAsync(SmokeOptions options, string scratch,
        IReadOnlyDictionary<string, string?> environment)
    {
        if (IsFullSha(options.Ref))
        {
            return options.Ref.ToLowerInvariant();
        }

        return await GetRemoteBranchShaAsync(options.Repository, options.Ref, scratch, environment);
    }

    private static async Task VerifyUpdateRefAsync(SmokeOptions options, string scratch,
        IReadOnlyDictionary<string, string?> environment, string phase)
    {
        var branchSha = await GetRemoteBranchShaAsync(options.Repository, options.UpdateRef, scratch, environment);
        if (!string.Equals(branchSha, options.CandidateSha, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Update branch {options.UpdateRef} for {phase} resolves to {branchSha}, expected candidate SHA {options.CandidateSha}.");
        }

        Console.WriteLine($"Update branch identity verified for {phase}: {options.UpdateRef} -> {options.CandidateSha}.");
    }

    private static async Task<string> GetRemoteBranchShaAsync(string repository, string branch, string scratch,
        IReadOnlyDictionary<string, string?> environment)
    {
        await RunProcessAsync("git", ["check-ref-format", "--branch", branch], scratch, environment, "update branch validation");
        var remote = $"https://github.com/{repository}.git";
        var output = await RunProcessAsync("git", ["ls-remote", "--heads", remote, $"refs/heads/{branch}"], scratch, environment, "remote update branch lookup");
        var matches = output.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .Select(line => line.Split('\t'))
            .Where(fields => fields.Length == 2 && fields[1] == $"refs/heads/{branch}")
            .ToArray();
        if (matches.Length != 1 || !Regex.IsMatch(matches[0][0], @"^[0-9a-fA-F]{40}$", RegexOptions.CultureInvariant))
        {
            throw new InvalidOperationException($"Remote branch {branch} was not found uniquely in {repository}.");
        }

        return matches[0][0].ToLowerInvariant();
    }

    private static bool IsFullSha(string value) => Regex.IsMatch(value, @"^[0-9a-fA-F]{40}$", RegexOptions.CultureInvariant);

    private static SortedDictionary<string, string> CaptureCodexAgentHashes(string codexHome)
    {
        var agentsDirectory = Path.Combine(codexHome, "agents");
        var hashes = new SortedDictionary<string, string>(StringComparer.Ordinal);
        if (!Directory.Exists(agentsDirectory))
        {
            return hashes;
        }

        foreach (var file in Directory.EnumerateFiles(agentsDirectory, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(agentsDirectory, file).Replace('\\', '/');
            hashes.Add(relative, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))));
        }

        return hashes;
    }

    private static void VerifyIdenticalHashes(IReadOnlyDictionary<string, string> expected, IReadOnlyDictionary<string, string> actual, string phase)
    {
        var changed = FindChangedHashes(expected, actual);
        if (changed.Length > 0)
        {
            throw new InvalidOperationException($"Codex agent profile hashes changed during {phase}: {string.Join(", ", changed)}");
        }
    }

    private static string[] FindChangedHashes(IReadOnlyDictionary<string, string> before, IReadOnlyDictionary<string, string> after) =>
        before.Keys.Union(after.Keys, StringComparer.Ordinal)
            .Where(path => !before.TryGetValue(path, out var beforeHash) || !after.TryGetValue(path, out var afterHash) || beforeHash != afterHash)
            .Order(StringComparer.Ordinal)
            .ToArray();

    private static void ResetReadOnlyAttributesForCleanup(string scratch)
    {
        var resolvedScratch = Path.GetFullPath(scratch);
        foreach (var path in Directory.EnumerateFileSystemEntries(resolvedScratch, "*", SearchOption.AllDirectories))
        {
            var resolvedPath = Path.GetFullPath(path);
            if (!resolvedPath.StartsWith(resolvedScratch + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException($"Refusing to change attributes outside the generated smoke directory: {resolvedPath}");
            }

            var attributes = File.GetAttributes(resolvedPath);
            if ((attributes & FileAttributes.ReparsePoint) == 0 && (attributes & FileAttributes.ReadOnly) != 0)
            {
                File.SetAttributes(resolvedPath, attributes & ~FileAttributes.ReadOnly);
            }
        }
    }

    private static string FindInstalledPackage(string moduleRoot, string packageName)
    {
        foreach (var manifest in Directory.EnumerateFiles(moduleRoot, "apm.yml", SearchOption.AllDirectories))
        {
            var content = File.ReadAllText(manifest);
            if (Regex.IsMatch(content, $"(?m)^name:\\s*{Regex.Escape(packageName)}\\s*$", RegexOptions.CultureInvariant))
            {
                return Path.GetDirectoryName(manifest)!;
            }
        }

        throw new InvalidOperationException($"Global APM module does not contain package {packageName}.");
    }

    private static bool InstalledPackageExists(string moduleRoot, string packageName) =>
        Directory.EnumerateFiles(moduleRoot, "apm.yml", SearchOption.AllDirectories)
            .Any(manifest => Regex.IsMatch(File.ReadAllText(manifest), $"(?m)^name:\\s*{Regex.Escape(packageName)}\\s*$", RegexOptions.CultureInvariant));

    private static string GetCheckoutRoot([CallerFilePath] string sourcePath = "") =>
        Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourcePath)!, ".."));

    private static void VerifyPrimitiveProjections(string packageRoot, string userHome, string codexHome, string copilotHome, string? target = null)
    {
        var primitiveRoot = Path.Combine(packageRoot, ".apm");
        var sourceSkills = Path.Combine(primitiveRoot, "skills");
        if (Directory.Exists(sourceSkills))
        {
            var skillDirectories = Directory.EnumerateDirectories(sourceSkills).ToArray();
            if (skillDirectories.Length == 0)
            {
                throw new InvalidOperationException($"Global package has an empty Skill source directory: {sourceSkills}");
            }

            foreach (var sourceSkill in skillDirectories)
            {
                var skillName = Path.GetFileName(sourceSkill);
                var deployedSkill = Path.Combine(userHome, ".agents", "skills", skillName);
                AssertDirectoryContentEqual(sourceSkill, deployedSkill, $"Agent Skill {skillName}");
            }
        }

        var sourceAgents = Path.Combine(primitiveRoot, "agents");
        if (Directory.Exists(sourceAgents) && target is not "agent-skills")
        {
            foreach (var sourceAgent in Directory.EnumerateFiles(sourceAgents, "*.agent.md"))
            {
                var fileName = Path.GetFileName(sourceAgent);
                var copilotPath = Path.Combine(copilotHome, "agents", fileName);
                var codexName = Path.GetFileNameWithoutExtension(Path.GetFileNameWithoutExtension(fileName)) + ".toml";
                var codexPath = Path.Combine(codexHome, "agents", codexName);
                if (target is null or "copilot" && !File.Exists(copilotPath))
                {
                    throw new InvalidOperationException($"Global Copilot agent projection is missing: {fileName}");
                }
                if (target is null or "copilot" && !string.Equals(NormalizeText(File.ReadAllText(sourceAgent)), NormalizeText(File.ReadAllText(copilotPath)), StringComparison.Ordinal))
                {
                    throw new InvalidOperationException($"Global Copilot agent projection differs from package source: {fileName}");
                }

                if (target is null or "codex" && !File.Exists(codexPath))
                {
                    throw new InvalidOperationException($"Global Codex agent profile is missing: {codexName}");
                }
            }
        }
    }

    private static async Task RunIndependentTargetSmokeAsync(SmokeOptions options, string packageSpec, string scratch,
        IReadOnlyDictionary<string, string?> baseEnvironment, string target)
    {
        var targetHome = Path.Combine(scratch, "target-" + target);
        Directory.CreateDirectory(targetHome);
        var environment = baseEnvironment.ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.Ordinal);
        environment["HOME"] = targetHome;
        environment["USERPROFILE"] = targetHome;
        await RunProcessAsync(options.ApmExecutable,
            ["install", packageSpec, "--global", "--target", target, "--https", "--no-audit"],
            scratch, environment, $"independent {target} global install");

        var packageRoot = FindInstalledPackage(Path.Combine(targetHome, ".apm", "apm_modules"), options.Package);
        VerifyPrimitiveProjections(packageRoot, targetHome, Path.Combine(targetHome, ".codex"), Path.Combine(targetHome, ".copilot"), target);
        VerifyPackageClosure(Path.Combine(targetHome, ".apm", "apm.lock.yaml"), options.Package);
    }

    private static void VerifyPackageClosure(string lockPath, string packageName)
    {
        var lockText = File.ReadAllText(lockPath);
        var packages = Regex.Matches(lockText, @"(?m)^\s*(?:-\s*)?name:\s*(?<name>[A-Za-z0-9._-]+)\s*$", RegexOptions.CultureInvariant)
            .Select(match => match.Groups["name"].Value)
            .ToHashSet(StringComparer.Ordinal);
        if (!packages.Contains(packageName))
        {
            throw new InvalidOperationException($"APM lockfile does not include direct package {packageName}.");
        }

        if (packageName is "design-pair-implementation-execution" or "plan-coverage-residual-flow")
        {
            foreach (var dependency in new[] { "adaptive-implementation-execution", "codex-profile-finalizer" })
            {
                if (!packages.Contains(dependency))
                {
                    throw new InvalidOperationException($"APM lockfile for {packageName} does not include transitive package {dependency}.");
                }
            }
        }

        if (packageName == "pr-review-remediation")
        {
            foreach (var forbidden in new[] { "adaptive-implementation-execution", "codex-profile-finalizer" })
            {
                if (packages.Contains(forbidden))
                {
                    throw new InvalidOperationException($"Standalone PR Review install unexpectedly includes {forbidden}.");
                }
            }
        }
    }

    private static void VerifyDependencyArtifacts(string moduleRoot, string userHome, string packageName)
    {
        if (packageName is "design-pair-implementation-execution" or "plan-coverage-residual-flow" or "adaptive-implementation-execution")
        {
            var adaptive = FindInstalledPackage(moduleRoot, "adaptive-implementation-execution");
            var adaptivePrimitiveRoot = Path.Combine(adaptive, ".apm");
            var skillRoot = Path.Combine(adaptivePrimitiveRoot, "skills", "adaptive-implementation-execution");
            var agentsRoot = Path.Combine(adaptivePrimitiveRoot, "agents");
            var overlayPath = Path.Combine(adaptive, "codex-profile-overlays.json");
            var finalizerPackageExists = InstalledPackageExists(moduleRoot, "codex-profile-finalizer");
            var finalizerPath = finalizerPackageExists
                ? Path.Combine(FindInstalledPackage(moduleRoot, "codex-profile-finalizer"), "scripts", "finalize-codex-agent-profiles.cs")
                : null;
            if (!File.Exists(Path.Combine(skillRoot, "SKILL.md")) ||
                !File.Exists(Path.Combine(agentsRoot, "decision-surface-implementation-owner.agent.md")) ||
                !File.Exists(Path.Combine(agentsRoot, "bounded-residual-implementation-owner.agent.md")) ||
                !File.Exists(overlayPath) || finalizerPath is null)
            {
                throw new InvalidOperationException($"Global {packageName} dependency closure is missing Adaptive or Finalizer package assets.");
            }

            AssertDirectoryContentEqual(skillRoot, Path.Combine(userHome, ".agents", "skills", "adaptive-implementation-execution"), "Adaptive Agent Skill");
            foreach (var agent in new[] { "decision-surface-implementation-owner", "bounded-residual-implementation-owner" })
            {
                if (!File.Exists(Path.Combine(userHome, ".copilot", "agents", agent + ".agent.md")) ||
                    !File.Exists(Path.Combine(userHome, ".codex", "agents", agent + ".toml")))
                {
                    throw new InvalidOperationException($"Global {packageName} install is missing Adaptive runtime agent projection {agent}.");
                }
            }
        }

        if (packageName == "pr-review-remediation")
        {
            foreach (var forbidden in new[] { "adaptive-implementation-execution", "codex-profile-finalizer" })
            {
                if (InstalledPackageExists(moduleRoot, forbidden))
                {
                    throw new InvalidOperationException($"Standalone PR Review install unexpectedly materialized {forbidden}.");
                }
            }

            foreach (var agentName in new[] { "review-planner.agent.md", "review-planner.toml" })
            {
                var agentRoot = agentName.EndsWith(".toml", StringComparison.Ordinal)
                    ? Path.Combine(userHome, ".codex", "agents")
                    : Path.Combine(userHome, ".copilot", "agents");
                if (File.Exists(Path.Combine(agentRoot, agentName)))
                {
                    throw new InvalidOperationException("Standalone PR Review install unexpectedly deployed its retired agent profile.");
                }
            }
        }
    }

    private static void VerifyPlanCoverageSharedGuardrails(string packageRoot, string userHome)
    {
        const string startMarker = "<!-- plan-coverage-shared:start -->";
        const string endMarker = "<!-- plan-coverage-shared:end -->";
        var canonicalPath = Path.Combine(packageRoot, "docs", "plan-coverage-shared-guardrails.md");
        if (!File.Exists(canonicalPath))
        {
            throw new InvalidOperationException($"Installed Plan Coverage package is missing canonical shared guardrails: {canonicalPath}");
        }

        var expectedGuardrails = NormalizeText(File.ReadAllText(canonicalPath)).Trim();
        var agentsRoot = Path.Combine(packageRoot, ".apm", "agents");
        var sourceAgents = Directory.EnumerateFiles(agentsRoot, "*.agent.md", SearchOption.TopDirectoryOnly).ToArray();
        var markedAgents = new List<string>();
        foreach (var sourceAgent in sourceAgents)
        {
            var content = File.ReadAllText(sourceAgent);
            var hasStart = content.Contains(startMarker, StringComparison.Ordinal);
            var hasEnd = content.Contains(endMarker, StringComparison.Ordinal);
            if (hasStart != hasEnd)
            {
                throw new InvalidOperationException($"Plan Coverage source agent has an incomplete shared guardrail marker pair: {sourceAgent}");
            }

            if (hasStart)
            {
                markedAgents.Add(sourceAgent);
            }
        }

        if (markedAgents.Count != 14)
        {
            throw new InvalidOperationException($"Expected fourteen marker-owned Plan Coverage agents; found {markedAgents.Count} under {agentsRoot}.");
        }

        foreach (var sourceAgent in markedAgents)
        {
            var name = Path.GetFileName(sourceAgent);
            var copilotProjection = Path.Combine(userHome, ".copilot", "agents", name);
            var codexName = Path.GetFileNameWithoutExtension(Path.GetFileNameWithoutExtension(name)) + ".toml";
            var codexProjection = Path.Combine(userHome, ".codex", "agents", codexName);
            if (!File.Exists(copilotProjection) || !File.Exists(codexProjection))
            {
                throw new InvalidOperationException($"Global Plan Coverage projections are incomplete for {name}.");
            }

            var canonicalAgent = File.ReadAllText(sourceAgent);
            if (!string.Equals(NormalizeText(canonicalAgent), NormalizeText(File.ReadAllText(copilotProjection)), StringComparison.Ordinal))
            {
                throw new InvalidOperationException($"Global Copilot Plan Coverage agent differs from its installed package source: {name}");
            }

            AssertSharedGuardrailBlock(canonicalAgent, expectedGuardrails, startMarker, endMarker, $"source agent {name}");
            AssertSharedGuardrailBlock(ReadCodexDeveloperInstructions(codexProjection), expectedGuardrails, startMarker, endMarker, $"Codex profile {codexName}");
        }
    }

    private static string ReadCodexDeveloperInstructions(string path)
    {
        var table = TomlSerializer.Deserialize<TomlTable>(File.ReadAllText(path))
            ?? throw new InvalidOperationException($"Codex profile deserialized to null: {path}");
        if (!table.TryGetValue("developer_instructions", out var value) || value is not string developerInstructions)
        {
            throw new InvalidOperationException($"Codex profile has no supported developer_instructions string: {path}");
        }

        return developerInstructions;
    }

    private static void AssertSharedGuardrailBlock(string text, string expectedGuardrails, string startMarker, string endMarker, string purpose)
    {
        var start = text.IndexOf(startMarker, StringComparison.Ordinal);
        var end = text.IndexOf(endMarker, StringComparison.Ordinal);
        if (start < 0 || end <= start || text.LastIndexOf(startMarker, StringComparison.Ordinal) != start || text.LastIndexOf(endMarker, StringComparison.Ordinal) != end)
        {
            throw new InvalidOperationException($"{purpose} has missing, duplicate, or misordered shared guardrail markers.");
        }

        var blockStart = start + startMarker.Length;
        var block = NormalizeText(text[blockStart..end]).Trim();
        if (!string.Equals(block, expectedGuardrails, StringComparison.Ordinal))
        {
            throw new InvalidOperationException($"{purpose} shared guardrail contents differ from the installed canonical source.");
        }
    }

    private static string NormalizeText(string text) => text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');

    private static void AssertDirectoryContentEqual(string source, string destination, string description)
    {
        if (!Directory.Exists(destination))
        {
            throw new InvalidOperationException($"Global {description} projection is missing: {destination}");
        }

        foreach (var sourceFile in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(source, sourceFile);
            var destinationFile = Path.Combine(destination, relative);
            if (!File.Exists(destinationFile) || !string.Equals(NormalizeText(File.ReadAllText(sourceFile)), NormalizeText(File.ReadAllText(destinationFile)), StringComparison.Ordinal))
            {
                throw new InvalidOperationException($"Global {description} projection differs or is missing: {relative}");
            }
        }
    }

    private static IReadOnlyDictionary<string, string> CreateProtectedFiles(string userHome, string scratch)
    {
        var sentinels = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            [Path.Combine(userHome, "AGENTS.md")] = "global-smoke-agents-sentinel",
            [Path.Combine(userHome, ".codex", "config.toml")] = "global-smoke-codex-config-sentinel",
            [Path.Combine(userHome, ".codex", "agents", "global-smoke-unrelated-agent.toml")] = "global-smoke-unrelated-codex-agent-sentinel",
            [Path.Combine(userHome, ".copilot", "copilot-instructions.md")] = "global-smoke-copilot-instructions-sentinel",
            [Path.Combine(userHome, ".copilot", "agents", "global-smoke-unrelated-agent.agent.md")] = "global-smoke-unrelated-copilot-agent-sentinel"
        };

        foreach (var (path, value) in sentinels)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, value, new UTF8Encoding(false));
        }

        return sentinels;
    }

    private static void VerifyProtectedFiles(IReadOnlyDictionary<string, string> sentinels, string scratch)
    {
        foreach (var (path, value) in sentinels)
        {
            if (File.ReadAllText(path) != value)
            {
                throw new InvalidOperationException($"Global package lifecycle changed a protected user file: {Path.GetRelativePath(scratch, path)}");
            }
        }
    }

    private static void VerifyNoProjectLocalProjections(string workRoot)
    {
        foreach (var relativePath in new[] { "apm_modules", ".agents/skills", ".github/agents", ".copilot/agents", ".codex/agents" })
        {
            var path = Path.Combine(workRoot, relativePath);
            if (Directory.Exists(path))
            {
                throw new InvalidOperationException($"Global install created a project-local projection: {Path.GetRelativePath(workRoot, path)}");
            }
        }
    }

    private sealed record SmokeOptions(string Package, string Repository, string Ref, string UpdateRef, string CandidateSha, string ApmExecutable);
}
