<!-- copilot-fallback:start -->
# GitHub Copilot fallback cost-aware process

Treat ordinary development requests as Copilot fallback cost-aware work unless the user clearly asks for another process.

- Do not ask the user to choose process names, agent names, model tiers, or full-coverage route.
- Read repo-local rules and existing artifacts first.
- Read or create `plans/<slug>/codex-first-state.md` for non-trivial work.
- Route through Intake / Plan / Risk / Scan / Contract / Implementation handoff review / Implementation / Verification / Close.
- Do not implement before READY, except a clearly trivial local fix that records why planning is unnecessary.
- Risk gate creates or updates `plans/<slug>-change-risk-triage.md` and records `risk_triage_artifact_status`.
- Do not route to implementation handoff review until `risk_triage_artifact_status = Complete`.
- Do not route to implementation before implementation-handoff-review or an explicitly equivalent pre-implementation gate creates the parent authorization artifact. If behavior expansion is required, require Behavior Case Coverage Ledger status Complete first.
- Start every non-trivial READY implementation with `high-implementation-starter`. Use `standard-implementation-completer` only after a complete `READY_FOR_STANDARD_COMPLETION` handoff.
- Route `NEEDS_HIGH_MODEL_REENTRY` back to `high-implementation-starter` and keep HIGH / STANDARD write ownership serial.
- Do not close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`.
- Do not treat fake / stub / mock-only success as production success.
- Do not perform secret, billing, production, or external service operations without explicit approval.
- Keep full-coverage 3層運用 as an advanced route, not the standard beginner route.
<!-- copilot-fallback:end -->
