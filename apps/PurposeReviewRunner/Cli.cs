namespace PurposeReviewRunner;

public abstract record RunnerCommand;
public sealed record StartCommand(string Repository, string InputPath) : RunnerCommand;
public sealed record ContinueCommand(string RunId, string InputPath) : RunnerCommand;
public sealed record StatusCommand(string RunId) : RunnerCommand;
public sealed record WorkCommand(string RunId) : RunnerCommand;
public sealed record VersionCommand : RunnerCommand;

public static class CliParser
{
    public static RunnerCommand Parse(string[] args)
    {
        if (args.Length == 1 && args[0] == "version")
        {
            return new VersionCommand();
        }

        if (args.Length == 0)
        {
            throw Usage("A command is required.");
        }

        return args[0] switch
        {
            "start" => ParseStart(args[1..]),
            "status" => ParseRunCommand(args[1..], "status", runId => new StatusCommand(runId)),
            "work" => ParseRunCommand(args[1..], "work", runId => new WorkCommand(runId)),
            "continue" => ParseContinue(args[1..]),
            _ => throw Usage($"Unknown command: {args[0]}")
        };
    }

    private static StartCommand ParseStart(string[] args)
    {
        string? repository = null;
        string? input = null;
        for (var index = 0; index < args.Length; index++)
        {
            var option = args[index];
            var value = NextValue(args, ref index, option);
            switch (option)
            {
                case "--repository":
                    if (repository is not null)
                    {
                        throw Usage("--repository can be specified only once.");
                    }
                    repository = value;
                    break;
                case "--input":
                    if (input is not null)
                    {
                        throw Usage("--input can be specified only once.");
                    }
                    input = value;
                    break;
                default:
                    throw Usage($"Unknown start option: {option}");
            }
        }

        if (string.IsNullOrWhiteSpace(repository))
        {
            throw Usage("start requires --repository <path>.");
        }
        if (string.IsNullOrWhiteSpace(input))
        {
            throw Usage("start requires --input <path>.");
        }
        return new(repository, input);
    }

    private static ContinueCommand ParseContinue(string[] args)
    {
        string? runId = null;
        string? input = null;
        for (var index = 0; index < args.Length; index++)
        {
            var option = args[index];
            var value = NextValue(args, ref index, option);
            switch (option)
            {
                case "--run" when runId is null:
                    runId = value;
                    break;
                case "--input" when input is null:
                    input = value;
                    break;
                default:
                    throw Usage($"Invalid or duplicate continue option: {option}");
            }
        }
        if (string.IsNullOrWhiteSpace(runId) || string.IsNullOrWhiteSpace(input))
        {
            throw Usage("continue requires --run <run-id> and --input <path>.");
        }
        return new(runId, input);
    }

    private static RunnerCommand ParseRunCommand(string[] args, string command, Func<string, RunnerCommand> create)
    {
        if (args.Length != 2 || args[0] != "--run" || string.IsNullOrWhiteSpace(args[1]))
        {
            throw Usage($"{command} requires exactly --run <run-id>.");
        }
        return create(args[1]);
    }

    private static string NextValue(string[] args, ref int index, string option)
    {
        if (!option.StartsWith("--", StringComparison.Ordinal) || index + 1 >= args.Length)
        {
            throw Usage($"{option} requires a value.");
        }
        var value = args[++index];
        if (string.IsNullOrWhiteSpace(value) || value.StartsWith("--", StringComparison.Ordinal))
        {
            throw Usage($"{option} requires a non-empty value.");
        }
        return value;
    }

    private static RunnerException Usage(string message) =>
        new("INVALID_ARGUMENTS", message + " Usage: purpose-review-runner start --repository <path> --input <path> | continue --run <run-id> --input <path> | status --run <run-id> | version");
}
