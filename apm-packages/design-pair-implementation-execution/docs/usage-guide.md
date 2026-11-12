# Usage Guide

## Route selection

通常経路は次の metadata を使用します。

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
```

利用者が Design Pair を明示した場合だけ次へ変更します。

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
```

agent / router は difficulty、risk、task size、architecture 特性から Design Pair を選択、推奨、提案しません。

fresh installではAdaptive packageとDesign Pair packageをco-installします。GitHub Copilot CLIでは`--target copilot,agent-skills`、Codexでは`--target codex,agent-skills`を使います。CodexでAPMがmodel-less agent TOMLを生成する環境では共通 finalizerのwriteと`--check`まで実行します。Design Pair skillが存在するだけでは、後段の 子bounded-residual-implementation-ownerのmodel mappingが完成したとは扱いません。

## Ordinary Plan Mode

```text
$design-pair-implementation-execution を明示的に使います。
plans/issue-123.md を読み、判断する問い・事実と制約・選択肢の違い・暫定提案・不明点を資料にしてください。
資料を読んで直接質問・確定・スキップを回答します。
```

goal、scope、acceptance が不足する場合は production code / tests を編集せず、上流判断へ戻します。

## Plan Coverage Flow

1. flow 開始時に Design Pair を明示選択し、route metadata を durable artifact / resume state に保存する。
2. 通常の Plan Coverage pre-implementation gates を完了する。
3. `implementation-handoff-review` または equivalent Inline Ready Gate が READY の場合だけ Design Pair を開始する。
4. Target Map 提示後は `AWAITING_USER_INPUT / target-selection` と handoff path を parent state に保存し、その turn を終了する。
5. user discussion 後に最終 disposition がなければ `AWAITING_USER_INPUT / disposition-confirmation` を保存して再停止する。
6. tracked Design Pair handoff が `interaction_stage: complete` かつ `READY_FOR_ADAPTIVE_IMPLEMENTATION` になった後だけ、現在の親がdecision-surface-implementation-owner契約を読み、構造コード・build・人への提示停止を行う。実承認後だけ子へ渡す。
7. verification-kernel、coverage gap handling、residual-decision-gate へ戻る。

Design Pair package の正式 target は `copilot`、`codex`、`agent-skills` です。Plan Coverage 経由でも Design Pair route は両 package を同じ target へ導入し、利用者が Design Pair を明示選択した場合だけ使います。GitHub Copilot CLI では tracked handoff を durable authority とし、READY 後は 現在の親sessionでAdaptiveを開始します。Plan Coverage parent と Design Pair を組み合わせた runtime qualification は Plan Coverage 側の Copilot CLI 認定 issue で実施します。

## Resume

`implementation_route`、`implementation_route_source`、`design_pair_handoff`、`design_pair_interaction_stage`はdurable artifactから再読します。Design Pair resume では資料節・版・提示turn、直接対話の案内、post-map user response、正本rowのdisposition、Locked confirmation evidenceも検証します。待機中のsummary / ReadinessがPendingであるだけなら再開できます。正本が欠ける、矛盾する、またはwaiting中なのにREADYへ正規化されている場合、upstream textから補完せず`BLOCKED` / `BlockedByInvalidCompletionHandoff`としてartifact repairを要求します。3 route項目を`adaptive / default / N/A`へ自動初期化できるのはfresh intakeだけです。

bounded-residual-implementation-ownerからdecision-surface-implementation-ownerへre-entryする場合は、Decision-Surface Re-entry Handoffに両route fieldとDesign Pair handoff pathをincoming completion handoffから変更せずコピーします。元親自身がcompletion handoffとre-entry handoffの両方を読み、route identityが一致しない場合は再実行前に`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止します。親は構造待機/委譲result、子は通常完了を含む非invalid resultで同じ3項目を返します。invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを返し、parentは完全なpairを要求せず停止resultとして受理します。

## Target Map discussion

AIは予定変更面をboundedに調査し、tracked handoffを一まとまりの判断資料として提示します。問い一覧の各IDから、問い・必要性→調査済み事実と制約→実在する選択肢とtrade-off→非binding proposalまたはNo proposal理由→不明点・検証期待を読めます。具体的file / symbol、現在の責務・invariant、caller / wiring / lifecycle / test seamと根拠も同じ資料へ記録します。1ファイル＝1IDではなく独立して判断・委任できる論点が単位であり、機械的な追随は関連論点へ含めます。初回から全詳細設計を行うのではなく、調査で不明な点は不明とします。

会話では資料への導線と各問いの主要な判断上の違い・不明点を要約し、直接質問・反論・案・確定・スキップを案内して `AWAITING_USER_INPUT / target-selection` で必ず停止します。資料の全面再掲は不要ですが、リンクやIDと論点名だけでは提示になりません。「実装してください」という初回依頼はpost-map responseの代わりになりません。

初回後の応答例:

```text
A案では、既存のキャンセル伝播を維持できないのでは？
DP-T01は資料のA案で確定します。
DP-T02は議論をスキップします。
残りはスキップします。
全部スキップします。
```

これらは別々の入力例です。事前のID選択は不要で、対象を特定できないときだけ確認します。IDだけの入力も受理し、初期案や同じTarget選択を再要求せず、資料の判断上の違いを短く示して最終判断を待ちます。具体的質問には該当根拠で回答し、既出の説明一式を再掲しません。

スキップはその論点のDesign Pair対話を行わず判断をAdaptiveへ委ねる `Adaptive-Owned` であり、実装省略や `No-Change` ではありません。「残り」は未確定・未委任のTargetです。全件スキップに既存Locked等が含まれる場合、撤回の意図が不明なら確認します。実際の対象IDとuser evidenceを残し、未指示TargetをAIが委任しません。

選択可能な disposition:

- `Locked`
- `Discussed-Unlocked`
- `Adaptive-Owned`
- `No-Change`
- `Upstream-Decision-Required`

`Locked` は初回資料を含む判断材料の提示後に、user message / turnで決定内容を明示確定したDecision ID付きentryだけです。資料節・版・提示turnと確定証拠を結び付け、儀礼的な「選択→同じ説明→再確認」を要求しません。Plan / Issue / acceptance / gold document / AI summaryはconfirmationではありません。初回promptの技術案はinitial positionとして保存し、post-map confirmationまでLockedにしません。

`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`は、Targetごとの`Target Disposition Evidence`にactual post-map user turn、確認内容、`Confirmation after Target Map: Yes`がある場合だけ確定できます。AIが未選択Targetを自己判断でAdaptiveへ委ねたり、最終応答なしでDiscussed-Unlockedへ移したりできません。複数Target委任またはall-Adaptiveでは同じuser turnを複数Target rowに使用できます。

質問・初期案・IDのみでは最終dispositionとせず `AWAITING_USER_INPUT / disposition-confirmation` で再停止します。親フローや検証harnessは利用者応答を補完しません。未選択Targetの委任・分類は必要な最終判断と同時に確認します。初回後の全件委任が明示された場合は個別対話なしにREADYへ進めますが、完了時照合は省略できません。

`Selected Target Discussion Evidence`は具体的根拠のある資料節・版・提示turnと実際のpost-map user responseを参照します。質問・回答の差分は論点節へ保存し、説明を多重転記しません。新案・情報不足・関連code / upstream変更時だけ必要範囲を追加調査します。判断に影響する更新は再提示し、旧確定をpendingに戻して再確認します。

対話中は更新した論点・row・証拠とlatest response / stage等を差分更新し、summary集合とReadinessは `Finalization status: Pending` として未計算のまま保ちます。完了時だけ同じ現行証拠から全summary/checkを作成して照合します。途中のPendingや過去のPASSをREADYの証拠として流用しません。

READY判定ではTarget MapのIDを一意な全集合とし、handoff summaryの`Selected Target IDs`、`Delegated-to-Adaptive Target IDs`、`No-Change Target IDs`、`Upstream-Decision-Required Target IDs`、`Pending human-owned Target IDs`を照合します。全summary IDがMapに実在し、5集合が互いに素で、和集合がMap全体と一致し、各集合がrow Dispositionと一致しなければなりません。`Selected`は`Locked` / `Discussed-Unlocked`、delegatedは`Adaptive-Owned`、残り3集合は同名Dispositionまたはpending Dispositionへ対応します。

Locked DecisionのTarget IDはSelected集合に含まれ、rowが`Locked`である必要があります。explicit all-Adaptiveでは`Selected Target IDs: None`、`Pending human-owned Target IDs: None`、Locked Decisionsなし、全rowが`Adaptive-Owned`、delegated集合がMap全体と一致する場合だけREADYにできます。

全照合後に `Finalization status: Validated` と `complete / READY_FOR_ADAPTIVE_IMPLEMENTATION` を同時に設定します。Adaptive受入でも資料参照・post-map人間証拠・全集合・Locked/upstream整合・pending不在を検証します。

## Handoff semantics

tracked handoff は `plans/<slug>-design-pair-implementation-handoff.md` に保存します。

- binding: `Locked Decisions` の explicit entry だけ
- binding but not Design Pair decisions: `Upstream Binding Constraints`
- non-binding pre-map input: `Upstream User Initial Positions`
- advisory: Target Map、Discussed but Unlocked、Adaptive-Owned、Known Evidence、Known Assumptions、Knowledge Candidates
- not an allowed edit surface: Target Map と `Affected files / symbols`

decision-surface-implementation-owner は advisory 情報を参考にできますが、Locked Decisions 以外の実装判断 authority を維持します。

## Conflict handling

Locked Decision が actual code、production wiring、dependency evidence、または upstream acceptance と衝突した場合、decision-surface-implementation-owner は Decision ID、code evidence、worktree state、checks、必要な人間判断を報告して停止します。Locked Decision を黙って変更せず、automatic Design Pair re-entry も行いません。

## Completion boundary

Design Pair route の実装完了は final code review、human review、総合 architecture review、独立 verification の完了を意味しません。実行済み verification と未検証範囲を分けて報告します。

## Troubleshooting

- `READY_FOR_ADAPTIVE_IMPLEMENTATION` だが post-map user response がない: invalid handoff。`target-selection` waiting state へ修復する。
- selected Target が空で readiness が PASS: invalid handoff。明示的な all-Adaptive delegation がない限り FAIL とする。
- summaryに架空ID、重複ID、未分類Target、row / summary不一致がある: invalid handoff。Target Mapと5集合を修復する。
- all-AdaptiveなのにSelected / Pendingが`None`でない、Locked Decisionがある、またはAdaptive-Ownedでないrowがある: invalid handoff。
- Selected / Delegated Targetの`Target Disposition Evidence`が欠落、重複、架空ID、row不一致、pre-map reference、AI summary由来: invalid handoff。
- `Locked` の confirmation が Plan / Issue を参照する: `Upstream Binding Constraints` へ移し、actual user turn evidence を要求する。
- resume artifact が `DRAFT` のみで interaction stage 不明: READY を推測せず artifact repair で停止する。

Copilot CLIの非対話入力でAdaptiveへ進む際は、現在の親sessionへ明示選択と導入済み .agents/skills/adaptive-implementation-execution/SKILL.md の読込みを指定します。slash名だけの未読実行をAdaptiveとして扱わず、別上位processへ切り替えません。
