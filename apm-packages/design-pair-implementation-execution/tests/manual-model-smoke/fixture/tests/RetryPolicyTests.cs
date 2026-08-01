namespace ManualSmoke.Tests;

public sealed class RetryPolicyTests
{
    public void UsesConfiguredFallbackDelay()
    {
        var policy = new RetryPolicy(TimeSpan.FromSeconds(3));

        if (policy.GetDelay() != TimeSpan.FromSeconds(3))
        {
            throw new InvalidOperationException("Expected the configured fallback delay.");
        }
    }
}
