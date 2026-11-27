# 実装必要性レビュー

既存ツールやレビューを重ねた実装で、利用者が必要なときにコード全体から不要な停止条件や機構を探す独立Skillです。

```sh
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/implementation-necessity-review --target copilot,codex,agent-skills
```

「$implementation-necessity-review で注文取込から保存までをレビューしてください」のように依頼します。利用者が守りたい制約と通常の利用場面が分かれば添えてください。PRやPurpose Review Runnerは不要です。
