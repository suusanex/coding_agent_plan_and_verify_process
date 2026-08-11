# Agent Execution Broker Operational v0 実装 Plan

## Process metadata

```yaml
process_route: plan-coverage-residual-flow
process_route_source: explicit-user-selection
user_selection_evidence: current user turn selecting plan-coverage-residual-flow
documentation_level: standard
implementation_route: adaptive
implementation_route_source: default
```

## 目的

Codex Appを最初のControl UIとし、provider-neutralなAgent Execution Brokerを介して少なくとも一つのnon-Control-UI production worker adapterを非同期実行する。runの開始、durableな状態把握、terminal eventによる完了認識、providerから取得可能なexecution output / diagnosticsの回収、次のレビュー・追加指示・手動resume判断までを、本物の開発Issueで一連の運用として成立させる。

## Source of truth

- Goal Context: `plans/goal-context-multi-agent-execution-broker-operational-v0.md`
- Black-box Behavior Spec: `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md`
- 既存 notification producer contract: `scripts/codex-notification-runtime/local-spool-interface.md`
- 既存 Inbox goal / consumer boundary: `docs/goal-context-local-spool-winui-inbox.md`

## Scope

- 実際のCodex Appからproduction integrationとして利用できる小さなlocal Broker facade。
- facade の lifetime から切り離された worker execution owner。
- provider-neutral run contract と provider-specific adapter boundary。
- run identity、state transition、request metadata、timestamps、output address、observed exit fact、agent-reported result metadata の durable storage。
- `start_run`、`get_run`、`list_runs`、`get_output`、`cancel_run`。
- Control UIであるCodex Appとは異なるproviderに対する、少なくとも一つのevidence-backed production adapter。
- provider-neutral terminal event の既存 notification plane への接続と Local Inbox からの識別可能性。
- 実 worker と本物の開発 Issue を使う Operational v0 E2E と運用手順。

## Non-goals

- `NG-001`: Broker を完全な worktree manager にしない。
- `NG-002`: provider 共通 session / resume / WAITING_FOR_USER protocol を完成させない。
- `NG-003`: PR URL / artifact 自動検出、usage / cost 集計、provider 自動選択を行わない。
- `NG-004`: worker dependency orchestration、自動 retry / recovery、複数 worker DAG を実装しない。
- `NG-005`: ACP 対応または複数 Control UI 対応を v0 completion 条件にしない。
- `NG-006`: Completion Notification / Runtime / Local Spool / Inbox を Broker に統合して umbrella runtime にしない。
- `NG-007`: 既存 `spool-item-v1` に他 provider を Codex callback として偽装しない。
- `NG-008`: process exit 0 を Issue の意味的完全成功と自動判定しない。
- `NG-009`: Issue #70のstandalone Copilot completion source adapterをBroker v0のcompletion条件にしない。provider-neutral spool schema / Inbox evolution等の共有部分は重複実装せず調整する。

## Functional requirements

- `FR-001` Control UI facade は provider ID、repository / working directory、prompt、任意の adapter options を受け取り、admission 成功時に stable な Broker run ID を返す。
- `FR-002` worker execution owner は facade の request / process lifetime と分離され、facade や親 turn が worker 終了まで同期占有されなくても run を継続する。
- `FR-003` run registry は少なくとも `Accepted`、`Starting`、`Running`、terminal states を単調遷移として durable に保持し、各遷移の observed timestamp と authority を記録する。exact state vocabulary は runtime contract で固定する。
- `FR-004` run identity は Broker authority とし、provider session / process ID / notification event ID を別 identity として相互参照できるようにする。
- `FR-005` request metadata、provider、cwd、開始・終了時刻、observed exit fact、cancel fact、diagnostics、output location を Broker memory だけに依存せず保存する。
- `FR-006` production adapterから取得可能なexecution output / diagnosticsをrun単位でdurableに保存し、完了後と再起動後に取得できる。stdout / stderrを区別して取得できるproviderではstream identityを保持するが、merged console / PTY / structured outputしか取得できないproviderをそれだけでunsupportedにしない。bounded retention policyとframingはimplementation/runtime contractで固定する。
- `FR-007` observed process result と agent-reported semantic result は別 field / evidence とし、片方からもう片方を推論しない。
- `FR-008` `get_run` と `list_runs` は durable registry を読み、同じ run ID と current observed state を返す。`get_output` は保存済み output と diagnostics を返す。
- `FR-009` `cancel_run` は cancel request、worker への停止伝達、observed termination を区別し、既に terminal の run を巻き戻さない。
- `FR-010` provider adapter は provider-neutral request / observation contract と provider 固有 invocation / output / session fields の変換だけを所有し、Broker state authority を持たない。
- `FR-011` v0のproduction adapterは、Control UIであるCodex Appとは異なるproviderからcapability evidence gateを通過した最小一つを採用する。gateはprogrammatic invocation、cwd / prompt指定、終了観測、利用可能なexecution output / diagnostics回収、detached ownerからの起動を最低条件とし、未確認の作業仮説だけで正式対応を宣言しない。Codex App→Codex CLIだけでは本要件を満たさない。
- `FR-012` unknown / unsupported provider、invalid cwd、missing prompt、admission policy 違反は worker 起動前に明示拒否し、別 provider へ黙って fallback しない。
- `FR-013` terminal state 確定後、Broker は stable event identity と run/result locator を持つ provider-neutral terminal event を共通 notification plane へ渡す。通知失敗は run completion を消さず診断可能に残す。
- `FR-014` notification / Inbox projection は source provider と Broker run identity を保ち、Codex callback 固有 identity や `resume_uri` が存在するものとして偽装しない。既存 schema の互換 extension か新 schema かは runtime contract で source-backed に決める。
- `FR-015` repository には install / start / stop / health check / run操作 / output確認 / cancel / manual resume の運用手順を記載する。
- `FR-016` formal Operational v0 verificationは、実際のCodex App、production integration、production execution owner、non-Control-UI production adapter、durable store、notification plane、Codex Appからのstate / result retrievalを通る本物の開発Issueを含む。fixture-only、fake-only、MCPテストクライアントのみ、process-start-onlyをcompletion evidenceにしない。
- `FR-017` first usable production vertical sliceが実際のCodex App→Broker→non-Control-UI worker→durable output→completion notification→Codex App result retrievalまで通った時点で、formal v0 completionを待たず低リスクな本物IssueによるEarly Operational Trialを開始する。trialで得た摩擦と残件をhardening順序へ反映するが、trial成功だけで残りのFR / ACを完了扱いしない。

## Acceptance conditions

- `AC-001` (`FR-001`,`FR-002`) valid request は stable run ID を返し、親 turn が終了または別作業へ移っても worker run が継続する。
- `AC-002` (`FR-003`〜`FR-005`) run の各 observed state と timestamps を facade / Broker 再起動後も同一 run ID で取得できる。
- `AC-003` (`FR-003`,`FR-009`) terminal state は cancel 再要求や再読込で非terminalへ戻らず、cancel accepted と process terminated を区別できる。
- `AC-004` (`FR-006`) providerから取得可能なexecution output / diagnosticsをrun終了後に取得できる。separated streamを提供するproviderではidentityを保持し、merged console / PTY / structured outputでは実際の形を明示する。empty output、partial output、nonzero exitでも取得契約が崩れない。
- `AC-005` (`FR-007`) UI/API/保存 artifact で observed exit と agent-reported result が別項目として確認でき、exit 0 のみで semantic success を表示しない。
- `AC-006` (`FR-008`) list→get→output の各操作が同じ run identity と durable authority を参照する。
- `AC-007` (`FR-009`) running run の cancel は bounded に結果を返し、最終状態が観測される。already-terminal run への cancel は元の terminal fact を保持する。
- `AC-008` (`FR-010`,`FR-011`) Codex Appとは異なるproviderのproduction adapterについて、capability evidence、invocation address、version、supported/unsupported operationがdurable design/verification evidenceに残る。
- `AC-009` (`FR-012`) unknown provider、invalid cwd、missing prompt は process 未起動で拒否され、理由を取得できる。
- `AC-010` (`FR-013`) zero exit、nonzero exit、launch failure、cancel の各 terminal event が stable event ID と Broker run ID を保って notification plane に渡る。
- `AC-011` (`FR-013`) notification publish failure 後も run state/output を Broker から取得でき、失敗 diagnostic と再送/非再送 disposition を判断できる。
- `AC-012` (`FR-014`) non-Codex worker の Inbox item / event は provider を正しく示し、Codex thread/turn/resume URI を捏造しない。
- `AC-013` (`FR-013`,`FR-014`) 同じ terminal event の再観測で利用者に別 run 完了として重複提示されない identity contract を検証できる。
- `AC-014` (`FR-015`) README または運用 docs の手順だけで人が Broker の起動確認、run開始、状態確認、output確認、cancel、停止、手動次行動を実施できる。
- `AC-015` (`FR-016`) 実際のCodex Appからproduction integrationを通してnon-Control-UI provider workerを`start_run`し、run IDを受け取り、親turnがworker終了を待たずに戻る。終了後、実際のCodex Appから同じrunのstate / outputを取得し、terminal notification→レビューまたは次指示まで完走したevidenceが残る。
- `AC-016` (`FR-016`) production wiring / entrypoint が検証され、fake adapter、in-memory registry、fixture event だけで完了扱いされない。
- `AC-017` (`NG-001`〜`NG-009`) non-goalsがBroker completionの暗黙要件へ拡張されず、既存notification packageの責務もgeneric orchestrationへ広がらない。Broker-owned runのterminal observationはBrokerが発行し、Issue #70のstandalone adapter完成を待たない。
- `AC-018` (`FR-017`) AC-001、AC-004〜006、AC-008、AC-010〜012、AC-015の最小production経路が成立した時点で、未完のcancel/restart/hardening/docs項目を明示したまま低リスクな本物IssueのEarly Operational Trialを開始し、run evidence、利用上の摩擦、残件の優先順位を記録する。trial成功はformal v0 close readinessを意味しない。

## Black-box behavior coverage

- Expansion required: Yes
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md`
- Plan readiness: ReadyForRiskTriage
- Expansion decision reason: durable state、restart、cancel、terminal notification、dedup、negative expectations、provider capability gate により結果が変わり、inline sketch では traceability を保てない。
- Blocking requirement-elaboration items: なし。provider / store / transportのexact selectionはbehavior ambiguityではなくdownstreamのevidence-backed implementation/runtime contract decisionとして明示済み。

### Case-to-Plan mapping

| Case ID | Source IDs | FR / AC | Disposition | Notes |
| --- | --- | --- | --- | --- |
| CASE-BRK-001 | SRC-BRK-001,002,007 | FR-001,002 / AC-001 | MappedToPlan | async start |
| CASE-BRK-002 | SRC-BRK-003,007 | FR-003,004,008 / AC-002,006 | MappedToPlan | durable query |
| CASE-BRK-003 | SRC-BRK-003,004 | FR-005,006,008 / AC-002,004 | MappedToPlan | restart recovery |
| CASE-BRK-004 | SRC-BRK-004,005,011 | FR-003,006,007 / AC-004,005 | MappedToPlan | exit 0 separation |
| CASE-BRK-005 | SRC-BRK-004,005 | FR-003,006,007 / AC-004,005 | MappedToPlan | failure diagnostics |
| CASE-BRK-006 | SRC-BRK-005,007 | FR-009 / AC-003,007 | MappedToPlan | running cancel |
| CASE-BRK-007 | SRC-BRK-005,007 | FR-003,009 / AC-003,007 | MappedToPlan | terminal monotonicity |
| CASE-BRK-008 | SRC-BRK-006,010 | FR-013,014 / AC-010,012 | MappedToPlan | notification projection |
| CASE-BRK-009 | SRC-BRK-003,006 | FR-013 / AC-011 | MappedToPlan | fail-open observation |
| CASE-BRK-010 | SRC-BRK-003,006 | FR-004,013 / AC-013 | MappedToPlan | dedup identity |
| CASE-BRK-011 | SRC-BRK-008,009,014 | FR-010,011 / AC-008 | MappedToPlan | capability gate |
| CASE-BRK-012 | SRC-BRK-001,007,014 | FR-012 / AC-009 | MappedToPlan | admission rejection |
| CASE-BRK-013 | SRC-BRK-008,009 | FR-004,007,010 / AC-005,008 | MappedToPlan | neutral vs provider fields |
| CASE-BRK-014 | SRC-BRK-001,012,014 | FR-016 / AC-015,016 | MappedToPlan | actual Codex App + non-Control-UI provider final E2E |
| CASE-BRK-015 | SRC-BRK-013 | FR-015 / AC-014 | DeferredWithSource | automated resume等は非必須、manual pathを文書化 |
| CASE-BRK-016 | SRC-BRK-012,015 | FR-017 / AC-018 | MappedToPlan | first usable vertical slice後のearly operational trial |

## Affected components and implementation scope

| Component / path | Change / read | Responsibility in this Plan |
| --- | --- | --- |
| `apps/AgentExecutionBroker/`（新規候補） | Change | durable run owner、state machine、adapter host、output persistence、local service lifecycle。exact project layoutはArchitecture readinessで確定。 |
| `apps/AgentExecutionBroker.Mcp/` または同等 facade（新規候補） | Change | Codex App向け `start_run/get_run/list_runs/get_output/cancel_run` surface。Broker execution ownerとはlifetime分離。 |
| `scripts/codex-notification-runtime/` | Read / bounded Change candidate | Broker-owned runのprovider-neutral terminal eventを既存notification planeへ渡す共有境界。既存Codex callback producerをorchestrator化せず、Issue #70 standalone adapterをBroker v0へ取り込まない。 |
| `apps/CodexLocalInbox/` | Read / bounded Change candidate | provider-neutral source/run/result locatorを表示・openできる consumer evolution。exact schema決定後のみ変更。 |
| `docs/`、root `README.md` | Change | install、operation、manual fallback、responsibility boundaries。 |
| `tests/` の新規 Broker tests と既存 Inbox/runtime tests | Change | state machine、persistence、adapter process、notification、production binding、E2E。exact test pointsはdownstreamで確定。 |
| `apm-packages/completion-notification-decorator/` | Conditional mirror Change | canonical notification assetsを変更する場合だけ同期。Broker ownershipは追加しない。 |

## Bounded implementation sequence

1. 実際のCodex Appがproduction integrationを通してrequestを検証し、Broker execution ownerにrun admissionを渡す。
2. Broker が durable run record を作成して run ID を authority とし、eligible adapter を起動する。
3. Brokerがadapter/workerのprocess lifecycleとproviderから取得可能なexecution output / diagnosticsを観測し、durable outputと単調state transitionを記録する。
4. cancel または自然終了で terminal observed fact を確定し、agent-reported result と分離して保存する。
5. stable terminal event を notification plane へ投影し、Inbox/result locator から同じ run を回収する。
6. 実際のCodex Appからlist/get/outputでrunを再取得し、人または親agentが次行動を選ぶ。
7. この最小production vertical sliceが通った時点でEarly Operational Trialを開始し、そのevidenceを残りのhardeningへ戻す。

## Known high-risk boundary candidates

| Risk trigger | Present / Absent / Unclear | Candidate boundary |
| --- | --- | --- |
| Cross-process or cross-service sequence | Present | Codex App facade → Broker owner → provider CLI process |
| Queue / event / webhook / background worker | Present | detached run owner と terminal event publication |
| External API or SDK | Unclear | MCP SDK / selected provider CLI surface |
| Authentication or authorization | Unclear | local client admission、provider CLI credentials inheritance |
| Durable state / retry / replay / idempotency | Present | run registry、output、terminal event identity、restart recovery |
| Startup wiring / DI / configuration | Present | facade-to-Broker endpoint、service startup、adapter registry、spool path |
| Production implementation split from test substitute | Present | fake adapter / in-memory store と production process/store |
| Multiple runtime participants coordinating state | Present | facade、Broker、adapter、worker process、notification runtime、Inbox |
| Observable behavior spanning more than one component | Present | startからnotification/result retrievalまで |

## Implementation-realization residuals

| Residual ID | Item | Status | Required downstream action |
| --- | --- | --- | --- |
| IR-BRK-001 | Codex App local integration surface と production address | Unclear | implementation contractでMCP feasibility、startup、IPC、permissions、実Codex App manual evidence方法を確認 |
| IR-BRK-002 | 最初のproduction provider と exact CLI invocation/version | Unclear | capability evidence gateを実機・公式contractで確認し一つ選択 |
| IR-BRK-003 | durable store、output framing、crash recovery、single-writer/lock | Unclear | implementation/runtime contractでauthority、atomicity、provider output capabilityを固定 |
| IR-BRK-004 | provider-neutral terminal event と spool/inbox schema evolution | Unclear | existing `spool-item-v1` compatibilityを調べ、偽装なしの契約を選択 |
| IR-BRK-005 | cancel の process-tree semantics と terminal reconciliation | Unclear | implementation/runtime contractとtest designで固定 |

## change-risk-triage への引き継ぎ

- 最小runtime sequenceは実Codex App→facade→durable Broker owner→non-Control-UI provider process→terminal durable state→notification plane→Codex App result retrieval。
- control/execution、persistence/recovery、notification/consumerは一つのvertical sequence内のhigh-risk boundariesとして分類し、一つのbounded parent passでimplementation contract→runtime contract→test design→implementation→verificationの順序を作れるか判定する。
- risk数やcomponent数だけで`full-coverage`へ上げない。
- production adapter、store、notification event は fake-only completion を禁止する。

## Handoff Packet

- Profile used: plan-kernel
- Plan artifact: `plans/goal-context-multi-agent-execution-broker-operational-v0-plan.md`
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md`
- Source artifacts: Goal Context、Black-box Behavior Spec、existing Local Spool interface、Inbox Goal Context、root README package boundaries。
- Selected contracts / IDs: このエージェントでは選択しない。最終選択は `change-risk-triage.agent.md` が行う。
- Implementation-realization residuals: `IR-BRK-001`〜`IR-BRK-005`は`Unclear`。implementation前にimplementation/runtime contractで解消する。
- Files inspected: `plans/goal-context-multi-agent-execution-broker-operational-v0.md`、`docs/goal-context-local-spool-winui-inbox.md`、`scripts/codex-notification-runtime/local-spool-interface.md`、`scripts/codex-notification-runtime/README.md`、`apps/CodexLocalInbox/README.md`、`README.md` の関連箇所。
- Files intentionally not inspected: provider CLI implementation全体、MCP SDK source、全tests、無関係APM packages。risk/contract phase前のbounded Planに不要。
- Decisions made: Operational v0 completion unit、実Codex App start/result経路、non-Control-UI provider capability gate、Early Operational Trial、run/notification identity分離、observed/reported result分離、provider-capability-aware output、Issue #70境界、manual fallback、non-goalsをFR/ACへ固定した。store/transport/provider exact selectionはdownstream evidence gateへ委譲した。
- Do not redo unless new evidence appears: FR-001〜017、AC-001〜018、Case mapping、non-goals、bounded runtime sequence。
- Remaining work: `Consumed`: behavior expansionとCase mapping。`Blocking`: RiskTriage後に選ばれるimplementation/runtime/test/handoff gates。`DeferredWithReason`: NG-001〜009とCASE-BRK-015の自動化。
- Recommended next step: `change-risk-triage.agent.md` に本 Plan、Behavior Spec、`IR-BRK-001`〜`005` を渡す。
