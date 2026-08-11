# Black-box Behavior Spec: Agent Execution Broker Operational v0

## Scope

`plans/goal-context-multi-agent-execution-broker-operational-v0.md` を source authority とし、Codex App を最初の Control UI として、provider-neutral な Broker 経由で少なくとも一つの実 worker を非同期実行し、終了認識、結果回収、次の行動までを成立させる Operational v0 の外部挙動を定義する。実装方式、内部 class、transport、永続化 engine、provider 固有 protocol はここでは決定しない。

## Source requirement inventory

| Source ID | Requirement summary | Kind | Source | Notes |
| --- | --- | --- | --- | --- |
| SRC-BRK-001 | Codex App から provider、working directory、prompt を指定して worker run を開始できる | 機能要求 | Goal Context「Operational v0で必要と判断している能力」 | 最初の Control UI は Codex App |
| SRC-BRK-002 | 親 turn / process lifetime から worker の長時間実行を切り離す | lifecycle | 同「全体構成」「利用体験」 | 親が終了まで占有されない |
| SRC-BRK-003 | run identity、状態、output を durable に保持し、再起動後も参照できる | durable state | 同「必要な能力」 | Broker memory のみは禁止 |
| SRC-BRK-004 | stdout / stderr と observed process result を後から取得できる | result retrieval | 同「必要な能力」 | agent-reported result と分離 |
| SRC-BRK-005 | 正常終了、異常終了、cancel 等の observed fact を記録する | state transition | 同「必要な能力」 | 意味的成功とは同一視しない |
| SRC-BRK-006 | terminal event を共通 notification plane に接続し、Local Inbox 等で認識できる | notification | 同「必要な能力」 | v0 の主要価値、後回し不可 |
| SRC-BRK-007 | start、状態取得、一覧、output、cancel の小さな surface を提供する | API surface | 同「必要な能力」 | 完全な session abstraction は非目標 |
| SRC-BRK-008 | provider-neutral boundary と provider-specific adapter を分離する | architecture constraint | 同「確定している方針」 | Control UI / provider の将来交換余地 |
| SRC-BRK-009 | provider の接続方式を rich protocol / ACP / CLI の一種へ固定しない | extensibility | 同「確定している方針」 | ACP は v0 必須ではない |
| SRC-BRK-010 | Completion Notification / Runtime / Spool / Inbox を Broker の umbrella runtime にしない | non-goal | 同「確定している方針」 | event / notification plane として再利用 |
| SRC-BRK-011 | 他 provider を Codex と偽装せず、observed fact と reported result を区別する | invariant / negative | 同「前提・再検証事項」 | schema evolution は後続設計対象 |
| SRC-BRK-012 | Operational v0 は本物の開発 Issue で end-to-end 利用可能である | acceptance | 同「Operational v0の目的」 | process 起動と ID 返却だけでは不足 |
| SRC-BRK-013 | worktree manager、共通 resume、waiting 検出、result 自動検出、usage/cost、自動選択、dependency orchestration、retry、ACP は v0 必須外 | defer / non-goal | 同「自動化を必須としない事項」 | 手動経路を許容 |
| SRC-BRK-014 | 最初に正式対応する worker はControl UI自身とは異なるproviderから実能力を証拠付きで選ぶ | capability gate | Goal Context「前提・再検証事項」「意図的に後続設計へ残している事項」およびreview | Copilot CLI / OpenCode等が候補だが作業仮説を確定扱いしない |
| SRC-BRK-015 | first usable vertical sliceが成立した時点から本物の低リスクIssueで利用し、残りのhardeningと並行して運用知見を得る | implementation order | Goal Context「v0の開発方法についての方針」およびreview | final completion evidenceとは別のearly operational gate |
| SRC-BRK-016 | Issue #70のstandalone Copilot completion source adapterをBroker v0のcompletion条件に含めない | scope boundary | Goal Context「Issue #70との統合・分割は後続設計」およびreview | provider-neutral schema / Inbox evolutionは重複実装せず調整 |

## Behavior axes

| Axis ID | Axis | Relevant values | Why behavior changes | Notes |
| --- | --- | --- | --- | --- |
| AX-BRK-001 | run lifecycle | accepted / running / terminal / cancelled | 許可される操作と observed status が変わる | 不正な後戻りを禁止 |
| AX-BRK-002 | worker exit | zero / nonzero / launch failure / forced cancel | observed fact が変わる | semantic success は別 field |
| AX-BRK-003 | process continuity | Broker 稼働中 / facade 再起動 / Broker 再起動 | durable recovery の要否が変わる | memory-only を禁止 |
| AX-BRK-004 | provider capability | eligible / unsupported / unavailable | run admission が変わる | unsupported を成功扱いしない |
| AX-BRK-005 | output | separated stdout/stderr / merged console or PTY output / structured output / empty | providerから取得可能なexecution output / diagnosticsの形が変わる | stream分離非対応だけでproviderをunsupportedにしない |
| AX-BRK-006 | terminal notification | publish success / publish failure / duplicate attempt | Inbox 可視性と fail-open 記録が変わる | Broker result 自体は保持 |
| AX-BRK-007 | cancel timing | before launch / running / already terminal | cancel result が変わる | terminal run を巻き戻さない |
| AX-BRK-008 | request validity | valid / unknown provider / invalid cwd / unsafe or missing input | admission 結果が変わる | worker を起動しない |

## Case matrix

| Case ID | Source IDs | Input conditions / preconditions | Expected observable behavior | Negative expectation | Status |
| --- | --- | --- | --- | --- | --- |
| CASE-BRK-001 | SRC-BRK-001,002,007 | eligible provider、存在する working directory、prompt を指定する | `start_run` は durable run identity を返し、親 turn が worker 終了まで占有されずに戻る | 同期 wait を唯一の利用経路にしない | Defined |
| CASE-BRK-002 | SRC-BRK-003,007 | accepted/running run がある | 状態取得と一覧で同じ run identity、provider、cwd、timestamps、observed state を取得できる | process-local handle だけを authority にしない | Defined |
| CASE-BRK-003 | SRC-BRK-003,004 | facade または Broker の再起動後に既存 run を参照する | durable metadata と保存済み output を同じ identity で再取得できる | 再起動で履歴を消失・別 run 化しない | Defined |
| CASE-BRK-004 | SRC-BRK-004,005,011 | worker が exit 0 で終了する | terminal observed fact、exit code、providerから取得可能なexecution output / diagnostics、agent-reported resultの有無を区別して保存する | exit 0 をIssueの意味的完全成功と断定せず、merged outputをstdout/stderrへ捏造分離しない | Defined |
| CASE-BRK-005 | SRC-BRK-004,005 | worker が nonzero または launch failure になる | failure 種別と、providerから取得可能な diagnostics / execution outputを保存し取得できる | runを正常終了と偽装せず、取得不能なstream identityを捏造しない | Defined |
| CASE-BRK-006 | SRC-BRK-005,007 | running run を cancel する | bounded な cancel request 結果と最終 observed state を記録する | cancel 受付だけで process 停止済みと断定しない | Defined |
| CASE-BRK-007 | SRC-BRK-005,007 | terminal run を cancel する | terminal state を維持し、既終了であることを返す | terminal state を cancelled へ巻き戻さない | Defined |
| CASE-BRK-008 | SRC-BRK-006,010 | run が terminal になる | provider-neutral terminal event が共通 notification plane に渡り、Local Inbox 等で run と結果参照先を識別できる | 他 provider を Codex callback と偽装しない | Defined |
| CASE-BRK-009 | SRC-BRK-003,006 | notification publish が失敗する | terminal run と output は durable に残り、通知失敗を診断可能に記録する | notification failure で run result を消さない | Defined |
| CASE-BRK-010 | SRC-BRK-003,006 | 同じ terminal event の publish が再試行・再観測される | stable event identity により重複表示を抑止できる契約を保つ | 同じ終了を別 run として偽装しない | Defined |
| CASE-BRK-011 | SRC-BRK-008,009,014 | Control UIであるCodex Appとは異なるproviderがcapability gateを満たす | v0対応のnon-Control-UI providerと接続方式がevidenceと共に登録され、同じBroker surfaceから実行できる | Codex App→Codex CLIだけ、または未確認の作業仮説だけで正式対応を宣言しない | Defined |
| CASE-BRK-012 | SRC-BRK-001,007,014 | unknown/unsupported provider、invalid cwd、missing prompt を指定する | request は worker 起動前に拒否され、理由が返る | fallback provider を黙って起動しない | Defined |
| CASE-BRK-013 | SRC-BRK-008,009 | provider 固有 output / session identity が得られる | adapter-owned data と provider-neutral run fields を区別して保持する | provider 固有 field を共通 field の意味として流用しない | Defined |
| CASE-BRK-014 | SRC-BRK-001,012,014 | 実際のCodex Appからproduction integrationを通して本物の開発Issueをnon-Control-UI providerへ委譲する | start、run ID受領、親turnの非同期復帰、terminal notification、同じrunのstate / output回収、次行動の判断まで一連で実行できる | MCPテストクライアント、Codex CLI worker、fixture-only / fake-onlyだけでv0完了としない | Defined |
| CASE-BRK-015 | SRC-BRK-013 | resume、waiting 検出、PR URL 自動検出、usage/cost、自動選択等を要求しない初回 run | 手動コマンド、ログ確認、copy/paste を含む bounded fallback を文書化して利用できる | 非必須機能を v0 の completion blocker にしない | DeferredWithSource |
| CASE-BRK-016 | SRC-BRK-012,015 | production vertical sliceがstart→durable output→notification→Codex App result retrievalまで初めて通る | final hardening完了前でも低リスクな本物Issueのearly operational trialを開始し、run ID、結果、摩擦、残件をevidenceとして記録する | cancel/restart/docsの全hardening完了まで実運用開始を遅らせず、trial成功だけでformal v0 completeとしない | Defined |

## Derived invariants

| Invariant ID | Description | Covered Case IDs | Notes |
| --- | --- | --- | --- |
| INV-BRK-001 | run identity は start から terminal、notification、result retrieval まで不変 | 001-010,014 | provider session identity とは別 authority |
| INV-BRK-002 | observed process fact と agent-reported semantic result を混同しない | 004,005,008,014 | UI 表示と永続 schema の両方で維持 |
| INV-BRK-003 | terminal state は単調であり cancel/retry で過去へ戻らない | 004-007,010 | exact state machine は downstream contract |
| INV-BRK-004 | notification は共通 plane だが Broker durable state の authority ではない | 008-010 | publish failure は診断対象 |
| INV-BRK-005 | provider-neutral surface は provider 固有 capability を偽装しない | 011-013 | unsupported operation は明示拒否 |
| INV-BRK-006 | fake-only / process-start-only evidence はearly trialまたはOperational v0完了証拠にならない | 014,016 | 実Codex Appとnon-Control-UI production workerが必要 |
| INV-BRK-007 | early operational trialはformal completionより先に行うが、残りのFR / ACを免除しない | 014,016 | trial evidenceとfinal completion evidenceを分離 |

## Excluded combinations / non-goals

| Exclusion ID | Condition / behavior | Source or reason | Reopen condition |
| --- | --- | --- | --- |
| EX-BRK-001 | Broker 自身による完全な worktree lifecycle 管理 | SRC-BRK-013 | 実運用で主要摩擦になった後続要求 |
| EX-BRK-002 | 全 provider 共通 resume / question-wait protocol | SRC-BRK-013 | adapter capability と運用証拠が揃った後続設計 |
| EX-BRK-003 | provider 自動選択、usage/cost 最適化、dependency orchestration、自動 retry | SRC-BRK-013 | v0 運用計測に基づく優先付け後 |
| EX-BRK-004 | ACP 対応と複数 Control UI 対応 | SRC-BRK-009,013 | CLI adapter の制約または client 追加要求が実測された後 |
| EX-BRK-005 | Completion Notification package の generic orchestrator 化 | SRC-BRK-010 | Goal Context の方針変更が明示された場合のみ |
| EX-BRK-006 | Issue #70のstandalone Copilot completion source adapter完成 | SRC-BRK-016 | Broker外で直接起動したCopilotをInboxへ流す後続scopeとして扱う。共有schema/Inbox変更は調整する |

## Unresolved requirement-elaboration items

| Item ID | Source IDs | Missing decision / ambiguity | Blocking? | Required decision |
| --- | --- | --- | --- | --- |
| URI-BRK-001 | SRC-BRK-014 | 最初の正式 provider と接続方式 | No（RiskTriage までは非blocking） | implementation contract で capability evidence gate を満たす最小1 providerを選択し、満たさなければ実装前に停止 |
| URI-BRK-002 | SRC-BRK-003,011 | durable store と provider-neutral terminal event の exact schema | No（Plan behavior は確定） | implementation / runtime contractでauthority、compatibility、atomicityを確定 |
| URI-BRK-003 | SRC-BRK-001,002 | Codex App facade と長寿命 Broker の exact local transport / startup | No（Plan behavior は確定） | implementation contractでproduction addressとlifecycleを確定 |

## Handoff Packet

- Profile used: black-box-behavior-spec-kernel
- Behavior spec artifact: `plans/goal-context-multi-agent-execution-broker-operational-v0-black-box-behavior-spec.md`
- Source artifacts: `plans/goal-context-multi-agent-execution-broker-operational-v0.md`
- Case IDs: `CASE-BRK-001`〜`CASE-BRK-016`
- Files inspected: source Goal Context、`docs/goal-context-local-spool-winui-inbox.md`、`scripts/codex-notification-runtime/local-spool-interface.md`
- Files intentionally not inspected: provider CLI implementation全体、network protocol、UI production code。black-box behavior確定に不要なため。
- Decisions made: Operational v0のcompletion unitをstart→durable observation→terminal notification→result retrieval→next actionとした。最初のworkerをnon-Control-UI providerとし、実Codex App経路を必須化した。first usable vertical slice後にearly operational trialを行い、formal completionとは分離した。provider選定、store、transportはdownstream evidence-backed contract decisionとした。
- Excluded combinations: `EX-BRK-001`〜`EX-BRK-006`
- NeedsHumanDecision: なし。`URI-BRK-001`〜`003` は source-backed evidence gateへ委譲でき、RiskTriageをblockしない。
- Do not redo unless new evidence appears: Case matrix、invariants、v0 non-goals。
- Remaining work: Plan FR / AC へ全 Case を mappingする。
- Recommended next step: `plan-kernel.agent.md`
