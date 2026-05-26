# Token-aware full-coverage decomposition flow

## Purpose

`full-coverage` 判定を、Full autonomous Plan-first flow へのエスカレーションではなく、実装前の Plan slice decomposition として扱うための運用メモです。

## Policy

- `full-coverage` means: the parent Plan is too broad / ambiguous / strongly interconnected to implement as one bounded pass.
- `full-coverage` does not mean: run `plan-generation.agent.md`, `runtime-evidence.agent.md`, or `integration-test-design.agent.md`.
- The next step is always `plan-slice-decomposition.agent.md`.
- Each resulting slice re-enters the token-aware kernel flow.
- Cross-slice contracts must remain explicit and must be verified after slice implementations.

## Minimal chain

```text
Parent Plan Kernel
→ Change Risk Triage
→ Plan Slice Decomposition
→ Per-slice token-aware flow
→ Cross-Slice Verification Kernel
→ Gap triage / selected slice repair when needed
```
