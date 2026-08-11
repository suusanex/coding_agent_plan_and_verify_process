# 実装実行記録: Agent Execution Broker Operational v0

## 実装route

```yaml
implementation_route: adaptive
implementation_route_source: default
design_pair_handoff: N/A
verdict_sequence:
  - COMPLETED_BY_HIGH_MODEL
```

## 実装結果

Host、MCP stdio facade、Copilot CLI adapter、durable run/output store、Windows Job Object、terminal spool event、Inbox side-by-side consumer、MSTestを追加した。MCP packageは`ModelContextProtocol` 1.4.1でrestore/buildし、stdio server / five-tool registrationがcompileすることを確認した。

`coding-v1`はprovider allowlistを実装し、Copilot CLIへ`--allow-tool=read,write,shell`、`-C`、`--no-ask-user`、`--no-auto-update`、UUID `--session-id`だけを渡す。raw option、URL、MCP、memory、`--allow-all*`を受けるsurfaceは追加していない。

## Files changed

| Area | Files | Result |
| --- | --- | --- |
| Broker contracts | `apps/AgentExecutionBroker/AgentExecutionBroker.Contracts/` | versioned request/response、run/output/event model、boundsを追加。 |
| Host | `apps/AgentExecutionBroker/AgentExecutionBroker.Host/` | named pipe listener、single Host mutex、durable JSON/JSONL、Job Object kill-on-close、cancel/recovery、terminal publishを追加。 |
| MCP | `apps/AgentExecutionBroker/AgentExecutionBroker.Mcp/` | stdio MCP server、Host launcher、`start_run`等five toolsを追加。 |
| Notification/InBox | `scripts/codex-notification-runtime/agent-execution-terminal-v1.schema.json`、`apps/CodexLocalInbox/` | side-by-side terminal schema、strict parser dispatch、safe locator copyを追加。 |
| Tests/docs | `tests/AgentExecutionBroker.Tests/`、`tests/CodexLocalInbox.Tests/`、`apps/AgentExecutionBroker/README.md` | Broker store/profile/recovery/event、Inbox regression、install/operation guideを追加。 |

## Validation

| Command | Result |
| --- | --- |
| `dotnet build apps/AgentExecutionBroker/AgentExecutionBroker.slnx --no-restore --no-incremental` | PASS, warnings 0, errors 0 |
| `dotnet test tests/AgentExecutionBroker.Tests/AgentExecutionBroker.Tests.csproj --no-restore` | PASS, 7 tests |
| `dotnet test tests/CodexLocalInbox.Tests/CodexLocalInbox.Tests.csproj --no-restore` | PASS, 13 tests |
| `dotnet build apps/CodexLocalInbox/CodexLocalInbox.slnx --no-restore --no-incremental` | PASS, warnings 0, errors 0 |
| `git diff --check` | PASS |

## Implementation Self-Map

| Change ID | Change | File / Symbol | Reason | Related Plan item | Related Behavior Case IDs | Related SL / XC / RC / TP / IC / Gap item | Assumption made | Review hint |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `CHG-BRK-001` | durable Host and pipe protocol | `BrokerHost`, `BrokerService`, `BrokerStore` | facadeとworker authorityを分離する | `FR-001`〜`009`, `AC-001`〜`007` | `CASE-BRK-001`〜`007`,`012` | `RC-BRK-001`〜`003`; `TP-BRK-001`〜`012` | same-user local Host | cancel/order and restart records |
| `CHG-BRK-002` | fixed Copilot profile | `CopilotCliAdapter` | default deny execution profile | `FR-010`〜`012`, `AC-008`,`009` | `CASE-BRK-011`〜`013` | `RC-BRK-002`; `TP-BRK-002`,`004` | installed `copilot` command is resolved by PATH | no raw option surface |
| `CHG-BRK-003` | no-orphan job ownership | `WorkerJob`, reconciliation | Host authority loss must stop worker tree | `FR-002`〜`005`, `FR-009`, `AC-002`,`003`,`007` | `CASE-BRK-003`,`006`,`007` | `RC-BRK-002`,`003`; `TP-BRK-008`,`010`,`011` | Windows Job Object supports kill-on-close | exit/result are not fabricated |
| `CHG-BRK-004` | bounded output and paging | `BrokerStore` | bounded MCP result contract | `FR-005`〜`008`, `AC-004`,`006` | `CASE-BRK-002`〜`005` | `RC-BRK-002`,`003`; `TP-BRK-006`,`009` | JSONL is Host-only writer | UTF-8 frame size and cursor |
| `CHG-BRK-005` | neutral terminal event / Inbox projection | schema, parser, view model | preserve Codex v1 identity boundary | `FR-013`,`014`, `AC-010`〜`013` | `CASE-BRK-008`〜`010` | `RC-BRK-004`; `TP-BRK-013`〜`016` | locator is non-URI | copy-only action never launches |
| `CHG-BRK-006` | operation documentation | `apps/AgentExecutionBroker/README.md` | install/run/output/cancel/manual continuation | `FR-015`, `AC-014`, `AC-017` | `CASE-BRK-015`,`016` | parent Plan docs pass | actual App trial remains separate | no retention / Issue #70 boundary |

## Remaining work

- `ManualOnly`: `TP-BRK-017` actual Codex App + authenticated Copilot CLI + low-risk real issue E2E、同時にEarly Operational Trial。
- これはcredentialおよびprivate working dataを使うため、現在のユーザー指示だけでは実行していない。fixture、MCP test client、process-start-only evidenceで代用していない。
