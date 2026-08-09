# Architecture Slice Readiness

## Inputs and requirement baseline

```yaml
baseline:
  repository_ref: PCF-001-seed
  source_repository_commit: deterministic-fixture-v1
  tracked_sources:
    - { role: parent_plan, path: "plans/pcf-001.md", revision_type: content_sha256, revision: "bcc766f949dd5d81e687b568266c20a16d5bb1fab7c285d4daa2565fcd16e1e7" }
    - { role: behavior_spec, path: "plans/pcf-001-black-box-behavior-spec.md", revision_type: content_sha256, revision: "0402070d0115688cb9976e4515e3ba68af354939b04f09e20817070d84eda24e" }
    - { role: change_risk_triage, path: "plans/pcf-001-change-risk-triage.md", revision_type: content_sha256, revision: "1fc71327f478ad3f20984cb73026ce4fdaae1ea1f0ec5635203e5002ca5e748f" }
    - { role: slice_architecture, path: "plans/pcf-001-slice-architecture.md", revision_type: external_content_sha256, revision: "579a1d16057f4b1223f989b7913ba92855a3693d6e46a732d300cdc013fa84dd" }
  watch_paths:
    - src/ProducerState.ps1
    - src/ConsumerGate.ps1
    - src/StartupFlow.ps1
  artifact_revision: pcf-001-readiness-v1
  evaluated_at: deterministic-fixture
```

## Architecture readiness verdict

- Verdict: ReadyForSliceDecomposition
- Selected process after readiness: `full-coverage`
- Architecture artifact: `plans/pcf-001-slice-architecture.md`
- Architecture baseline authority: Slice Architecture artifact
- Immediate next agent: `plan-slice-decomposition.agent.md`
- Decomposition allowed now: Yes

## Full-coverage escalation reassessment

- Candidate bounded sequence: one pass combining producer recovery/publication and consumer startup/replay.
- Independent implementation slices required: producer recovery/atomic publication and consumer startup/idempotent replay.
- Shared semantics that must remain fixed before decomposition: `correlation_id` plus `generation`, producer-only authority, completed publication, and stale/incomplete rejection.
- Why one bounded parent pass is insufficient: the sequences have independent entrypoints, owners, recovery lifecycles, and verifiers.
- Failure mode that decomposition prevents: consumer acceptance of a stale or partially published generation.
- Escalation gate result: `Satisfied`
- Reassessment result: KeepFullCoverage

## Lightweight architecture baseline

N/A - current Slice Architecture is the baseline authority.

## Architecture-readiness triggers

| Trigger | Present / Absent / Unclear | Evidence | Required action |
| --- | --- | --- | --- |
| Shared producer/consumer identity and authority | Present | `XC-001` | preserve identity, producer-only authority, and atomic publication |
| Retry/replay forbidden state | Present | `CASE-001`, `CASE-002` | preserve idempotent replay and stale/incomplete rejection |
| Production startup wiring | Present | `AC-001` | verify through production entrypoint |

## Readiness checklist

| Check | PASS / FAIL / N/A | Evidence mode | Source artifact | Production evidence address | Notes |
| --- | --- | --- | --- | --- | --- |
| Slice ownership explicit | PASS | document | slice architecture | `src/ProducerState.ps1`, `src/ConsumerGate.ps1` | owners are separate |
| Cross-slice semantics explicit | PASS | document | slice architecture | `src/StartupFlow.ps1` | `XC-001` is explicit |
| Human decision required | N/A | document | parent Plan | N/A | none |

## Architecture residual ledger

| ID | Classification | Topic | Source / evidence | Owner | Blocking? | Next action |
| --- | --- | --- | --- | --- | --- | --- |
| none | none | none | all checks pass | Plan Coverage parent | No | decomposition |

## Cross-slice verification postconditions

- `Active -> atomically published -> replayed -> Accepting -> Accepted` through `src/StartupFlow.ps1`.
- non-accepting, incomplete, and stale-generation state rejects without admitting work.
- `snapshot_state`, `correlation_id`, and `generation` remain continuous; replay is idempotent.

## Files inspected

Parent Plan, behavior specification, triage artifact, and Slice Architecture.

## Files intentionally not inspected

Production payloads; readiness is based on approved architecture artifacts.

## Handoff Packet

- Readiness verdict: ReadyForSliceDecomposition
- Baseline authority: Slice Architecture artifact
- Baseline identity: `plans/pcf-001-slice-architecture.md` at `pcf-001-readiness-v1`
- Architecture Elaboration: N/A for this happy path
- Blocking residuals: none
- Recommended next step: `plan-slice-decomposition.agent.md`
