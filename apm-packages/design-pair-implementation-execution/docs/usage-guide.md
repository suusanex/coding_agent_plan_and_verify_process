# Usage Guide

## Route selection

通常経路は次の metadata を使用します。

```yaml
implementation_route: adaptive
implementation_route_source: default
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
4. tracked Design Pair handoff が `READY_FOR_ADAPTIVE_IMPLEMENTATION` になった後、Adaptive Implementation を HIGH_MODEL から開始する。
5. verification-kernel、coverage gap handling、residual-decision-gate へ戻る。

Design Pair package は Copilot target を宣言しません。Plan Coverage package が Copilot target を持っていても、Design Pair route は Codex / agent-skills で両 package を導入した場合だけ利用します。

## Resume

`implementation_route`と`implementation_route_source`はdurable artifactから再読します。resume時に欠ける、矛盾する、またはDesign Pair evidenceがあるのにtracked handoffが欠ける場合、Adaptiveへ補完せず`BLOCKED` / `BlockedByInvalidCompletionHandoff`としてartifact repairを要求します。`adaptive / default`の自動初期化はfresh intakeだけです。

STANDARD_MODELからHIGH_MODELへre-entryする場合は、High-model Re-entry Handoffに両route fieldとDesign Pair handoff pathをincoming completion handoffから変更せずコピーします。parentは元のcompletion handoffとre-entry handoffの両方をHIGH_MODELへ渡し、route identityが一致しない場合は再実行前に`BLOCKED` / `BlockedByInvalidCompletionHandoff`で停止します。HIGH_MODELとSTANDARD_MODELは通常完了を含むすべてのresultで同じ3項目を返します。

## Target Map discussion

AI は予定変更面全体を bounded に調査し、具体的な file / symbol、現在の責務、requested change との関係、evidence、不明点を説明します。

利用者は議論したい Target を選び、初期案を提示します。その後、AI が trade-off、反論、代替案、追加 evidence、validation expectation を返します。

選択可能な disposition:

- `Locked`
- `Discussed-Unlocked`
- `Adaptive-Owned`
- `No-Change`
- `Upstream-Decision-Required`

`Locked` は explicit human confirmation と Decision ID がある entry だけです。Target Map の全項目を Locked にする必要はありません。

## Handoff semantics

tracked handoff は `plans/<slug>-design-pair-implementation-handoff.md` に保存します。

- binding: `Locked Decisions` の explicit entry だけ
- advisory: Target Map、Discussed but Unlocked、Adaptive-Owned、Known Evidence、Known Assumptions、Knowledge Candidates
- not an allowed edit surface: Target Map と `Affected files / symbols`

HIGH_MODEL は advisory 情報を参考にできますが、Locked Decisions 以外の実装判断 authority を維持します。

## Conflict handling

Locked Decision が actual code、production wiring、dependency evidence、または upstream acceptance と衝突した場合、HIGH_MODEL は Decision ID、code evidence、worktree state、checks、必要な人間判断を報告して停止します。Locked Decision を黙って変更せず、automatic Design Pair re-entry も行いません。

## Completion boundary

Design Pair route の実装完了は final code review、human review、総合 architecture review、独立 verification の完了を意味しません。実行済み verification と未検証範囲を分けて報告します。
