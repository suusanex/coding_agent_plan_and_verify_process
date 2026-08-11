# Implementation Contract Kernel: Agent Execution Broker Operational v0

## スコープ

`plans/goal-context-multi-agent-execution-broker-operational-v0-plan.md` を唯一の要求 authority とし、RiskTriage が選択した `RC-BRK-001`〜`RC-BRK-004` を一つの `standard-slice` production vertical pass として実現するための、実装可能な production address、dependency、責務境界を固定する。コード、テスト、実プロバイダーの実行はこの pass では行わない。

採用する最初の production worker は、ローカルに導入済みの GitHub Copilot CLI `1.0.79` とする。これは Codex App とは異なる provider であり、公式の programmatic mode とローカル help が `-p`、`-C`、`--output-format`、`--no-ask-user` を提供することを確認した evidence-backed selection である。Codex CLI を worker にする代替案は `FR-011` により不採用とする。

## Plan が要求する実装要件

| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |
| `FR-001`,`FR-002`,`AC-001` | Codex App から非同期に run を開始し、request lifetime と worker owner を分離する | ローカル `codex mcp add` は stdio command を登録でき、Copilot CLI は non-interactive prompt を受ける。新規 Host/MCP facade が必要。 | MissingButRequired |
| `FR-003`〜`FR-009`,`AC-002`〜`AC-007` | durable run authority、単調 state、output、cancel、再起動後取得 | 既存 Broker 実装はない。BCL の JSON/file/NamedPipe/Process で実装可能。 | MissingButRequired |
| `FR-010`〜`FR-012`,`AC-008`,`AC-009` | provider-neutral contract と non-Control-UI production adapter、admission rejection | Copilot CLI 1.0.79 の `-p`、`-C`、`--output-format json`、`--no-ask-user`、`--session-id` をローカル help で確認。 | Confirmed |
| `FR-013`,`FR-014`,`AC-010`〜`AC-013` | provider-neutral terminal event を既存 spool/inbox plane へ偽装なく渡す | `spool-item-v1` は Codex callback 固有の厳密10 field/source であり、Broker event の代用にできない。Inbox は `*.json` scan と `source_event_id` dedup を持つ。 | MissingButRequired |
| `FR-015`,`AC-014` | install/start/stop/health/run/output/cancel/manual resume の手順 | 既存 runtime/Inbox README の運用記述形式を再利用できる。Broker docs は新規。 | MissingButRequired |
| `FR-016`,`FR-017`,`AC-015`〜`AC-018` | actual Codex App + real issue による production E2E と early trial | Codex は local stdio MCP server を登録可能。実 App 操作と provider credential は未実行であり ManualOnly。 | Confirmed |

## Dependency と API surface の確認結果

| Dependency/API/symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |
| MCP stdio facade | `ModelContextProtocol` package 1.4.1 | NuGet package metadata、`codex mcp add --help` | Confirmed | `net8.0` で利用可能な stable package を pin する。HTTP server は不要。 |
| Codex App registration | `codex mcp add agent-execution-broker -- <command>` | local `codex mcp add --help`、`%USERPROFILE%/.codex/config.toml` | Confirmed | user-level stdio MCP registration。実 App discovery は ManualOnly。 |
| First worker adapter | GitHub Copilot CLI 1.0.79 | local `copilot --help` / `--version`、GitHub Docs | Confirmed | command is `copilot -p <prompt> -C <cwd> --output-format json --no-ask-user --no-auto-update --session-id <provider-session-id>`; optional tool policy is explicit input, never silent `--allow-all-tools`。 |
| Durable registry/output | Broker-owned JSON files and JSONL | no existing Broker path | MissingButRequired | external database package は導入しない。single Host writer と atomic replacement を使う。 |
| Local IPC | Windows named pipe `agent-execution-broker.v1` | .NET BCL | Confirmed | same-user ACL、request/response JSON frames。MCP process は durable state owner にならない。 |
| Notification schema | `agent-execution-terminal-v1` | existing `spool-item-v1.schema.json` / `SpoolItemParser.cs` | MissingButRequired | Codex-only `spool-item-v1` を拡張・偽装しない。side-by-side schema と parser dispatch が必要。 |
| Inbox consumer evolution | `SpoolItemParser`、`InboxEntry`、`SpoolInboxService`、ViewModel | `apps/CodexLocalInbox/` | Confirmed | source-specific validationを維持した discriminated parser にする。Broker locator は表示/コピーのみで、任意URIを launch しない。 |
| Test convention | MSTest 4.2.3 | `tests/CodexLocalInbox.Tests/CodexLocalInbox.Tests.csproj` | Confirmed | 新規 Broker tests も MSTest を使用する。 |

## 選択した実装アプローチ

1. `apps/AgentExecutionBroker/AgentExecutionBroker.Host/` を `net8.0` console/service host として新設する。Host は named pipe の唯一の listener、run registry/output の唯一の writer、provider process の owner、terminal event producer になる。user profile ごとに mutex を取得し、二重 Host は既存 listener へ接続するか起動失敗を返す。
2. `apps/AgentExecutionBroker/AgentExecutionBroker.Mcp/` を stdio MCP server として新設する。公開 tool は `start_run`、`get_run`、`list_runs`、`get_output`、`cancel_run` のみとし、すべて named pipe を通じて Host に委譲する。pipe が存在しない時だけ同梱 Host を detached 起動し、接続待機には有限 timeout を使う。
3. `start_run` は `provider_id`、絶対 `working_directory`、非空 `prompt`、任意 `adapter_options` を検証してから UUID run ID を作る。adapter registry の明示登録外、存在しない cwd、空 prompt、許可されない tool policy は process 起動前に拒否する。fallback provider は選ばない。
4. `CopilotCliAdapter` は provider invocation と観測だけを担当し、Broker run state を所有しない。標準 output は Copilot JSON output を `structured`、stderr を `stderr` とした `broker-output-v1.jsonl` に保存する。provider が分離 stream を提供する場合だけ `stdout`/`stderr` identity を保存し、merged/PTY/structured data を捏造分離しない。
5. durable root は `%LOCALAPPDATA%\\AgentExecutionBroker`（absolute override `AGENT_EXECUTION_BROKER_HOME`）とし、`runs/<run-id>/run.json`、`runs/<run-id>/broker-output-v1.jsonl`、`runs/<run-id>/diagnostics.jsonl` を使用する。`run.json` は同じ directory の temporary file を flush 後 atomic replace、output は sequence を持つ append+flush とする。schema version、Broker run ID、provider session/process ID、observed fact、agent-reported result、notification disposition を別 field にする。
6. state は `Accepted -> Starting -> Running -> CancelRequested -> terminal` の前進のみとする。terminal observed status は `Exited`、`LaunchFailed`、`Cancelled`、`UnknownAfterBrokerRestart` を最小集合とし、exit code / process observation / reported result は別 field にする。cancel は `CancelRequested` を durable に記録後 `Process.Kill(entireProcessTree: true)` を試行し、停止要求の受理を停止観測と同一視しない。
7. terminal 時、Host は `scripts/codex-notification-runtime/agent-execution-terminal-v1.schema.json` に適合する一 event one final JSON を既存 resolved spool folder へ atomic publish する。event は `source: agent-execution-broker.run-terminal`、`source_event_id`、`run_id`、`provider_id`、`observed_status`、`occurred_at`、`title`、`repository`、`result_locator` を持つ。`result_locator` は `broker-run:<run-id>` であり Codex thread / resume URI ではない。publish failure は run record に `Failed` と diagnostic を残し、run/output は保持する。v0 は automatic retry を約束せず、`broker publish-terminal --run-id` の手動 repair を文書化する。
8. Inbox は既存 Codex `spool-item-v1` parserを保持し、source により新 schema を dispatch する。Broker event の item は provider、run ID、observed status、result locator を表示/コピーできるが、Codex-specific Resume/Open URI action は表示しない。
9. first vertical slice は `AC-001`,`AC-004`〜`AC-006`,`AC-008`,`AC-010`〜`AC-012`,`AC-015` を production path で満たした後、低リスク real issue の Early Operational Trial を開始する。formal close は `AC-002`,`AC-003`,`AC-007`,`AC-013`,`AC-014`,`AC-016`〜`AC-018` を含む後続 verification まで宣言しない。

## 必要なコード変更

| Path | Change | Responsibility |
| --- | --- | --- |
| `apps/AgentExecutionBroker/AgentExecutionBroker.Host/` | Add | Host、pipe protocol、registry、state machine、output writer、process/cancel、terminal publisher、CLI health/repair command。 |
| `apps/AgentExecutionBroker/AgentExecutionBroker.Mcp/` | Add | `ModelContextProtocol` 1.4.1 stdio facade、Host launcher/client、five tool surface。 |
| `apps/AgentExecutionBroker/AgentExecutionBroker.Contracts/` | Add | versioned request/response、run/event/output records、adapter contract。Host と MCP の shared assembly。 |
| `apps/AgentExecutionBroker/AgentExecutionBroker.slnx` | Add | Host/MCP/contracts の solution entrypoint。 |
| `scripts/codex-notification-runtime/agent-execution-terminal-v1.schema.json` | Add | Broker terminal event machine-readable schema。 |
| `scripts/codex-notification-runtime/local-spool-interface.md` | Change | Codex-only v1 を維持したまま side-by-side Broker terminal event contract と atomic publication を記載。 |
| `apps/CodexLocalInbox/Models/`、`Services/`、`ViewModels/`、`README.md` | Change | discriminated source parser、Broker item表示/コピー、非Codex locatorの安全方針。 |
| `tests/AgentExecutionBroker.Tests/` | Add | Host/adapter/pipe/file/event seams の MSTest suite。 |
| `tests/CodexLocalInbox.Tests/` | Change | side-by-side schema、dedup、unsafe locator non-launch の回帰 tests。 |
| `docs/`、root `README.md` | Change | install、MCP registration、lifecycle、permissions、manual resume、repair、trial手順と責務境界。 |

## 禁止される代替実装

| Prohibited substitute | Reason | Status |
| --- | --- | --- |
| Codex App → Codex CLI を唯一の production worker とする | `FR-011` の non-Control-UI provider gate を満たさない。 | RejectedSubstitute |
| MCP facade 内だけで worker/process/state を保持する | facade/parent lifetime と execution owner を分離できず、再起動後参照も失う。 | RejectedSubstitute |
| in-memory registry、fake adapter、MCP test clientだけで完成扱いする | `FR-016`,`AC-015`,`AC-016` の fake-only prohibition に反する。 | RejectedSubstitute |
| `spool-item-v1` の source/`resume_uri`を偽装して Broker event を投入する | Codex callback identity と non-Codex provider identity が混同される。 | RejectedSubstitute |
| existing completion notification runtime を generic Broker/orchestrator に変更する | Plan non-goal と Issue #70 boundary に反する。 | RejectedSubstitute |
| merged/structured output を stdout/stderr に推測分割する | `FR-006`,`AC-004` の observed capability preservation に反する。 | RejectedSubstitute |
| cancel acceptance を worker termination と表示する | `FR-009`,`AC-003`,`AC-007` の observed fact separation に反する。 | RejectedSubstitute |
| implicit `--allow-all-tools` を adapter default にする | user-authorized execution policyを無視する。tool allowlist は request profile から明示的に渡す。 | RejectedSubstitute |
| Issue #70 standalone completion adapterを Broker v0 の completion prerequisite にする | `NG-009`,`AC-017` に反する。 | OutOfScopeForThisPass |

## 検証フック

| Hook | Observation | Status |
| --- | --- | --- |
| Host unit/integration tests | pipe request、state monotonicity、atomic registry/output、adapter command construction、cancel reconciliation、terminal event schema | to be assigned by test-design-kernel |
| Inbox regression tests | Codex v1 compatibility、Broker event parser dispatch、event identity dedup、unsafe locator non-launch | to be assigned by test-design-kernel |
| Production binding check | packaged MCP command → detached Host → actual Copilot CLI → durable run/output → real spool event → Inbox/Codex retrieval | ManualOnly |
| Early Operational Trial | first vertical slice後の低リスク実Issue、run evidence、friction、remaining hardening priority | ManualOnly |

## 未解決の実装実現性項目

| Item | Status | Disposition |
| --- | --- | --- |
| Copilot CLI authentication and a real worker execution | ManualOnly | implementation後、private credentialsを露出させず actual Codex App E2E で確認する。 |
| Exact MCP attribute/API shape of `ModelContextProtocol` 1.4.1 | NotImplementedOrMismatch | restore/build phaseで package API に合わせる。package/transport selectionは固定済みで、API mismatch時は local code decision として HIGH_MODEL が解消する。 |
| Provider tool allowlist contents | NotImplementedOrMismatch | request-owned `execution_profile` を実装し、default deny / explicit listにする。per-repository policyは運用 docsで最初に設定する。 |
| 30-day default retention implementation | NotImplementedOrMismatch | active runは削除せず、terminal runだけを明示 `broker cleanup --older-than` commandで掃除する。automatic deletionは v0では行わない。 |

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
| production address decision | PASS | Host、MCP facade、Contracts、event schema、Inbox/test/docs paths を指定。 |
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
- Decisions made: Copilot CLI 1.0.79、stdio MCP facade、named-pipe long-lived Host、file-based durable registry/output、side-by-side `agent-execution-terminal-v1`、explicit tool policy、manual notification repairを選択した。
- Do not redo unless new evidence appears: provider choice、Host/facade separation、Broker run ID authority、output fidelity、Codex spool identity prohibition、Issue #70 boundary。
- Remaining work: `NotImplementedOrMismatch`: production code/tests/wiring。`ManualOnly`: actual Codex App/Copilot real issue、Early Operational Trial。
- Recommended next step: `runtime-contract-kernel.agent.md` にこのartifact、Plan、RiskTriage を渡し、`RC-BRK-001`〜`RC-BRK-004` の participant/boundary contract を固定する。
