---
name: design-pair-implementation-execution
description: Use only when the user explicitly selects Design Pair before implementation. Investigate the bounded planned change surface, discuss user-selected design topics, persist only explicit Locked Decisions, then hand off to Adaptive Implementation.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Design Pair Implementation Execution

この skill は、利用者が Design Pair route を明示的に選択した場合だけ、Adaptive Implementation の前段として使用する。

route metadata は次の固定値とする。

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
```

課題の難易度、risk、変更規模、architecture 特性からこの route を自動選択、推奨、提案してはいけない。明示選択がない通常経路は `adaptive-implementation-execution` であり、この skill を起動しない。

## Role boundary

この skill の責務は次に限定する。

- upstream Plan / Implementation Intent と関連 artifact を読む
- bounded な予定変更面に関係する既存 code と tests を調査する
- 予定変更面全体を説明する `Design Pair Target Map` を作る
- 利用者が選んだ重要論点を対話する
- 利用者が明示的に確定した事項だけを `Locked Decisions` として tracked handoff に保存する
- completed handoff を `adaptive-implementation-execution` へ渡す
- Adaptive 実行後、比較評価用の結果を同じ tracked handoff に追記する

production code / tests の実装、HIGH_MODEL / STANDARD_MODEL の orchestration、delegation、re-entry、verification boundary は再実装しない。Design Pair phase の完了前に production code / tests を編集してはいけない。

## Accepted upstream routes

### Ordinary Plan / Implementation Intent

goal、scope、acceptance が実装開始に十分であれば、通常 Plan Mode output、repository-tracked Plan、Issue、または短い Implementation Intent から開始できる。

### Plan Coverage Flow

`implementation-handoff-review` または明示的に同等の Inline Ready Gate が implementation を許可した後だけ開始する。parent Plan / FR / AC、change-risk-triage、implementation contract、runtime contract、test design、handoff review の責務を Design Pair へ移してはいけない。

route metadata は Plan Coverage の durable artifact / resume state から次のまま受け取る。

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
```

metadata が欠落または矛盾する場合、この skill は route を推測せず `HUMAN_DECISION_REQUIRED` で停止する。

## Phase 1: Validate source and route

1. explicit user selection の evidence を確認する。
2. repository instructions、current worktree status、upstream Plan / Implementation Intent、関連 artifact を読む。
3. goal、scope、acceptance を確認する。不足が product / policy / scope decision の場合は `REPLAN_REQUIRED` または `HUMAN_DECISION_REQUIRED` で停止する。
4. Plan Coverage route では、handoff review または equivalent Inline Ready Gate が implementation を許可していることを確認する。
5. tracked handoff path を `plans/<slug>-design-pair-implementation-handoff.md` として確定する。

## Phase 2: Build the bounded Target Map

upstream Plan / handoff から予定変更面の境界を導き、repository 全体を無差別に読むことなく、少なくとも次を確認する。

- production code の対象 symbol と直接の call sites
- tests、fixture、test seam
- DI、factory、startup、entrypoint、production wiring
- config、serialized shape、public API 等の関連 surface
- 対象変更に直接関係する event、callback、async lifecycle、cancellation、state ownership

`map.md` の schema で具体的な file / symbol、現在の責務、requested change との関係、予想される変更または verification、evidence、不明点を記録する。AI が重要と推定した一部だけを説明して終了してはいけない。

Target Map は bounded な予定変更面の説明であり、全 repository、すべての潜在 decision surface、または全 allowed edit surface の列挙ではない。`Affected files / symbols` と Target Map の file / symbol は Adaptive Implementation の allowed edit surface ではない。

## Phase 3: Discuss user-selected topics

各重要 Target は次の順で扱う。

1. AI が現在の構造、具体的 code location、現在の invariant、今回必要になり得る判断、不明点を説明する。
2. 利用者が初期案、問題の捉え方、検討したい技術や構造を提示する。
3. AI が反論、代替案、trade-off、追加 evidence、validation expectation を提示する。
4. 利用者が disposition を決める。

AI の推奨案を最初から確定案として提示してはいけない。利用者の沈黙、AI の提案、既存 pattern、または「異論なし」から `Locked` を推定してはいけない。

各 Target は次のいずれかへ分類する。

| Disposition | Meaning |
| --- | --- |
| `Locked` | 利用者との対話で明示的に決定済み。Decision ID を付けて binding とする |
| `Discussed-Unlocked` | 対話したが Adaptive Implementation に判断を委ねる参考情報 |
| `Adaptive-Owned` | Design Pair では決めず、HIGH_MODEL が実コードと verification evidence から判断する |
| `No-Change` | 影響を確認したが変更しない |
| `Upstream-Decision-Required` | Plan、仕様、policy 等の上流判断が必要 |

`Adaptive-Owned` と `Discussed-Unlocked` が残ることは正常であり、不完全な Design Pair と扱わない。全設計確定、全 unknown の除去、`Unknown == 0` は完了条件ではない。

必要な場合は public signature、状態遷移、ownership、lock 範囲、CancellationToken 伝播等の最小 Design Probe を会話または handoff に記録できる。Design Probe は非 binding であり、production implementation または source of truth にしてはいけない。

## Phase 4: Finalize the tracked handoff

`handoff.md` の schema を使い、次を明確に分離する。

- `Locked Decisions`: 利用者が明示的に確定した Decision ID 付き binding constraint
- `Discussed but Unlocked`: 参考情報
- `Adaptive-Owned`: HIGH_MODEL の通常裁量
- `Known Evidence` / `Known Assumptions`: 参考情報
- `Upstream Decisions Required`: blocking / non-blocking の上流判断

Adaptive Implementation へ進める条件は次のとおり。

- goal、scope、acceptance が実装開始に十分
- 利用者が議論対象として選んだ Target が disposition 済み
- Locked Decisions が曖昧でなく、upstream contract と矛盾しない
- blocking な `Upstream-Decision-Required` がない
- tracked handoff が current worktree と upstream artifact を参照している

条件を満たす場合は `READY_FOR_ADAPTIVE_IMPLEMENTATION` とする。blocking な上流判断がある場合は `HUMAN_DECISION_REQUIRED` または `REPLAN_REQUIRED`、tool / permission / environment blocker は `BLOCKED` とする。

## Phase 5: Hand off to Adaptive Implementation

`READY_FOR_ADAPTIVE_IMPLEMENTATION` の場合だけ、tracked handoff path と original Plan / Implementation Intent を `adaptive-implementation-execution` へ渡す。

Adaptive Implementation に対する invariant:

> HIGH_MODEL は通常の adaptive implementation と同じ authority を維持する。Design Pair handoff の `Locked Decisions` に明示された事項だけを binding constraint として扱い、それ以外の実装判断は実コードと verification evidence に基づいて自由に行う。

Target Map、`Discussed but Unlocked`、`Adaptive-Owned`、Known Evidence、Known Assumptions、Knowledge Candidates は参考情報であり、HIGH_MODEL の裁量または edit surface を拘束しない。

Design Pair 由来の Locked Decisions は Decision ID と origin を保持し、HIGH_MODEL の追加 locked decisions と統合して Implementation Completion Handoff へ渡す。STANDARD_MODEL はその統合済み一覧を守る。

Locked Decision と actual code が衝突した場合、HIGH_MODEL は黙って変更せず `HUMAN_DECISION_REQUIRED`、`REPLAN_REQUIRED`、または適切な既存 stop verdict で停止する。automatic Design Pair re-entry は行わない。

## Evaluation record

Adaptive 実行後、parent / router は tracked Design Pair handoff の `Adaptive Implementation Result` を更新し、少なくとも次を残す。

- route used
- Target Map path / section
- Locked Decision IDs
- Discussed-Unlocked / Adaptive-Owned items
- tracked handoff path
- Adaptive Implementation verdict sequence
- Locked Decision compliance evidence
- Locked Decision conflict の有無
- validation performed
- final review status

Design Pair または Adaptive Implementation の completion verdict を、final code review、human review、総合 architecture review、独立 verification の完了と表現してはいけない。

## Output

- Design Pair verdict
- implementation route metadata
- upstream source references
- tracked handoff path
- Target Map summary
- Locked Decision IDs
- Discussed-Unlocked / Adaptive-Owned items
- blocking upstream decisions, if any
- next action: Adaptive Implementation / human decision / replan / blocked
- production code / tests edited during Design Pair: `No`
- final review status: `Not performed by this flow`
