namespace ManualSmoke;

public sealed class RetryingClient(RetryPolicy retryPolicy)
{
    public async Task WaitBeforeRetryAsync(CancellationToken cancellationToken)
    {
        await Task.Delay(retryPolicy.GetDelay(), cancellationToken);
    }
}
