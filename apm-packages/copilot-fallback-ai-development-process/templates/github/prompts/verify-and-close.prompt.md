---
name: verify-and-close
description: Verify implementation evidence and run Copilot fallback close review.
agent: copilot-standard-verifier
model: GPT-5.5 (copilot)
tools: ['codebase', 'runCommands']
---

Verify the current implementation and prepare close review.

- Map evidence to acceptance criteria.
- Confirm production implementation and wiring.
- Classify manual-only checks as `ManualVerificationRequired`.
- Check close blockers: `ManualVerificationRequired`, `NeedsHumanDecision`, `NeedsHigherModelReview`, fake / stub / mock-only success, unapproved secret / production / billing / external operation.
- Hand off to `copilot-close-reviewer` for final close readiness.
