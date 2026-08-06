#:property TargetFramework=net10.0
#:property PublishAot=false

using System.Text.Json;

var scenario = Environment.GetEnvironmentVariable("FAKE_CODEX_SCENARIO") ?? "success";
var statePath = Environment.GetEnvironmentVariable("FAKE_CODEX_STATE");
if (!string.IsNullOrWhiteSpace(statePath))
{
    File.AppendAllText(statePath, string.Join('\t', args) + Environment.NewLine);
}

// Drain stdin when present so callers can deliver prompts off-argv.
// Exception: "stdin_closed_early" scenario closes stdin immediately to test delivery failure.
if (scenario == "stdin_closed_early")
{
    try
    {
        if (Console.IsInputRedirected)
        {
            // Close stdin immediately without reading to force parent write failure.
            Console.In.Close();
        }
    }
    catch { }
    // Continue to write success output and exit with code 0.
}
else
{
    try
    {
        if (!Console.IsInputRedirected)
        {
            // no-op
        }
        else
        {
            _ = Console.In.ReadToEnd();
        }
    }
    catch
    {
        // ignore
    }
}

if (args.Length == 0 || args[0] != "exec")
{
    Console.Error.WriteLine("fake-codex expects exec");
    return 2;
}

string? outputPath = null;
string? model = null;
for (var i = 0; i < args.Length; i++)
{
    if (args[i] == "-o" && i + 1 < args.Length) outputPath = args[i + 1];
    if (args[i] == "-m" && i + 1 < args.Length) model = args[i + 1];
}

// Fail if a huge positional prompt leaked onto argv (anything after known flags that is not a flag value).
for (var i = 1; i < args.Length; i++)
{
    var arg = args[i];
    if (arg is "--json" or "--strict-config" or "--ignore-user-config") continue;
    if (arg is "-C" or "-m" or "-s" or "-c" or "-o")
    {
        i++;
        continue;
    }
    if (arg.Length > 200)
    {
        Console.Error.WriteLine("fake-codex rejected oversized argv payload");
        return 9;
    }
}

if (scenario == "timeout")
{
    Thread.Sleep(TimeSpan.FromSeconds(30));
    return 0;
}

if (scenario == "auth_failure")
{
    Console.Error.WriteLine("not authenticated: run codex login");
    return 1;
}

if (scenario == "non_zero")
{
    Console.Error.WriteLine("simulated codex failure");
    return 3;
}

if (scenario == "empty")
{
    Console.WriteLine(JsonSerializer.Serialize(new { type = "thread.started", thread_id = "t1", model = model ?? "gpt-5.6-terra" }));
    Console.WriteLine(JsonSerializer.Serialize(new { type = "turn.completed" }));
    if (!string.IsNullOrWhiteSpace(outputPath)) File.WriteAllText(outputPath, "");
    return 0;
}

if (scenario == "malformed")
{
    Console.WriteLine("{not-json");
    return 0;
}

if (scenario == "jsonl_error")
{
    Console.WriteLine(JsonSerializer.Serialize(new { type = "thread.started", thread_id = "t1", model = model ?? "gpt-5.6-terra" }));
    Console.WriteLine(JsonSerializer.Serialize(new { type = "error", message = "boom" }));
    return 0;
}

if (scenario == "write")
{
    var repo = ".";
    for (var i = 0; i < args.Length - 1; i++)
    {
        if (args[i] == "-C") repo = args[i + 1];
    }
    File.WriteAllText(Path.Combine(repo, "reviewer-wrote.txt"), "mutation\n");
}

var body = """
# Local Review Findings

- Verdict: REVIEWED
- Finding IDs: none

## Findings

No findings.

- Production code changed: No
""";

if (scenario == "purpose")
{
    body = """
# Purpose Review Findings

- Verdict: PURPOSE_REVIEWED

## Findings

No findings.

- Production code changed: No
""";
}

if (scenario == "missing_marker")
{
    body = """
# Local Review Findings

No findings.
""";
}

Console.WriteLine(JsonSerializer.Serialize(new { type = "thread.started", thread_id = "fake-thread", model = model ?? "gpt-5.6-terra" }));
Console.WriteLine(JsonSerializer.Serialize(new { type = "turn.completed" }));
if (!string.IsNullOrWhiteSpace(outputPath)) File.WriteAllText(outputPath, body + "\n");
return 0;
