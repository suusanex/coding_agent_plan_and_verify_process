# Test Design Kernel: Agent Execution Broker Operational v0

## スコープ

Runtime Contract Kernel の `RC-BRK-001`〜`RC-BRK-004` に対し、observable behavior、substitute policy、production binding requirementを設計する。`Done` は test design行の完了であり、test実装・実行・production verificationの完了ではない。Parent Plan とBehavior Specは依然として唯一の要求authorityである。

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `TP-BRK-001` | `RC-BRK-001` | valid requestのadmissionがstable run IDを返し、MCP requestがworker exitを待たない | Yes | Yes | responseにrun ID、Host registryに`Accepted`、facade終了後もHost runが残る | Done |
| `TP-BRK-002` | `RC-BRK-001` | unknown provider/invalid cwd/empty prompt/policy violationを起動前に拒否する | Yes | Yes | rejection reason、adapter process start 0、fallback 0 | Done |
| `TP-BRK-003` | `RC-BRK-001` | pipe未起動時のHost launch/reconnectがboundedで、二重Hostを作らない | Yes | Yes | one mutex owner、bounded unavailable diagnostic、second Hostはexisting endpointへ接続 | Done |
| `TP-BRK-004` | `RC-BRK-002` | Copilot adapterがprovider/cwd/prompt/session/tool profileをexactにcommandへ投影する | Yes | Yes | process start infoとrecorded provider metadataがinputと一致し、implicit allow-allなし | Done |
| `TP-BRK-005` | `RC-BRK-002` | `Accepted`→`Starting`→`Running`→terminal transitionが単調でtimestamp/authorityを保持する | Yes | Yes | durable `run.json`は後退なし、exit factとreported resultが別 field | Done |
| `TP-BRK-006` | `RC-BRK-002` | structured/stderr/empty/nonzero/launch failure outputを実際のkindで保存する | Yes | Yes | JSONL sequence、kind、diagnostic、exit factを再取得でき、stream捏造なし | Done |
| `TP-BRK-007` | `RC-BRK-002` | atomic metadata publicationとoutput appendがpartial final registryを公開しない | Yes | Yes | restart/parallel readでvalid旧版またはvalid新版だけを読める | Done |
| `TP-BRK-008` | `RC-BRK-002` | processを観測不能なHost restartが推測terminalを作らない | Yes | Yes | `UnknownAfterBrokerRestart` と diagnostic、semantic result未推論 | Done |
| `TP-BRK-009` | `RC-BRK-003` | facade/Host restart後、list→get→outputが同じrun IDのdurable recordを返す | Yes | Yes | IDs、state、output locator、stored outputが一致 | Done |
| `TP-BRK-010` | `RC-BRK-003` | running cancelはrequest/delivery/terminal observationを分離する | Yes | Yes | `CancelRequested`、kill attempt diagnostic、eventual observed terminalの別時点記録 | Done |
| `TP-BRK-011` | `RC-BRK-003` | terminal runへのcancelがstateを巻き戻さない | Yes | Yes | original terminal status/exit fact不変、already-terminal response | Done |
| `TP-BRK-012` | `RC-BRK-003` | corrupt/missing runとsingle-writer conflictを診断する | Yes | Yes | explicit not-found/corrupt/busy response、別authorityのsilent overwriteなし | Done |
| `TP-BRK-013` | `RC-BRK-004` | zero/nonzero/launch failure/cancelがstable terminal event IDとrun IDを持つnew schemaをpublishする | Yes | Yes | schema-valid final JSON、exact source/provider/run/result locator、Codex identityなし | Done |
| `TP-BRK-014` | `RC-BRK-004` | publish failureがrun/outputを保持しnotification dispositionを診断する | Yes | Yes | `Failed` diagnostic、get/output可、manual repair commandのcandidate | Done |
| `TP-BRK-015` | `RC-BRK-004` | same terminal event再観測時にInboxがevent identityでdedupする | Yes | Yes | canonical one item、duplicate is explicit error/ignored per existing policy、別run化なし | Done |
| `TP-BRK-016` | `RC-BRK-004` | InboxがCodex v1とBroker v1をside-by-sideで読み、Broker locatorをlaunchしない | Yes | Yes | Codex resume behavior不変、Broker itemのprovider/run ID表示・copy、unsafe URI execution 0 | Done |
| `TP-BRK-017` | `RC-BRK-004` | actual Codex Appからproduction MCP→Host→Copilot→spool→state/output retrievalを通す | No | Yes | real issueのrun ID、asynchronous parent return、terminal event、same-ID result retrieval、next action evidence | ManualOnly |
| `TP-BRK-018` | `RC-BRK-004` | first usable vertical slice後のEarly Operational Trialを行う | No | Yes | low-risk real issue、run evidence、friction、remaining work priority、formal close未宣言 | ManualOnly |

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `TP-BRK-001`〜`003` | `RC-BRK-001` | in-process fake pipe/Host allowed | `AgentExecutionBroker.Mcp` and `Host` | actual `codex mcp add` stdio command and detached Host launch | fake facade onlyは不可。 |
| `TP-BRK-004`〜`008` | `RC-BRK-002` | fake process adapter allowed | `CopilotCliAdapter`, file registry/output writer | installed `copilot` executable version/invocation and durable root | fake output onlyは不可。 |
| `TP-BRK-009`〜`012` | `RC-BRK-003` | temp directory/fake clock allowed | Host state/cancel/store | real Host mutex, named pipe, restart process | in-memory registry onlyは不可。 |
| `TP-BRK-013`〜`016` | `RC-BRK-004` | temp spool/fake filesystem allowed | terminal publisher, new schema, Inbox parser/UI | resolved production spool path and packaged Inbox | Codex `spool-item-v1` must remain compatible. |
| `TP-BRK-017`,`018` | `RC-BRK-004` | no substitute | all production components | actual Codex App + non-Control-UI Copilot on a real issue | formal/early evidence are distinct. |

## 手動確認のみの項目

- `TP-BRK-017`: authenticated Copilot CLI、actual Codex App MCP discovery、production Host detachment、real issue、result retrieval。この検証はprivate credentials/working dataをチャットまたはtest fixtureへ記録しない。
- `TP-BRK-018`: first usable production vertical slice後のEarly Operational Trial。trial resultはformal v0 close-readyの根拠にしない。

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-BRK-001` | `RC-BRK-001` | `TP-BRK-001` | async start and stable ID | Guardrail Focus | MCP/Host integration | Done |
| `CASE-BRK-002` | `RC-BRK-003` | `TP-BRK-009` | durable list/get identity | Guardrail Focus | restart integration | Done |
| `CASE-BRK-003` | `RC-BRK-003` | `TP-BRK-009`,`012` | restart recovery | Guardrail Focus | process/file integration | Done |
| `CASE-BRK-004` | `RC-BRK-002` | `TP-BRK-005`,`006` | exit 0 fact/result/output separation | Guardrail Focus | adapter/store test | Done |
| `CASE-BRK-005` | `RC-BRK-002` | `TP-BRK-006` | failure diagnostics retention | Guardrail Focus | adapter/store test | Done |
| `CASE-BRK-006` | `RC-BRK-003` | `TP-BRK-010` | running cancel observation | Guardrail Focus | process integration | Done |
| `CASE-BRK-007` | `RC-BRK-003` | `TP-BRK-011` | terminal monotonicity | Guardrail Focus | state test | Done |
| `CASE-BRK-008` | `RC-BRK-004` | `TP-BRK-013`,`016` | neutral event and Inbox projection | Guardrail Focus | spool/Inbox integration | Done |
| `CASE-BRK-009` | `RC-BRK-004` | `TP-BRK-014` | publish failure preserves run | Guardrail Focus | failure injection | Done |
| `CASE-BRK-010` | `RC-BRK-004` | `TP-BRK-015` | terminal event dedup | Guardrail Focus | Inbox regression | Done |
| `CASE-BRK-011` | `RC-BRK-002` | `TP-BRK-004`,`017` | non-Control-UI capability/prod provider | Guardrail Focus | installed provider/manual E2E | ManualOnly |
| `CASE-BRK-012` | `RC-BRK-001` | `TP-BRK-002` | admission rejection | Guardrail Focus | facade/Host integration | Done |
| `CASE-BRK-013` | `RC-BRK-002` | `TP-BRK-004`,`006` | neutral/provider field separation | Guardrail Focus | record/output schema test | Done |
| `CASE-BRK-014` | `RC-BRK-004` | `TP-BRK-017` | actual Codex App full path | Guardrail Focus | ManualOnly real E2E | ManualOnly |
| `CASE-BRK-015` | none | none | documented manual fallback | Parent Plan pass | docs review / operator walkthrough | NotImplementedOrMismatch |
| `CASE-BRK-016` | `RC-BRK-004` | `TP-BRK-018` | early trial before formal completion | Parent Plan pass | ManualOnly trial record | ManualOnly |

## 注記 / 前提

- external provider、MCP startup、process tree、durable store、notification schemaはすべて production binding required とする。fake/fixture passで`Bound`やclose-readyを宣言しない。
- `TP-BRK-017`/`018` は実装直前に行わず、実装後のverification/residual decisionで扱う。
- formal verificationには広い連続運転/運用testが必要になり得るが、現時点では selected RCのtest pointとして十分である。full-coverage escalation recommendation: なし。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: Parent Plan、Behavior Spec、Change Risk Triage、Implementation Contract Kernel、Runtime Contract Kernel、existing Inbox MSTest convention。
- Selected contracts / IDs: `RC-BRK-001`〜`RC-BRK-004`; `TP-BRK-001`〜`TP-BRK-018`。
- Files inspected: 上記artifactと既存Inbox test projectのみ。
- Files intentionally not inspected: full test suite、provider implementation internals。test designのselected scope外のため。
- Decisions made: all TP production binding required、ManualOnly E2E/trial、side-by-side spool regression、no fake-only completionを固定した。
- Behavior case coverage: `CASE-BRK-001`〜`014`はGuardrail Focus、`015`はParent Plan docs pass、`016`はManualOnly early trial。
- Do not redo unless new evidence appears: TP mapping、substitute policy、production binding requirement、manual evidence boundary。
- Remaining work: `NotImplementedOrMismatch`: tests/code/wiring。`ManualOnly`: TP-BRK-017/018。
- Recommended next step: `implementation-handoff-review.agent.md` に全artifactを渡し、Parent Plan/Behavior Case coverageとimplementation authorizationを判定する。
