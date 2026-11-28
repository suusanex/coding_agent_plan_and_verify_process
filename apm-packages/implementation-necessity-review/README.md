# 実装必要性レビュー

既存ツールやレビューを重ねた実装で、利用者が必要なときにコード全体から不要な停止条件や機構を探す独立Skillです。

任意のディレクトリから実行し、OS ユーザー単位でインストールします。更新・削除は[共通運用手順](../../docs/installation-and-maintenance.md#global-lifecycle)を参照してください。

```sh
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/implementation-necessity-review --target copilot,codex,agent-skills --global
```

「$implementation-necessity-review で注文取込から保存までをレビューしてください」のように依頼します。利用者が守りたい制約と通常の利用場面が分かれば添えてください。PRやPurpose Review Runnerは不要です。
