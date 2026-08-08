# Plan網羅チェック full-coverage decomposition flow

## Purpose

`full-coverage` 判定を、Full autonomous Plan-first flow へのエスカレーションではなく、実装前の Plan slice decomposition として扱うための運用メモです。

このメモは、Plan網羅チェック・残件判定フロー に関する `full-coverage` の意味付けを要約した補足ポリシーです。`docs/plan-coverage-process-and-agents.md` 側でも、`### full-coverage`、main flow、full autonomous flow、および `runtime-contract-kernel.agent.md` の escalation condition をこの方針に合わせて更新します。

## Policy

- `full-coverage` means: a `ReadyForRiskTriage` parent Plan is too broad or strongly interconnected to implement as one bounded pass.
- `full-coverage` does not mean that many executable slices are required. If parent acceptance conditions, cross-slice contracts, field continuity, and Behavior Case mapping remain traceable, few slices are valid, including a 2-slice decomposition.
- `full-coverage` does not mean: missing behavior expansion, missing Case-to-Plan mapping, or undecided expected behavior. Those are Plan readiness failures and must return to `black-box-behavior-spec-kernel.agent.md`, `plan-kernel.agent.md`, or human decision.
- `full-coverage` does not mean: run `plan-generation.agent.md`, `runtime-evidence.agent.md`, or `integration-test-design.agent.md`.
- The next step is always `architecture-slice-readiness.agent.md`; `full-coverage` must not transition directly to decomposition.
- `ReadyForSliceDecomposition` requires a current `plans/<slug>-slice-architecture.md`. `ArchitectureNotRequired` permits decomposition without that artifact only when the readiness verdict gives a source-backed simple-structure reason.
- `NeedsArchitectureElaboration` routes to `architecture-elaboration.agent.md` and then reruns readiness. `NeedsHumanDecision`, `ArchitectureCritical`, missing, stale, or contradicted architecture artifacts block decomposition.
- `plan-slice-decomposition.agent.md` must consider delegation overhead. A candidate slice should be executable only when running the required Plan Coverage gates, Adaptive Implementation, and verification as a separate bounded pass has value.
- Candidate slices that share owner, module, production wiring, verification route, and parent acceptance condition should be coalesced unless there is a documented reason to keep them separate.
- Small independent slices require `Small slice justification`; otherwise they should be recorded as `merge-candidate`, `too-small-to-delegate`, or `coalesce-with-SL-xxx` and not sent to downstream Plan Coverage execution.
- The broad autonomous flow remains available only as an explicit, separate process choice; it is not the default interpretation of `full-coverage` inside Plan網羅チェック triage.
- Each resulting slice re-enters the Plan Coverage flow as a bounded Plan pass while retaining traceability to the parent Plan, approved architecture, decomposition, Case IDs, and XC IDs.
- Before implementation authorization, the Plan Coverage parent reconfirms the Architecture Slice Readiness baseline and the implementation handoff records Slice ID, readiness verdict, baseline authority / identity, observed semantics, `Match / Drift / Unclear`, and required action. Only a current-baseline `Match` may proceed. `Drift` returns to Architecture Slice Readiness / Elaboration; `Unclear` reruns Architecture Slice Readiness. `ArchitectureNotRequired` still compares against the readiness artifact's Lightweight architecture baseline.
- If Design Pair was explicitly selected, the parent decomposition artifact and each implementation-ready slice handoff preserve `design_pair_handoff`, `design_pair_interaction_stage`, and post-map user evidence. Its first Design Pair turn stops at `target-selection`; unresolved final disposition stops at `disposition-confirmation`. No Adaptive or verification step starts while either stage is waiting.
- Cross-slice contracts must remain explicit and must be verified after slice implementations.
- Cross-slice verification must confirm runtime postconditions after production wiring, not only structural wiring. Production interface / implementation / wiring, source-structure tests, and CI green are not enough unless they prove the parent acceptance condition postcondition.
- Parent acceptance condition forbidden states must be carried into the cross-slice verification artifact and denied by evidence before a pass verdict is allowed.
- Stateful cross-slice contracts must check both producer state and consumer gate. Startup, recovery, async worker, durable state, and state-machine consistency cannot be closed by source-structure evidence alone.
- Reruns must include previous gap / residual closure delta. A previous gap cannot be closed with evidence of the same or weaker strength than the evidence previously judged insufficient.
- Cross-slice verification is not the final close gate. Unresolved items must go through `residual-decision-gate.agent.md`.
- `coverage-gap-resolution-slice.agent.md` is used only when coverage-gap-triage or residual-decision-gate emits an explicit FixNow selector.

## Minimal chain

```text
Parent Plan Kernel
→ Black-box Behavior Spec Kernel when Plan readiness requires it
→ Parent Plan Kernel rerun for Case-to-Plan mapping when needed
→ Change Risk Triage
→ Architecture Slice Readiness
  → Architecture Elaboration and readiness rerun when needed
→ Plan Slice Decomposition
→ Per-slice Plan網羅チェック・残件判定フロー
  → Architecture baseline compatibility: Match
  → Explicit Design Pair Target Map / user disposition boundary when selected
  → Adaptive implementation only after complete / READY_FOR_ADAPTIVE_IMPLEMENTATION
→ Cross-Slice Verification Kernel
→ Residual Decision Gate
→ FixNow repair only when explicit selector exists
```

## Bounded slice execution

Each executable `plans/<slug>-slice-SL-xxx.md` is a bounded Plan owned by Plan Coverage. It runs the standard pre-implementation gates required by its recommended profile. Before Adaptive Implementation, the Plan Coverage parent reconfirms baseline freshness and the implementation handoff must record a current-baseline `Match`; `Drift` or `Unclear` blocks implementation and returns to the architecture gate. The slice must not redefine parent requirements or shared architecture, and it must leave cross-slice completion to `cross-slice-verification-kernel.agent.md`. Parent residual and close decisions use the normal `residual-decision-gate.agent.md` output.

## Synthetic self-check fixture

This fixture assumes the Architecture Slice Readiness Gate has already approved the architecture baseline. The broader readiness routing fixtures are defined in `docs/architecture-slice-readiness-validation.md`.

Use this anonymous fixture when reviewing cross-slice verification behavior:

```text
Startup.Restore()
  ProducerSnapshot = Active

Startup.StartWorker()
  Worker started

Consumer.Push()
  if ConsumerPhase != Accepting:
      reject
```

Source-structure evidence that `Restore()` runs before `StartWorker()` and `ProducerSnapshot` becomes `Active` is wiring evidence only. If `ConsumerPhase` remains non-accepting, cross-slice verification must not pass.

Expected verdict:

```text
BLOCKED_BY_PARENT_ACCEPTANCE_GAP
or
BLOCKED_BY_CROSS_SLICE_CONTRACT_MISMATCH
```
