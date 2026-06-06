# codex-full-coverage-3layer

Use this skill when `change-risk-triage.agent.md` recommends `full-coverage`, or when the requested change is too broad, ambiguous, or cross-slice connected for one bounded pass.

## Purpose

This skill turns full-coverage from "do everything in one enormous run" into a three-layer Codex operation:

1. Parent orchestration
2. Slice preparation
3. Slice implementation

## Workflow

1. Treat the parent Plan as source of truth.
2. Run `plan-slice-decomposition.agent.md`.
3. For each slice, produce a slice artifact with scope, non-goals, dependencies, parent acceptance condition mapping, and cross-slice contracts.
4. Run each implementation slice through the token-aware kernel flow.
5. Do not mark parent acceptance conditions complete inside a single slice when cross-slice evidence is required.
6. After slice work, run `cross-slice-verification-kernel.agent.md`.
7. Use residual decision logic to classify remaining work as FixNow, Deferred, ManualVerificationRequired, NeedsHumanDecision, or NeedsHigherModelReview.

## Rules

- Do not jump from `full-coverage` directly to broad implementation.
- Do not collapse parent, slice-prep, and slice-impl into one unbounded pass.
- Do not hide cross-slice contracts inside a slice-local completion note.
- Do not spend high-cost model time on routine slice implementation once the slice contract is clear.

## Output

Return:

- parent Plan reference
- slice list
- cross-slice contract list
- per-slice next agent
- residual decision summary
- manual or higher-model review needs
