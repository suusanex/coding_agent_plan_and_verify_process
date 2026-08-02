# Change Risk Triage

## Plan readiness check

| Check | Result | Notes |
| --- | --- | --- |
| Expansion decision exists? | Yes | Plan は `Expansion required: Yes`、`Inline behavior sketch sufficient: No`、separate Behavior Spec 必須を記録している。 |
| Behavior spec exists when required? | Yes | `plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md` が存在する。 |
| Relevant source requirements have Case IDs? | Yes | current producer scope と source-backed defer / exclusion は `CASE-76-001`〜`CASE-76-029` に展開済み。 |
| Relevant Case IDs are mapped to FR / AC or explicit disposition? | Yes | 全29件が `FR-001`〜`FR-010` / `AC-001`〜`AC-012`、`DeferredWithSource`、または `OutOfScopeWithSource` に対応し、`UnmappedBlocking`: 0。 |
| Negative expectations are represented? | Yes | callback fan-out 禁止、consumer semantics 非混入、partial / corrupt final file 非公開、payload equality による誤 dedupe 禁止、`PENDING` 非永続化等を Case / invariant / AC が保持する。 |
| Blocking requirement ambiguity remains? | No | `URE-001`〜`URE-010` は source-backed defer または non-blocking implementation-realization decision。`NeedsHumanDecision`: 0。 |
| Plan readiness status | ReadyForRiskTriage | risk / profile 分類へ進める。 |
| Documentation level | standard | durable state、並行 replay、atomic publish、failure、legacy wiring を separate guardrail artifacts で追跡する。 |

## 推奨プロファイル

`standard-slice`

## 理由

current scope は consumer / Inbox / toast / retention / forwarding を除外した producer-only Local Spool であり、主たる runtime sequence は Codex callback → `codex-notification-runtime` → Local Spool provider → local filesystem の1本に bounded 化できる。このため、複数の独立 slice へ分解する `full-coverage` は過大である。

一方、現行 production path は `config.toml` の `notify` から runtime を起動し、runtime が `runtime-config.json` の複数形 `providers` から provider process を選び、`notification_status: PENDING` を含む current completion event を stdin へ渡す。installer は `windows-app-notification-provider.exe` を発行し、既存 notify を `chained_notify` として保持する。validator の runtime delivery evidence は fake provider を使い、installed production Local Spool provider、Spool path、atomic write、single-provider migration はまだ存在しない。したがって、`IR-001`〜`IR-006` は implementation-realization risk `Present` であり、`implementation-contract-kernel.agent.md` を先行させたうえで runtime contract、test point、production binding / wiring まで検証する1回の bounded parent Plan pass が必要である。

## High-risk boundaries

| Boundary | Producer | Consumer | Mechanism | Risk type |
| --- | --- | --- | --- | --- |
| `B-001` | Codex `notify` callback | installed `codex-notification-runtime.exe` | user-level `config.toml` の top-level `notify` argv と raw callback JSON | startup / entrypoint wiring、fail-open |
| `B-002` | `codex-notification-runtime` の normalized `CompletionEvent` | 新規 Local Spool provider process | `runtime-config.json` の provider argv、stdin JSON、bounded process timeout / exit code | schema projection、single-provider selection、timeout / failure |
| `B-003` | Local Spool provider process | Windows local filesystem Spool directory | same-directory temp write + flush + atomic rename、`source_event_id` 由来 identity / filename | durable state、replay / race / idempotency、partial publish |
| `B-004` | `install-codex-notification-runtime-local` | Codex config、installed runtime config / binaries | staged publish、`config.toml` / `runtime-config.json` 更新、backup / rollback | production binding、legacy migration、single-provider wiring |
| `B-005` | canonical `scripts/codex-notification-runtime` assets | APM package mirror / installed package assets | checked file mirror、package validator、CI entrypoints | distribution binding、mirror drift、fake-only completion |

## 対象とする runtime contracts

| Contract ID | Boundary | What is at risk | Why selected | Triage status | Next action |
| --- | --- | --- | --- | --- | --- |
| `RC-001` | `codex-notification-runtime` → Local Spool provider process | normalized event から `spool-item-v1` 10-field JSON への projection、`notification_status` 非永続化、provider exit / timeout と callback fail-open | current provider input schema は `notification_status` を必須とし、Local Spool provider の concrete production address と failure contract が未確定 | `Deferred` | `implementation-contract-kernel.agent.md` で concrete provider / schema / config / exit address を確定し、その後 `runtime-contract-kernel.agent.md` で stdin・timeout・fail-open boundary を定義する。 |
| `RC-002` | Local Spool provider process → Windows filesystem Spool | default path、directory creation、1 event 1 final JSON、same-ID replay / parallel race、distinct-ID collision、safe UTC-first filename、temp + flush + atomic rename | durable postcondition と同一 ID の1 final itemは production filesystem behavior であり、fake provider output や source-structure test だけでは証明できない | `Deferred` | `implementation-contract-kernel.agent.md` で path / naming / collision / failure realization を確定し、runtime contract と test design で atomicity・idempotency・diagnostic の観測点を定義する。 |
| `RC-003` | installer / configuration → installed callback runtime + Local Spool provider | Local Spool の単一 provider 設定、旧 Windows provider / `chained_notify` の最小互換、update / rollback、canonical / APM mirror、real entrypoint binding | current installer は Windows App Notification provider を発行して1 providerとして設定し、旧 notify chain を保存する。new provider binary / schema / Spool path と installed callback の production wiring が未確定 | `Deferred` | `implementation-contract-kernel.agent.md` で migration と production addresses を確定し、test design / verification で installed config、binary、mirror、callback→filesystem postconditionを確認する。 |

## 選択されなかった候補 runtime contracts

| Contract ID | Boundary | Why not selected | Candidate status | Suggested next action |
| --- | --- | --- | --- | --- |
| `RC-004` | Spool item → consumer claim / ack / retry | consumer は `NG-001`, `NG-009` および `CASE-76-014`, `CASE-76-015` で source-backed defer | `OutOfScopeForThisPass` | consumer lifecycle を定義する後続 Issue で再 triage する。 |
| `RC-005` | consumer → Inbox UI / state / search / toast / retention | `NG-002`〜`NG-005` と対応 Case が current producer completion から明示除外 | `OutOfScopeForThisPass` | Inbox / notification / lifecycle の後続 Plan で扱う。 |
| `RC-006` | Spool → Webhook / Slack / cloud / multi-device forwarder | callback fan-out を禁止し、forwarding / sync は `NG-006`, `NG-007` で後続へ defer | `OutOfScopeForThisPass` | 独立 forwarder requirement が承認された場合に選択する。 |

## Risk trigger スキャン

| Risk trigger | Present / Absent / Unclear | Notes |
| --- | --- | --- |
| Cross-process or cross-service sequence | Present | Codex callback → runtime process → Local Spool provider process → filesystem。consumer は含めない。 |
| Queue / event / webhook / background worker | Present | completion / stop event を append-only Local Spool へ enqueue する producer boundary。Webhook / worker は対象外。 |
| External API or SDK | Absent | new external service / SDK は要求されず、Windows local filesystem と既存 process invocation が対象。 |
| Authentication or authorization | Absent | new auth behavior は要求されない。local directory ACL / writeability は `IR-002` の production address 確認として扱う。 |
| Durable state / retry / replay / idempotency | Present | distinct events、same-ID replay / race、atomic publish、write failure が中心要件。 |
| Startup wiring / DI / configuration | Present | `config.toml` notify、`runtime-config.json` provider、installed binary、default Spool path、installer / rollback が関与する。 |
| Production implementation split from test substitute | Present | current runtime validator は fake provider を用い、Local Spool production provider と installed callback→filesystem evidence は未実装。 |
| Multiple runtime participants coordinating state | Present | Codex process、notification runtime、provider process、filesystem が `source_event_id` と delivery / durable state をまたいで関与する。 |
| Observable behavior spanning more than one component | Present | normalization、stdin delivery、filesystem publish、installer / package mirror / entrypoint wiringにまたがる。 |

## 実装実現性リスク

| Trigger | Status | Evidence | Required next step |
| --- | --- | --- | --- |
| Plan names a specific external SDK or API | Absent | external service SDK はない。filesystem / process API の exact realization は別行で扱う。 | 追加 branch 不要。 |
| Plan names a package, release, binary artifact, or local lib folder | Present | installed runtime / provider binaries、`apm-packages/completion-notification-decorator` の checked asset mirror、schema asset を production surface とする。 | canonical / mirror / installed binary addresses を implementation contract に固定する。 |
| Plan names a namespace, type, method, extension method, provider ID, or config section | Present | current `RuntimeConfig.Providers`, `ProviderSpec`, `ChainedNotify`、top-level `notify`、event / envelope schema と新規 `spool-item-v1` の関係がある。 | config shape、provider ID / executable、stdin / persisted schema boundary を確定する。 |
| Existing code contains a similar but different implementation path | Present | `windows-app-notification-provider.cs`、複数 provider fallback、`chained_notify`、fake provider validation が存在するが producer-only Local Spool とは意味が異なる。 | nearest-neighbor substitution を避け、single-provider migration と legacy disposition を明示する。 |
| Implementation requires DI/startup/configuration wiring | Present | installer が `config.toml`、`runtime-config.json`、staged binaries、backup / rollback を管理する。 | installed entrypoint と single Local Spool provider wiring を implementation contract に固定する。 |
| The affected production address is not known from current evidence | Present | default Spool path、新 provider / schema file 名、installed path、atomic failure diagnostic、mirror additions が未確定。 | `IR-001`〜`IR-006` を implementation-contract-kernel で解消または explicit unresolved にする。 |
| Plan contains remaining work about API surface inspection or dependency confirmation | Present | Plan は `IR-001`〜`IR-006` を implementation authorization 前の Blocking として handoff している。 | runtime-contract-kernel へ直行せず bounded implementation-contract branch を先行する。 |

## 推奨する次の agent

Immediate next agent は `implementation-contract-kernel.agent.md`。

Required inputs は live Issue #76（updated `2026-08-01T11:52:56Z`）、bounded Plan、Behavior Spec、`IR-001`〜`IR-006`、selected `RC-001`〜`RC-003`、および本 triage の concrete boundary / current production address evidenceである。implementation contract は product scope を consumer / Inbox へ広げず、default path、schema projection、naming / collision、atomic failure / provider exit、single-provider migration、legacy installer / rollback、APM mirror / installed wiringを確定または explicit unresolved にする。

Minimum required downstream flow:

1. `implementation-contract-kernel.agent.md`
2. `runtime-contract-kernel.agent.md` — `RC-001`〜`RC-003` の participant / boundary、runtime postcondition、production binding を定義
3. `test-design-kernel.agent.md` — atomic / replay / parallel / failure / installer / mirror と fake-only completion 防止の test point を対応付け
4. `implementation-handoff-review.agent.md` — Parent Plan `FR-001`〜`FR-010`, `AC-001`〜`AC-012` と3 RC の coverage を確認
5. implementation authorization 後、`implementation_route: adaptive` に従い `high-implementation-starter.agent.md` から bounded implementation を開始
6. `verification-kernel.agent.md` — production provider binding、installed callback / config / binary / filesystem wiring、final file postconditionを確認
7. unresolved があれば `coverage-gap-triage.agent.md` と必要な bounded FixNow、最後に `residual-decision-gate.agent.md`

各 selected contract で、runtime contract identification、participant / boundary mapping、test point mapping、stub / fake / mock / in-memory usage identification、production implementation binding、production wiring / entrypoint verification、未完了項目の explicit unresolved status の全 chain を保持する。

## Architecture-readiness triggers

該当なし。`full-coverage` は推奨しない。

## full-coverage 時の分割方針

該当なし。

## 今回の triage の対象外

- consumer、Inbox UI / state、toast、search / filter、retention、cleanup、forwarding、cloud / multi-device の source / code。Plan が明示 defer しており、producer risk classification に不要なため。
- implementation-internal な class / interface 分割、具体 algorithm、test seam の決定。`implementation-contract-kernel` と implementation phase の責務であるため。
- production code、tests、Plan、Behavior Spec の変更、および validator 実行。triage-only の stop condition を越えるため。
- repository 全体、他の plans / packages / workflows の broad scan。selected boundaries の分類に必要な current runtime/provider/installer/schema/validator/APM mirror のみを確認した。
- manual / real installed environment の実行。production binding / wiring は downstream verification の対象であり、本 triage では未検証のまま `Deferred` とした。

## Handoff Packet

- Profile used: triage-only
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Behavior spec artifact: `plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`
- Recommended process profile: `standard-slice`
- Source artifacts: live GitHub Issue #76（updated `2026-08-01T11:52:56Z`）、`plans/issue-76-codex-completion-local-spool-inbox-plan.md`、`plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`、`.agents/skills/plan-coverage-residual-flow/SKILL.md`、`.github/instructions/plan-coverage-shared.instructions.md`、`.github/agents/change-risk-triage.agent.md`
- Selected contracts / IDs: `RC-001`, `RC-002`, `RC-003`
- Files inspected: `scripts/codex-notification-runtime/codex-notification-runtime.cs`、`scripts/codex-notification-runtime/windows-app-notification-provider.cs`（provider input / model と既存 notification path の該当箇所）、`scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs`、`scripts/codex-notification-runtime/completion-notification-event-v1.schema.json`、`scripts/codex-notification-runtime/completion-notification-envelope-v1.schema.json`、`scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`（provider / dedupe / timeout / installer / rollback の該当箇所）、`apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1`（canonical mirror check の該当箇所）、APM runtime asset mirror 7 files（canonical との hash equality のみ確認）、`.github/workflows/validate-codex-notification-runtime.yml` と `.github/workflows/validate-completion-notification-decorator.yml`（validator entrypoint の参照箇所）
- Files intentionally not inspected: consumer / Inbox / toast / retention / forwarding component（current source scope 外）、他の plans / docs / packages / workflows（classification に不要）、runtime docs 本文と tests の全量（test design / implementation / verification phase の責務）
- Decisions made: Plan は ready。producer-only の1 sequence に bounded できるため `standard-slice` を選び、`full-coverage` は選ばない。3つの high-risk contract に process / schema、filesystem durability、installer / production wiring を集約した。implementation-realization risk は Present のため runtime-contract-kernel へ直行させない。
- Implementation realization risk summary: `Present`。新規 Local Spool provider / schema / default path、filename / collision / atomic failure、single-provider config、legacy chain / rollback、APM mirror / installed production address が未確定で、current production path は Windows App provider と fake provider validation に結び付いている。
- Do not redo unless new evidence appears: 全29 Case の Plan mapping、`NeedsHumanDecision`: 0、producer / consumer scope split、current runtime の `providers` / `chained_notify` / stdin / timeout / fail-open structure、current installer の Windows provider / backup / rollback structure、canonical 7 assetsとAPM mirrorの current hash一致。
- Remaining work: `IR-001`〜`IR-006` と `RC-001`〜`RC-003` は `Deferred`。implementation contract、runtime contract、test design、handoff review、production implementation、production binding / wiring verification、residual decision は未実施。implementation permission: No。close readiness: No。
- Recommended next step: `implementation-contract-kernel.agent.md` に Plan、Behavior Spec、本 triage、`IR-001`〜`IR-006`、`RC-001`〜`RC-003`、inspected production addresses を渡す。
- Required downstream guardrails: 各 selected contract について runtime contract identification、participant / boundary mapping、test point mapping、stub / fake / in-memory usage check、production implementation binding、production wiring / entrypoint verification、未完了項目の explicit unresolved status を保持する。
- Full-coverage handling: 該当なし。Full autonomous Plan-first flow へ接続しない。
