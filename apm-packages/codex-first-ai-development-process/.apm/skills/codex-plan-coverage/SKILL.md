# codex-plan-coverage

Use this skill when a user asks Codex to start or continue normal development work and wants the Codex-first process to keep Plan coverage, READY gating, implementation, verification, and residual work explicit.

## Workflow

1. Read the user's request, issue body, or supplied artifact as the source of truth.
2. Create or consume a bounded Plan using `plan-kernel.agent.md`.
3. Run `change-risk-triage.agent.md` against the Plan.
4. If implementation-realization risk is `Present` or `Unclear`, create `implementation-contract-kernel` and review it when non-trivial.
5. Create the selected `runtime-contract-kernel` and `test-design-kernel` artifacts.
6. Run `implementation-handoff-review.agent.md` unless the change is clearly trivial and has no production binding risk.
7. Implement only after the handoff is `READY_FOR_IMPLEMENTATION` or `READY_WITH_NOTES`.
8. Verify with `verification-kernel.agent.md`.
9. If gaps remain, run `coverage-gap-triage.agent.md` and fix only selected gaps with `coverage-gap-resolution-slice.agent.md`.

## Rules

- Do not implement before a bounded Plan exists.
- Do not use runtime-contract artifacts as the whole implementation spec.
- Do not treat fake, stub, mock, or in-memory success as production readiness.
- Do not close if `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview` remains.
- Record residual work instead of looping until everything looks green.

## Output

Return a concise result with:

- source artifacts used
- gates executed
- implementation scope
- verification result
- residual work
- whether closure is safe
