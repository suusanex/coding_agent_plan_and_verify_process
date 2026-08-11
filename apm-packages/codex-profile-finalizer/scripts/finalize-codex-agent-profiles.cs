#!/usr/bin/env dotnet
//#:property TargetFramework=net10.0

using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

return await CodexProfileFinalizer.RunAsync(args);

internal static class CodexProfileFinalizer
{
    private static readonly string[] ProfileKeys = ["model", "model_reasoning_effort", "sandbox_mode"];
    private static readonly string[] OverlayEntryKeys = ["agent", "model", "model_reasoning_effort", "sandbox_mode"];
    private static readonly string[] OverlayDocumentKeys = ["schemaVersion", "package", "profiles"];
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly Regex ManifestName = new(@"(?m)^name:\s*(?<value>[^\r\n#]+)", RegexOptions.Compiled);
    private static readonly Regex AgentName = new(@"(?m)^name:\s*(?<value>[^\r\n#]+)", RegexOptions.Compiled);
    private static readonly Regex SafeAgentIdentifier = new("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.Compiled);
    private static readonly Regex TopLevelTomlKey = new("^(?<indent>\\s*)(?<key>[A-Za-z0-9_-]+)\\s*=\\s*\\\"(?<value>(?:\\\\.|[^\\\"\\\\])*)\\\"\\s*$", RegexOptions.Compiled);
    private static readonly Regex Section = new(@"^\s*\[[^\]]+\]\s*$", RegexOptions.Compiled);

    public static async Task<int> RunAsync(string[] args)
    {
        Options options;
        try
        {
            options = Parse(args);
        }
        catch (ArgumentException ex)
        {
            if (string.Equals(ex.Message, "help", StringComparison.Ordinal))
            {
                PrintUsage();
                return 0;
            }

            Console.Error.WriteLine(ex.Message);
            PrintUsage();
            return 2;
        }

        if (!Directory.Exists(options.TargetRoot))
        {
            Console.Error.WriteLine($"Target repository not found: {options.TargetRoot}");
            return 2;
        }

        var overlaysRoot = Path.Combine(options.TargetRoot, "apm_modules");
        if (!Directory.Exists(overlaysRoot))
        {
            Console.WriteLine("No apm_modules directory found; no Codex profile overlays are available.");
            return 0;
        }

        var failures = new List<string>();
        var overlays = new Dictionary<string, Profile>(StringComparer.Ordinal);
        var sources = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var metadataPath in Directory.EnumerateFiles(overlaysRoot, "codex-profile-overlays.json", SearchOption.AllDirectories))
        {
            await ReadOverlayAsync(metadataPath, overlays, sources, failures);
        }

        if (failures.Count > 0)
        {
            PrintFailures(failures);
            return 1;
        }

        if (overlays.Count == 0)
        {
            Console.WriteLine("No Codex profile overlays found.");
            return 0;
        }

        var operations = new List<Operation>();
        foreach (var pair in overlays.OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            await InspectTargetAsync(options.TargetRoot, pair.Key, pair.Value, sources[pair.Key], options.Force, operations, failures);
        }

        if (failures.Count > 0)
        {
            PrintFailures(failures);
            return 1;
        }

        foreach (var operation in operations)
        {
            Console.WriteLine($"{operation.Kind}: {operation.Path}");
        }

        var changes = operations.Where(x => x.Kind == OperationKind.Update).ToArray();
        if (options.Check)
        {
            Console.WriteLine(changes.Length == 0
                ? "Codex profile check: OK"
                : $"Codex profile check: FAILED ({changes.Length} update(s) required)");
            return changes.Length == 0 ? 0 : 1;
        }

        if (options.DryRun)
        {
            Console.WriteLine(changes.Length == 0
                ? "Dry-run result: no changes are needed."
                : $"Dry-run result: {changes.Length} update(s) planned; no files were changed.");
            return 0;
        }

        foreach (var operation in changes)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(operation.Path)!);
            await File.WriteAllTextAsync(operation.Path, operation.Content!, Utf8NoBom);
        }

        Console.WriteLine(changes.Length == 0
            ? "Codex profiles are already compliant."
            : $"Codex profile finalizer applied {changes.Length} update(s).");
        return 0;
    }

    private static async Task ReadOverlayAsync(
        string metadataPath,
        IDictionary<string, Profile> overlays,
        IDictionary<string, string> sources,
        ICollection<string> failures)
    {
        OverlayDocument? document;
        try
        {
            document = ParseOverlay(await File.ReadAllTextAsync(metadataPath));
        }
        catch (Exception ex)
        {
            failures.Add($"Invalid overlay {metadataPath}: {ex.Message}");
            return;
        }

        var packageRoot = Path.GetDirectoryName(metadataPath)!;
        var manifestPath = Path.Combine(packageRoot, "apm.yml");
        var manifestText = File.Exists(manifestPath) ? await File.ReadAllTextAsync(manifestPath) : string.Empty;
        var manifestMatch = ManifestName.Match(manifestText);
        var packageName = manifestMatch.Success ? manifestMatch.Groups["value"].Value.Trim() : string.Empty;
        if (document is null || document.SchemaVersion != 1 || string.IsNullOrWhiteSpace(document.Package) || document.Package != packageName || document.Profiles is null)
        {
            failures.Add($"Overlay {metadataPath} has an invalid schema or package ownership declaration.");
            return;
        }

        foreach (var entry in document.Profiles)
        {
            if (!SafeAgentIdentifier.IsMatch(entry.Agent) ||
                ProfileKeys.Any(key => string.IsNullOrWhiteSpace(GetProfileValue(entry, key))))
            {
                failures.Add($"Overlay {metadataPath} contains an incomplete profile entry.");
                continue;
            }

            var agentPath = Path.Combine(packageRoot, ".apm", "agents", entry.Agent + ".agent.md");
            if (!File.Exists(agentPath))
            {
                failures.Add($"Overlay {metadataPath} is not backed by package-owned agent {agentPath}.");
                continue;
            }

            var agentText = await File.ReadAllTextAsync(agentPath);
            var agentMatch = AgentName.Match(agentText);
            if (!agentMatch.Success || !string.Equals(agentMatch.Groups["value"].Value.Trim(), entry.Agent, StringComparison.Ordinal))
            {
                failures.Add($"Overlay {metadataPath} agent ownership does not match {agentPath}.");
                continue;
            }

            var profile = new Profile(entry.Model, entry.Reasoning, entry.Sandbox);
            if (overlays.TryGetValue(entry.Agent, out var existing) && existing != profile)
            {
                failures.Add($"Conflicting Codex profile overlays target agent {entry.Agent}: {sources[entry.Agent]} and {metadataPath}.");
                continue;
            }

            overlays[entry.Agent] = profile;
            sources[entry.Agent] = metadataPath;
        }
    }

    private static OverlayDocument ParseOverlay(string text)
    {
        using var json = JsonDocument.Parse(text);
        var root = json.RootElement;
        if (root.ValueKind != JsonValueKind.Object ||
            root.EnumerateObject().Any(property => !OverlayDocumentKeys.Contains(property.Name, StringComparer.Ordinal)))
        {
            throw new InvalidDataException("overlay document contains unsupported fields");
        }

        var profiles = new List<OverlayEntry>();
        foreach (var element in root.GetProperty("profiles").EnumerateArray())
        {
            if (element.ValueKind != JsonValueKind.Object ||
                element.EnumerateObject().Any(property => !OverlayEntryKeys.Contains(property.Name, StringComparer.Ordinal)))
            {
                throw new InvalidDataException("overlay profile entry contains unsupported fields");
            }

            profiles.Add(new OverlayEntry(
                element.GetProperty("agent").GetString() ?? string.Empty,
                element.GetProperty("model").GetString() ?? string.Empty,
                element.GetProperty("model_reasoning_effort").GetString() ?? string.Empty,
                element.GetProperty("sandbox_mode").GetString() ?? string.Empty));
        }

        return new OverlayDocument(
            root.GetProperty("schemaVersion").GetInt32(),
            root.GetProperty("package").GetString() ?? string.Empty,
            profiles);
    }

    private static string GetProfileValue(OverlayEntry entry, string key) => key switch
    {
        "model" => entry.Model,
        "model_reasoning_effort" => entry.Reasoning,
        "sandbox_mode" => entry.Sandbox,
        _ => string.Empty
    };

    private static async Task InspectTargetAsync(
        string targetRoot,
        string agent,
        Profile profile,
        string source,
        bool force,
        ICollection<Operation> operations,
        ICollection<string> failures)
    {
        var targetPath = Path.Combine(targetRoot, ".codex", "agents", agent + ".toml");
        if (!File.Exists(targetPath))
        {
            failures.Add($"APM projection for {agent} is missing: {targetPath} (overlay: {source}).");
            return;
        }

        var original = await File.ReadAllTextAsync(targetPath);
        var newline = original.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var hadTrailingNewline = original.EndsWith("\r\n", StringComparison.Ordinal) || original.EndsWith("\n", StringComparison.Ordinal);
        var normalized = original.Replace("\r\n", "\n").Replace('\r', '\n');
        var lines = normalized.Split('\n').ToList();
        var firstSection = lines.FindIndex(line => Section.IsMatch(line));
        var values = new Dictionary<string, (int Index, string Value)>(StringComparer.Ordinal);
        string? projectedAgentName = null;
        for (var i = 0; i < lines.Count; i++)
        {
            if (firstSection >= 0 && i >= firstSection)
            {
                break;
            }

            var match = TopLevelTomlKey.Match(lines[i]);
            if (!match.Success)
            {
                continue;
            }

            var key = match.Groups["key"].Value;
            if (string.Equals(key, "name", StringComparison.Ordinal))
            {
                if (projectedAgentName is not null)
                {
                    failures.Add($"Duplicate top-level name field in {targetPath}.");
                    continue;
                }

                projectedAgentName = UnescapeToml(match.Groups["value"].Value);
                continue;
            }

            if (!ProfileKeys.Contains(key, StringComparer.Ordinal))
            {
                continue;
            }
            if (values.ContainsKey(key))
            {
                failures.Add($"Duplicate top-level profile field {key} in {targetPath}.");
                continue;
            }

            values[key] = (i, UnescapeToml(match.Groups["value"].Value));
        }

        if (!string.Equals(projectedAgentName, agent, StringComparison.Ordinal))
        {
            failures.Add($"Codex projection ownership mismatch for {agent}: {targetPath} has name '{projectedAgentName ?? "<missing>"}'.");
            return;
        }

        var expected = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["model"] = profile.Model,
            ["model_reasoning_effort"] = profile.Reasoning,
            ["sandbox_mode"] = profile.Sandbox
        };
        var updates = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var key in ProfileKeys)
        {
            if (!values.TryGetValue(key, out var value))
            {
                updates[key] = expected[key];
                continue;
            }

            if (!string.Equals(value.Value, expected[key], StringComparison.Ordinal))
            {
                if (!force)
                {
                    failures.Add($"Explicit Codex profile mismatch for {agent}.{key} in {targetPath}; use --force to apply the package recommendation.");
                    continue;
                }

                updates[key] = expected[key];
            }
        }

        if (updates.Count == 0)
        {
            operations.Add(new Operation(OperationKind.Unchanged, targetPath, null));
            return;
        }

        var insertAt = firstSection >= 0 ? firstSection : lines.Count;
        foreach (var key in ProfileKeys.Reverse())
        {
            if (updates.TryGetValue(key, out var value))
            {
                if (values.TryGetValue(key, out var existing))
                {
                    lines[existing.Index] = $"{key} = {QuoteToml(value)}";
                }
                else
                {
                    lines.Insert(insertAt, $"{key} = {QuoteToml(value)}");
                }
            }
        }

        var fixedText = string.Join(newline, lines).TrimEnd('\r', '\n');
        if (hadTrailingNewline)
        {
            fixedText += newline;
        }
        operations.Add(new Operation(OperationKind.Update, targetPath, fixedText));
    }

    private static Options Parse(string[] args)
    {
        var target = Directory.GetCurrentDirectory();
        var targetSet = false;
        var dryRun = false;
        var check = false;
        var force = false;
        foreach (var arg in args)
        {
            switch (arg)
            {
                case "--dry-run": dryRun = true; break;
                case "--check": check = true; break;
                case "--force": force = true; break;
                case "--help": case "-h": throw new ArgumentException("help");
                default:
                    if (arg.StartsWith('-', StringComparison.Ordinal) || targetSet)
                    {
                        throw new ArgumentException($"Unknown or duplicate argument: {arg}");
                    }

                    target = Path.GetFullPath(arg);
                    targetSet = true;
                    break;
            }
        }

        if (dryRun && check)
        {
            throw new ArgumentException("--dry-run and --check cannot be combined.");
        }

        return new Options(target, dryRun, check, force);
    }

    private static string UnescapeToml(string value) => value.Replace("\\\"", "\"").Replace("\\\\", "\\");

    private static string QuoteToml(string value) => "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";

    private static void PrintFailures(IEnumerable<string> failures)
    {
        foreach (var failure in failures)
        {
            Console.Error.WriteLine("Finalizer error: " + failure);
        }
    }

    private static void PrintUsage() => Console.WriteLine("Usage: dotnet run --file finalize-codex-agent-profiles.cs -- [target-repository] [--dry-run | --check] [--force]");

    private sealed record Options(string TargetRoot, bool DryRun, bool Check, bool Force);
    private sealed record Profile(string Model, string Reasoning, string Sandbox);
    private sealed record Operation(OperationKind Kind, string Path, string? Content);
    private sealed record OverlayDocument(
        [property: JsonPropertyName("schemaVersion")] int SchemaVersion,
        [property: JsonPropertyName("package")] string Package,
        [property: JsonPropertyName("profiles")] List<OverlayEntry>? Profiles);
    private sealed record OverlayEntry(
        [property: JsonPropertyName("agent")] string Agent,
        [property: JsonPropertyName("model")] string Model,
        [property: JsonPropertyName("model_reasoning_effort")] string Reasoning,
        [property: JsonPropertyName("sandbox_mode")] string Sandbox);
    private enum OperationKind { Unchanged, Update }
}
