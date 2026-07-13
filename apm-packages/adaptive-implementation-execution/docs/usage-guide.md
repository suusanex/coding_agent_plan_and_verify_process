# Usage Guide

## Suitable tasks

- 通常 Plan Mode で scope と acceptance は決まったが、実装中の責務配置や wiring 判断が残り得る変更
- small-bounded または medium-bounded な production implementation
- existing pattern を確認してから、同型 case や tests を STANDARD_MODEL へ渡せる可能性がある変更
- HIGH_MODEL が代表経路を実装した後に残存 decision surface を評価すべき変更

## Unsuitable tasks

- goal、scope、acceptance が判断できない request
- Plan Coverage Flow が必要な広い requirement coverage / runtime boundary / residual decision work
- final code review や総合 architecture review だけを行いたい request
- write-heavy agent を並列実行したい request
- CHEAP_MODEL に一般的な production implementation を任せたい request
- 未検証の Copilot model tier switching を前提にした運用

## Start after ordinary Plan Mode

```text
$adaptive-implementation-execution を使って、直前の Plan を実装してください。
Plan の scope / non-goals / acceptance を維持し、final review は別工程として残してください。
```

repository-tracked Plan の例:

```text
$adaptive-implementation-execution を使って plans/issue-123.md を実装してください。
```

短い caller intent の例:

```text
$adaptive-implementation-execution を使って進めてください。
Goal: CSV import の空行を無視する。
Scope: ImportService と既存 tests。
Non-goals: parser library の交換、public API 変更。
Acceptance: 空行を含む既存形式が成功し、invalid row の既存 error は維持される。
Validation: focused unit tests と solution build。
```

## What HIGH_MODEL does

`high-implementation-starter` は relevant code、tests、production wiring を読み、実際に編集し、focused checks を実行します。

事前に `direct implementation` / `shape-then-complete` を固定分類しません。actual code と verification の結果から、残っている decision surface を繰り返し評価します。

次が残る間は HIGH_MODEL が続行します。

- responsibility placement
- API / signature / schema
- dependency / module / interface choice
- DI / entrypoint / production wiring
- error / cancellation / retry / state ownership
- test seam / mock boundary / harness
- implementation trade-off

安全な delegation point がない場合は `COMPLETED_BY_HIGH_MODEL` で完了して構いません。

## What STANDARD_MODEL does

`standard-implementation-completer` は handoff の `Remaining work` と `Allowed edit surface` だけを扱います。

適した残作業:

- established pattern に沿った追加 case
- validation / mapping の局所追加
- tests / fixtures / test data
- locked decisions を変えない focused failure 修正

locked decisions を変える必要がある場合は、局所的にねじ込まず `NEEDS_HIGH_MODEL_REENTRY` を返します。

## Re-entry example

HIGH_MODEL が validation branches と tests を委譲した後、STANDARD_MODEL が production entrypoint の registration 変更を必要と判断した例:

```text
READY_FOR_STANDARD_COMPLETION
  -> standard-implementation-completer starts
  -> existing test cannot reach the production registration path
  -> NEEDS_HIGH_MODEL_REENTRY
  -> high-implementation-starter resumes with the original intent and re-entry handoff
```

STANDARD_MODEL は registration を暗黙変更しません。re-entry handoff に invalidating evidence、変更済み files、実行した checks、必要な decision を記録します。

## Inline and tracked handoff

### inline

同一 run / 同一 parent orchestration 内で agent を直列実行できる通常経路です。repository file を増やしません。

### tracked

次の場合に `plans/<slug>-implementation-completion-handoff.md` を作成します。

- session boundary または resume が必要
- 別 thread / 別 model / 別作業者へ移行する
- execution time limit により同一 run で続けられない

tracked handoff は実コードの代替設計書ではありません。locked decisions、remaining work、allowed surface、validation、re-entry trigger の短い実行情報に留めます。

## Verification and final review

HIGH_MODEL と STANDARD_MODEL は、それぞれの変更に関連する build、focused test、lint、format、type check を可能な範囲で実行します。

この flow の `COMPLETED_BY_HIGH_MODEL` または `COMPLETED` は implementation scope の完了を表します。final code review、human review、総合 architecture review、独立 verification の完了は表しません。

最終報告は次を分けます。

- 完了済み implementation
- 実行済み checks
- 未検証事項
- 人手での作業が必要な項目
- final review status

## Changing model assignment

抽象 tier と具体的 model の対応は `profiles/adaptive-implementation/agents/*.toml` で変更します。

- `model`: runtime で利用可能な model
- `model_reasoning_effort`: role に必要な reasoning
- `sandbox_mode`: implementation agent では `workspace-write`

skill、portable agent、profile `AGENTS.md` の本文に具体的 model 名を追加しません。

