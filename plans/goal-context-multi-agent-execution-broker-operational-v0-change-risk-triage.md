# Change Risk Triage: Agent Execution Broker Operational v0

## Plan readiness check

| Check | Result | Notes |
| --- | --- | --- |
| Expansion decision exists? | Yes | Plan は `Expansion required: Yes` |
| Behavior spec exists when required? | Yes | `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md` |
| Relevant source requirements have Case IDs? | Yes | `CASE-BRK-001`〜`016` |
| Relevant Case IDs are mapped to FR / AC or explicit disposition? | Yes | 001〜014と016は`MappedToPlan`、015は`DeferredWithSource` |
| Negative expectations are represented? | Yes | identity偽装、fake-only、sync-only、semantic-success推論、scope拡張をFR/AC/NGへ接続 |
| Blocking requirement ambiguity remains? | No | exact provider/store/transportはevidence-backed contract decisionとして残るが、期待behaviorは確定 |
| Plan readiness status | ReadyForRiskTriage | risk/profile分類へ進行可 |
| Documentation level | standard | separate behavior、implementation contract、runtime contract、test design、production-binding guardrailが必要 |

## 推奨プロファイル

`standard-slice`

- Recommendation confidence: High
- Evidence that would lower the profile: durable execution owner、provider adapter、terminal event projectionが既存production pathとして揃い、選択RCを1〜3件のnarrow contractだけで閉じられる証拠。
- Evidence that would raise the profile: Broker serviceの独立製品化、remote Broker、複数provider同時正式対応、独立daemon / persistent queue、notification schemaの独立migrationなど、単一vertical sequenceへ収束しないsource change。

## 理由

この変更は、実Codex App→facade→durable Broker owner/store→non-Control-UI provider worker→terminal state→notification plane→Codex App result retrievalという一つのbounded production vertical sequenceとして説明できる。control、execution/persistence、notification/consumerは独立機能ではなく、同じrun identityとterminal authorityを受け渡す連続したhopである。

provider、store、transport、notification schemaの未確定事項はimplementation-realization riskであり、単一passを不可能にする根拠ではない。`implementation-contract-kernel.agent.md`でproduction address、provider capability、store、Codex App integration、schema boundaryを先に固定し、その後runtime contract / test design / handoff reviewを通せば、fake contractの固定、Codex identity偽装、fake-only completionを同じbounded pass内で防げる。よってguardrail depthは維持しつつ、process breadthは`standard-slice`に留める。

## High-risk boundaries

| Boundary | Producer | Consumer | Mechanism | Risk type |
| --- | --- | --- | --- | --- |
| HB-BRK-001 | Codex App / parent agent | local Broker facade | MCPまたは同等local tool invocation | production address、permissions、request/admission contract |
| HB-BRK-002 | Broker facade | long-lived execution owner | local IPC / service endpoint | lifetime separation、run ID authority、startup/reconnect |
| HB-BRK-003 | execution owner | non-Control-UI provider adapter / worker CLI | child processまたはprovider protocol | invocation、credentials、available execution output/diagnostics、exit observation |
| HB-BRK-004 | execution owner | durable run/output store | durable writes / recovery reads | atomicity、single writer、crash recovery、state monotonicity |
| HB-BRK-005 | cancel request owner | running worker process tree | provider/process termination | accepted vs observed termination、race、terminal reconciliation |
| HB-BRK-006 | terminal run owner | notification runtime / Local Spool | provider-neutral terminal event | schema、event ID、fail-open、dedup、source identity |
| HB-BRK-007 | Local Spool | CodexLocalInbox / result opener | filesystem consumer contract | schema evolution、non-Codex display、result locator safety |

## 対象とする runtime contracts

| Contract ID | Boundary | What is at risk | Why selected | Triage status | Next action |
| --- | --- | --- | --- | --- | --- |
| RC-BRK-001 | actual Codex App / production facade → long-lived Broker owner | request validation、run ID authority、lifetime分離、reconnect/startup、actual App evidence | test clientだけでstart/retrievalを完了扱いする危険 | Deferred | implementation contractでCodex App integration surface、production address、manual evidence方法を固定 |
| RC-BRK-002 | Broker owner → non-Control-UI provider adapter/worker process | capability gate、cwd/prompt、available output/diagnostics、exit/cancel、credential inheritance | Codex CLIのみ、nearest-provider substitution、fake-only成功を防ぐ | Deferred | implementation contractでprovider/version/invocation/output capability/production addressを固定 |
| RC-BRK-003 | Broker owner ↔ durable run/output store | state machine、atomicity、restart recovery、single-writer、terminal monotonicity | Broker memory-onlyまたはraceでhistory/stateを失う | Deferred | implementation contractでstore/address/ownershipを固定しruntime contractでcrash/reconciliationを定義 |
| RC-BRK-004 | terminal run → notification plane → Codex App/Inbox result retrieval | event/source/run identity、schema evolution、dedup、fail-open、safe locator、Issue #70境界 | Codex偽装、standalone adapter scope混入、通知だけ成功するfalse completionを防ぐ | Deferred | implementation contractでBroker-owned eventとIssue #70境界を固定しruntime contractへ渡す |

## 選択されなかった候補 runtime contracts

| Contract ID | Boundary | Why not selected | Candidate status | Suggested next action |
| --- | --- | --- | --- | --- |
| NRC-BRK-001 | human/manual resume command → provider CLI | v0は共通resume automationを要求せず、manual fallbackを許容 | OutOfScopeForThisPass | 運用docsでprovider固有手順だけ残す |
| NRC-BRK-002 | provider usage/cost → automatic scheduler | v0 non-goal | OutOfScopeForThisPass | 実運用計測後の別Plan |
| NRC-BRK-003 | Broker → worktree manager | v0は親agent/既存Git操作へ委譲 | OutOfScopeForThisPass | 必要性が実測された後続Issue |

## Bounded runtime sequence

| Step | Producer / owner / consumer | Mechanism | Execution model | State / authority | Evidence |
| --- | --- | --- | --- | --- | --- |
| 1 | Codex App parent → Broker facade | local tool/MCP candidate | Cross-process IPC / external local process | requestは入力、run ID authorityはBroker | Plan FR-001,002; AC-001 |
| 2 | facade → long-lived Broker owner | local IPC / service activation | Cross-process IPC | Broker ownerがrun admissionとregistry authority | FR-002〜005 |
| 3 | Broker owner → durable store | atomic durable write/read | Cross-process durable-state observation | run state/output locator/terminal fact | FR-003〜008 |
| 4 | Broker owner → provider adapter → worker | process/protocol invocation | Independent background worker | provider session/process IDはsecondary identity | FR-010〜012 |
| 5 | worker → Broker owner/store | providerから取得可能なexecution output/diagnostics、exit/cancel observation | Cross-process IPC + durable observation | observed factとreported resultを分離 | FR-006,007,009 |
| 6 | terminal owner → notification plane/spool | versioned terminal event | Persistent event/file handoff | stable event ID、run/result locator | FR-013,014 |
| 7 | actual Codex App / Inbox → store/output | later query/open | Cross-process durable-state observation | Broker run IDへ戻る | FR-008,014〜017; AC-015,018 |

## Execution-model boundary classification

| Execution model | Present / Absent / Unclear | Boundary / participants | Evidence |
| --- | --- | --- | --- |
| Same-process ABI / FFI boundary | Absent | current Planにnative ABI要求なし | Goal Context / Plan |
| Cross-process IPC | Present | Codex App/facade、Broker owner、provider CLI | FR-001,002,010 |
| Cross-process durable-state observation | Present | Broker writes、facade/Inbox/restart recovery reads | FR-003〜008,013,014 |
| External or independently deployed service | Unclear | local Broker serviceとprovider CLIのdeployment/startup方式 | IR-BRK-001,002 |
| Local asynchronous operation / UI-thread handoff | Present | Codex App requestはworker終了前に戻り、Inboxはlater observation | AC-001,010〜015 |
| Independent background worker | Present | provider worker process | FR-002,010,011 |
| Persistent queue / replayable job | Unclear | terminal eventはdurable handoffだがjob retry/claimはv0非目標 | FR-013, NG-004 |

## Risk semantic スキャン

| Risk semantic | Present / Absent / Unclear | Boundary / participants | Notes |
| --- | --- | --- | --- |
| External API or SDK | Unclear | MCP candidate、selected provider CLI | exact API/version未選択 |
| Authentication or authorization | Unclear | local client admission、provider credential context | remote/multi-user authは非目標だがinheritanceを要確認 |
| Durable state ownership / observation | Present | Broker/store/facade/Inbox | run authorityを一意化必須 |
| Retry / resume / replay / idempotency | Present | restart recovery、terminal event dedup、cancel race | automatic worker retryは非目標 |
| Startup wiring / DI / configuration | Present | facade endpoint、Broker service、adapter registry、spool | production entrypoint必須 |
| Production implementation split from test substitute | Present | fake adapter/in-memory store vs production process/store | fake-only禁止 |
| Multiple runtime participants coordinating state | Present | facade、Broker、adapter、worker、notification、Inbox | identity continuityがshared invariant |
| Observable behavior spanning more than one component | Present | start→notify→result retrieval | AC-015のE2E |

## 実装実現性リスク

| Trigger | Status | Evidence | Required next step |
| --- | --- | --- | --- |
| Plan names a specific external SDK or API | Unclear | MCPが有力だがexact SDK未確定 | implementation contractでproduction APIとactual Codex App evidence方法を確認 |
| Plan names a package, release, binary artifact, or local lib folder | Present | provider CLI binary/versionがproduction adapterを決める | capability evidence、version、installation addressを固定 |
| Plan names a namespace, type, method, extension method, provider ID, or config section | Unclear | exact code surface未作成 | implementation contractで確認 |
| Existing code contains a similar but different implementation path | Present | Codex notification runtime/Spoolはorchestratorではない | nearest-neighbor reuseを禁止し境界を明示 |
| Implementation requires DI/startup/configuration wiring | Present | long-lived owner、facade、adapter registry、notification | implementation contractでentrypointを固定しproduction wiringを検証 |
| The affected production address is not known from current evidence | Present | Broker projects/transport/store/provider未確定 | implementation contractでaddress ownershipを固定 |
| Plan contains remaining work about API surface inspection or dependency confirmation | Present | IR-BRK-001〜005 | immediate next agentをimplementation-contract branchとする |

## 推奨する次の agent

Immediate next agent は `implementation-contract-kernel.agent.md`。

入力はParent Plan、Black-box Behavior Spec、本triage、Goal Context、既存Local Spool/Inbox boundaries。implementation contractはactual Codex App integration、long-lived Broker production address/lifetime、non-Control-UI provider/version/invocation/output capability、durable store、Broker-owned terminal event schema、Issue #70 standalone adapter境界、Early Operational Trial gateを固定する。

Minimum required flow:

1. `implementation-contract-kernel.agent.md`
2. 非自明またはunresolvedなself-checkが残る場合だけ`implementation-contract-review-kernel.agent.md`
3. `runtime-contract-kernel.agent.md`
4. `test-design-kernel.agent.md`
5. `implementation-handoff-review.agent.md`
6. `high-implementation-starter.agent.md`から始まるAdaptive implementation
7. first usable vertical slice gate成立時にEarly Operational Trialを行い、残りのhardeningへevidenceを戻す
8. formal parent Plan実装後に`verification-kernel.agent.md`
9. 必要ならgap triage/resolution
10. `residual-decision-gate.agent.md`

## Architecture-readiness triggers

該当なし。`standard-slice`を選択したためArchitecture Slice Readinessへrouteしない。participant ownership、state authority、schema、entrypointはimplementation/runtime contractで同じbounded sequenceに対して固定する。

## Why standard-slice is insufficient

- Candidate bounded sequence: actual Codex App→production facade→durable Broker owner/store→non-Control-UI provider worker→terminal state→notification plane→actual Codex App/Inbox result retrievalを一parent passで順次実装・検証する。
- Independent implementation slices required: No。複数componentは同じrun identityとterminal authorityを順に受け渡す一つのvertical featureであり、独立したruntime sequenceではない。
- Shared semantics that must remain fixed before decomposition: Broker run ID authority、state monotonicity、observed fact/reported result分離、non-Control-UI provider gate、terminal event ID、result locator、Issue #70境界、fake-only禁止。decomposition前architectureではなくimplementation/runtime contractで固定できる。
- Why one bounded parent pass is insufficient: N/A。一つのbounded parent passでimplementation contract→runtime contract→test design→handoff review→Adaptive implementation→Early Operational Trial→hardening→verificationの安全な順序を作れる。
- Failure mode that decomposition prevents: N/A。fake contract、memory-only store、Codex identity偽装、test-client-only evidenceは同じpassのcontract/test/production-binding guardrailsで防ぐ。
- Escalation gate result: NotSatisfied

## full-coverage 時の分割方針

該当なし。`standard-slice`の一つのproduction vertical passとして扱う。

## 今回の triage の対象外

- MCP SDK、各provider CLI、SQLite等store candidateの詳細比較。implementation contractの責務。
- class/interface/project layout、test seam。implementation agentの責務。
- worktree manager、common resume、usage/cost、自動provider選択、ACP。Plan non-goals。
- private provider credentialsを使う実機smoke。triageではprivate dataへアクセスしない。

## Handoff Packet

- Profile used: triage-only
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Behavior spec artifact: `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md`
- Recommended process profile: standard-slice
- Recommendation confidence: High
- Full-coverage escalation gate: NotSatisfied
- Source artifacts: Goal Context、Parent Plan、Black-box Behavior Spec、review attachment、existing Local Spool interface、Inbox Goal Context、root README boundaries。
- Selected contracts / IDs: `RC-BRK-001`〜`RC-BRK-004`
- Files inspected: `plans/goal-context-multi-agent-execution-broker-operational-v0.md`、同`-plan.md`、同`-black-box-behavior-spec.md`、`scripts/codex-notification-runtime/local-spool-interface.md`、`scripts/codex-notification-runtime/README.md`、`apps/CodexLocalInbox/README.md`、`docs/goal-context-local-spool-winui-inbox.md`、root `README.md`関連箇所。
- Files intentionally not inspected: provider CLI internals、MCP SDK、全repository source/tests。triage classificationに不要。
- Decisions made: control、execution/persistence、notification/result retrievalを一つのbounded vertical sequenceとして再分類し、component数やimplementation-realization riskだけではfull-coverage gateを満たさないと判断した。actual Codex App、non-Control-UI provider、Early Operational Trial、provider-capability-aware output、Issue #70境界をguardrailへ追加した。
- Implementation realization risk summary: Present/Unclear。provider/API、actual Codex App production address、store、startup、schema、cancel semanticsが未確定で、`implementation-contract-kernel.agent.md`が必要。
- Do not redo unless new evidence appears: bounded sequence、execution-model classification、RC-BRK-001〜004、`standard-slice`判定、full-coverage escalation gate `NotSatisfied`。
- Remaining work: implementation contractでproduction addresses/capabilities/boundariesを固定し、その後runtime contract/test design/handoff reviewへ進む。実装は未開始。
- Recommended next step: `implementation-contract-kernel.agent.md`。
- Required downstream guardrails: 各RCについてruntime contract identification、participant/boundary mapping、test point mapping、stub/fake/in-memory check、production implementation binding、production wiring/entrypoint verification、未完了のexplicit statusを保持する。
- Full-coverage handling: N/A。escalation gateは`NotSatisfied`であり、Architecture Slice Readiness / decompositionへ進めない。
