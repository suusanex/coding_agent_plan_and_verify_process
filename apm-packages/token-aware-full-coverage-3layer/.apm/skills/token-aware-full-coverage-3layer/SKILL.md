---
name: token-aware-full-coverage-3layer
description: Advanced full-coverage orchestration after Architecture Slice Readiness and decomposition. Fresh executions use compact Slice Records, parent authorization, Adaptive Implementation, independent verification, and a Final Record.
---

<!--
Copyright (c) 2026 suusanex (GitHub UserName)
SPDX-License-Identifier: CC-BY-4.0
License: https://creativecommons.org/licenses/by/4.0/
Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
-->

# Full-coverage compact slice execution

This skill is an advanced route after a parent Plan has passed behavior expansion when required, Parent Change Risk Triage, Architecture Slice Readiness (and any required elaboration rerun), and Plan Slice Decomposition. Those pre-decomposition gates retain their authority and are not repeated per slice.

## Three layers

1. Parent orchestration and authorization.
2. Slice preparation delta.
3. Adaptive implementation and independent slice verification.

`full-coverage` is not a documentation level and does not make this a default or beginner route. It does not weaken Plan authority, no-fake-only completion, explicit residual decisions, independent verification, Design Pair rules, or HIGH → STANDARD → HIGH adaptive implementation.

## Applicability and parent ownership

Use this only after `full-coverage` triage and the approved Architecture Slice Readiness/decomposition chain; it does not replace explicit Plan Coverage route selection or invoke itself recursively. In `PREP_ONLY`, the parent may create or update only orchestration/record artifacts and must not edit production code or tests. In `DELEGATED_IMPLEMENTATION`, the parent authorizes slices but does not edit production code or tests; the serial Adaptive write owner does. Parent State is the mandatory resume entrypoint and must record freshness from source revisions/watch paths before reuse. Few valid slices and coalescing remain valid; never split solely to increase delegation count.

## Layout selection

Fresh runs record the following in Parent State and every executable Slice Record:

```yaml
full_coverage_artifact_layout: compact-slice-record-v2
full_coverage_artifact_layout_source: default-new-flow
```

The standard durable set is:

```text
plans/<slug>-coverage-ledger.md
plans/<slug>-parent-orchestration-state.md
plans/<slug>-slice-SL-001.md
plans/<slug>-slice-SL-002.md
plans/<slug>-full-coverage-final.md
```

For an existing split run, preserve `legacy-split-v1` with source `legacy-resume`. Do not migrate, delete, normalize, or infer between layouts. Missing, partial, contradictory, or mixed layout metadata is `BlockedByArtifactLayoutMismatch`; stop before authorization or implementation. Explicit compatibility is the only new use of the legacy route.

ResumeではParent Orchestration Stateが必須である。`implementation_route`と`implementation_route_source`をdurable stateから読み、欠落または矛盾はAdaptiveへ補完せずartifact mismatchとして停止する。fresh intakeだけ`implementation_route: adaptive` / `implementation_route_source: default`を初期化する。Design Pairはexplicit selectionだけで開始し、最初のturnはTarget Map全体を提示して`AWAITING_USER_INPUT / target-selection`で停止し、post-map user responseとTarget disposition確認後も`AWAITING_USER_INPUT / disposition-confirmation`で再停止する。`design_pair_user_evidence`をSlice RecordとParent Stateへ伝播する。

## Canonical ownership

| Fact | Owner |
| --- | --- |
| Parent Goal, FR, AC, Non-goals | Parent Plan |
| Behavior Case definition | Behavior Spec or parent inline sketch |
| Parent risk / shared architecture | Parent triage / architecture baseline |
| Slice assignment and XC role | immutable Slice Record baseline |
| Slice-local prep, implementation, verification, fix evidence | corresponding Slice Record sections |
| orchestration, authorization, delegation audit | Parent Orchestration State |
| complete coverage table | canonical Coverage Ledger |
| final XC verification, residual, close decision | Full-Coverage Final Record |
| Design Pair human interaction | tracked Design Pair handoff |

One fact has one canonical owner. Records emit ledger deltas only. The parent does not copy detailed implementation or verification evidence into its state.

## Execution

1. Decomposition creates an immutable baseline Slice Record for every executable slice and creates or updates the Parent State and canonical ledger.
2. `slice-prep` verifies baseline freshness and produces Slice Preparation Delta only. It inherits parent authority and emits its Inline Slice Ready Gate. It never creates a generic child artifact.
3. The parent reviews all preparation deltas together, checks assignments, CASE/XC/field continuity, ownership, shared semantics, production bindings, and parallel safety. It writes Parent Authorization Decisions and the matching `Parent Authorization` section with the same digest/revision. This is the v2 equivalent of implementation-handoff review.
4. Only an authorized slice can enter the explicit Design Pair boundary or Adaptive Implementation. Non-trivial work begins at `high-implementation-starter`; a valid handoff may invoke `standard-implementation-completer`, and re-entry returns to HIGH. Both update the Slice Record Implementation section.
5. An independent `verification-kernel` updates Slice Verification. It verifies local FR/AC/CASE, deltas, production binding, and producer/consumer evidence; it does not claim parent close or repair gaps. XC completion remains for the Final Record.
6. A simple, selected Direct FixNow selector permits one bounded repair in the same record, followed by formal verification rerun.
7. `cross-slice-verification-kernel` writes only Final Verification Snapshot. `residual-decision-gate` then writes Residual Decision and Close Decision without rewriting verification facts.

## Separate Artifact Creation Gate

Inline section update is the default. A separate artifact requires all of: independent human/tool/model lifecycle; an authority, confidentiality, concurrency, or resume-safety reason that prevents section ownership; Parent State Artifact Exception Register row; a canonical owner; and merge-back/close rule. Generic agent default paths never satisfy this gate. Explicit Design Pair handoff, external manual evidence bundle, required independent audit, large generated evidence, and legacy compatibility may qualify.

## Focused escalation

When a bounded external API, production address, or 1–3 item RC/TP/IC question needs specialist inspection, invoke the relevant generic kernel only with `embedded_output_target`, `embedded_output_section`, and `artifact_layout: compact-slice-record-v2`. It writes a delta into the Slice Record. Shared semantics drift returns to Architecture Slice Readiness; broad scope returns to decomposition; product/policy uncertainty stops for human decision.

## Final audit

Before close confirm current layout consistency, baseline freshness, section ownership, parent assignment, authorization, adaptive delegation compliance, independent local verification, final XC/forbidden-state/production-wiring verification, complete canonical ledger classification, no fake-only completion, and explicit residual disposition. Historical plans are not migrated.

Every non-trivial READY slice starts at `high-implementation-starter`. `READY_FOR_STANDARD_COMPLETION` is required before `standard-implementation-completer`; `NEEDS_HIGH_MODEL_REENTRY` returns to `high-implementation-starter`. Delegation Audit records that HIGH and STANDARD write owners did not overlap. Missing required delegation is `BlockedByMissingAdaptiveImplementationDelegation`. Completion Handoff is inline in the same Slice Record Implementation section unless a registered exception requires a tracked separate file.

## Legacy compatibility

Generic non-sliced kernel agents and their output paths remain available. Legacy split runs may use their existing artifacts. This skill does not remove model assignments or change Design Pair selection and tracked-handoff requirements.

`slice-impl` is legacy compatibility only.
