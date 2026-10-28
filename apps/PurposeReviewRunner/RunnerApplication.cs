using System.Diagnostics;

namespace PurposeReviewRunner;

public sealed class RunnerApplication
{
    private static readonly TimeSpan WorkerStartGrace = TimeSpan.FromSeconds(60);

    private readonly RunnerPaths paths;
    private readonly IExecutableResolver executableResolver;
    private readonly IProcessRunner processRunner;
    private readonly IWorkerLauncher workerLauncher;
    private readonly StateStore stateStore;
    private readonly JobStore jobStore;
    private readonly IChangeMetadataCollector changeMetadataCollector;
    private readonly InvestigatorBypass investigatorBypass;

    public RunnerApplication(RunnerPaths paths, IExecutableResolver executableResolver, IProcessRunner processRunner, IWorkerLauncher workerLauncher, IChangeMetadataCollector? changeMetadataCollector = null)
    {
        this.paths = paths;
        this.executableResolver = executableResolver;
        this.processRunner = processRunner;
        this.workerLauncher = workerLauncher;
        stateStore = new(paths.StateRoot);
        jobStore = new(paths.StateRoot);
        this.changeMetadataCollector = changeMetadataCollector ?? new GitChangeMetadataCollector(processRunner, executableResolver);
        investigatorBypass = new(processRunner, executableResolver);
    }

    public Task<ExecutionResult> ExecuteAsync(RunnerCommand command, CancellationToken cancellationToken) => command switch
    {
        VersionCommand => Task.FromResult(new ExecutionResult(RunnerOutput.Version(), ExitCodes.Success)),
        StartCommand start => SubmitStartAsync(start, cancellationToken),
        ContinueCommand continuation => SubmitContinueAsync(continuation, cancellationToken),
        StatusCommand status => Task.FromResult(Status(status)),
        WorkCommand work => WorkAsync(work, cancellationToken),
        _ => throw new RunnerException("INVALID_ARGUMENTS", "Unsupported command.")
    };

    private Task<ExecutionResult> SubmitStartAsync(StartCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var repository = NormalizePath(command.Repository, "REPOSITORY_PATH_INVALID", "Repository path was invalid.");
        if (!Directory.Exists(repository))
        {
            throw new RunnerException("REPOSITORY_NOT_FOUND", $"Repository directory was not found: {repository}");
        }
        var contexts = ResolveContexts(repository, command.ContextPaths);
        var config = ConfigLoader.Load(paths.ConfigPath);
        var snapshot = new ProviderSnapshot(
            config.Provider,
            config.Executable,
            config.Model,
            config.ReasoningEffort,
            config.Profile);
        snapshot = ResolveSnapshot(snapshot);
        var investigator = config.Investigator;
        if (investigator is not null)
        {
            try { investigator = ResolveSnapshot(investigator); }
            catch (Exception exception) { Trace.TraceError(exception.ToString()); }
        }
        var runId = Guid.NewGuid().ToString("D");
        var job = new JobState(
            1,
            runId,
            1,
            JobOperations.Start,
            JobStatuses.Running,
            DateTimeOffset.UtcNow,
            Repository: repository,
            ContextPaths: contexts.Select(context => context.Path).ToArray(),
            Provider: snapshot,
            Investigator: investigator,
            InitialContexts: contexts.Select(context => new ContextSnapshot(context.Path, context.Content)).ToArray());
        using (stateStore.AcquireLock(runId))
        {
            jobStore.Save(job);
        }

        return Task.FromResult(LaunchSubmittedJob(runId));
    }

    private Task<ExecutionResult> SubmitContinueAsync(ContinueCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using (stateStore.AcquireLock(command.RunId))
        {
            var state = stateStore.Load(command.RunId);
            if (state.Status != ReviewStatuses.Findings)
            {
                throw new RunnerException("RUN_TERMINAL", $"Run is already terminal with status {state.Status}.");
            }
            if (state.Round >= Protocol.MaximumRounds)
            {
                throw new RunnerException("MAX_ROUNDS_REACHED", "The review run has already reached the maximum of three rounds.");
            }
            if (!Directory.Exists(state.Repository))
            {
                throw new RunnerException("REPOSITORY_NOT_FOUND", $"Repository directory was not found: {state.Repository}");
            }
            if (jobStore.Exists(command.RunId))
            {
                var existing = jobStore.Load(command.RunId);
                if (existing.JobStatus == JobStatuses.Running)
                {
                    throw new RunnerException("JOB_IN_PROGRESS", "The review run already has a worker in progress.");
                }
                if (existing.JobStatus == JobStatuses.Failed)
                {
                    throw new RunnerException("RUN_TERMINAL", "Run is already terminal with status ERROR.");
                }
            }

            var nextRound = state.Round + 1;
            jobStore.Save(new JobState(
                1,
                command.RunId,
                nextRound,
                JobOperations.Continue,
                JobStatuses.Running,
                DateTimeOffset.UtcNow,
                Repository: state.Repository,
                Provider: state.Provider,
                Investigator: state.Investigator,
                InitialContexts: state.InitialContexts));
            jobStore.DeleteResult(command.RunId);
        }

        return Task.FromResult(LaunchSubmittedJob(command.RunId));
    }

    private ExecutionResult LaunchSubmittedJob(string runId)
    {
        WorkerLaunchResult? launched = null;
        try
        {
            launched = workerLauncher.Launch(runId);
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            PersistLaunchFailure(runId, exception);
            if (jobStore.TryLoadResult(runId, out _))
            {
                return ReadStoredResult(runId);
            }
            if (exception is RunnerException)
            {
                throw;
            }
            throw new RunnerException("WORKER_START_FAILED", $"The review worker process did not start: {exception.Message}", ExitCodes.RuntimeError, exception);
        }

        TryRecordWorkerProcess(runId, launched);
        return ReadSnapshot(runId);
    }

    private void PersistLaunchFailure(string runId, Exception exception)
    {
        var runnerException = exception as RunnerException;
        var code = runnerException?.Code ?? "WORKER_START_FAILED";
        var message = runnerException?.Code == "WORKER_START_FAILED" ? runnerException.Message : $"The review worker process did not start: {exception.Message}";
        var exitCode = runnerException?.ExitCode ?? ExitCodes.RuntimeError;
        try
        {
            using var runLock = stateStore.AcquireLock(runId);
            var job = jobStore.Load(runId);
            if (job.JobStatus != JobStatuses.Running)
            {
                return;
            }
            PersistFailure(job, code, message, exitCode);
        }
        catch (Exception persistException)
        {
            Trace.TraceError(persistException.ToString());
        }
    }

    private void TryRecordWorkerProcess(string runId, WorkerLaunchResult launched)
    {
        try
        {
            using var runLock = stateStore.AcquireLock(runId);
            var job = jobStore.Load(runId);
            if (job.JobStatus != JobStatuses.Running)
            {
                return;
            }
            jobStore.Save(job with { Pid = launched.ProcessId, ProcessStartTimeUtc = launched.ProcessStartTimeUtc });
        }
        catch (Exception exception) when (exception is RunnerException { Code: "RUN_BUSY" })
        {
            Trace.TraceError(exception.ToString());
        }
    }

    private ExecutionResult Status(StatusCommand command)
    {
        var job = jobStore.Load(command.RunId);
        if (job.JobStatus != JobStatuses.Running)
        {
            return ReadStoredResult(command.RunId);
        }

        if (WorkerProcessStatus.IsAlive(job.Pid, job.ProcessStartTimeUtc) ||
            (job.Pid is null && DateTimeOffset.UtcNow - job.StartedAtUtc < WorkerStartGrace))
        {
            return new(RunnerOutput.Running(command.RunId, job.Round), ExitCodes.Success);
        }

        using var runLock = stateStore.AcquireLock(command.RunId);
        job = jobStore.Load(command.RunId);
        if (job.JobStatus != JobStatuses.Running)
        {
            return ReadStoredResult(command.RunId);
        }
        if (WorkerProcessStatus.IsAlive(job.Pid, job.ProcessStartTimeUtc) ||
            (job.Pid is null && DateTimeOffset.UtcNow - job.StartedAtUtc < WorkerStartGrace))
        {
            return new(RunnerOutput.Running(command.RunId, job.Round), ExitCodes.Success);
        }
        if (jobStore.TryLoadResult(command.RunId, out var stored) && stored.Output.Round == job.Round)
        {
            var finishedStatus = stored.Output.Error is null ? JobStatuses.Succeeded : JobStatuses.Failed;
            jobStore.Save(job with { JobStatus = finishedStatus, FinishedAtUtc = DateTimeOffset.UtcNow });
            return new(stored.Output, stored.ExitCode);
        }

        PersistFailure(job, "WORKER_ABANDONED", "The review worker process is no longer running and did not store a result.", ExitCodes.RuntimeError);
        TryMarkStateError(command.RunId);
        return ReadStoredResult(command.RunId);
    }

    private async Task<ExecutionResult> WorkAsync(WorkCommand command, CancellationToken cancellationToken)
    {
        using var runLock = stateStore.AcquireLock(command.RunId);
        var job = jobStore.Load(command.RunId);
        if (job.JobStatus is JobStatuses.Succeeded or JobStatuses.Failed)
        {
            return ReadStoredResult(command.RunId);
        }
        if (job.JobStatus != JobStatuses.Running)
        {
            throw new RunnerException("JOB_INVALID", $"Job status {job.JobStatus} cannot be executed.");
        }

        jobStore.Save(job with
        {
            Pid = Environment.ProcessId,
            ProcessStartTimeUtc = new DateTimeOffset(Process.GetCurrentProcess().StartTime.ToUniversalTime())
        });
        job = jobStore.Load(command.RunId);

        try
        {
            await ExecuteRoundAsync(job, cancellationToken);
            return ReadStoredResult(command.RunId);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            var runnerException = exception as RunnerException;
            PersistFailure(
                job,
                runnerException?.Code ?? "UNEXPECTED_ERROR",
                exception.Message,
                runnerException?.ExitCode ?? ExitCodes.RuntimeError);
            return ReadStoredResult(command.RunId);
        }
    }

    private async Task ExecuteRoundAsync(JobState job, CancellationToken cancellationToken)
    {
        if (job.Operation == JobOperations.Start)
        {
            await ExecuteStartRoundAsync(job, cancellationToken);
            return;
        }
        await ExecuteContinueRoundAsync(job, cancellationToken);
    }

    private async Task ExecuteStartRoundAsync(JobState job, CancellationToken cancellationToken)
    {
        var repository = job.Repository ?? throw new RunnerException("JOB_INVALID", "Start job is missing a repository.");
        var contextPaths = job.ContextPaths ?? throw new RunnerException("JOB_INVALID", "Start job is missing context paths.");
        var snapshot = job.Provider ?? throw new RunnerException("JOB_INVALID", "Start job is missing a provider snapshot.");
        if (!Directory.Exists(repository))
        {
            throw new RunnerException("REPOSITORY_NOT_FOUND", $"Repository directory was not found: {repository}");
        }

        var contexts = job.InitialContexts?.Select(context => (context.Path, context.Content)).ToArray() ?? ResolveContexts(repository, contextPaths);
        var changeMetadata = await changeMetadataCollector.CollectAsync(repository, cancellationToken);
        var snapshotPath = job.Investigator is null ? null : await investigatorBypass.CaptureAsync(repository, stateStore.GetRunDirectory(job.RunId), 1, cancellationToken);
        var reportPath = await RunInvestigatorAsync(job, repository, contexts, changeMetadata, cancellationToken);
        var unavailable = job.Investigator is null ? "INVESTIGATOR_BYPASSED" : reportPath is null ? "INVESTIGATOR_UNAVAILABLE" : null;
        var payload = PromptBuilder.BuildStart(repository, contexts, changeMetadata, reportPath, unavailable);
        var transcriptStore = new TranscriptStore(stateStore.GetRunDirectory(job.RunId));
        transcriptStore.SavePrompt(1, payload);
        var provider = ProviderFactory.Create(snapshot.Provider);
        var providerResult = await provider.ExecuteAsync(
            new(snapshot, repository, stateStore.GetRunDirectory(job.RunId), payload, null, 1),
            processRunner,
            cancellationToken);
        transcriptStore.SaveResponse(1, providerResult.ReviewText);
        var review = ReviewProtocol.Parse(providerResult.ReviewText);
        var state = new RunState(
            Protocol.Version,
            job.RunId,
            repository,
            contextPaths.ToArray(),
            snapshot,
            providerResult.SessionHandle,
            1,
            review.Status,
            job.Investigator,
            job.InitialContexts?.ToArray() ?? contexts.Select(context => new ContextSnapshot(context.Path, context.Content)).ToArray(),
            await SnapshotUnchangedAsync(repository, stateStore.GetRunDirectory(job.RunId), 1, snapshotPath, cancellationToken) ? snapshotPath : null,
            [new InvestigatorBypassDecision(1, job.Investigator is null ? "disabled" : "run", job.Investigator is null ? "investigator-not-configured" : "round-1-baseline")]);
        stateStore.Save(state);
        PersistSuccess(job, RunnerOutput.FromReview(job.RunId, 1, review));
    }

    private async Task ExecuteContinueRoundAsync(JobState job, CancellationToken cancellationToken)
    {
        var state = stateStore.Load(job.RunId);
        if (job.Investigator != state.Investigator || (job.Provider is not null && job.Provider != state.Provider) ||
            (job.InitialContexts is not null && state.InitialContexts is not null && !job.InitialContexts.SequenceEqual(state.InitialContexts)))
        {
            throw new RunnerException("JOB_INVALID", "Continuation job role snapshots do not match the saved review run.");
        }
        if (state.Status != ReviewStatuses.Findings)
        {
            throw new RunnerException("RUN_TERMINAL", $"Run is already terminal with status {state.Status}.");
        }
        if (state.Round >= Protocol.MaximumRounds)
        {
            throw new RunnerException("MAX_ROUNDS_REACHED", "The review run has already reached the maximum of three rounds.");
        }
        if (!Directory.Exists(state.Repository))
        {
            throw new RunnerException("REPOSITORY_NOT_FOUND", $"Repository directory was not found: {state.Repository}");
        }

        var nextRound = state.Round + 1;
        if (nextRound != job.Round)
        {
            throw new RunnerException("JOB_INVALID", "Job round does not match the review state.");
        }

        var terminalState = state with { Round = nextRound, Status = ReviewStatuses.Error };
        stateStore.Save(terminalState);
        var changeMetadata = await changeMetadataCollector.CollectAsync(state.Repository, cancellationToken);
        var snapshotPath = state.Investigator is null ? null : await investigatorBypass.CaptureAsync(state.Repository, stateStore.GetRunDirectory(state.RunId), nextRound, cancellationToken);
        var autoBypassCandidate = false;
        var bypassReason = "investigator-not-configured";
        RepositoryChangeSize? changeSize = null;
        if (state.Investigator is not null)
        {
            bypassReason = "snapshot-unavailable";
            if (state.RepositorySnapshotPath is not null && snapshotPath is not null)
            {
                changeSize = await investigatorBypass.CompareAsync(state.RepositorySnapshotPath, snapshotPath, state.Repository, cancellationToken);
                bypassReason = changeSize is null ? "comparison-failed" : "change-above-threshold";
                if (changeSize is not null && changeSize.Files <= 3 && changeSize.AddedLines + changeSize.DeletedLines <= 40)
                {
                    autoBypassCandidate = true;
                    bypassReason = "small-delta";
                }
            }
            else
                changeMetadata += "\n前roundからの変更規模をRunnerが確定できませんでした。表示されたHEADとの差分や部分的な変更情報を、前roundからの完全な差分として扱わないでください。";
        }
        if (state.Investigator is not null && bypassReason == "comparison-failed")
            changeMetadata += "\n前roundからの変更規模をRunnerが確定できませんでした。表示されたHEADとの差分や部分的な変更情報を、前roundからの完全な差分として扱わないでください。";
        var initialContexts = state.InitialContexts?.Select(context => (context.Path, context.Content)).ToArray()
            ?? (state.Investigator is null ? [] : ResolveContexts(state.Repository, state.ContextPaths));
        var autoBypassed = autoBypassCandidate && await SnapshotUnchangedAsync(state.Repository, stateStore.GetRunDirectory(state.RunId), nextRound, snapshotPath, cancellationToken);
        if (autoBypassCandidate && !autoBypassed)
        {
            bypassReason = "repository-changed-before-lead";
            changeMetadata += "\n前roundからの変更規模をRunnerが確定できませんでした。表示されたHEADとの差分や部分的な変更情報を、前roundからの完全な差分として扱わないでください。";
        }
        else if (autoBypassed)
            bypassReason = "small-delta-with-stable-snapshot";
        if (autoBypassed && changeSize is not null)
            changeMetadata += $"\nAutomatic Investigator bypass: compared round {state.Round} start snapshot (verified unchanged at round end) to round {nextRound} start; scope={changeSize.Scope}; paths={string.Join(", ", changeSize.Paths)}; files={changeSize.Files}; added={changeSize.AddedLines}; deleted={changeSize.DeletedLines}.";
        var decision = new InvestigatorBypassDecision(
            nextRound,
            state.Investigator is null ? "disabled" : autoBypassed ? "bypassed" : "run",
            bypassReason,
            state.Investigator is null ? null : state.Round,
            changeSize?.Scope,
            changeSize?.Files,
            changeSize?.AddedLines,
            changeSize?.DeletedLines,
            changeSize?.Paths);
        terminalState = terminalState with { InvestigatorBypassHistory = (state.InvestigatorBypassHistory ?? []).Append(decision).ToArray() };
        stateStore.Save(terminalState);
        var reportPath = autoBypassed ? null : await RunInvestigatorAsync(job, state.Repository, initialContexts, changeMetadata, cancellationToken);
        var unavailable = state.Investigator is null ? "INVESTIGATOR_BYPASSED" : autoBypassed ? "INVESTIGATOR_AUTO_BYPASSED" : reportPath is null ? "INVESTIGATOR_UNAVAILABLE" : null;
        var payload = PromptBuilder.BuildContinue(nextRound, changeMetadata, reportPath, unavailable);
        var transcriptStore = new TranscriptStore(stateStore.GetRunDirectory(state.RunId));
        transcriptStore.SavePrompt(nextRound, payload);
        var provider = ProviderFactory.Create(state.Provider.Provider);
        var providerResult = await provider.ExecuteAsync(
            new(state.Provider, state.Repository, stateStore.GetRunDirectory(state.RunId), payload, state.SessionHandle, nextRound),
            processRunner,
            cancellationToken);
        transcriptStore.SaveResponse(nextRound, providerResult.ReviewText);
        if (providerResult.SessionHandle != state.SessionHandle)
        {
            throw new RunnerException("SESSION_MISMATCH", "Provider resumed a different session.", ExitCodes.ContractError);
        }
        var review = ReviewProtocol.Parse(providerResult.ReviewText);
        if (nextRound == Protocol.MaximumRounds && review.Status == ReviewStatuses.Findings)
        {
            review = review with
            {
                Status = ReviewStatuses.HumanDecisionRequired,
                // 比較限界や指摘の訂正理由を、round上限の通知で失わないようにする。
                Message = string.IsNullOrWhiteSpace(review.Message)
                    ? "Actionable findings remain after the fixed maximum of three review rounds."
                    : review.Message + "\nActionable findings remain after the fixed maximum of three review rounds."
            };
        }
        stateStore.Save(terminalState with
        {
            Status = review.Status,
            RepositorySnapshotPath = await SnapshotUnchangedAsync(state.Repository, stateStore.GetRunDirectory(state.RunId), nextRound, snapshotPath, cancellationToken) ? snapshotPath : null
        });
        PersistSuccess(job, RunnerOutput.FromReview(state.RunId, nextRound, review));
    }

    private ProviderSnapshot ResolveSnapshot(ProviderSnapshot snapshot) => snapshot with { Executable = executableResolver.Resolve(snapshot.Executable) };

    private async Task<bool> SnapshotUnchangedAsync(string repository, string runDirectory, int round, string? before, CancellationToken cancellationToken)
    {
        if (before is null) return false;
        var after = await investigatorBypass.CaptureAsync(repository, runDirectory, round + 10, cancellationToken);
        if (after is null) return false;
        return (await investigatorBypass.CompareAsync(before, after, repository, cancellationToken)) is { Files: 0 };
    }

    private string InvestigatorReportPath(string runId, int round) => Path.Combine(stateStore.GetRunDirectory(runId), $"investigator-report-{round}.json");

    private async Task<string?> RunInvestigatorAsync(JobState job, string repository, IReadOnlyList<(string Path, string Content)> contexts, string changeMetadata, CancellationToken cancellationToken)
    {
        if (job.Investigator is null) return null;
        try
        {
            var payload = PromptBuilder.BuildInvestigator(repository, contexts, job.Round, changeMetadata);
            var transcriptStore = new TranscriptStore(Path.Combine(stateStore.GetRunDirectory(job.RunId), "investigator"));
            transcriptStore.SavePrompt(job.Round, payload);
            var adapter = ProviderFactory.Create(job.Investigator.Provider);
            var result = await adapter.ExecuteAsync(new(job.Investigator, repository, stateStore.GetRunDirectory(job.RunId), payload, null, job.Round), processRunner, cancellationToken);
            transcriptStore.SaveResponse(job.Round, result.ReviewText);
            var validated = InvestigatorReportValidator.ParseAndValidate(result.ReviewText);
            var path = InvestigatorReportPath(job.RunId, job.Round);
            SharedStateFile.WriteAtomic(path, System.Text.Json.JsonSerializer.Serialize(validated, JsonDefaults.Options));
            return path;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
            return null;
        }
    }

    private void PersistSuccess(JobState job, RunnerOutput output)
    {
        jobStore.SaveResult(job.RunId, new(output, ExitCodes.Success));
        jobStore.Save(job with
        {
            JobStatus = JobStatuses.Succeeded,
            FinishedAtUtc = DateTimeOffset.UtcNow
        });
    }

    private void PersistFailure(JobState job, string code, string message, int exitCode)
    {
        var output = RunnerOutput.FromError(code, message, job.RunId, job.Round, JobStatuses.Failed);
        jobStore.SaveResult(job.RunId, new(output, exitCode));
        jobStore.Save(job with
        {
            JobStatus = JobStatuses.Failed,
            FinishedAtUtc = DateTimeOffset.UtcNow
        });
    }

    private void TryMarkStateError(string runId)
    {
        try
        {
            var state = stateStore.Load(runId);
            if (state.Status == ReviewStatuses.Findings)
            {
                stateStore.Save(state with { Status = ReviewStatuses.Error });
            }
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
        }
    }

    private ExecutionResult ReadSnapshot(string runId)
    {
        var job = jobStore.Load(runId);
        if (job.JobStatus == JobStatuses.Running)
        {
            return new(RunnerOutput.Running(runId, job.Round), ExitCodes.Success);
        }
        return ReadStoredResult(runId);
    }

    private ExecutionResult ReadStoredResult(string runId)
    {
        var stored = jobStore.LoadResult(runId);
        return new(stored.Output, stored.ExitCode);
    }

    private static IReadOnlyList<(string Path, string Content)> ResolveContexts(string repository, IReadOnlyList<string> contextPaths)
    {
        var contexts = new List<(string Path, string Content)>();
        var seen = new HashSet<string>(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
        foreach (var contextPath in contextPaths)
        {
            var combined = Path.IsPathRooted(contextPath) ? contextPath : Path.Combine(repository, contextPath);
            var resolved = NormalizePath(combined, "CONTEXT_PATH_INVALID", $"Context path was invalid: {contextPath}");
            if (!seen.Add(resolved))
            {
                throw new RunnerException("CONTEXT_DUPLICATE", $"Context path was specified more than once: {resolved}");
            }
            if (!File.Exists(resolved))
            {
                throw new RunnerException("CONTEXT_NOT_FOUND", $"Context file was not found: {resolved}");
            }
            string content;
            try
            {
                content = File.ReadAllText(resolved);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                throw new RunnerException("CONTEXT_UNREADABLE", $"Context file could not be read: {resolved}", ExitCodes.ContractError, exception);
            }
            if (string.IsNullOrWhiteSpace(content))
            {
                throw new RunnerException("CONTEXT_EMPTY", $"Context file was empty: {resolved}");
            }
            contexts.Add((resolved, content));
        }
        return contexts;
    }

    private static string NormalizePath(string path, string code, string message)
    {
        try
        {
            return Path.GetFullPath(path);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            throw new RunnerException(code, message, ExitCodes.ContractError, exception);
        }
    }
}
