# Purpose Review Runner Compatibility

この文書は、Purpose Review Runnerのversion履歴と非互換点をまとめます。現在の利用条件は[Runner README](../apps/PurposeReviewRunner/README.md)と[Persistent Purpose Review README](../apm-packages/persistent-purpose-review/README.md)を参照してください。

## 現在の利用条件

Skill 0.6.0はRunner 0.6.0以上、protocol v4を要求します。v4はReviewInput JSONを導入し、目的・設計整合を評価します。Runner 0.6.0のRelease状態および実モデルqualificationは未確認です。`apm update`はSkillだけを更新し、Runner binaryは更新しません。

## v3および0.5.0から0.6.0への移行

protocol v4はv3と非互換です。旧`--context`入力、v3 run/state/resultは新Runnerで継続・再解釈しません。Runner 0.6.0の`job.json` schemaVersionは3で、v3のschema 1、0.5.0のschema 2、および`reviewRounds`を持たない旧state/lineage recordは拒否します。旧runは開始したRunnerで扱い、新しい作業のみ0.6.0で始めます。v4は`start --repository <path> --input <json>`と`continue --run <uuid> --input <json>`を使い、各提出で完全な入力を要求します。自動移行、session再構成、transcript replayは行いません。

同じchangeに対する最大3 review rounds（`reviewRounds`）はlinked runs全体で共有されます。reviewが成立する前に終了したoperational failureは`durableSubmissions`にのみ記録され、3-roundのreview予算は消費しません。`ERROR`または`BLOCKED`のrunはcontinueせず、同じchangeで新しいlinked runへ進む場合はtask/change identityと成立済み`reviewRounds`およびreview履歴を維持します。terminal結果はcontinueしません。`HUMAN_DECISION_REQUIRED`はユーザー判断が必要であり、同じ変更の自動再開を認めません。

## History

| Version | 内容 |
| --- | --- |
| 0.2.0 | async job。`start` / `continue`がprovider完了をforegroundで待たず、`status`で結果を取得 |
| 0.2.1 | Windowsのrestrictive Job Objectからの独立起動 |
| 0.2.2 | CopilotへのBOMなしUTF-8標準入力prompt転送 |
| 0.2.3 | reviewerのshell調査と目的逸脱レビュー |
| 0.3.0 | protocol v3。findingに`requiredOutcome`を導入 |
| 0.4.0 | 実装reviewと後工程の実環境検証の境界を追加 |
| 0.5.0 | protocol v4。ReviewInput、linked submission budget、目的・設計整合reviewへ変更。Grok/profileを削除 |
| 0.6.0 | runtime契約とbest-effort guardrailの整理。exact CLI version gateを廃止しcapability discoveryをbest-effort化、`reviewRounds`と`durableSubmissions`を分離（job schema 3）、authority不変時の`ERROR` / `BLOCKED`後新`changeId`で`userDecision`を不要化 |

0.5.0以降はpurpose sourceとproposalを入力へ埋め込み、承認済みbaselineが存在しない場合はnullを許します。proposal deltaには追加、削除、緩和など全変更を記録します。入力内のevidenceを使い、reviewerによるsource再取得は前提にしません。conformance recordはownerの実行を保証しません。旧v3 finding schemaをv4へ読み替えません。

`COMPLETE`はproposalやapproved baselineを承認しません。完了後に別changeを始める場合は同じtaskKey、新しいchangeId、直近のcompleted runを指すpreviousRunIdを使います。approvedDesignに入れられるのはユーザーが実際に承認したbaselineだけです。以前のproposalを自動昇格せず、実際に承認済みなら既存decisionのbodyとauthorityをuserDecisionに引用して記録し、同じ承認を再要求しません。Runnerは前回inputからpurposeまたはapprovedDesignが変わる場合に新しい`changeId`と`userDecision`を要求します。`HUMAN_DECISION_REQUIRED`後の新changeも新しい`changeId`と`userDecision`を要求します。`ERROR` / `BLOCKED`後のdistinct changeは、purposeとapprovedDesignが不変なら新しい`changeId`のみで開始でき、`userDecision`は不要です。`FINDINGS`からは新`changeId`で逃げることはできず、必ず同一runの`continue`を使います。詳細は[technical reference](purpose-review-runner-technical-reference.md)を参照してください。
