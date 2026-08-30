---
name: adaptive-implementation-execution
description: Use only when the user explicitly invokes this skill with /adaptive-implementation-execution. Do not select for ordinary implement-this-plan requests or natural-language mentions.
user-invocable: true
disable-model-invocation: true
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Adaptive Implementation Execution

このskillは利用者が`/adaptive-implementation-execution`で明示起動した場合だけ使用する。通常の実装依頼や自然文での名前言及では選択しない。

通常のPlan、手書きPlan、repository-tracked Plan、Issue内の実装計画、または明示選択されたDesign Pair Implementation Handoffを入力に、実装中のdecision surfaceに応じてsemantic ownerを直列に切り替えるimplementation-only flowです。

Plan Coverageの縮小版ではありません。Plan Coverage artifacts、change-risk-triage、runtime contract、test design、coverage ledger、residual decisionは必須入力にしません。

## Semantic roles

- `Decision-Surface Implementation Owner`: unresolved decision surfaceが残る間、code inspection、production code、tests、wiring、focused verification、影響再確認を含むimplementation feedback loopを所有する。
- `Bounded-Residual Implementation Owner`: decision surfaceがactual codebase evidenceによって解消され、locked contract / semanticsの適用だけで完了できるbounded residual workを所有する。

semantic roleはHIGH / STANDARD等のconcrete model tier、parent / subagent、別process、VS Code handoff button等のruntime topologyから独立しています。runtime adapterは各roleへmodelを割り当てますが、topologyやmodel名によってownershipを再定義してはいけません。

## Parent / router role

parent / routerは次だけを担当します。

- inputのsource of truthとImplementation Intentを確認する
- semantic ownerを直列に起動する
- verdictとhandoff contractを検証する
- re-entry時に元intent、両handoff、route identityを保持する
- 最終状態と未検証事項を集約する

dedicated routerとして動作するruntime roleはimplementation editを行わず、write-heavy ownerを並列に起動しません。ただし、top-level parent自身へ`Decision-Surface Implementation Owner`を割り当て、orchestration responsibilityとsemantic ownershipを同じruntime instanceが兼ねる構成は許容します。parentというruntime位置だけを理由にimplementation ownershipを付与または禁止してはいけません。

## Accepted inputs

- 通常Plan Mode output
- repository-tracked Plan
- callerの短い実装計画
- Issue / prompt内のgoal、scope、acceptance、constraints
- 明示選択されたDesign Pair Implementation Handoff

`goal`、`scope`、`acceptance`は必須です。`non_goals`、`constraints`、`validation`、`plan_reference`は任意です。validation未指定時はrepository standardを採用し、`Validation expectation: inferred from repository`と記録します。source requestから導けないnon-goalをexisting codeから推測してscopeを狭めません。

入力不足で変更対象、scope、完了条件を判断できない場合は`REPLAN_REQUIRED`または`HUMAN_DECISION_REQUIRED`で停止します。

## Route identity and Design Pair

fresh Adaptive intakeだけ次を初期化します。

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
```

resumeではdurable stateから読み、欠落や矛盾をAdaptiveへ補完しません。旧0.5 handoff、旧agent名、部分的な新旧schemaも互換normalizationせず、`BLOCKED / BlockedByInvalidCompletionHandoff`とします。

Design Pair routeは`implementation_route: design-pair`、`implementation_route_source: explicit-user-selection`を要求します。handoffの`READY_FOR_ADAPTIVE_IMPLEMENTATION`、complete interaction stage、Target Map提示・選択要求・post-map user response、valid selectionまたはall-Adaptive delegation、pendingなし、集合完全性、Target Disposition Evidence、Selected Target Discussion Evidence、Locked Decision confirmationを編集前に検証します。

欠落、矛盾、waiting、空集合PASS、架空・重複・未分類ID、row / summary不一致、pre-map evidence、AIが再構成したuser responseは拒否します。Design Pairが今回作るbinding decisionはvalidな`Locked Decisions`だけです。Target MapやAffected files / symbolsはAllowed edit surfaceではありません。

## Required execution order

```text
ordinary Plan / short implementation intent
  or explicit Design Pair Implementation Handoff
  -> decision-surface-implementation-owner
       -> CONTINUE_DECISION_SURFACE_IMPLEMENTATION
       -> IMPLEMENTATION_COMPLETED
       -> READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION
            -> bounded-residual-implementation-owner
                 -> IMPLEMENTATION_COMPLETED
                 -> NEEDS_DECISION_SURFACE_REENTRY
                      -> decision-surface-implementation-owner
       -> REPLAN_REQUIRED / HUMAN_DECISION_REQUIRED / BLOCKED
```

すべての非自明なimplementationはDecision-Surface Implementation Ownerから開始します。課題規模、risk、ファイル数、作業種別だけを理由にBounded-Residual Implementation Ownerへ直行してはいけません。

## Runtime adapters

- Codex: portable semantic contractを使い、repository-local profileが各roleへconcrete modelを割り当てる。
- GitHub Copilot Chat in VS Code: `decision-surface-implementation-owner`は`GPT-5.6 Terra (copilot)`、`bounded-residual-implementation-owner`は`GPT-5.6 Luna (copilot)`を要求する。
- GitHub Copilot CLI: agent切替が必要なら新processとtracked handoffを使う。

これらはruntime topology / model mappingであり、semantic ownershipの定義ではありません。handoff buttonは手動遷移候補で、verdictを検証するrouterではありません。

## Step 1: Validate intent

1. repository instructionsとuser constraintsを確認する。
2. goal、scope、acceptance、任意項目を抽出する。
3. missing informationがimplementation detailかproduct / scope / acceptance decisionか分ける。
4. route identityとDesign Pair evidenceを検証する。
5. invalid inputは実装前にfail closedで停止する。

## Step 2: Start the Decision-Surface Implementation Owner

`decision-surface-implementation-owner`を一度だけ起動し、完了するまで待ちます。

渡すもの:

- Original Implementation Intent
- implementation_route
- implementation_route_source
- Design Pair handoff pathまたは`N/A`
- repository instructions
- current worktree status
- relevant source pointers
- validation expectations
- re-entry時は元のBounded Residual Implementation HandoffとDecision-Surface Re-entry Handoff
- Design Pair Decision IDs
- supplied Plan Coverage bindings

ownerはactual codeを読み、必要なproduction / test implementationとfocused verificationを行い、結果からdecision surfaceを再評価します。code editを避けることも、一定量のeditを行うことも目的にしません。

## Step 3: Validate the decision-surface verdict

全resultでroute identityがincoming stateと一致することを検証します。invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを受理して停止します。

### CONTINUE_DECISION_SURFACE_IMPLEMENTATION

同一runで続行可能ならownerにそのまま続行させます。細かく再起動しません。resumeやexecution boundaryが必要な場合だけstate verdictとして扱います。

### IMPLEMENTATION_COMPLETED

scope内の全acceptance itemが`Complete`で、各itemにimplementationまたはvalidation evidenceがある場合に受理します。最初のownerによる完了は例外ではなく、transfer理由やcode quotaを要求しません。

### READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION

`refs/handoff.md`の全fieldと次を検証します。

- `Ownership transfer basis: bounded-residual-work-only`
- Decision surface assessmentが全行`Resolved`または理由付き`N/A`
- actual code / implementation / verification evidenceがassessmentを裏付ける
- 残作業がlocked contract / semanticsの適用だけで完了できる
- acceptanceとWork Package mappingが双方向に一致する
- Allowed edit surfaceが全Authorized surfaceを包含する
- Design Pair / upstream bindingと矛盾しない
- 残る不確実性がlocalかつreversibleである

不足がある場合は次ownerへ渡さず、handoff修正またはimplementation継続を求めます。

### Stop verdicts

`REPLAN_REQUIRED`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`は理由、既実装、worktree state、次に必要なinputを保持して停止します。

## Step 4: Run the Bounded-Residual Implementation Owner

valid handoff後だけ`bounded-residual-implementation-owner`を直列に起動します。

渡すもの:

- Original Implementation Intent
- Bounded Residual Implementation Handoff
- current worktree status
- repository instructions
- Design Pair Decision IDsを含むLocked decisions
- Plan Coverage Slice Living Record adapter fields when applicable

ownerはWork PackagesとAllowed edit surface内で実装・検証します。class、wiring、tests等の作業種別ではなく、残作業がboundedかどうかがauthorizationです。

## Step 5: Handle bounded-residual result

### IMPLEMENTATION_COMPLETED

全acceptance itemとevidence、route identity、Locked Decision complianceを検証してcallerへ返します。

### NEEDS_DECISION_SURFACE_REENTRY

valid handoffの実装中に新しいdecision surfaceが開いた場合だけ受理します。元のBounded Residual Implementation Handoff、Decision-Surface Re-entry Handoff、Original Implementation Intent、current worktreeを保持し、route identity一致を確認してDecision-Surface Implementation Ownerへ直列に戻します。

re-entryは失敗ではありません。戻ったownerは新しいdecision surfaceと必要なimplementation / verificationを所有します。再transferは、`reentry_count`を直前のre-entry handoffと一致させ、`previous_reentry_trigger`と`reentry_progress_evidence.trigger`をそのtriggerへ一致させ、actual codeによる`resolution`、確認結果である`verification`、`same_unresolved_cause_rehanded_off: false`を記録し、通常のtransfer gateを改めてすべて満たす場合に許可します。Remaining workやAllowed edit surfaceが前回より広がること自体はtransfer拒否理由にしません。

invalid handoff、route identity欠落、単なるedit typeにはre-entryを使いません。

### Other verdicts

`REPLAN_REQUIRED`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`はevidenceを保持して停止します。

## Serial write ownership

両semantic ownerを同時に起動しません。parent / routerも同じworktreeへ並列にimplementation editを行いません。

## Plan Coverage traceability

supplied binding artifactsがある場合、各ownerは自分のphaseで実際に変更した行だけの`Implementation Self-Map Delta`を返します。orchestratorがstable Change IDでcanonical recordへ集約します。standalone runではevidence-backed `N/A`で構いません。

## Final output

- final verdict
- Original Implementation Intent / Plan reference
- implementation_route
- implementation_route_source
- Design Pair handoff pathまたは`N/A`
- phase owner sequence
- implementation / validation evidence
- files changed
- acceptance status table
- Locked Decision compliance
- remaining uncertainty / manual validation
- final review status: `Not performed by this flow`
