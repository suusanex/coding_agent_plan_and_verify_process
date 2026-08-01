# Change Risk Triage: SL-002

## Scope

SL-002 covers same-parent independent review, bounded parent-owned remediation, purpose-only reruns, and terminal-result projection. `XC-001` and `XC-002` remain cross-slice items and are not completed here.

## Selected risk boundaries

| Boundary | Producer | Consumer | Risk | Status | Required downstream artifact |
| --- | --- | --- | --- | --- | --- |
| `SL2-RC-001` | `$goal-context-pr-review` parent | collector, Goal Context selector, local/purpose reviewer profiles | Ready PR / Goal Context identity, round-1 mandatory source coverage, read-only isolation | Present | implementation and runtime contracts |
| `SL2-RC-002` | parent orchestrator | remediation worktree, collector, subsequent purpose reviewer | single writer, current-head gate, finding continuity, purpose-only rounds 2/3, terminal decision | Present | implementation and runtime contracts |
| `SL2-RC-003` | parent terminal projection | `XC-001` notification consumer | safe terminal status/title/current PR URI without callback identity | Present | runtime contract; consumer verification is cross-slice |

## Implementation-realization risks

| Risk | Evidence | Status | Required decision / check |
| --- | --- | --- | --- |
| Existing Goal Context Skill requires a distinct Review Thread and Implementation Thread and stops before Adaptive. | `goal-context-pr-review/SKILL.md`, `manage-review-cycle.cs` require both thread IDs. | Confirmed mismatch | Replace only the normal-path authority with same-parent orchestration; retain historical/multi-thread evidence only when explicitly legacy. |
| Collector currently accepts explicit `--repo` / `--pr`. | `collect-pr-review-context.cs` validates Ready PR and base/head identity. | AllowedReuse | Add auto-resolution at the Skill/orchestrator boundary; retain collector as the remote identity and patch authority. |
| Existing manager has durable round/identity validation but encodes two fixed role tasks. | `manage-review-cycle.cs` validates role IDs, new head OIDs, full/purpose-only modes, and artifact roles. | RejectedSubstitute | Do not reuse its fixed-thread contract as the new normal path; selectively reuse validated round/source/finding semantics only after an explicit same-parent address is implemented. |
| Reviewer prompts/profiles are already read-only. | Canonical agent contracts and package TOMLs set `sandbox_mode = read-only`. | AllowedReuse | Preserve profile validation and raw-output retention; parent remains sole production write owner. |
| Terminal PR enrichment reaches notification runtime only through `XC-001`. | Slice architecture and decomposition define optional envelope and callback-owned thread identity. | Deferred | Produce only safe projection fields; do not generate or carry `thread-id` / `turn-id`. |
| Real reviewer/subagent notification count cannot be proven with fixtures. | `NTF-005`, `XC-002`, architecture residual `AR-002`. | ManualOnly | Record roles/count from a real same-parent smoke; notification observation is cross-slice. |

## Recommended handling

- Recommended process profile: standard-slice
- implementation_route: adaptive
- implementation_route_source: default
- design_pair_handoff: N/A
- Required next artifacts: implementation contract, runtime contract, and test design for `SL2-RC-001` through `SL2-RC-003`.
- Prohibited scope expansion: notification runtime consumer work, Plugin migration, Adaptive executor replacement, generic multi-thread recovery, and automatic round 4.

## Handoff Packet

- Profile used: triage-only
- Source artifacts: parent Plan, behavior spec, parent triage, Architecture Slice Readiness R2, Slice Architecture, slice decomposition, SL-002 bounded Plan.
- Selected contracts / IDs: `SL2-RC-001`, `SL2-RC-002`, `SL2-RC-003`; cross-slice `XC-001`, `XC-002` deferred.
- Files inspected: Goal Context PR review Skill, baseline review Skill, collector, cycle manager, reviewer agents/profiles, manifest, sync helper, validators, package/root README references.
- Files intentionally not inspected: unrelated packages, full fixture bodies, live GitHub/Codex/Windows state.
- Decisions made: existing collector and read-only profiles are reusable; fixed two-task cycle authority is not a valid normal-path substitute.
- Remaining work: concrete same-parent orchestrator address, run-summary schema, remediation commit/push command, and production binding verification.
- Recommended next step: `implementation-contract-kernel.agent.md` for this bounded slice.
