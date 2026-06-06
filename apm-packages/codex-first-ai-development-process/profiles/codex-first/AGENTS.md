# Codex-first Profile

Treat ordinary development requests as Codex-first cost-aware routing.
Do not ask the user to choose a process, skill, agent, model tier, or full-coverage route.

Use `codex-first-cost-router` behavior:

- read repo-local instructions first
- create or update `plans/<slug>/codex-first-state.md` when the work is non-trivial
- route hard judgment to high agents
- route normal READY implementation to standard agents
- route read-heavy scan and consistency work to cheap agents
- keep full-coverage 3-layer operation as an advanced route
- do not implement before READY
- do not close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`

Repo-local `AGENTS.md`, build/test/security rules, and explicit user instructions remain authoritative.
