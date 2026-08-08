# Change Risk Triage

## Plan readiness check

| Check | Result | Notes |
| --- | --- | --- |
| Expansion decision exists? | Yes | Parent Plan records `Expansion required: Yes`. |
| Behavior spec exists when required? | Yes | `plans/pcf-001-black-box-behavior-spec.md` exists. |
| Relevant source requirements have Case IDs? | Yes | `CASE-001` and `CASE-002` cover the parent requirements. |
| Relevant Case IDs are mapped to FR / AC or explicit disposition? | Yes | Parent Case-to-Plan mapping is complete. |
| Negative expectations are represented? | Yes | `CASE-002` and `AC-002` require rejection in a non-accepting state. |
| Blocking requirement ambiguity remains? | No | All required behavior and ordering are explicit. |
| Plan readiness status | ReadyForRiskTriage | No blocking behavior mapping remains. |
| Documentation level | standard | Full artifact chain is required by the E2E. |

## 推奨プロファイル

`full-coverage`

## 理由

Producer state continuity and production startup wiring span two runtime participants and require local plus cross-slice verification.

## High-risk boundaries

| Boundary | Producer | Consumer | Mechanism | Risk type |
| --- | --- | --- | --- | --- |
| `BND-001` | Producer restore | Consumer gate | `snapshot_state`, `correlation_id` | shared runtime semantics |
| `BND-002` | Both slices | Startup entrypoint | function wiring | production binding |

## 対象とする runtime contracts

| Contract ID | Boundary | What is at risk | Why selected | Triage status | Next action |
| --- | --- | --- | --- | --- | --- |
| `RC-001` | `BND-001` | producer output fields | consumer depends on exact fields | Deferred | assign during decomposition |
| `RC-002` | `BND-002` | accepting and rejecting behavior | parent AC spans both slices | Deferred | assign during decomposition |

## 選択されなかった候補 runtime contracts

| Contract ID | Boundary | Why not selected | Candidate status | Suggested next action |
| --- | --- | --- | --- | --- |
| none | none | all candidates selected | Done | none |

## Risk trigger スキャン

| Risk trigger | Present / Absent / Unclear | Notes |
| --- | --- | --- |
| Cross-process or cross-service sequence | Absent | Single synthetic process. |
| Queue / event / webhook / background worker | Absent | Not in scope. |
| External API or SDK | Absent | Not in scope. |
| Authentication or authorization | Absent | Not in scope. |
| Durable state / retry / replay / idempotency | Absent | Not in scope. |
| Startup wiring / DI / configuration | Present | Production startup entrypoint binds both slices. |
| Production implementation split from test substitute | Absent | Verifiers load production payload functions directly. |
| Multiple runtime participants coordinating state | Present | Producer and consumer share fields. |
| Observable behavior spanning more than one component | Present | `AC-001` spans both slices. |

## 実装実現性リスク

| Trigger | Status | Evidence | Required next step |
| --- | --- | --- | --- |
| Production addresses | Absent | Fixture paths are explicit. | none |

## 推奨する次の agent

Run `architecture-slice-readiness.agent.md` with the parent Plan, behavior specification, and this triage artifact.

## Architecture-readiness triggers

| Trigger | Present / Absent / Unclear | Evidence | Readiness check |
| --- | --- | --- | --- |
| Shared state semantics | Present | `BND-001` | establish producer/consumer ownership |
| Production entrypoint wiring | Present | `BND-002` | establish cross-slice verification postcondition |

## full-coverage 時の分割方針

Preserve `AC-001`, `AC-002`, `CASE-001`, `CASE-002`, and `XC-001`; implement producer before consumer and verify the production entrypoint only after both slice verdicts pass.

## 今回の triage の対象外

External services, retries, persistence, and model execution.

## Handoff Packet

- Profile used: triage-only
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Behavior spec artifact: `plans/pcf-001-black-box-behavior-spec.md`
- Recommended process profile: full-coverage
- Source artifacts: parent Plan and behavior specification
- Selected contracts / IDs: `RC-001`, `RC-002`
- Files inspected: fixture planning artifacts
- Files intentionally not inspected: production payloads; triage is document-only
- Decisions made: full-coverage is the minimum sufficient route
- Implementation realization risk summary: Absent; addresses are explicit
- Do not redo unless new evidence appears: selected boundaries and contracts
- Remaining work: architecture readiness, decomposition, implementation, verification
- Recommended next step: `architecture-slice-readiness.agent.md`
- Required downstream guardrails: preserve RC/XC mapping, test points, production binding, wiring, and unresolved statuses
- Full-coverage handling: `architecture-slice-readiness.agent.md`へ進める。readiness verdictなしでdecompositionへ進めず、Full autonomous Plan-first flowへも接続しない
