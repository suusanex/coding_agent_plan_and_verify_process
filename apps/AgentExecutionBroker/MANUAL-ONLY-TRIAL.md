# Agent Execution Broker Operational v0 ManualOnly Trial

## 1. この手順の目的

この手順は、Agent Execution Broker Operational v0を実環境で確認するためのManualOnly試験手順である。設計書や実装コードを読んでいない担当者でも、準備、通常run、cancel smoke、証跡整理、後片付けを実施できることを目的とする。

試験は次の2本で構成する。

1. **通常run**: Codex Appから低リスクな実Issueを起動し、Copilot CLIの正常実行、terminal event、Inbox表示、同じrun IDによるbounded結果取得、worktreeのdiffとvalidationを確認する。
2. **cancel smoke**: 通常runとは別のdisposable worktreeと別runでCopilot processを起動後、`cancel_run`を実行し、cancel request、delivery、process termination、terminal event、Inbox表示を確認する。

2本を同じrunで兼ねてはならない。通常runの成功だけでcancel behaviorの確認済みとは扱わない。

## 2. 人手承認と安全条件

試験開始前に、担当者は次の2点を明示的に承認する。

- 使用する低リスクな実Issue
- ローカルに認証済みのGitHub Copilot CLI資格情報を、この試験の範囲で使用すること

次の条件を満たさない場合、試験を開始せず `NeedsHumanDecision` として停止する。

- 対象Issueが、破壊的変更、機密情報の移動、本番環境変更、外部サービスへの書き込みを要求しない
- 通常runとcancel smokeに、既存のユーザー作業を含まないdisposable worktreeを使用する
- 自動commit、push、merge、Issueへのコメント投稿を行わない
- prompt、資格情報、raw Copilot output、ユーザー固有の絶対パスを証跡へ保存しない
- Codex App/MCP/Hostを同じWindowsユーザーと同じ昇格レベルで実行する

この試験は実データと資格情報を使用する。認証失敗、対象Issueの不確実性、意図しないdiff、孤児processの疑いが発生した場合は、原因を推測して継続せず、その時点で停止する。

## 3. 必要な環境

試験担当者は、次を同じWindowsユーザーで利用できる状態にする。

- Windows
- .NET 8 SDK（Brokerのpublish用）
- .NET 11 preview SDKとWindows App SDK prerequisites（Inboxをsourceから起動する場合）
- GitHub Copilot CLI（認証済み）
- Codex AppとCodex CLI
- Codex Local Inbox、または同じLocal Spoolを読む起動済みのInbox
- 対象repositoryのcheckoutとIssueを扱える権限

最初に、バージョンとGit状態を確認する。出力へ資格情報が含まれていないことを確認する。

```powershell
dotnet --version
copilot --version
codex mcp --help
git --version
```

`copilot --version`はCLIの存在確認であり、認証成功を保証しない。認証状態が不明な場合は、組織で承認されたログイン確認方法を使う。認証tokenをこの文書、prompt、証跡へ貼り付けてはならない。

## 4. disposable worktreeを用意する

通常runとcancel smokeで、別々のworktreeを用意する。次の値は担当者の環境に合わせて置き換える。

```powershell
$repoRoot = '<absolute-repository-root>'
$baseRef = '<known-good-base-ref>'
$normalWorktree = '<absolute-normal-trial-worktree>'
$cancelWorktree = '<absolute-cancel-smoke-worktree>'
$trialRoot = '<absolute-trial-root>'
$trialSpool = Join-Path $trialRoot 'spool'

New-Item -ItemType Directory -Force -Path $trialRoot, $trialSpool | Out-Null
git -C $repoRoot worktree add --detach $normalWorktree $baseRef
git -C $repoRoot worktree add --detach $cancelWorktree $baseRef
git -C $normalWorktree status --short
git -C $cancelWorktree status --short
```

両worktreeの`git status --short`は空でなければならない。既存の変更が表示された場合、そのworktreeを試験に使わず、原因を確認する。`baseRef`、Issue番号、worktreeの対応関係は担当者だけが管理し、証跡にはユーザー固有の絶対パスを記録しない。

## 5. BrokerをpublishしてCodex Appへ登録する

MCP facadeとHostを同じpublish directoryへ配置する。HostはMCP facadeから必要時に起動されるため、Hostを別途常駐起動しない。

```powershell
$publishRoot = Join-Path $trialRoot 'agent-execution-broker'
$mcpProject = Join-Path $repoRoot 'apps\AgentExecutionBroker\AgentExecutionBroker.Mcp\AgentExecutionBroker.Mcp.csproj'
$hostProject = Join-Path $repoRoot 'apps\AgentExecutionBroker\AgentExecutionBroker.Host\AgentExecutionBroker.Host.csproj'
$mcpPath = Join-Path $publishRoot 'AgentExecutionBroker.Mcp.exe'
$hostPath = Join-Path $publishRoot 'AgentExecutionBroker.Host.exe'

New-Item -ItemType Directory -Force -Path $publishRoot | Out-Null
dotnet publish $mcpProject --configuration Release --output $publishRoot
dotnet publish $hostProject --configuration Release --output $publishRoot

if (-not (Test-Path -LiteralPath $mcpPath)) { throw "MCP executable was not published." }
if (-not (Test-Path -LiteralPath $hostPath)) { throw "Host executable was not published." }
```

試験専用のSpoolを使うことで、過去の通知と今回の通知を混同しないようにする。MCPが起動するHostとInboxの両方が、同じ`$trialSpool`を参照する必要がある。

既存の`agent-execution-broker`登録を確認する。

```powershell
codex mcp get agent-execution-broker --json
```

既存登録が試験専用のものなら、次のように削除してから再登録する。自分が所有していない登録は削除せず、管理者へ確認する。

```powershell
codex mcp remove agent-execution-broker
```

次のコマンドで、Host executableとSpoolをMCP processへ渡して登録する。

```powershell
codex mcp add agent-execution-broker `
  --env "AGENT_EXECUTION_BROKER_HOST_PATH=$hostPath" `
  --env "CODEX_NOTIFICATION_SPOOL_HOME=$trialSpool" `
  -- $mcpPath

codex mcp get agent-execution-broker --json
```

登録結果で次を確認する。

- commandがpublish済みの`AgentExecutionBroker.Mcp.exe`である
- `AGENT_EXECUTION_BROKER_HOST_PATH`がpublish済みのHost executableを指す
- `CODEX_NOTIFICATION_SPOOL_HOME`が試験用Spoolを指す
- URL型MCPや別providerの登録になっていない

MCP登録後、Codex Appを再起動するか、MCP server一覧を再読み込みして`agent-execution-broker`のtoolsが見える状態にする。

## 6. Inboxを同じSpoolへ接続する

試験用Spoolを読むInboxを起動する。sourceから起動する場合は、次を実行する。

```powershell
$env:CODEX_NOTIFICATION_SPOOL_HOME = $trialSpool
dotnet run --project (Join-Path $repoRoot 'apps\CodexLocalInbox\CodexLocalInbox.csproj')
```

インストール済みのInboxを使う場合も、起動時に同じ`CODEX_NOTIFICATION_SPOOL_HOME`が設定されるようにする。ユーザー環境へ永続的に環境変数を追加する必要はない。Inboxが起動したら、試験用Spoolが空であることを確認する。

```powershell
@(Get-ChildItem -LiteralPath $trialSpool -Filter 'agent-execution-terminal-*.json' -ErrorAction SilentlyContinue).Count
```

既存イベントがある場合は、試験用Spoolを新しい空directoryへ変更してから続行する。過去イベントを削除して試験結果を作ってはならない。

## 7. 通常runを実施する

### 7.1 Codex Appから起動する

Codex Appで`agent-execution-broker`の`start_run` toolを呼び出す。入力は次の契約に従う。

| Field | Value |
| --- | --- |
| `provider_id` | `github-copilot-cli` |
| `working_directory` | `$normalWorktree`の絶対パス |
| `prompt` | 承認済みIssueの低リスクな実装指示 |
| `execution_profile` | `coding-v1` |
| `repository` | 表示用のrepository名。不要なら`null` |

promptは、対象Issue、変更範囲、validation方法、commit/pushを行わないことを明記する。例:

```text
承認済みのIssue #<issue-number>をこのworktreeで実装する。
対象範囲をIssue本文に限定し、破壊的な環境変更や外部サービスへの書き込みは行わない。
実装後にIssueで指定されたvalidationを実行し、変更点とvalidation結果を報告する。
commit、push、merge、Issueへのコメント投稿は行わない。
```

実際のprompt全文は証跡へ保存しない。`start_run`の応答から`run_id`だけを記録する。応答が非同期にrun IDを返し、Copilot終了までCodex Appのtool callが占有されないことを確認する。

### 7.2 run stateを確認する

Codex Appから同じ`run_id`で`get_run`を呼び、次を確認する。

1. 初期状態が`Accepted`、`Starting`、または`Running`のいずれかである
2. `provider_id`が`github-copilot-cli`である
3. `execution_profile`が`coding-v1`である
4. `host_instance_id`、`job_id`、`provider_session_id`、`provider_process_id`、`prompt_digest`が取得できる
5. `state_transitions`にauthority、sequence、timestampがある

terminalになるまで、数秒間隔で`get_run`を再実行する。正常終了の期待値は次の通り。

- `state`: `Exited`
- `exit_code`: `0`
- `cancel_requested`: `false`
- `notification_disposition`: publish成功を示す値、またはnullの場合はSpoolを直接確認する

`StartFailed`、`HostStopping`、`HostLostWorkerTreeTerminated`、非zero exit codeの場合は通常run成功と判定しない。認証、publish、working directory、Issue scopeを確認し、そこで停止する。

### 7.3 bounded outputを取得する

同じ`run_id`で`get_output`を呼ぶ。最初の取得は次のboundを明示する。

```text
after_sequence = 0
max_records = 200
max_bytes = 262144
```

応答の`records`、`next_after_sequence`、`has_more`、`truncation_reason`を確認する。`has_more`が`true`の場合は、前回の`next_after_sequence`を次の`after_sequence`へ渡して繰り返す。取得結果を証跡へそのまま貼り付けず、取得ページ数、最終cursor、`has_more=false`になったかだけを記録する。

### 7.4 terminal eventとInboxを確認する

Spoolに、今回のrun IDに対応するterminal eventが1件だけ生成されていることを確認する。

```powershell
$events = @(Get-ChildItem -LiteralPath $trialSpool -Filter 'agent-execution-terminal-*.json')
$events | Select-Object -ExpandProperty FullName
```

対象JSONの次の値を、run IDと照合する。

- `source`: `agent-execution-broker.run-terminal`
- `source_event_id`: `agent-execution-broker:run:<run-id>:terminal`
- `run_id`: `get_run`で取得したrun ID
- `provider_id`: `github-copilot-cli`
- `observed_status`: `Exited`
- `result_locator`: `broker-run:<run-id>`

Inboxで同じ`source_event_id`のBroker itemが1件表示されることを確認する。Broker locatorは表示・コピー用であり、Codex resume URIとして起動されない。Inboxが既存Codex callback itemとBroker itemを混同していないことも確認する。

### 7.5 worktree結果を確認する

通常runのworktreeで、Issueに対応するdiffとvalidationを確認する。

```powershell
git -C $normalWorktree status --short
git -C $normalWorktree diff --stat
git -C $normalWorktree diff --check
```

Issueで指定されたvalidationを実行し、変更が対象Issueの範囲内であることを確認する。Unexpected diff、validation failure、機密情報の生成を検出した場合は、commitやpushを行わず試験を停止する。

## 8. cancel smokeを実施する

### 8.1 別runを起動する

通常runとは別の`$cancelWorktree`を使い、Codex Appから新しい`start_run`を呼ぶ。run IDも新しいものを使う。promptはdisposable worktree内で完結する低リスクな確認作業にし、通常runのIssue実装結果をcancel smokeへ持ち込まない。

processが起動したことを観測できるよう、次の順序で進める。

1. `start_run`の応答からcancel smoke用run IDを記録する
2. `get_run`を呼び、`state`が`Running`になるまで待つ
3. `provider_process_id`がnullでないことを確認する
4. `state`がterminalになる前に`cancel_run`を呼ぶ

runが`Running`になる前に`CancelledBeforeStart`または`Exited`になった場合、running process cancelの証跡には使わない。新しいdisposable runで再実行する。最初からterminalだったrunに`cancel_run`を呼んでもcancel smokeの成功とは扱わない。

### 8.2 cancel結果を確認する

`cancel_run`の応答はrequest受理を示すだけで、process termination完了を意味しない。`get_run`でterminal stateになるまで追跡する。

running process cancel smokeの期待値は次の通り。

- `cancel_requested`: `true`
- `cancel_delivery`: `Delivered`
- `state`: `CancelledByBroker`
- `completed_at`: nullではない
- `state_transitions`: `CancelRequested`とterminal transitionを含む
- terminal eventがcancel run IDで1件生成される
- Inboxに同じ`source_event_id`のBroker itemが1件表示される

次の結果は成功扱いにしない。

| 観測結果 | 扱い |
| --- | --- |
| `CancelledBeforeStart` | process起動前cancel。running cancel smoke未達として記録し、新しいrunで再試行する。 |
| `Exited`かつ`CancelDelivery=Pending` | natural exitがdeliveryより先に観測された可能性がある。cancel smoke成功とは扱わない。 |
| `ExitedAfterFailedCancel` | kill delivery failure。試験を停止し、失敗証跡として残す。 |
| `HostLostWorkerTreeTerminated` | Host authorityまたはJob Objectの問題。試験を停止する。 |
| nonzero exit codeのみ | Killによる終了ではあり得るが、stateとdeliveryが期待値でなければ成功扱いにしない。 |

terminal確認後、`provider_process_id`を使ってprocessが残っていないことを確認する。PIDの再利用を断定せず、確認結果は真偽だけをsanitized evidenceへ記録する。processが残っている、または孤児化が疑われる場合は、次のrunを開始せず、担当者の通常のWindows process管理手順で安全に停止してから報告する。

cancel runについても、通常runと同じbounded `get_output`、terminal event、Inbox確認を行う。raw outputは証跡へ保存しない。

## 9. 証跡をsanitized recordとして残す

試験結果は、次の項目だけを使ってsanitized recordにまとめる。資格情報や作業データを含むraw logをcommitしてはならない。

```text
trial_date_utc: <UTC date>
approval: <human approval reference or owner>
target_issue: <repository label and issue number>
provider: github-copilot-cli
provider_version: <copilot --version result>
broker_source_ref: <commit or build identifier>
normal_run_id: <UUID>
normal_started_at_utc: <timestamp>
normal_completed_at_utc: <timestamp>
normal_terminal_state: Exited
normal_exit_code: 0
normal_source_event_id: agent-execution-broker:run:<UUID>:terminal
normal_inbox_observed: true|false
normal_output_pages: <count>
normal_output_last_cursor: <sequence>
normal_output_has_more: true|false
normal_diff_summary: <short summary without absolute paths or raw content>
normal_validation_summary: <commands/categories and result>
cancel_run_id: <UUID>
cancel_terminal_state: CancelledByBroker|other observed state
cancel_delivery: Delivered|other observed value
cancel_process_termination_observed: true|false
cancel_source_event_id: agent-execution-broker:run:<UUID>:terminal
cancel_inbox_observed: true|false
friction: <short operational observations>
remaining_work: <short list>
```

記録してはならないもの:

- Copilot、GitHub、Codexのtokenやcredential
- full prompt
- raw Copilot stdout/stderr、agent log、tool result
- ユーザー固有の絶対パス
- Issue本文全体や機密なdiff

Issue番号、run ID、provider/version、UTC時刻、terminal state、exit code、cancel delivery、`source_event_id`、Inbox確認、bounded outputのcursor、diff/validationの要約だけを残す。結果をcommitする場合も、commit前にこの除外条件を再確認する。

## 10. 失敗時の停止基準

次のいずれかに該当したら、試験を成功扱いにせず停止する。

- MCP toolが見えない、MCP登録先やHost pathが不明確
- Hostを起動できない、named pipeへ接続できない、ユーザー/elevation levelが一致しない
- Copilot認証失敗、provider/profile拒否、working directory拒否
- 対象Issueの範囲を超える変更、unexpected diff、validation failure
- terminal eventがSpoolに出ない、別Spoolを読んでいる、Inboxに表示されない
- `get_output`がrun IDを跨ぐ、boundを守らない、cursorが進まない
- cancel後にdelivery failure、terminal stateの巻き戻り、process残留、孤児processの疑いがある
- prompt、raw output、credential、機密diffを保存しそうになった

失敗時は、run ID、観測したstate、exit code、発生時刻、公開可能な短いエラー概要だけを記録する。原因を推測して「成功」に補正してはならない。

## 11. 後片付け

1. 通常runとcancel smokeがterminalになっていることを確認する。
2. sanitized recordを作成し、raw outputを保存していないことを確認する。
3. 試験専用のMCP登録だけを削除する。

   ```powershell
   codex mcp remove agent-execution-broker
   ```

4. 他のrunがないことを確認してから、MCP/Host/Codex App/Inboxを終了する。Hostを終了するとJob Objectによりworker treeも停止する。
5. diffと証跡を確認してから、worktreeを通常のGit手順で扱う。変更を残す必要がある場合は削除しない。
6. 試験用Spoolは、sanitized recordの確認が終わるまで削除しない。Operational v0には自動retentionやmanual cleanup commandがない。

worktreeを削除する場合は、未保存変更がないことを確認してから、`git worktree remove <path>`を実行する。`--force`で変更を破棄してはならない。

## 12. 完了判定

ManualOnly試験を完了と判定できるのは、次をすべて満たした場合だけである。

- 通常runがCodex App → production MCP → Host → authenticated Copilot CLI → Spool → Inbox → bounded result retrievalまで通った
- 通常runのdiffとvalidationを担当者が確認した
- 別worktreeのcancel smokeで、process起動後の`cancel_run`を実施した
- cancel smokeでrequest、delivery、termination、terminal event、Inboxを確認した
- 通常runとcancel smokeのrun ID、worktree、証跡が混同されていない
- sanitized recordに必要な項目があり、禁止された秘密情報・raw data・ユーザー固有absolute pathがない

上記の一部だけを満たした場合は、`ManualVerificationRequired`または`NeedsHumanDecision`のまま残し、Operational v0のformal completionやclose-readyを宣言しない。
