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
- run `implementation-handoff-review` or an explicitly equivalent pre-implementation gate before normal READY implementation
- when `Expansion required: Yes`, require `Behavior Case Coverage Ledger` status `Complete` before handing off to `standard-implementer`
- route hard judgment to high agents
- MUST delegate normal READY implementation serially to `standard-implementer`
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
