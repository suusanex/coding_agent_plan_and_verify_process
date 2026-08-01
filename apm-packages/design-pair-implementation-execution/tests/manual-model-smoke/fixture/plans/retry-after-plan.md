# Retry-After support plan

## Goal

Use a valid server-provided Retry-After delay when retrying a throttled request while preserving the configured fallback delay for missing or invalid values.

## Scope

- `src/RetryPolicy.cs`
- `src/RetryingClient.cs`
- `tests/RetryPolicyTests.cs`

## Acceptance criteria

- A valid non-negative Retry-After delta is used for the next retry.
- Missing, invalid, or negative input uses the configured fallback delay.
- The caller remains cancellation-aware.
- Focused tests cover server delay and fallback behavior.

## Initial technical proposal

The initial proposal is to keep parsing inside `RetryPolicy`. This is upstream user input for discussion, not a confirmed Design Pair Locked Decision.
