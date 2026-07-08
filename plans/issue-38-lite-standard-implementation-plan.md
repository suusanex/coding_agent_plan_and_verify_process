# Issue #38 Lite / Standard Implementation Plan

## Source Context

- Issue: https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/38
- Issue title: Plan Coverage Flow の Lite/Standard 化と軽量化
- Issue state at planning time: Open, no issue comments
- This artifact is analysis only. It does not implement Issue #38.

## Planning Constraints

- Code, agent, skill, README, and template implementation is out of scope for this planning task.
- The implementation plan must keep the existing guardrail invariants:
  - `Plan is source of truth`
  - `No fake-only completion`
  - `Residual requires explicit decision`
- `strict` must not become a supported `documentation_level`.
- `full-coverage` remains a route / selected process, not a documentation level.
- Each implementation slice below has one primary responsibility. If an implementation pass discovers that a slice requires broad rewrites outside its listed target files, split that slice before editing.

## Existing File Map

| Area | Existing path | Current role observed |
| --- | --- | --- |
| Plan Coverage skill | `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` | Direct entrypoint for Plan Coverage Check and Residual Decision Flow |
| Plan Coverage package manifest | `apm-packages/token-aware-guardrail-kernel-flow/apm.yml` | Ships root `.github/agents/*.agent.md` dependencies into APM targets |
| Codex-first router skill | `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` | Task weight, selected process, state, delegation, READY / close rules |
| Codex-first instructions | `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md` | Codex-first runtime instruction set |
| Codex-first state template | `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md` | Core resume state and audit ledger are currently combined |
| Codex-first installer | `apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs` | Copies Codex-first skill, agents, config, and templates |
| Agent manifests | `.github/agents/*.agent.md` | Source of truth for agent-specific rules, output sections, verdicts |
| Main docs | `README.md`, `docs/token-aware-guardrail-kernel-process-and-agents.md` | Process overview, routing examples, artifact naming, guardrail semantics |
| Codex-first docs | `apm-packages/codex-first-ai-development-process/docs/*.md` | User / maintainer / process docs and validation samples |
| Validation examples | `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-validation.md` | Existing sample suite for router behavior |

## Implementation Order

| Order | Slice | Primary responsibility | Depends on |
| --- | --- | --- | --- |
| 1 | SL-001 | Add shared common instruction source and package wiring | none |
| 2 | SL-002 | Add direct Plan Coverage `documentation_level` routing vocabulary | SL-001 |
| 3 | SL-003 | Add Codex-first router `documentation_level` selection | SL-002 |
| 4 | SL-004 | Define Plan Coverage Lite artifact template | SL-002 |
| 5 | SL-005 | Define Inline Ready Gate as handoff-equivalent | SL-004 |
| 6 | SL-006 | Define inline behavior sketch and escalation to Behavior Spec | SL-004 |
| 7 | SL-007 | Define canonical coverage ledger plus delta updates | SL-005 |
| 8 | SL-008 | Conditionalize coverage-gap-triage and direct FixNow selector | SL-007 |
| 9 | SL-009 | Add self-check / readiness verdict to implementation-contract-kernel | SL-001 |
| 10 | SL-010 | Convert implementation-contract-review-kernel to compatibility shim / review-only mode | SL-009 |
| 11 | SL-011 | Migrate pre-implementation agents to shared instruction references | SL-001, SL-009, SL-010 |
| 12 | SL-012 | Migrate post-implementation agents to shared instruction references | SL-001, SL-007, SL-008 |
| 13 | SL-013 | Split Codex-first state into core and audit templates | SL-003 |
| 14 | SL-014 | Add VAL-001 to VAL-010 validation samples | SL-004 through SL-013 |
| 15 | SL-015 | Update README and user / maintainer docs for final consistency | all prior slices |

## Slice Details

### SL-001: Shared Common Instruction Source

| Field | Plan |
| --- | --- |
| Target files | New `.github/instructions/plan-coverage-shared.instructions.md`; `apm-packages/token-aware-guardrail-kernel-flow/apm.yml`; `apm-packages/codex-first-ai-development-process/apm.yml` |
| Implementation content | Add a shared instruction file for common failure modes, guardrail intent, Plan source-of-truth rule, no fake-only completion, residual decision basics, shared Handoff Packet fields, shared status vocabulary, lite / standard routing policy, portability rule, and "do not over-read" rule. Add manifest dependencies so the instruction is bundled with agents. Do not move agent-specific output paths, allowed verdict vocabulary, or stop conditions into the shared file. |
| Verification method | `rg -n "Plan is source of truth|No fake-only completion|Residual requires explicit decision|documentation_level|lite|standard" .github/instructions/plan-coverage-shared.instructions.md`; inspect both `apm.yml` files for the new dependency path. |
| Dependencies | None |
| Completion criteria | Common instruction exists, is package-bundled, and explicitly says verdict vocabulary / output paths / stop conditions remain agent-owned. |
| Rollback | Remove the new instruction file and manifest dependency entries. No behavior changes should remain because no agent consumes it yet. |

### SL-002: Direct Plan Coverage Documentation Level Routing

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`; `.github/agents/change-risk-triage.agent.md`; `.github/agents/plan-kernel.agent.md` |
| Implementation content | Introduce `documentation_level: lite / standard` in the direct Plan Coverage flow. Define `lite` and `standard`, forbid `strict`, and state that `full-coverage` is a route / process profile after `ReadyForRiskTriage`. Update the skill flow so lite can use a single artifact and standard can use compressed guardrails. Update triage / plan handoff vocabulary so ready broad work records `documentation_level: standard` plus selected route `full-coverage`, rather than treating full coverage as a level. |
| Verification method | `rg -n "documentation_level|lite|standard|strict|full-coverage" apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md .github/agents/change-risk-triage.agent.md .github/agents/plan-kernel.agent.md`; manual check that `strict` appears only as an explicit non-option. |
| Dependencies | SL-001 |
| Completion criteria | Direct flow can classify lite / standard without asking the user; full-coverage remains an advanced route. |
| Rollback | Revert the three target files. Later slices depending on `documentation_level` must be reverted first. |

### SL-003: Codex-first Documentation Level Selection

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`; `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md`; `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md`; `apm-packages/codex-first-ai-development-process/templates/stop-report.md` |
| Implementation content | Add `documentation_level` as a router-owned field derived from task weight and risk. Define rules for `trivial-local`, `small-bounded`, `medium-bounded`, `high-risk-bounded`, `needs-plan-behavior-expansion`, `broad-full-coverage-candidate`, and `blocked-human-required`. Keep user choice disabled. Add state / stop-report fields for `documentation_level` without changing `selected_process`. |
| Verification method | `rg -n "documentation_level|lite|standard|selected_process|advanced-full-coverage|strict" apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md apm-packages/codex-first-ai-development-process/templates`; manual check that `strict` is not an enum value. |
| Dependencies | SL-002 |
| Completion criteria | Codex-first records `documentation_level` automatically and keeps `full-coverage` under selected process / route semantics. |
| Rollback | Revert the router skill, instruction, and template changes. |

### SL-004: Plan Coverage Lite Artifact Template

| Field | Plan |
| --- | --- |
| Target files | New `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`; `.github/agents/plan-kernel.agent.md` |
| Implementation content | Define the standard Plan Coverage Lite structure: Source of truth, Plan summary, FR / AC, Inline behavior sketch, Risk checklist, Inline Ready Gate, Implementation Self-Map, Verification Summary, and Residual / Close Decision. Require FR / AC coverage and residual / human-decision classification even in lite. Clarify that lite combines artifacts; it does not remove guardrails. |
| Verification method | `rg -n "Plan Coverage Lite|Source of truth|FR / AC|Inline behavior sketch|Inline Ready Gate|Implementation Self-Map|Residual / Close Decision" apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; inspect skill / plan-kernel references. |
| Dependencies | SL-002 |
| Completion criteria | Lite artifact is documented or templated and includes all required sections from Issue #38. |
| Rollback | Remove the template and revert references in the skill / plan kernel. |

### SL-005: Inline Ready Gate Equivalence

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/implementation-handoff-review.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` |
| Implementation content | Define when `Inline Ready Gate` is explicitly equivalent to `implementation-handoff-review`: Plan readiness, expansion required, Case-to-Plan mapping, risk checklist, parent coverage, and implementation allowed must be complete. State that lite normally does not create a separate `plans/<slug>-implementation-handoff-review.md`; standard may choose inline or separate gate depending on risk. |
| Verification method | `rg -n "Inline Ready Gate|implementation-handoff-review 相当|Implementation allowed|Parent Plan coverage|Expansion required" .github/agents/implementation-handoff-review.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md` |
| Dependencies | SL-004 |
| Completion criteria | Inline gate equivalence is precise enough for implementation permission and fail-closed when incomplete. |
| Rollback | Revert the three target files. Lite template remains but no longer authorizes implementation inline. |

### SL-006: Inline Behavior Sketch and Escalation

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/plan-kernel.agent.md`; `.github/agents/black-box-behavior-spec-kernel.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/plan-coverage-lite.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Implementation content | Add the two-stage Behavior Spec rule: lite / standard first record an inline behavior sketch, then escalate to `plans/<slug>-black-box-behavior-spec.md` only when case count, negative expectations, recovery / rollback / retry / replay / cleanup, durable state, idempotency, mapping risk, human decision, or standard / full-coverage escalation requires it. Preserve existing Plan readiness failure behavior. |
| Verification method | `rg -n "Inline behavior sketch|Black-box Behavior Spec|escalation|negative expectation|rollback|retry|idempotency|NeedsPlanBehaviorExpansion" .github/agents/plan-kernel.agent.md .github/agents/black-box-behavior-spec-kernel.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm` |
| Dependencies | SL-004 |
| Completion criteria | Inline sketch is accepted for simple cases, and separate Behavior Spec escalation conditions are explicit. |
| Rollback | Revert target files. Existing behavior spec kernel remains usable. |

### SL-007: Canonical Coverage Ledger and Delta Updates

| Field | Plan |
| --- | --- |
| Target files | New `apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/coverage-ledger.md`; `.github/agents/implementation-handoff-review.agent.md`; `.github/agents/verification-kernel.agent.md`; `.github/agents/residual-decision-gate.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Implementation content | Define `plans/<slug>-coverage-ledger.md` as the canonical ledger and `Coverage Ledger Delta` as the update format for intermediate gates. Preserve the rule that all FR / AC rows remain classified and that close / residual decision may produce a full completion view. Update handoff / verification / residual agents to read canonical ledger plus relevant deltas. |
| Verification method | `rg -n "coverage-ledger|Coverage Ledger Delta|canonical ledger|full completion view|Parent Plan Coverage Ledger" apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/coverage-ledger.md .github/agents/implementation-handoff-review.agent.md .github/agents/verification-kernel.agent.md .github/agents/residual-decision-gate.agent.md` |
| Dependencies | SL-005 |
| Completion criteria | Standard route can avoid repeated full ledger copies without hiding unclassified FR / AC rows. |
| Rollback | Remove ledger template and revert agent / skill references. Existing full ledger behavior resumes. |

### SL-008: Conditional Coverage Gap Triage and Direct FixNow

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/verification-kernel.agent.md`; `.github/agents/coverage-gap-triage.agent.md`; `.github/agents/residual-decision-gate.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Implementation content | Add conditions for skipping `coverage-gap-triage` when a gap is 1-2 items, gap type and target file / address are clear, no human decision / manual verification / Plan ambiguity / Behavior Case residual exists, and a bounded fix pass is safe. Let verification / residual gate emit a direct FixNow selector for simple gaps. Keep complex / ambiguous gaps routed to `coverage-gap-triage`. |
| Verification method | `rg -n "direct FixNow|coverage-gap-triage|simple gap|PlanAmbiguity|UnmappedParentAcceptance|BehaviorCaseWithoutEvidence|ManualVerificationRequired" .github/agents/verification-kernel.agent.md .github/agents/coverage-gap-triage.agent.md .github/agents/residual-decision-gate.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md` |
| Dependencies | SL-007 |
| Completion criteria | Simple gaps can go directly to FixNow; complex gaps still require triage. |
| Rollback | Revert target files. All unresolved items again route through coverage-gap-triage. |

### SL-009: Unified Implementation Contract Self-check

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/implementation-contract-kernel.agent.md` |
| Implementation content | Add `Self-check / Readiness verdict` to the required output structure. Use the Issue #38 verdict vocabulary: `READY_FOR_RUNTIME_CONTRACT`, `READY_FOR_IMPLEMENTATION`, `BLOCKED_BY_DEPENDENCY_MISSING`, `BLOCKED_BY_API_SURFACE_UNKNOWN`, `BLOCKED_BY_UNJUSTIFIED_SUBSTITUTION`, `BLOCKED_BY_SOURCE_OF_TRUTH_DRIFT`, `NEEDS_HUMAN_DECISION`. Keep no-code / no-test policy. |
| Verification method | `rg -n "Self-check / Readiness verdict|READY_FOR_RUNTIME_CONTRACT|READY_FOR_IMPLEMENTATION|BLOCKED_BY_DEPENDENCY_MISSING|BLOCKED_BY_API_SURFACE_UNKNOWN|BLOCKED_BY_UNJUSTIFIED_SUBSTITUTION|BLOCKED_BY_SOURCE_OF_TRUTH_DRIFT|NEEDS_HUMAN_DECISION" .github/agents/implementation-contract-kernel.agent.md` |
| Dependencies | SL-001 |
| Completion criteria | Implementation contract can create contract and readiness verdict in one artifact. |
| Rollback | Revert `implementation-contract-kernel.agent.md`. Separate review kernel remains unchanged. |

### SL-010: Review Kernel Compatibility Shim

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/implementation-contract-review-kernel.agent.md`; `apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md`; `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`; `README.md`; `docs/token-aware-guardrail-kernel-process-and-agents.md` |
| Implementation content | Decide and document the compatibility behavior for the old review kernel. Recommended path: keep the file as a deprecated compatibility shim / explicit review-only mode that validates the unified implementation-contract self-check when requested. Update references so new normal flow uses the unified contract artifact while existing references do not break. |
| Verification method | `rg -n "implementation-contract-review-kernel|deprecated|compatibility|review-only mode|implementation-contract-kernel" .github/agents/implementation-contract-review-kernel.agent.md apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md README.md docs/token-aware-guardrail-kernel-process-and-agents.md` |
| Dependencies | SL-009 |
| Completion criteria | Existing references remain valid, and the normal path no longer requires two thin adjacent artifacts. |
| Rollback | Revert all target files. The old two-step contract review flow resumes. |

### SL-011: Shared Instruction Migration for Pre-implementation Agents

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/plan-kernel.agent.md`; `.github/agents/black-box-behavior-spec-kernel.agent.md`; `.github/agents/change-risk-triage.agent.md`; `.github/agents/implementation-contract-kernel.agent.md`; `.github/agents/runtime-contract-kernel.agent.md`; `.github/agents/test-design-kernel.agent.md`; `.github/agents/implementation-handoff-review.agent.md` |
| Implementation content | Replace duplicated embedded policy / status vocabulary / common Handoff Packet boilerplate in pre-implementation agents with references to `.github/instructions/plan-coverage-shared.instructions.md`. Keep agent-specific responsibilities, required inputs, output paths, required output sections, allowed verdict vocabulary, stop conditions, and agent-specific must-not-do sections inside each agent. |
| Verification method | `rg -n "plan-coverage-shared.instructions.md|Allowed verdict|output path|Stop condition|Must not do" .github/agents/plan-kernel.agent.md .github/agents/black-box-behavior-spec-kernel.agent.md .github/agents/change-risk-triage.agent.md .github/agents/implementation-contract-kernel.agent.md .github/agents/runtime-contract-kernel.agent.md .github/agents/test-design-kernel.agent.md .github/agents/implementation-handoff-review.agent.md`; manual review for lost verdicts. |
| Dependencies | SL-001, SL-009, SL-010 |
| Completion criteria | Boilerplate is reduced without losing each agent's local verdicts and stop rules. |
| Rollback | Revert the listed agent files. The shared instruction file may remain unused. |

### SL-012: Shared Instruction Migration for Post-implementation Agents

| Field | Plan |
| --- | --- |
| Target files | `.github/agents/verification-kernel.agent.md`; `.github/agents/coverage-gap-triage.agent.md`; `.github/agents/residual-decision-gate.agent.md`; `.github/agents/cross-slice-verification-kernel.agent.md`; `.github/agents/coverage-gap-resolution-slice.agent.md` |
| Implementation content | Move common status vocabulary and Handoff Packet boilerplate for post-implementation / close agents to the shared instruction reference. Keep production-binding verification rules, gap type precedence, residual verdict vocabulary, output path, and close-blocking logic in the owning agents. |
| Verification method | `rg -n "plan-coverage-shared.instructions.md|PARENT_PLAN_VERIFIED|READY_TO_CLOSE|Gap type|FixNow|Residual Decision|Stop condition" .github/agents/verification-kernel.agent.md .github/agents/coverage-gap-triage.agent.md .github/agents/residual-decision-gate.agent.md .github/agents/cross-slice-verification-kernel.agent.md .github/agents/coverage-gap-resolution-slice.agent.md`; manual review for lost production-binding / residual rules. |
| Dependencies | SL-001, SL-007, SL-008 |
| Completion criteria | Common policy duplication is reduced, while post-implementation fail-closed semantics remain local and explicit. |
| Rollback | Revert the listed agent files. |

### SL-013: Codex-first Core / Audit State Split

| Field | Plan |
| --- | --- |
| Target files | `apm-packages/codex-first-ai-development-process/templates/codex-first-state.md`; new `apm-packages/codex-first-ai-development-process/templates/codex-first-audit.md`; `apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md`; `apm-packages/codex-first-ai-development-process/.apm/instructions/codex-first-ai-development-process.instructions.md`; `apm-packages/codex-first-ai-development-process/templates/stop-report.md`; `apm-packages/codex-first-ai-development-process/docs/codex-first-ai-development-process.md`; `apm-packages/codex-first-ai-development-process/docs/user-guide.md`; `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md` |
| Implementation content | Keep `plans/<slug>/codex-first-state.md` as the resume core with task slug, source of truth, documentation level, selected process, current/next gate, plan readiness, risk artifact status, edit permission, stop reason, human-required items, unresolved residuals, next action, and last updated summary. Move full Agent Usage Ledger, observed runs, configured / hook / reported / effective model details, delegation compliance detail, and historical routing detail to `plans/<slug>/codex-first-audit.md`. Update router rules to read audit only when needed. The existing installer copies all Markdown templates, so no installer logic change is required unless implementation adds non-`.md` assets. |
| Verification method | `rg -n "codex-first-audit|documentation_level|Agent Usage Ledger|Observed runs|configured_model|hook_model|reported_model|effective_model" apm-packages/codex-first-ai-development-process/templates apm-packages/codex-first-ai-development-process/.apm apm-packages/codex-first-ai-development-process/docs`; run `dotnet run --file apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs -- . --dry-run` if the environment has a compatible .NET SDK. |
| Dependencies | SL-003 |
| Completion criteria | Core resume state is smaller, audit remains available, and docs / templates explain when to read each file. |
| Rollback | Delete `codex-first-audit.md` template and revert router / docs / state template to combined state. |

### SL-014: Validation Samples VAL-001 to VAL-010

| Field | Plan |
| --- | --- |
| Target files | New `apm-packages/codex-first-ai-development-process/docs/examples/lite-standard-validation.md`; optionally update `apm-packages/codex-first-ai-development-process/docs/examples/routing-mvp-validation.md` with a pointer |
| Implementation content | Add validation samples for VAL-001 through VAL-010: trivial-local, small-bounded-lite, medium-standard, high-risk-standard, behavior-expansion-standard, full-coverage-candidate, resume-with-core-state, simple-gap-direct-fixnow, complex-gap-triage, and unified-implementation-contract. Include expected artifact count / sections read comparison so lite route reduction is observable. |
| Verification method | `rg -n "VAL-001|VAL-002|VAL-003|VAL-004|VAL-005|VAL-006|VAL-007|VAL-008|VAL-009|VAL-010|artifact count|sections read" apm-packages/codex-first-ai-development-process/docs/examples/lite-standard-validation.md` |
| Dependencies | SL-004 through SL-013 |
| Completion criteria | All ten validation samples exist and cover both lightweight effect and guardrail preservation. |
| Rollback | Remove the new validation file and pointer. |

### SL-015: Final Documentation Consistency

| Field | Plan |
| --- | --- |
| Target files | `README.md`; `docs/token-aware-guardrail-kernel-process-and-agents.md`; `apm-packages/codex-first-ai-development-process/docs/user-guide.md`; `apm-packages/codex-first-ai-development-process/docs/maintainer-guide.md`; `apm-packages/codex-first-ai-development-process/docs/codex-first-ai-development-process.md`; `apm-packages/codex-first-ai-development-process/docs/bootstrap-and-merge-policy.md` if state/template install behavior changes |
| Implementation content | Update user-facing and maintainer docs after all behavior changes are implemented. Explain lite / standard, no strict, full-coverage as route, Lite artifact, Inline Ready Gate, Behavior Spec escalation, ledger delta, conditional gap triage, unified implementation contract, common instruction ownership, core/audit state, and validation samples. Keep novice docs clear that users do not select process / agent / model / documentation level. |
| Verification method | `rg -n "documentation_level|lite|standard|strict|full-coverage|Inline Ready Gate|Coverage Ledger Delta|codex-first-audit|VAL-010" README.md docs/token-aware-guardrail-kernel-process-and-agents.md apm-packages/codex-first-ai-development-process/docs`; inspect that `strict` is documented only as non-option. |
| Dependencies | All prior slices |
| Completion criteria | Public docs and package docs describe the implemented behavior consistently. |
| Rollback | Revert docs only. Core implementation remains but public guidance returns to previous wording. |

## FR Traceability Matrix

| FR | Requirement summary | Satisfying slice(s) |
| --- | --- | --- |
| FR-001 | Introduce `documentation_level: lite / standard` to router / skill / docs | SL-002, SL-003, SL-015 |
| FR-002 | Do not add `strict` as a choice | SL-002, SL-003, SL-015 |
| FR-003 | Keep `full-coverage` as route, not documentation level | SL-002, SL-003, SL-015 |
| FR-004 | Define Plan Coverage Lite artifact format | SL-004 |
| FR-005 | Require source of truth, FR / AC coverage, and residual classification in lite | SL-004, SL-005 |
| FR-006 | Define Inline Ready Gate as implementation-handoff-review alternative | SL-005 |
| FR-007 | Make Behavior Spec inline sketch then separate artifact escalation | SL-006 |
| FR-008 | Introduce canonical coverage ledger plus delta updates | SL-007 |
| FR-009 | Define coverage-gap-triage trigger conditions | SL-008 |
| FR-010 | Allow direct FixNow selector for simple gaps | SL-008 |
| FR-011 | Merge implementation-contract-kernel and review-kernel responsibilities | SL-009, SL-010 |
| FR-012 | Add self-check verdict to unified implementation-contract | SL-009 |
| FR-013 | Decide compatibility behavior for old review kernel | SL-010 |
| FR-014 | Bundle common instruction file with agents | SL-001 |
| FR-015 | Move duplicate boilerplate from agents to common instruction references | SL-011, SL-012 |
| FR-016 | Keep agent-specific verdict vocabulary / stop condition in agent files | SL-001, SL-011, SL-012 |
| FR-017 | Split codex-first-state into core and audit | SL-013 |
| FR-018 | Add validation samples | SL-014 |

## AC Coverage Matrix

| AC | Acceptance criteria summary | Satisfying slice(s) | Validation evidence |
| --- | --- | --- | --- |
| AC-001 | `documentation_level` values are only `lite` / `standard`; no `strict` | SL-002, SL-003, SL-015 | `rg` enum / wording scan |
| AC-002 | Router / skill auto-select lite / standard by task weight and risk | SL-002, SL-003, SL-014 | Router sample VAL-001 to VAL-006 |
| AC-003 | `full-coverage` is selected_process / route, not documentation level | SL-002, SL-003, SL-015 | `rg` and docs review |
| AC-004 | Lite route standard structure is documented / templated | SL-004 | Lite template section scan |
| AC-005 | Lite keeps Plan source of truth, FR / AC coverage, residual / human decision classification | SL-004, SL-005, SL-014 | Lite template and VAL-002 |
| AC-006 | Inline Ready Gate equivalence conditions are documented | SL-005 | Inline gate table scan |
| AC-007 | Inline behavior sketch vs separate Behavior Spec escalation conditions are documented | SL-006 | Behavior escalation scan |
| AC-008 | Canonical coverage ledger, delta format, reading rules, close behavior are documented | SL-007 | Ledger template and agent references |
| AC-009 | coverage-gap-triage run / skip conditions are documented | SL-008 | Gap triage condition scan |
| AC-010 | Simple gaps can emit direct FixNow selector | SL-008 | VAL-008 and agent wording |
| AC-011 | `implementation-contract-kernel.agent.md` can output contract plus self-check verdict | SL-009 | Required output structure scan |
| AC-012 | Unified implementation-contract verdict vocabulary is defined | SL-009 | Verdict vocabulary scan |
| AC-013 | Review-kernel handling is deprecated alias / shim / removed without breaking references | SL-010 | Review-kernel and reference scan |
| AC-014 | Common instruction file is bundled with agents without docs runtime dependency | SL-001 | Manifest dependency scan |
| AC-015 | Embedded policy / status vocabulary / Handoff Packet boilerplate duplication is reduced | SL-011, SL-012 | Agent diff review and shared reference scan |
| AC-016 | Agent-specific verdict vocabulary / output path / stop condition stay in agents | SL-011, SL-012 | Manual review of agent-specific sections |
| AC-017 | codex-first-state core / audit split is reflected in template / docs / skill | SL-013 | Template and docs scan |
| AC-018 | VAL-001 to VAL-010 are added or reflected in validation suite | SL-014 | Validation ID scan |
| AC-019 | Validation shows lite reads / creates fewer artifacts or sections than current standard | SL-014 | VAL-002 artifact count / section count |
| AC-020 | Source-of-truth, no fake-only completion, residual explicit decision invariants remain | SL-001, SL-004, SL-007, SL-012, SL-015 | Shared instruction and docs scan |

## User Requirement Traceability

| UR | Requirement summary | Satisfying slice(s) |
| --- | --- | --- |
| UR-001 | Prevent missing implementation pieces and disconnected elements | SL-004, SL-005, SL-007, SL-009, SL-012 |
| UR-002 | Prevent excess autonomous token use | SL-002, SL-003, SL-004, SL-008, SL-013 |
| UR-003 | Continue across AI / thread boundaries from docs | SL-001, SL-004, SL-007, SL-013 |
| UR-004 | Keep Plan as source of truth through the flow | SL-001, SL-004, SL-007, SL-012, SL-015 |
| UR-005 | Confirm production implementation beyond stub tests | SL-001, SL-009, SL-012 |
| UR-006 | Make residuals individually decidable | SL-004, SL-007, SL-008, SL-012 |
| UR-007 | Support delegation to other AI / lower-cost models | SL-003, SL-013, SL-014 |
| UR-008 | Reduce excessive artifacts / token use | SL-004, SL-007, SL-008, SL-013 |
| UR-009 | Use two levels: lite / standard | SL-002, SL-003, SL-015 |
| UR-010 | Do not create strict | SL-002, SL-003, SL-015 |
| UR-011 | Avoid conflict between full-coverage and level classification | SL-002, SL-003, SL-015 |
| UR-012 | Merge thin adjacent kernels | SL-009, SL-010 |
| UR-013 | Move shared boilerplate to bundled common instruction | SL-001, SL-011, SL-012 |

## NFR Traceability

| NFR | Requirement summary | Satisfying slice(s) |
| --- | --- | --- |
| NFR-001 | Token-aware: reduce read / generated artifacts for light tasks | SL-004, SL-007, SL-008, SL-013, SL-014 |
| NFR-002 | Traceable: FR / AC / Behavior Case / residual remain trackable | SL-004, SL-006, SL-007, SL-012 |
| NFR-003 | Portable: no consuming repo `docs/` runtime dependency | SL-001, SL-011, SL-012 |
| NFR-004 | Fail-closed on readiness / human decision / residual issues | SL-005, SL-006, SL-008, SL-012, SL-013 |
| NFR-005 | Backward-compatible migration | SL-010, SL-013, SL-015 |
| NFR-006 | Maintainable: reduce policy / vocabulary duplication | SL-001, SL-011, SL-012 |
| NFR-007 | Not over-routed: separate full-coverage / standard / lite responsibilities | SL-002, SL-003, SL-015 |

## Decision Traceability

| Decision | Summary | Satisfying slice(s) |
| --- | --- | --- |
| DEC-001 | documentation level is lite / standard only | SL-002, SL-003, SL-015 |
| DEC-002 | full-coverage is route, not documentation level | SL-002, SL-003, SL-015 |
| DEC-003 | Add lite route | SL-004, SL-005, SL-006 |
| DEC-004 | Compress standard route while preserving guardrails | SL-007, SL-008, SL-009, SL-010, SL-011, SL-012 |
| DEC-005 | Inline Ready Gate can replace independent handoff review | SL-005 |
| DEC-006 | Behavior Spec is inline sketch then separate artifact | SL-006 |
| DEC-007 | Canonical coverage ledger plus delta | SL-007 |
| DEC-008 | coverage-gap-triage is conditional | SL-008 |
| DEC-009 | Merge implementation contract and review kernel | SL-009, SL-010 |
| DEC-010 | Extract common boilerplate to bundled instruction | SL-001, SL-011, SL-012 |
| DEC-011 | Split state into core and audit | SL-013 |
| DEC-012 | Add validation samples | SL-014 |

## Rollback Policy

1. Implement each slice as a separate commit or separately reviewable PR section.
2. Roll back in reverse dependency order. For example, revert SL-012 before SL-001 if agents already reference the shared instruction.
3. Avoid removing compatibility shims before all references are updated. SL-010 should be the last place to remove old review-kernel behavior, if removal is ever chosen.
4. For documentation-only slices, rollback is file-level revert.
5. For template / installer slices, run dry-run / check-only validation after rollback to confirm target repo bootstrap behavior is still coherent.
6. If a late slice exposes a design problem in an earlier slice, create a corrective slice instead of editing unrelated responsibilities in place.

## Final Verification Plan

Run these checks after the last implementation slice:

```powershell
git diff --check
rg -n "FR-00[1-9]|FR-01[0-8]|AC-00[1-9]|AC-01[0-9]|AC-020" plans/issue-38-lite-standard-implementation-plan.md
rg -n "documentation_level|lite|standard|strict|full-coverage" README.md docs apm-packages .github
rg -n "VAL-001|VAL-002|VAL-003|VAL-004|VAL-005|VAL-006|VAL-007|VAL-008|VAL-009|VAL-010" apm-packages/codex-first-ai-development-process/docs/examples
dotnet run --file apm-packages/codex-first-ai-development-process/scripts/install-codex-first-local.cs -- . --dry-run
dotnet run --file scripts/setup-work-repo-agents.cs -- . --dry-run
```

If the local environment lacks a compatible .NET SDK, record that as unverified with the exact error and keep the `rg` / `git diff --check` evidence.

