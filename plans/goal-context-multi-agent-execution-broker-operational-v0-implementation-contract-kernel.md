# Implementation Contract Kernel: Agent Execution Broker Operational v0

## スコープ

`plans/goal-context-multi-agent-execution-broker-operational-v0-plan.md` を唯一の要求 authority とし、RiskTriage が選択した `RC-BRK-001`〜`RC-BRK-004` を一つの `standard-slice` production vertical pass として実現するための、実装可能な production address、dependency、責務境界を固定する。コード、テスト、実プロバイダーの実行はこの pass では行わない。

採用する最初の production worker は、ローカルに導入済みの GitHub Copilot CLI `1.0.79` とする。これは Codex App とは異なる provider であり、公式の programmatic mode とローカル help が `-p`、`-C`、`--output-format`、`--no-ask-user` を提供することを確認した evidence-backed selection である。Codex CLI を worker にする代替案は `FR-011` により不採用とする。

## Plan が要求する実装要件

| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |
| `FR-001`,`FR-002`,`AC-001` | Codex App から非同期に run を開始し、request lifetime と worker owner を分離する | ローカル `codex mcp add` は stdio command を登録でき、Copilot CLI は non-interactive prompt を受ける。新規 Host/MCP facade が必要。 | MissingButRequired |
| `FR-003`〜`FR-009`,`AC-002`〜`AC-007` | durable run authority、no-orphan worker ownership、単調 state、bounded output、cancel、再起動後取得 | 既存 Broker 実装はない。Windows Job Object、BCL の JSON/file/NamedPipe/Process で実装可能。 | MissingButRequired |
| `FR-010`〜`FR-012`,`AC-008`,`AC-009` | provider-neutral contract と non-Control-UI production adapter、admission rejection | Copilot CLI 1.0.79 の `-p`、`-C`、`--output-format json`、`--no-ask-user`、valid UUID `--session-id`、selective `--allow-tool` を公式仕様とローカル help で確認。 | Confirmed |
| `FR-013`,`FR-014`,`AC-010`〜`AC-013` | provider-neutral terminal event を既存 spool/inbox plane へ偽装なく渡す | `spool-item-v1` は Codex callback 固有の厳密10 field/source であり、Broker event の代用にできない。Inbox は `*.json` scan と `source_event_id` dedup を持つ。 | MissingButRequired |
| `FR-015`,`AC-014` | install/start/stop/health/run/output/cancel/manual resume の手順 | 既存 runtime/Inbox README の運用記述形式を再利用できる。Broker docs は新規。 | MissingButRequired |
| `FR-016`,`FR-017`,`AC-015`〜`AC-018` | actual Codex App + real issue による production E2E と early trial | Codex は local stdio MCP server を登録可能。実 App 操作と provider credential は未実行であり ManualOnly。 | Confirmed |

## Dependency と API surface の確認結果

| Dependency/API/symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |
| MCP stdio facade | `ModelContextProtocol` package 1.4.1 | NuGet package metadata、`codex mcp add --help` | Confirmed | `net8.0` で利用可能な stable package を pin する。HTTP server は不要。 |
| Codex App registration | `codex mcp add agent-execution-broker -- <command>` | local `codex mcp add --help`、`%USERPROFILE%/.codex/config.toml` | Confirmed | user-level stdio MCP registration。実 App discovery は ManualOnly。 |
| First worker adapter | GitHub Copilot CLI 1.0.79 | local `copilot --help` / `--version`、GitHub Docs | Confirmed | required `coding-v1` profile is `--allow-tool=read,write,shell`、`-C <cwd>`、`--no-ask-user`、`--no-auto-update`、`--session-id <run-id UUID>`。raw CLI flags、URL/MCP/memory permission、`--allow-all*` は受け取らない。 |
| Durable registry/output | Broker-owned JSON files and JSONL | no existing Broker path | MissingButRequired | external database package は導入しない。single Host writer と atomic replacement を使う。 |
| Local IPC / worker ownership | Windows named pipe and Job Object | .NET BCL / Windows API | Confirmed | v0は同一PCのlocal named pipeとOS default pipe ACLを採用し、same-user-only ACLは保証しない。remote transportは持たない。Host は `KILL_ON_JOB_CLOSE` Job Object の唯一の owner とし、worker tree をjobへassignする。 |
| Notification schema | `agent-execution-terminal-v1` | existing `spool-item-v1.schema.json` / `SpoolItemParser.cs` | MissingButRequired | Codex-only `spool-item-v1` を拡張・偽装しない。side-by-side schema と parser dispatch が必要。 |
| Inbox consumer evolution | `SpoolItemParser`、`InboxEntry`、`SpoolInboxService`、ViewModel | `apps/CodexLocalInbox/` | Confirmed | source-specific validationを維持した discriminated parser にする。Broker locator は表示/コピーのみで、任意URIを launch しない。 |
| Test convention | MSTest 4.2.3 | `tests/CodexLocalInbox.Tests/CodexLocalInbox.Tests.csproj` | Confirmed | 新規 Broker tests も MSTest を使用する。 |

## 選択した実装アプローチ

1. `apps/AgentExecutionBroker/AgentExecutionBroker.Host/` を `net8.0` console/service host として新設する。Host は named pipe の唯一の listener、run registry/output の唯一の writer、provider process の owner、terminal event producer になる。user profile ごとに mutex を取得し、二重 Host は既存 listener へ接続するか起動失敗を返す。Host は `KILL_ON_JOB_CLOSE` を設定した Windows Job Object を作成し、各worker process treeをassignする。**no-orphan invariant**として、Hostが正常停止・クラッシュ・再起動でjob handleを失うと、そのHost所有worker treeは停止され、authorityを失ったworkerをrepositoryへ継続実行させない。
2. `apps/AgentExecutionBroker/AgentExecutionBroker.Mcp/` を stdio MCP server として新設する。公開 tool は `start_run`、`get_run`、`list_runs`、`get_output`、`cancel_run` のみとし、すべて named pipe を通じて Host に委譲する。pipe が存在しない時だけ同梱 Host を detached 起動し、接続待機には有限 timeout を使う。
3. `start_run` は `provider_id`、絶対 `working_directory`、非空 `prompt`、必須 `execution_profile: coding-v1`、任意 `repository` display metadata、allowlisted `adapter_options` を検証してから UUID run ID を作る。`coding-v1` は `read,write,shell` のみを `--allow-tool` で許可し、cwd外path、URL、MCP、memory、raw CLI flags、`--allow-all*`を許可しない。未知profile、adapter registry外、存在しないcwd、空prompt、policy違反はprocess起動前に拒否し、fallback provider は選ばない。
4. `CopilotCliAdapter` は provider invocation と観測だけを担当し、Broker run state を所有しない。command は `copilot -p <prompt> -C <cwd> --output-format json --no-ask-user --no-auto-update --session-id <run-id UUID> --allow-tool=read,write,shell` とし、profile外のraw optionを受け付けない。標準 output は Copilot JSON output を `structured`、stderr を `stderr` とした `broker-output-v1.jsonl` に保存する。provider が分離 stream を提供する場合だけ `stdout`/`stderr` identity を保存し、merged/PTY/structured data を捏造分離しない。
5. durable root は `%LOCALAPPDATA%\\AgentExecutionBroker`（absolute override `AGENT_EXECUTION_BROKER_HOME`）とし、`runs/<run-id>/run.json`、`runs/<run-id>/broker-output-v1.jsonl`、`runs/<run-id>/diagnostics.jsonl` を使用する。`run.json` は同じdirectoryのtemporary fileをflush後atomic replace、outputはsequenceを持つappend+flushとする。writerはinputを最大16 KiBのframed recordへ分割する。`get_output` は `after_sequence`、`max_records`（default 200, max 500）、`max_bytes`（default 256 KiB, max 1 MiB）を受け、ascending records、`next_after_sequence`、`has_more`、truncation reasonを返す。`list_runs` はnewest-firstで`limit`（default 50, max 100）とopaque cursorを返す。
6. state は `Accepted -> Starting -> Running -> CancelRequested -> terminal` の前進のみとする。Host lossから回復したrunは `HostLostWorkerTreeTerminated` とし、Job Object enforcementがworker treeを停止したことを記録するが、exit codeやsemantic resultを捏造しない。cancelはstate lock下で`CancelRequested`をdurableに記録し、worker開始前は`CancelledBeforeStart`へ進めてCopilotを起動しない。開始直前・process割当・`Running`保存は同じstate lockで直列化し、古いsnapshotでstateを上書きしない。exitがこの記録より前に観測済みなら既存`Exited`を保持する。delivery成功後にexitを観測した場合は`CancelledByBroker`（Broker cancellation delivery後の観測という意味）とし、delivery失敗自体はterminalにせず`cancel_delivery: Failed`とdiagnosticを残して監視を続け、後続exitは`ExitedAfterFailedCancel`とする。stop requestの受理だけをterminationと表示しない。
7. `run.json`には`host_instance_id`、Broker run IDとは別のprovider session ID、provider process ID、Job ID、prompt digest、state transition sequence/timestamp/authority、`agent_reported_result` fieldを保持する。providerがsemantic resultを返さない場合はnullのまま保持し、exit codeから推測しない。
7. terminal時、Hostは `scripts/codex-notification-runtime/agent-execution-terminal-v1.schema.json` に適合する一event one final JSONを既存resolved spool folderへatomic publishする。eventの`source_event_id`は `agent-execution-broker:run:<run-id>:terminal` と決定論的に生成し、一runにつきterminal eventは一つだけとする。required fieldsは `schema_version`, `source`, `source_event_id`, `run_id`, `provider_id`, `observed_status`, `occurred_at`, `title`, `result_locator`で、`repository`はrequest supplied時だけ含むoptional display metadataとする。`result_locator` は `broker-run:<run-id>` でありCodex thread / resume URIではない。publish failureはrun recordに`Failed`とdiagnosticを残し、run/outputは保持する。v0はautomatic retryもmanual cleanup/retentionも実装しない。
8. Inbox は既存 Codex `spool-item-v1` parserを保持し、source により新schemaをdispatchする。Broker eventのitemはprovider、run ID、optional repository、observed status、result locatorを表示/コピーできるが、Codex-specific Resume/Open URI actionは表示しない。
9. `TP-BRK-017` の最初のactual Codex App + Copilot + low-risk real issue E2Eを、そのままEarly Operational Trialとして扱い、`AC-015` と `AC-018` のevidenceを一つにする。production provider/wiring/profile/transportがtrial後にmaterialに変わった時だけ、formal verificationとして同じE2Eを再実行する。trial成功だけでformal closeは宣言しない。

## 必要なコード変更

| Path | Change | Responsibility |
| --- | --- | --- |
| `apps/AgentExecutionBroker/AgentExecutionBroker.Host/` | Add | Host、Job Object no-orphan owner、pipe protocol、registry、state/cancel reconciliation、framed output writer、terminal publisher。 |
| `apps/AgentExecutionBroker/AgentExecutionBroker.Mcp/` | Add | `ModelContextProtocol` 1.4.1 stdio facade、Host launcher/client、bounded five-tool surface。 |
| `apps/AgentExecutionBroker/AgentExecutionBroker.Contracts/` | Add | versioned request/response、mandatory `coding-v1` profile、cursor/limit response、run/event/output records、adapter contract。 |
| `apps/AgentExecutionBroker/AgentExecutionBroker.slnx` | Add | Host/MCP/contracts の solution entrypoint。 |
| `scripts/codex-notification-runtime/agent-execution-terminal-v1.schema.json` | Add | Broker terminal event machine-readable schema。 |
| `scripts/codex-notification-runtime/local-spool-interface.md` | Change | Codex-only v1 を維持したまま side-by-side Broker terminal event contract と atomic publication を記載。 |
| `apps/CodexLocalInbox/Models/`、`Services/`、`ViewModels/`、`README.md` | Change | discriminated source parser、Broker item表示/コピー、非Codex locatorの安全方針。 |
| `tests/AgentExecutionBroker.Tests/` | Add | Host/adapter/pipe/file/event seams の MSTest suite。 |
| `tests/CodexLocalInbox.Tests/` | Change | side-by-side schema、dedup、unsafe locator non-launch の回帰 tests。 |
| `docs/`、root `README.md` | Change | install、MCP registration、no-orphan lifecycle、`coding-v1` permissions、bounded retrieval、manual resume、trial手順と責務境界。 |

## 禁止される代替実装

| Prohibited substitute | Reason | Status |
| --- | --- | --- |
| Codex App → Codex CLI を唯一の production worker とする | `FR-011` の non-Control-UI provider gate を満たさない。 | RejectedSubstitute |
| MCP facade 内だけで worker/process/state を保持する | facade/parent lifetime と execution owner を分離できず、再起動後参照も失う。 | RejectedSubstitute |
| in-memory registry、fake adapter、MCP test clientだけで完成扱いする | `FR-016`,`AC-015`,`AC-016` の fake-only prohibition に反する。 | RejectedSubstitute |
| `spool-item-v1` の source/`resume_uri`を偽装して Broker event を投入する | Codex callback identity と non-Codex provider identity が混同される。 | RejectedSubstitute |
| existing completion notification runtime を generic Broker/orchestrator に変更する | Plan non-goal と Issue #70 boundary に反する。 | RejectedSubstitute |
| merged/structured output を stdout/stderr に推測分割する | `FR-006`,`AC-004` の observed capability preservation に反する。 | RejectedSubstitute |
| Host loss後にworker processを再attach不能のまま継続させる | Broker run authorityを失い、repositoryを書き続ける孤児workerを許す。 | RejectedSubstitute |
| cancel acceptance を worker termination と表示する | `FR-009`,`AC-003`,`AC-007` の observed fact separation に反する。delivery/order/exitを別記録する。 | RejectedSubstitute |
| implicit `--allow-all-tools` またはprofile未指定のraw CLI optionsをadapter defaultにする | `coding-v1`のexplicit allowlist/default denyを破る。 | RejectedSubstitute |
| automatic retention / 30-day default cleanupをv0へ導入する | Plan外であり、early operational evidenceを削除する。 | OutOfScopeForThisPass |
| Issue #70 standalone completion adapterを Broker v0 の completion prerequisite にする | `NG-009`,`AC-017` に反する。 | OutOfScopeForThisPass |

## 検証フック

| Hook | Observation | Status |
| --- | --- | --- |
| Host unit/integration tests | pipe request、Job Object no-orphan、state/cancel race、atomic registry/framed output、cursor/limit、adapter command construction、terminal event schema | to be assigned by test-design-kernel |
| Inbox regression tests | Codex v1 compatibility、Broker event parser dispatch、event identity dedup、unsafe locator non-launch | to be assigned by test-design-kernel |
| Production binding check | packaged MCP command → detached Host → actual Copilot CLI → durable run/output → real spool event → Inbox/Codex retrieval | ManualOnly |
| Early Operational Trial / actual E2E | first low-risk real issueでactual Codex App→Copilot→result retrieval、run evidence、friction、remaining hardening priority | ManualOnly |

## 未解決の実装実現性項目

| Item | Status | Disposition |
| --- | --- | --- |
| Copilot CLI authentication and a real worker execution | ManualOnly | implementation後、private credentialsを露出させず actual Codex App E2E で確認する。 |
| Exact MCP attribute/API shape of `ModelContextProtocol` 1.4.1 | NotImplementedOrMismatch | restore/build phaseで package API に合わせる。package/transport selectionは固定済みで、API mismatch時は local code decision として HIGH_MODEL が解消する。 |
| `coding-v1` profile implementation | NotImplementedOrMismatch | required profileとexact `read,write,shell` allowlistは確定済み。実装はraw option injectionを拒否する。 |
| retention / cleanup | OutOfScopeForThisPass | v0はautomatic retentionもmanual cleanup commandも導入しない。 |

## Self-check / Readiness verdict

`READY_FOR_RUNTIME_CONTRACT`

provider、MCP transport、Host/facade lifetime、durable storage、terminal eventの責務境界、Inbox compatibility、cancel semantics、禁止代替案を evidence-backed に固定した。production code、tests、real credential evidenceは未実施であり、`READY_FOR_IMPLEMENTATION` や `Bound` を意味しない。

## Self-check evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Plan/triage authority read | PASS | Plan、Behavior Spec、RiskTriage の `RC-BRK-001`〜`004`。 |
| non-Control-UI provider evidence | PASS | installed Copilot CLI 1.0.79 と official programmatic documentation。 |
| Codex integration surface evidence | PASS | local `codex mcp` stdio registration help と existing user config。 |
| existing spool compatibility | PASS | strict Codex-only `spool-item-v1` parser/schema を確認し、side-by-side schemaを選択。 |
| production address decision | PASS | Host、MCP facade、Contracts、Job Object、bounded output/query、event schema、Inbox/test/docs paths を指定。 |
| execution authority/profile decision | PASS | no-orphan invariant、cancel race rule、required `coding-v1`、exact allowlistを固定。 |
| prohibited substitute visibility | PASS | この artifactの禁止表へ明記。 |
| human decision blocker | PASS | `NeedsHumanDecision`: 0。ManualOnlyは実装後の実環境 evidence。 |

## Handoff Packet

- Profile used: implementation-contract-kernel
- implementation_route: adaptive
- implementation_route_source: default
- Source artifacts: Parent Plan、Black-box Behavior Spec、Change Risk Triage、existing Local Spool interface/schema/runtime、Codex Local Inbox parser/tests、local `codex` / `copilot` help、official provider/package documentation。
- Selected contracts / IDs: `RC-BRK-001`〜`RC-BRK-004`; `IR-BRK-001`〜`IR-BRK-005`。
- Files inspected: 上記 artifacts、および対象の existing spool/Inbox source/test filesのみ。
- Files intentionally not inspected: provider CLI internals、all repository tests、Issue #70 implementation全体。選択した implementation contract に不要。
- Decisions made: Copilot CLI 1.0.79、required `coding-v1`、stdio MCP facade、Job Object no-orphan Host、file-based durable registry/framed output、bounded cursor API、side-by-side `agent-execution-terminal-v1`、deterministic event identityを選択した。
- Do not redo unless new evidence appears: provider choice、Host/facade separation、no-orphan invariant、cancel rule、Broker run ID/event identity、bounded output fidelity、Codex spool identity prohibition、Issue #70 boundary。
- Remaining work: production code、テスト、docs、wiringのbounded passは完了。`ManualOnly`: actual Codex App/Copilot real-issue Early Operational Trial（通常runと別disposable worktreeのcancel smoke）。
- Implementation follow-up evidence: cancel/start state lock、開始前cancel guard、execution identity/transition history/result separation、same-machine OS default ACL方針、bounded retrieval、generated output除外を実装・検証した。providerがsemantic resultを返さない場合の`agent_reported_result`はnullのまま保持する。
- Recommended next step: verification kernelでproduction source/build/test evidenceを確認し、TP-BRK-017の人手承認へ進む。
