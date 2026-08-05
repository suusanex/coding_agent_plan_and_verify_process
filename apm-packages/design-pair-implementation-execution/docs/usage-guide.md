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

fresh installではAdaptive packageとDesign Pair packageをco-installします。GitHub Copilot CLIでは`--target copilot,agent-skills`、Codexでは`--target codex,agent-skills`を使います。CodexでAPMがmodel-less agent TOMLを生成する環境では`install-adaptive-implementation-local.cs`のwriteと`--check`まで実行します。Design Pair skillが存在するだけでは、後段のHIGH / STANDARD model mappingが完成したとは扱いません。

## Ordinary Plan Mode

```text
$design-pair-implementation-execution を明示的に使います。
plans/issue-123.md を読み、予定変更面の Target Map を作ってください。
まず現在の構造と判断論点を説明し、私の初期案を聞いてから議論してください。
```

goal、scope、acceptance が不足する場合は production code / tests を編集せず、上流判断へ戻します。

## Plan Coverage Flow

1. flow 開始時に Design Pair を明示選択し、route metadata を durable artifact / resume state に保存する。
2. 通常の Plan Coverage pre-implementation gates を完了する。
3. `implementation-handoff-review` または equivalent Inline Ready Gate が READY の場合だけ Design Pair を開始する。
4. Target Map 提示後は `AWAITING_USER_INPUT / target-selection` と handoff path を parent state に保存し、その turn を終了する。
5. user discussion 後に最終 disposition がなければ `AWAITING_USER_INPUT / disposition-confirmation` を保存して再停止する。
6. tracked Design Pair handoff が `interaction_stage: complete` かつ `READY_FOR_ADAPTIVE_IMPLEMENTATION` になった後だけ、Adaptive Implementation を HIGH_MODEL から開始する。
7. verification-kernel、coverage gap handling、residual-decision-gate へ戻る。

Design Pair package の正式 target は `copilot`、`codex`、`agent-skills` です。Plan Coverage 経由でも Design Pair route は両 package を同じ target へ導入し、利用者が Design Pair を明示選択した場合だけ使います。GitHub Copilot CLI では tracked handoff を durable authority とし、READY 後だけ Adaptive agents を開始します。

## Resume

`implementation_route`、`implementation_route_source`、`design_pair_handoff`、`design_pair_interaction_stage`はdurable artifactから再読します。Design Pair resume では Target Map presentation、Target 選択要求、post-map user response、disposition、Locked confirmation evidence も検証します。欠ける、矛盾する、またはwaiting中なのにREADYへ正規化されている場合、upstream textから補完せず`BLOCKED` / `BlockedByInvalidCompletionHandoff`としてartifact repairを要求します。3 route項目を`adaptive / default / N/A`へ自動初期化できるのはfresh intakeだけです。

STANDARD_MODELからHIGH_MODELへre-entryする場合は、High-model Re-entry Handoffに両route fieldとDesign Pair handoff pathをincoming completion handoffから変更せずコピーします。parentは元のcompletion handoffとre-entry handoffの両方をHIGH_MODELへ渡し、route identityが一致しない場合は再実行前に`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止します。HIGH_MODELとSTANDARD_MODELは通常完了を含む非invalid resultで同じ3項目を返します。invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを返し、parentは完全なpairを要求せず停止resultとして受理します。

## Target Map discussion

AI は予定変更面全体を bounded に調査し、具体的な file / symbol、現在の責務、current invariant、requested change との関係、内部設計判断候補、evidence、不明点を説明します。初回 turn は handoff に `AWAITING_USER_INPUT / target-selection` を保存し、利用者へ議論する Target IDを求めて必ず終了します。初期案、懸念、質問、未選択 Target の Adaptive delegationは任意で併記できます。「実装してください」という初回依頼はこの post-map response の代わりになりません。

この説明はuser-facing responseそのものに各Targetのfile / symbol、responsibility / invariant、変更との関係、判断候補、expected modification / verification、evidence、open questionを含めます。handoffへのlink、Target ID、論点名だけの一覧は完全なTarget Map提示ではありません。

実際の応答では7列の`Design Pair Target Map` table、Coverage evidence、Selection requestを省略せず出力します。handoffだけを詳細にし、最終応答を短いTarget一覧へ圧縮した場合はpresentation FAILです。選択後の対話では`<DP-Txx> Internal design discussion` blockのCode location、invariant、関連surface、判断、alternatives / trade-offs、proposal、validation、open questionsをすべて提示します。

利用者は議論したい Target を選びます。初期案、懸念、質問は任意で併記できます。その後、AI がcode evidence、trade-off、反論または支持、代替案、非binding proposal、追加 evidence、validation expectation を返します。

選択可能な disposition:

- `Locked`
- `Discussed-Unlocked`
- `Adaptive-Owned`
- `No-Change`
- `Upstream-Decision-Required`

`Locked` は Target Map 提示後に AI が trade-off と validation expectation を説明し、その後の user message / turn で明示確認された Decision ID 付き entry だけです。Plan / Issue / acceptance / gold document / AI summary は confirmation ではありません。利用者が初回 prompt に書いた技術案は initial position として保存し、post-map confirmation まで Locked にしません。

`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`は、Targetごとの`Target Disposition Evidence`にactual post-map user turn、確認内容、`Confirmation after Target Map: Yes`がある場合だけ確定できます。AIが未選択Targetを自己判断でAdaptiveへ委ねたり、最終応答なしでDiscussed-Unlockedへ移したりできません。複数Target委任またはall-Adaptiveでは同じuser turnを複数Target rowに使用できます。

利用者が Target だけ、または Target と初期案を返した場合、AI は evidence、反論または支持、代替案、trade-off、production wiring / lifecycle / state ownership / test seam への影響、非binding proposal、validation expectation を提示し、`AWAITING_USER_INPUT / disposition-confirmation` で再停止します。利用者が Target Map 提示後に全 Target を Adaptive へ委ねると明示した場合は、個別議論なしで `Adaptive-Owned` として READY にできます。

親フローや検証harnessは利用者の応答を補完しません。Target Mapに実在するTarget IDだけでも選択成立です。Skillは選択Targetのcode evidence、判断候補、alternatives / trade-offs、非binding proposal、validation expectationを説明し、初期案の提示や同じTarget選択を再要求せず`AWAITING_USER_INPUT / disposition-confirmation`へ進みます。未選択Targetの委任または分類は、選択Targetの最終dispositionと同じ確認で求めます。`design-discussion`等の独自stageを作りません。各turnの保存前にheader、Target Map、summary集合、Readiness Checkを再計算し、post-map user responseの有無とreferenceを一致させます。

ここでいうcode evidenceは抽象的な論点名ではありません。選択Targetごとに具体的file / symbol、current responsibility / invariant、caller / wiring / lifecycle / test seam、内部設計判断の必要性、代替案とtrade-off、既存codeに基づく非binding proposalまたはNo proposal理由、validation expectationをuser-facing responseへ出します。同じ内容とassistant turn referenceを`Selected Target Discussion Evidence`へ保存します。

READY判定ではTarget MapのIDを一意な全集合とし、handoff summaryの`Selected Target IDs`、`Delegated-to-Adaptive Target IDs`、`No-Change Target IDs`、`Upstream-Decision-Required Target IDs`、`Pending human-owned Target IDs`を照合します。全summary IDがMapに実在し、5集合が互いに素で、和集合がMap全体と一致し、各集合がrow Dispositionと一致しなければなりません。`Selected`は`Locked` / `Discussed-Unlocked`、delegatedは`Adaptive-Owned`、残り3集合は同名Dispositionまたはpending Dispositionへ対応します。

Locked DecisionのTarget IDはSelected集合に含まれ、rowが`Locked`である必要があります。explicit all-Adaptiveでは`Selected Target IDs: None`、`Pending human-owned Target IDs: None`、Locked Decisionsなし、全rowが`Adaptive-Owned`、delegated集合がMap全体と一致する場合だけREADYにできます。

## Handoff semantics

tracked handoff は `plans/<slug>-design-pair-implementation-handoff.md` に保存します。

- binding: `Locked Decisions` の explicit entry だけ
- binding but not Design Pair decisions: `Upstream Binding Constraints`
- non-binding pre-map input: `Upstream User Initial Positions`
- advisory: Target Map、Discussed but Unlocked、Adaptive-Owned、Known Evidence、Known Assumptions、Knowledge Candidates
- not an allowed edit surface: Target Map と `Affected files / symbols`

HIGH_MODEL は advisory 情報を参考にできますが、Locked Decisions 以外の実装判断 authority を維持します。

## Conflict handling

Locked Decision が actual code、production wiring、dependency evidence、または upstream acceptance と衝突した場合、HIGH_MODEL は Decision ID、code evidence、worktree state、checks、必要な人間判断を報告して停止します。Locked Decision を黙って変更せず、automatic Design Pair re-entry も行いません。

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
