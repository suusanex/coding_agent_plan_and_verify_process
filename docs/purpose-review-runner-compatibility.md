# Purpose Review Runner Compatibility

この文書は、Purpose Review Runnerのversion履歴と非互換点をまとめます。現在の利用条件は[Runner README](../apps/PurposeReviewRunner/README.md)と[Persistent Purpose Review README](../apm-packages/persistent-purpose-review/README.md)を参照してください。

## 現在の利用条件

Skill 0.8.0はRunner 0.7.0以上、protocol v5を要求します。v5はv4のReviewInput / 目的・設計整合評価を継承しつつ、初回3-roundの自動レビュー予算上限（`REVIEW_BUDGET_EXHAUSTED`）と`budgetGrant`による追加レビュー許可に対応します。Runner 0.7.0のRelease状態および実モデルqualificationは未確認です。`apm update`はSkillだけを更新し、Runner binaryは更新しません。

## v4および0.6.0から0.7.0への移行

protocol v5はv4以前と非互換です。Runner 0.7.0の`job.json` schemaVersionは4で、旧v4の`job.json` schema 3（およびv3のschema 1、0.5.0のschema 2）、`authorizedReviewRounds`または`reviewRounds`を持たないstate/result/lineage recordはfail closedで拒否します（protocol v4でround 3上限に達して変換された`HUMAN_DECISION_REQUIRED`をv5で誤読しないため、自動移行や読み替えを行いません）。旧runは開始したRunnerで扱い、新しい作業のみ0.7.0で始めます。自動移行、session再構成、transcript replayは行いません。

同じchangeに対する初回自動レビュー予算は`authorizedReviewRounds`（初期値3、`reviewRounds`）としてlinked runs全体で共有されます。reviewが成立する前に終了したoperational failureは`durableSubmissions`にのみ記録され、review予算は消費しません。予算内で解決しなかった場合は`REVIEW_BUDGET_EXHAUSTED`で停止し、同じchangeを続ける場合はユーザーの追加レビュー許可（`budgetGrant`）を付けて同じ`taskKey`・同じ`changeId`で新しいlinked runを`start`します。`ERROR`または`BLOCKED`のrunはcontinueせず、同じchangeで新しいlinked runへ進む場合はtask/change identityと成立済み`reviewRounds`・拡大済み`authorizedReviewRounds`およびreview履歴を維持します。terminal結果はcontinueしません。`HUMAN_DECISION_REQUIRED`はユーザー判断が必要であり、同じ変更の自動再開を認めません。

## History

| Version | 内容 |
| --- | --- |
| 0.2.0 | async job。`start` / `continue`がprovider完了をforegroundで待たず、`status`で結果を取得 |
| 0.2.1 | Windowsのrestrictive Job Objectからの独立起動 |
| 0.2.2 | CopilotへのBOMなしUTF-8標準入力prompt転送 |
| 0.2.3 | reviewerのshell調査と目的逸脱レビュー |
| 0.3.0 | protocol v3。findingに`requiredOutcome`を導入 |
| 0.4.0 | 実装reviewと後工程の実環境検証の境界を追加 |
| 0.5.0 | protocol v4（Skill 0.6.0）。ReviewInput、linked submission budget、目的・設計整合reviewへ変更。Grok/profileを削除 |
| 0.6.0 | runtime契約とbest-effort guardrailの整理（Skill 0.7.0）。exact CLI version gateを廃止しcapability discoveryをbest-effort化、`reviewRounds`と`durableSubmissions`を分離（job schema 3）、authority不変時の`ERROR` / `BLOCKED`後新`changeId`で`userDecision`を不要化 |
| 0.7.0 | protocol v5（Skill 0.8.0）。固定3回上限を初回自動レビュー予算へ変更し、予算到達時状態`REVIEW_BUDGET_EXHAUSTED`、`budgetGrant`・`authorizedReviewRounds`（job schema 4）を導入してユーザーによるスキップ・追加レビュー許可に対応 |

0.5.0以降はpurpose sourceとproposalを入力へ埋め込み、承認済みbaselineが存在しない場合はnullを許します。proposal deltaには追加、削除、緩和など全変更を記録します。入力内のevidenceを使い、reviewerによるsource再取得は前提にしません。conformance recordはownerの実行を保証しません。旧v3 finding schemaをv4/v5へ読み替えません。

`COMPLETE`はproposalやapproved baselineを承認しません。完了後に別changeを始める場合は同じtaskKey、新しいchangeId、直近のcompleted runを指すpreviousRunIdを使います。approvedDesignに入れられるのはユーザーが実際に承認したbaselineだけです。以前のproposalを自動昇格せず、実際に承認済みなら既存decisionのbodyとauthorityをuserDecisionに引用して記録し、同じ承認を再要求しません。Runnerは前回inputからpurposeまたはapprovedDesignが変わる場合に新しい`changeId`と`userDecision`を要求します。`HUMAN_DECISION_REQUIRED`や`REVIEW_BUDGET_EXHAUSTED`後の新changeも新しい`changeId`と`userDecision`を要求します（スキップ許可のみでは新`changeId`へ進みません）。`ERROR` / `BLOCKED`後のdistinct changeは、残予算がありpurposeとapprovedDesignが不変なら新しい`changeId`のみで開始でき、`userDecision`は不要です。`FINDINGS`からは新`changeId`で逃げることはできず、必ず同一runの`continue`を使います。詳細は[technical reference](purpose-review-runner-technical-reference.md)を参照してください。
