# Full-Coverage Parent Orchestration State

This artifact is the single resume entrypoint for full-coverage parent orchestration.
Keep it compact. Do not paste full source artifacts, full subagent outputs, or long reasoning traces.
Prefer path + status + next action.
Do not paste source excerpts except for a short pointer when needed.
If this file grows too large, compact old completed slice rows into a short summary and keep details in the original slice artifacts.

## Resume header

- Process: token-aware-full-coverage-3layer
- ExecutionMode: PREP_ONLY / DELEGATED_IMPLEMENTATION / PARENT_DIRECT_IMPLEMENTATION
- Last updated:
- Parent tool: Codex / GitHub Copilot / other
- Repo / branch:
- Work item / ticket:
- Current phase:
- Last completed checkpoint:
- Next required action:
- Stop reason: none / token-limit / tool-failure / manual-stop / model-switch / planned-handoff / unknown
- Resume safety: Safe / NeedsReview / NeedsHumanDecision / Blocked
- Repository ref:
- Repository commit:
- Architecture readiness evaluated at:

## Artifact index

| Kind | Path | Status | Notes |
| --- | --- | --- | --- |
| Parent Plan | | current / stale / missing / contradicted | |
| Behavior Spec | | n/a / current / stale / missing / contradicted | |
| Parent triage | | current / stale / missing / contradicted | |
| Architecture readiness | | current / stale / missing / contradicted | |
| Slice architecture | | n/a / current / stale / missing / contradicted | |
| Slice decomposition | | current / stale / missing / contradicted | |
| Agent Usage Ledger | | current / stale / missing / contradicted | |
| Slice execution table | | current / stale / missing / contradicted | |
| Parent review gate | | n/a / current / stale / missing / contradicted | |
| Cross-slice verification | | n/a / current / stale / missing / contradicted | |
| Residual decision gate | | n/a / current / stale / missing / contradicted | |

`contradicted` means this artifact conflicts with the current branch, work item, slice queue, or newer listed artifact and must be reviewed before continuing.

`stale` means an upstream baseline revision/hash, repository commit affecting inspected production evidence, human decision source, or architecture artifact revision changed after readiness evaluation. Path equality alone does not make an artifact `current`. If baseline identity is missing or cannot be compared, use `stale` and rerun Architecture Slice Readiness.

## Slice queue

| Slice ID | State | Evidence artifact | Next action |
| --- | --- | --- | --- |
| SL-xxx | pending-prep / prep-ready / blocked / ready-for-impl / impl-running / impl-done / verification-done / stale | | |

## Cross-slice blockers

| ID | Kind | Status | Next check |
| --- | --- | --- | --- |
| XC-xxx | contract / field-continuity / production-wiring / behavior-case | open / blocked / verified / stale | |

Architecture drift is also a cross-slice blocker. If slice-prep or slice-impl changes shared state ownership, precedence, identity, sequence, retry / release, capacity, schema, invariant, or production wiring, record it here and return to Architecture Slice Readiness before implementation continues.

## Pending parent decisions

| Decision | Required evidence | Owner | Blocking? |
| --- | --- | --- | --- |

## Parent decisions made

| Decision | Applies to | Evidence artifact | Status |
| --- | --- | --- | --- |

## Recent checkpoint delta

- Last state change:
- Files/artifacts updated:
- Delegation started/completed:
- Important caution for next agent:

## Emergency checkpoint

Use this section only when interruption is likely before a full state update.

- Minimal next action:
- Avoid repeating:
- Must read before continuing:
- Known blocker:
