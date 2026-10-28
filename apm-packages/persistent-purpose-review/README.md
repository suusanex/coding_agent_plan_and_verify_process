# Persistent Purpose Review

`$persistent-purpose-review`は、明示的に許可されたtaskで、元の目的と提案設計の整合を独立reviewerに確認させるAPM Skillです。対象は初期設計と重要な設計変更です。通常の実装完了やverificationを契機に自動起動しません。findingだけ、または実装不足だけを理由に開始せず、実装修正やコード品質レビューを担当しません。

Skillはuser-invocableで、`disable-model-invocation: true`を維持します。RunnerはSkillから利用する別途導入のCLIです。SkillとRunnerの両方が必要です。

## 前提条件

- APM CLIが利用できること。
- reviewerとしてCodex CLIまたはGitHub Copilot CLIのいずれかが導入・認証済みであること。Grok Buildは対応しません。
- `purpose-review-runner` 0.5.0以上、protocol v4のRunner buildがあること。
- Runnerのconfigでproviderを`codex`または`copilot`に設定し、`profile`は`null`にすること。

Runner 0.5.0 / protocol v4のReleaseと実モデル評価は、この変更時点で未確認です。導入前にversionとreleaseの存在を確認し、必要なRunner buildが配布されていない場合はSkillの運用を開始しないでください。`apm update`だけではRunner binaryは更新されません。

## Install

Runnerの現在の配布状態、導入、configは[Purpose Review Runner README](../../apps/PurposeReviewRunner/README.md)を参照してください。Runnerを導入し、provider CLIの認証を済ませた後、Skillをuser-scopeで導入します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/persistent-purpose-review --target agent-skills --global
purpose-review-runner version
```

`version` JSONでprotocol v4、Runner 0.5.0以上を確認します。実行前に必ずSkill自体を明示的に起動します。

```text
$persistent-purpose-review を起動し、許可済みの設計変更をpurpose reviewしてください。
```

## InputとCLI

各提出で`schemaVersion: 1`のJSON inputを用意します。ユーザーの目的・authorityの引用とsource、承認済みbaseline（存在しなければ`null`）、設計全体とbaselineからの追加・削除・緩和を含むdelta、証拠本文、findingへの応答、要件ごとのconformance申告を埋め込みます。Runnerやreviewerにsourceを取りに行かせず、入力内の証拠を使います。conformance記録はownerの実施を保証しません。

初回は`start --repository <path> --input <json>`、同じrunでの再提出は`continue --run <uuid> --input <json>`、状態確認は`status --run <uuid>`です。各continueで完全な最新inputを渡します。`taskKey`と`changeId`は安定して維持し、同一changeのlinked runを通じて最大3提出までです。continue inputは初回start時の`previousRunId`値を保ちます。terminal `ERROR`/`BLOCKED`後は同じtask/change IDsと直前run参照で新しいlinked runを`start`し、消費済み予算を引き継ぎます。`HUMAN_DECISION_REQUIRED`後はユーザーが新しい判断を明示するまで再開しません。

`priorReviewHistory`はRunner管理のfieldです。user inputから省略し、ERROR / BLOCKED後のlinked runやcontinueに過去履歴を手作業で混ぜないでください。

Runnerはcallerが提示したIDからlineageと予算を管理します。異なる`taskKey`が同じ実質的作業を指すことや、`userDecision`のbody/authorityが実際のユーザー発言かどうかは推測・認証しません。Skillは同じ作業のIDを保ち、`userDecision`にはユーザーの決定を原文引用して出典・決定範囲を記録します。

`HUMAN_DECISION_REQUIRED`後にユーザーが新しいscopeを実際に決めた場合、同じ`taskKey`、新しい`changeId`、terminal runを指す`previousRunId`、判断を引用した`userDecision`で新しい`start`を行います。これは新たなchangeとしてreviewします。同じchangeを自動再開する用途には使いません。

`COMPLETE`はレビュー工程の完了を示します。ユーザー承認、設計適合の独立実証、実装完了、実行時conformanceの保証を示しません。レビュー結果を設計責任者へ返し、判断が必要な事項を明示します。

## Review境界

- reviewerは目的、承認済みbaseline、提案設計、差分、提示証拠の整合を評価します。
- implementationの不足をfindingに変換して修復したり、レビューのためにコードを調査したりしません。
- ユーザーが明示的に許可した範囲内で、初期設計や重要な変更を扱います。些細な変更やfindingだけを理由に提出しません。
- 目的の変更やscope追加のauthorityがなければ推測で補わず停止します。

## Runtime qualification

現在のSkill/Runner組合せの実モデル評価は未実施です。評価statusは`NOT_RUN`、Agent Plugin direct deploymentは`HOLD`のままです。詳細とシナリオは[qualificationシナリオ](../../tests/PurposeReviewRunner.Tests/purpose-review-scenarios.md)および[Agent Plugin runtime qualification](../../docs/agent-plugin-runtime-qualification.md)を参照してください。過去の実装reviewやprovider継続実験から、目的・設計reviewの検出力や利用負荷を推定しません。

## Maintenance

`apm update`はSkillを更新します。Runnerは独立して更新します。protocol v4はv3と非互換です。既存runを移行・再構築せず、旧runは旧Runnerで扱い、新しいrunだけ新しいprotocolで開始してください。詳細は[compatibility note](../../docs/purpose-review-runner-compatibility.md)と[maintainer reference](../../docs/purpose-review-runner-maintenance.md)を参照してください。

## Agent Plugin artifact

process semanticsの正本はこのpackageの`.apm/**`です。Agent Plugin artifactはrepository共通builderで一時stageへ生成して検証します。

```powershell
pwsh -NoProfile -File scripts/agent-plugins/build-agent-plugin.ps1 -Package persistent-purpose-review
pwsh -NoProfile -File scripts/agent-plugins/validate-agent-plugin-package.ps1 -Package persistent-purpose-review
```

APMがsupported distributionです。direct deploymentの未観測behaviorをPASSへ昇格しません。
