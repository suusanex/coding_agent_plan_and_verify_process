# Usage Guide

## 開始と親の担当

scope / acceptanceが分かるPlanを`/adaptive-implementation-execution`へ渡します。現在の親がcanonical親agent契約を読み、選択済みmodelで調査・構造コード・production buildを行います。別上位agentは起動しません。

既存API / 拡張点 / 構造追従 / 別方式を比較し、参照file / symbol・call site、要求差分、採用根拠、別方式の具体的不適合と例外範囲を記録します。新しい経路・状態は近傍以外の関連更新箇所・兄弟機能も調べ、局所修正は短い比較で足ります。見つからない場合は探索範囲と未発見事実を記します。

親の成果物は責務境界の型とXML契約、依存、主要なクラス間呼出順序と引数・結果・awaitです。内部条件計算や本体は子へ残し、末端NotImplementedExceptionで示します。入口全体の未実装や空結果による成功偽装は禁止です。既存完成処理は戻しません。

## 提示・停止・再開

親agentのfrontmatterは自動agent切替ボタンを提供しません。承認後は現在の親のsubagent/task呼出機能で子のcanonical契約とtracked handoffを渡し、子の返却を同じ親sessionで受け取ります。親子のUI切替をhandoff readinessや実承認の代用にしません。この呼出機能がないsurfaceでは子の開始前にBLOCKEDを返します。Copilot CLIのtask経路はruntime証跡を参照してください。VS Code UIの同等呼出経路は未検証です。

変更/影響production projectのbuild後、[handoff](../.apm/skills/adaptive-implementation-execution/refs/handoff.md)をtracked保存し、コードsnapshot・構造版・未実装・build対象を提示してAWAITING_STRUCTURE_REVIEWでそのターンを終了します。実際の応答がなければresumeしても待機します。

応答原文とturn、承認対象版を保存し、提示後の応答か、現在コードに構造変更がないか確認します。修正指示には親が構造修正・build・新版提示を行い、再び停止します。Design Pairのスキップは構造承認ではありません。

人の承認とStructure readinessは別条件です。構造契約・依存・sequence・保証責務が実コードから読め、production buildとhandoff mappingが整った場合だけ子へ渡します。test設計、入力検査、本体、内部error / cancellation / retry制御はDeferred to childで構いません。

## 子と再引受け

子はWork PackagesとAllowed edit surface内で詳細実装、tests / mock、検証、参照処理とactual diffの照合を完成します。追加状態、順序制御、既存serviceを迂回する直接呼出の必要性を確認します。局所変更は再承認不要です。

合意したI/F・共有型、責務、依存、主要sequence、保証責務が実質的に変わる場合だけNEEDS_DECISION_SURFACE_REENTRYで元親へ返します。親は構造修正とbuildと人への再提示・停止を行い、詳細を引き取りません。count / trigger / progress evidenceと元intent・両handoffを保持します。

## Route identity

fresh Adaptive intake:

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
```

Design Pair:

```yaml
implementation_route: design-pair
implementation_route_source: explicit-user-selection
design_pair_handoff: plans/<slug>-design-pair-implementation-handoff.md
```

resumeはdurable stateを維持します。欠落・矛盾・旧schemaをdefaultへ補完しません。Design PairのLocked Decisionsと既存upstreamを保持し、対話工程を再設計しません。Plan Coverageの場合も同じ親が構造担当となり、既存Living Recordへreview stateを保存します。

## Runtimeと完了

Codex / Copilot CLI / VS Codeとも親は現sessionを継続します。CLIで別processが必要なのは承認済みhandoffを持つ子実行です。子を起動できない場合はBLOCKEDで停止し、親による詳細代行へfallbackしません。

子の全acceptance Completeと実装・検証証拠を親が集約します。親自身の直接完了経路はありません。final review statusはNot performed by this flowです。静的検証、合成応答によるruntime試験、人が実際にレビューした運用確認を区別します。

### Copilot CLIの非対話起動

CLI 1.0.109の`-p`ではslash名だけの入力でSkillが読まれないケースを観測したため、明示選択と本文pathを一緒に渡します。`disable-model-invocation: true`は維持し、modelからskill toolを呼び出す必要はありません。

```powershell
copilot -p '/adaptive-implementation-execution を明示的に使用します。.agents/skills/adaptive-implementation-execution/SKILL.md を読み、その手順で plans/issue-123.md を実装してください。'
```

このpathはAPMのagent-skills targetで配置した本文です。初回出力やtool traceで読込みを確認し、未読の通常実装をAdaptive完了とみなしません。構造提示後にCLIが終了することを確認し、次の起動で実際の利用者応答を渡します。
