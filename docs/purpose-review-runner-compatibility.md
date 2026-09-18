# Purpose Review Runner Compatibility

この文書は、Purpose Review Runnerのversion履歴と非互換点をまとめたmigration noteです。現在必要な導入条件は[Purpose Review Runner README](../apps/PurposeReviewRunner/README.md)と[Persistent Purpose Review README](../apm-packages/persistent-purpose-review/README.md)を正本とします。

## 現在必要なversion

`$persistent-purpose-review`は`purpose-review-runner` 0.3.0以上とprotocol v3を要求します。Runner未導入、0.3.0未満、またはprotocol非互換ならfail closedで停止します。`apm update`はSkillだけを更新し、Runner binaryは更新しません。

## Protocol compatibility

v3はv2と非互換です。既存のv2 runは開始時のRunnerで完了させ、RunnerとSkillの更新後の新しい作業からv3を利用します。v2 stateの`continue`やv2保存結果の`status`は`STATE_INCOMPATIBLE`で停止します。旧結果の自動変換、stateの移行、sessionの再構築は行いません。configとjob lifecycleのschemaは変更しません。

進行中runを別Runnerへ移す必要はありません。開始したversionで完了させ、新しい作業だけ新しいversionを使います。

## History

| Version | 内容 |
| --- | --- |
| 0.2.0 | async job。`start` / `continue`がprovider完了をforegroundで待たず、`status`で結果を取得する |
| 0.2.1 | Windowsのrestrictive Job Objectからの独立起動 |
| 0.2.2 | CopilotへのBOMなしUTF-8標準入力prompt転送 |
| 0.2.3 | reviewerのshell調査と目的逸脱レビュー |
| 0.3.0 | protocol v3。findingの必須項目を`requiredChange`から`requiredOutcome`へ変更。0.2.3のshell調査と目的逸脱レビューは維持 |

0.3.0ではreviewerが必要成果を示し、具体的な修正設計はparentが所有します。`requiredOutcome`の欠落・null・空白、旧`requiredChange`や両項目の混在は不正結果です。
