---
name: design-pair-implementation-execution
description: Use only when the user explicitly selects Design Pair before implementation. Investigate and present the bounded planned change surface, stop for a new post-map user response, discuss user-selected design topics, persist only explicitly confirmed Locked Decisions, then hand off to Adaptive Implementation.
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
- Target Map と内部設計判断候補を利用者へ提示し、durable waiting state を保存してその turn を終了する
- 利用者が選んだ重要論点を対話する
- 利用者が明示的に確定した事項だけを `Locked Decisions` として tracked handoff に保存する
- upstream binding constraints と今回の Design Pair decisions を別 section に保存する
- completed handoff を `adaptive-implementation-execution` へ渡す
- Adaptive 実行後、比較評価用の結果を同じ tracked handoff に追記する

production code / tests の実装、HIGH_MODEL / STANDARD_MODEL の orchestration、delegation、re-entry、verification boundary は再実装しない。Design Pair phase の完了前に production code / tests を編集してはいけない。

## Accepted upstream routes

### Ordinary Plan / Implementation Intent

goal、scope、acceptance が実装開始に十分であれば、通常 Plan Mode output、repository-tracked Plan、Issue、または短い Implementation Intent から開始できる。

### Plan Coverage Flow

`implementation-handoff-review` または明示的に同等の Inline Ready Gate が implementation を許可した後だけ開始する。parent Plan / FR / AC、change-risk-triage、implementation contract、runtime contract、test design、handoff review の責務を Design Pair へ移してはいけない。

route metadata と Design Pair interaction state は Plan Coverage の durable artifact / resume state から次のまま受け取る。

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
design_pair_handoff: plans/<slug>-design-pair-implementation-handoff.md
design_pair_interaction_stage: target-selection / disposition-confirmation / upstream-decision / complete
```

metadata が欠落または矛盾する場合、この skill は route や user evidence を推測せず `BLOCKED` とし、artifact repair を要求して停止する。Plan Coverage parent は waiting 中の Design Pair を完了扱いせず、Adaptive Implementation、verification、residual flow を開始しない。

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

`map.md` の schema で具体的な file / symbol、現在の責務、current invariant、requested change との関係、内部設計判断候補、予想される変更または verification、evidence、不明点を記録する。AI が重要と推定した一部だけを説明して終了してはいけない。human response 前の disposition は `Pending-User-Selection` とし、Target Map 作成時点で `Locked`、`Discussed-Unlocked`、`Adaptive-Owned` を割り当てない。

Target Map は bounded な予定変更面の説明であり、全 repository、すべての潜在 decision surface、または全 allowed edit surface の列挙ではない。`Affected files / symbols` と Target Map の file / symbol は Adaptive Implementation の allowed edit surface ではない。

upstream Plan、Issue、acceptance criteria、gold document、repository policy / public contract は `Upstream Binding Constraints` または `Known Evidence` として記録する。Design Pair Decision ID を付けず、今回の対話による explicit human confirmation として計上しない。最初の依頼に技術案が含まれる場合は `Upstream User Initial Positions` として保存できるが、Target Map と code evidence の提示前に Locked Decision へ昇格しない。「この判断を Lock する」という current request であっても、内部設計判断は conflict evidence を確認した Target Map の提示後に再確認する。

## Phase 3: Present the Target Map and stop

Target Map を作成した最初の Design Pair turn では、bounded な予定変更面全体と各 Target の判断候補を利用者へ説明する。続いて次を明示的に求める。

- 議論したい Target ID
- 各 Target に対する初期案、懸念、検討したい技術または構造
- 議論しない Target を Adaptive に委ねるか
- 全 Target を Adaptive に委ねる場合は、その包括的な明示

`handoff.md` に次を保存する。

```yaml
verdict: AWAITING_USER_INPUT
interaction_stage: target-selection
target_map_presentation_evidence: <assistant message / turn reference and presented Target IDs>
target_selection_request_evidence: <assistant message / turn reference>
latest_user_response_reference: Pending
user_response_after_target_map: Pending
```

保存後、**その turn を終了する**。利用者の最初の依頼が「実装してください」であっても、この boundary を省略しない。初回 turn では次を禁止する。

- `READY_FOR_ADAPTIVE_IMPLEMENTATION` の返却
- `adaptive-implementation-execution` または implementation owner の開始
- production code / tests の編集
- Design Pair 由来の Locked Decision の生成
- 人間が選択していない Target の human-owned disposition 確定
- upstream artifact または利用者の沈黙を今回の Design Pair confirmation とみなすこと

## Phase 4: Resume and discuss user-selected topics

resume では、tracked handoff の route identity、interaction stage、Target Map、presentation evidence、Target 選択要求 evidence、Target Map 提示後の user response、disposition evidence を検証する。欠落または矛盾がある場合は upstream text や AI summary から補完せず、`BLOCKED` / artifact repair で停止する。`AWAITING_USER_INPUT` で有効な新しい user response がない場合は同じ waiting state を維持し、Adaptive へ fallback しない。

Target Map 提示後の user response は、test harness や parent が補足、言い換え、または必要項目を合成せず、そのままこの skill に渡す。response が Target ID の選択だけで、初期案、懸念、または未選択 Target の delegation が不足する場合は partial selection として扱う。AI は選択済み Target の code evidence と判断候補を説明して不足項目を尋ねてもよいが、未定義の interaction stage を作らず、`AWAITING_USER_INPUT / target-selection` を維持してその turn を終了する。必要な selection input が揃い、AI が trade-off と validation expectation を提示した後だけ `AWAITING_USER_INPUT / disposition-confirmation` へ進める。

各 response を処理して turn を終了する前に、handoff header、Target Map row、summary Target sets、Readiness Check を同じ observed evidence から再計算する。`User response occurred after Target Map presentation: Yes` なら Readiness Check の同名 row も同じ user reference で `PASS` にしなければならない。interaction stage は `target-selection`、`disposition-confirmation`、`upstream-decision`、`complete` のいずれかだけを使用し、partial input を独自 stage で表現してはいけない。headerとReadiness、summaryとrow、stageとpending状態に矛盾がある artifact は保存せず、修復してから停止する。

各重要 Target は次の順で扱う。

1. AI が現在の構造、具体的 code location、現在の invariant、今回必要になり得る判断、不明点を説明する。
2. 利用者が初期案、問題の捉え方、検討したい技術や構造を提示する。
3. AI が反論、代替案、trade-off、追加 evidence、validation expectation を提示する。
4. 利用者が最終 disposition を明示的に決める。

AI の推奨案を最初から確定案として提示してはいけない。利用者の沈黙、AI の提案、既存 pattern、または「異論なし」から `Locked` を推定してはいけない。

利用者が Target と初期案だけを返した場合、AI は code evidence、反論または支持、代替案、trade-off、production wiring / lifecycle / state ownership / test seam への影響、validation expectation、未解決点を提示する。その response の前に与えられた initial position を自動的に最終 disposition とせず、次を保存して再び turn を終了する。

```yaml
verdict: AWAITING_USER_INPUT
interaction_stage: disposition-confirmation
```

利用者の response が、すでに提示済みの AI trade-off に対する明確な最終 disposition まで含む場合だけ追加 turn を省略できる。AI が自分で human-owned disposition を決めてはいけない。

各 Target は次のいずれかへ分類する。

| Disposition | Meaning |
| --- | --- |
| `Pending-User-Selection` | Target Map 提示後の利用者選択待ち |
| `Pending-User-Disposition` | AI の分析後の利用者最終判断待ち |
| `Locked` | Target Map 提示後の対話で利用者が明示的に決定済み。Decision ID と confirmation evidence を付けて binding とする |
| `Discussed-Unlocked` | 対話後、利用者が拘束しないと明示した参考情報 |
| `Adaptive-Owned` | Target Map 提示後、利用者が個別、未選択項目一括、または全件を Adaptive に委ねると明示した範囲 |
| `No-Change` | 客観的 evidence で変更対象外。human-owned decision に関係する場合は利用者の disposition が必要 |
| `Upstream-Decision-Required` | Plan、仕様、policy 等の上流判断が必要 |

`Adaptive-Owned` と `Discussed-Unlocked` が残ることは正常であり、不完全な Design Pair と扱わない。全設計確定、全 unknown の除去、`Unknown == 0` は完了条件ではない。

必要な場合は public signature、状態遷移、ownership、lock 範囲、CancellationToken 伝播等の最小 Design Probe を会話または handoff に記録できる。Design Probe は非 binding であり、production implementation または source of truth にしてはいけない。

`Locked` は次のすべてを満たす場合だけ作成する。

- Target Map で対象 Target を提示済み
- AI が code evidence、trade-off、代替案、validation expectation を説明済み
- 利用者がその決定を明示的に確定済み
- Decision ID がある
- user message / turn reference、Target ID、確定内容の短い引用または忠実な要約、`confirmation occurred after Target Map presentation: Yes` がある

upstream Plan、Issue、acceptance criteria、gold document、repository docs、AI summary、過去会話からの推測、利用者の沈黙は confirmation evidence に使用しない。

## Phase 5: Finalize the tracked handoff

`handoff.md` の schema を使い、次を明確に分離する。

- `Upstream Binding Constraints`: Plan / Issue / acceptance / repository policy に既存の binding requirement。Design Pair Decision ID は付けない
- `Upstream User Initial Positions`: Target Map 提示前の利用者案。Design Pair decision ではない
- `Locked Decisions`: Target Map 提示後に利用者が明示的に確定した Decision ID 付き binding constraint
- `Discussed but Unlocked`: 参考情報
- `Adaptive-Owned`: HIGH_MODEL の通常裁量
- `Known Evidence` / `Known Assumptions`: 参考情報
- `Upstream Decisions Required`: blocking / non-blocking の上流判断

Adaptive Implementation へ進める条件は次のとおり。

- goal、scope、acceptance が実装開始に十分
- Target Map presentation と Target 選択要求の evidence がある
- Target Map 提示後の利用者 response がある
- 利用者が一件以上の Target を議論対象として選択した、または全 Target を Adaptive に委ねると明示した
- 選択された全 Target に利用者由来の最終 disposition があり、pending human-owned Target がない
- Locked Decisions が有効な post-map confirmation evidence を持ち、upstream contract と矛盾しない
- blocking な `Upstream-Decision-Required` がない
- tracked handoff が current worktree と upstream artifact を参照している

READY 判定前に、Target Map と summary field を集合として照合する。Target Map の全 Target ID は一意でなければならない。`Selected Target IDs`、`Delegated-to-Adaptive Target IDs`、`No-Change Target IDs`、`Upstream-Decision-Required Target IDs`、`Pending human-owned Target IDs` の concrete ID はすべて Target Map に実在し、5集合は互いに素で、その和集合は Target Map の全 Target ID と完全一致しなければならない。架空 ID、重複 ID、未分類 Target、summary にだけある ID、Target Map にだけある ID は readiness を FAIL にする。

summary と Target Map row の対応は次の完全一致とする。

- `Selected Target IDs`: disposition が `Locked` または `Discussed-Unlocked`
- `Delegated-to-Adaptive Target IDs`: disposition が `Adaptive-Owned`
- `No-Change Target IDs`: disposition が `No-Change`
- `Upstream-Decision-Required Target IDs`: disposition が `Upstream-Decision-Required`
- `Pending human-owned Target IDs`: disposition が `Pending-User-Selection` または `Pending-User-Disposition`

各 Locked Decision の Target ID は `Selected Target IDs` に含まれ、その Target Map row は `Locked` でなければならない。`Locked` row には一件以上の valid Locked Decision が必要である。`Explicit all-Adaptive delegation: Yes` では、`Selected Target IDs: None`、`Pending human-owned Target IDs: None`、Locked Decisionsなし、Target Map の全 Target row が `Adaptive-Owned`、`Delegated-to-Adaptive Target IDs` が全 Target IDと完全一致する場合だけ READY にできる。

Target 未選択を空集合として PASS にしない。Target Map 提示後に利用者が全 Target を Adaptive へ委ねると明示した場合は、個別対話や Locked Decision を作らず READY にできる。条件を満たす場合だけ `interaction_stage: complete` と `READY_FOR_ADAPTIVE_IMPLEMENTATION` を同時に設定する。選択または disposition 待ちは `AWAITING_USER_INPUT`、blocking な上流判断は `interaction_stage: upstream-decision` と `HUMAN_DECISION_REQUIRED` または `REPLAN_REQUIRED`、tool / permission / environment blocker は `BLOCKED` とする。

## Phase 6: Hand off to Adaptive Implementation

`READY_FOR_ADAPTIVE_IMPLEMENTATION` の場合だけ、tracked handoff path と original Plan / Implementation Intent を `adaptive-implementation-execution` へ渡す。

Adaptive Implementation に対する invariant:

> HIGH_MODEL は通常の adaptive implementation と同じ authority を維持する。original Plan / Implementation Intent、repository policy、`Upstream Binding Constraints` は既存の binding input として守る。Design Pair が今回新たに作る binding decision は、handoff の有効な `Locked Decisions` だけとし、それ以外の実装判断は実コードと verification evidence に基づいて自由に行う。

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
- interaction stage
- implementation route metadata
- upstream source references
- tracked handoff path
- Target Map summary
- Target Map presentation / user response evidence
- selected / Adaptive-delegated / No-Change / Upstream-Decision-Required / pending Target IDs と Target Map 集合照合 evidence
- Upstream Binding Constraints
- Locked Decision IDs
- Discussed-Unlocked / Adaptive-Owned items
- blocking upstream decisions, if any
- next action: Adaptive Implementation / human decision / replan / blocked
- production code / tests edited during Design Pair: `No`
- final review status: `Not performed by this flow`
