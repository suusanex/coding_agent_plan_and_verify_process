# PR Review Remediation

`$pr-review-remediation`は、Ready GitHub PRにremote reviewを要求し、review findingsを現在の実装エージェント自身が評価して、必要な修正、validation、commit、pushまで同じ作業内で完了するAPM Skillです。標準のremote review sourceとしてGitHub Copilot Code Reviewを使います。

利用者はreview取得やGit操作を一つずつ指示する必要はありません。Skillを指定すると、対象PRの確認から最終報告までを一続きで処理します。修正が不要ならempty commitを作りません。

## 何に向いているか

- 向いている: 実装済みのReady PRにbaseline code reviewを要求し、指摘の採否判断と必要な修正まで同じエージェントへ任せたい。
- 向いている: review後のvalidation、commit、pushを別作業として毎回指示したくない。
- 向いていない: Draft PRを自動的にReadyへ変更してほしい。先に人手でReady for reviewへ変更します。
- 向いていない: 仕様やGoal Contextに対して実装が目的を達成したかを独立reviewerへ確認したい。その場合は[$persistent-purpose-review](../persistent-purpose-review/README.md)を使います。
- 向いていない: GitHub PRを使わないlocal-only review。

PR Review Remediationはbaseline PR reviewを担当します。purpose-aware reviewや同じreviewer sessionでの再reviewは別の責務です。

## 前提条件

Quickstartの前に次を満たしてください。

- [APM CLI](https://github.com/microsoft/apm)が使えること。
- GitHub CLI `gh`が導入済みで、対象repositoryへ認証済みであること。
- 対象PRとreview / comment / checkを読み取り、GitHub Copilot Code Reviewを要求できる権限があること。
- remediationをcommitし、対象PRのhead repository / branchへpushできること。
- File-based Appsを実行できる.NET 10 SDK以降が使えること。
- 対象がDraftではないReady GitHub PRであること。
- Skillを実行するエージェントがCopilot、Codex、またはAgent Skills経由であること。

GitHub Copilot Code Reviewを利用できない、reviewを要求できない、またはpush権限がない場合、Skillは未取得reviewや未反映変更を成功扱いせず停止します。

## 5分Quickstart

### 1. Skillを導入する

SkillをOSユーザー単位のglobal領域へ導入します。実際のPR処理は対象repositoryで行います。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target copilot,codex,agent-skills --global
```

APMは`pr-review-remediation` Skillとreview context collectorを導入します。0.9.0以降は独立した`review-planner`、Codex agent profile、`codex-profile-finalizer`は必要ありません。

### 2. 実装エージェントへ指示する

現在のbranchに紐付くReady PRを処理する通常の指示はこれだけです。

```text
$pr-review-remediation を使って、このbranchのReady PRを処理してください。
```

repositoryとPR番号を明示する場合:

```text
$pr-review-remediation を使って owner/name#123 を処理してください。
```

review要求、取得、finding評価、必要な修正、validation、commit、pushを個別に列挙する必要はありません。利用者がcommitやpushを止めたい場合だけ、その制約を同じ依頼で明示します。

### 3. 実行後に起こること

```text
Ready PRを確認
  → GitHub Copilot Code Reviewを要求してremote review evidenceを取得
  → 現在の親エージェントが全findingを評価
  → 必要なfindingだけを修正してvalidation
  → validation結果を記録し、Git安全条件を確認してcommit / push
  → finding、検証、Git結果を報告
```

反映しないfindingには理由を残します。人間のproduct / scope判断が必要な指摘を推測で処理せず、review取得失敗、PR更新、validation失敗、push失敗を「指摘なし」や成功へ読み替えません。

## 上流原因を確認するProcess Feedback

通常のレビューでも全findingについて、局所的な問題か、設計・Plan・SKILL等の上流に原因が疑われるか、証拠不足かを短く記録します。詳細な原因分析が不要な小規模PRでは、追加指定は必要ありません。

既存artifactを遡って再発防止の候補まで調べたい場合だけ、依頼に追加します。

```text
$pr-review-remediation を使って、このbranchのReady PRを処理してください。Process Feedbackを有効にしてください。
```

疑い又は証拠不足のfindingを対象に、存在するGoal Context、Plan、設計判断、実装記録、関連SKILLを参照し、今回のPR修正・今回の上流artifact修正・共通プロセス改善候補を分けて報告します。Goal ContextやPlan Coverageの導入は前提ではありません。対象がなければ詳細分析は行いません。

選択は分析の許可であり、共通SKILLの変更や他フローの起動許可ではありません。単発ミスだけで共通プロセスの欠陥を断定せず、証拠不足は不明として残します。候補が未実施でも、今回のPRの採否・修正・検証・Git操作に問題がなければレビューを完了できます。

## Adaptive Implementationを使う場合

Adaptive Implementationは通常利用には不要です。指定がなければ、このSkillを開始した現在の親エージェントがremediationを実装します。

採用したfindingの実装にAdaptive Implementationを使いたい場合だけ、[Adaptive Implementation](../adaptive-implementation-execution/README.md)を別途導入し、依頼で明示します。

```text
$pr-review-remediation を使って owner/name#123 を処理し、採用したfindingの実装には /adaptive-implementation-execution を使ってください。
```

Adaptiveを明示しても、review coverage、validation、commit、push、最終報告はPR Review Remediationを開始した親エージェントが最後まで所有します。

## 結果の見え方

| 結果 | 意味 |
| --- | --- |
| `REVIEW_COMPLETE` | 全findingの判断と必要な修正が完了し、必要なvalidationがすべてPASS。Git結果も解決済み |
| `REVIEW_COMPLETE_WITH_VALIDATION_ISSUES` | review処理は完了したがFAIL / NOT_RUN（pendingを含む）が残る。検証成功・品質保証・merge可能を意味しない |
| `HUMAN_DECISION_REQUIRED` | product / scope判断や未取得reviewを許容するかなど、利用者の判断が必要 |
| `BLOCKED` | review要求、権限、PR identity、push先、repository固有の禁止条件などで安全に完了できない |

最終報告にはfindingの採否、変更概要、validation、commit / push結果、未検証事項、人手で必要な作業が含まれます。

PR準備時とreview後のremediation時の両方で、validation失敗だけをcommit / push / PR作成の禁止理由にしません。関連validationを実行し、command、結果、原因（既存・環境・変更・不明）と根拠、影響、未解決事項を記録します。scope内で修復可能なら修正・再検証を続け、残件は上記の専用verdictで明示します。利用者指示、repository規約、Git安全性や確認済み自動デプロイ等の禁止条件は維持します。修正不要ならempty commitを作らず、利用者のGit操作禁止は`SKIPPED_BY_USER`として記録します。

## 更新

OSユーザー単位のglobal領域にあるAPM packageを更新します。具体的な更新対象やオプションは[APMの資料](https://microsoft.github.io/apm/reference/cli/update/)を参照してください。

```powershell
apm update --global
```

0.8.0以前から更新する場合、planner/profile依存の変更点は[Migration](.apm/skills/pr-review-remediation/references/migration.md)を確認してください。

## 削除

OSユーザー単位のglobal領域からアンインストールします。

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --global
```

以前のversionが生成したprofile等が残る場合は、ownershipを確認してから[Troubleshooting](.apm/skills/pr-review-remediation/references/troubleshooting.md)の案内に従います。

## Troubleshootingと関連文書

| 文書 | 役割 |
| --- | --- |
| このREADME | 利用判断、前提条件、導入、実装エージェントへの指示、結果の見方 |
| [Troubleshooting](.apm/skills/pr-review-remediation/references/troubleshooting.md) | Draft、review timeout、PR更新、push destination、validation / push failure |
| [Usage reference](.apm/skills/pr-review-remediation/references/usage.md) | 導入済みSkillの指示例とartifact一覧 |
| [Technical reference](../../docs/pr-review-remediation-technical-reference.md) | workflow、collector artifact、評価・trust boundary、Git contract、terminal semantics、maintainer validation |
| [Migration](.apm/skills/pr-review-remediation/references/migration.md) | 0.7.0から0.9.0までのbehavior境界 |
| [Skill contract](.apm/skills/pr-review-remediation/SKILL.md) | 実装エージェントが従うprocess semanticsの正本 |
| [Installation and Maintenance](../../docs/installation-and-maintenance.md) | repository横断のdistribution、validation、maintainer手順 |
| [Persistent Purpose Review](../persistent-purpose-review/README.md) | 実装後のpurpose-aware reviewと同一reviewer sessionでの再review |
