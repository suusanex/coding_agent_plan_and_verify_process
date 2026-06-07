---
description: Codex project guidance for Plan網羅チェック・残件判定フロー when full-coverage decomposition requires three-layer slice orchestration.
---

## Codex 向けプロジェクト指示

この repository は、coding agent に Plan-first / verification-first の作業プロセスを渡すための agent / skill / documentation を管理します。

GitHub Copilot 向けの `.github/agents/*.agent.md` が既存の主成果物です。Codex で作業する場合も、既存の Plan網羅チェック・残件判定フロー の用語・責務・artifact chain を source of truth として扱ってください。

## Plan網羅チェック・残件判定フロー の扱い

`change-risk-triage.agent.md` が `full-coverage` を診断した場合、Codex は `plan-slice-decomposition.agent.md` の出力から直接実装に入ってはいけません。

その場合は、原則として `$token-aware-full-coverage-3layer` skill を使ってください。この skill 名は互換用の legacy invocation です。本文では Plan網羅チェック・残件判定フローとして扱います。

この skill は、次の3層で進めます。

1. 親エージェントによる orchestration と parent review gate
2. slice-prep subagent による slice 単位の kernel artifact 下書き
3. slice-impl subagent による親承認済み slice-local bounded parent Plan pass の実装と verification-kernel
4. 親エージェントによる cross-slice-verification-kernel と residual-decision-gate

開始時に `ExecutionMode` を `PREP_ONLY` / `DELEGATED_IMPLEMENTATION` / `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION` のいずれかとして `plans/*-agent-usage-ledger.md` に記録してください。

`DELEGATED_IMPLEMENTATION` mode では、親エージェントは production code / tests を直接編集してはいけません。親が編集できるのは orchestration artifact、parent review gate、Agent Usage Ledger、cross-slice verification、residual decision、final summary / handoff artifact に限定します。

## 重要な禁止事項

- `plan-slice-decomposition` の slice artifact を「実装準備完了」とみなしてはいけません。
- per-slice `change-risk-triage`、必要な `implementation-contract-kernel`、`runtime-contract-kernel`、`test-design-kernel` を飛ばしてはいけません。
- executable slice は `slice-prep` に MUST delegate してください。blocked / human decision / triage only の場合は理由を Agent Usage Ledger に記録してください。
- `DELEGATED_IMPLEMENTATION` で READY になった slice は `slice-impl` に MUST delegate してください。`slice-impl` run の証跡がない READY slice は `BlockedByMissingSliceImplDelegation` として停止してください。
- 親直接実装は `PARENT_DIRECT_IMPLEMENTATION_EXCEPTION`、明示理由、explicit human approval がある場合だけ許可します。これは3層委譲成功として扱いません。
- cross-slice contract (`XC-xxx`) を単一 slice 内で完了扱いにしてはいけません。
- source evidence のない field / state / identifier を fallback、空文字、推測、本文からの生成値で埋めて `Done` にしてはいけません。
- `verification-kernel` や `cross-slice-verification-kernel` で見つけた gap を、その場で scope 拡大して修正してはいけません。必要なら `coverage-gap-triage` に渡してください。

## Codex での典型的な起動例

```text
$token-aware-full-coverage-3layer を使って、この full-coverage decomposition を Plan網羅チェック・残件判定フローとして進めて。
まず slice preparation と parent review gate まで。実装はまだ行わない。
```

実装まで進める場合も、parent review gate で READY になった slice だけを `slice-impl` に渡してください。
このとき `ExecutionMode = DELEGATED_IMPLEMENTATION`、`EditOwner = slice-impl`、`DelegationRequired = Yes` を Agent Usage Ledger に記録し、親エージェントは production code / tests を直接編集しないでください。
