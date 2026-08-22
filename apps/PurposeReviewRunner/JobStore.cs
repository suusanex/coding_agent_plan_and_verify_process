using System.Diagnostics;
using System.Text.Json;

namespace PurposeReviewRunner;

public sealed class JobStore
{
    private readonly string root;

    public JobStore(string root) => this.root = Path.GetFullPath(root);

    public string GetRunDirectory(string runId)
    {
        if (!Guid.TryParseExact(runId, "D", out _))
        {
            throw new RunnerException("INVALID_RUN_ID", "run-id must be a canonical UUID.");
        }
        return Path.Combine(root, runId);
    }

    public bool Exists(string runId) => File.Exists(JobPath(runId));

    public JobState Load(string runId)
    {
        var path = JobPath(runId);
        if (!File.Exists(path))
        {
            throw new RunnerException("JOB_NOT_FOUND", $"Job state was not found for {runId}.");
        }
        try
        {
            var job = JsonSerializer.Deserialize<JobState>(File.ReadAllText(path), JsonDefaults.Options)
                ?? throw new JsonException("Job JSON was empty.");
            if (job.RunId != runId)
            {
                throw new RunnerException("STATE_INCOMPATIBLE", "Job identity is incompatible.");
            }
            Validate(job);
            return job;
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new RunnerException("JOB_INVALID", $"Job state could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }
    }

    public JobResult LoadResult(string runId)
    {
        var path = ResultPath(runId);
        if (!File.Exists(path))
        {
            throw new RunnerException("RESULT_NOT_FOUND", $"Job result was not found for {runId}.");
        }
        try
        {
            var result = JsonSerializer.Deserialize<JobResult>(File.ReadAllText(path), JsonDefaults.Options)
                ?? throw new JsonException("Result JSON was empty.");
            return result;
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new RunnerException("RESULT_INVALID", $"Job result could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }
    }

    public bool TryLoadResult(string runId, out JobResult result)
    {
        result = null!;
        if (!File.Exists(ResultPath(runId)))
        {
            return false;
        }
        result = LoadResult(runId);
        return true;
    }

    public void Save(JobState job)
    {
        Validate(job);
        WriteAtomic(JobPath(job.RunId), JsonSerializer.Serialize(job, JsonDefaults.Options));
    }

    public void SaveResult(string runId, JobResult result)
    {
        if (!Guid.TryParseExact(runId, "D", out _))
        {
            throw new RunnerException("INVALID_RUN_ID", "run-id must be a canonical UUID.");
        }
        WriteAtomic(ResultPath(runId), JsonSerializer.Serialize(result, JsonDefaults.Options));
    }

    public void DeleteResult(string runId)
    {
        var path = ResultPath(runId);
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new RunnerException("STATE_WRITE_FAILED", "Previous job result could not be cleared.", ExitCodes.ContractError, exception);
        }
    }

    private string JobPath(string runId) => Path.Combine(GetRunDirectory(runId), "job.json");

    private string ResultPath(string runId) => Path.Combine(GetRunDirectory(runId), "result.json");

    private static void WriteAtomic(string path, string json)
    {
        var directory = Path.GetDirectoryName(path) ?? throw new RunnerException("STATE_WRITE_FAILED", "Run state directory was invalid.");
        var temporaryPath = path + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(temporaryPath, json + Environment.NewLine, new System.Text.UTF8Encoding(false));
            File.Move(temporaryPath, path, true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            throw new RunnerException("STATE_WRITE_FAILED", "Job state could not be saved.", ExitCodes.ContractError, exception);
        }
        finally
        {
            try
            {
                if (File.Exists(temporaryPath))
                {
                    File.Delete(temporaryPath);
                }
            }
            catch (Exception exception)
            {
                Trace.TraceError(exception.ToString());
            }
        }
    }

    private static void Validate(JobState job)
    {
        if (job.SchemaVersion != 1 ||
            string.IsNullOrWhiteSpace(job.RunId) ||
            job.Round is < 1 or > Protocol.MaximumRounds ||
            job.Operation is not (JobOperations.Start or JobOperations.Continue) ||
            job.JobStatus is not (JobStatuses.Running or JobStatuses.Succeeded or JobStatuses.Failed) ||
            job.StartedAtUtc == default)
        {
            throw new RunnerException("JOB_INVALID", "Job state contains invalid control data.");
        }

        if (job.Operation == JobOperations.Start)
        {
            if (string.IsNullOrWhiteSpace(job.Repository) || !Path.IsPathFullyQualified(job.Repository) ||
                job.ContextPaths is null || job.ContextPaths.Count == 0 ||
                job.ContextPaths.Any(path => string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path)) ||
                job.Provider is null || job.Provider.Provider is not ("codex" or "grok" or "copilot") ||
                string.IsNullOrWhiteSpace(job.Provider.Executable) || !Path.IsPathFullyQualified(job.Provider.Executable) ||
                string.IsNullOrWhiteSpace(job.Provider.Model) || string.IsNullOrWhiteSpace(job.Provider.ReasoningEffort))
            {
                throw new RunnerException("JOB_INVALID", "Job state contains invalid start control data.");
            }
        }
    }
}

public static class WorkerProcessStatus
{
    public static bool IsAlive(int? pid, DateTimeOffset? processStartTimeUtc)
    {
        if (pid is null or <= 0)
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById(pid.Value);
            if (process.HasExited)
            {
                return false;
            }
            if (processStartTimeUtc is DateTimeOffset expected)
            {
                var actual = process.StartTime.ToUniversalTime();
                if (Math.Abs((actual - expected.UtcDateTime).TotalSeconds) > 3)
                {
                    return false;
                }
            }
            return true;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception)
        {
            // プロセスは存在するが開始時刻を読めない場合、PID reuse 判定ができない。誤って abandoned にしない。
            Trace.TraceError(exception.ToString());
            return true;
        }
    }
}
