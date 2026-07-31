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

fresh Codex installではAdaptive packageとDesign Pair packageをco-installし、APMがmodel-less agent TOMLを生成する環境では`install-adaptive-implementation-local.cs`のwriteと`--check`まで実行します。Design Pair skillが存在するだけでは、後段のHIGH / STANDARD model mappingが完成したとは扱いません。

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

Design Pair package は Copilot target を宣言しません。Plan Coverage package が Copilot target を持っていても、Design Pair route は Codex / agent-skills で両 package を導入した場合だけ利用します。

## Resume

`implementation_route`、`implementation_route_source`、`design_pair_handoff`、`design_pair_interaction_stage`はdurable artifactから再読します。Design Pair resume では Target Map presentation、Target 選択要求、post-map user response、disposition、Locked confirmation evidence も検証します。欠ける、矛盾する、またはwaiting中なのにREADYへ正規化されている場合、upstream textから補完せず`BLOCKED` / `BlockedByInvalidCompletionHandoff`としてartifact repairを要求します。3 route項目を`adaptive / default / N/A`へ自動初期化できるのはfresh intakeだけです。

STANDARD_MODELからHIGH_MODELへre-entryする場合は、High-model Re-entry Handoffに両route fieldとDesign Pair handoff pathをincoming completion handoffから変更せずコピーします。parentは元のcompletion handoffとre-entry handoffの両方をHIGH_MODELへ渡し、route identityが一致しない場合は再実行前に`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止します。HIGH_MODELとSTANDARD_MODELは通常完了を含む非invalid resultで同じ3項目を返します。invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを返し、parentは完全なpairを要求せず停止resultとして受理します。

## Target Map discussion

AI は予定変更面全体を bounded に調査し、具体的な file / symbol、現在の責務、current invariant、requested change との関係、内部設計判断候補、evidence、不明点を説明します。初回 turn は handoff に `AWAITING_USER_INPUT / target-selection` を保存し、利用者へ Target ID、初期案、未選択 Target の Adaptive delegation を求めて必ず終了します。「実装してください」という初回依頼はこの post-map response の代わりになりません。

利用者は議論したい Target を選び、初期案を提示します。その後、AI が trade-off、反論、代替案、追加 evidence、validation expectation を返します。

選択可能な disposition:

- `Locked`
- `Discussed-Unlocked`
- `Adaptive-Owned`
- `No-Change`
- `Upstream-Decision-Required`

`Locked` は Target Map 提示後に AI が trade-off と validation expectation を説明し、その後の user message / turn で明示確認された Decision ID 付き entry だけです。Plan / Issue / acceptance / gold document / AI summary は confirmation ではありません。利用者が初回 prompt に書いた技術案は initial position として保存し、post-map confirmation まで Locked にしません。

利用者が Target と初期案だけを返した場合、AI は evidence、反論または支持、代替案、trade-off、production wiring / lifecycle / state ownership / test seam への影響、validation expectation を提示し、`AWAITING_USER_INPUT / disposition-confirmation` で再停止します。利用者が Target Map 提示後に全 Target を Adaptive へ委ねると明示した場合は、個別議論なしで `Adaptive-Owned` として READY にできます。

親フローや検証harnessは利用者の応答を補完しません。Target IDだけのpartial selectionを受けた場合、Skillはcode evidenceと判断候補を説明して不足する初期案や未選択Targetの委任方針を尋ね、`AWAITING_USER_INPUT / target-selection`を維持します。必要項目が揃う前に`disposition-confirmation`へ進めず、`design-discussion`等の独自stageを作りません。各turnの保存前にheader、Target Map、summary集合、Readiness Checkを再計算し、post-map user responseの有無とreferenceを一致させます。

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
- `Locked` の confirmation が Plan / Issue を参照する: `Upstream Binding Constraints` へ移し、actual user turn evidence を要求する。
- resume artifact が `DRAFT` のみで interaction stage 不明: READY を推測せず artifact repair で停止する。
