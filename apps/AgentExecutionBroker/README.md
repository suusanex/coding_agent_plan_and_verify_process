# Agent Execution Broker Operational v0

Agent Execution Brokerは、Codex Appのstdio MCP facadeからGitHub Copilot CLIを非同期実行するWindows向けlocal Brokerである。MCP processはworkerを所有せず、別processのHostがnamed pipe、durable run registry、output、terminal eventを所有する。

Named pipeは同一PCのlocal endpointとしてOS default ACLを使う。v0ではsame-user-only ACLを保証せず、remote transportも提供しない。

## Build

```powershell
dotnet build .\AgentExecutionBroker.slnx
```

MCP facadeとHostを同じ配布directoryへpublishする。MCP facadeがHostを起動するには、`AGENT_EXECUTION_BROKER_HOST_PATH`へHost executableのabsolute pathを設定する。

## Codex MCP registration

人手での作業が必要: MCP facade executableをpublish後、Codex CLIから次を実行する。

```powershell
codex mcp add agent-execution-broker -- <absolute-path-to-AgentExecutionBroker.Mcp.exe>
```

## Tool contract

- `start_run`: `provider_id: github-copilot-cli`、absolute `working_directory`、non-empty `prompt`、required `execution_profile: coding-v1`を受ける。
- `coding-v1`: Copilot CLIへ `read,write,shell` だけを明示許可する。raw CLI flags、URL、MCP、memory、`--allow-all*`は受け付けない。
- `get_run` / `list_runs`: durable stateを返す。`list_runs`はdefault 50、maximum 100件でopaque cursorを使う。
- `get_output`: `after_sequence`とrecord/byte boundを使う。defaultは200 records / 256 KiB、maximumは500 records / 1 MiBである。
- `cancel_run`: cancel request、delivery、terminal observationを別に保存する。request受理だけをterminationとして扱わない。worker開始前は`CancelledBeforeStart`としてCopilotを起動しない。

## Lifecycle and recovery

HostはWindows Job Objectの`KILL_ON_JOB_CLOSE`を唯一所有し、worker treeをJobへassignする。Hostが終了またはクラッシュするとJob handleが閉じ、Host所有worker treeは停止する。次回Host起動時に非terminal registry recordは`HostLostWorkerTreeTerminated`へreconcileされる。exit codeやagent semantic resultはこのreconciliationから推測しない。

Run dataは`%LOCALAPPDATA%\AgentExecutionBroker`へ保存する。absolute overrideは`AGENT_EXECUTION_BROKER_HOME`である。Operational v0はautomatic retentionおよびmanual cleanup commandを提供しない。

health checkは`list_runs`でHostへの接続とdurable registry読取を確認する。停止はHost processを終了させる。Job Objectによりworker treeも停止する。Brokerはprovider共通resumeを実装しないため、terminal eventを確認した後のレビュー、追加指示、または新しい`start_run`は人手で判断する。

## Notification and Inbox

terminal時にHostは既存local spoolへ`agent-execution-terminal-v1`をatomic publishする。`spool-item-v1`は変更しない。InboxのBroker locatorはdisplay/copy専用であり、URI launch actionを持たない。

## Operational trial

## Trial procedure and evidence policy

人手での作業が必要: Trial前にMCPとHostをpublishし、`AGENT_EXECUTION_BROKER_HOST_PATH`へHost executableのabsolute pathを設定し、`codex mcp add agent-execution-broker -- <absolute-path-to-AgentExecutionBroker.Mcp.exe>`でproduction MCPを登録する。Inboxはproduction `CODEX_NOTIFICATION_SPOOL_HOME`を読む状態にする。

通常runは、低リスクな実IssueをCodex Appから起動し、非同期return、Copilot正常終了、terminal notification、Inbox表示、同じrun IDの`get_run`/bounded `get_output`、diff/validation確認まで通す。別のdisposable worktree/runでcancel smokeを行い、Copilot process起動後に`cancel_run`し、request、delivery、terminationを確認する。通常runとcancel smokeを同じrunで兼ねない。

証跡にはrun ID、対象Issue、provider/version、開始・終了時刻、terminal state/exit code、`source_event_id`、Inbox確認、`get_output`のcursor/`has_more`、結果diffとvalidation概要、摩擦、残件だけをsanitized recordとして残す。credential、full prompt、raw Copilot output、ユーザー固有absolute pathはcommitしない。これをEarly Operational Trialとする。provider/wiring/profile/transportがmaterialに変わった場合だけformal E2Eを再実行する。
