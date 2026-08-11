# coding_agent_plan_and_verify_process

GitHub Copilot / CodexでPlan-first開発を行うためのAPM processes、agents、補助packageと、Codexの完了通知を扱うlocal toolsを管理するrepositoryです。

このREADMEは、利用目的から必要な構成を選び、そのまま導入を始めるためのQuickstartです。package固有のcollision、update、remove、詳細flowはリンク先を正本とします。

## このrepositoryでできること

- 既存Planから、model roleを分けて実装を進める。
- 実装前にfile / symbol単位の内部設計を人間と確認する。
- Ready PRを独立reviewし、修正と目的照合まで進める。
- bounded Planから実装、検証、残件判断までのcoverageを維持する。
- Goal Context作成や、Codex完了eventの保存・閲覧を補助する。

APM process packageは基本的に利用するwork repositoryごとに導入します。Notification RuntimeはPCのuser-level設定、Codex Local InboxはWindows applicationであり、導入scopeが異なります。

## Quickstart: 目的から選ぶ

以下の`apm install`は、導入先repositoryのrootで実行します。`$moduleRoot`はAPMが作る導入済みmoduleを指します。

### 実装を改善したい

[Adaptive Implementation Execution](apm-packages/adaptive-implementation-execution/README.md)は、既にPlanやimplementation intentがある状態から、HIGH_MODELで非局所decisionを閉じ、decision-closedなproduction implementation、tests、validationをSTANDARD_MODEL主体で進めます。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

APM installがSkillとportable agentsを導入し、finalizerがCodex用TOMLのconcrete model / reasoning / sandbox profileだけを補完します。APMが同等の設定を生成済みならfinalizerはno-opになります。dry-run、check、force、更新・削除は[Adaptive install guide](apm-packages/adaptive-implementation-execution/docs/install-guide.md)を参照してください。

### 実装前に内部設計も対話して決めたい

[Design Pair Implementation Execution](apm-packages/design-pair-implementation-execution/README.md)をAdaptiveのpre-stageとして追加します。Target Mapをfile / symbol単位で提示して人間の選択を待ち、confirmed Locked DecisionsだけをAdaptiveへ渡します。Design Pair単独ではimplementation orchestrationを所有しません。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution --target copilot,codex,agent-skills
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

Design Pair manifestもAdaptive Skillとcanonical agentsをdependencyとして導入します。上の用途別Quickstartは、必要なpackageをAPMで導入してから共通finalizerを一度実行する構成です。

### PRレビューと修正を改善したい

[PR Review Remediation](apm-packages/pr-review-remediation/README.md)には二つの入口があります。baseline `$pr-review-remediation`はreview planを作り、別turnの修正前で停止します。canonical `$goal-context-pr-review`は、独立review、元のparentによる修正、purpose-only再reviewを同じparent task内で進めます。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

Goal Contextはfree-form textであり、`goal-context-authoring` packageへの依存を意味しません。baseline flowのreview planを別turnのAdaptiveで修正する場合だけ、Adaptive Implementationをoptional add-onとして導入します。canonical same-parent flowには不要です。

### Planから実装・検証・残件判断まで抜けを防ぎたい

[Plan Coverage Check and Residual Decision Flow](apm-packages/plan-coverage-residual-flow/README.md)は、bounded Planをsource of truthとしてcoverageを追跡し、必要なimplementation / runtime / test design guardrail、Adaptive Implementation、verification、Residual Decisionをつなぎます。広い要求も`full-coverage` routeでArchitecture Slice ReadinessからResidual Decisionまで扱います。

Plan Coverageの現時点のsupported installationはAPM経由です。Agent Plugins bundleは同じcanonical sourceから継続的に生成・検証する将来のdeployment candidateであり、direct plugin installを通常導入方法として扱いません。[Agent Plugins採用方針](docs/agent-plugin-adoption-strategy.md)で、APM・runtime qualification・direct deploymentの境界と昇格条件を定義しています。

導入先repositoryのrootで、必要なpackageをAPMから導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow --target copilot,codex,agent-skills
$moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
```

APM installがportable agentsとSkillを導入し、finalizerが必要なCodex profile fieldだけを補完します。Plan Coverage manifestはAdaptiveと共通finalizerをdependencyとして持つため、Adaptiveやfinalizer packageを別途installする必要はありません。implementation stageでDesign Pairを使う場合だけDesign Pair packageを追加します。

## Processの関係

| Process | 主な入口 | 他processとの関係 |
| --- | --- | --- |
| Adaptive Implementation | 既存Planからの実装 | decision closureとimplementation orchestrationを所有する |
| Design Pair | 実装前のTarget Map対話 | Adaptiveの任意pre-stage。実装はAdaptiveへ渡す |
| PR Review Remediation | Ready PRのreview / remediation | canonical flowはsame-parent、baselineの別turn修正だけAdaptiveを任意追加する |
| Plan Coverage Residual Flow | Plan-first全体とcoverage管理 | Adaptiveを実装経路として含み、検証後の残件をResidual Decisionへ渡す |

## 通常使うprocessを一通り入れる

通常セットはAdaptive Implementation、Design Pair、PR Review Remediation、Plan Coverageです。Plan CoverageがAdaptiveと共通finalizerをdependencyとして導入するため、全部入りではAdaptive packageやfinalizer packageを重ねてinstallしません。

1. 導入先repositoryのrootでPlan Coverageをinstallします。

   ```powershell
   apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow --target copilot,codex,agent-skills
   ```

2. 同じ導入先repositoryでDesign PairとPR Review Remediationを追加します。必要なAPM installをすべて終えてから、共通finalizerを一度実行します。

   ```powershell
   apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/design-pair-implementation-execution --target copilot,codex,agent-skills
   apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target codex,agent-skills
   $moduleRoot = ".\apm_modules\suusanex\coding_agent_plan_and_verify_process"
   dotnet run --file "$moduleRoot\apm-packages\codex-profile-finalizer\scripts\finalize-codex-agent-profiles.cs" -- .
   ```

各用途のQuickstartを個別に実行する場合も、APMの導入結果を確認してからfinalizerを実行します。異なる明示済みprofileを更新する場合だけ、保守文書の手順に従って`--force`を使います。

## 開発支援ツール

### Goal Context Authoring

[Goal Context Authoring](apm-packages/goal-context-authoring/README.md)は、chat historyを含む自然言語資料からfree-form Goal Contextを作る任意toolです。chat専用ではなく、Goal Contextという文書形式自体もこのpackageへ依存しません。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target codex,agent-skills
```

### Completion Notification / Runtime / Inbox

| Component | 役割 | Installation scope |
| --- | --- | --- |
| [Completion Notification Decorator](apm-packages/completion-notification-decorator/README.md) | primary processのterminal status、title、result linkをenrichするoptional APM decorator | 利用するwork repositoryごと |
| [Codex Notification Runtime](scripts/codex-notification-runtime/README.md) | callbackごとにLocal Spoolへeventを保存するalways-on producer。decoratorなしでもgeneric `TURN_ENDED`を生成する | PCのuser-levelでOS userごとに一度setup |
| [Codex Local Inbox](apps/CodexLocalInbox/README.md) | Windows上でLocal Spoolを読み、Resume、Open result、Deleteを提供するconsumer | local Windows application |

通知を保存するだけならRuntimeをsetupします。process metadataも表示したいwork repositoryにだけDecoratorを導入し、GUIで扱う場合にInboxをbuild / installします。InboxはAPM processではありません。

Decoratorは、現在検証済みのlocal package経路を使います。導入先work repositoryのrootで、source checkoutを指定します。

```powershell
$sourceRoot = "C:\path\to\coding_agent_plan_and_verify_process"
apm install "$sourceRoot\apm-packages\completion-notification-decorator" --target codex,agent-skills
```

Runtimeはこのsource repositoryのrootからcurrent OS userへdry-run、install、checkの順で導入します。userが複数いるPCではuserごとに実行します。

```powershell
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --dry-run
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- install
dotnet run --file .\scripts\codex-notification-runtime\install-codex-notification-runtime-local.cs -- --check
```

InboxはWindows上でsource repositoryのrootから起動します。build prerequisitesとpackaged appの制約はcomponent READMEを参照してください。

```powershell
dotnet run --project .\apps\CodexLocalInbox\CodexLocalInbox.csproj
```

## 詳細ドキュメントとmaintenance

複数packageにまたがるinstaller、runtime mirror、maintainer手順、validation matrixは[Installation and Maintenance](docs/installation-and-maintenance.md)を参照してください。

設計理由や検証記録は`docs/`、実行ごとのPlanとledgerは`plans/`にあります。`plans/**`はhistorical recordを含むため、一般ドキュメントの正本としては扱いません。
