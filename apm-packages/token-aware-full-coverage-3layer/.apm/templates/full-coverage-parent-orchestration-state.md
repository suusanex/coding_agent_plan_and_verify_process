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

## Artifact index

| Kind | Path | Status | Notes |
| --- | --- | --- | --- |
| Parent Plan | | current / stale / missing | |
| Behavior Spec | | n/a / current / stale / missing | |
| Parent triage | | current / stale / missing | |
| Slice decomposition | | current / stale / missing | |
| Agent Usage Ledger | | current / stale / missing | |
| Slice execution table | | current / stale / missing | |
| Parent review gate | | n/a / current / stale / missing | |
| Cross-slice verification | | n/a / current / stale / missing | |
| Residual decision gate | | n/a / current / stale / missing | |

## Slice queue

| Slice ID | State | Evidence artifact | Next action |
| --- | --- | --- | --- |
| SL-xxx | pending-prep / prep-ready / blocked / ready-for-impl / impl-running / impl-done / verification-done / stale | | |

## Cross-slice blockers

| ID | Kind | Status | Next check |
| --- | --- | --- | --- |
| XC-xxx | contract / field-continuity / production-wiring / behavior-case | open / blocked / verified / stale | |

## Pending parent decisions

| Decision | Required evidence | Owner | Blocking? |
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
