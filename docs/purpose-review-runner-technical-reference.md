# Purpose Review Runner Technical Reference

この文書はPurpose Review Runner protocol v4のCLI、ReviewInput、状態、provider境界を説明します。通常利用は[Runner README](../apps/PurposeReviewRunner/README.md)、工程契約は[`$persistent-purpose-review`](../apm-packages/persistent-purpose-review/README.md)が正本です。

## Public CLI

```powershell
purpose-review-runner version
purpose-review-runner start --repository C:\path\to\repo --input C:\path\to\review-input.json
purpose-review-runner status --run <run-id>
purpose-review-runner continue --run <run-id> --input C:\path\to\updated-review-input.json
```

protocolは4、Runner versionは0.6.0、input schemaVersionは1です。`start`と`continue`は入力検証後にdurable jobを登録してworkerを起動し、通常は`RUNNING`を返します。結果は同じrun IDの`status`で取得します。結果不明時にstart/continueを再submitせず、先にstatusを確認します。

## ReviewInput schema

JSONはcamelCaseで、未知fieldを拒否します。必須fieldは次のとおりです。

| Field | 形式と意味 |
| --- | --- |
| `schemaVersion` | `1` |
| `taskKey` | repository内で連続提出を識別する安定ID |
| `changeId` | 対象changeの安定ID |
| `previousRunId` | 初回はnull、linked startでは直前のdurable run ID |
| `userDecision` | 通常はnull。ユーザー判断によりpurposeまたはapprovedDesignを変える場合、または`HUMAN_DECISION_REQUIRED`後に新しい`changeId`へ進む場合に、その本文とauthorityを記録 |
| `purpose` | `version`, `sources`, `body`, `original`, `authority`。元の目的と根拠source、authorityを含む |
| `approvedDesign` | `version`, `body`, `authority`。承認済みbaselineがなければnull |
| `proposal` | `version`, `body`, `delta`。提案設計全体とbaselineからの追加・削除・緩和を含む差分 |
| `evidence` | `id`, `source`, `body`。各項目の本文を埋め込み、外部source fetchに依存しない |
| `responses` | `findingId`, `body`, `evidence`。findingへの応答と証拠ID |
| `conformance` | `owner`, `plan`, `evidence`。実行・確認のowner、計画、証拠ID |
| `priorReviewHistory` | optional / Runner-owned。利用者inputでは省略または空にする。ERROR / BLOCKED後のlinked runではRunnerが前runのreview履歴を設定 |

証拠IDは一意で、responses/conformanceの参照先は入力内に存在する必要があります。purpose、approvedDesign、proposalのhash/versionを`inputBinding`としてresultへ返します。continueではpurposeとapprovedDesign baselineは固定し、提案のみ新しいversionで更新できます。bindingは評価対象inputの識別情報であり、内容の正しさを保証しません。conformance recordもownerの実施・確認を保証しません。

初回taskの`start`は`previousRunId: null`です。すでにtaskKeyのlineageがある場合、直前durable run ID、同一repository、適切なterminal statusを要求します。`FINDINGS`は同じrunのcontinueが必要であり、新しい`changeId`に変えて`start`しても`CONTINUE_REQUIRED`で拒否します。continue inputはそのrunのstart時に設定された`previousRunId`値を保ちます。

Runnerは同一changeで成立した有効なreview結果の回数（`reviewRounds`、最大3）と、operational attemptを含む累積提出数（`durableSubmissions`、上限なし）を分離して管理します。provider実行やprotocol parseが成立する前に終了したoperational failure（`WORKER_START_FAILED`、`WORKER_ABANDONED`、`PROVIDER_FAILED`、`PROVIDER_TIMEOUT`、`REVIEW_OUTPUT_MISSING`、`REVIEW_PARSE_FAILED`等）や未完了予約（`SUBMISSION_INCOMPLETE`）は`reviewRounds`を消費しません。`ERROR` / `BLOCKED`後に同じ`changeId`で新しいlinked runを開始する場合は、以前に成立した`reviewRounds`と`priorReviewHistory`を引き継ぎ、同一changeで3回のreview成立（`MAX_REVIEW_ROUNDS_REACHED`）に達した後の再提出を拒否します。3回目の成立したreviewが`FINDINGS`だった場合は`HUMAN_DECISION_REQUIRED`へ遷移します。

前回inputからpurposeまたはapprovedDesignを変える場合は、常に新しい`changeId`と非null `userDecision`が必要です（`USER_DECISION_REQUIRED`）。`ERROR` / `BLOCKED`後にpurposeとapprovedDesignを変えないまま異なる`changeId`の新しいchangeを開始する場合は、`userDecision`を要求せず新しい3-round review budget（`reviewRounds: 0`）を開始します。`HUMAN_DECISION_REQUIRED`後は異なる`changeId`と非null `userDecision`が必須です。`COMPLETE`したchangeは再提出できません。完了後のdistinct changeは同じtaskKey、新changeId、直近のCOMPLETE runを指すpreviousRunIdでstartします。proposalやCOMPLETEを承認済みbaselineとして自動昇格しません。既に存在するユーザー承認を使う場合、その決定sourceを`userDecision`に記録し、同じ承認を再度要求しません。taskKey/changeIdはcallerが提供するため、同じ実作業に対するID aliasやuserDecisionの真偽はRunnerが認証しません。

## Result protocol

stdoutは単一JSONです。共通fieldは`protocolVersion`、`runnerVersion`、`runId`、`round`、`status`、`terminal`、`findings`、`message`、`error`、`jobStatus`、`reviewRounds`、`durableSubmissions`です。`round`はそのrun内のround番号、`reviewRounds`は同一changeのlinked runsを通じた累積成立review回数（0〜3）、`durableSubmissions`はoperational attemptを含む累積提出回数です。purpose/design review resultでは`reviewKind: "purpose-design-alignment"`と`inputBinding`を返します。bindingは`purposeHash` / `purposeVersion`、nullable `approvedDesignHash` / `approvedDesignVersion`、`proposalHash` / `proposalVersion`を含みます。

statusは`RUNNING`、`FINDINGS`、`COMPLETE`、`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`です。`FINDINGS`には1件以上のfindingが必要で、`COMPLETE`にはfindingがありません。`HUMAN_DECISION_REQUIRED`または`BLOCKED`でも、入力から独立して確認できる未解決findingを保持できます。`BLOCKED`は1件以上のinformation requestも必要です。各findingのfieldは`id`、`severity`、`title`、`summary`、`evidence`、`requiredOutcome`です。information requestは`id`、`source`、`question`、`whyNeeded`を持ちます。provider/process diagnosticsはstderrへ出し、stdoutへ別形式を混ぜません。

`COMPLETE`はpurpose/design reviewの完了であり、目的達成、設計承認、実装完了、runtime conformanceの保証ではありません。`HUMAN_DECISION_REQUIRED`、`BLOCKED`、`ERROR`もterminalです。terminal runはcontinueできません。

## State and lineage

run state、job/result、入力snapshot、task lineageはuser-level state directoryに保存します。Runnerの診断ログには例外詳細が記録されます。prompt / response transcriptには目的やrepository由来情報が含まれる可能性があるため、共有前に確認してください。credentialはprompt本文や結果JSONに含めません。

`job.json`のschemaVersionは3です。旧v3のschema 1や0.5.0のschema 2、および`reviewRounds`を持たないstate/lineage recordは拒否します。旧job/state/resultを新schemaへ自動読み替えしません。

Provider設定はrun開始時にsnapshotされます。既存runへのconfig変更は反映されません。入力snapshotはroundごとに保存されます。続きの入力は前roundの目的bindingを保持し、提案version/hashや証拠・応答・conformanceを更新できます。

## Worker

workerは親CLIのstdin/stdout/stderrから独立して起動します。WindowsではJob Object内外に応じたdetached起動経路を使い、分離できなければ`WORKER_START_FAILED`で停止します。OS固有処理の詳細とqualification境界はsourceとテストを参照してください。

## Provider boundary

対応providerはCodex CLIとGitHub Copilot CLIです。Grok Buildは対応対象外です。configの`profile`はnull固定で、非nullは拒否します。provider固有の認証とCLI実行は利用者の環境が担当します。purpose reviewの提示inputから一つのpromptを生成し、provider adapterはその文字列をCLIへ渡します。CLI構文やsession handleはRunnerが所有します。

Runnerはruntime契約（review入力とprompt生成、session handle継続、`BEGIN_PURPOSE_REVIEW` / `END_PURPOSE_REVIEW`応答検証、lineageと3 review rounds上限）をhard-failとし、provider CLI versionの完全一致はruntime hard-fail条件としません。実機確認済みの基準CLI版（Codex `0.165.0`、Copilot `1.0.105`）は`LastQualifiedVersion`メタデータとして保持します。feature名・MCP名に限定せず、reviewer探索を抑制するためだけのoptional guardrailはbest-effortの対象とし、CLI側で利用不能になったこと自体をruntime incompatibilityにはしません。ただし事前に利用可能性を判定できる範囲でのみbest-effort適用を行い、review本体の失敗後に制限を外した弱い設定で再試行するfallbackは行いません。事前capability discovery（`codex features list`、`copilot mcp list --json`）は短い専用timeoutで実行し、成功時は得られた対象だけを無効化し、非0終了・parse不能・timeout時はトレースへ記録して残りのguardrailで続行します。`PROVIDER_TIMEOUT`はreview本体の実行がtimeoutした場合にのみ返します。

Runnerはrepository外のrun directoryからCLIを起動し、埋め込まれたreview inputから作ったpromptだけをstdinへ渡します。continueは同じprovider sessionを再利用します。Codexの初回実行ではCLIの通常read-only sandboxとapproval設定を使い、resume時はsession設定としてread-only sandboxとapproval policyを明示します。両方でuser config/rulesの読込を抑え、`codex features list`で確認できた探索系feature（shell、browser/web/search、apps/MCP、code mode、multi-agent、image/view、in-app、skills、plugins、hooks、memories）を`--disable`で無効化します。reviewerにはrepository探索、外部調査、tool use、delegationを禁じるrole promptを与えますが、Codex host collaboration等が環境に残る可能性があるため、完全なcapability isolationを保証しません。

RunnerとSkillは独自のauthenticationや追加sandbox infrastructureを提供しません。Copilotは実機でtool inventory 0件を確認した既存のより制限された設定を維持しつつ、動的MCP列挙（`copilot mcp list --json`）が失敗した場合でも`--disable-builtin-mcps`、`--available-tools=report_intent`、`--deny-tool`等の他guardrailを維持して実行します。そのCopilot実測をCodexにも適用できるとは扱いません。Codexの過去の全機能disable試行は歴史的な証拠として別に記録し、現在の運用境界・後続実行とは区別します。実装review用のshell調査やimplementation test評価はreview scopeに含みません。
