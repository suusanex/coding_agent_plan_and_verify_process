# Change Risk Triage

## Plan readiness check

| Check | Result | Notes |
| --- | --- | --- |
| Expansion decision exists? | Yes | Parent Plan records `Expansion required: Yes`. |
| Behavior spec exists when required? | Yes | `plans/pcf-001-black-box-behavior-spec.md` exists. |
| Relevant source requirements have Case IDs? | Yes | `CASE-001` and `CASE-002` cover the parent requirements. |
| Relevant Case IDs are mapped to FR / AC or explicit disposition? | Yes | Parent Case-to-Plan mapping is complete. |
| Negative expectations are represented? | Yes | `CASE-002` and `AC-002` forbid stale, incomplete, and non-accepting states. |
| Blocking requirement ambiguity remains? | No | Identity, authority, publication, replay, and ordering are explicit. |
| Plan readiness status | ReadyForRiskTriage | No blocking behavior mapping remains. |
| Documentation level | standard | Full artifact chain is required by the E2E. |

## Bounded runtime sequence

| Sequence | Producer and hops | State owner / durable store | Later consumer | Bounded verification |
| --- | --- | --- | --- | --- |
| `SEQ-PUBLISH` | recovery entrypoint -> construct generation -> atomic temporary write -> publish | producer owns the durable snapshot file | startup reader in a later process lifecycle | producer verifier proves identity and completed atomic publication |
| `SEQ-REPLAY` | startup entrypoint -> observe durable file -> validate identity and publication -> replay -> admit/reject | producer remains authority; consumer is read-only | consumer work admission | consumer verifier proves idempotent replay and rejects stale/incomplete state |

## Execution-model boundary classification

| Execution model | Present / Absent | Evidence | Sequence |
| --- | --- | --- | --- |
| Same-process ABI / FFI boundary | Absent | no native ABI | N/A |
| Cross-process IPC | Absent | no live message channel | N/A |
| Cross-process durable-state observation | Present | consumer observes a file published by producer in a separate lifecycle | `SEQ-PUBLISH` -> `SEQ-REPLAY` |
| External or independently deployed service | Absent | no external service | N/A |
| Local asynchronous operation / UI-thread handoff | Absent | no UI handoff | N/A |
| Independent background worker | Present | producer recovery and consumer startup have independent entrypoints and failure recovery | both |
| Persistent queue / replayable job | Present | published generation is replayed idempotently during startup | `SEQ-REPLAY` |

## Risk semantic スキャン

| Risk semantic | Present / Absent / Unclear | Notes |
| --- | --- | --- |
| Authentication / authorization | Absent | not in scope |
| Durable state ownership | Present | producer is the sole writer; consumer is read-only |
| Retry / resume / replay / idempotency | Present | producer may replace a generation atomically; consumer replay is idempotent |
| Startup wiring / production entrypoint | Present | `src/StartupFlow.ps1` binds both sequences |
| Production / test implementation split | Absent | verifiers load production payload functions directly |
| Multiple runtime participants | Present | producer, durable store, and consumer |
| Observable behavior across components | Present | `AC-001`, `AC-002`, and `XC-001` span both slices |

## 推奨プロファイル

`full-coverage`

- Recommendation confidence: High
- Evidence that would lower the profile: one owner and one entrypoint could implement and verify publication and replay without a shared protocol or independent recovery.
- Evidence that would raise the profile: an external independently deployed consumer or additional competing state authority is introduced.

## 理由

The two bounded sequences have independent ownership, entrypoints, retry/replay behavior, and verification surfaces. They must nevertheless preserve one durable identity and publication protocol across runs.

## Why standard-slice is insufficient

- Candidate bounded sequence: combine producer recovery, atomic durable publication, consumer startup, and replay in one parent pass.
- Independent implementation slices required: `SL-001` producer recovery/publication and `SL-002` consumer startup/replay.
- Shared semantics that must remain fixed before decomposition: durable identity is `correlation_id` plus `generation`; producer is the only state authority; consumer is read-only; only a fully published matching generation can become `Accepting`.
- Why one bounded parent pass is insufficient: each sequence has an independent owner, entrypoint, failure recovery lifecycle, and verifier, while neither may redefine the shared protocol.
- Failure mode that decomposition prevents: consumer startup accepts a stale or partially published generation after producer recovery.
- Escalation gate result: Satisfied

## High-risk boundaries

| Boundary | Producer | Consumer | Mechanism | Risk type |
| --- | --- | --- | --- | --- |
| `BND-001` | atomic durable publisher | startup replay | `snapshot_state`, `correlation_id`, `generation`, `published` | state authority and cross-run identity |
| `BND-002` | both sequences | startup entrypoint | production function wiring | production binding |

## 対象とする runtime contracts

| Contract ID | Boundary | What is at risk | Why selected | Triage status | Next action |
| --- | --- | --- | --- | --- | --- |
| `RC-001` | `BND-001` | durable identity, authority, and atomic publication fields | consumer replay depends on exact semantics | Deferred | preserve through readiness and decomposition |
| `RC-002` | `BND-002` | accepting, stale, incomplete, and replay behavior | parent AC spans both sequences | Deferred | preserve through readiness and decomposition |

## 選択されなかった候補 runtime contracts

| Contract ID | Boundary | Why not selected | Candidate status | Suggested next action |
| --- | --- | --- | --- | --- |
| none | none | all candidates selected | Done | none |

## 実装実現性リスク

| Trigger | Status | Evidence | Required next step |
| --- | --- | --- | --- |
| Production addresses | Absent | fixture paths and entrypoints are explicit | none |

## Architecture-readiness triggers

| Trigger | Present / Absent / Unclear | Evidence | Readiness check |
| --- | --- | --- | --- |
| Shared state authority and identity | Present | `BND-001`, `RC-001` | fix writer/reader roles and identity fields |
| Retry/replay and forbidden state | Present | `CASE-001`, `CASE-002`, `RC-002` | fix idempotency and stale/incomplete rejection |
| Production entrypoint wiring | Present | `BND-002` | fix cross-slice verification postcondition |

## 推奨する次の agent

Run `architecture-slice-readiness.agent.md` with the parent Plan, behavior specification, and this triage artifact.

## full-coverage 時の分割方針

Preserve `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, and `XC-001`; implement producer publication before consumer replay and verify both the durable forbidden state and production entrypoint after both slice verdicts pass.

## 今回の triage の対象外

External services, model execution, and installer behavior.

## Handoff Packet

- Profile used: triage-only
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Recommended process profile: full-coverage
- Recommendation confidence: High
- Evidence that would lower the profile: one owner, one entrypoint, and no shared cross-run protocol
- Evidence that would raise the profile: external deployment or competing authority
- Source artifacts: parent Plan and behavior specification
- Selected contracts / IDs: `RC-001`, `RC-002`
- Files inspected: fixture planning artifacts
- Files intentionally not inspected: production payloads; triage is document-only
- Decisions made: the source-backed full-coverage escalation gate is satisfied
- Implementation realization risk summary: Absent; addresses are explicit
- Do not redo unless new evidence appears: bounded sequences, execution models, and selected boundaries
- Remaining work: architecture readiness, decomposition, implementation, verification
- Recommended next step: `architecture-slice-readiness.agent.md`
- Required downstream guardrails: preserve RC/XC mapping, durable identity, authority, forbidden state, production binding, wiring, and unresolved statuses
- Full-coverage escalation gate: Satisfied
- Full-coverage handling: `architecture-slice-readiness.agent.md`へ進める。readiness verdictなしでdecompositionへ進めない
