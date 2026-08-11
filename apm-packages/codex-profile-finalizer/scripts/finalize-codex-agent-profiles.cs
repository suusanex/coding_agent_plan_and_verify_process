#!/usr/bin/env dotnet
//#:property TargetFramework=net10.0
#:package Tomlyn@2.10.1

using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Tomlyn;
using Tomlyn.Model;

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
    private static readonly Regex TopLevelTomlAssignment = new("^(?<indent>\\s*)(?<key>[A-Za-z0-9_-]+)\\s*=\\s*(?<value>.*)$", RegexOptions.Compiled);
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
            Console.WriteLine(options.Check
                ? "Codex profile check: FAILED (apm_modules directory is missing)."
                : "No apm_modules directory found; no Codex profile overlays are available.");
            return options.Check ? 1 : 0;
        }

        var failures = new List<string>();
        var overlays = new Dictionary<string, Profile>(StringComparer.Ordinal);
        var sources = new Dictionary<string, string>(StringComparer.Ordinal);
        var contracts = new Dictionary<string, PortableContract>(StringComparer.Ordinal);
        foreach (var metadataPath in Directory.EnumerateFiles(overlaysRoot, "codex-profile-overlays.json", SearchOption.AllDirectories))
        {
            await ReadOverlayAsync(metadataPath, overlays, sources, contracts, failures);
        }

        if (failures.Count > 0)
        {
            PrintFailures(failures);
            return 1;
        }

        if (overlays.Count == 0)
        {
            Console.WriteLine(options.Check
                ? "Codex profile check: FAILED (no Codex profile overlays found)."
                : "No Codex profile overlays found.");
            return options.Check ? 1 : 0;
        }

        var operations = new List<Operation>();
        foreach (var pair in overlays.OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            await InspectTargetAsync(options.TargetRoot, pair.Key, pair.Value, contracts[pair.Key], sources[pair.Key], options.Force, operations, failures);
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
        IDictionary<string, PortableContract> contracts,
        ICollection<string> failures)
    {
        OverlayDocument? document;
        try
        {
            document = ParseOverlay(await File.ReadAllTextAsync(metadataPath));
        }
        catch (Exception ex)
        {
            failures.Add($"Invalid overlay {metadataPath}: {ex.ToString()}");
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

        if (string.Equals(document.Package, "adaptive-implementation-execution", StringComparison.Ordinal))
        {
            var high = document.Profiles.SingleOrDefault(x => string.Equals(x.Agent, "high-implementation-starter", StringComparison.Ordinal));
            var standard = document.Profiles.SingleOrDefault(x => string.Equals(x.Agent, "standard-implementation-completer", StringComparison.Ordinal));
            if (high is null || standard is null || string.Equals(high.Model, standard.Model, StringComparison.Ordinal))
            {
                failures.Add($"Adaptive overlay {metadataPath} must define distinct HIGH and STANDARD models.");
                return;
            }
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

            PortableContract contract;
            try
            {
                contract = ParsePortableContract(await File.ReadAllTextAsync(agentPath), entry.Agent);
            }
            catch (Exception ex)
            {
                failures.Add($"Invalid package-owned agent {agentPath}: {ex.ToString()}");
                continue;
            }

            if (!string.Equals(contract.Name, entry.Agent, StringComparison.Ordinal))
            {
                failures.Add($"Overlay {metadataPath} agent ownership does not match {agentPath}.");
                continue;
            }

            var profile = new Profile(entry.Model, entry.Reasoning, entry.Sandbox, contract);
            if (overlays.TryGetValue(entry.Agent, out var existing) && existing != profile)
            {
                failures.Add($"Conflicting Codex profile overlays target agent {entry.Agent}: {sources[entry.Agent]} and {metadataPath}.");
                continue;
            }

            overlays[entry.Agent] = profile;
            sources[entry.Agent] = metadataPath;
            contracts[entry.Agent] = contract;
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
        PortableContract contract,
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
        TomlTable model;
        try
        {
            model = TomlSerializer.Deserialize<TomlTable>(original)
                ?? throw new InvalidDataException("TOML document produced no model.");
        }
        catch (Exception ex)
        {
            failures.Add($"Invalid Codex projection {targetPath}: {ex.ToString()}");
            return;
        }

        var portableValues = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var key in new[] { "name", "description", "developer_instructions" })
        {
            if (!model.TryGetValue(key, out var value) || value is not string stringValue)
            {
                failures.Add($"Codex projection ownership mismatch for {agent}: {targetPath} is missing top-level string field '{key}'.");
                continue;
            }

            portableValues[key] = stringValue;
        }

        if (!portableValues.TryGetValue("name", out var projectedAgentName) ||
            !string.Equals(projectedAgentName, contract.Name, StringComparison.Ordinal) ||
            !portableValues.TryGetValue("description", out var description) ||
            !string.Equals(description, contract.Description, StringComparison.Ordinal) ||
            !portableValues.TryGetValue("developer_instructions", out var developerInstructions) ||
            !string.Equals(developerInstructions, contract.DeveloperInstructions, StringComparison.Ordinal))
        {
            failures.Add($"Codex projection ownership mismatch for {agent}: {targetPath} does not match package-owned portable contract.");
            return;
        }

        var newline = original.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var hadTrailingNewline = original.EndsWith("\r\n", StringComparison.Ordinal) || original.EndsWith("\n", StringComparison.Ordinal);
        var normalized = original.Replace("\r\n", "\n").Replace('\r', '\n');
        var lines = normalized.Split('\n').ToList();
        var firstSection = lines.FindIndex(line => Section.IsMatch(line));
        var values = FindTopLevelAssignments(lines, firstSection, targetPath, failures);

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

            if (!model.TryGetValue(key, out var modelValue) || modelValue is not string currentValue)
            {
                failures.Add($"Codex projection profile field {key} in {targetPath} is not a top-level string.");
                continue;
            }

            if (!string.Equals(currentValue, expected[key], StringComparison.Ordinal))
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
                    lines[existing.Index] = ReplaceTomlAssignmentValue(lines[existing.Index], QuoteToml(value));
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
        try
        {
            _ = TomlSerializer.Deserialize<TomlTable>(fixedText)
                ?? throw new InvalidDataException("rewritten TOML document produced no model");
        }
        catch (Exception ex)
        {
            failures.Add($"Finalizer produced invalid TOML for {targetPath}: {ex.ToString()}");
            return;
        }
        operations.Add(new Operation(OperationKind.Update, targetPath, fixedText));
    }

    private static Dictionary<string, (int Index, string Value)> FindTopLevelAssignments(
        IReadOnlyList<string> lines,
        int firstSection,
        string targetPath,
        ICollection<string> failures)
    {
        var values = new Dictionary<string, (int Index, string Value)>(StringComparer.Ordinal);
        for (var i = 0; i < lines.Count; i++)
        {
            if (firstSection >= 0 && i >= firstSection) break;
            var match = TopLevelTomlAssignment.Match(lines[i]);
            if (!match.Success) continue;
            var key = match.Groups["key"].Value;
            if (!ProfileKeys.Contains(key, StringComparer.Ordinal)) continue;
            if (values.ContainsKey(key))
            {
                failures.Add($"Duplicate top-level profile field {key} in {targetPath}.");
                continue;
            }

            var comment = FindInlineCommentStart(match.Groups["value"].Value);
            var rawValue = comment >= 0 ? match.Groups["value"].Value[..comment].TrimEnd() : match.Groups["value"].Value.Trim();
            values[key] = (i, rawValue);
        }

        return values;
    }

    private static string ReplaceTomlAssignmentValue(string line, string replacement)
    {
        var match = TopLevelTomlAssignment.Match(line);
        if (!match.Success) return line;
        var raw = match.Groups["value"].Value;
        var comment = FindInlineCommentStart(raw);
        if (comment >= 0)
        {
            while (comment > 0 && char.IsWhiteSpace(raw[comment - 1])) comment--;
        }
        var suffix = comment >= 0 ? raw[comment..] : string.Empty;
        return $"{match.Groups["indent"].Value}{match.Groups["key"].Value} = {replacement}{suffix}";
    }

    private static int FindInlineCommentStart(string value)
    {
        var inBasic = false;
        var inLiteral = false;
        var escaped = false;
        for (var i = 0; i < value.Length; i++)
        {
            var current = value[i];
            if (inBasic)
            {
                if (escaped) escaped = false;
                else if (current == '\\') escaped = true;
                else if (current == '"') inBasic = false;
                continue;
            }
            if (inLiteral)
            {
                if (current == '\'') inLiteral = false;
                continue;
            }
            if (current == '"') inBasic = true;
            else if (current == '\'') inLiteral = true;
            else if (current == '#') return i;
        }
        return -1;
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
                    if (arg.StartsWith("-", StringComparison.Ordinal) || targetSet)
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

    private static PortableContract ParsePortableContract(string text, string expectedAgent)
    {
        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        if (lines.Length < 3 || !string.Equals(lines[0].Trim(), "---", StringComparison.Ordinal))
            throw new InvalidDataException("agent frontmatter is missing");

        var end = Array.FindIndex(lines, 1, line => string.Equals(line.Trim(), "---", StringComparison.Ordinal));
        if (end < 0) throw new InvalidDataException("agent frontmatter is unterminated");

        var frontmatter = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var line in lines[1..end])
        {
            var separator = line.IndexOf(':');
            if (separator <= 0) continue;
            var key = line[..separator].Trim();
            var value = line[(separator + 1)..].Trim();
            if (key is "name" or "description") frontmatter[key] = UnquoteYaml(value);
        }

        if (!frontmatter.TryGetValue("name", out var name) || !string.Equals(name, expectedAgent, StringComparison.Ordinal) ||
            !frontmatter.TryGetValue("description", out var description))
            throw new InvalidDataException("agent frontmatter does not contain the expected name and description");

        var instructions = string.Join("\n", lines[(end + 1)..]).Trim();
        if (string.IsNullOrWhiteSpace(instructions)) throw new InvalidDataException("agent developer instructions are empty");
        return new PortableContract(name, description, instructions);
    }

    private static string UnquoteYaml(string value)
    {
        if (value.Length >= 2 && ((value[0] == '"' && value[^1] == '"') || (value[0] == '\'' && value[^1] == '\'')))
            return value[1..^1];
        return value;
    }

    private static void PrintFailures(IEnumerable<string> failures)
    {
        foreach (var failure in failures)
        {
            Console.Error.WriteLine("Finalizer error: " + failure);
        }
    }

    private static void PrintUsage() => Console.WriteLine("Usage: dotnet run --file finalize-codex-agent-profiles.cs -- [target-repository] [--dry-run | --check] [--force]");

    private sealed record Options(string TargetRoot, bool DryRun, bool Check, bool Force);
    private sealed record Profile(string Model, string Reasoning, string Sandbox, PortableContract Contract);
    private sealed record PortableContract(string Name, string Description, string DeveloperInstructions);
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
