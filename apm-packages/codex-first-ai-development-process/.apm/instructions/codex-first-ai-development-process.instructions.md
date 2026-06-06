# Codex-first AI Development Process Instructions

Use this instruction set when the user wants ordinary issue work to pass through a Codex-first, Plan-first, gate-driven process without requiring them to manually choose every agent.

## Entry behavior

- Treat short requests such as "この issue を進めて" as a request to start with Plan creation, not immediate implementation.
- Keep the user-facing entry small, but keep internal gates explicit.
- Use Codex as the primary execution environment.
- Use GitHub Copilot only as a fallback route documented in the final artifact or maintainer notes.

## Required gates

1. Plan gate: create or consume a bounded Plan.
2. Risk gate: classify whether the work is standard, selected-contract, implementation-realization, fix-slice, or full-coverage.
3. READY gate: confirm Plan, selected scope, non-goals, contract/test handoff, and unresolved implementation-realization items before implementation.
4. Implementation gate: implement only the selected scope.
5. Verification gate: classify production implementation, production wiring, and manual-only checks.
6. Close gate: do not close when unresolved items include `ManualVerificationRequired`, `NeedsHumanDecision`, or `NeedsHigherModelReview`.

## Stop vocabulary

- `Blocked`
- `NeedsHumanDecision`
- `ManualVerificationRequired`
- `NeedsHigherModelReview`
- `NeedsExternalOperation`
- `NeedsSecretInput`
- `ReadyForImplementation`
- `ReadyForVerification`
- `ResidualWorkRecorded`

## Cost-aware model routing

- Use `HIGH_MODEL` for Plan quality, ambiguous risk triage, full-coverage parent work, and final closure decisions.
- Use `STANDARD_MODEL` for bounded implementation and verification when the contract is already clear.
- Use `CHEAP_MODEL` for formatting, artifact consistency checks, and simple read-only reviews.

Do not hard-code model names here. The consuming organization owns the mapping from labels to actual model names.
