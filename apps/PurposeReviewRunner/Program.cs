using System.Diagnostics;
using System.Text.Json;
using PurposeReviewRunner;

return await MainAsync(args);

static async Task<int> MainAsync(string[] args)
{
    Trace.Listeners.Clear();
    Trace.Listeners.Add(new TextWriterTraceListener(Console.Error));
    Trace.AutoFlush = true;
    try
    {
        var paths = RunnerPaths.CreateDefault();
        var application = new RunnerApplication(
            paths,
            new ExecutableResolver(),
            new SystemProcessRunner(TimeSpan.FromMinutes(10)));
        var command = CliParser.Parse(args);
        var result = await application.ExecuteAsync(command, CancellationToken.None);
        Console.WriteLine(JsonSerializer.Serialize(result.Output, JsonDefaults.Options));
        return result.ExitCode;
    }
    catch (Exception exception)
    {
        Trace.TraceError(exception.ToString());
        var runnerException = exception as RunnerException;
        var exitCode = runnerException?.ExitCode ?? ExitCodes.RuntimeError;
        var code = runnerException?.Code ?? "UNEXPECTED_ERROR";
        var output = RunnerOutput.FromError(code, exception.Message);
        Console.WriteLine(JsonSerializer.Serialize(output, JsonDefaults.Options));
        return exitCode;
    }
}
