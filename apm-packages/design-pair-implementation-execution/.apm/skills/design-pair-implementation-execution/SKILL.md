---
name: design-pair-implementation-execution
description: Use only when the user explicitly selects Design Pair before implementation. Present code-grounded decision materials, stop for a post-map response, accept direct questions, decisions or explicit skips, persist confirmed Locked Decisions, then hand off to Adaptive Implementation.
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
- 資料から直接受けた質問・反論・案・確定・スキップを処理する
- 利用者が明示的に確定した事項だけを `Locked Decisions` として tracked handoff に保存する
- upstream binding constraints と今回の Design Pair decisions を別 section に保存する
- completed handoff を `adaptive-implementation-execution` へ渡す
- Adaptive 実行後、比較評価用の結果を同じ tracked handoff に追記する

production code / tests の実装、decision-surface-implementation-owner / bounded-residual-implementation-owner の orchestration、delegation、re-entry、verification boundary は再実装しない。Design Pair phase の完了前に production code / tests を編集してはいけない。

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

`map.md` の schema を tracked handoff 内に展開し、判断する問いを中心とした一覧と ID 別の判断資料を一まとまりの Markdown にする。1ファイル＝1IDではなく、独立に議論・判断・委任できる論点を1IDとする。機械的な追随変更や検証対象は関連論点の変更範囲・根拠へまとめる。AI が重要と推定した一部だけを説明して終了してはいけない。human response 前の disposition は `Pending-User-Selection` とし、Target Map 作成時点で `Locked`、`Discussed-Unlocked`、`Adaptive-Owned` を割り当てない。

各論点は「何を決めるか／なぜ必要か → 調査済みの事実と制約 → 実在する選択肢と判断上の違い → 根拠付きの非 binding proposal または `No proposal` 理由 → 未確認事項・検証期待」を因果関係が読める形で説明する。具体的な file / symbol、現在の責務・invariant、caller / wiring / lifecycle / state ownership / test seam、変更・検証範囲と evidence に辿れるようにする。関連 surface が存在しない場合は調査根拠付き N/A とする。単に表の列名を替えて事実を列挙してはいけない。

目的は調査・検討済みの判断材料の説明であり、初回に全論点の詳細設計を新たに行うことではない。未調査の仮説を確定事実や既存案とせず、不明・追加調査条件を明記する。選択肢を水増しせず、比較できない場合も理由を示す。資料節には Target ごとの版と根拠 revision を付ける。同じ説明を別ファイルと会話へ重複生成することは必須にしない。

Target Map は bounded な予定変更面の説明であり、全 repository、すべての潜在 decision surface、または全 allowed edit surface の列挙ではない。`Affected files / symbols` と Target Map の file / symbol は Adaptive Implementation の allowed edit surface ではない。

upstream Plan、Issue、acceptance criteria、gold document、repository policy / public contract は `Upstream Binding Constraints` または `Known Evidence` として記録する。Design Pair Decision ID を付けず、今回の対話による explicit human confirmation として計上しない。最初の依頼に技術案が含まれる場合は `Upstream User Initial Positions` として保存できるが、Target Map と code evidence の提示前に Locked Decision へ昇格しない。「この判断を Lock する」という current request であっても、内部設計判断は conflict evidence を確認した Target Map の提示後に再確認する。

## Phase 3: Present the Target Map and stop

最初の Design Pair turn では、保存した判断資料へのリンクと、各論点の問い・主要な判断上の違い・不明点が分かる要約を会話に示す。質問・反論・代替案・明示的確定、部分／残件／全部スキップへ直接進めると案内する。IDのみの従来入力も受け付けるが、事前のID選択や「議論します」という宣言は必須にしない。

資料にある詳細の全面再掲や固定7列表は要求しない。ただし資料が存在するだけ、リンクだけ、IDと論点名だけでは提示にならない。turn終了前に資料への導線、判断入口の要約、各論点の判断材料と具体的根拠が読めることを確認し、欠ければ修復する。利用者が資料を参照できない場合は必要な説明を会話で提供してから提示済みとする。

会話の要約をAI提案だけにしない。各IDについて「何を決めるか、案の違い、残る不明点」を短く示す。不明点がなければその旨を示す。たとえば「解析をpolicyへ集約すると既存test seamで完結、callerへ置くとprotocol依存を分離できる。入力型は未確認」のように、資料を開く前にも判断の入口を分かるようにする。

`Target Map presentation evidence` は提示した資料節・版・全Target IDと実際のassistant turnを結び付ける。既存の `Target selection request evidence` は直接対話・確定・スキップを案内したturnを記録するfieldとして維持し、ID選択専用の要求を意味しない。

`handoff.md` に次を保存する。

```yaml
verdict: AWAITING_USER_INPUT
interaction_stage: target-selection
target_map_presentation_evidence: <assistant message / turn reference and presented Target IDs>
target_selection_request_evidence: <assistant message / turn reference>
latest_user_response_reference: Pending
user_response_after_target_map: Pending
finalization_status: Pending
```

保存後、**その turn を終了する**。利用者の最初の依頼が「実装してください」であっても、この boundary を省略しない。初回 turn では次を禁止する。

- `READY_FOR_ADAPTIVE_IMPLEMENTATION` の返却
- `adaptive-implementation-execution` または implementation owner の開始
- production code / tests の編集
- Design Pair 由来の Locked Decision の生成
- 人間が選択していない Target の human-owned disposition 確定
- upstream artifact または利用者の沈黙を今回の Design Pair confirmation とみなすこと

## Phase 4: Resume and discuss directly

resume では、tracked handoff の route identity、interaction stage、Target Map、資料節・版と presentation evidence、直接対話の案内 evidence、Target Map 提示後の user response、disposition evidence を検証する。正本は論点節とrow・人間の証拠であり、`Finalization status: Pending` のsummary集合・Readiness Checkは未計算である。これらがPendingであるだけで不正とはしないが、正本の欠落・矛盾は upstream text や AI summary から補完せず、`BLOCKED` / artifact repair で停止する。`AWAITING_USER_INPUT` で有効な新しい user response がない場合は同じ waiting state を維持し、Adaptive へ fallback しない。

Target Map 提示後の user response は、test harness や parent が補足、言い換え、または必要項目を合成せず、そのままこの skill に渡す。対象が一意ならIDなしの質問・懸念・案・反論・明示的確定を直接受理する。対象を特定できないときだけ確認する。Target Map に実在する Target ID の選択だけでも受理し、初期案、問題の捉え方、質問、検討したい技術や構造は任意とする。同じ Target ID を再要求せず、既存資料の判断上の違いを短く示して最終判断を尋ねる。存在しないIDだけなら選択未成立として `target-selection` を維持する。

新しい質問には該当する事実・根拠を使って直接回答する。初回資料で提示済みの判断材料を再利用し、定型の全文説明・コード再読・全論点再調査を繰り返さない。新案、情報不足、関連code / upstream条件の変更、参照資料へのアクセス不能など理由がある場合だけ必要範囲を追加調査し、理由・根拠と該当資料節の版を更新する。判断に影響する差分は利用者へ提示し、影響する確定をpendingに戻して再確認する。旧証拠は履歴へ残し、旧版への確定を新版へ黙って適用しない。単なる表記修正では判断内容を変えない。

「DP-T02は議論をスキップ」「残りはスキップ」「全部スキップ」は、その論点のDesign Pair対話を行わず判断をAdaptiveへ委ねる明示的な処置である。部分・残件・全件の対象をその時点の具体的IDへ展開してuser evidenceとともに保存する。「残り」は未確定・未委任のTargetを指す。既存Locked等も含む「全部」は、既存決定の撤回まで明示されない限りその扱いを確認する。実装省略や `No-Change` へ変換しない。未指示のTargetはpendingのままとし、全件委任を推測しない。

全Targetへの個別の明示委任が揃った場合も包括的な全件委任と同様に扱える。`Explicit all-Adaptive delegation: Yes` の根拠は、全Targetを覆う実際の明示委任の集合とする。単にSelectedが空であることからYesにしてはいけない。

`Selected Target Discussion Evidence` は具体的な判断材料のある資料節・版・提示assistant turnと、実際のuser response、追加対話の参照を結び付ける。初回資料でcode location、invariant、関連構造、alternatives / trade-offs、proposalまたはNo proposal理由、validation expectationを提示済みなら、その参照を再利用してよい。内容の全文転記や選択後の固定8項目blockは要求しない。資料なしの抽象的なリンクや論点名だけは証拠にならない。

各turnは更新した論点の質問・回答・判断・証拠、Target Map rowと `Target Disposition Evidence` / `Locked Decisions` の実際の変更、latest user response・verdict・stageだけを差分更新する。summaryの5集合、Selected Target discussion evidenceのsummary、Readiness Checkは完了まで `Pending` とし、`Finalization status: Pending` を維持する。途中で全状態を毎回書き直したり、全集合照合を常時必須にしたりしない。確定済みartifactへ変更を加える場合は先にREADYを解除し、finalizationと派生summary/checkをPendingへ戻す。正本rowと証拠の矛盾は放置しない。

Target Map 提示後の通常 interaction stage は `target-selection`、`disposition-confirmation`、`upstream-decision`、`complete` のいずれかだけを使用する。`target-selection` は直接対話も含む初回応答待ちであり、ID選択の必須工程ではない。`target-map-building` は提示前の `DRAFT`、`artifact-repair` は不整合を報告する `BLOCKED` だけに使用する。

AI の推奨案を最初から確定案として提示してはいけない。利用者の沈黙、AI の提案、既存 pattern、または「異論なし」から `Locked` を推定してはいけない。質問・初期案・IDのみでは最終dispositionにしない。必要な判断が残る場合は次を保存して再び turn を終了する。

```yaml
verdict: AWAITING_USER_INPUT
interaction_stage: disposition-confirmation
```

利用者の response が、初回資料を含む提示済みの判断材料に対して「A案で確定」のような明確な最終 disposition を含む場合、形式的な選択→同じ説明→再確認を挟まず受理する。AI が自分で human-owned disposition を決めてはいけない。

各 Target は次のいずれかへ分類する。

| Disposition | Meaning |
| --- | --- |
| `Pending-User-Selection` | Target Map 提示後の利用者応答待ち（ID選択は必須でない） |
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
- 確定が参照する判断資料の節・版・提示turnが追跡可能で、その後に判断を変える未確認差分がない
- 利用者がその決定を明示的に確定済み
- Decision ID がある
- user message / turn reference、Target ID、確定内容の短い引用または忠実な要約、`confirmation occurred after Target Map presentation: Yes` がある

upstream Plan、Issue、acceptance criteria、gold document、repository docs、AI summary、過去会話からの推測、利用者の沈黙は confirmation evidence に使用しない。

`Locked`、`Discussed-Unlocked`、`Adaptive-Owned` は、Targetごとに `Target Disposition Evidence` を一件持つ場合だけ最終 disposition として扱う。各 evidence row には Target ID、Target Map row と一致する final disposition、実際の user message / turn reference、確認内容の短い引用または忠実な要約、`Confirmation after Target Map: Yes` を保存する。Target ID はTarget Mapに実在し、同一Targetのrowは一件だけでなければならない。`Locked` rowは対応するLocked Decisionのconfirmation evidenceを同じ値で参照または複製できる。明示的な複数Target委任またはall-Adaptive委任では、同じuser turn referenceを複数Target rowに使用できるが、Targetごとのrowを省略してはいけない。

AIの推奨、Target Map、Plan、Issue、repository docs、過去会話、AI summaryを `Target Disposition Evidence` に使用しない。利用者が委任していないTargetをAIが`Adaptive-Owned`へ移すこと、利用者の最終応答なしに`Discussed-Unlocked`へ移すこと、pre-mapの発言をpost-map confirmationとして扱うことを禁止する。valid evidenceがないhuman-owned Targetはpendingのまま残してturnを終了する。

## Phase 5: Finalize the tracked handoff

`handoff.md` の schema を使い、次を明確に分離する。

- `Upstream Binding Constraints`: Plan / Issue / acceptance / repository policy に既存の binding requirement。Design Pair Decision ID は付けない
- `Upstream User Initial Positions`: Target Map 提示前の利用者案。Design Pair decision ではない
- `Locked Decisions`: Target Map 提示後に利用者が明示的に確定した Decision ID 付き binding constraint
- `Target Disposition Evidence`: `Locked`、`Discussed-Unlocked`、`Adaptive-Owned`をTarget単位で許可したpost-map user evidence
- `Discussed but Unlocked`: 参考情報
- `Adaptive-Owned`: decision-surface-implementation-owner の通常裁量
- `Known Evidence` / `Known Assumptions`: 参考情報
- `Upstream Decisions Required`: blocking / non-blocking の上流判断

Adaptive Implementation へ進める条件は次のとおり。

- goal、scope、acceptance が実装開始に十分
- Target Map presentation と直接対話・確定・スキップの案内（既存 Target selection request field）の evidence がある
- Target Map 提示後の利用者 response がある
- 利用者が一件以上の Target に直接判断または対話で参加した、または全 Target を Adaptive に委ねると明示した
- 選択された全 Target に利用者由来の最終 disposition があり、pending human-owned Target がない
- `Locked`、`Discussed-Unlocked`、`Adaptive-Owned`の全Targetに、row dispositionと一致する一意なpost-map `Target Disposition Evidence`がある
- 選択された全 Target に`Selected Target Discussion Evidence`があり、提示済み資料節・版・assistant turnから具体的code location、current invariant、関連構造、alternatives / trade-offs、proposalまたはNo proposal理由、validation expectationへ辿れ、実際のpost-map user responseと結び付く
- Locked Decisions が有効な post-map confirmation evidence を持ち、upstream contract と矛盾しない
- blocking な `Upstream-Decision-Required` がない
- tracked handoff が current worktree と upstream artifact を参照している

READY 判定前に、正本rowと証拠からsummary fieldとReadiness Checkをまとめて生成し、Target Map と summary field を集合として照合する。途中のPendingや過去のPASSを完了証拠として流用しない。Target Map の全 Target ID は一意でなければならない。`Selected Target IDs`、`Delegated-to-Adaptive Target IDs`、`No-Change Target IDs`、`Upstream-Decision-Required Target IDs`、`Pending human-owned Target IDs` の concrete ID はすべて Target Map に実在し、5集合は互いに素で、その和集合は Target Map の全 Target ID と完全一致しなければならない。架空 ID、重複 ID、未分類 Target、summary にだけある ID、Target Map にだけある ID は readiness を FAIL にする。

summary と Target Map row の対応は次の完全一致とする。

- `Selected Target IDs`: disposition が `Locked` または `Discussed-Unlocked`
- `Delegated-to-Adaptive Target IDs`: disposition が `Adaptive-Owned`
- `No-Change Target IDs`: disposition が `No-Change`
- `Upstream-Decision-Required Target IDs`: disposition が `Upstream-Decision-Required`
- `Pending human-owned Target IDs`: disposition が `Pending-User-Selection` または `Pending-User-Disposition`

各 Locked Decision の Target ID は `Selected Target IDs` に含まれ、その Target Map row は `Locked` でなければならない。`Locked` row には一件以上の valid Locked Decision が必要である。`Explicit all-Adaptive delegation: Yes` では、`Selected Target IDs: None`、`Pending human-owned Target IDs: None`、Locked Decisionsなし、Target Map の全 Target row が `Adaptive-Owned`、`Delegated-to-Adaptive Target IDs` が全 Target IDと完全一致する場合だけ READY にできる。

READY判定では`Target Disposition Evidence`も集合照合する。`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`のTarget全集合とevidence rowのTarget ID集合が完全一致し、各Targetが一回だけ現れ、evidenceのfinal dispositionがTarget Map rowおよびsummary分類と一致し、各confirmationがTarget Map提示後のactual user turnを参照する必要がある。evidenceの欠落、架空ID、重複Target、row / evidence disposition不一致、pre-map reference、AIが作った要約だけのreferenceはreadinessをFAILにする。all-Adaptiveでも全Targetに一件ずつevidence rowが必要である。

Target 未選択を空集合として PASS にしない。Target Map 提示後に利用者が全 Target を Adaptive へ委ねると明示した場合は、個別対話や Locked Decision を作らず READY にできる。全条件を満たし、header・summary・Readinessを同じ現行証拠へ同期した場合だけ `Finalization status: Validated`、`interaction_stage: complete` と `READY_FOR_ADAPTIVE_IMPLEMENTATION` を同時に設定する。失敗時はREADYにせず修復または利用者判断を要求する。応答または disposition 待ちは `AWAITING_USER_INPUT`、blocking な上流判断は `interaction_stage: upstream-decision` と `HUMAN_DECISION_REQUIRED` または `REPLAN_REQUIRED`、tool / permission / environment blocker は `BLOCKED` とする。

## Phase 6: Hand off to Adaptive Implementation

`READY_FOR_ADAPTIVE_IMPLEMENTATION` の場合だけ、tracked handoff path と original Plan / Implementation Intent を `adaptive-implementation-execution` へ渡す。

Adaptive Implementation に対する invariant:

> decision-surface-implementation-owner は通常の adaptive implementation と同じ authority を維持する。original Plan / Implementation Intent、repository policy、`Upstream Binding Constraints` は既存の binding input として守る。Design Pair が今回新たに作る binding decision は、handoff の有効な `Locked Decisions` だけとし、それ以外の実装判断は実コードと verification evidence に基づいて自由に行う。

Target Map、`Discussed but Unlocked`、`Adaptive-Owned`、Known Evidence、Known Assumptions、Knowledge Candidates は参考情報であり、decision-surface-implementation-owner の裁量または edit surface を拘束しない。

Design Pair 由来の Locked Decisions は Decision ID と origin を保持し、decision-surface-implementation-owner の追加 locked decisions と統合して Bounded Residual Implementation Handoff へ渡す。bounded-residual-implementation-owner はその統合済み一覧を守る。

Locked Decision と actual code が衝突した場合、decision-surface-implementation-owner は黙って変更せず `HUMAN_DECISION_REQUIRED`、`REPLAN_REQUIRED`、または適切な既存 stop verdict で停止する。automatic Design Pair re-entry は行わない。

## Evaluation record

説明効率は同じ課題・モデル・実行条件で、初回資料の作成から最終dispositionまでの全行程を比較する。説明不足解消だけの往復、重複した調査・記録更新、input / output / reasoning / cached tokensを取得可能な範囲でturn別・総計に記録する。cachedがinputの内数か、reasoningがoutputの内数かを明示して二重計上しない。取得不能はUnknown、未実施はNOT RUNとし、初回だけの短縮や後続turnへの移転を改善の証明にしない。実測なしに削減効果を断定しない。

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

待機中の会話は資料への導線、当該質問への回答・判断差分、verdict / stage、必要な次の利用者判断に絞る。以下は完了時のhandoff項目であり、各turnの会話への全文出力や派生集合の再計算を要求しない。

- Design Pair verdict
- interaction stage
- implementation route metadata
- upstream source references
- tracked handoff path
- Target Map summary
- Target Map presentation / user response evidence
- Selected Target Discussion Evidence とuser-facing turn reference
- selected / Adaptive-delegated / No-Change / Upstream-Decision-Required / pending Target IDs と Target Map 集合照合 evidence
- Upstream Binding Constraints
- Locked Decision IDs
- Discussed-Unlocked / Adaptive-Owned items
- blocking upstream decisions, if any
- next action: Adaptive Implementation / human decision / replan / blocked
- production code / tests edited during Design Pair: `No`
- final review status: `Not performed by this flow`
