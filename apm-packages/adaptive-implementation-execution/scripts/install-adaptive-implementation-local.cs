#:property TargetFramework=net10.0

using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;

var options = ParseArguments(args);
if (!options.IsValid)
{
    PrintUsage();
    Environment.ExitCode = 2;
    return;
}

var sourceFile = GetSourceFilePath();
var packageRoot = Directory.GetParent(Path.GetDirectoryName(sourceFile)!)!.FullName;
var agentConfigRoot = Path.Combine(packageRoot, "codex-agents");
var targetRoot = Path.GetFullPath(options.TargetRoot);

var agentSources = new[]
{
    Path.Combine(agentConfigRoot, "high-implementation-starter.toml"),
    Path.Combine(agentConfigRoot, "standard-implementation-completer.toml")
};

var missingSources = agentSources.Where(path => !File.Exists(path)).ToArray();
if (missingSources.Length > 0)
{
    foreach (var path in missingSources)
    {
        Console.Error.WriteLine("Missing package source: " + path);
    }

    Environment.ExitCode = 2;
    return;
}

if (!Directory.Exists(targetRoot))
{
    Console.Error.WriteLine("Target repository does not exist: " + targetRoot);
    Environment.ExitCode = 2;
    return;
}

var operations = new List<PlannedOperation>();
var conflicts = new List<string>();

if (options.Remove)
{
    foreach (var source in agentSources)
    {
        PlanFileRemoval(source, Path.Combine(targetRoot, ".codex", "agents", Path.GetFileName(source)), options.Force, operations, conflicts);
    }
}
else
{
    ValidateAgentConfiguration(agentSources[0], agentSources[1], "Package", conflicts);
    foreach (var source in agentSources)
    {
        PlanFileInstall(source, Path.Combine(targetRoot, ".codex", "agents", Path.GetFileName(source)), options.Force, operations, conflicts);
    }
}

if (options.Check)
{
    if (!options.Remove)
    {
        var installedAgents = agentSources
            .Select(source => Path.Combine(targetRoot, ".codex", "agents", Path.GetFileName(source)))
            .ToArray();
        ValidateAgentConfiguration(installedAgents[0], installedAgents[1], "Installed", conflicts);
    }

    var hasChanges = operations.Any(operation => operation.Kind != OperationKind.Unchanged);
    if (hasChanges || conflicts.Count > 0)
    {
        foreach (var operation in operations.Where(operation => operation.Kind != OperationKind.Unchanged))
        {
            Console.Error.WriteLine("Check failed: " + operation.Description);
        }

        foreach (var conflict in conflicts)
        {
            Console.Error.WriteLine("Check failed: " + conflict);
        }

        Environment.ExitCode = 1;
        return;
    }

    Console.WriteLine(options.Remove
        ? "Adaptive Implementation custom agent configuration removal check: OK"
        : "Adaptive Implementation custom agent configuration check: OK (distinct model mappings are installed).");
    return;
}

foreach (var operation in operations)
{
    Console.WriteLine(operation.Description);
}

foreach (var conflict in conflicts)
{
    Console.Error.WriteLine("Conflict: " + conflict);
}

if (conflicts.Count > 0)
{
    Console.Error.WriteLine("No files were changed. Review collisions and rerun with --force only for package-owned custom agent files.");
    Environment.ExitCode = 1;
    return;
}

if (options.DryRun)
{
    Console.WriteLine("Dry-run result: no files were changed.");
    return;
}

foreach (var operation in operations.Where(operation => operation.Apply is not null))
{
    operation.Apply!();
}

Console.WriteLine(options.Remove
    ? "Adaptive Implementation custom agent configuration removal completed."
    : "Adaptive Implementation custom agent configuration installation completed.");

static Options ParseArguments(string[] arguments)
{
    var target = Directory.GetCurrentDirectory();
    var targetWasSet = false;
    var dryRun = false;
    var check = false;
    var force = false;
    var remove = false;
    var valid = true;

    foreach (var argument in arguments)
    {
        switch (argument)
        {
            case "--dry-run":
                dryRun = true;
                break;
            case "--check":
                check = true;
                break;
            case "--force":
                force = true;
                break;
            case "--remove":
                remove = true;
                break;
            case "--help":
            case "-h":
                valid = false;
                break;
            default:
                if (argument.StartsWith('-') || targetWasSet)
                {
                    valid = false;
                }
                else
                {
                    target = argument;
                    targetWasSet = true;
                }
                break;
        }
    }

    if (dryRun && check)
    {
        valid = false;
    }

    return new Options(target, dryRun, check, force, remove, valid);
}

static void PrintUsage()
{
    Console.WriteLine("Usage: dotnet run --file apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs -- [target-repository] [--dry-run | --check] [--force] [--remove]");
}

static string GetSourceFilePath([CallerFilePath] string path = "") => path;

static void PlanFileInstall(
    string source,
    string target,
    bool force,
    List<PlannedOperation> operations,
    List<string> conflicts)
{
    var desired = Normalize(File.ReadAllText(source));
    if (!File.Exists(target))
    {
        operations.Add(new PlannedOperation(
            OperationKind.Create,
            "Create " + target,
            () => WriteText(target, desired)));
        return;
    }

    var existing = Normalize(File.ReadAllText(target));
    if (existing == desired)
    {
        operations.Add(PlannedOperation.Unchanged("Unchanged " + target));
        return;
    }

    if (IsApmGeneratedAgentStub(existing, desired))
    {
        operations.Add(new PlannedOperation(
            OperationKind.Update,
            "Complete APM-generated custom agent configuration: " + target,
            () => WriteText(target, desired)));
        return;
    }

    if (!force)
    {
        conflicts.Add(target + " exists with different content.");
        return;
    }

    operations.Add(new PlannedOperation(
        OperationKind.Update,
        "Replace " + target,
        () => WriteText(target, desired)));
}

static bool IsApmGeneratedAgentStub(string existing, string desired)
{
    if (!TryReadFlatApmAgentToml(existing, out var existingValues) ||
        !TryReadTomlString(desired, "name", out var desiredName) ||
        !TryReadTomlString(desired, "description", out var desiredDescription))
    {
        return false;
    }

    if (existingValues["name"] != desiredName ||
        existingValues["description"] != desiredDescription)
    {
        return false;
    }

    var expectedOpening = desiredName switch
    {
        "high-implementation-starter" => "You are the \"High Implementation Starter\" agent.",
        "standard-implementation-completer" => "You are the \"Standard Implementation Completer\" agent.",
        _ => ""
    };

    return expectedOpening.Length > 0 &&
        existingValues["developer_instructions"].StartsWith(expectedOpening, StringComparison.Ordinal);
}

static bool TryReadFlatApmAgentToml(string content, out Dictionary<string, string> values)
{
    values = new Dictionary<string, string>(StringComparer.Ordinal);
    var allowedKeys = new HashSet<string>(StringComparer.Ordinal)
    {
        "name",
        "description",
        "developer_instructions"
    };

    foreach (var line in Normalize(content).Split('\n'))
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            continue;
        }

        var match = Regex.Match(
            line,
            "^(?<key>[A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(?<value>\\\"(?:\\\\.|[^\\\"\\\\])*\\\")\\s*$",
            RegexOptions.CultureInvariant);
        if (!match.Success || !allowedKeys.Contains(match.Groups["key"].Value))
        {
            return false;
        }

        var key = match.Groups["key"].Value;
        if (values.ContainsKey(key))
        {
            return false;
        }

        if (!TryUnescapeTomlBasicString(match.Groups["value"].Value, out var parsedValue))
        {
            return false;
        }

        values[key] = parsedValue;
    }

    return values.Count == allowedKeys.Count && allowedKeys.All(values.ContainsKey);
}

static bool TryReadTomlString(string content, string key, out string value)
{
    value = "";
    var match = Regex.Match(
        Normalize(content),
        "(?m)^" + Regex.Escape(key) + "\\s*=\\s*(?<value>\\\"(?:\\\\.|[^\\\"\\\\])*\\\")\\s*$",
        RegexOptions.CultureInvariant);
    if (!match.Success)
    {
        return false;
    }

    return TryUnescapeTomlBasicString(match.Groups["value"].Value, out value);
}

static bool TryUnescapeTomlBasicString(string literal, out string value)
{
    value = "";
    if (literal.Length < 2 || literal[0] != '"' || literal[^1] != '"')
    {
        return false;
    }

    try
    {
        value = Regex.Unescape(literal[1..^1]);
        return true;
    }
    catch (ArgumentException)
    {
        return false;
    }
}

static void PlanFileRemoval(
    string source,
    string target,
    bool force,
    List<PlannedOperation> operations,
    List<string> conflicts)
{
    if (!File.Exists(target))
    {
        operations.Add(PlannedOperation.Unchanged("Already absent " + target));
        return;
    }

    var sourceContent = Normalize(File.ReadAllText(source));
    var targetContent = Normalize(File.ReadAllText(target));
    if (sourceContent != targetContent && !force)
    {
        conflicts.Add(target + " differs from the package custom agent configuration and will not be removed.");
        return;
    }

    operations.Add(new PlannedOperation(
        OperationKind.Delete,
        "Delete " + target,
        () => File.Delete(target)));
}

static void ValidateAgentConfiguration(
    string highPath,
    string standardPath,
    string sourceLabel,
    List<string> conflicts)
{
    if (!File.Exists(highPath) || !File.Exists(standardPath))
    {
        foreach (var path in new[] { highPath, standardPath }.Where(path => !File.Exists(path)))
        {
            conflicts.Add(sourceLabel + " custom agent file is missing: " + path);
        }

        return;
    }

    var high = ReadTomlStrings(highPath);
    var standard = ReadTomlStrings(standardPath);
    var requiredKeys = new[] { "name", "model", "model_reasoning_effort", "sandbox_mode" };

    foreach (var (role, values, path) in new[]
    {
        (Role: "HIGH_MODEL", Values: high, Path: highPath),
        (Role: "STANDARD_MODEL", Values: standard, Path: standardPath)
    })
    {
        foreach (var key in requiredKeys)
        {
            if (!values.TryGetValue(key, out var value) || string.IsNullOrWhiteSpace(value))
            {
                conflicts.Add(sourceLabel + " " + role + " custom agent requires a non-empty top-level " + key + ": " + path);
            }
        }

        if (values.TryGetValue("sandbox_mode", out var sandbox) && sandbox != "workspace-write")
        {
            conflicts.Add(sourceLabel + " " + role + " custom agent sandbox_mode must be workspace-write: " + path);
        }
    }

    ValidateExpectedAgentName(high, "high-implementation-starter", highPath, sourceLabel, conflicts);
    ValidateExpectedAgentName(standard, "standard-implementation-completer", standardPath, sourceLabel, conflicts);

    if (high.TryGetValue("name", out var highName)
        && standard.TryGetValue("name", out var standardName)
        && highName == standardName)
    {
        conflicts.Add(sourceLabel + " HIGH_MODEL and STANDARD_MODEL must reference different custom agents.");
    }

    if (high.TryGetValue("model", out var highModel)
        && standard.TryGetValue("model", out var standardModel)
        && highModel == standardModel)
    {
        conflicts.Add(sourceLabel + " HIGH_MODEL and STANDARD_MODEL must use distinct model mappings.");
    }
}

static void ValidateExpectedAgentName(
    Dictionary<string, string> values,
    string expected,
    string path,
    string sourceLabel,
    List<string> conflicts)
{
    if (values.TryGetValue("name", out var actual) && actual != expected)
    {
        conflicts.Add(sourceLabel + " custom agent name must be " + expected + ": " + path);
    }
}

static Dictionary<string, string> ReadTomlStrings(string path)
{
    var result = new Dictionary<string, string>(StringComparer.Ordinal);
    foreach (var rawLine in File.ReadLines(path))
    {
        var line = rawLine.Trim();
        var separator = line.IndexOf('=');
        if (separator <= 0)
        {
            continue;
        }

        var key = line[..separator].Trim();
        var encodedValue = line[(separator + 1)..].Trim();
        if (encodedValue.Length >= 2 && encodedValue[0] == '"' && encodedValue[^1] == '"')
        {
            result[key] = encodedValue[1..^1];
        }
    }

    return result;
}

static void WriteText(string path, string content)
{
    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    File.WriteAllText(path, content.Replace("\n", Environment.NewLine), new UTF8Encoding(false));
}

static string Normalize(string text) => text.Replace("\r\n", "\n").Replace("\r", "\n");

internal sealed record Options(
    string TargetRoot,
    bool DryRun,
    bool Check,
    bool Force,
    bool Remove,
    bool IsValid);

internal enum OperationKind
{
    Unchanged,
    Create,
    Update,
    Delete
}

internal sealed record PlannedOperation(
    OperationKind Kind,
    string Description,
    Action? Apply)
{
    public static PlannedOperation Unchanged(string description) =>
        new(OperationKind.Unchanged, description, null);
}
