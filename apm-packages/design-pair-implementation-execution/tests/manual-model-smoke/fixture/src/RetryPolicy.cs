namespace ManualSmoke;

public sealed class RetryPolicy
{
    private readonly TimeSpan fallbackDelay;

    public RetryPolicy(TimeSpan fallbackDelay)
    {
        this.fallbackDelay = fallbackDelay;
    }

    public TimeSpan GetDelay() => fallbackDelay;
}
