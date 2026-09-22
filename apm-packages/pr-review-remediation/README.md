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

処理したいrepositoryのrootで実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/pr-review-remediation --target copilot,codex,agent-skills
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
  → validation成功後にcommit / push
  → finding、検証、Git結果を報告
```

反映しないfindingには理由を残します。人間のproduct / scope判断が必要な指摘を推測で処理せず、review取得失敗、PR更新、validation失敗、push失敗を「指摘なし」や成功へ読み替えません。

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
| `REVIEW_COMPLETE` | 全findingの判断と必要な修正・validationが完了し、変更があればcommit / push済み。修正不要ならempty commitなしで完了 |
| `HUMAN_DECISION_REQUIRED` | product / scope判断や未取得reviewを許容するかなど、利用者の判断が必要 |
| `BLOCKED` | review要求、権限、PR更新、validation、pushなどの問題で安全に完了できない |

最終報告にはfindingの採否、変更概要、validation、commit / push結果、未検証事項、人手で必要な作業が含まれます。

## 更新

対象repositoryのrootでAPM packageを更新します。具体的な更新対象やオプションは[APMの資料](https://microsoft.github.io/apm/reference/cli/update/)を参照してください。

```powershell
apm update
```

0.8.0以前から更新する場合、planner/profile依存の変更点は[Migration](.apm/skills/pr-review-remediation/references/migration.md)を確認してください。

## 削除

対象repositoryのrootでアンインストールします。

```powershell
apm uninstall pr-review-remediation
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
