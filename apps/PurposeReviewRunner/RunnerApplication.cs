namespace PurposeReviewRunner;

public sealed class RunnerApplication
{
    private readonly RunnerPaths paths;
    private readonly IExecutableResolver executableResolver;
    private readonly IProcessRunner processRunner;
    private readonly StateStore stateStore;

    public RunnerApplication(RunnerPaths paths, IExecutableResolver executableResolver, IProcessRunner processRunner)
    {
        this.paths = paths;
        this.executableResolver = executableResolver;
        this.processRunner = processRunner;
        stateStore = new(paths.StateRoot);
    }

    public Task<ExecutionResult> ExecuteAsync(RunnerCommand command, CancellationToken cancellationToken) => command switch
    {
        VersionCommand => Task.FromResult(new ExecutionResult(RunnerOutput.Version(), ExitCodes.Success)),
        StartCommand start => StartAsync(start, cancellationToken),
        ContinueCommand continuation => ContinueAsync(continuation, cancellationToken),
        _ => throw new RunnerException("INVALID_ARGUMENTS", "Unsupported command.")
    };

    private async Task<ExecutionResult> StartAsync(StartCommand command, CancellationToken cancellationToken)
    {
        var repository = NormalizePath(command.Repository, "REPOSITORY_PATH_INVALID", "Repository path was invalid.");
        if (!Directory.Exists(repository))
        {
            throw new RunnerException("REPOSITORY_NOT_FOUND", $"Repository directory was not found: {repository}");
        }
        var contexts = ResolveContexts(repository, command.ContextPaths);
        var config = ConfigLoader.Load(paths.ConfigPath);
        var snapshot = new ProviderSnapshot(
            config.Provider,
            executableResolver.Resolve(config.Executable),
            config.Model,
            config.ReasoningEffort,
            config.Profile);
        var runId = Guid.NewGuid().ToString("D");
        using var runLock = stateStore.AcquireLock(runId);
        var payload = PromptBuilder.BuildStart(repository, contexts);
        var provider = ProviderFactory.Create(snapshot.Provider);
        var providerResult = await provider.ExecuteAsync(
            new(snapshot, repository, stateStore.GetRunDirectory(runId), payload, null, 1),
            processRunner,
            cancellationToken);
        var review = ReviewProtocol.Parse(providerResult.ReviewText);
        var state = new RunState(
            Protocol.Version,
            runId,
            repository,
            contexts.Select(context => context.Path).ToArray(),
            snapshot,
            providerResult.SessionHandle,
            1,
            review.Status);
        stateStore.Save(state);
        return new(RunnerOutput.FromReview(runId, 1, review), ExitCodes.Success);
    }

    private async Task<ExecutionResult> ContinueAsync(ContinueCommand command, CancellationToken cancellationToken)
    {
        using var runLock = stateStore.AcquireLock(command.RunId);
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

        var nextRound = state.Round + 1;
        var payload = PromptBuilder.BuildContinue(nextRound);
        var provider = ProviderFactory.Create(state.Provider.Provider);
        var providerResult = await provider.ExecuteAsync(
            new(state.Provider, state.Repository, stateStore.GetRunDirectory(state.RunId), payload, state.SessionHandle, nextRound),
            processRunner,
            cancellationToken);
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
                Message = "Actionable findings remain after the fixed maximum of three review rounds."
            };
        }
        stateStore.Save(state with { Round = nextRound, Status = review.Status });
        return new(RunnerOutput.FromReview(state.RunId, nextRound, review), ExitCodes.Success);
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
