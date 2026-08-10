# STD-001 request

Use `plan-coverage-residual-flow` for this task.

## Source requirement

Implement a single-process configuration loader for this repository.

### Behavior

1. Load `config/appsettings.json` through the production entrypoint `src/Load-AppConfig.ps1`.
2. Required keys: `AppName` (non-empty string), `Port` (integer 1..65535), `EnableFeatureX` (boolean).
3. Missing file, invalid JSON, missing key, empty `AppName`, or out-of-range `Port` must throw a clear error and must not return a partial config object.
4. Valid config returns a PowerShell object with exactly those three properties and the parsed values.
5. Do not invent extra product settings. Do not ask the human for decisions.

### Constraints

- Keep the change bounded to one standard-slice sequence.
- Do not select Design Pair.
- You MUST drive the route by invoking repository custom agents (`.github/agents/*.agent.md`) via the task/agent tool when available, in this observable order:
  1. `plan-kernel` (or equivalent lite Plan Coverage artifact creation owned by plan-kernel semantics)
  2. `change-risk-triage` (must select standard-slice)
  3. `high-implementation-starter` first for non-local decisions / initial implementation ownership
  4. after a valid `READY_FOR_STANDARD_COMPLETION` handoff, `standard-implementation-completer`
  5. `verification-kernel`
  6. `residual-decision-gate`
- Do not skip Adaptive HIGH -> STANDARD handoff. Record handoff evidence under `plans/`.
- Leave Plan Coverage artifacts under `plans/` according to the canonical Plan Coverage contract.
- Do not weaken or rewrite `tests/verify-std-001.ps1`. That verifier is the external oracle.
- Do not ask clarifying questions; execute to close.

### Done when

- `tests/verify-std-001.ps1` exits 0
- Plan Coverage residual decision can close without blocking residual
- No Design Pair artifacts were created
