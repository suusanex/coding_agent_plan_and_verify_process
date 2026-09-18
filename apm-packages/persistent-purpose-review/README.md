# Persistent Purpose Review

`$persistent-purpose-review`は、実装が仕様やGoal Contextの目的を満たしたかを独立reviewerに確認させ、findingがあれば元の実装エージェントが直して同じreviewerに再確認させるAPM Skillです。

向いているのは、仕様・Goal Context・承認済み判断に対して「本当に目的を満たしたか」を実装完了後に確認したいときです。baseline PR code reviewの代替ではなく、最初から明確なpurpose contextがない仕事にも向きません。詳細は[何に向いているか](#何に向いているか)を参照してください。

Skillは実装担当エージェントにレビュー工程を教えます。独立reviewerの起動と同一sessionの維持は、PCへ一度だけ入れるローカルCLI [Purpose Review Runner](../../apps/PurposeReviewRunner/README.md)が担当します。両方必要です。RunnerはOS userごとに一度、Skillは実行環境へ`--global`で導入します。

通常はRunnerの`start` / `status` / `continue`を手で呼ぶ必要はありません。実装エージェントがこのSkillに従い、Runnerを呼び出します。

## 前提条件

Quickstartの前に次を満たしてください。満たさないままconfigだけ書くと、provider CLIが見つからずそこで止まります。

- [APM CLI](https://github.com/microsoft/apm)が使えること
- reviewerとして使うprovider CLIが導入済みで、そのCLI自身の認証が済んでいること。選べるのはCodex / Grok / Copilotです。RunnerはAPI keyやOAuthを代行しません
- Runnerの対応OSがWindows x64またはLinux x64であること
- Skillを実行する実装側エージェントがCodex、Copilot、またはAgent Skills経由であること

このSkillは`purpose-review-runner` 0.3.0以上とprotocol v3を要求します。未導入や非互換ならfail closedで停止します。過去runの継続が必要な場合は[compatibility note](../../docs/purpose-review-runner-compatibility.md)を参照してください。

## 5分Quickstart

上から順に実行すると、初回のpurpose reviewまで到達できます。Runnerの展開・configの詳細、他provider例、トラブル時は[Purpose Review Runner README](../../apps/PurposeReviewRunner/README.md)が正本です。

### 1. Runnerを導入する

1. [最新Release](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest)から、Windowsは`purpose-review-runner-win-x64.zip`、Linuxは`purpose-review-runner-linux-x64.tar.gz`を取得します。
2. [Purpose Review Runner README の Install](../../apps/PurposeReviewRunner/README.md#install)を、ダウンロードしたdirectoryで上から実行します。展開、PATH追加、configコピーと編集、`version`確認まで同じ例につながっています。configはbinaryの隣には置きません。
3. Codexを使う場合、コピーされる内容は次の現行例です。Grok / Copilot ならRunner READMEの構文例に置き換えます。

```json
{
  "schemaVersion": 1,
  "provider": "codex",
  "executable": "codex",
  "model": "gpt-5.6-terra",
  "reasoningEffort": "high",
  "profile": null
}
```

### 2. Skillを導入する

実行環境へuser-scopeで導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/persistent-purpose-review --target agent-skills --global
purpose-review-runner version
```

紹介するのはこの方式です。`--target`や導入先scopeなど、ほかのオプションは[APMの資料](https://microsoft.github.io/apm/reference/cli/install/)を参照してください。

`version`が単一JSONを返し、`protocolVersion`が`3`、`runnerVersion`が`0.3.0`以上であることを確認します。

### 3. 実装エージェントへ指示する

通常の実装指示へ次を加えます。これが主経路です。あとはimplementation parentがRunnerを呼び、findingがあれば直し、同じreviewerに再確認します。

```text
実装完了後は $persistent-purpose-review に従ってpurpose reviewを完了してください。
```

purpose contextがある場合はpathも渡します。補完関係にある複数文書はすべて指定できます。

```text
実装完了後は $persistent-purpose-review に従ってpurpose reviewを完了してください。
purpose contextは docs/goal-context.md です。
```

```text
実装完了後は $persistent-purpose-review に従ってpurpose reviewを完了してください。
purpose contextは plans/accepted-plan.md と docs/accepted-decisions.md です。
```

明示されたbaseやPRがある場合はcontext内に比較対象を記載します。PRやレビュー専用commitの作成は不要です。現在のsourceが競合する場合だけ、parentがreview開始前に質問します。

### 4. 成功時の見え方

```text
実装完了
  → Skillがreviewを開始する
  → FINDINGSがあれば元の実装エージェントが修正し、同じreviewerへ再reviewする
  → COMPLETEなら成功
```

最大3roundです。なお残る場合は`HUMAN_DECISION_REQUIRED`で止まり、人手の判断が必要です。JSON schemaを先に読む必要はありません。

reviewerはnon-modifying reviewerです。変更禁止を指示しますが、OS-levelのread-only isolationではありません。修正は元のimplementation parentだけが行います。

## 何に向いているか

- 向いている: 仕様・Goal Context・承認済み判断に対して、実装が利用経路で目的を満たしたか確認したい。
- 向いている: 同じreviewerが修正後も再確認し、表面的な充足や修正による逸脱も見たい。
- 向いていない: Ready PRのbaseline code reviewの代替。[`$pr-review-remediation`](../pr-review-remediation/README.md)を使います。
- 向いていない: 最初から明確なpurpose contextが存在しない仕事。

## 更新

| 対象 | 手順 |
| --- | --- |
| Skill | 導入時と同じく実行環境のuser-scopeで更新する。コマンドとほかのオプションは[APMの資料](https://microsoft.github.io/apm/reference/cli/install/)を参照 |
| Runner | [最新Release](https://github.com/suusanex/coding_agent_plan_and_verify_process/releases/latest)のarchiveを差し替える |
| config / state | 通常はそのまま |

`apm update`だけではRunner binary、user-level config、既存run stateは変わりません。Runner 0.3.0以上への更新はGitHub Release側で別に行います。protocol移行などの特殊ケースは[compatibility note](../../docs/purpose-review-runner-compatibility.md)を参照してください。

## 削除

Skillが不要になったときだけ、導入時と同じuser-scopeでアンインストールします。コマンドとほかのオプションは[APMの資料](https://microsoft.github.io/apm/reference/cli/install/)を参照してください。Runner binary、user-level config、既存run stateは削除しません。

## 関連文書

| 文書 | 役割 |
| --- | --- |
| このREADME | 利用者の入口とSkillの利用方法 |
| [Purpose Review Runner README](../../apps/PurposeReviewRunner/README.md) | Runnerのインストール、設定、update、troubleshooting |
| [Technical reference](../../docs/purpose-review-runner-technical-reference.md) | protocol、state、worker、provider adapter |
| [Compatibility](../../docs/purpose-review-runner-compatibility.md) | version履歴とv2/v3非互換 |
| [Maintainer reference](../../docs/purpose-review-runner-maintenance.md) | build、release、validation |

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはpackage rootへchecked-inせず、repository共通builderでtemporary stageへ生成します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package persistent-purpose-review
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package persistent-purpose-review
```

APMがsupported distributionです。direct deploymentのstatusとevidenceは`tests/agent-plugin/qualification.json`に記録し、未観測のbehaviorをPASSへ昇格させません。
