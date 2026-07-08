# Plan Coverage Lite

この template は、小さく bounded な変更で `documentation_level: lite` を選べる場合に使う compact Plan Coverage artifact です。

Lite は guardrail を削るものではありません。Plan source of truth、FR / AC coverage、implementation authorization、verification summary、residual / close decision を 1 つの artifact にまとめるための形式です。

`documentation_level` の値は `lite` または `standard` のみです。`strict` を値として作ってはいけません。`full-coverage` は `documentation_level` ではなく、`Plan readiness: ReadyForRiskTriage` 後に選ばれる route / process profile です。

## Source of Truth

- Source request / issue:
- Related existing artifacts:
- Repository / branch:
- Artifact owner:

## Plan Summary

- Goal:
- Non-goals:
- Scope:
- Affected components / files:

## Documentation Level

- documentation_level: lite
- Selection reason:
- Why separate standard artifacts are not required:

## Plan Readiness

- Expansion required: Yes / No / Unclear
- Inline behavior sketch sufficient: Yes / No / N/A
- Behavior spec artifact required: Yes / No / N/A
- Behavior spec artifact: <path / N/A>
- Plan readiness: ReadyForRiskTriage / NeedsPlanBehaviorExpansion / NeedsHumanDecision
- Case-to-Plan mapping status: Complete / Incomplete / N/A
- Blocking items:

## Functional Requirements

| FR | Requirement | Source |
| --- | --- | --- |

## Acceptance Conditions

| AC | Observable condition | Related FR | Verification method |
| --- | --- | --- | --- |

## Inline Behavior Sketch

Use this section only when a separate Black-box Behavior Spec is not required. If a separate spec is required, set Plan readiness to `NeedsPlanBehaviorExpansion` until the artifact exists and Case-to-Plan mapping is complete.

| Scenario / case | Input or state | Expected behavior | Negative expectation | Related FR / AC |
| --- | --- | --- | --- | --- |

Escalate to a separate `plans/<slug>-black-box-behavior-spec.md` instead of using only this inline sketch when any of these are true:

- more than a few behavior cases are needed to preserve source requirement coverage
- expected behavior changes across recovery, rollback, retry, replay, cleanup, durable state, or idempotency paths
- negative expectations are numerous or safety-critical
- Case-to-Plan mapping is incomplete, ambiguous, or requires human decision
- standard or full-coverage routing is needed to keep behavior coverage traceable

## Risk Checklist

| Risk item | Status | Evidence / notes |
| --- | --- | --- |
| External API / SDK / service? | Yes / No / N/A | |
| Auth / permission / secret? | Yes / No / N/A | |
| DB / durable state / migration? | Yes / No / N/A | |
| Public API / serialized payload / config surface? | Yes / No / N/A | |
| Async / queue / event / background worker? | Yes / No / N/A | |
| Production wiring / entrypoint affected? | Yes / No / N/A | |
| Manual verification required? | Yes / No / N/A | |
| Human decision required? | Yes / No / N/A | |

## Inline Ready Gate

Implementation is allowed only when every required row is `PASS` or `N/A` with evidence.

This section may replace a separate `plans/<slug>-implementation-handoff-review.md` only when `Inline Ready Gate equivalent to implementation-handoff-review` is `PASS`, every required row has source-backed evidence, and no blocking item remains. This equivalence is limited to authorization for the bounded implementation pass. It is not parent Plan close readiness.

| Check | Status | Evidence |
| --- | --- | --- |
| Source of truth is identified | PASS / FAIL / N/A | |
| FR / AC coverage is complete for this bounded pass | PASS / FAIL / N/A | |
| Behavior expansion is not required, or inline behavior sketch sufficient / required behavior artifact exists | PASS / FAIL / N/A | |
| Case-to-Plan mapping is complete, or N/A with reason | PASS / FAIL / N/A | |
| Risk checklist has no unresolved blocking item | PASS / FAIL / N/A | |
| Implementation scope and non-goals are clear | PASS / FAIL / N/A | |
| Human decisions are resolved or explicitly blocking | PASS / FAIL / N/A | |
| Behavior coverage is complete when `Behavior spec artifact required: Yes` or inline sketch has Case IDs | PASS / FAIL / N/A | |
| Inline Ready Gate equivalent to implementation-handoff-review | PASS / FAIL / N/A | |
| Implementation is allowed for the bounded pass | PASS / FAIL / N/A | |

## Implementation Self-Map

| Change ID | Planned or actual change | File / symbol | Reason | Related FR / AC | Assumption made | Review hint |
| --- | --- | --- | --- | --- | --- | --- |

## Verification Summary

| Check | Status | Evidence |
| --- | --- | --- |
| Required checks identified | Yes / No / N/A | |
| Automated checks run | Yes / No / N/A | |
| Manual checks needed | Yes / No / N/A | |
| Stub / fake / mock / in-memory only? | Yes / No / N/A | |
| Production implementation checked? | Yes / No / N/A | |
| Production wiring / entrypoint checked? | Yes / No / N/A | |
| FR / AC evidence mapped | Yes / No / N/A | |

No fake-only completion rule: do not claim implementation or close readiness using only stub, fake, mock, in-memory, or test-helper evidence. If production implementation or production wiring / entrypoint is not checked, record the missing evidence as residual work or a blocking item.

## Residual / Close Decision

| Item | Classification | Owner | Blocking? | Required evidence / next step |
| --- | --- | --- | --- | --- |

- Close readiness: ReadyToClose / ReadyToCloseWithAcceptedResiduals / NotReady
- Decision reason:

## Handoff Packet

- Profile used: plan-coverage-lite
- Plan artifact:
- documentation_level: lite
- Plan readiness:
- Inline behavior sketch sufficient:
- Behavior spec artifact required:
- Source artifacts:
- Files inspected:
- Files intentionally not inspected:
- Decisions made:
- Assumptions made:
- Tests / checks run:
- Tests / checks not run:
- Remaining work:
- Recommended next step:
