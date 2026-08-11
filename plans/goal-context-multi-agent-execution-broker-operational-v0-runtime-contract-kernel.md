# Runtime Contract Kernel: Agent Execution Broker Operational v0

## スコープ

Change Risk Triage が選択した `RC-BRK-001`〜`RC-BRK-004` を対象とし、Implementation Contract Kernel の production address を変更せず、participant、boundary、required fields、error behaviorを記録する。これは `contract-kernel` profile の bounded pass であり、code/testの作成や full-coverage への拡張は行わない。

## Runtime Contract Kernel

| Contract ID | Scenario | Producer | Consumer | Message / API / Event | Required fields | Error / timeout behavior | Production implementation address | Verification hook |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `RC-BRK-001` | Codex Appがvalid requestを非同期runとして受理する | `AgentExecutionBroker.Mcp` stdio MCP server | `AgentExecutionBroker.Host` named-pipe request handler | named pipe `agent-execution-broker.v1`: `start_run` request/response | `request_id`, `provider_id`, absolute `working_directory`, non-empty `prompt`, optional explicit `execution_profile`; response `run_id`, `admission_status`, `reason` | pipe absent時はMCPがHostをdetached起動し有限待機。unknown provider/invalid cwd/missing prompt/policy violationはworker未起動でrejection。silent fallbackなし。 | `apps/AgentExecutionBroker/AgentExecutionBroker.Mcp/`; `apps/AgentExecutionBroker/AgentExecutionBroker.Host/`; `apps/AgentExecutionBroker/AgentExecutionBroker.Contracts/` | `TP-BRK-001`,`TP-BRK-002`,`TP-BRK-003` |
| `RC-BRK-002` | Hostがeligible Copilot workerを起動し、durable state/outputを観測する | `AgentExecutionBroker.Host` / `CopilotCliAdapter` | Copilot CLI process and Broker file store | `copilot -p` invocation; `runs/<run-id>/run.json`; `broker-output-v1.jsonl`; `diagnostics.jsonl` | Broker `run_id`, `provider_id`, adapter version, cwd, prompt digest, state/observed timestamps, provider session/process ID, output sequence/kind/data, observed exit code/fact, reported result field | launch failure is terminal `LaunchFailed`; output can be structured/merged/empty; restart marks an unobservable inherited process `UnknownAfterBrokerRestart` rather than fabricating exit. cancel request is recorded before tree kill attempt and terminal only after observation. | `apps/AgentExecutionBroker/AgentExecutionBroker.Host/` and `...Contracts/`; `%LOCALAPPDATA%\\AgentExecutionBroker\\runs` | `TP-BRK-004`〜`TP-BRK-008` |
| `RC-BRK-003` | facade restart、Host restart、list/get/output/cancelが同じ Broker identityを参照する | `AgentExecutionBroker.Host` durable registry reader/writer | `AgentExecutionBroker.Mcp` and its Codex App caller | named pipe `get_run`, `list_runs`, `get_output`, `cancel_run`; atomic `run.json` replacement | `run_id`, registry schema version, state transition sequence/timestamps, provider/process IDs, output locator, cancellation request/delivery/observation, notification disposition | malformed/missing record returns explicit not-found/corrupt diagnostic; terminal never regresses; cancel returns bounded request disposition, not asserted process termination. Host single-writer lock prevents competing authority. | `apps/AgentExecutionBroker/AgentExecutionBroker.Host/`; `...Mcp/`; `%LOCALAPPDATA%\\AgentExecutionBroker\\runs` | `TP-BRK-009`〜`TP-BRK-012` |
| `RC-BRK-004` | terminal Broker runをnon-Codex eventとしてSpool/Inboxへ投影し、Codex Appから同じrunを回収する | `AgentExecutionBroker.Host` terminal publisher | Local Spool folder and `CodexLocalInbox` parser/UI; Codex App MCP facade for result retrieval | `agent-execution-terminal-v1` final JSON in resolved spool folder; `get_run`/`get_output` by run ID | `schema_version`, `source`, stable `source_event_id`, `run_id`, `provider_id`, `observed_status`, `occurred_at`, `title`, `repository`, `result_locator`; notification disposition/diagnostic in Broker record | atomic final publication; publish failure leaves durable run/output and `Failed` diagnostic. same event ID dedups in Inbox. `result_locator` is display/copy only; no Codex `resume_uri` fabrication. manual repair is explicit, no automatic retry guarantee. | `apps/AgentExecutionBroker/AgentExecutionBroker.Host/`; `scripts/codex-notification-runtime/agent-execution-terminal-v1.schema.json`; `apps/CodexLocalInbox/Models/`, `Services/`, `ViewModels/` | `TP-BRK-013`〜`TP-BRK-017` |

## Plan / implementation contract 適合性

| Runtime Contract ID | Plan requirement | Implementation contract decision | Runtime contract address | Conformance |
| --- | --- | --- | --- | --- |
| `RC-BRK-001` | `FR-001`,`FR-002`,`FR-012`; `AC-001`,`AC-009` | stdio MCP facade + detached named-pipe Host | five-tool facade and `start_run` admission | Conformant |
| `RC-BRK-002` | `FR-003`〜`FR-007`,`FR-010`,`FR-011`; `AC-002`〜`AC-005`,`AC-008` | Copilot CLI adapter, file durable store, observed/reported separation | provider process and per-run records | Conformant |
| `RC-BRK-003` | `FR-003`〜`FR-009`; `AC-002`,`AC-003`,`AC-006`,`AC-007` | Host single writer, atomic state, pipe read surface | registry/output/cancel lifecycle | Conformant |
| `RC-BRK-004` | `FR-013`,`FR-014`; `AC-010`〜`AC-013`,`AC-015` | side-by-side provider-neutral spool event and Inbox dispatch | terminal event / result retrieval | Conformant |

## 注記 / 前提

- `ModelContextProtocol` の具体的attribute/APIは restore/build時に確認する `NotImplementedOrMismatch` だが、stdio MCP + named pipeという boundary decisionは確定している。
- Copilot CLI credential、actual Codex App tool discovery、実Issueへの権限は `ManualOnly`。設計段階で実行はしない。
- Host restart後、元processを安全に観測できない場合は推測でterminalにせず `UnknownAfterBrokerRestart` を durableにする。そのrunのoperator remediationは docsで明示する。
- selected contracts は一つのvertical runtime sequenceであり、詳細sequence diagram、rollback/replay architecture、full-coverage decompositionは不要。full-coverage escalation recommendation: なし。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: Parent Plan、Change Risk Triage、Implementation Contract Kernel、Behavior Spec、existing Local Spool/Inbox contracts。
- Selected contracts / IDs: `RC-BRK-001`〜`RC-BRK-004`。
- Files inspected: 上記artifactと、selected boundaryを確認する既存 spool/Inbox sourceのみ。
- Files intentionally not inspected: future Broker source、provider internals、repository-wide test suite。まだ存在しない/selected scope外のため。
- Decisions made: Producer/Consumer、named pipe、Copilot process/file store、side-by-side terminal event、result locatorの非launch性を固定した。
- Do not redo unless new evidence appears: RC participant、field、error/timeout、production address、Plan適合性。
- Remaining work: `NotImplementedOrMismatch`: contractsを実装しproduction binding/wiringを確認する。`ManualOnly`: actual Codex App/Copilot path。
- Recommended next step: `test-design-kernel.agent.md` に本artifact、Implementation Contract、Plan、Behavior Specを渡し、`TP-BRK-001`〜`017`を設計する。
