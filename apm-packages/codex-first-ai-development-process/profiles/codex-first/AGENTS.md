# Codex-first Profile

Treat ordinary development requests as Codex-first cost-aware routing.
Do not ask the user to choose a process, skill, agent, model tier, or full-coverage route.

Use `codex-first-cost-router` behavior:

- read repo-local instructions first
- create or update `plans/<slug>/codex-first-state.md` when the work is non-trivial
- write Routing Plan, Edit Permission, Agent Usage Ledger, and DelegationCompliance into state
- record execution_mode and keep model tier, configured model, hook model, reported model, and effective model separate
- record behavior expansion decision, Case-to-Plan mapping, and Plan readiness before risk / implementation
- route `NeedsPlanBehaviorExpansion` to `black-box-behavior-spec-kernel` or a Plan rerun, not to full-coverage or fix-slice
- create or update `plans/<slug>-change-risk-triage.md` during Risk gate and record `risk_triage_artifact_status`
- do not run `implementation-handoff-review` until the change-risk-triage artifact is complete
- run `implementation-handoff-review` or an explicitly equivalent pre-implementation gate before normal READY implementation
- default implementation routing to `adaptive / default`; use `design-pair / explicit-user-selection` only when the user explicitly selected it, never from task weight, risk, size, or architecture
- when explicitly selected, run `design-pair-implementation-execution` after implementation authorization and before `high-implementation-starter`; allow only the tracked Design Pair handoff write until `READY_FOR_ADAPTIVE_IMPLEMENTATION`
- for `documentation_level: lite`, treat the Plan Coverage Lite Inline Ready Gate as equivalent to `implementation-handoff-review` only when it is explicitly PASS and covers source of truth, FR / AC coverage, Case-to-Plan mapping, risk checklist, implementation scope, human decisions, required Behavior Case Coverage Ledger, and implementation allowed
- when `Expansion required: Yes`, require `Behavior Case Coverage Ledger` status `Complete` before handing off to `high-implementation-starter`
- route hard judgment to high agents
- MUST delegate non-trivial READY implementation serially to `high-implementation-starter`
- use `standard-implementation-completer` only after a valid `READY_FOR_STANDARD_COMPLETION` handoff and return to HIGH_MODEL on `NEEDS_HIGH_MODEL_REENTRY`
- keep HIGH_MODEL and STANDARD_MODEL write ownership serial and record the owner/verdict sequence in state and audit
- update `shape_handoff_status`, `remaining_design_uncertainty`, `completion_scope`, `shape_reentry_reason`, and the active verdict / agent / tier / edit owner at every implementation phase boundary
- MUST delegate normal READY verification to `standard-verifier`, unless risky close judgment needs `high-closure-reviewer`
- route read-heavy scan and consistency work to cheap agents
- keep full-coverage 3-layer operation as an advanced route
- do not implement before READY
- do not parent-direct execute a gate with `DelegationRequired = Yes` unless `ParentDirectExecutionException` has explicit human approval
- do not count parent-direct work or trivial parent fixes as cost-saving delegation
- do not treat "no write-heavy parallel editing" as permission for parent-direct implementation
- do not close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`
- do not close when `DelegationCompliance` is `FAIL` or required observed runs are missing

Repo-local `AGENTS.md`, build/test/security rules, and explicit user instructions remain authoritative.
