# FULL-001 request

Use `plan-coverage-residual-flow` for this task.

## Source requirement

Implement durable producer publication and consumer startup/replay for this repository.

### Shared durable identity

- Durable identity is the pair `(correlation_id, generation)`.
- Producer is the sole state authority for the durable snapshot file.
- Consumer must reject stale or partially published generations.
- Consumer must replay idempotently from a complete Active snapshot.

### Runtime sequences

1. **Producer sequence**
   - Recover or build snapshot for a correlation_id + generation
   - Atomically publish to the durable store path
   - SnapshotState becomes `Active` only after atomic publish completes

2. **Consumer sequence**
   - Startup reads the durable snapshot
   - Accept only matching correlation_id + generation with SnapshotState `Active` and Published true
   - Enter ConsumerState `Accepting`
   - Reject push while not accepting
   - Reject stale generation

### Production entrypoints

- `src/ProducerState.ps1` — producer recovery + atomic publish
- `src/ConsumerGate.ps1` — consumer accept/reject helpers
- `src/StartupFlow.ps1` — production composition entrypoint used by cross-slice verification

### Constraints

- This requires full-coverage: two independently owned runtime sequences plus a cross-slice invariant.
- Do not select Design Pair.
- You MUST invoke repository custom agents (`.github/agents/*.agent.md`) via the task/agent tool when available, including at least:
  `plan-kernel`, `change-risk-triage` (full-coverage escalation), `architecture-slice-readiness`,
  `plan-slice-decomposition`, per-slice Adaptive `high-implementation-starter` then
  `standard-implementation-completer` after valid handoff, `verification-kernel`,
  `cross-slice-verification-kernel`, and `residual-decision-gate`.
- Use canonical Slice Living Records (`plans/*-slice-SL-*.md`) for implementation-ready slices (at least two).
- Connect each implementation-ready slice to Adaptive Implementation under the Adaptive package contract. Start from HIGH; hand off to STANDARD only after `READY_FOR_STANDARD_COMPLETION`. `COMPLETED_BY_HIGH_MODEL` is a valid Adaptive terminal when no STANDARD remainder remains.
- Do not weaken or rewrite `tests/verify-full-001.ps1` or the per-slice verifiers. They are external oracles.
- No human product decision is required; stop only on true blocking residual.
- Do not ask clarifying questions; execute until verifiers pass and residual close is possible.

### Done when

- `tests/verify-sl-001.ps1`, `tests/verify-sl-002.ps1`, and `tests/verify-full-001.ps1` exit 0
- Plan Coverage residual decision can close without blocking residual
- No Design Pair artifacts were created
