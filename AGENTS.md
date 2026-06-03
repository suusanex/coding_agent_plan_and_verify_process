# AGENTS.md

<!--
Copyright (c) 2026 suusanex (GitHub UserName)
SPDX-License-Identifier: CC-BY-4.0
License: https://creativecommons.org/licenses/by/4.0/
Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
-->

## Codex 向けプロジェクト指示

この repository は、coding agent に Plan-first / verification-first の作業プロセスを渡すための agent / skill / documentation を管理します。

GitHub Copilot 向けの `.github/agents/*.agent.md` が既存の主成果物です。Codex で作業する場合も、既存の Token-aware guardrail kernel flow の用語・責務・artifact chain を source of truth として扱ってください。

## Token-aware guardrail kernel flow の扱い

`change-risk-triage.agent.md` が `full-coverage` を診断した場合、Codex は `plan-slice-decomposition.agent.md` の出力から直接実装に入ってはいけません。

その場合は、原則として `$token-aware-full-coverage-3layer` skill を使ってください。

この skill は、次の3層で進めます。

1. 親エージェントによる orchestration と parent review gate
2. slice-prep subagent による slice 単位の kernel artifact 下書き
3. slice-impl subagent による親承認済み slice の実装と verification-kernel

## 重要な禁止事項

- `plan-slice-decomposition` の slice artifact を「実装準備完了」とみなしてはいけません。
- per-slice `change-risk-triage`、必要な `implementation-contract-kernel`、`runtime-contract-kernel`、`test-design-kernel` を飛ばしてはいけません。
- cross-slice contract (`XC-xxx`) を単一 slice 内で完了扱いにしてはいけません。
- source evidence のない field / state / identifier を fallback、空文字、推測、本文からの生成値で埋めて `Done` にしてはいけません。
- `verification-kernel` や `cross-slice-verification-kernel` で見つけた gap を、その場で scope 拡大して修正してはいけません。必要なら `coverage-gap-triage` に渡してください。

## Codex での典型的な起動例

```text
$token-aware-full-coverage-3layer を使って、この full-coverage decomposition を進めて。
まず slice preparation と parent review gate まで。実装はまだ行わない。
```

実装まで進める場合も、parent review gate で READY になった slice だけを `slice-impl` に渡してください。
