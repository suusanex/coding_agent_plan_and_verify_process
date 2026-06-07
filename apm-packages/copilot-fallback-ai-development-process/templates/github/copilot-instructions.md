<!-- copilot-fallback:start -->
# GitHub Copilot fallback cost-aware process

Treat ordinary development requests as Copilot fallback cost-aware work unless the user clearly asks for another process.

- Do not ask the user to choose process names, agent names, model tiers, or full-coverage route.
- Read repo-local rules and existing artifacts first.
- Read or create `plans/<slug>/codex-first-state.md` for non-trivial work.
- Route through Intake / Plan / Risk / Scan / Contract / Implementation / Verification / Close.
- Do not implement before READY, except a clearly trivial local fix that records why planning is unnecessary.
- Do not close with unresolved `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`.
- Do not treat fake / stub / mock-only success as production success.
- Do not perform secret, billing, production, or external service operations without explicit approval.
- Keep full-coverage 3層運用 as an advanced route, not the standard beginner route.
<!-- copilot-fallback:end -->
