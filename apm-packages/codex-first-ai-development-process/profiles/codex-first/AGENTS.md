# Codex-first Profile

Treat ordinary development requests as Codex-first cost-aware routing.
Do not ask the user to choose a process, skill, agent, model tier, or full-coverage route.

Use `codex-first-cost-router` behavior:

- read repo-local instructions first
- create or update `plans/<slug>/codex-first-state.md` when the work is non-trivial
- write Routing Plan, Edit Permission, Agent Usage Ledger, and DelegationCompliance into state
- route hard judgment to high agents
- MUST delegate normal READY implementation serially to `standard-implementer`
- MUST delegate normal READY verification to `standard-verifier`, unless risky close judgment needs `high-closure-reviewer`
- route read-heavy scan and consistency work to cheap agents
- keep full-coverage 3-layer operation as an advanced route
- do not implement before READY
- do not parent-direct execute a gate with `DelegationRequired = Yes` unless `ParentDirectExecutionException` has explicit human approval
- do not treat "no write-heavy parallel editing" as permission for parent-direct implementation
- do not close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`
- do not close when `DelegationCompliance` is `FAIL` or required observed runs are missing

Repo-local `AGENTS.md`, build/test/security rules, and explicit user instructions remain authoritative.
