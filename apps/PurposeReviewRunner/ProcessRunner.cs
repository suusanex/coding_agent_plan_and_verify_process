using System.Diagnostics;
using System.Text;

namespace PurposeReviewRunner;

public sealed record ProcessRequest(
    string Executable,
    IReadOnlyList<string> Arguments,
    string WorkingDirectory,
    string? StandardInput);

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError, bool TimedOut);

public interface IProcessRunner
{
    Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken);
}

public sealed class SystemProcessRunner : IProcessRunner
{
    private readonly TimeSpan timeout;

    public SystemProcessRunner(TimeSpan timeout) => this.timeout = timeout;

    public async Task<ProcessResult> RunAsync(ProcessRequest request, CancellationToken cancellationToken)
    {
        var startInfo = CreateStartInfo(request);
        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start())
            {
                throw new RunnerException("PROVIDER_START_FAILED", "Provider process did not start.", ExitCodes.RuntimeError);
            }
            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
            if (request.StandardInput is not null)
            {
                await process.StandardInput.WriteAsync(request.StandardInput.AsMemory(), cancellationToken);
            }
            process.StandardInput.Close();

            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutSource.CancelAfter(timeout);
            try
            {
                await process.WaitForExitAsync(timeoutSource.Token);
            }
            catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
            {
                Trace.TraceError(exception.ToString());
                TryKill(process);
                var timedOutStdout = await stdoutTask;
                var timedOutStderr = await stderrTask;
                return new(-1, timedOutStdout, timedOutStderr, true);
            }

            return new(process.ExitCode, await stdoutTask, await stderrTask, false);
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new RunnerException("PROVIDER_START_FAILED", $"Provider process failed: {exception.Message}", ExitCodes.RuntimeError, exception);
        }
    }

    private static ProcessStartInfo CreateStartInfo(ProcessRequest request)
    {
        var isCommandScript = OperatingSystem.IsWindows() &&
            (request.Executable.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || request.Executable.EndsWith(".bat", StringComparison.OrdinalIgnoreCase));
        var startInfo = new ProcessStartInfo
        {
            FileName = isCommandScript ? Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe" : request.Executable,
            WorkingDirectory = request.WorkingDirectory,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        if (isCommandScript)
        {
            startInfo.Arguments = "/d /s /c " + BuildCommandScriptInvocation(request.Executable, request.Arguments);
        }
        else
        {
            foreach (var argument in request.Arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }
        }
        return startInfo;
    }

    private static string BuildCommandScriptInvocation(string executable, IReadOnlyList<string> arguments)
    {
        static string Quote(string value) => "\"" + value.Replace("%", "%%", StringComparison.Ordinal).Replace("\"", "\"\"", StringComparison.Ordinal) + "\"";
        return "\"" + Quote(executable) + " " + string.Join(" ", arguments.Select(Quote)) + "\"";
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(true);
                process.WaitForExit();
            }
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
        }
    }
}
