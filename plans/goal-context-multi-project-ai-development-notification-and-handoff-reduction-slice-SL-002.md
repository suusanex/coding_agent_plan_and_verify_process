# SL-002 Bounded Plan: Same-parent independent review and bounded remediation

## Goal

初回実装を行った同じ親threadで一度起動すると、current Ready PRとGoal Contextを自動解決し、round 1 full review、parent-owned remediation、round 2/3 purpose-only review、terminal decisionを手動messengerなしに完結する。

## Non-goals

- separate top-level Review / Implementation tasks、Adaptive executor、round 4自動継続。
- Goal Contextの利用者向け多段承認 / hash管理。
- notification runtimeのconsumer実装。

## Parent requirements covered

`FR-005`〜`FR-012`。

## Parent acceptance conditions covered

`AC-006`〜`AC-013`。

## Affected components / modules

- `apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/`
- collector、reviewer prompts / profiles、sync helper、APM manifest
- PRR validators / fixtures / manual-model smoke
- package and root README review sections

## Expected implementation scope

- same-parent one-operation intake and automatic repo / Ready PR / Goal Context resolution。
- auto run root / minimal summary / raw reviewer outputs。
- round 1 Copilot sources + independent local / purpose reviewers。
- parent-only fix / verify / PR head update。
- round 2/3 purpose-only review、active / resolved finding projection、terminal decisions。
- optional terminal notification enrichment。
- fixed two-task cycle manager / manual handoffをGoal Context normal-pathから除去し、live docs / validators / fixturesを整合させる。

## Cross-slice dependencies

- `XC-001`: terminal status / current PR URLを`SL-001`へ渡す。
- `XC-002`: subagent executionを`SL-001`real notification observationへ渡す。

## Related Cross-slice Contract IDs

`XC-001`, `XC-002`

## Architecture baseline

- Verdict: ReadyForSliceDecomposition
- Architecture: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-architecture.md`
- Identity: commit `774d6da78ed67be8478b4b5169121805daec79e6`、artifact revision `1`、hash `1e791e99a059428996355d38012ea155204b073c0e6a7a77c8ed25c7b02437de`。
- Source sections: review participants / state / decisions、`ARC-RC-005`〜`ARC-RC-009`, `ARCH-INV-006`〜`ARCH-INV-011`。
- Assigned residuals: `AR-003`, `AR-004`, review-related `AR-005`。

## Black-box behavior coverage

- Parent behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Expansion required: Yes
- Slice Plan readiness: ReadyForRiskTriage
- Assigned Behavior Case IDs: `REV-001`〜`REV-013`, `NTF-003`, `NTF-005`, `SCP-001`〜`SCP-003`

### Case-to-Slice mapping

| Case ID | Parent FR / AC | Slice FR / AC | Cross-slice Contract ID | Disposition | Notes |
| --- | --- | --- | --- | --- | --- |
| `REV-001`〜`REV-012` | `FR-005`〜`FR-011` / `AC-006`〜`AC-010`,`AC-012`,`AC-013` | `SL2-FR-001`〜`SL2-FR-006` / `SL2-AC-001`〜`SL2-AC-008` | N/A | InternalToSlice | same-parent review / remediation。 |
| `REV-013`, `NTF-003` | `FR-009` / `AC-011` | `SL2-FR-007` / `SL2-AC-009` | `XC-001` | CrossSliceVerification | terminal projection。 |
| `NTF-005` | `FR-004` / `AC-005` | `SL2-FR-003` / `SL2-AC-010` | `XC-002` | CrossSliceVerification | real subagent execution。 |
| `SCP-001` | Parent non-goals | Non-goal | N/A | OutOfScopeWithSource | complex multi-thread / long resume。 |
| `SCP-002` | Parent non-goals | Non-goal | N/A | DeferredWithSource | timeline / Adaptive executor。 |
| `SCP-003` | `FR-012` / `AC-012` | `SL2-FR-008` / `SL2-AC-011` | N/A | OutOfScopeWithSource | APM継続、Plugin移行なし。 |

## Slice functional requirements

- `SL2-FR-001`: one-operation same-parent intake auto-resolves current repository / Ready PR / Goal Context or stops with one concrete blocker。
- `SL2-FR-002`: round 1 collects current GitHub Copilot sources and independent local / purpose raw outputs。
- `SL2-FR-003`: reviewers run read-only; the original parent agent is the only production write owner。
- `SL2-FR-004`: parent applies authorized findings, verifies, updates current PR head, and passes current patch to a new purpose reviewer。
- `SL2-FR-005`: rounds 2/3 run purpose-only and track active / resolved IDs without repeating code review。
- `SL2-FR-006`: Complete / HumanDecisionRequired / Blocked are derived from mandatory source coverage, findings, and round count; round 4 is not automatic。
- `SL2-FR-007`: terminal result emits safe optional PR enrichment without carrying thread identity。
- `SL2-FR-008`: APM package / sync / docs expose the same-parent path and remove fixed two-task user contract from Goal Context normal usage。

## Slice acceptance conditions

- `SL2-AC-001`: canonical invocation contains no separate task creation or ID/path/hash/JSON copy。
- `SL2-AC-002`: round 1 fixture records GitHub, local, purpose sources bound to current head。
- `SL2-AC-003`: reviewer profiles and outputs prove read-only; only parent diff changes production files。
- `SL2-AC-004`: actionable round 1 leads to parent remediation and current remote head refresh。
- `SL2-AC-005`: round 2/3 source ledger contains purpose reviewer only and rejects repeated local / Copilot wait。
- `SL2-AC-006`: no findings closes; round 3 active finding / product decision / missing mandatory source stops explicitly。
- `SL2-AC-007`: Goal Context missing / ambiguous and stale / Draft PR fail closed without Issue substitution。
- `SL2-AC-008`: old fixed two-task cycle manager is absent from normal Skill / README / validator fixtures or explicitly historical only。
- `SL2-AC-009`: terminal envelope contains safe status / PR URI and no thread ID; `XC-001`integration passes。
- `SL2-AC-010`: real-model smoke records reviewer subagent roles for`XC-002`notification observation。
- `SL2-AC-011`: APM install / profile sync / package validator / File-based App publish / docs checks pass。

## Cross-slice contract excerpts

### XC-001

- This slice role: Producer
- Mechanism: optional terminal envelope
- Required fields / state / identifiers: schema version、terminal status、safe title、current PR URI。
- This slice owns: terminal verdict / result projection。
- This slice consumes: N/A。
- Unresolved: thread identityは生成しない。
- Authority: parent decomposition `Cross-slice contracts` / field continuity。

### XC-002

- This slice role: Producer
- Mechanism: real parent spawns read-only reviewer subagents
- Required fields / state / identifiers: reviewer roles / count、parent terminal。
- This slice owns: subagent orchestration evidence。
- This slice consumes: notification observation result only atcross-slice verification。
- Unresolved: callback hierarchyはmanual-only。
- Authority: parent decomposition `Cross-slice contracts` / field continuity。

## Implementation-realization risks

- current Skill / manager / plannerのfixed two-task authority。
- reviewer promptsのReview Thread / Adaptive result references。
- collectorのexplicit repo / PR-only intake。
- minimal run summary / finding continuityのproduction address。
- commit / push / current remote headとtool permission。

## Recommended route

- Recommended process profile: standard-slice
- Immediate next agent: `implementation-contract-kernel.agent.md`
- implementation_route: adaptive
- implementation_route_source: default
- design_pair_handoff: N/A

## Required inputs for next agent

parent / behavior / triage / readiness / architecture / decomposition、本slice、current Goal Context Skill、collector、manager surface、reviewer prompts / profiles、APM manifest / sync helper、validators / fixtures / docs。

## Stop condition

slice-local implementation / verificationを完了し、`XC-001`producer statusと`XC-002 ManualOnly`をparent orchestrationへ返す。cross-slice closeは行わない。
