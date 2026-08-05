#:property TargetFramework=net10.0
#:property PublishAot=false

var scenario = Environment.GetEnvironmentVariable("FAKE_COPILOT_SCENARIO") ?? "success";
var statePath = Environment.GetEnvironmentVariable("FAKE_COPILOT_STATE");
if (!string.IsNullOrWhiteSpace(statePath))
{
    File.AppendAllText(statePath, string.Join('\t', args) + Environment.NewLine);
}

// Reject full prompt payloads on argv.
for (var i = 0; i < args.Length; i++)
{
    if (args[i] is "-p" or "--prompt")
    {
        var prompt = i + 1 < args.Length ? args[i + 1] : "";
        if (prompt.Length > 500 || prompt.Contains("review-context.json", StringComparison.Ordinal))
        {
            Console.Error.WriteLine("fake-copilot rejected full prompt on argv");
            return 9;
        }
    }
}

if (scenario == "timeout")
{
    Thread.Sleep(TimeSpan.FromSeconds(30));
    return 0;
}

if (scenario == "auth_failure")
{
    Console.Error.WriteLine("Error: not authenticated. Run copilot login.");
    return 1;
}

if (scenario == "non_zero")
{
    Console.Error.WriteLine("simulated copilot failure");
    return 4;
}

if (scenario == "empty")
{
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
    body = "hello from copilot without contract markers";
}

Console.Write(body + "\n");
return 0;
