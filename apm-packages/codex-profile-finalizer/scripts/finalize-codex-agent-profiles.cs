#!/usr/bin/env dotnet
//#:property TargetFramework=net10.0
#:package Tomlyn@2.10.1

using System.Text;
using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Tomlyn;
using Tomlyn.Model;
using Tomlyn.Parsing;

return await CodexProfileFinalizer.RunAsync(args);

internal static class CodexProfileFinalizer
{
    private const string AdaptivePackageName = "adaptive-implementation-execution";
    private const string ParentAgentName = "decision-surface-implementation-owner";
    private const string ChildAgentName = "bounded-residual-implementation-owner";

    // 管理対象はAdaptiveが公開している既存agent名だけに固定する。
    // lockfileや内容hashから所有権を推測する仕組みは導入しない。
    private static readonly string[] ProfileKeys = ["model", "model_reasoning_effort", "sandbox_mode"];
    private static readonly string[] OverlayEntryKeys = ["agent", "model", "model_reasoning_effort", "sandbox_mode"];
    private static readonly string[] OverlayDocumentKeys = ["schemaVersion", "package", "profiles"];
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private static readonly Regex ManifestName = new(@"(?m)^name:\s*(?<value>[^\r\n#]+)", RegexOptions.Compiled);
    private static readonly Regex AgentName = new(@"(?m)^name:\s*(?<value>[^\r\n#]+)", RegexOptions.Compiled);
    private static readonly Regex SafeAgentIdentifier = new("^[A-Za-z0-9][A-Za-z0-9._-]*$", RegexOptions.Compiled);
    private static readonly Regex FrontmatterModel = new(@"^\s*model\s*:", RegexOptions.Compiled);

    public static async Task<int> RunAsync(string[] args)
    {
        try
        {
            return await RunCoreAsync(args);
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
            Console.Error.WriteLine(ex.ToString());
            return 1;
        }
    }

    private static async Task<int> RunCoreAsync(string[] args)
    {
        if (args.Length == 1 && args[0] is "--help" or "-h")
        {
            PrintUsage();
            return 0;
        }

        Options options;
        try
        {
            options = Parse(args);
        }
        catch (ArgumentException ex)
        {
            Trace.WriteLine(ex.ToString());
            Console.Error.WriteLine(ex.ToString());
            PrintUsage();
            return 2;
        }

        Locations locations;
        try
        {
            locations = ResolveLocations();
        }
        catch (InvalidOperationException ex)
        {
            Trace.WriteLine(ex.ToString());
            Console.Error.WriteLine(ex.ToString());
            return 2;
        }

        Console.WriteLine($"Codex profile overlays: {locations.OverlaysRoot}");
        Console.WriteLine($"Codex agent directory: {locations.AgentsRoot}");

        if (!Directory.Exists(locations.OverlaysRoot))
        {
            Console.Error.WriteLine($"Codex profile finalizer failed: apm_modules directory is missing: {locations.OverlaysRoot}");
            return 1;
        }

        var failures = new List<string>();
        var overlays = new Dictionary<string, Profile>(StringComparer.Ordinal);
        var sources = new Dictionary<string, string>(StringComparer.Ordinal);
        var contracts = new Dictionary<string, PortableContract>(StringComparer.Ordinal);
        var parentBinding = new ParentBinding();
        foreach (var metadataPath in Directory.EnumerateFiles(locations.OverlaysRoot, "codex-profile-overlays.json", SearchOption.AllDirectories))
        {
            await ReadOverlayAsync(metadataPath, overlays, sources, contracts, parentBinding, failures);
        }

        if (failures.Count > 0)
        {
            PrintFailures(failures);
            return 1;
        }

        if (overlays.Count == 0 && parentBinding.Contract is null)
        {
            Console.Error.WriteLine($"Codex profile finalizer failed: no Codex profile overlays found under {locations.OverlaysRoot}.");
            return 1;
        }

        var operations = new List<Operation>();
        if (parentBinding.Contract is not null)
        {
            await InspectTargetAsync(locations.AgentsRoot, ParentAgentName, null, parentBinding.Contract,
                parentBinding.Source!, options.Force, operations, failures);
        }

        foreach (var pair in overlays.OrderBy(x => x.Key, StringComparer.Ordinal))
        {
            if (string.Equals(pair.Key, ParentAgentName, StringComparison.Ordinal))
            {
                failures.Add($"Adaptive parent must inherit its session profile and cannot accept a Codex profile overlay: {sources[pair.Key]}.");
                continue;
            }

            await InspectTargetAsync(locations.AgentsRoot, pair.Key, pair.Value, contracts[pair.Key], sources[pair.Key], options.Force, operations, failures);
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
        ParentBinding parentBinding,
        ICollection<string> failures)
    {
        OverlayDocument? document;
        try
        {
            document = ParseOverlay(await File.ReadAllTextAsync(metadataPath));
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
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

        if (string.Equals(document.Package, AdaptivePackageName, StringComparison.Ordinal))
        {
            if (document.Profiles.Count != 1 ||
                document.Profiles[0].Agent != ChildAgentName)
            {
                failures.Add(
                    $"Adaptive overlay {metadataPath} must define only the child profile; the parent uses its selected model.");
                return;
            }

            await LoadAdaptiveParentAsync(packageRoot, parentBinding, failures);
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
                Trace.WriteLine(ex.ToString());
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

    private static async Task LoadAdaptiveParentAsync(string packageRoot, ParentBinding parentBinding, ICollection<string> failures)
    {
        var parentPath = Path.Combine(packageRoot, ".apm", "agents", ParentAgentName + ".agent.md");
        string parentText;
        try
        {
            parentText = await File.ReadAllTextAsync(parentPath);
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
            failures.Add($"Invalid Adaptive parent canonical contract {parentPath}: {ex.ToString()}");
            return;
        }

        if (FrontmatterPinsModel(parentText))
        {
            failures.Add($"Adaptive parent canonical contract must not pin a model: {parentPath}.");
            return;
        }

        PortableContract contract;
        try
        {
            contract = ParsePortableContract(parentText, ParentAgentName);
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
            failures.Add($"Invalid Adaptive parent canonical contract {parentPath}: {ex.ToString()}");
            return;
        }

        if (parentBinding.Contract is not null && parentBinding.Contract != contract)
        {
            failures.Add($"Conflicting Adaptive parent contracts: {parentBinding.Source} and {parentPath}.");
            return;
        }

        parentBinding.Contract ??= contract;
        parentBinding.Source ??= parentPath;
    }

    private static bool FrontmatterPinsModel(string text)
    {
        var lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Split('\n');
        if (lines.Length < 3 || !string.Equals(lines[0].Trim(), "---", StringComparison.Ordinal))
        {
            return false;
        }

        for (var i = 1; i < lines.Length; i++)
        {
            if (string.Equals(lines[i].Trim(), "---", StringComparison.Ordinal))
            {
                return false;
            }

            if (FrontmatterModel.IsMatch(lines[i]))
            {
                return true;
            }
        }

        return false;
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
        string agentsRoot,
        string agent,
        Profile? profile,
        PortableContract contract,
        string source,
        bool force,
        ICollection<Operation> operations,
        ICollection<string> failures)
    {
        var targetPath = Path.Combine(agentsRoot, agent + ".toml");
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
            Trace.WriteLine(ex.ToString());
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

        var syntax = SyntaxParser.Parse(original);
        if (syntax.HasErrors)
        {
            failures.Add($"Invalid Codex projection {targetPath}: {string.Join("; ", syntax.Diagnostics)}");
            return;
        }

        var values = FindTopLevelAssignments(syntax, targetPath, failures);

        if (profile is null && ProfileKeys.Any(model.ContainsKey))
        {
            failures.Add($"Adaptive parent profile fields must be absent: {targetPath}.");
            return;
        }

        var expected = profile is null ? new Dictionary<string, string>(StringComparer.Ordinal) : new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["model"] = profile.Model,
            ["model_reasoning_effort"] = profile.Reasoning,
            ["sandbox_mode"] = profile.Sandbox
        };
        var updates = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var key in ProfileKeys)
        {
            if (profile is null) break;
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

        var fixedText = PatchProfileFields(original, updates, values);
        try
        {
            _ = TomlSerializer.Deserialize<TomlTable>(fixedText)
                ?? throw new InvalidDataException("rewritten TOML document produced no model");
        }
        catch (Exception ex)
        {
            Trace.WriteLine(ex.ToString());
            failures.Add($"Finalizer produced invalid TOML for {targetPath}: {ex.ToString()}");
            return;
        }
        operations.Add(new Operation(OperationKind.Update, targetPath, fixedText));
    }

    private static Dictionary<string, (int Offset, int Length)> FindTopLevelAssignments(
        Tomlyn.Syntax.DocumentSyntax syntax,
        string targetPath,
        ICollection<string> failures)
    {
        var values = new Dictionary<string, (int Offset, int Length)>(StringComparer.Ordinal);
        foreach (var assignment in syntax.KeyValues)
        {
            var keySyntax = assignment.Key;
            if (keySyntax?.Key is null || keySyntax.DotKeys?.Any() == true) continue;
            var key = keySyntax.Key switch
            {
                Tomlyn.Syntax.BareKeySyntax bareKey => bareKey.Key?.ToString().Trim() ?? string.Empty,
                Tomlyn.Syntax.StringValueSyntax stringKey => stringKey.Value?.ToString() ?? string.Empty,
                _ => string.Empty
            };
            if (!ProfileKeys.Contains(key, StringComparer.Ordinal)) continue;

            if (values.ContainsKey(key))
            {
                failures.Add($"Duplicate top-level profile field {key} in {targetPath}.");
                continue;
            }

            if (assignment.Value is null) continue;
            values[key] = (assignment.Value.Span.Offset, assignment.Value.Span.Length);
        }

        return values;
    }

    private static string PatchProfileFields(
        string original,
        IReadOnlyDictionary<string, string> updates,
        IReadOnlyDictionary<string, (int Offset, int Length)> values)
    {
        var builder = new StringBuilder(original);
        foreach (var pair in updates
            .Where(pair => values.ContainsKey(pair.Key))
            .OrderByDescending(pair => values[pair.Key].Offset))
        {
            var valueSpan = values[pair.Key];
            builder.Remove(valueSpan.Offset, valueSpan.Length);
            builder.Insert(valueSpan.Offset, QuoteToml(pair.Value));
        }

        var missing = ProfileKeys.Where(key => updates.ContainsKey(key) && !values.ContainsKey(key)).ToArray();
        if (missing.Length == 0)
        {
            return builder.ToString();
        }

        var fixedText = builder.ToString();
        var newline = original.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var syntax = SyntaxParser.Parse(fixedText);
        var firstTableOffset = syntax.Tables.Select(table => table.Span.Offset).DefaultIfEmpty(-1).Min();
        var additions = string.Join(newline, missing.Select(key => $"{key} = {QuoteToml(updates[key])}")) + newline;
        if (firstTableOffset >= 0)
        {
            var lineStart = fixedText.LastIndexOf('\n', firstTableOffset - 1) + 1;
            return fixedText.Insert(lineStart, additions);
        }

        var trailingStart = fixedText.Length;
        while (trailingStart > 0 && char.IsWhiteSpace(fixedText[trailingStart - 1])) trailingStart--;
        var prefix = fixedText[..trailingStart];
        var suffix = fixedText[trailingStart..];
        var prefixSeparator = prefix.Length == 0 || prefix.EndsWith('\n') || prefix.EndsWith('\r') ? string.Empty : newline;
        var suffixSeparator = suffix.Length > 0 && suffix[0] is not ('\n' or '\r') ? newline : string.Empty;
        return prefix + prefixSeparator + additions.TrimEnd('\r', '\n') + suffixSeparator + suffix;
    }

    private static Options Parse(string[] args)
    {
        var global = false;
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
                case "--global":
                    if (global)
                    {
                        throw new ArgumentException("--global must be specified exactly once.");
                    }

                    global = true;
                    break;
                default:
                    throw new ArgumentException($"Unknown argument: {arg}");
            }
        }

        if (dryRun && check)
        {
            throw new ArgumentException("--dry-run and --check cannot be combined.");
        }

        if (!global)
        {
            throw new ArgumentException("--global is required.");
        }

        return new Options(dryRun, check, force);
    }

    private static Locations ResolveLocations()
    {
        // APM 0.26のglobal storeはOS標準のユーザーホーム直下の .apm を使う。
        var apmHome = Path.Combine(ResolveUserProfile(), ".apm");
        var codexHome = ResolveHome("CODEX_HOME", ".codex");
        return new Locations(Path.Combine(apmHome, "apm_modules"), Path.Combine(codexHome, "agents"));
    }

    private static string ResolveUserProfile()
    {
        var configured = Environment.GetEnvironmentVariable(OperatingSystem.IsWindows() ? "USERPROFILE" : "HOME");
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured.Trim());
        }

        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (string.IsNullOrWhiteSpace(profile))
        {
            throw new InvalidOperationException("Cannot resolve user profile directory from the operating system.");
        }

        return Path.GetFullPath(profile);
    }

    private static string ResolveHome(string variableName, string defaultFolderName)
    {
        var configured = Environment.GetEnvironmentVariable(variableName);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured.Trim());
        }

        return Path.Combine(ResolveUserProfile(), defaultFolderName);
    }

    private static string NormalizeNewlines(string value) =>
        value.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');

    private static string QuoteToml(string value)
    {
        var builder = new StringBuilder(value.Length + 2);
        builder.Append('"');
        foreach (var ch in NormalizeNewlines(value))
        {
            switch (ch)
            {
                case '\\':
                    builder.Append("\\\\");
                    break;
                case '"':
                    builder.Append("\\\"");
                    break;
                case '\n':
                    builder.Append("\\n");
                    break;
                case '\t':
                    builder.Append("\\t");
                    break;
                default:
                    if (ch < ' ')
                    {
                        builder.Append("\\u");
                        builder.Append(((int)ch).ToString("x4"));
                    }
                    else
                    {
                        builder.Append(ch);
                    }

                    break;
            }
        }

        builder.Append('"');
        return builder.ToString();
    }

    private static PortableContract ParsePortableContract(string text, string expectedAgent)
    {
        var lines = NormalizeNewlines(text).Split('\n');
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

    private static void PrintUsage() => Console.WriteLine("Usage: dotnet run --file finalize-codex-agent-profiles.cs -- --global [--dry-run | --check] [--force]");

    private sealed record Options(bool DryRun, bool Check, bool Force);
    private sealed record Locations(string OverlaysRoot, string AgentsRoot);
    private sealed class ParentBinding
    {
        public PortableContract? Contract { get; set; }
        public string? Source { get; set; }
    }
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
