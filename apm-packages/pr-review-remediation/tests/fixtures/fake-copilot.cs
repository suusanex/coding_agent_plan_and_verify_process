#:property TargetFramework=net10.0
#:property PublishAot=false

var scenario = Environment.GetEnvironmentVariable("FAKE_COPILOT_SCENARIO") ?? "success";
var statePath = Environment.GetEnvironmentVariable("FAKE_COPILOT_STATE");
if (!string.IsNullOrWhiteSpace(statePath))
{
    File.AppendAllText(statePath, string.Join('\t', args) + Environment.NewLine);
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

Console.Write(body + "\n");
return 0;
