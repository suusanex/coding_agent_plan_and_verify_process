---
name: Plan Coverage Shared Guardrails
description: Shared invariant guardrails for Plan Coverage Check and Residual Decision Flow agents
# Copyright (c) 2026 suusanex
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Shared invariant guardrails

These rules apply to Plan Coverage Check and Residual Decision Flow agents when an agent explicitly references this shared instruction. Agent-specific responsibilities, artifact destinations, allowed verdict vocabulary, and stop rules remain in each agent file.

## Required invariants

- **Plan is source of truth**: the parent Plan FR / AC remain the source of truth for implementation, verification, residual decisions, and close readiness. Guardrail artifacts narrow deep-check focus; they do not replace or shrink the parent Plan.
- **No fake-only completion**: source-structure checks, stub tests, fake implementations, mocks, or in-memory substitutes are not enough to claim production behavior is complete. Production implementation binding and production wiring must be verified where the Plan requires runtime behavior.
- **Residual requires explicit decision**: unresolved residual, manual, delegated, deferred, aborted, or human-decision items must be explicitly classified before close. Do not infer acceptance from silence or from weaker evidence than a prior run.
- **Reduce breadth, not depth**: token reduction should remove redundant artifact breadth or repeated boilerplate, not the depth of required guardrail checks for the selected scope.
- **Fail closed on missing authority**: if the required Plan authority, implementation authorization, evidence, or human decision is missing, record the blocker and stop instead of treating the item as complete.
- **Adaptive implementation ownership**: after implementation authorization, every non-trivial bounded implementation starts with `high-implementation-starter` on `HIGH_MODEL`. It may delegate only a decision-free remainder to `standard-implementation-completer` on `STANDARD_MODEL`, and that completer must return `NEEDS_HIGH_MODEL_REENTRY` instead of reopening structural decisions. These write owners run serially within one bounded pass.
- **Explicit implementation route selection**: initialize `implementation_route: adaptive` and `implementation_route_source: default` only at fresh intake when no durable route or resume evidence exists. Use `implementation_route: design-pair` only when the user explicitly selected it, and preserve `implementation_route_source: explicit-user-selection` through durable artifacts and resume state. On resume, missing or contradictory route metadata must fail closed and must not be normalized to Adaptive. The only compatibility exception is an exact pre-Design-Pair Adaptive completion handoff that passes the canonical `Legacy Adaptive handoff normalization` predicate and has no Design Pair evidence; record `route_metadata_normalization: legacy-adaptive-handoff`. Do not infer, recommend, or propose Design Pair from risk, difficulty, size, or architecture. When explicitly selected, run `design-pair-implementation-execution` only after implementation authorization and before `high-implementation-starter`.

## Shared artifact discipline

- Repository-tracked artifacts are the durable handoff surface. Do not use chat-only notes, temporary files, or tool-local session state as the final source of truth.
- Every handoff should identify the source artifacts read, the current phase, the next required agent or human action, implementation permission, unresolved items, and close readiness.
- When a shared `Handoff Packet` is used, keep common fields stable while leaving agent-specific verdicts and required sections in the agent that owns them.
- Do not drop a parent Plan item because it is outside the current Guardrail Focus. Classify it as implemented, verified, manual, residual, deferred, out of scope by source, or human-decision required.

## Shared status vocabulary

Use these statuses when an agent needs common progress, residual, or handoff classification. Agent-specific verdicts, profile recommendations, output paths, and stop rules remain in the owning agent file.

| Status | Meaning |
| --- | --- |
| `Done` | The item is complete for the current agent pass. It does not imply feature-level completion unless the owning agent explicitly says so. |
| `PartiallyDone` | Useful progress was made, but the item is not complete. |
| `Deferred` | The item is intentionally not handled in the current pass. |
| `ManualOnly` | Manual or real-environment validation is required. |
| `NeedsHumanDecision` | A product, architecture, policy, or risk decision is needed before safe progress. |
| `NotImplementedOrMismatch` | The implementation is missing, mismatched, or only present in test-side / fake-side form. |
| `OutOfScopeForThisPass` | The work is valid but outside the selected scope for the current pass. |
| `Bound` | A formal production-binding status for test substitutes. Use only when the owning agent's local rules allow it and the required production interface, concrete implementation, wiring / entrypoint, and post-wiring behavior evidence are present. |

## Bounded reading

## Full-coverage decomposition inheritance

For fresh post-decomposition work with `full_coverage_artifact_layout: compact-slice-record-v2`, parent Goal, FR, AC, CASE, risk, architecture authority, and XC roles are inherited rather than re-derived per slice. The canonical owners are Parent Plan, Behavior Spec, Parent triage, architecture baseline, immutable Slice Record baseline, canonical Coverage Ledger, Parent State, and Final Record respectively.

A phase does not imply a separate artifact. Slice Record sections have serial owners: decomposition writes immutable baseline; preparation writes delta; parent writes authorization; Adaptive owner writes implementation; independent verifier writes verification; selected fix owner writes bounded fix; current phase owner writes handoff and ledger delta. Parent State alone owns orchestration and authorization tables; Final Record owns cross-slice verification, residual, and close sections. Do not full-copy the canonical ledger.

Separate artifact creation requires an independent lifecycle plus an authority/confidentiality/concurrency/resume-safety reason, Parent State exception registration, canonical owner, and merge-back rule. Do not create generic per-slice contract/result files merely because an agent has a default output path. A partial or contradictory v1/v2 layout, or a v2 authorization that implicitly uses legacy artifacts, is `BlockedByArtifactLayoutMismatch` and fails closed.

- Read the Plan and upstream artifacts needed for the current phase before reading source code broadly.
- Inspect source files only where the current artifact, selected contract, selected gap, or verification target points.
- Do not continue repository exploration after the current phase has enough evidence to produce its required artifact, verdict, or stop condition.
