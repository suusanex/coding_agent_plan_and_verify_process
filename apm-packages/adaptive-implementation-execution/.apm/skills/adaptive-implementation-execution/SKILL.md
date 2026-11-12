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

利用者が`/adaptive-implementation-execution`で明示起動した場合だけ使用します。通常Planまたは明示的なDesign Pair handoffから、親の構造コード → 人の構造レビュー → 子の詳細実装を行います。Plan Coverage artifactsはstandaloneの必須入力ではありません。

## Semantic roles

- Decision-Surface Implementation Owner: 現在のトップレベル親自身。調査・構造コード・production build・提示・実応答待機・構造修正・委譲・再引受けを所有する。
- Bounded-Residual Implementation Owner: 承認済み構造の内側で本体・入力検査・例外送出・局所分岐/loop・private helper・test / mock / 検証を完成する子。

親はcanonical `decision-surface-implementation-owner.agent.md`を読み、自分の選択済みmodelで実行します。別の上位subagent、新しい上位CLI process、model pin・補完・切替を使用しません。親単独の全実装完了経路はありません。両者は同じworktreeを並列編集しません。

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

選択要求fieldは直接質問・確定・スキップの案内も表し、事前のID選択turnを要求しません。Selected Target Discussion Evidenceは具体的根拠を持つ初回資料節・版・提示turnと実際のuser response、必要な対話差分への参照を受け入れます。部分・残件・全件スキップは明示範囲のAdaptive-Ownedであり、No-Changeや実装省略ではありません。`Finalization status: Validated`と現行の全summary / Readiness整合を要求し、待機中のPendingまたは古いPASSを完了証拠にしません。判断に影響する資料変更後は旧confirmationを流用しません。

欠落、矛盾、waiting、空集合PASS、架空・重複・未分類ID、row / summary不一致、pre-map evidence、AIが再構成したuser responseは拒否します。Design Pairが今回作るbinding decisionはvalidな`Locked Decisions`だけです。Target MapやAffected files / symbolsはAllowed edit surfaceではありません。

## Required execution order

```text
Plan / explicit Design Pair READY
 -> current parent: inspect / compare / structure code / production build
 -> AWAITING_STRUCTURE_REVIEW (persist, present, END TURN)
 -> actual user response about the presented structure version
    -> revision requested: parent revises structure / builds / presents / END TURN
    -> approved AND handoff ready
       -> READY_FOR_BOUNDED_RESIDUAL_IMPLEMENTATION
       -> bounded-residual-implementation-owner
          -> IMPLEMENTATION_COMPLETED
          -> NEEDS_DECISION_SURFACE_REENTRY
             -> same parent: revise structure / build / present / END TURN
```

## 1. 親による構造コード

goal / scope / acceptance、repository指示とroute identity、Design Pair evidenceを編集前に検証します。canonical親契約の既存処理比較と成果物境界に従います。既存API / 拡張点 / 構造追従 / 別方式の根拠、参照file / symbol・呼出関係、要求差分・例外理由を既存evidenceへ残します。

責務境界の型とsignature、日本語XML契約（前提、エラー条件、保証/検査担当、違反表現、結果・副作用）、依存の生成・登録、主要な呼出順序とデータ受渡し・awaitを書きます。最小限の連携条件はコード化してよいが、詳細本体・条件計算・内部制御は子へ残します。末端NotImplementedExceptionは許容し、空結果・成功偽装・入口丸ごとの未実装は禁止です。既存完成処理を戻したり分担だけの抽象化を追加しません。

変更対象production projectと契約変更の影響を受けるproduction projectをbuildします。buildは静的整合確認であり動作・責務の正しさの証明ではありません。親のtest / mock / runtime DI / 詳細動作検証は必須にしません。

## 2. 人への提示と本当の停止

`refs/handoff.md`を用いtracked stateへStructure reviewとStructure readinessを保存します。対象コード状態・未実装・build対象を人へ示し、AWAITING_STRUCTURE_REVIEWとしてそのターンを終了します。実際の利用者応答まで作業や委譲を進めません。事前の実装指示、Design Pairのスキップ・Locked Decisions、AI生成応答を構造承認へ読み替えません。

resume時は提示版・snapshot・提示turnとその後の実応答原文/referenceを結合します。応答なしは待機のまま。古い版・矛盾・不足はfail closed。承認前にコードが変化した場合は差分を確認し、構造に影響すれば版を更新・再提示して停止します。意味不明の応答を承認と推測しません。

## 3. 承認とhandoff readinessを別々に検証

`Ownership transfer basis: human-approved-structure`を要求します。

- 構造の責務、共有契約・保証責務、依存、主要シーケンス、upstream整合が実コードから判断できる。
- 必要production buildが成功し、対象と結果がsnapshotに対応する。
- Structure reviewに提示後の実承認があり、承認対象の構造版が一致する。
- acceptanceとWork Package mappingが双方向に一致する。全Incompleteに残作業、全Completeに証拠がある。
- Allowed edit surfaceが全Authorized surfaceを包含する。子に残す詳細判断を明記する。
- 比較根拠と、実施済み構造diffの照合結果・子が行うCompletion checkを区別する。
- 初回transferは`reentry_count: 0`、previous_reentry_triggerとreentry_progress_evidenceの各値はN/A。

テスト設計・seam / harness、入力検査処理、内部error / cancellation / retry制御はDeferred to childです。旧全decision surfaceのResolved条件を使いません。要件が求めるクラス間連携だけを親の構造に含めます。未解決の構造契約・上流矛盾・build失敗・artifact不足を、親による詳細実装で埋めません。

不足はhandoff修正または構造修正で対処します。構造の実質変更は再提示・停止が必要です。承認があってもreadiness不足なら子を起動しません。ほぼ全て既存再利用でも同じ停止を行い、残る確認・完了処理を子へ渡します。

## 4. 子による詳細実装

valid handoff後だけ`bounded-residual-implementation-owner`を直列に起動し、元intent、tracked state、worktree、repository規約、Locked Decisions、supplied bindingsを渡します。ownerはWork PackagesとAllowed edit surface内で実装・検証します。親は並列編集しません。

子の局所設計・追加修正は再承認不要です。IMPLEMENTATION_COMPLETEDは子の全acceptance Completeと実装・検証証拠、route identity、Locked Decision compliance、引き継いだ比較に対するactual diffの実装後照合結果を確認して受理します。親による詳細code review全体を新しい必須工程にしません。

## 5. 構造変更の再引受け

NEEDS_DECISION_SURFACE_REENTRYは合意済みI/F・共有型、責務、依存、主要シーケンス、保証責務の実質変更が必要な場合です。単なるedit typeや局所test設計では戻しません。triggerが空白/N/Aでなく、reentry_countが直前handoff+1、元intent・両handoff・route identity・Locked Decisionsが維持されていることを確認します。不正ならBLOCKEDで停止します。

元の親が構造修正・build・必要な再レビューを行い、詳細は引き取りません。再transferではcountを直前re-entryに合わせ、previous_reentry_triggerとreentry_progress_evidence.triggerを一致させます。resolution、verification、same_unresolved_cause_rehanded_off: falseを記録し、新版の実承認と通常readinessを再確認します。残作業範囲の縮小は要求しません。

## Runtime adapters

Codex、GitHub Copilot CLI、VS Codeとも親は現在sessionの選択済みmodelを使います。親agent定義にmodelを置かず、子だけCodex overlay / Copilot frontmatterのmodelを使います。CLIの新processは承認後の子実行に限り、上位別起動を標準経路にしません。再引受けは元親への返却です。子を安全に直列起動できないruntimeはBLOCKEDとして制約を報告し、親による詳細代行へfallbackしません。

## Plan Coverageと永続化

supplied bindingがあれば各phaseのImplementation Self-Map Deltaを返し、親がstable Change IDで集約します。standaloneでは根拠付きN/A。Living Record modeは既存record内にStructure reviewを保存し、追加handoff fileは事前登録されたArtifact Exceptionsに従います。子のUNPERSISTED_PARENT_PAYLOADは親がrouteを検証・登録・保存してから再開します。inline-onlyの待機は不可です。

## Final output

verdict、intent / Plan、route identity、Design Pair path、親/子sequence、構造版・承認証拠、buildと子のvalidation、比較・実装後照合、files changed、acceptance、Locked Decision compliance、未確認事項を報告します。final review statusは`Not performed by this flow`です。REPLAN_REQUIRED / HUMAN_DECISION_REQUIRED / BLOCKEDは証拠と次に必要な情報を残し停止します。
