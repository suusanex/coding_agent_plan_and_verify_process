using System.Diagnostics;
using System.Text.Json;

namespace PurposeReviewRunner;

public sealed class StateStore
{
    private readonly string root;

    public StateStore(string root) => this.root = Path.GetFullPath(root);

    public string GetRunDirectory(string runId)
    {
        if (!Guid.TryParseExact(runId, "D", out _))
        {
            throw new RunnerException("INVALID_RUN_ID", "run-id must be a canonical UUID.");
        }
        return Path.Combine(root, runId);
    }

    public IDisposable AcquireLock(string runId)
    {
        var directory = GetRunDirectory(runId);
        try
        {
            Directory.CreateDirectory(directory);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            throw new RunnerException("RUN_LOCK_FAILED", "The review run lock directory could not be created.", ExitCodes.ContractError, exception);
        }
        try
        {
            return new FileStream(Path.Combine(directory, "run.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException exception)
        {
            throw new RunnerException("RUN_BUSY", "The review run is already being changed by another process.", ExitCodes.ContractError, exception);
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException)
        {
            throw new RunnerException("RUN_LOCK_FAILED", "The review run lock could not be opened.", ExitCodes.ContractError, exception);
        }
    }

    public RunState Load(string runId)
    {
        var statePath = Path.Combine(GetRunDirectory(runId), "state.json");
        if (!File.Exists(statePath))
        {
            throw new RunnerException("STATE_NOT_FOUND", $"Run state was not found for {runId}.");
        }
        try
        {
            var state = JsonSerializer.Deserialize<RunState>(File.ReadAllText(statePath), JsonDefaults.Options)
                ?? throw new JsonException("State JSON was empty.");
            if (state.ProtocolVersion != Protocol.Version || state.RunId != runId)
            {
                throw new RunnerException("STATE_INCOMPATIBLE", "Run state protocol or identity is incompatible.");
            }
            Validate(state);
            return state;
        }
        catch (RunnerException)
        {
            throw;
        }
        catch (Exception exception) when (exception is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new RunnerException("STATE_INVALID", $"Run state could not be read: {exception.Message}", ExitCodes.ContractError, exception);
        }
    }

    public void Save(RunState state)
    {
        var directory = GetRunDirectory(state.RunId);
        var statePath = Path.Combine(directory, "state.json");
        var temporaryPath = statePath + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            Validate(state);
            Directory.CreateDirectory(directory);
            var json = JsonSerializer.Serialize(state, JsonDefaults.Options) + Environment.NewLine;
            File.WriteAllText(temporaryPath, json, new System.Text.UTF8Encoding(false));
            File.Move(temporaryPath, statePath, true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            throw new RunnerException("STATE_WRITE_FAILED", "Run state could not be saved.", ExitCodes.ContractError, exception);
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

    private static void Validate(RunState state)
    {
        if (string.IsNullOrWhiteSpace(state.Repository) || !Path.IsPathFullyQualified(state.Repository) || state.ContextPaths is null || state.ContextPaths.Count == 0 ||
            state.ContextPaths.Any(path => string.IsNullOrWhiteSpace(path) || !Path.IsPathFullyQualified(path)) || string.IsNullOrWhiteSpace(state.SessionHandle) ||
            state.Round is < 1 or > Protocol.MaximumRounds ||
            state.Status is not (ReviewStatuses.Findings or ReviewStatuses.Complete or ReviewStatuses.HumanDecisionRequired or ReviewStatuses.Blocked or ReviewStatuses.Error) ||
            state.Provider is null || state.Provider.Provider is not ("codex" or "grok" or "copilot") ||
            string.IsNullOrWhiteSpace(state.Provider.Executable) || !Path.IsPathFullyQualified(state.Provider.Executable) ||
            string.IsNullOrWhiteSpace(state.Provider.Model) || string.IsNullOrWhiteSpace(state.Provider.ReasoningEffort))
        {
            throw new RunnerException("STATE_INVALID", "Run state contains invalid control data.");
        }
    }
}
