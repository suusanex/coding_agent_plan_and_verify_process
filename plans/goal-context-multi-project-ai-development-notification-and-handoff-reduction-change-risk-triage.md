# Change Risk Triage

## Plan readiness check

| Check | Result | Notes |
| --- | --- | --- |
| Expansion decision exists? | Yes | `Expansion required: Yes`。 |
| Behavior spec exists when required? | Yes | `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`。 |
| Relevant source requirements have Case IDs? | Yes | `NTF-001`〜`NTF-008`、`REV-001`〜`REV-013`、`SCP-001`〜`SCP-003`。 |
| Relevant Case IDs are mapped to FR / AC or explicit disposition? | Yes | 親PlanのCase-to-Plan mappingに全Caseがある。 |
| Negative expectations are represented? | Yes | Decorator不要、thread探索不要、notification spam禁止、reviewer write禁止、fixed two-task handoff禁止、round 2以降のcode review禁止等。 |
| Blocking requirement ambiguity remains? | No | `URE-001`は期待behaviorではなく実機verification項目。 |
| Plan readiness status | ReadyForRiskTriage | source-to-case-to-Plan traceabilityが成立している。 |
| Documentation level | standard | separate behavior、architecture、contract、verification artifactが必要。 |

## 推奨プロファイル

`full-coverage`

## 理由

readyな親Planは、user-level Codex configuration、cross-process notification delivery、Windows provider、GitHub review取得、複数read-only reviewer subagent、親agentによるwrite、3roundの再review、terminal resultからの通知導線をまたぐ。通知だけ、またはreview flowだけを個別に変更しても、通常promptからterminal通知へ至る入口、同じ親threadのwrite ownership、review resultと通知linkの接続が不整合なら利用者の手動引き継ぎは残る。

実装実現性も、公開`notify` payloadに親／subagent識別fieldがないこと、既存packageが固定二task cycle managerをauthorityにしていること、既存collector / reviewer profileをsame-parent orchestrationへ接続するaddressが未確定であることから`Present / Unclear`である。単一`contract-kernel`または`standard-slice`へ押し込むより、共有architecture semanticsを確定してから、通知基盤、review orchestration、配布・移行を最小有用sliceへ分ける必要がある。

## High-risk boundaries

| Boundary | Producer | Consumer | Mechanism | Risk type |
| --- | --- | --- | --- | --- |
| `BND-001` | Codex `agent-turn-complete` callback | `codex-notification-runtime` | user-level `notify` argvへJSON引数 | callback schema、parent/subagent classification、terminal targeting |
| `BND-002` | `codex-notification-runtime` | Windows notification provider / chained notify | event JSON stdin、元callback JSON argv | fail-open、timeout、duplicate delivery、deep-link安全性 |
| `BND-003` | notification installer | user-level Codex configとinstalled runtime | publish、runtime-config、top-level TOML `notify` replacement | startup wiring、既存notify保持、self-wrap、rollback |
| `BND-004` | same-parent review Skill / 親agent | GitHub review context collector | repository / PR / headを使うCLI・GitHub API取得 | auth、Ready PR identity、external review completeness |
| `BND-005` | 親agent | code reviewer / purpose reviewer subagents | read-only agent spawnとresult return | reviewer independence、read-only enforcement、raw output traceability |
| `BND-006` | reviewer outputs | 親agent remediation loop | finding synthesis、parent-owned source edits、test execution | finding identity、write ownership、同じcontextの維持 |
| `BND-007` | 修正済みhead / diff | 次round purpose reviewer | purpose-only spawn、round counter、terminal decision | stale review、最大3round、human stop |
| `BND-008` | review/remediation terminal result | notification runtime | terminal assistant messageまたは安全なresult metadata | thread / PR deep link、generic callbackとの互換性 |
| `BND-009` | APM package / sync helper | 利用者のCodex installation | manifest install、profile配置、validation | package completeness、legacy fixed-two-task contract残存 |

## 対象とする runtime contracts

| Contract ID | Boundary | What is at risk | Why selected | Triage status | Next action |
| --- | --- | --- | --- | --- | --- |
| `RC-001` | `BND-001` + `BND-002` | markerなしcallbackの通知化、parent-centric delivery、thread/result links、dedup、fail-open | 常時通知という第一のuser-visible outcomeを直接所有する。 | Deferred | `architecture-slice-readiness.agent.md`でcallback authorityとgeneric/enriched event境界のcompletenessを判定する。 |
| `RC-002` | `BND-003` + `BND-009` | 一度のAPM導入、user config wiring、既存notify chain、runtime/package source of truth | 日常promptに手順を追加しないためのproduction entrypoint。 | Deferred | `architecture-slice-readiness.agent.md`で配布・installation ownershipとlegacy package境界を判定する。 |
| `RC-003` | `BND-004` + `BND-005` | Ready PR identity、三系統round-1 review、read-only reviewer、raw output | independent reviewとsame-parent UXの中核。 | Deferred | `architecture-slice-readiness.agent.md`でparent orchestrator / collector / reviewer responsibilityを判定する。 |
| `RC-004` | `BND-006` + `BND-007` | parent-only write、purpose-only再review、finding継承、最大3round、human stop | 手動messengerをなくしつつ過剰自動化しない状態遷移。 | Deferred | `architecture-slice-readiness.agent.md`でminimal durable stateとround authorityを判定する。 |
| `RC-005` | `BND-008` | review terminal verdictからthread / PR direct-link通知への接続 | notificationとreviewを別々に完成扱いするgapを防ぐ。 | Deferred | `architecture-slice-readiness.agent.md`でresult metadataのauthorityとfallbackを判定する。 |

## 選択されなかった候補 runtime contracts

| Contract ID | Boundary | Why not selected | Candidate status | Suggested next action |
| --- | --- | --- | --- | --- |
| `RC-C01` | notification runtime → 将来のntfy / Slack / Web UI provider | Goal ContextのMVPは既存Windows providerとdirect linkであり、provider追加は要求外。 | OutOfScopeForThisPass | 別Planでprovider portabilityを扱う。 |
| `RC-C02` | same-parent orchestrator → Adaptive Implementation executor | 初版は親agentが修正ownerで、Adaptive executor対応は明示的な後続課題。 | OutOfScopeForThisPass | 後続Planでexecutor差し替えcontractを定義する。 |
| `RC-C03` | notification event → persistent timeline storage | timelineは望ましい拡張だがMVP必須ではない。 | OutOfScopeForThisPass | direct-link MVP成立後に別sliceとして検討する。 |

## Risk trigger スキャン

| Risk trigger | Present / Absent / Unclear | Notes |
| --- | --- | --- |
| Cross-process or cross-service sequence | Present | Codex callback → runtime → Windows provider / chained notify、親agent → GitHub / reviewer subagents。 |
| Queue / event / webhook / background worker | Present | `agent-turn-complete` eventをcallback processで処理する。 |
| External API or SDK | Present | Codex callback/config contract、Windows App SDK、GitHub CLI/API。 |
| Authentication or authorization | Present | GitHub authとreviewer read-only permission。 |
| Durable state / retry / replay / idempotency | Present | callback dedup、review round / finding progression。 |
| Startup wiring / DI / configuration | Present | user-level `notify`設定、published runtime、APM-installed profiles。 |
| Production implementation split from test substitute | Present | fake provider / fake GitHub / deterministic fixtureと実Windows / GitHub / Codex subagentが分離する。 |
| Multiple runtime participants coordinating state | Present | Codex、runtime、provider、GitHub、親agent、reviewer subagents。 |
| Observable behavior spanning more than one component | Present | notification deep linkとreview/remediation terminal UXが複数componentをまたぐ。 |

## 実装実現性リスク

| Trigger | Status | Evidence | Required next step |
| --- | --- | --- | --- |
| Plan names a specific external SDK or API | Present | Codex `notify`、Windows App SDK、GitHub CLI/API。 | 各sliceでactual API / payload / failure contractを確認する。 |
| Plan names a package, release, binary artifact, or local lib folder | Present | APM package、published File-based Apps、installed runtime root。 | package manifest、publish、install/check addressをcontract化する。 |
| Plan names a namespace, type, method, extension method, provider ID, or config section | Present | top-level `notify`、`AppNotificationManager`、reviewer profiles。 | sourceと現行official contractからconcrete addressを固定する。 |
| Existing code contains a similar but different implementation path | Present | marker/envelope必須runtimeと固定二task multi-round managerが存在する。 | nearest-neighbor reuse範囲と廃止範囲をarchitectureで分離する。 |
| Implementation requires DI/startup/configuration wiring | Present | user config書換え、runtime config、APM profile sync。 | production entrypoint / rollback / checkをslice contractへ含める。 |
| The affected production address is not known from current evidence | Unclear | same-parent orchestratorのpackage pathとterminal metadata形式は未確定。 | Architecture ElaborationまたはLightweight baselineでauthorityを決める。 |
| Plan contains remaining work about API surface inspection or dependency confirmation | Present | `IR-001`〜`IR-005`。 | decomposition後のimplementation-contract-kernelへ引き継ぐ。 |

## 推奨する次の agent

Immediate next agentは`architecture-slice-readiness.agent.md`。

Required inputs:

- `docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md`
- `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md`
- `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- 本triage artifact
- 現行notification runtime、PR Review Remediation package、APM manifest / sync helperのbounded source

Minimum required downstream flow:

1. `architecture-slice-readiness.agent.md`
2. `NeedsArchitectureElaboration`なら`architecture-elaboration.agent.md`
3. `architecture-slice-readiness.agent.md`再実行
4. `ReadyForSliceDecomposition`または`ArchitectureNotRequired`の場合だけ`plan-slice-decomposition.agent.md`
5. 各sliceのPlan Coverage kernel chain、Adaptive implementation、slice verification
6. `cross-slice-verification-kernel.agent.md`
7. unresolvedがあれば`coverage-gap-triage.agent.md`
8. `residual-decision-gate.agent.md`

## Architecture-readiness triggers

| Trigger | Status | Evidence | Readiness checkで確認する事項 |
| --- | --- | --- | --- |
| multiple runtime participants / services / agents | Present | callback runtime、provider、GitHub、親agent、複数reviewer。 | participant責務とwrite authorityが一意か。 |
| durable state と derived observation の混在 | Present | callback dedup state、review round / finding observation。 | durable最小stateと再計算可能なreview resultを区別できるか。 |
| state / artifact / field authority の競合 | Present | 旧cycle JSON、review-plan、assistant terminal output、notification envelope。 | 新normal-pathで何がauthorityか、旧artifactをどう扱うか。 |
| cross-run / cross-process identity continuity | Present | thread ID、PR / head、turn、round、result URI。 | identityを利用者入力にせずagentが取得・検証できるか。 |
| async / retry / resume / replay / cleanup | Present | GitHub review待機、callback replay、最大3round。 | bounded wait、replay、terminal stop、cleanup semantics。 |
| lane / lock / reservation / shared capacity | Absent | single parent write ownerでparallel writeをしない。 | reviewer並列実行がwrite lockを必要としないこと。 |
| producer / consumer schema または temporal protocol | Present | callback JSON、notification event、reviewer output、round progression。 | schema / order / stale-head rejection。 |
| Control Plane / Execution Plane separation | Present | Skill orchestration / round decisionと親agent source edits。 | reviewer結果をcontrol inputにし、write executionを親へ限定すること。 |
| production entrypoint / wiring の共有 | Present | user-level notify、APM install / sync、root README。 | package source of truthとinstalled outputの対応。 |
| cross-slice invariant / forbidden state | Present | no decorator、no separate top-level task、reviewer read-only、code review once。 | 全sliceでnegative expectationを保持すること。 |

## full-coverage 時の分割方針

保持すべきparent-level acceptance conditionsは`AC-001`〜`AC-013`すべて。特に`AC-005`のreal subagent notification observation、`AC-006`のone-operation same-parent UX、`AC-010`のreviewer read-only / parent write ownership、`AC-011`のterminal notification接続はcross-slice verification対象とする。

想定slice候補:

1. 常時notification callbackとdeep-link delivery。
2. same-parent round-1 independent review orchestration。
3. parent-owned remediationとpurpose-only bounded rerun。
4. APM distribution、legacy normal-path removal、end-to-end docs / validation。

slice境界はimplementation mechanismの細片ではなく、単独でobservable valueを持つ最小有用単位にする。notification基盤を先に成立させ、same-parent review control plane、remediation loop、最後に配布・migrationとcross-slice evidenceを接続する。`RC-005`は単独sliceへせず、notificationとreviewのcross-slice invariantとして扱う。

## 今回の triage の対象外

- 2046行の既存cycle manager全実装、validator全行、fixture全内容はarchitecture responsibility判定に不要なため未読。
- Windows App SDKとGitHub APIの詳細method contractは各sliceのimplementation-contract / runtime-contractへ委ねる。
- notification timeline、追加provider、Adaptive executor対応は親Planの非目標。
- 実機Codex / GitHub / Windows smokeはverification phaseへ委ねる。

## Handoff Packet

- Profile used: triage-only
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Recommended process profile: full-coverage
- Source artifacts: Goal Context、親Plan、Black-box Behavior Spec、notification decision record、現行review Skill / manager surface、APM manifests、現行Codex Manual Notifications / Subagents。
- Selected contracts / IDs: `RC-001`〜`RC-005`（parent-level candidates）
- Files inspected: 親Plan / behavior specのHandoffに記録されたbounded filesと、current package manifest。
- Files intentionally not inspected: unrelated packages、historical plans、full validator / fixture / CI logs、external live state。
- Decisions made: readyなPlanはstrongly interconnectedであり`full-coverage`。Immediate nextはArchitecture Slice Readinessで、Full autonomous flowへは接続しない。
- Implementation realization risk summary: `Present / Unclear`。外部API、config wiring、nearest-neighbor old path、unknown same-parent addressがある。
- Do not redo unless new evidence appears: notification / review / distributionを一つのimplementation passへまとめない。Decorator必須とfixed two-task handoffをnormal-path authorityにしない。
- Remaining work: shared architecture semantics、legacy boundary、same-parent orchestration address、terminal metadata authorityをreadiness gateで判定する。
- Recommended next step: `architecture-slice-readiness.agent.md`へ上記artifactsと`RC-001`〜`RC-005`を渡す。
- Required downstream guardrails: 各selected contractでruntime contract identification、participant/boundary mapping、test point mapping、stub/fake/in-memory usage check、production implementation binding、production wiring/entrypoint verification、未完了項目のexplicit unresolved statusを保持する。
- Full-coverage handling: `architecture-slice-readiness.agent.md`へ進める。readiness verdictなしでdecompositionへ進めず、Full autonomous Plan-first flowへも接続しない。
