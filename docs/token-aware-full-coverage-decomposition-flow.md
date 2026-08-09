# Plan網羅チェック full-coverage decomposition flow

## Purpose

`full-coverage` 判定を、Full autonomous Plan-first flow へのエスカレーションではなく、実装前の Plan slice decomposition として扱うための運用メモです。

このメモは、Plan網羅チェック・残件判定フロー に関する current `full-coverage` contractを要約した補足ポリシーです。`docs/plan-coverage-process-and-agents.md` の`### full-coverage`、main flow、Full Autonomousとの境界、および各active agent contractはこの方針に従います。

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
- Each resulting slice becomes a canonical Slice Living Record while retaining traceability to the parent Plan, approved architecture, decomposition, Case IDs, and XC IDs. It does not re-enter as a fresh standard Plan Coverage run.
- New decompositions record `documentation_level: standard`, `selected_process: full-coverage`, and `artifact_mode: slice-living-record` plus an Artifact Budget.
- Existing agents run in `output_contract: section-delta` mode for their owned section. The Plan Coverage parent/router is the only repository writer for Living Records and the canonical Coverage Ledger.
- Before implementation authorization, the Plan Coverage parent reconfirms the Architecture Slice Readiness baseline and the implementation handoff records Slice ID, readiness verdict, baseline authority / identity, observed semantics, `Match / Drift / Unclear`, and required action. Only a current-baseline `Match` may proceed. `Drift` returns to Architecture Slice Readiness / Elaboration; `Unclear` reruns Architecture Slice Readiness. `ArchitectureNotRequired` still compares against the readiness artifact's Lightweight architecture baseline.
- If Design Pair was explicitly selected, the parent decomposition artifact and each implementation-ready slice handoff preserve `design_pair_handoff`, `design_pair_interaction_stage`, and post-map user evidence. Its first Design Pair turn stops at `target-selection`; unresolved final disposition stops at `disposition-confirmation`. No Adaptive or verification step starts while either stage is waiting.
- Cross-slice contracts must remain explicit and must be verified after slice implementations.
- Cross-slice verification must confirm runtime postconditions after production wiring, not only structural wiring. Production interface / implementation / wiring, source-structure tests, and CI green are not enough unless they prove the parent acceptance condition postcondition.
- Parent acceptance condition forbidden states must be carried into the cross-slice verification artifact and denied by evidence before a pass verdict is allowed.
- Stateful cross-slice contracts must check both producer state and consumer gate. Startup, recovery, async worker, durable state, and state-machine consistency cannot be closed by source-structure evidence alone.
- Reruns must include previous gap / residual closure delta. A previous gap cannot be closed with evidence of the same or weaker strength than the evidence previously judged insufficient.
- Cross-slice verification is not the final close gate. `CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES` first returns to the affected Slice Living Record for triage, one bounded repair pass, slice re-verification, and cross-slice rerun. It must not flow directly to Residual Decision.
- `coverage-gap-resolution-slice.agent.md` is used only when coverage-gap-triage or another permitted direct-selector source emits an explicit FixNow selector. In Living Record mode it returns `Gap Repair Evidence` and Coverage Ledger Delta instead of creating a separate result artifact. If an implementation-realization selector lacks sufficient `Implementation Contract Decisions`, it stops and asks the parent to run `implementation-contract-kernel.agent.md` with `output_contract: section-delta`; it never creates the section or a separate implementation-contract artifact itself.
- A tracked Implementation Completion Handoff may be created only after the parent applies an exact-path `cross-thread-handoff` Artifact Exception row to the target Slice Living Record. A tracked High-model Re-entry Handoff uses delayed registration: STANDARD returns an unpersisted payload, then the parent applies the exact-path exception, saves the payload, and resumes HIGH.

## Minimal chain

```text
Parent Plan Kernel
→ Black-box Behavior Spec Kernel when Plan readiness requires it
→ Parent Plan Kernel rerun for Case-to-Plan mapping when needed
→ Change Risk Triage
→ Architecture Slice Readiness
  → Architecture Elaboration and readiness rerun when needed
→ Plan Slice Decomposition
→ Per-slice Living Record lifecycle
  → Slice-local risk delta and required kernel section deltas
  → Architecture baseline compatibility: Match
  → Explicit Design Pair Target Map / user disposition boundary when selected
  → Adaptive evidence aggregation only after complete / READY_FOR_ADAPTIVE_IMPLEMENTATION
  → Independent Verification section delta
→ Full-Coverage Close Record
  → Cross-Slice Verification Kernel section delta
  → If FixNow candidates: target-slice triage delta
    → one bounded Gap Repair Evidence delta
    → affected slice Verification rerun
    → Cross-Slice Verification rerun
  → Residual Decision Gate section delta
```

## Bounded slice execution

Each executable `plans/<slug>-slice-SL-xxx.md` is both a bounded Slice Plan and its canonical Living Record. Agents run only the selected pre-implementation semantics and return their owned section or subsection delta; they do not create separate slice-local gate artifacts. Before Adaptive Implementation, the Plan Coverage parent reconfirms baseline freshness and the Inline Ready Gate must record a current-baseline `Match`; `Drift` or `Unclear` blocks implementation and returns to the architecture gate. Adaptive returns its normal result and Implementation Self-Map Delta for parent aggregation. A tracked completion handoff requires a pre-applied Artifact Exception. Independent `verification-kernel` then returns Verification Result, Coverage Ledger Delta, and Slice Residuals / Handoff deltas; any later repair is recorded in `Gap Repair Evidence` and followed by a verification rerun.

The base durable artifact budget is five parent control-plane artifacts, one Living Record per executable slice, and one final close record. Conditional Behavior Spec, Slice Architecture, and Design Pair artifacts are counted separately. Any other artifact requires a recorded Artifact Creation Gate reason. Existing pre-redesign runs retain explicit legacy/separate mode and are not silently migrated or mixed with the new mode.

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
