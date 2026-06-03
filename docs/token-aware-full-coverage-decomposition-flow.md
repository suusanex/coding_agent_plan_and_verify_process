# Token-aware full-coverage decomposition flow

## Purpose

`full-coverage` 判定を、Full autonomous Plan-first flow へのエスカレーションではなく、実装前の Plan slice decomposition として扱うための運用メモです。

このメモは、token-aware kernel flow に関する `full-coverage` の意味付けを要約した補足ポリシーです。`docs/token-aware-guardrail-kernel-process-and-agents.md` 側でも、`### full-coverage`、`Flow A`、`Flow C`、および `runtime-contract-kernel.agent.md` の escalation condition をこの方針に合わせて更新済みです。

## Policy

- `full-coverage` means: the parent Plan is too broad / ambiguous / strongly interconnected to implement as one bounded pass.
- `full-coverage` does not mean: run `plan-generation.agent.md`, `runtime-evidence.agent.md`, or `integration-test-design.agent.md`.
- The next step is always `plan-slice-decomposition.agent.md`.
- The broad autonomous flow remains available only as an explicit, separate process choice; it is not the default interpretation of `full-coverage` inside token-aware triage.
- Each resulting slice re-enters the token-aware kernel flow.
- Cross-slice contracts must remain explicit and must be verified after slice implementations.

## Minimal chain

```text
Parent Plan Kernel
→ Change Risk Triage
→ Plan Slice Decomposition
→ Per-slice Plan網羅チェック・残件判定フロー
→ Cross-Slice Verification Kernel
→ Gap triage / selected slice repair when needed
```
