---
name: plan-coverage-residual-flow
description: >
  Explicit-invocation-only Plan Coverage Check and Residual Decision Flow.
  Use only when the current user explicitly and affirmatively selects
  `plan-coverage-residual-flow`, or when an upstream process forwards
  durable evidence that the user explicitly selected this exact route.
  Never select, recommend, or propose this skill from a generic
  implementation, fix, continue, or proceed request; from task size,
  difficulty, risk, complexity, or architecture; from existing Plan or
  coverage artifacts; from repository history; or from mere Skill availability.
  A question, quote, negation, comparison, or informational mention of the
  route name is not an invocation; do not activate or read this Skill for it.
---

# Plan Coverage Check and Residual Decision Flow

<!--
Copyright (c) 2026 suusanex (GitHub UserName)
SPDX-License-Identifier: CC-BY-4.0
License: https://creativecommons.org/licenses/by/4.0/
Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
-->

## Invocation authorization

Before reading any repository artifact, creating or updating any Plan Coverage artifact, or invoking any agent, verify that this route is authorized.

Authorization exists only when one of the following is true:

1. The current user message explicitly and affirmatively selects the exact literal route name `plan-coverage-residual-flow` for this task.
2. An upstream durable artifact contains all of the following fields and evidence:

   ```yaml
   process_route: plan-coverage-residual-flow
   process_route_source: explicit-user-selection
   user_selection_evidence: <reference to the actual user message that selected this exact route>
   ```

`user_selection_evidence` must identify an actual user message or durable user-turn reference. An upstream process, agent, or AI recommendation is not user selection evidence.

A literal, quoted, negated, rejected, comparative, question-based, or informational mention of `plan-coverage-residual-flow` is not direct authorization. When the current message does not clearly and affirmatively select this route, treat authorization as absent.

None of the following authorizes this route:

- `実装して`, `修正して`, `続けて`, `このPlanを実装して`, or another generic implementation, fix, continue, or proceed request
- a large, difficult, high-risk, complex, or architecture-heavy task
- an existing Plan, Plan Coverage artifact, coverage ledger, or prior handoff
- prior use of this process in the repository
- an agent or upstream process deciding that this flow would be useful
- the Skill being installed or otherwise available

When authorization is absent:

- do not run this flow
- do not read repository artifacts on behalf of this flow
- do not create or update Plan Coverage artifacts
- do not invoke Plan Coverage agents
- do not recommend or propose this route
- return control to the caller or the repository's normal implementation route
- do not select another large process from this Skill

## Authorized use

After the invocation authorization gate passes, this skill is the entrypoint for the standard Plan網羅チェック・残件判定フロー.

The APM package and this entrypoint skill use the same name, `plan-coverage-residual-flow`. Use that name as the normal invocation name for the flow.

This skill does not replace the individual agents. The source of truth for agent-specific rules, output formats, and verdict vocabulary remains `.github/agents/*.agent.md`.

After authorization, use this flow to:

- preserve the full parent Plan FR / AC as the source of truth for a bounded Plan-first change
- decide which Plan網羅チェック agent runs next
- check runtime, production-binding, production-wiring, or test-substitute risk within this authorized flow
- prevent unresolved items from being closed by agent inference alone
- progress the complete Plan Coverage Check and Residual Decision Flow

## Do not use when

Do not use this skill when:

- the change is a simple local fix that does not need a Plan artifact
- the user explicitly selected the Full autonomous Plan-first flow
- the agent is trying to resolve product semantics, policy, or expected behavior by inference instead of recording `NeedsHumanDecision` and stopping
- the agent is trying to treat a requirement-elaboration gap as implementation work

## Required inputs

Read only the artifacts and related source files needed for the current phase. Do not scan the whole repository indiscriminately.

Start from the available items in this order:

1. user prompt, issue body, high-level requirement, or prior handoff
2. bounded Plan from `plan-kernel.agent.md`
3. Black-box Behavior Spec artifact, when a separate behavior spec artifact was required
4. `change-risk-triage.agent.md` output
5. `architecture-slice-readiness.agent.md` output, when full-coverage was selected
6. `architecture-elaboration.agent.md` output / `plans/<slug>-slice-architecture.md`, when readiness requires it
7. `plan-slice-decomposition.agent.md` output, after the architecture gate permits decomposition
8. implementation contract, runtime contract, test design, handoff review, implementation, verification, coverage, and residual artifacts from the current pass
9. relevant docs and source files only, selected from the artifacts above

If a required upstream artifact is absent, route to the agent that creates or refreshes it. Do not proceed by reconstructing missing decisions from source inspection alone.

## Documentation level

The flow records `documentation_level` as routing metadata for the amount of Plan Coverage artifact structure required for the current bounded work.

Allowed values:

| Value | Meaning |
| --- | --- |
| `lite` | Use a compact Plan Coverage artifact for a small, bounded change when the Plan can still preserve source-of-truth, FR / AC coverage, implementation authorization, verification summary, and residual decision fields without separate guardrail artifacts. |
| `standard` | Use the normal compressed Plan Coverage chain when the work needs separate risk, behavior, contract, verification, or residual-decision artifacts to remain traceable. |

Do not add `strict` as a `documentation_level`. When more rigor is needed, route to `standard` and then to the appropriate guardrail or advanced route.

`full-coverage` is not a `documentation_level`. It remains a process profile / route selected after `Plan readiness: ReadyForRiskTriage` when a ready parent Plan is too broad or interconnected for one bounded pass.

`artifact_mode` is separate routing metadata. New full-coverage decompositions must record:

```yaml
documentation_level: standard
selected_process: full-coverage
artifact_mode: slice-living-record
```

`slice-living-record` controls only the durable artifact layout for executable full-coverage slices. It does not reduce guardrails and is not used by normal lite or standard routes. Pre-redesign full-coverage runs may resume in their explicit legacy/separate artifact mode under the compatibility rules below.

When `documentation_level: lite` is selected, use the bundled `references/plan-coverage-lite.md` reference as the compact artifact shape. The Lite artifact must still preserve source-of-truth, FR / AC coverage, Inline Ready Gate, Implementation Self-Map, Verification Summary, and Residual / Close Decision sections.

The Inline Ready Gate may replace `plans/<slug>-implementation-handoff-review.md` only when it explicitly says it is equivalent to `implementation-handoff-review`, every required check is `PASS` or source-backed `N/A`, and there is no unresolved blocking item. This is implementation authorization for the bounded pass, not close readiness.

For `documentation_level: standard`, use the bundled `references/coverage-ledger.md` reference when a durable parent Plan coverage ledger is needed. `plans/<slug>-coverage-ledger.md` is the canonical ledger. Intermediate agents should emit `Coverage Ledger Delta` instead of repeating the full ledger when only a small set of rows changed. When the canonical ledger exists, handoff and verification artifacts should point their Parent Plan Coverage Ledger section to it and put current-pass changes in `Coverage Ledger Delta`.

Use inline behavior sketch only when it can preserve source-backed behavior coverage in the compact artifact. Escalate to `black-box-behavior-spec-kernel.agent.md` when case count, recovery / rollback / retry / replay / cleanup / durable state / idempotency, negative expectations, ambiguous Case-to-Plan mapping, human decisions, or standard / full-coverage routing require a separate artifact.

`Expansion required: Yes` does not automatically mean a separate Black-box Behavior Spec artifact is required. Record `Inline behavior sketch sufficient` and `Behavior spec artifact required` separately. Continue with a ready Plan only when either the inline sketch preserves FR / AC traceability or the required behavior spec exists and Case-to-Plan mapping is complete.

The Lite artifact must include an explicit no fake-only completion check. Stub, fake, mock, in-memory, or test-helper evidence alone cannot support implementation completion or close readiness.

## Implementation route selection

At flow intake, record one of the following durable metadata pairs.

Default route:

```yaml
implementation_route: adaptive
implementation_route_source: default
```

Only when the user explicitly selects Design Pair:

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
```

Do not automatically select, recommend, or propose Design Pair based on difficulty, risk, task size, or architecture. Do not ask the user to choose between the routes when no explicit selection exists; keep the default Adaptive route.

Preserve both fields through the Plan Coverage Lite artifact, canonical coverage ledger / handoff review, parent decomposition artifact, each implementation-ready slice handoff, resume, and implementation result. For the Design Pair route, also record `design_pair_handoff: plans/<slug>-design-pair-implementation-handoff.md` and `design_pair_interaction_stage: not-started / target-selection / disposition-confirmation / upstream-decision / complete / artifact-repair`. Missing or contradictory route metadata, interaction state, Target Map presentation evidence, or post-map user evidence must not be inferred during resume. The only compatibility exception is an exact pre-Design-Pair Adaptive completion handoff with all former required fields and no Design Pair evidence; apply the canonical `Legacy Adaptive handoff normalization`, record `route_metadata_normalization: legacy-adaptive-handoff`, and reject partial new-schema or Design Pair evidence cases.

The `design-pair-implementation-execution` package remains a separate package. When both packages are installed for the same target and the user explicitly selects Design Pair, Plan Coverage may invoke that route and must keep `plan-coverage-residual-flow` selection evidence separate from Design Pair implementation route selection evidence. While Design Pair is waiting, do not fall back to Adaptive.

## Standard route

Run the flow in this order unless a stop condition applies:

1. Run `plan-kernel.agent.md`.
2. If Plan readiness is `NeedsPlanBehaviorExpansion` because source-to-case expansion is missing, run `black-box-behavior-spec-kernel.agent.md`.
3. If behavior Case IDs exist but are not mapped to Plan FR / AC or explicit disposition, return to `plan-kernel.agent.md`.
4. If Plan readiness is `NeedsHumanDecision`, stop and request the human decision. Do not proceed to risk triage or implementation.
5. Record `documentation_level: lite / standard`. Use `lite` only when the compact Plan Coverage artifact can preserve all required source-of-truth, coverage, implementation authorization, verification, and residual-decision fields. Use `standard` when separate guardrail artifacts are needed. For `lite`, use the Plan Coverage Lite template shape and keep the no fake-only completion checks in the Verification Summary.
6. Run `change-risk-triage.agent.md` only when Plan readiness is `ReadyForRiskTriage` and `documentation_level` has been recorded.
7. Follow the `change-risk-triage` result:
   - `contract-kernel`: run the needed implementation contract, runtime contract, and test-design kernel steps.
   - `standard-slice`: run one bounded parent Plan pass.
   - `fix-slice`: run only the explicitly selected FixNow items.
   - `full-coverage`: follow the full-coverage route below.
8. In a normal bounded pass, run the needed pre-implementation gates:
   - `implementation-contract-kernel.agent.md`, when implementation-realization risk is present or unclear
   - `implementation-contract-review-kernel.agent.md`, only as an explicit review-only fallback for the implementation contract self-check verdict
   - `runtime-contract-kernel.agent.md`
   - `test-design-kernel.agent.md`
   - `implementation-handoff-review.agent.md`
9. Implement only after the handoff review or a documented equivalent Inline Ready Gate allows implementation for the bounded parent Plan pass.
   - When `implementation_route: adaptive`, start the existing Adaptive route directly.
   - When `implementation_route: design-pair` and `implementation_route_source: explicit-user-selection`, run `design-pair-implementation-execution` first. It may inspect bounded source and write only the tracked Design Pair handoff; it must not edit production code / tests. Its first turn must present the complete bounded Target Map, save `AWAITING_USER_INPUT / target-selection`, and stop for a new user response. If final disposition is still missing after discussion, save `AWAITING_USER_INPUT / disposition-confirmation` and stop again. Start Adaptive Implementation only after the same handoff records valid post-map user evidence, `interaction_stage: complete`, and `READY_FOR_ADAPTIVE_IMPLEMENTATION` with no blocking `Upstream-Decision-Required`.
   - While Design Pair is waiting, persist the handoff path and interaction stage in the parent artifact. Do not treat waiting as completion, fall back to Adaptive, or start verification / residual handling.
   - If an explicitly selected Design Pair skill is unavailable, route metadata is missing, or the handoff is invalid, stop instead of silently falling back to Adaptive or implementing directly.
   After this optional pre-stage, every non-trivial pass starts with `high-implementation-starter.agent.md` on `HIGH_MODEL`; do not classify shape need from documents or route directly to a standard implementation agent.
   - `READY_FOR_STANDARD_COMPLETION`: validate the complete Implementation Completion Handoff, then run `standard-implementation-completer.agent.md` on `STANDARD_MODEL` serially.
   - `CONTINUE_HIGH_IMPLEMENTATION`: continue the same high-model run when possible; use it as a resume state only at an execution boundary.
   - `COMPLETED_BY_HIGH_MODEL`: aggregate the implementation evidence and continue to verification.
   - `NEEDS_HIGH_MODEL_REENTRY`: stop the completion agent, preserve its re-entry handoff and current worktree, then return serially to `high-implementation-starter.agent.md`.
   - `REPLAN_REQUIRED`, `HUMAN_DECISION_REQUIRED`, or `BLOCKED`: preserve the worktree and evidence, record the stop reason, and do not continue to verification.
   When Parent Plan Coverage, Behavior Case, slice, runtime-contract, test-point, implementation-contract, or gap bindings are supplied, every implementation owner emits an `Implementation Self-Map Delta` for the changes made in that phase. Use this exact schema so traceability survives HIGH -> STANDARD -> HIGH transitions:

   ```md
   ## Implementation Self-Map Delta

   | Change ID | Change | File / Symbol | Reason | Related Plan item | Related Behavior Case IDs | Related SL / XC / RC / TP / IC / Gap item | Assumption made | Review hint |
   | --- | --- | --- | --- | --- | --- | --- | --- | --- |
   ```

   Use `none` for a confirmed non-applicable binding and `unknown` only when the source artifact does not resolve it. The active implementation agent returns the current-phase rows; it does not rewrite prior phase rows. The orchestrator is the single aggregation owner: it merges phase deltas by stable Change ID into the `Implementation Self-Map` in `plans/<slug>-implementation-execution.md`, alongside phase owners, verdict sequence, checks, acceptance evidence, and Remaining Work. Keep the completion handoff inline unless resume, another thread/model, or another worker requires a tracked `plans/<slug>-implementation-completion-handoff.md`.
10. Run `verification-kernel.agent.md`.
11. If unresolved coverage items or FixNow candidates remain, run `coverage-gap-triage.agent.md` unless `verification-kernel.agent.md` emitted a complete `Direct FixNow selectors` table for 1〜2 simple gaps.
12. Before final close, run `residual-decision-gate.agent.md`. If no residual candidates remain, it may produce `READY_TO_CLOSE_WITH_NO_RESIDUALS`. If residual, manual, or human-decision candidates remain, it must classify them before close.
13. If `coverage-gap-triage`, `verification-kernel`, or `residual-decision-gate` emits an explicit FixNow selector, run `coverage-gap-resolution-slice.agent.md`, then return to verification and residual decision as needed. Direct selectors from verification or residual decision must include source artifact, source section/table, existing ID, gap type, Plan item / Case ID, target files / addresses, and why direct FixNow is safe.

The parent Plan FR / AC remain the implementation and verification source of truth throughout the route. Guardrail Focus artifacts are deep-check guardrails; they are not an implementation scope reduction.

## Full-coverage route

`full-coverage` is not an automatic move to the Full autonomous Plan-first flow.

Use `full-coverage` only after Plan readiness is `ReadyForRiskTriage`. It means the ready parent Plan is too broad, strongly interconnected, or cross-slice to handle safely as a single bounded pass.

When `change-risk-triage.agent.md` recommends `full-coverage`:

1. Run `architecture-slice-readiness.agent.md`.
2. Follow the readiness verdict:
   - `ReadyForSliceDecomposition`: require the cited current `plans/<slug>-slice-architecture.md`, then continue.
   - `NeedsArchitectureElaboration`: run `architecture-elaboration.agent.md`, then rerun readiness.
   - `ArchitectureNotRequired`: use the current source-backed readiness artifact and its Lightweight architecture baseline as the baseline authority; continue without a separate architecture artifact.
   - `NeedsHumanDecision`: stop.
   When elaboration is required, preserve R1 as a non-freshness `elaboration_trigger` snapshot. R2 may update the same readiness path and must track the Slice Architecture external content hash; R1 path/hash changes do not stale the architecture.
3. Do not continue while any `ArchitectureCritical` or `NeedsHumanDecision` residual remains. Recompute tracked source content hashes / explicit revisions and inspect the source-repository-commit-to-current diff for declared watch paths. HEAD equality is not required, and generated readiness/architecture artifact commits do not self-invalidate the baseline. Path equality is insufficient; any semantic baseline change makes the verdict stale and requires a readiness rerun.
4. Run `plan-slice-decomposition.agent.md` only after the architecture gate permits it. Every new decomposition records `documentation_level: standard`, `selected_process: full-coverage`, and `artifact_mode: slice-living-record` and includes an Artifact Budget. The decomposition's executable slice artifacts become canonical Slice Living Records using `references/full-coverage-slice-living-record.md`; do not create a second slice-record file.
5. Do not re-enter each executable slice as a new standard Plan Coverage run. For each slice, read the parent Plan, parent triage, approved readiness / architecture source, decomposition, canonical Coverage Ledger, and Slice Living Record baseline. Preserve parent FR / AC, Case IDs, XC IDs, field continuity, architecture source, and explicit residuals without re-deciding shared architecture or work assigned to another slice.
6. Use existing agents in section-delta mode. Give each agent `artifact_mode: slice-living-record`, `living_record_path`, `canonical_coverage_ledger`, and `output_contract: section-delta`. The agent returns only its owned section body and Coverage Ledger Delta; it must not write repository files or regenerate another section. `change-risk-triage.agent.md` runs slice-local delta mode and inherits the parent risk decision without selecting full-coverage again. If the slice remains full-coverage-sized, return `needs-further-decomposition`.
7. The Plan Coverage parent/router is the only repository writer for Slice Living Records and the canonical Coverage Ledger. Before applying a delta, validate target path, target section, semantic owner, existing section, and stable Delta ID. Reject cross-section or cross-slice writes. Apply the Living Record and ledger updates atomically and mark the delta Applied only after the canonical ledger succeeds.
8. Run only the pre-implementation kernels selected by the slice risk delta: implementation contract when implementation-realization risk requires it, runtime contract when Guardrail Focus requires it, test design when required, then `implementation-handoff-review.agent.md` for the `Inline Ready Gate` section. Use source-backed `N/A` for an inapplicable section; absence is not N/A.
9. Before the Inline Ready Gate may authorize implementation, the Plan Coverage parent owns the `Architecture baseline compatibility` check:
   - Recompute the Architecture Slice Readiness tracked source hashes / revisions and inspect declared watch-path changes. A stale, missing, or contradicted baseline is `Unclear` and requires an Architecture Slice Readiness rerun before implementation.
   - For `ReadyForSliceDecomposition`, compare slice-local pre-implementation decisions with the current approved Slice Architecture. For `ArchitectureNotRequired`, compare them with the current readiness artifact's Lightweight architecture baseline; this verdict does not waive the check.
   - Record Slice ID, Readiness verdict, Baseline authority, Baseline identity, Observed semantics, `Match / Drift / Unclear`, and Required action in `Inline Ready Gate`.
   - Only a current-baseline `Match` may proceed. `Drift` returns to Architecture Slice Readiness / Elaboration. `Unclear` fails closed and reruns Architecture Slice Readiness.
10. Preserve `implementation_route`, `implementation_route_source`, `design_pair_handoff`, and `design_pair_interaction_stage` in the parent decomposition and Slice Living Record. A Design Pair route waiting at target selection, disposition confirmation, upstream decision, or artifact repair must not advance to Adaptive or verification.
11. Every non-trivial implementation-ready slice starts with `high-implementation-starter.agent.md`; a valid `READY_FOR_STANDARD_COMPLETION` handoff may invoke `standard-implementation-completer.agent.md`. Adaptive agents keep their standalone output contract and return implementation evidence plus `Implementation Self-Map Delta`. The Plan Coverage parent aggregates those results into `Implementation Evidence` and `Implementation Self-Map`; Adaptive is not a Living Record writer and no normal `*-implementation-execution.md` file is created.
12. Run `verification-kernel.agent.md` independently from the implementation owner. It returns deltas for `Verification Result`, `Coverage Ledger Delta`, and `Slice Residuals / Handoff`; it does not create a normal `*-verification-kernel.md` file. Verification fails closed if any earlier implementation-authorization or implementation ledger delta is pending, if production binding/wiring is missing, or if evidence is fake-only.
13. Apply each verified slice's ledger delta before advancing. Do not start another dependent slice or final cross-slice verification until every required predecessor is independently verified and its pending delta count is zero.
14. After all required slices are independently verified, create `plans/<slug>-full-coverage-close.md` from `references/full-coverage-close.md`. Run `cross-slice-verification-kernel.agent.md`, apply its section and ledger delta, then run `residual-decision-gate.agent.md`, apply its section and ledger delta, and only then determine close readiness. These agents retain separate semantics and verdict vocabularies even though they share the close record.

The base durable artifact budget is `5 + executable slice count + 1`, or at most `6 + executable slice count`: five parent control-plane artifacts, one Living Record per executable slice, and one final close record. Black-box Behavior Spec, Slice Architecture, Design Pair handoff, and explicitly gated exception artifacts are conditional and counted separately with their source condition or exception reason.

Before creating any separate slice-local artifact, record an `Artifact Exceptions` row with exactly one allowed reason code: `cross-thread-handoff`, `parallel-write-isolation`, `human-approval-wait`, `external-audit-evidence`, or `record-size-limit`. The exception is normally supplemental and cannot replace the canonical Plan, Living Record, or Coverage Ledger. Parallel work may use different slice records; multiple writers must not edit the same slice record concurrently.

New runs must not mix legacy separate-artifact slices with Living Record slices. For resume, use explicit `artifact_mode`. An explicit legacy/separate mode resumes unchanged. A pre-redesign artifact with no mode may be recognized only when its existing artifact set clearly matches the old contract; record compatibility normalization and do not silently migrate it. Artifact Creation Gate supplements do not count as mixed modes.

Do not use `full-coverage` for:

- missing source-to-case behavior expansion
- missing Case-to-Plan mapping
- undecided product semantics or expected behavior
- implementation scope shrink

Those are Plan readiness failures and must return to `black-box-behavior-spec-kernel.agent.md`, `plan-kernel.agent.md`, or explicit human decision.

## Close conditions

Close is allowed only when all of these are true:

- Parent Plan FR / AC are implemented and verified, or explicitly dispositioned by valid flow artifacts
- Guardrail Focus runtime contract, test point, production binding, and production wiring checks are complete where required
- unresolved items are absent, or explicit human decision accepted / delegated / deferred / aborted them with owner, method, and required evidence where applicable
- `residual-decision-gate.agent.md` produced a close-ready verdict using its allowed verdict vocabulary
- Parent Plan Coverage Ledger has no unclassified rows
- Canonical Coverage Ledger and all relevant Coverage Ledger Delta rows have no unresolved contradiction
- every required Slice Living Record has an independent verification verdict
- pending Coverage Ledger Delta count is zero in every Slice Living Record and the Full-Coverage Close Record

Close is not allowed when any of these are true:

- Plan readiness is `NeedsPlanBehaviorExpansion`
- Plan readiness is `NeedsHumanDecision`
- `ManualVerificationRequired` is present and not delegated or otherwise explicitly decided
- a residual candidate lacks explicit human decision
- a previous residual is removed using only equal or weaker evidence than the previous run
- source-structure tests or CI green are used as the only proof of runtime postcondition
- production implementation or production wiring remains unverified
- Parent Plan Coverage Ledger has unclassified rows
- Coverage Ledger Delta contradicts the canonical coverage ledger and the contradiction has not been resolved
- a required slice is unverified or any earlier authorization, implementation, verification, cross-slice, or residual delta is pending

Residual candidates are not accepted merely because they are recorded. Explicit human decision is required before they can become close-compatible decisions.

## Output expectations

Every parent-agent turn using this skill should report:

- current phase
- source artifacts read
- Plan readiness
- Architecture Slice Readiness verdict, when full-coverage was selected
- documentation_level
- next agent to use
- why that agent is next
- whether implementation is allowed now
- current adaptive implementation owner and verdict sequence, once implementation has started
- completion handoff status and high-model re-entry reason, when applicable
- implementation_route and implementation_route_source
- Design Pair handoff path, interaction stage, Target Map presentation / post-map user evidence, selected / delegated / pending Target IDs, Locked Decision IDs, and compliance/conflict evidence when explicitly selected
- residual, manual, or human-decision candidates
- close readiness
- concrete next action

Use existing agent verdict vocabulary. Do not invent replacement verdicts in this skill.

## Codex and GitHub Copilot compatibility

Keep routing language tool-neutral. Codex may consume this as a repository-local skill, while GitHub Copilot can translate the same sequence into custom agents, prompt files, or custom instructions.

Always spell out agent file names, artifact names, Plan readiness values, and close blockers so the flow can be moved between Codex and GitHub Copilot without changing the process meaning.
