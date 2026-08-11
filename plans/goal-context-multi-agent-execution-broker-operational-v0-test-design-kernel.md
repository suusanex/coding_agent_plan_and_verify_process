# Test Design Kernel: Agent Execution Broker Operational v0

## スコープ

Runtime Contract Kernel の `RC-BRK-001`〜`RC-BRK-004` に対し、observable behavior、substitute policy、production binding requirementを設計する。`Done` は test design行の完了であり、test実装・実行・production verificationの完了ではない。Parent Plan とBehavior Specは依然として唯一の要求authorityである。

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `TP-BRK-001` | `RC-BRK-001` | valid `coding-v1` requestのadmissionがstable UUID run IDを返し、MCP requestがworker exitを待たない | Yes | Yes | responseにrun ID、Host registryに`Accepted`、facade終了後もHost runが残る | Done |
| `TP-BRK-002` | `RC-BRK-001` | unknown provider/invalid cwd/empty prompt/missing-or-unknown profile/raw option injectionを起動前に拒否する | Yes | Yes | rejection reason、adapter process start 0、fallback 0 | Done |
| `TP-BRK-003` | `RC-BRK-001` | pipe未起動時のHost launch/reconnectがboundedで、二重Hostを作らない | Yes | Yes | one mutex owner、bounded unavailable diagnostic、second Hostはexisting endpointへ接続 | Done |
| `TP-BRK-004` | `RC-BRK-002` | Copilot adapterが`coding-v1`をexactな`-C`、UUID `--session-id`、`--allow-tool=read,write,shell`へ投影する | Yes | Yes | process start infoとrecorded profileが一致し、URL/MCP/memory/allow-all/raw optionなし | Done |
| `TP-BRK-005` | `RC-BRK-002` | `Accepted`→`Starting`→`Running`→terminal transitionが単調でtimestamp/authorityを保持する | Yes | Yes | durable `run.json`は後退なし、exit factとreported resultが別 field | Done |
| `TP-BRK-006` | `RC-BRK-002` | structured/stderr/empty/nonzero/launch failure outputを最大16 KiB frameとして実際のkindで保存する | Yes | Yes | JSONL sequence、kind、diagnostic、exit factを再取得でき、stream捏造/巨大single recordなし | Done |
| `TP-BRK-007` | `RC-BRK-002` | atomic metadata publicationとoutput appendがpartial final registryを公開しない | Yes | Yes | restart/parallel readでvalid旧版またはvalid新版だけを読める | Done |
| `TP-BRK-008` | `RC-BRK-002` | Host lossがJob Object closeでworker treeを停止し、recoveryがno-orphan outcomeを記録する | Yes | Yes | prior Hostのrunning processは継続せず、`HostLostWorkerTreeTerminated`、exit code/resultなし | Done |
| `TP-BRK-009` | `RC-BRK-003` | facade/Host restart後、list→get→bounded outputが同じrun IDのdurable recordを返す | Yes | Yes | IDs/state/output locatorが一致し、`get_output`はcursor、records、`has_more`、byte/record capを返す | Done |
| `TP-BRK-010` | `RC-BRK-003` | natural completionとcancel request/deliveryのraceを決定規則どおり記録する | Yes | Yes | request前exitは`Exited`、delivery後exitは`CancelledByBroker`、request/delivery/timestampを保存 | Done |
| `TP-BRK-011` | `RC-BRK-003` | kill delivery failureとalready-terminal cancelをterminal誤認/巻戻しなしで扱う | Yes | Yes | delivery failureはnonterminal diagnostic、後続exitは`ExitedAfterFailedCancel`; terminal runは不変 | Done |
| `TP-BRK-012` | `RC-BRK-003` | corrupt/missing runとsingle-writer conflictを診断する | Yes | Yes | explicit not-found/corrupt/busy response、別authorityのsilent overwriteなし | Done |
| `TP-BRK-013` | `RC-BRK-004` | zero/nonzero/launch failure/cancel/Host lossが決定論的terminal event IDとrun IDを持つnew schemaをpublishする | Yes | Yes | `agent-execution-broker:run:<run-id>:terminal`、exact source/provider/run/result locator、optional repository、Codex identityなし | Done |
| `TP-BRK-014` | `RC-BRK-004` | publish failureがrun/outputを保持しnotification dispositionを診断する | Yes | Yes | `Failed` diagnostic、get/output可、manual repair commandのcandidate | Done |
| `TP-BRK-015` | `RC-BRK-004` | same terminal event再観測時にInboxがevent identityでdedupする | Yes | Yes | canonical one item、duplicate is explicit error/ignored per existing policy、別run化なし | Done |
| `TP-BRK-016` | `RC-BRK-004` | InboxがCodex v1とBroker v1をside-by-sideで読み、Broker locatorをlaunchしない | Yes | Yes | Codex resume behavior不変、Broker itemのprovider/run ID表示・copy、unsafe URI execution 0 | Done |
| `TP-BRK-017` | `RC-BRK-004` | actual Codex Appからproduction MCP→Host→Copilot→spool→bounded state/output retrievalを通す最初のlow-risk real issueをEarly Operational Trialとして行う | No | Yes | run ID、asynchronous parent return、terminal event、same-ID bounded retrieval、next action、friction、remaining work priority。material production path change時だけformal E2Eを再実行 | ManualOnly |

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `TP-BRK-001`〜`003` | `RC-BRK-001` | in-process fake pipe/Host allowed | `AgentExecutionBroker.Mcp` and `Host` | actual `codex mcp add` stdio command and detached Host launch | `coding-v1` validation must be production wired. |
| `TP-BRK-004`〜`008` | `RC-BRK-002` | fake process adapter allowed | `CopilotCliAdapter`, Job Object owner, file registry/output writer | installed `copilot` executable/profile and durable root | fake output only/no-orphan test onlyは不可。 |
| `TP-BRK-009`〜`012` | `RC-BRK-003` | temp directory/fake clock allowed | Host state/cancel/store | real Host mutex, named pipe, restart process | bounded cursor/limit and cancel delivery must be production wired. |
| `TP-BRK-013`〜`016` | `RC-BRK-004` | temp spool/fake filesystem allowed | terminal publisher, new schema, Inbox parser/UI | resolved production spool path and packaged Inbox | Codex `spool-item-v1` must remain compatible. |
| `TP-BRK-017` | `RC-BRK-004` | no substitute | all production components | actual Codex App + non-Control-UI Copilot on a low-risk real issue | first evidence is Early Operational Trial and AC-015 evidence; rerun only after material production-path change. |

## 手動確認のみの項目

- `TP-BRK-017`: authenticated Copilot CLI、actual Codex App MCP discovery、production Host detachment、low-risk real issue、bounded result retrievalを一つのEarly Operational Trialとして確認する。この検証はprivate credentials/working dataをチャットまたはtest fixtureへ記録しない。trial resultだけでformal v0 close-readyを宣言しない。

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-BRK-001` | `RC-BRK-001` | `TP-BRK-001` | async start and stable ID | Guardrail Focus | MCP/Host integration | Done |
| `CASE-BRK-002` | `RC-BRK-003` | `TP-BRK-009` | durable list/get identity | Guardrail Focus | restart integration | Done |
| `CASE-BRK-003` | `RC-BRK-002`,`003` | `TP-BRK-008`,`009`,`012` | restart recovery and no-orphan outcome | Guardrail Focus | process/file integration | Done |
| `CASE-BRK-004` | `RC-BRK-002` | `TP-BRK-005`,`006` | exit 0 fact/result/output separation | Guardrail Focus | adapter/store test | Done |
| `CASE-BRK-005` | `RC-BRK-002` | `TP-BRK-006` | failure diagnostics retention | Guardrail Focus | adapter/store test | Done |
| `CASE-BRK-006` | `RC-BRK-003` | `TP-BRK-010`,`011` | running cancel observation and delivery failure | Guardrail Focus | process integration | Done |
| `CASE-BRK-007` | `RC-BRK-003` | `TP-BRK-010`,`011` | terminal monotonicity | Guardrail Focus | state test | Done |
| `CASE-BRK-008` | `RC-BRK-004` | `TP-BRK-013`,`016` | neutral event and Inbox projection | Guardrail Focus | spool/Inbox integration | Done |
| `CASE-BRK-009` | `RC-BRK-004` | `TP-BRK-014` | publish failure preserves run | Guardrail Focus | failure injection | Done |
| `CASE-BRK-010` | `RC-BRK-004` | `TP-BRK-015` | terminal event dedup | Guardrail Focus | Inbox regression | Done |
| `CASE-BRK-011` | `RC-BRK-002` | `TP-BRK-004`,`017` | non-Control-UI capability/prod provider | Guardrail Focus | installed provider/manual E2E | ManualOnly |
| `CASE-BRK-012` | `RC-BRK-001` | `TP-BRK-002` | admission rejection | Guardrail Focus | facade/Host integration | Done |
| `CASE-BRK-013` | `RC-BRK-002` | `TP-BRK-004`,`006` | neutral/provider field separation | Guardrail Focus | record/output schema test | Done |
| `CASE-BRK-014` | `RC-BRK-004` | `TP-BRK-017` | actual Codex App full path | Guardrail Focus | ManualOnly real E2E | ManualOnly |
| `CASE-BRK-015` | none | none | documented manual fallback | Parent Plan pass | docs review / operator walkthrough | NotImplementedOrMismatch |
| `CASE-BRK-016` | `RC-BRK-004` | `TP-BRK-017` | first real-issue E2E is early trial before formal completion | Parent Plan pass | ManualOnly trial record | ManualOnly |

## 注記 / 前提

- external provider、MCP startup、process tree、durable store、notification schemaはすべて production binding required とする。fake/fixture passで`Bound`やclose-readyを宣言しない。
- `TP-BRK-017` は実装直前に行わず、実装後のverification/residual decisionで扱う。旧 `TP-BRK-018` は同一の実Issue経路を重複していたため `TP-BRK-017` に統合し、独立test pointとしては廃止した。
- formal verificationには広い連続運転/運用testが必要になり得るが、現時点では selected RCのtest pointとして十分である。full-coverage escalation recommendation: なし。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: Parent Plan、Behavior Spec、Change Risk Triage、Implementation Contract Kernel、Runtime Contract Kernel、existing Inbox MSTest convention。
- Selected contracts / IDs: `RC-BRK-001`〜`RC-BRK-004`; `TP-BRK-001`〜`TP-BRK-017`（旧 `TP-BRK-018` は `TP-BRK-017` へ統合）。
- Files inspected: 上記artifactと既存Inbox test projectのみ。
- Files intentionally not inspected: full test suite、provider implementation internals。test designのselected scope外のため。
- Decisions made: all TP production binding required、no-orphan/cancel race、required `coding-v1`、bounded retrieval、deterministic event identity、side-by-side spool regression、single ManualOnly E2E/trial、no fake-only completionを固定した。
- Behavior case coverage: `CASE-BRK-001`〜`014`はGuardrail Focus、`015`はParent Plan docs pass、`016`は`TP-BRK-017`のManualOnly early trial。
- Do not redo unless new evidence appears: TP mapping、substitute policy、production binding requirement、no-orphan/cancel rule、bounded retrieval、manual evidence boundary。
- Remaining work: 自動テスト、production binding、wiringのbounded verificationは完了。`ManualOnly`: TP-BRK-017（通常runと、別disposable worktreeでのcancel smoke）。
- Recommended next step: verification kernelで自動証跡を確定し、資格情報と対象Issueの人手承認後にTP-BRK-017を実行する。
