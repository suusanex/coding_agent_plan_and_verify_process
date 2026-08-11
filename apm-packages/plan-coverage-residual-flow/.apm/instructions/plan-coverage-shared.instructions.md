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
- **Minimum sufficient process breadth**: risk trigger count, changed file/project count, security importance, ABI/FFI, local async work, shared storage, or production wiring do not independently justify `full-coverage`. Build the bounded runtime sequence first. Use `full-coverage` only when a source-backed `Why standard-slice is insufficient` escalation gate is `Satisfied`; otherwise keep the same guardrail depth in `contract-kernel` or `standard-slice`.
- **Fail closed on missing authority**: if the required Plan authority, implementation authorization, evidence, or human decision is missing, record the blocker and stop instead of treating the item as complete.
- **Decision ownership is durable**: when an upstream architecture or slice artifact classifies an unresolved item with an owner, human-input requirement, blocking state, and resolution phase, preserve that tuple downstream. An implementation-owned `SliceLocalContract` or `ImplementationDetail` does not become `NeedsHumanDecision` merely because its concrete production address has not been implemented yet. Escalation may override an upstream `Human decision blockers: none` only with new source evidence, the specific product / architecture / policy / risk choice, and why the current agent cannot make it safely.
- **Adaptive implementation ownership**: after implementation authorization, every non-trivial bounded implementation starts with `high-implementation-starter` on `HIGH_MODEL`. HIGH closes non-local decisions from actual code evidence and delegates when all remaining uncertainty is local and reversible. `standard-implementation-completer` on `STANDARD_MODEL` owns production implementation, tests, and validation inside locked boundaries and authorized Work Packages; it returns `NEEDS_HIGH_MODEL_REENTRY` only when a locked non-local decision must change. These write owners run serially within one bounded pass.
- **Explicit implementation route selection**: initialize `implementation_route: adaptive` and `implementation_route_source: default` only at fresh intake when no durable route or resume evidence exists. Use `implementation_route: design-pair` only when the user explicitly selected it, and preserve `implementation_route_source: explicit-user-selection` through durable artifacts and resume state. On resume, missing or contradictory route metadata must fail closed and must not be normalized to Adaptive. The only compatibility exception is an exact pre-Design-Pair Adaptive completion handoff that passes the canonical `Legacy Adaptive handoff normalization` predicate and has no Design Pair evidence; record `route_metadata_normalization: legacy-adaptive-handoff`. Do not infer, recommend, or propose Design Pair from risk, difficulty, size, or architecture. When explicitly selected, run `design-pair-implementation-execution` only after implementation authorization and before `high-implementation-starter`.
- **Full-coverage architecture baseline compatibility**: before implementation authorization for every executable full-coverage slice, the Plan Coverage parent must confirm that the Architecture Slice Readiness baseline is current and compare slice-local pre-implementation decisions with the approved Slice Architecture or the readiness artifact's Lightweight architecture baseline. Record `Match`, `Drift`, or `Unclear`. Only `Match` may proceed to implementation; `Drift` returns to Architecture Slice Readiness / Elaboration, and `Unclear` fails closed and reruns Architecture Slice Readiness. `ArchitectureNotRequired` does not waive this check.
- **Full-coverage de-escalation backstop**: before decomposition begins, Architecture Slice Readiness may return `StandardSliceSufficient` when the parent change can be implemented and verified as one bounded pass. This is a successful route correction to `selected_process: standard-slice`, not an architecture blocker. It must not create Slice Architecture, decomposition, Slice Living Records, or cross-slice verification artifacts.

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
| `NeedsHumanDecision` | A product, architecture, policy, or risk decision is needed before safe progress. Do not use it for an implementation-owned design choice, a missing greenfield production address, or a ManualOnly provisioned secret value. |
| `NotImplementedOrMismatch` | The implementation is missing, mismatched, or only present in test-side / fake-side form. |
| `OutOfScopeForThisPass` | The work is valid but outside the selected scope for the current pass. |
| `Bound` | A formal production-binding status for test substitutes. Use only when the owning agent's local rules allow it and the required production interface, concrete implementation, wiring / entrypoint, and post-wiring behavior evidence are present. |

## Bounded reading

- Read the Plan and upstream artifacts needed for the current phase before reading source code broadly.
- Inspect source files only where the current artifact, selected contract, selected gap, or verification target points.
- Do not continue repository exploration after the current phase has enough evidence to produce its required artifact, verdict, or stop condition.
