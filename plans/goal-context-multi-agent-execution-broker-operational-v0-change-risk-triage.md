# Change Risk Triage: Agent Execution Broker Operational v0

## Plan readiness check

| Check | Result | Notes |
| --- | --- | --- |
| Expansion decision exists? | Yes | Plan は `Expansion required: Yes` |
| Behavior spec exists when required? | Yes | `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md` |
| Relevant source requirements have Case IDs? | Yes | `CASE-BRK-001`〜`015` |
| Relevant Case IDs are mapped to FR / AC or explicit disposition? | Yes | 001〜014 は `MappedToPlan`、015 は `DeferredWithSource` |
| Negative expectations are represented? | Yes | identity偽装、fake-only、sync-only、semantic-success推論、scope拡張をFR/AC/NGへ接続 |
| Blocking requirement ambiguity remains? | No | exact provider/store/transportはevidence-backed contract decisionとして残るが、期待behaviorは確定 |
| Plan readiness status | ReadyForRiskTriage | risk/profile分類へ進行可 |
| Documentation level | standard | separate behavior、architecture、runtime、production-binding guardrailが必要 |

## 推奨プロファイル

`full-coverage`

- Recommendation confidence: High
- Evidence that would lower the profile: production facade、execution owner、durable store、provider adapter、terminal event projection、Inbox consumerが既に一つのproduction componentと一つの検証entrypointへ統合され、同じrun identity/state authorityを単一passで検証できる証拠。
- Evidence that would raise the profile: 複数provider同時対応、remote Broker、multi-user authorization、persistent queue/retry orchestrationをcurrent v0へ追加するsource change。

## 理由

この変更は単なるcross-process riskの多さではなく、少なくとも三つの独立したproduction sequenceを持つ。(1) Codex App facadeから長寿命Broker ownerへのcontrol sequence、(2) Brokerからprovider workerへのexecution/persistence/cancel/recovery sequence、(3) terminal factからnotification plane/Inbox/result retrievalへのobservation sequenceである。それぞれ独立して実装・検証可能だが、Broker run identity、terminal state authority、observed factとreported resultの分離、terminal event identityを共有する。

具体的なstandard-slice候補として三sequenceを一つのparent passで順に実装する案を検討した。しかし、provider capability gateが未確定のままfacade/storeを先行するとfake adapter前提の契約が固定され、notification schemaを先行するとCodex identity偽装または後戻りが生じる。逆に全surfaceを同時に変更すると、どのproduction entrypointがrun authorityを持つか、restart/cancel/terminal dedupをどのevidenceで閉じるかが一つのhandoffに混在する。shared semanticsをarchitecture gateで固定してから独立sliceへ分解する必要がある。

## High-risk boundaries

| Boundary | Producer | Consumer | Mechanism | Risk type |
| --- | --- | --- | --- | --- |
| HB-BRK-001 | Codex App / parent agent | local Broker facade | MCPまたは同等local tool invocation | production address、permissions、request/admission contract |
| HB-BRK-002 | Broker facade | long-lived execution owner | local IPC / service endpoint | lifetime separation、run ID authority、startup/reconnect |
| HB-BRK-003 | execution owner | provider-specific adapter / worker CLI | child processまたはprovider protocol | invocation、credentials、stdout/stderr、exit observation |
| HB-BRK-004 | execution owner | durable run/output store | durable writes / recovery reads | atomicity、single writer、crash recovery、state monotonicity |
| HB-BRK-005 | cancel request owner | running worker process tree | provider/process termination | accepted vs observed termination、race、terminal reconciliation |
| HB-BRK-006 | terminal run owner | notification runtime / Local Spool | provider-neutral terminal event | schema、event ID、fail-open、dedup、source identity |
| HB-BRK-007 | Local Spool | CodexLocalInbox / result opener | filesystem consumer contract | schema evolution、non-Codex display、result locator safety |

## 対象とする runtime contracts

| Contract ID | Boundary | What is at risk | Why selected | Triage status | Next action |
| --- | --- | --- | --- | --- | --- |
| RC-BRK-001 | Control UI facade → long-lived Broker owner | request validation、run ID authority、lifetime分離、reconnect/startup | startが同期process handleへ退化するとv0価値を失う | Deferred | `architecture-slice-readiness.agent.md` でcontrol/execution境界とauthority completenessを判定 |
| RC-BRK-002 | Broker owner → provider adapter/worker process | capability gate、cwd/prompt、output/exit/cancel、credential inheritance | nearest-provider substitutionとfake-only成功が最も起きやすい | Deferred | readinessでadapter ownershipとproduction evidence境界を判定 |
| RC-BRK-003 | Broker owner ↔ durable run/output store | state machine、atomicity、restart recovery、single-writer、terminal monotonicity | Broker memory-onlyまたはraceでhistory/stateを失う | Deferred | readinessでdurable authorityとcrash/reconciliation semanticsを判定 |
| RC-BRK-004 | terminal run → notification plane → Inbox/result retrieval | event/source/run identity、schema evolution、dedup、fail-open、safe locator | Codex偽装または通知だけ成功するfalse completionを防ぐ | Deferred | readinessでproducer/consumer schemaとcross-slice invariantを判定 |

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
| 5 | worker → Broker owner/store | stdout/stderr、exit/cancel observation | Cross-process IPC + durable observation | observed factとreported resultを分離 | FR-006,007,009 |
| 6 | terminal owner → notification plane/spool | versioned terminal event | Persistent event/file handoff | stable event ID、run/result locator | FR-013,014 |
| 7 | Inbox/facade → store/output | later query/open | Cross-process durable-state observation | Broker run IDへ戻る | FR-008,014〜016 |

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
| Plan names a specific external SDK or API | Unclear | MCPが有力だがexact SDK未確定 | architecture readiness後、implementation contractでproduction APIを確認 |
| Plan names a package, release, binary artifact, or local lib folder | Present | provider CLI binary/versionがproduction adapterを決める | capability evidence、version、installation addressを固定 |
| Plan names a namespace, type, method, extension method, provider ID, or config section | Unclear | exact code surface未作成 | slice-local implementation contractで確認 |
| Existing code contains a similar but different implementation path | Present | Codex notification runtime/Spoolはorchestratorではない | nearest-neighbor reuseを禁止し境界を明示 |
| Implementation requires DI/startup/configuration wiring | Present | long-lived owner、facade、adapter registry、notification | production wiringを各sliceで検証 |
| The affected production address is not known from current evidence | Present | Broker projects/transport/store/provider未確定 | architecture readiness / elaborationでaddress ownershipを固定 |
| Plan contains remaining work about API surface inspection or dependency confirmation | Present | IR-BRK-001〜005 | architecture後にimplementation-contract branch必須 |

## 推奨する次の agent

Immediate next agent は `architecture-slice-readiness.agent.md`。

入力は Parent Plan、Black-box Behavior Spec、本 triage、Goal Context、既存 Local Spool/Inbox boundaries。readiness は shared identity/state authority、facade/Broker lifetime、durable owner、adapter capability gate、terminal event schema、production entrypointを current source から確定できるか判定する。readiness verdict なしで decomposition へ進めない。

Minimum required flow:

1. `architecture-slice-readiness.agent.md`
2. `NeedsArchitectureElaboration` なら `architecture-elaboration.agent.md` と readiness再実行
3. `StandardSliceSufficient` なら `selected_process: standard-slice` へ戻す
4. `ReadyForSliceDecomposition` または `ArchitectureNotRequired` の場合だけ `plan-slice-decomposition.agent.md`
5. 各sliceで必要な implementation contract、runtime contract、test design、handoff review、Adaptive implementation、independent verification
6. `cross-slice-verification-kernel.agent.md`
7. 必要なら gap triage/resolution
8. `residual-decision-gate.agent.md`

## Architecture-readiness triggers

| Trigger | Status | Evidence | Readinessで確認する事項 |
| --- | --- | --- | --- |
| multiple runtime participants / services / agents | Present | facade、Broker、adapter、worker、notification、Inbox | ownershipとlifetime |
| durable state と derived observation の混在 | Present | registry/output authorityとInbox projection | canonical state vs projection |
| state / artifact / field authority の競合 | Present | Broker run ID、provider session、event ID、Codex IDs | field authority table |
| cross-run / cross-process identity continuity | Present | restart、notification dedup、result retrieval | stable identity lifecycle |
| async / retry / resume / replay / cleanup | Present | detached run、cancel、event dedup。resume/retryは一部non-goal | required vs deferred semantics |
| lane / lock / reservation / shared capacity | Unclear | concurrent runsとsingle writer/store lock | v0 concurrency policy |
| producer / consumer schema または temporal protocol | Present | terminal event→Spool→Inbox | versioningとordering |
| Control Plane / Execution Plane separation | Present | facade/control request vs long-lived worker owner | concrete process/IPC、startup |
| production entrypoint / wiring の共有 | Present | install/service/facade/adapter/notification config | one production route perslice |
| cross-slice invariant / forbidden state | Present | terminal monotonicity、identity偽装禁止、fake-only禁止 | XC候補を固定 |

## Why standard-slice is insufficient

- Candidate bounded sequence: Codex App→facade→Broker/store→provider worker→terminal state→notification plane→Inbox/result retrievalを一parent passで順次実装・検証する。
- Independent implementation slices required: (A) facade/service lifecycleとrun control、(B) durable execution owner/provider adapter/output/cancel、(C) terminal event schema/notification/Inbox projection。少なくとも三つ。
- Shared semantics that must remain fixed before decomposition: Broker run ID authority、state monotonicity、observed fact/reported result分離、provider capability gate、terminal event ID、result locator、fake-only禁止。
- Why one bounded parent pass is insufficient: 各sequenceのproduction entrypointとfailure oracleが異なり、adapter未確定のままA/Cを作るとfake contractが固定される。全surface同時変更ではrestart/cancel/dedup/schema compatibilityの責任と検証evidenceが混在し、独立verificationを保てない。
- Failure mode that decomposition prevents: facadeだけ動くprocess-start-only完成、in-memory/fake adapterのみ成功、再起動でrun消失、Codex identity偽装、notification成功をsemantic completionと誤認、terminal eventとInbox schemaの不一致。
- Escalation gate result: Satisfied

## full-coverage 時の分割方針

- Parent-level acceptance conditions `AC-001`〜`017` と Case mapping を分割後もsource of truthとして保持する。
- cross-slice contract候補は run identity/state authority、provider-neutral request/result、durable terminal transition、terminal event/result locator。
- 候補順序は architecture baseline → control/service slice → execution/persistence/adapter slice → notification/Inbox slice。実際のslice数と依存はreadiness/decompositionが確定する。
- provider adapter eligibility と production evidence はexecution sliceからfake-onlyで先送りしない。
- notification sliceはCodex callback固有schemaを他providerへ流用する前提を置かない。

## 今回の triage の対象外

- MCP SDK、各provider CLI、SQLite等store candidateの詳細比較。Architecture / implementation contractの責務。
- class/interface/project layout、test seam。implementation agentの責務。
- worktree manager、common resume、usage/cost、自動provider選択、ACP。Plan non-goals。
- private provider credentialsを使う実機smoke。triageではprivate dataへアクセスしない。

## Handoff Packet

- Profile used: triage-only
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Behavior spec artifact: `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md`
- Recommended process profile: full-coverage
- Recommendation confidence: High
- Full-coverage escalation gate: Satisfied
- Source artifacts: Goal Context、Parent Plan、Black-box Behavior Spec、existing Local Spool interface、Inbox Goal Context、root README boundaries。
- Selected contracts / IDs: `RC-BRK-001`〜`RC-BRK-004`（parent-level candidates）
- Files inspected: `plans/goal-context-multi-agent-execution-broker-operational-v0.md`、同`-plan.md`、同`-black-box-behavior-spec.md`、`scripts/codex-notification-runtime/local-spool-interface.md`、`scripts/codex-notification-runtime/README.md`、`apps/CodexLocalInbox/README.md`、`docs/goal-context-local-spool-winui-inbox.md`、root `README.md`関連箇所。
- Files intentionally not inspected: provider CLI internals、MCP SDK、全repository source/tests。triage classificationに不要。
- Decisions made: 三つの独立sequenceと共有semanticsを特定し、具体的standard-slice候補を棄却、escalation gateをSatisfiedとした。
- Implementation realization risk summary: Present/Unclear。provider/API、production address、store、startup、schema、cancel semanticsが未確定で、各sliceにimplementation-contract branchが必要。
- Do not redo unless new evidence appears: bounded sequence、execution-model classification、RC-BRK-001〜004、standard-slice insufficiency。
- Remaining work: Architecture Slice Readinessでbaseline completeness、watch paths、shared authority、sliceabilityを判定する。実装・test designは未開始。
- Recommended next step: `architecture-slice-readiness.agent.md`。readiness verdictなしでdecompositionしない。
- Required downstream guardrails: 各RCについてruntime contract identification、participant/boundary mapping、test point mapping、stub/fake/in-memory check、production implementation binding、production wiring/entrypoint verification、未完了のexplicit statusを保持する。
- Full-coverage handling: `architecture-slice-readiness.agent.md` へ進める。readiness verdict なしで decomposition へ進めない。
