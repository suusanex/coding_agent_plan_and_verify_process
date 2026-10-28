# Purpose Review Runner Technical Reference

この文書はPurpose Review Runner protocol v4のCLI、ReviewInput、状態、provider境界を説明します。通常利用は[Runner README](../apps/PurposeReviewRunner/README.md)、工程契約は[`$persistent-purpose-review`](../apm-packages/persistent-purpose-review/README.md)が正本です。

## Public CLI

```powershell
purpose-review-runner version
purpose-review-runner start --repository C:\path\to\repo --input C:\path\to\review-input.json
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id> --input C:\path\to\updated-review-input.json
```

protocolは4、Runner versionは0.5.0、input schemaVersionは1です。`start`と`continue`は入力検証後にdurable jobを登録してworkerを起動し、通常は`RUNNING`を返します。結果は同じrun IDの`status`で取得します。結果不明時にstart/continueを再submitせず、先にstatusを確認します。

## ReviewInput schema

JSONはcamelCaseで、未知fieldを拒否します。必須fieldは次のとおりです。

| Field | 形式と意味 |
| --- | --- |
| `schemaVersion` | `1` |
| `taskKey` | repository内で連続提出を識別する安定ID |
| `changeId` | 対象changeの安定ID |
| `previousRunId` | 初回はnull、linked startでは直前のdurable run ID |
| `userDecision` | 通常はnull。ユーザー判断によりpurposeまたはapprovedDesignを変える場合、その本文とauthorityを記録。`HUMAN_DECISION_REQUIRED`後、および`ERROR` / `BLOCKED`後のdistinct changeにも必要 |
| `purpose` | `version`, `sources`, `body`, `original`, `authority`。元の目的と根拠source、authorityを含む |
| `approvedDesign` | `version`, `body`, `authority`。承認済みbaselineがなければnull |
| `proposal` | `version`, `body`, `delta`。提案設計全体とbaselineからの追加・削除・緩和を含む差分 |
| `evidence` | `id`, `source`, `body`。各項目の本文を埋め込み、外部source fetchに依存しない |
| `responses` | `findingId`, `body`, `evidence`。findingへの応答と証拠ID |
| `conformance` | `owner`, `plan`, `evidence`。実行・確認のowner、計画、証拠ID |
| `priorReviewHistory` | optional / Runner-owned。利用者inputでは省略または空にする。ERROR / BLOCKED後のlinked runではRunnerが前runのreview履歴を設定 |

証拠IDは一意で、responses/conformanceの参照先は入力内に存在する必要があります。purpose、approvedDesign、proposalのhash/versionを`inputBinding`としてresultへ返します。continueではpurposeとapprovedDesign baselineは固定し、提案のみ新しいversionで更新できます。bindingは評価対象inputの識別情報であり、内容の正しさを保証しません。conformance recordもownerの実施・確認を保証しません。

初回taskの`start`は`previousRunId: null`です。すでにtaskKeyのlineageがある場合、直前durable run ID、同一repository、適切なterminal statusを要求します。`FINDINGS`は同じrunのcontinueが必要です。continue inputはそのrunのstart時に設定された`previousRunId`値を保ちます。`ERROR` / `BLOCKED`は同じchangeの新しいlinked runを許可しますが、最大3 durable submissionsの予算を共有します。異なるchangeIdのchangeは新しいrunになり、`ERROR` / `BLOCKED`後は`userDecision`が必要です。新しいlinked runの`previousRunId`は直前terminal run IDです。`HUMAN_DECISION_REQUIRED`後は異なるchangeIdと非null `userDecision`が必須です。`COMPLETE`したchangeは再提出できません。完了後のdistinct changeは同じtaskKey、新changeId、直近のCOMPLETE runを指すpreviousRunIdでstartします。前回inputからpurposeまたはapprovedDesignを変える場合は`userDecision`を要求します。proposalやCOMPLETEを承認済みbaselineとして自動昇格しません。既に存在するユーザー承認を使う場合、その決定sourceを`userDecision`に記録し、同じ承認を再度要求しません。taskKey/changeIdはcallerが提供するため、同じ実作業に対するID aliasやuserDecisionの真偽はRunnerが認証しません。

## Result protocol

stdoutは単一JSONです。共通fieldは`protocolVersion`、`runnerVersion`、`runId`、`round`、`status`、`terminal`、`findings`、`message`、`error`、`jobStatus`です。purpose/design review resultでは`reviewKind: "purpose-design-alignment"`と`inputBinding`を返します。bindingは`purposeHash` / `purposeVersion`、nullable `approvedDesignHash` / `approvedDesignVersion`、`proposalHash` / `proposalVersion`を含みます。

statusは`RUNNING`、`FINDINGS`、`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`です。`FINDINGS`には1件以上のfindingが必要で、`COMPLETE`にはfindingがありません。`HUMAN_DECISION_REQUIRED`または`BLOCKED`でも、入力から独立して確認できる未解決findingを保持できます。`BLOCKED`は1件以上のinformation requestも必要です。各findingのfieldは`id`、`severity`、`title`、`summary`、`evidence`、`requiredOutcome`です。information requestは`id`、`source`、`question`、`whyNeeded`を持ちます。provider/process diagnosticsはstderrへ出し、stdoutへ別形式を混ぜません。

`COMPLETE`はpurpose/design reviewの完了であり、目的達成、設計承認、実装完了、runtime conformanceの保証ではありません。`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`もterminalです。terminal runはcontinueできません。

## State and lineage

run state、job/result、入力snapshot、task lineageはuser-level state directoryに保存します。Runnerの診断ログには例外詳細が記録されます。prompt / response transcriptには目的やrepository由来情報が含まれる可能性があるため、共有前に確認してください。credentialはprompt本文や結果JSONに含めません。

`job.json`のschemaVersionは2です。旧v3のschema 1には`contextPaths`があり、新しいRunnerは拒否します。旧job/resultを新protocolへ読み替えません。

Provider設定はrun開始時にsnapshotされます。既存runへのconfig変更は反映されません。入力snapshotはroundごとに保存されます。続きの入力は前roundの目的bindingを保持し、提案version/hashや証拠・応答・conformanceを更新できます。

## Worker

workerは親CLIのstdin/stdout/stderrから独立して起動します。WindowsではJob Object内外に応じたdetached起動経路を使い、分離できなければ`WORKER_START_FAILED`で停止します。OS固有処理の詳細とqualification境界はsourceとテストを参照してください。

## Provider boundary

対応providerはCodex CLIとGitHub Copilot CLIです。Grok Buildは対応対象外です。configの`profile`はnull固定で、非nullは拒否します。provider固有の認証とCLI実行は利用者の環境が担当します。purpose reviewの提示inputから一つのpromptを生成し、provider adapterはその文字列をCLIへ渡します。CLI構文やsession handleはRunnerが所有します。

Runnerはrepository外のrun directoryからCLIを起動し、埋め込まれたreview inputから作ったpromptだけをstdinへ渡します。continueは同じprovider sessionを再利用します。Codexの初回実行ではCLIの通常read-only sandboxとapproval設定を使い、resume時はsession設定としてread-only sandboxとapproval policyを明示します。両方でuser config/rulesの読込を抑え、shell、browser/web/search、apps/MCP、code mode、multi-agent、image/view、in-app、skills、plugins、hooks、memoriesの探索機能を無効化します。reviewerにはrepository探索、外部調査、tool use、delegationを禁じるrole promptを与えますが、Codex host collaboration等が環境に残る可能性があるため、完全なcapability isolationを保証しません。

RunnerとSkillは独自のauthenticationや追加sandbox infrastructureを提供しません。Copilotは実機でtool inventory 0件を確認した既存のより制限された設定を維持します。そのCopilot実測をCodexにも適用できるとは扱いません。Codexの過去の全機能disable試行は歴史的な証拠として別に記録し、現在の運用境界・後続実行とは区別します。実装review用のshell調査やimplementation test評価はreview scopeに含みません。
