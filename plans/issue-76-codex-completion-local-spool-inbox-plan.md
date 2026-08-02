# Plan Kernel

## 目的

Codex の完了・停止 event を、callback から単一の Local Spool provider へ渡し、1 event 1 JSON file の append-only な producer-side boundary として安全に保存する。

異なる event の独立保持、同一 `source_event_id` の冪等性、完成 item の atomic な公開、versioned JSON contract、通常の editor からの閲覧、provider failure / timeout 時の fail-open、installer / configuration からの単一 provider 設定までを今回の完成単位とする。

## 非目標

- `NG-001`: Spool consumer、claim / ack / ownership / retry、consumer の常駐・自動起動・再処理を実装しない。
- `NG-002`: 正式な Inbox UI、未処理・処理済み・保留・再表示・archive 等の利用者向け state と操作を実装しない。
- `NG-003`: Inbox の search / filter / 固有 sort を実装しない。
- `NG-004`: retention、容量管理、自動削除、cleanup、delete、archive、recovery を実装しない。
- `NG-005`: 補助 toast、集約通知、Windows 通知履歴を正式 Inbox とする behavior を実装しない。
- `NG-006`: Webhook、Slack、その他外部サービスへの forwarding を callback の追加 provider として実装しない。
- `NG-007`: 複数 PC、smartphone、cloud sync を扱わない。
- `NG-008`: Goal Context 生成、目的 review、PR review / remediation cycle を再設計しない。
- `NG-009`: Local Spool を claim、ack、処理済み遷移、automatic cleanup を持つ完成済み message queue として扱わない。

## 機能要件

- `FR-001` Local Spool の完成 item は `spool-item-v1` 相当の versioned JSON contract とし、少なくとも `schema_version`、`source`、`source_event_id`、`primary_process`、`observed_status`、`occurred_at`、`title`、`repository`、`resume_uri`、`result_uri` を保持する。JSON 本文を正本とし、transient な `notification_status: PENDING` を永続 state として保存しない。
- `FR-002` Local Spool は 1 event につき 1 個の完成 JSON file を保存する append-only boundary とする。異なる `source_event_id` の event は、近接・並行投入または payload 内容の一致にかかわらず、互いに上書き・黙示集約せず独立して保持する。
- `FR-003` 同一 `source_event_id` の逐次再送または並行投入は、完成 file を増殖・破損させず、同じ 1 個の最終 item として冪等に扱う。
- `FR-004` provider は完成 file と同じ directory の一時 file へ JSON を書き、flush 後に完成 file 名へ atomic rename する。rename 成功前の内容を完成 item として公開せず、write / flush / rename failure 時に partial または invalid な完成 file を残さない。
- `FR-005` 完成 file 名は Windows-safe とし、UTC 時刻を先頭に置いて file 一覧を時系列に並べられ、status、repository の識別要素、`source_event_id` 由来の短い hash を含める。file 名は識別用 projection に限定し、contract の完全な意味は JSON 本文から読み取る。
- `FR-006` 利用者は専用 consumer がなくても、生成された Spool folder を VS Code 等の通常の editor で開き、各完成 item と JSON の後続処理に必要な情報を個別に確認できる。
- `FR-007` Codex callback から直接呼ぶ provider は Local Spool 一種類とし、callback の責務を enqueue の結果までに限定する。Local Spool と toast / Webhook 等への複数 provider fan-out、consumer / Inbox / notification 処理は callback 内で行わない。
- `FR-008` Local Spool provider の failure または callback timeout が発生しても、既存の fail-open 境界を維持して Codex の完了経路へ制御を返す。failure を成功と偽装せず、無制限に待機しない。
- `FR-009` installer / configuration から、Local Spool を Codex callback の単一 provider として設定できるようにする。
- `FR-010` 現行の completion event normalization、`source_event_id`、provider stdin、dedupe / log、installer / update / rollback の境界を current producer contract と整合させる。exact な互換方式は implementation-realization residual として downstream で確定し、consumer / Inbox scope へ拡張しない。

## 受け入れ条件

- `AC-001` (`FR-001`, `FR-002`, `FR-007`) 一意な valid completion / stop event の保存が成功すると、versioned 10-field contract を満たす schema-valid な完成 JSON file が 1 個生成され、`notification_status: PENDING` は永続 spool state として含まれない。
- `AC-002` (`FR-001`) event に `resume_uri` がある場合は保存され、`result_uri` が利用可能な場合はそれも保存される。後続処理は JSON から該当 result または元 Codex thread への導線を構成できる。
- `AC-003` (`FR-002`) 異なる `source_event_id` の複数 event を近い時刻または並行に投入すると、すべてが独立した完成 JSON file として残る。payload が同じでも ID が異なる event は抑止されない。
- `AC-004` (`FR-003`, `FR-004`) 同一 `source_event_id` を逐次再送または並行投入すると、競合後も schema-valid な完成 item が 1 個だけ残り、増殖・破損・全欠落が起きない。
- `AC-005` (`FR-004`) write が一時 file への書込中、flush 後、atomic rename 前後で中断または失敗しても、rename 成功前の内容は完成 item として見えず、完成名で見える file は schema-valid な JSON である。
- `AC-006` (`FR-005`) status、repository、`source_event_id`、`occurred_at` を含む event の完成 file 名は Windows-safe で、UTC 時刻を先頭に一覧順を作り、status / repository の識別要素と source ID 由来の短い hash を含む。JSON の完全な意味を file 名から復元する必要はない。
- `AC-007` (`FR-006`) 複数の完成 item を含む生成済み Spool folder を通常の editor で開くと、利用者は file 一覧から各 item を個別に認識し、各 JSON の保存情報を読める。専用 consumer、Inbox UI、Windows toast 履歴は不要である。
- `AC-008` (`FR-007`) consumer が存在しない、停止中、更新中でも、callback は consumer の起動や Inbox 処理を代行せず、保存成功した完成 JSON は Spool に残る。Windows 通知履歴の状態は完成 item を削除・処理済み化しない。
- `AC-009` (`FR-008`) Local Spool provider failure または callback timeout 時、callback は既存の fail-open 境界に従い Codex の完了経路へ制御を返し、provider の無制限待機、Codex 完了の fail-closed、成功の偽装を行わない。
- `AC-010` (`FR-004`, `FR-008`) permission、容量、I/O、flush、rename 等による write failure 時、壊れた完成 JSON file は残らず、callback は fail-open を維持する。
- `AC-011` (`FR-007`, `FR-009`, `FR-010`) installer / configuration により Local Spool を callback の単一 provider として設定でき、旧 provider 導入済み環境でも exact minimal compatibility contract に従う observable な install / update / rollback 結果を検証できる。callback の複数 provider fan-outは維持しない。
- `AC-012` (`FR-001`, `FR-003`, `FR-010`) spool item の identity は `source_event_id` に基づき、永続 contract は `observed_status` を保持する。既存 provider input / log に現れ得る `notification_status: PENDING` を Inbox state または spool item authority と同一視しない。

## Black-box behavior coverage

- Expansion required: Yes
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`
- Plan readiness: ReadyForRiskTriage
- Expansion decision reason: durable state、replay / idempotency、並行 writer、atomic publish、failure / timeout、negative expectation、旧 runtime / installer 互換、consumer lifecycle の明示的 defer を case 単位で追跡する必要があるため separate Behavior Spec を使用する。更新済み artifact は current producer scope を `CASE-76-001`〜`CASE-76-029` へ展開済みである。
- Blocking requirement-elaboration items: なし。`URE-001`〜`URE-010` は current behavior で解消済み、source-backed defer、または non-blocking implementation-realization residual に分類されている。

### Source-to-Plan coverage summary

| Source IDs | Plan connection | Status |
| --- | --- | --- |
| `SRC-76-001`〜`SRC-76-004`, `SRC-76-011`〜`SRC-76-016`, `SRC-76-018` | `FR-001`〜`FR-009`; `AC-001`〜`AC-012` | `MappedToPlan` |
| `SRC-76-005`〜`SRC-76-007`, `SRC-76-017` | `FR-006`〜`FR-008`; `AC-007`〜`AC-010`; `NG-001`〜`NG-007`, `NG-009` | `MappedToPlan` / source-backed defer |
| `SRC-76-008`, `SRC-76-009`, `SRC-76-019` | `FR-009`, `FR-010`; `AC-011`, `AC-012`; `IR-001`〜`IR-006` | `MappedToPlan` / implementation-realization handoff |
| `SRC-76-010` | `NG-007`, `NG-008` | source-backed out-of-scope |

### Case-to-Plan mapping

| Case ID | Source IDs | FR / AC | Disposition | Notes |
| --- | --- | --- | --- | --- |
| `CASE-76-001` | `SRC-76-003`, `004`, `011`, `016`, `018` | `FR-001`, `FR-002`, `FR-007`; `AC-001` | `MappedToPlan` | 1 event 1 schema-valid JSON、10 field、single provider、`PENDING` 非永続化。 |
| `CASE-76-002` | `SRC-76-003`, `005`, `007`, `011`, `017` | `FR-007`; `AC-008` | `MappedToPlan` | consumer 非依存の producer output。consumer 本体は `NG-001`。 |
| `CASE-76-003` | `SRC-76-001`, `011`, `012`, `018` | `FR-002`; `AC-003` | `MappedToPlan` | 異なる ID の独立保持。 |
| `CASE-76-004` | `SRC-76-001`, `014`, `018` | `FR-006`; `AC-007` | `MappedToPlan` | 通常 editor からの folder / JSON 閲覧。 |
| `CASE-76-005` | `SRC-76-002`, `016`, `018` | `FR-001`; `AC-002` | `MappedToPlan` | navigation 情報の永続化。 |
| `CASE-76-006` | `SRC-76-006`, `017` | `NG-002`, `NG-005`, `NG-009` | `DeferredWithSource` | Inbox state / toast 操作 / 処理完了 semantics は後続。 |
| `CASE-76-007` | `SRC-76-004`, `005`, `007`, `017` | `FR-007`; `AC-008` | `MappedToPlan` | callback 責務は単一 Spool provider の保存まで。 |
| `CASE-76-008` | `SRC-76-001`, `006`, `011`, `014` | `FR-006`; `AC-007`, `AC-008` | `MappedToPlan` | toast history から独立した完成 file。 |
| `CASE-76-009` | `SRC-76-003`, `018`, `019` | `FR-008`; `AC-009` | `MappedToPlan` | exact budget / exit / diagnostic は `IR-004`。 |
| `CASE-76-010` | `SRC-76-003`, `013`, `018`, `019` | `FR-004`, `FR-008`; `AC-009`, `AC-010` | `MappedToPlan` | 壊れた完成 file を残さない。exact failure diagnostic は `IR-004`。 |
| `CASE-76-011` | `SRC-76-011`, `012`, `018` | `FR-003`; `AC-004` | `MappedToPlan` | 同一 ID の逐次 replay は 1 item。 |
| `CASE-76-012` | `SRC-76-012`, `013`, `018`, `019` | `FR-003`, `FR-004`; `AC-004` | `MappedToPlan` | 同一 ID の並行競合後も 1 valid item。diagnostic は `IR-003`。 |
| `CASE-76-013` | `SRC-76-001`, `011`, `012` | `FR-002`; `AC-003` | `MappedToPlan` | 同内容・異なる ID は独立 event。 |
| `CASE-76-014` | `SRC-76-005`, `017` | `NG-001`, `NG-009` | `DeferredWithSource` | consumer claim / ack / ownership / retry は後続。 |
| `CASE-76-015` | `SRC-76-005`, `017` | `NG-001`, `NG-009` | `DeferredWithSource` | consumer crash / restart / reprocessing は後続。 |
| `CASE-76-016` | `SRC-76-006`, `017` | `NG-002`, `NG-009` | `DeferredWithSource` | 利用者向け state transition は後続。 |
| `CASE-76-017` | `SRC-76-014`, `015`, `018`, `019` | `FR-005`; `AC-006` | `MappedToPlan` | exact sanitization は `IR-003`。 |
| `CASE-76-018` | `SRC-76-017` | `NG-003` | `DeferredWithSource` | 正式 Inbox の search / filter / sort は後続。 |
| `CASE-76-019` | `SRC-76-011`, `017` | `NG-004`, `NG-009` | `DeferredWithSource` | retention / capacity cleanup / deletion は後続。current boundary は append-only。 |
| `CASE-76-020` | `SRC-76-017` | `NG-004`, `NG-009` | `DeferredWithSource` | delete / archive / recovery は後続。 |
| `CASE-76-021` | `SRC-76-013`, `016`, `018`, `019` | `FR-004`; `AC-005`, `AC-010` | `MappedToPlan` | atomic publish と partial 非公開。exact exit は `IR-004`。 |
| `CASE-76-022` | `SRC-76-005`, `014`, `017` | `FR-006`; `AC-007`; `NG-001` | `DeferredWithSource` | current editor inspection は mapped。consumer UI / startup / reprocessing は後続。 |
| `CASE-76-023` | `SRC-76-006`, `017` | `NG-005` | `DeferredWithSource` | 補助 toast の有無・集約・操作は後続。callback fan-out は禁止。 |
| `CASE-76-024` | `SRC-76-004`, `008`, `019` | `FR-007`, `FR-010`; `AC-011` | `MappedToPlan` | legacy provider / chained notify の最小互換は `IR-005`。 |
| `CASE-76-025` | `SRC-76-008`, `012`, `016`, `019` | `FR-001`, `FR-003`, `FR-010`; `AC-012` | `MappedToPlan` | identity、`observed_status`、`PENDING` 非流用。 |
| `CASE-76-026` | `SRC-76-004`, `008`, `018`, `019` | `FR-007`, `FR-009`, `FR-010`; `AC-011` | `MappedToPlan` | installer / configuration の single-provider wiring。 |
| `CASE-76-027` | `SRC-76-004`, `017` | `NG-006` | `DeferredWithSource` | forwarding は将来の consumer / forwarder。callback から fan-out しない。 |
| `CASE-76-028` | `SRC-76-010`, `017` | `NG-007` | `DeferredWithSource` | multi-device / cloud は後続課題。 |
| `CASE-76-029` | `SRC-76-010` | `NG-008` | `OutOfScopeWithSource` | Goal Context / review workflow の再設計は Issue #76 の producer scope 外。 |

Mapping result: `CASE-76-001`〜`CASE-76-029` はすべて Plan FR / AC、`DeferredWithSource`、または `OutOfScopeWithSource` に分類済み。`UnmappedBlocking`: 0、`NeedsHumanDecision`: 0。

## 影響コンポーネント / モジュール

### 変更対象候補

- `scripts/codex-notification-runtime/codex-notification-runtime.cs`: callback normalization、single provider invocation、timeout / fail-open、既存 dedupe / log 境界。
- `scripts/codex-notification-runtime/` 配下の新規 Local Spool provider と `spool-item-v1` schema asset: 1 event 1 JSON、idempotency、atomic write、filename、persisted contract の実装 surface。exact file 名は implementation contract で確定する。
- `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs`: Local Spool path と単一 provider の install / configuration / update / rollback wiring。
- `scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`: producer behavior、failure / timeout、並行・replay、installer compatibility の validation surface。
- `scripts/codex-notification-runtime/decision-record.md`、`scripts/codex-notification-runtime/manual-verification.md`、`README.md`: producer-only responsibility、導入、Spool folder の確認方法、manual boundary。
- `apm-packages/completion-notification-decorator/.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/` と package validators: canonical runtime の checked mirror、package install contract。
- `.github/workflows/validate-codex-notification-runtime.yml`、`.github/workflows/validate-completion-notification-decorator.yml`: validator / package mirror の CI wiring が既存 entrypoint 変更で必要となる場合の更新候補。

### 読取・互換確認対象

- `scripts/codex-notification-runtime/completion-notification-event-v1.schema.json`: current normalized event field と persisted contract input の対応確認。
- `scripts/codex-notification-runtime/completion-notification-envelope-v1.schema.json`: callback-authoritative field と optional enrichment の境界確認。変更要否は implementation contract に従う。
- 既存 Windows App Notification provider、runtime config、installer backup / rollback behavior: producer single-provider への移行時に最小互換境界を確定するための参照対象。

### 変更しない component

- consumer / Inbox / toast / forwarding / retention / cloud sync の新規 component は今回作成しない。
- Goal Context / purpose review / PR review-remediation の production component は変更しない。

## 実装スコープ

実装 authorization 後の bounded surface は、(1) current completion event を versioned spool item へ投影する Local Spool provider、(2) distinct-event independence と同一 `source_event_id` idempotency、(3) same-directory temp + flush + atomic rename、(4) Windows-safe UTC-first filename、(5) editor-readable Spool folder / JSON、(6) callback の single-provider / timeout / fail-open、(7) installer / configuration と必要最小限の legacy compatibility、(8) canonical / APM mirror / docs / validator の同期である。

default path、exact sanitization、collision diagnostics、atomic failure exit、legacy installer compatibility は implementation-realization decision として downstream artifact で確定する。この Plan はそれらの方式を選ばず、`FR-001`〜`FR-010` と `AC-001`〜`AC-012` の observable boundary を source of truth とする。

## 既知の high-risk boundaries

詳細な contract analysis と final selection は `change-risk-triage.agent.md` に委ねる。

| Risk trigger | Present / Absent / Unclear | Boundary candidate |
| --- | --- | --- |
| Cross-process or cross-service sequence | Present | Codex callback runtime → Local Spool provider process → filesystem Spool。consumer は今回含まない。 |
| Queue / event / webhook / background worker | Present | completion / stop event を append-only Local Spool へ enqueue する producer boundary。Webhook / worker は対象外。 |
| External API or SDK | Absent | current scope は Windows local filesystem と既存 callback/provider boundary。 |
| Authentication or authorization | Absent | current source は local single-user execution を前提とし、新規 auth behavior を要求しない。filesystem ACL の実現確認は `IR-002`。 |
| Durable state / retry / replay / idempotency | Present | 1 event 1 file、distinct event、same-ID replay / race、atomic publish、write failure。 |
| Startup wiring / DI / configuration | Present | user-level Codex `notify`、runtime config、single provider、Spool path、installer / update / rollback。 |
| Production implementation split from test substitute | Present | deterministic temp Spool / fake provider evidence と real installed provider / filesystem / callback wiring の分離。 |
| Multiple runtime participants coordinating state | Present | Codex process、notification runtime、Local Spool provider、filesystem。consumer state coordination は対象外。 |
| Observable behavior spanning more than one component | Present | callback normalization / invocation、provider persistence、filesystem observation、installer wiring。 |

## 今回の対象外

- `NG-001`〜`NG-009` の consumer / Inbox / lifecycle / notification / forwarding / multi-device / workflow redesign。
- production code、tests、schema、workflow、package mirror の実装または変更。本 Plan Kernel pass が行う repository write は本 artifact の更新だけである。
- full runtime evidence、PlantUML sequence diagram、scenario ledger、full integration test design。
- final runtime contract、test point、具体 class / executable / path / sanitization algorithm の選択。
- implementation、verification、coverage-gap resolution、residual close decision。

## change-risk-triage への引き継ぎ

`Plan readiness: ReadyForRiskTriage`。`change-risk-triage.agent.md` は本 Plan と Behavior Spec を入力として、少なくとも次の boundary candidates と implementation-realization risk を分類する。

- callback runtime → single Local Spool provider → filesystem の cross-process / durable enqueue / fail-open boundary。
- 1 event 1 file、distinct IDs、same-ID replay / parallel race、same-directory temp + flush + atomic rename の idempotency / atomicity boundary。
- versioned 10-field JSON と current normalized event / provider input / dedupe / log の data-contract boundary。
- Windows-safe UTC-first filename、default Spool path、collision diagnostics、atomic failure exit の implementation-realization boundary。
- installer / config / update / rollback、旧 Windows provider / chained notify、canonical source / APM mirror の production wiring / compatibility boundary。
- deterministic temp / fake evidence と installed production callback / provider / filesystem wiring の binding boundary。

Case-to-Plan mapping は全29件分類済みで、`UnmappedBlocking` と `NeedsHumanDecision` はない。producer-only scope を consumer / Inbox へ再拡張せず、必要に応じて `implementation-contract-kernel.agent.md`、`runtime-contract-kernel.agent.md`、`test-design-kernel.agent.md` へ送ること。

## 実装実現性の残留事項

| Residual ID | Type | Status | Required confirmation | Downstream owner |
| --- | --- | --- | --- | --- |
| `IR-001` | API / persisted contract | `Unclear` / `Blocking before implementation` | current normalized event から versioned 10-field spool item を構成する field mapping、required / nullable、schema asset と production address。 | change-risk-triage → implementation-contract-kernel |
| `IR-002` | Dependency / Spool address | `Unclear` / `Blocking before implementation` | default Spool path、directory creation、Windows local ACL、installed runtime からの production address。 | change-risk-triage → implementation-contract-kernel |
| `IR-003` | Filename / collision | `Unclear` / `Blocking before implementation` | exact Windows sanitization、UTC precision、repository / status projection、short hash length、distinct-ID hash collision と same-ID race の diagnostic。 | implementation-contract-kernel |
| `IR-004` | Failure / timeout | `Unclear` / `Blocking before implementation` | exact callback time budget、provider exit、timeout / write / flush / rename failure diagnostic、一時 file の bounded handling。 | change-risk-triage → implementation-contract-kernel / runtime-contract-kernel |
| `IR-005` | Legacy compatibility / installer | `Unclear` / `Blocking before implementation` | 旧 Windows provider、provider list / chained notify、dedupe / log、config、installer / update / rollback の最小互換と migration address。single-provider invariantは変更しない。 | change-risk-triage → implementation-contract-kernel |
| `IR-006` | Production binding / mirror | `Unclear` / `Blocking before implementation` | canonical provider / schema / installer、APM checked mirror、CI validator、real installed callback / filesystem wiring の production address。 | change-risk-triage → implementation-contract-kernel / test-design-kernel / verification-kernel |

これらは product behavior の `NeedsHumanDecision` ではない。Plan readiness を block せず、implementation authorization 前に downstream contract artifacts で解消または明示 disposition する。

## Handoff Packet

- Profile used: plan-kernel
- Current phase: `plan-coverage-residual-flow` Step 3 / Plan Kernel rerun after behavior expansion
- Plan artifact: `plans/issue-76-codex-completion-local-spool-inbox-plan.md`
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Inline behavior sketch sufficient: No
- Behavior spec artifact required: Yes
- Behavior spec artifact: `plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`
- Process route: `plan-coverage-residual-flow`
- Process route source: explicit-user-selection（upstream durable task handoff に記録済み）
- Implementation route: adaptive
- Implementation route source: default（既存 Plan metadata を継続）
- Implementation permission: No。Plan は risk triage ready だが、change-risk-triage と必要な implementation / runtime / test-design / handoff guardrails は未実施。
- Close readiness: No。production implementation、production binding / wiring、verification、residual decision は未実施。
- Source artifacts: live GitHub Issue #76 `https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/76`（updated `2026-08-01T11:52:56Z`、2026-08-01 取得）、`plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`、更新前の本 Plan artifact。
- Selected contracts / IDs: このエージェントでは選択しない。最終選択は change-risk-triage が行う
- Implementation-realization residuals: `IR-001`〜`IR-006` は Plan readiness には non-blocking、implementation authorization 前には `Blocking`。change-risk-triage と implementation-contract-kernel が classification / realization decision を行う。
- Files inspected: `.agents/skills/plan-coverage-residual-flow/SKILL.md`、`.github/instructions/plan-coverage-shared.instructions.md`、`plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`、`plans/issue-76-codex-completion-local-spool-inbox-plan.md`、live GitHub Issue #76。
- Files intentionally not inspected: production code、tests、schema、installer / validator / provider 本文、APM mirror、Issue / Behavior Spec / existing Plan 以外の plans / docs / packages。既存 Plan の bounded source inspection を新 evidence なしに再実行していない。
- Decisions made: 2026-08-01 の Issue 追記を current authority とし、今回の完成単位を producer-side Local Spool に縮小した。1 event 1 JSON append-only、distinct event independence、same-ID idempotency、atomic publish、versioned contract、UTC-first safe filename、editor inspection、single provider、fail-open、installer / config を Plan FR / AC に確定した。consumer / Inbox / notification / retention 等は source-backed defer / out-of-scope とした。separate Behavior Spec が必要なため documentation level は `standard` とした。
- Case-to-Plan mapping summary: `CASE-76-001`〜`CASE-76-005`, `007`〜`013`, `017`, `021`, `024`〜`026` は `MappedToPlan`、`CASE-76-006`, `014`〜`016`, `018`〜`020`, `022`, `023`, `027`, `028` は `DeferredWithSource`、`CASE-76-029` は `OutOfScopeWithSource`。`UnmappedBlocking`: 0、`NeedsHumanDecision`: 0。
- Do not redo unless new evidence appears: `CASE-76-001`〜`CASE-76-029` と `URE-001`〜`URE-010` の stable IDs、producer / consumer scope split、Issue 追記の 10 observable checks、全 Case の disposition、consumer / Inbox / notification / retention 非対象判断。
- Remaining work:
  - `Consumed`: live Issue の producer-only scope revision、Behavior Spec の source-to-case expansion、全29 Case の Plan mapping、`URE-001`〜`URE-010` の blocking 解消判定、documentation level / Plan readiness 判定。
  - `Blocking`: `change-risk-triage.agent.md` が本 Plan、Behavior Spec、`IR-001`〜`IR-006` を入力として risk / process profile と必要 contract kernels を選択する。
  - `Blocking`: implementation authorization 前に、triage 結果に従って implementation contract、runtime contract、test design、handoff review を成立させる。
  - `DeferredWithReason`: `NG-001`〜`NG-009`。consumer / Inbox / notification / lifecycle / forwarding / multi-device / workflow redesign は source-backed に後続 Issue / 実装へ defer または current scope 外。
- Recommended next step: `change-risk-triage.agent.md`。入力は本 Plan、Behavior Spec、live Issue #76、documentation level `standard`、全29 Case の mapping summary、high-risk boundary candidates、`IR-001`〜`IR-006`。implementation はまだ許可しない。
