# Full-Coverage Parent Orchestration State

implementation_route: adaptive / design-pair
implementation_route_source: default / explicit-user-selection
design_pair_handoff: N/A / plans/<ticket-or-slug>-design-pair-implementation-handoff.md / per-slice paths
design_pair_interaction_stage: N/A / not-started / target-selection / disposition-confirmation / upstream-decision / complete / artifact-repair
design_pair_user_evidence: N/A / Pending / <Target Map presentation and post-map user response references>

Design Pair は explicit-user-selection の場合だけ使用する。difficulty、risk、size、architecture から自動選択、推奨、提案しない。
Design Pair が `target-selection` または `disposition-confirmation` で待機中の slice は、Adaptive、slice verification、cross-slice verificationへ進めない。resumeでinteraction stateまたはuser evidenceが欠ける場合は補完せずartifact repairで停止する。

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
- Source repository commit:
- Tracked source revisions verified at:
- Watch path diff verified through commit:
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

`stale` means a tracked source revision/content hash changed, a diff after Source repository commit touched a declared watch path / inspected production evidence address, a human decision source changed, or an explicit architecture artifact revision changed. HEAD changes containing only generated readiness/architecture artifacts do not self-invalidate the baseline. HEAD equality and path equality are not freshness tests. If tracked source or watch path comparison cannot be completed, use `stale` and rerun Architecture Slice Readiness.

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
