# coding_agent_plan_and_verify_process

GitHub Copilot / CodexでPlan-first開発を行うためのAPM processes、agents、補助packageと、Codexの完了通知を扱うlocal toolsを管理するrepositoryです。

このページは目的から最初に読む文書を選ぶためのnavigationです。導入手順、詳細契約、検証方法はリンク先を参照してください。

## 開発プロセスを選ぶ

| 目的 | 種別 | 最初に読む文書 |
| --- | --- | --- |
| bounded Planをsource of truthとして実装・検証し、未解決項目を明示判断したい | APM process | [Plan Coverage Check and Residual Decision Flow](apm-packages/plan-coverage-residual-flow/README.md) |
| 通常のPlanから、HIGH_MODELで非局所decisionを閉じ、決定済み境界内の実装をSTANDARD_MODEL主体で進めたい | APM process | [Adaptive Implementation Execution](apm-packages/adaptive-implementation-execution/README.md) |
| 実装前に予定変更面をfile / symbol単位で利用者と対話し、確定事項だけを実装へ渡したい | optional APM pre-stage | [Design Pair Implementation Execution](apm-packages/design-pair-implementation-execution/README.md) |

選択に迷う場合は、Plan-first開発と広い要求の`full-coverage`ではPlan Coverage、既にあるPlanの実装ではAdaptive Implementationを基準にしてください。

## 補助機能を使う

| 目的 | 種別 | 最初に読む文書 |
| --- | --- | --- |
| Ready PRをreviewし、通常版ではreview plan、Goal Context版では同じ親task内の修正と再reviewまで進めたい | helper APM package | [PR Review Remediation](apm-packages/pr-review-remediation/README.md) |
| 自然言語資料から、後続AIが目的を判断できるfree-form Goal Contextを作りたい | authoring APM package | [Goal Context Authoring](apm-packages/goal-context-authoring/README.md) |
| 通常の完了通知へprocess status、title、result linkを任意追加したい | optional APM decorator | [Completion Notification Decorator](apm-packages/completion-notification-decorator/README.md) |

これらは開発プロセス本体とは役割が異なります。Goal Context Authoringは文書作成補助、Completion Notification Decoratorは通知metadata enrichmentであり、primary processのroutingやverdictを置き換えません。

## ローカルツールを使う

| 目的 | 種別 | 最初に読む文書 |
| --- | --- | --- |
| Codex turn終了をalways-on callbackからLocal Spoolへ1 event 1 JSONで保存したい | non-APM runtime tool | [Codex Notification Runtime](scripts/codex-notification-runtime/README.md) |
| Local Spoolの完了eventをWindows上で確認し、resume、result表示、削除を行いたい | non-APM WinUI application | [Codex Local Inbox](apps/CodexLocalInbox/README.md) |

Notification Runtimeはproducer、Codex Local Inboxはconsumerです。どちらもAPM開発プロセスではありません。

## 導入・保守を行う

複数packageにまたがるinstallerの選択、`provision-work-repo-agents.cs`、runtime mirrorの同期、validator一覧は[Installation and Maintenance](docs/installation-and-maintenance.md)を参照してください。

設計理由や過去の検証記録を確認する場合は`docs/`、実行ごとのPlanとledgerを確認する場合は`plans/`を参照してください。`plans/**`はhistorical recordを含むため、一般ドキュメントの正本としては扱いません。
