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
    private readonly ReviewInputStore inputStore;
    private readonly TaskLineageStore lineageStore;

    public RunnerApplication(RunnerPaths paths, IExecutableResolver executableResolver, IProcessRunner processRunner, IWorkerLauncher workerLauncher)
    {
        this.paths = paths;
        this.executableResolver = executableResolver;
        this.processRunner = processRunner;
        this.workerLauncher = workerLauncher;
        stateStore = new(paths.StateRoot);
        jobStore = new(paths.StateRoot);
        inputStore = new(paths.StateRoot);
        lineageStore = new(paths.StateRoot);
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
        var input = inputStore.ReadAndValidate(command.InputPath);
        var config = ConfigLoader.Load(paths.ConfigPath);
        var snapshot = new ProviderSnapshot(
            config.Provider,
            executableResolver.Resolve(config.Executable),
            config.Model,
            config.ReasoningEffort,
            config.Profile);
        var runId = Guid.NewGuid().ToString("D");
        int submissions;
        using (lineageStore.Acquire(repository, input.Input.TaskKey))
        {
            var lineage = lineageStore.Load(repository, input.Input.TaskKey);
            submissions = ValidateNewSubmission(repository, input, lineage);
            var priorHistory = lineage is null ? [] : LoadReviewHistory(lineage);
            if (lineage is not null)
            {
                var previousJob = jobStore.Load(lineage.LatestRunId);
                var previousInput = inputStore.Load(lineage.LatestRunId, previousJob.Round);
                InputBinding? previousBinding = null;
                try
                {
                    previousBinding = stateStore.Load(lineage.LatestRunId).InputBinding;
                }
                catch (RunnerException exception) when (exception.Code == "STATE_NOT_FOUND")
                {
                    Trace.TraceError(exception.ToString());
                    previousBinding = previousInput.Binding;
                }
                if ((input.Binding.PurposeHash != previousBinding!.PurposeHash || input.Input.ApprovedDesign != previousInput.Input.ApprovedDesign) && input.Input.UserDecision is null)
                {
                    throw new RunnerException("USER_DECISION_REQUIRED", "Changing the purpose or approved-design baseline requires explicit userDecision evidence.");
                }
                if (input.Binding.ProposalHash != previousInput.Binding.ProposalHash && input.Input.Proposal.Version == previousInput.Input.Proposal.Version)
                {
                    throw new RunnerException("INPUT_VERSION_MISMATCH", "A changed proposal must use a new proposal version.");
                }
            }
            input = ReviewInputStore.Snapshot(input.Input with { PriorReviewHistory = priorHistory });
            inputStore.Save(runId, 1, input);
            var job = new JobState(
                Protocol.JobSchemaVersion,
                runId,
                1,
                JobOperations.Start,
                JobStatuses.Running,
                DateTimeOffset.UtcNow,
                Repository: repository,
                Provider: snapshot,
                InputHash: input.Hash,
                DurableSubmissions: submissions);
            lineageStore.Save(new(repository, input.Input.TaskKey, input.Input.ChangeId, runId, ReviewStatuses.Running, submissions, input.Hash));
            using (stateStore.AcquireLock(runId))
            {
                jobStore.Save(job);
            }
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
            var input = inputStore.ReadAndValidate(command.InputPath);
            if (input.Input.TaskKey != state.TaskKey || input.Input.ChangeId != state.ChangeId ||
                input.Input.PreviousRunId != state.PreviousRunId || input.Binding.PurposeHash != state.InputBinding!.PurposeHash ||
                input.Binding.ApprovedDesignHash != state.InputBinding.ApprovedDesignHash)
            {
                throw new RunnerException("INPUT_MISMATCH", "Continue input must preserve taskKey, changeId, and the purpose snapshot.");
            }
            input = ReviewInputStore.Snapshot(input.Input with { PriorReviewHistory = state.ReviewHistory });
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
            using (lineageStore.Acquire(state.Repository, state.TaskKey))
            {
                var lineage = lineageStore.Load(state.Repository, state.TaskKey)
                    ?? throw new RunnerException("STATE_INCOMPATIBLE", "Task lineage is missing for this run.");
                if (lineage.LatestRunId != command.RunId || lineage.ChangeId != state.ChangeId)
                {
                    throw new RunnerException("PREVIOUS_RUN_MISMATCH", "This run is no longer the latest run for its task.");
                }
                if (lineage.DurableSubmissions >= Protocol.MaximumRounds)
                {
                    throw new RunnerException("MAX_SUBMISSIONS_REACHED", "The change has reached the maximum of three durable submissions.");
                }
                var priorInput = inputStore.Load(command.RunId, state.Round);
                if (input.Binding.ProposalHash != priorInput.Binding.ProposalHash && input.Input.Proposal.Version == priorInput.Input.Proposal.Version)
                {
                    throw new RunnerException("INPUT_VERSION_MISMATCH", "A changed proposal must use a new proposal version.");
                }
                var durableSubmissions = lineage.DurableSubmissions + 1;
                lineageStore.Save(lineage with { DurableSubmissions = durableSubmissions, InputHash = input.Hash });
                state = state with { DurableSubmissions = durableSubmissions };
                stateStore.Save(state);
                inputStore.Save(command.RunId, nextRound, input);
                jobStore.Save(new JobState(
                    Protocol.JobSchemaVersion,
                    command.RunId,
                    nextRound,
                    JobOperations.Continue,
                    JobStatuses.Running,
                    DateTimeOffset.UtcNow,
                    Repository: state.Repository,
                    InputHash: input.Hash,
                    DurableSubmissions: durableSubmissions));
            }
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
        var snapshot = job.Provider ?? throw new RunnerException("JOB_INVALID", "Start job is missing a provider snapshot.");
        if (!Directory.Exists(repository))
        {
            throw new RunnerException("REPOSITORY_NOT_FOUND", $"Repository directory was not found: {repository}");
        }

        var storedInput = inputStore.Load(job.RunId, job.Round);
        if (storedInput.Hash != job.InputHash)
        {
            throw new RunnerException("STATE_INCOMPATIBLE", "Job input hash does not match its immutable snapshot.");
        }
        var payload = PromptBuilder.BuildStart(storedInput.Input);
        var transcriptStore = new TranscriptStore(stateStore.GetRunDirectory(job.RunId));
        transcriptStore.SavePrompt(1, payload);
        var provider = ProviderFactory.Create(snapshot.Provider);
        var providerResult = await provider.ExecuteAsync(
            new(snapshot, repository, stateStore.GetRunDirectory(job.RunId), payload, null, 1),
            processRunner,
            cancellationToken);
        transcriptStore.SaveResponse(1, providerResult.ReviewText);
        var review = EnforceSubmissionCap(ReviewProtocol.Parse(providerResult.ReviewText), job.DurableSubmissions);
        var state = new RunState(
            Protocol.Version,
            job.RunId,
            repository,
            snapshot,
            providerResult.SessionHandle,
            1,
            review.Status,
            storedInput.Input.TaskKey,
            storedInput.Input.ChangeId,
            Protocol.ReviewKind,
            storedInput.Binding,
            job.DurableSubmissions,
            storedInput.Input.PreviousRunId,
            (storedInput.Input.PriorReviewHistory ?? []).Append(CreateHistoryEntry(1, review)).ToArray());
        stateStore.Save(state);
        PersistSuccess(job, RunnerOutput.FromReview(job.RunId, 1, review, storedInput.Binding, storedInput.Hash));
    }

    private async Task ExecuteContinueRoundAsync(JobState job, CancellationToken cancellationToken)
    {
        var state = stateStore.Load(job.RunId);
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
        var storedInput = inputStore.Load(job.RunId, job.Round);
        if (storedInput.Hash != job.InputHash)
        {
            throw new RunnerException("STATE_INCOMPATIBLE", "Job input hash does not match its immutable snapshot.");
        }
        var payload = PromptBuilder.BuildContinue(storedInput.Input, nextRound);
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
        review = EnforceSubmissionCap(review, job.DurableSubmissions);
        stateStore.Save(terminalState with
        {
            Status = review.Status,
            InputBinding = storedInput.Binding,
            ReviewHistory = (storedInput.Input.PriorReviewHistory ?? []).Append(CreateHistoryEntry(nextRound, review)).ToArray()
        });
        PersistSuccess(job, RunnerOutput.FromReview(state.RunId, nextRound, review, storedInput.Binding, storedInput.Hash));
    }

    private void PersistSuccess(JobState job, RunnerOutput output)
    {
        jobStore.SaveResult(job.RunId, new(output, ExitCodes.Success));
        jobStore.Save(job with
        {
            JobStatus = JobStatuses.Succeeded,
            FinishedAtUtc = DateTimeOffset.UtcNow
        });
        if (job.Operation == JobOperations.Start)
        {
            var input = inputStore.Load(job.RunId, job.Round).Input;
            UpdateLineageStatus(job.Repository!, input.TaskKey, job.RunId, output.Status);
        }
        else
        {
            var state = stateStore.Load(job.RunId);
            UpdateLineageStatus(state.Repository, state.TaskKey, job.RunId, state.Status);
        }
    }

    private static ReviewerResponse EnforceSubmissionCap(ReviewerResponse review, int durableSubmissions)
    {
        if (durableSubmissions != Protocol.MaximumRounds || review.Status != ReviewStatuses.Findings)
        {
            return review;
        }
        var notice = "Actionable findings remain after the maximum of three durable submissions for this change.";
        return review with
        {
            Status = ReviewStatuses.HumanDecisionRequired,
            Message = string.IsNullOrWhiteSpace(review.Message) ? notice : review.Message + "\n" + notice
        };
    }

    private IReadOnlyList<ReviewHistoryEntry> LoadReviewHistory(TaskLineage lineage)
    {
        var job = jobStore.Load(lineage.LatestRunId);
        try
        {
            var state = stateStore.Load(lineage.LatestRunId);
            return state.ReviewHistory ?? [];
        }
        catch (RunnerException exception) when (exception.Code == "STATE_NOT_FOUND")
        {
            Trace.TraceError(exception.ToString());
            var result = jobStore.LoadResult(lineage.LatestRunId);
            if (result.Output.JobStatus == JobStatuses.Succeeded && result.Output.ReviewKind == Protocol.ReviewKind)
            {
                return [new ReviewHistoryEntry(
                    job.Round,
                    result.Output.Status,
                    result.Output.Findings,
                    result.Output.Message,
                    result.Output.InformationRequests ?? [])];
            }
            return [];
        }
    }

    private static ReviewHistoryEntry CreateHistoryEntry(int round, ReviewerResponse response) =>
        new(round, response.Status, response.Findings, response.Message, response.InformationRequests);

    private void PersistFailure(JobState job, string code, string message, int exitCode)
    {
        var output = RunnerOutput.FromError(code, message, job.RunId, job.Round, JobStatuses.Failed);
        jobStore.SaveResult(job.RunId, new(output, exitCode));
        jobStore.Save(job with
        {
            JobStatus = JobStatuses.Failed,
            FinishedAtUtc = DateTimeOffset.UtcNow
        });
        if (job.Operation == JobOperations.Start)
        {
            var input = inputStore.Load(job.RunId, job.Round).Input;
            UpdateLineageStatus(job.Repository!, input.TaskKey, job.RunId, ReviewStatuses.Error);
        }
        else
        {
            TryMarkStateError(job.RunId);
            var state = stateStore.Load(job.RunId);
            UpdateLineageStatus(state.Repository, state.TaskKey, job.RunId, ReviewStatuses.Error);
        }
    }

    private void UpdateLineageStatus(string repository, string taskKey, string runId, string status)
    {
        try
        {
            using var lineageLock = lineageStore.Acquire(repository, taskKey);
            var lineage = lineageStore.Load(repository, taskKey);
            if (lineage?.LatestRunId == runId)
            {
                lineageStore.Save(lineage with { LatestStatus = status });
            }
        }
        catch (Exception exception)
        {
            Trace.TraceError(exception.ToString());
        }
    }

    private int ValidateNewSubmission(string repository, StoredReviewInput stored, TaskLineage? lineage)
    {
        var input = stored.Input;
        if (lineage is null)
        {
            if (input.PreviousRunId is not null)
            {
                throw new RunnerException("PREVIOUS_RUN_MISMATCH", "The first submission for this task must not name a previous run.");
            }
            return 1;
        }
        if (!PathComparer.Equals(lineage.Repository, repository) || lineage.TaskKey != input.TaskKey || input.PreviousRunId != lineage.LatestRunId)
        {
            throw new RunnerException("PREVIOUS_RUN_MISMATCH", "previousRunId must identify the latest durable run for this repository and taskKey.");
        }
        var previousStatus = ResolveLatestStatus(lineage);
        if (previousStatus == ReviewStatuses.Findings)
        {
            throw new RunnerException("CONTINUE_REQUIRED", "A FINDINGS run must continue in the same session.");
        }
        if (previousStatus == ReviewStatuses.HumanDecisionRequired)
        {
            if (input.ChangeId == lineage.ChangeId || input.UserDecision is null)
            {
                throw new RunnerException("USER_DECISION_REQUIRED", "A HUMAN_DECISION_REQUIRED result requires a new changeId and explicit userDecision body and authority.");
            }
            return 1;
        }
        if (previousStatus == ReviewStatuses.Complete)
        {
            if (input.ChangeId == lineage.ChangeId)
            {
                throw new RunnerException("RUN_TERMINAL", "A COMPLETE change cannot be submitted again.");
            }
            return 1;
        }
        if (previousStatus is ReviewStatuses.Blocked or ReviewStatuses.Error)
        {
            if (input.ChangeId != lineage.ChangeId)
            {
                if (input.UserDecision is null)
                {
                    throw new RunnerException("USER_DECISION_REQUIRED", "A new change after BLOCKED or ERROR requires explicit userDecision body and authority.");
                }
                return 1;
            }
            if (lineage.DurableSubmissions >= Protocol.MaximumRounds)
            {
                throw new RunnerException("MAX_SUBMISSIONS_REACHED", "The change has reached the maximum of three durable submissions.");
            }
            return lineage.DurableSubmissions + 1;
        }
        throw new RunnerException("JOB_IN_PROGRESS", "The latest task submission is still running or has an unsupported status.");
    }

    private string ResolveLatestStatus(TaskLineage lineage)
    {
        JobState job;
        try
        {
            job = jobStore.Load(lineage.LatestRunId);
        }
        catch (RunnerException exception) when (exception.Code == "JOB_NOT_FOUND")
        {
            Trace.TraceError(exception.ToString());
            throw new RunnerException(
                "SUBMISSION_INCOMPLETE",
                $"Task {lineage.TaskKey} has a reserved submission without a durable job record. Its budget remains consumed; inspect lineage run {lineage.LatestRunId} before submitting again.",
                ExitCodes.ContractError,
                exception);
        }
        if (job.JobStatus == JobStatuses.Running)
        {
            throw new RunnerException("JOB_IN_PROGRESS", $"The latest task submission is still running; query status for run {lineage.LatestRunId} before submitting a new change.");
        }
        string status;
        try
        {
            status = stateStore.Load(lineage.LatestRunId).Status;
        }
        catch (RunnerException exception) when (exception.Code == "STATE_NOT_FOUND")
        {
            Trace.TraceError(exception.ToString());
            status = jobStore.LoadResult(lineage.LatestRunId).Output.Status;
        }
        if (status != lineage.LatestStatus || lineage.DurableSubmissions != job.DurableSubmissions || lineage.InputHash != job.InputHash)
        {
            lineageStore.Save(lineage with { LatestStatus = status, DurableSubmissions = job.DurableSubmissions, InputHash = job.InputHash ?? lineage.InputHash });
        }
        return status;
    }

    private static readonly StringComparer PathComparer = OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

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
