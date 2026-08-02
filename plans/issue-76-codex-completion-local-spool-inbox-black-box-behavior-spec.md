# Black-box Behavior Spec

## Scope

Issue #76「Codex完了イベントのローカルSpool化と独立Inbox」のうち、2026-08-01 に「初回実装スコープとして確定した分割」で確定した producer-side Local Spool を、実装方式に依存しない外部観測可能な behavior cases へ展開する。

今回の完成単位は、Codex callback から単一の Local Spool provider へ渡された完了・停止 event を、1 event 1 JSON file の append-only な境界へ安全に保存するところまでである。複数の異なる event の独立保持、同一 `source_event_id` の冪等性、完成 item の atomic な公開、versioned JSON contract、Windows-safe で UTC-first なファイル名、通常の editor からの閲覧、callback の既存 fail-open 境界、installer / configuration からの単一 provider 設定を扱う。

consumer、正式な Inbox、利用者向け state、search / filter、toast、forwarding、startup / reprocessing、retention / cleanup / archive / recovery、複数端末・cloud は後続へ defer する。今回の Local Spool を claim、ack、処理済み遷移を持つ完成済み message queue とは扱わない。Plan FR / AC、Case-to-Plan mapping、runtime contract、implementation contract、test design、production code、tests は変更しない。

## Source requirement inventory

| Source ID | Requirement summary | Kind | Source | Notes |
| --- | --- | --- | --- | --- |
| `SRC-76-001` | 複数の完了・停止 event を互いに上書き・黙示集約せず、独立した item として失わず保持する。 | 機能要求 / durable state | live Issue #76「成功とみなす利用者側の結果」「初回実装スコープとして確定した分割」 | 今回は独立した完成 JSON file として観測する。正式な Inbox 一覧は後続。 |
| `SRC-76-002` | 後続処理が結果または元の Codex thread への導線を構成できる情報を保持する。 | 機能要求 | live Issue #76「成功とみなす利用者側の結果」「保存用 JSON 契約」 | `resume_uri` と、利用可能な場合の `result_uri` を保存する。 |
| `SRC-76-003` | Codex callback は短時間で Local Spool への enqueue までを担い、provider failure / timeout 時も既存の fail-open 境界を維持する。 | 責務境界 / failure behavior | live Issue #76「採用する責務分担」「今回確認する結果」 | exact budget と provider exit は bounded implementation contract で確定し、product human decision にはしない。 |
| `SRC-76-004` | Codex callback から利用する provider は単一の Local Spool provider とし、複数 provider へ fan-out しない。 | negative expectation / 責務境界 | live Issue #76「採用する責務分担」「採用しない方向」「今回確認する結果」 | installer / configuration からこの単一 provider を設定可能にする。 |
| `SRC-76-005` | Spool を読む consumer は callback と別の local process とするが、consumer 自体は今回実装しない。 | scope boundary / deferred | live Issue #76「採用する責務分担」「今回の対象外」 | consumer の停止・更新・再処理 semantics も後続。 |
| `SRC-76-006` | Windows toast / 通知履歴を正式な Inbox または作業キューとして使用しない。 | negative expectation | live Issue #76「採用しない方向」 | 補助 toast の有無・集約・操作結果は今回対象外。 |
| `SRC-76-007` | callback 内に Inbox UI、利用者向け state、通知集約、search、retention、外部サービス連携を実装しない。 | negative expectation / 責務境界 | live Issue #76「採用する責務分担」「採用しない方向」「今回の対象外」 | producer-side Local Spool の責務を拡張しない。 |
| `SRC-76-008` | 現行の event normalization、provider stdin 境界、既存 event 情報を可能な範囲で再利用する。 | 互換境界 / 前提 | live Issue #76「現時点の前提」「後続設計へ残す実装上の確認」 | 既存 Windows provider と installer / update / rollback の最小互換境界は bounded implementation contract で確定する。 |
| `SRC-76-009` | 以前未決定だった実現候補のうち、初回実装に必要な Local Spool semantics は 2026-08-01 の追記で確定し、残りは明示的に後続へ defer された。 | source revision / scope decision | live Issue #76「後続設計に残す事項」「初回実装スコープとして確定した分割」 | 旧記述の未決定状態を、そのまま current scope の human-decision blocker にしない。 |
| `SRC-76-010` | Goal Context 生成、目的 review、PR review / remediation cycle は作り直さない。複数 PC、smartphone、cloud も今回含めない。 | non-goal / scope boundary | live Issue #76「過去ブランチとの関係」「今回の対象外」 | 配送先の変更を既存 workflow の再設計へ拡大しない。 |
| `SRC-76-011` | Local Spool は 1 event につき 1 個の JSON file を保存する append-only boundary とする。 | 機能要求 / persistence | live Issue #76「今回のゴール」 | 異なる event は別 file。同じ `source_event_id` は同じ 1 item。 |
| `SRC-76-012` | 同一 `source_event_id` の再送は完成 file を増殖・破損させず、1 個の最終 item として冪等に扱う。 | idempotency / replay | live Issue #76「今回のゴール」「今回確認する結果」 | distinct `source_event_id` は payload が同じでも独立 event。 |
| `SRC-76-013` | 同一 directory の一時 file へ書き、flush 後に完成 file 名へ atomic rename し、途中内容を完成 item として公開しない。 | atomicity / failure behavior | live Issue #76「今回のゴール」「今回確認する結果」 | write failure 時は壊れた完成 file を残さない。 |
| `SRC-76-014` | 利用者は Spool folder を VS Code 等で開き、各 JSON から後続 Inbox / notification に必要な event 情報を読める。 | user-observable behavior | live Issue #76「今回のゴール」「今回確認する結果」 | 専用 consumer / UI の存在を要求しない。 |
| `SRC-76-015` | file 名は UTC 時刻を先頭に置き、status・repository の識別要素と `source_event_id` 由来の短い hash を含み、Windows-safe である。JSON 本文を正本とする。 | naming / negative expectation | live Issue #76「今回のゴール」「今回確認する結果」 | exact sanitization と collision diagnostics は bounded implementation contract で確定する。 |
| `SRC-76-016` | versioned persisted spool-item contract は少なくとも指定された 10 field を保持し、transient な `notification_status: PENDING` を永続意味に流用しない。 | data contract / negative expectation | live Issue #76「保存用 JSON 契約」 | `schema_version`, `source`, `source_event_id`, `primary_process`, `observed_status`, `occurred_at`, `title`, `repository`, `resume_uri`, `result_uri`。 |
| `SRC-76-017` | consumer / Inbox state / search / filter / toast / forwarding / startup / reprocessing / retention / capacity cleanup / archive / recovery / multi-device / cloud は後続 Issue または後続実装とする。 | explicit defer | live Issue #76「今回の対象外」 | 今回の producer completion をこれらで block しない。 |
| `SRC-76-018` | 今回の acceptance evidence は Issue 追記の 10 個の observable checks を満たす。 | acceptance boundary | live Issue #76「今回確認する結果」 | `CASE-76-001`, `003`, `004`, `005`, `009`〜`012`, `017`, `021`, `026` で展開する。 |
| `SRC-76-019` | default Spool path、exact filename sanitization、collision diagnostics、atomic failure 時の provider exit、既存 Windows provider と installer / update / rollback の最小互換境界は bounded implementation contract で確定する。 | implementation-realization handoff | live Issue #76「後続設計へ残す実装上の確認」 | source contradiction がない限り product human decision へ戻さない。本 artifact では具体方式を選ばない。 |

## Behavior axes

| Axis ID | Axis | Relevant values | Why behavior changes | Notes |
| --- | --- | --- | --- | --- |
| `AX-76-001` | event identity / multiplicity | 一意な単一 event / distinct events / 同一 `source_event_id` の逐次 replay / 同一 ID の並行投入 / 同内容で別 ID | 最終的な完成 file 数と上書き・冪等結果が変わる。 | 全直積ではなく file 数が変わる境界だけを Case 化する。 |
| `AX-76-002` | write lifecycle | 一時 file への書込中 / flush 済み rename 前 / atomic rename 後 / write or rename failure | completed item として見えるか、壊れた file が残るかが変わる。 | 一時 file は完成 item ではない。 |
| `AX-76-003` | persisted payload | schema-valid / required field の有無 / `result_uri` 利用可能・利用不可 / transient `PENDING` 入力 | 後続処理が読み取れる情報と永続意味が変わる。 | versioned JSON 本文が authority。 |
| `AX-76-004` | filename projection | UTC timestamp / status element / repository element / short source hash / Windows-unsafe source characters | editor 上の時系列性、識別性、安全性が変わる。 | exact sanitization と collision diagnostics は implementation contract へ渡す。 |
| `AX-76-005` | provider result | success / failure / timeout | callback の fail-open と完成 file の有無が変わる。 | exact exit value / time budget は implementation contract へ渡す。 |
| `AX-76-006` | human inspection | generated Spool folder を通常 editor で開く / 専用 consumer がない | current scope で item と JSON を人が確認できるかが変わる。 | 正式な Inbox UX の代替仕様ではなく、producer artifact の observable check。 |
| `AX-76-007` | deferred consumer behavior | claim / ack / state / search / toast / forwarding / startup / reprocessing | 後続では結果を変えるが、current producer scope には state transition がない。 | `DeferredWithSource` Case として境界を残す。 |
| `AX-76-008` | lifecycle policy | retention / capacity cleanup / delete / archive / recovery | 将来の保持・削除結果が変わる。 | current append-only producer には cleanup semantics を追加しない。 |
| `AX-76-009` | existing installation | 旧 Windows provider 有 / Local Spool 設定 / install・update・rollback | single-provider 設定と最小互換境界が変わる。 | exact compatibility は current implementation contract で確定する。 |

## Case matrix

| Case ID | Source IDs | Input conditions / preconditions | Expected observable behavior | Negative expectation | Status |
| --- | --- | --- | --- | --- | --- |
| `CASE-76-001` | `SRC-76-003`, `SRC-76-004`, `SRC-76-011`, `SRC-76-016`, `SRC-76-018` | 一意な valid completion / stop event が単一の Local Spool provider に渡され、保存が成功する。 | 1 個の schema-valid な完成 JSON file が生成される。JSON は versioned contract の 10 field を保持し、callback の producer-side 処理は enqueue の結果で終わる。 | callback から別 provider へ fan-out せず、Inbox / consumer 処理を実行せず、transient `notification_status: PENDING` を spool item の永続状態として保存しない。 | `Defined` |
| `CASE-76-002` | `SRC-76-003`, `SRC-76-005`, `SRC-76-007`, `SRC-76-011`, `SRC-76-017` | consumer が存在しない、停止中、または更新中に valid event の保存が成功する。 | consumer の稼働を待たずに完成 JSON が Local Spool に残り、後続 consumer が利用できる producer output となる。 | callback が consumer を起動・代行したり、Inbox state や通知を更新したりしない。 | `Defined` |
| `CASE-76-003` | `SRC-76-001`, `SRC-76-011`, `SRC-76-012`, `SRC-76-018` | 異なる `source_event_id` を持つ複数の completion / stop event を近い時刻または並行に投入する。 | すべての event がそれぞれ独立した完成 JSON file として残る。 | event 同士を上書き・黙示集約せず、並行投入を理由に欠落させない。 | `Defined` |
| `CASE-76-004` | `SRC-76-001`, `SRC-76-014`, `SRC-76-018` | 自動テスト等で複数の完成 item を含む Spool folder を生成し、利用者が VS Code 等の通常 editor で folder を開く。 | 利用者は file 一覧から各完成 item を個別に認識し、各 JSON の後続処理に必要な情報を読める。 | 専用 consumer / Inbox UI や Windows toast 履歴がなければ確認不能な形式にしない。 | `Defined` |
| `CASE-76-005` | `SRC-76-002`, `SRC-76-016`, `SRC-76-018` | event に `resume_uri` があり、`result_uri` は利用可能または利用不可である。 | 完成 JSON に `resume_uri` と、利用可能な場合の `result_uri` が保存され、後続処理が該当結果または元 thread への導線を構成できる。 | URI を file 名だけへ埋め込んだり、利用可能な URI を失って後続に再探索させたりしない。 | `Defined` |
| `CASE-76-006` | `SRC-76-006`, `SRC-76-017` | 将来の Inbox item で link open、toast click / dismiss、明示的な処理完了操作を区別する必要がある。 | Inbox state と操作 semantics を定める後続 Issue / 実装で扱う。current Local Spool item には未処理・処理済み遷移を持たせない。 | producer の保存成功、link open、toast 操作を開発作業上の処理済みとみなさない。 | `DeferredWithSource` |
| `CASE-76-007` | `SRC-76-004`, `SRC-76-005`, `SRC-76-007`, `SRC-76-017` | event が callback から producer-side Local Spool へ配送される。 | callback の直接配送先は Local Spool 一種類であり、保存までで current processing を終える。 | Inbox UI、state、search、toast、retention、外部転送を callback または Local Spool provider の current responsibility に追加しない。 | `Defined` |
| `CASE-76-008` | `SRC-76-001`, `SRC-76-006`, `SRC-76-011`, `SRC-76-014` | Windows 通知履歴が空、dismiss 済み、または利用不能で、Local Spool への保存は成功している。 | 完成 JSON file は toast history から独立して Spool folder に残り、通常 editor で確認できる。 | toast history の状態を理由に完成 spool item を削除・処理済み化しない。 | `Defined` |
| `CASE-76-009` | `SRC-76-003`, `SRC-76-018`, `SRC-76-019` | Local Spool provider が失敗する、または callback 側の timeout 境界に到達する。 | callback は既存の fail-open 境界を維持して Codex の完了経路へ制御を返す。exact time budget、provider exit、diagnostic は bounded implementation contract により再現可能に定義される。 | provider の無制限待機や failure により Codex 本体の完了を fail-closed にせず、成功したと偽装しない。 | `Defined` |
| `CASE-76-010` | `SRC-76-003`, `SRC-76-013`, `SRC-76-018`, `SRC-76-019` | permission、容量、I/O、flush、rename 等により spool write が失敗する。 | 壊れた完成 JSON file を残さず、callback は fail-open を維持する。provider の失敗結果と collision / atomic-failure diagnostic は bounded implementation contract で確定する。 | partial / invalid JSON を完成 item として公開せず、cleanup policy を current scope へ暗黙追加しない。 | `Defined` |
| `CASE-76-011` | `SRC-76-011`, `SRC-76-012`, `SRC-76-018` | 既に保存済みの `source_event_id` と同じ ID の event を再送する。 | 最終的な完成 item は同じ 1 個に保たれ、再送によって完成 file が増殖・破損しない。 | title 等の payload 類似性ではなく `source_event_id` の同一性に基づき、2 個目の完成 item を作らない。 | `Defined` |
| `CASE-76-012` | `SRC-76-012`, `SRC-76-013`, `SRC-76-018`, `SRC-76-019` | 同一 `source_event_id` の複数 event が並行して保存を試みる。 | 競合後も schema-valid な完成 item が 1 個だけ残る。collision の診断方法は bounded implementation contract で確定する。 | race により完成 item を全て失わず、複数の最終 item や壊れた file を残さない。 | `Defined` |
| `CASE-76-013` | `SRC-76-001`, `SRC-76-011`, `SRC-76-012` | payload 内容が同じでも異なる `source_event_id` を持つ複数 event を投入する。 | distinct events としてそれぞれ独立した完成 JSON file が残る。 | payload の内容一致を `source_event_id` の同一性とみなして一方を抑止しない。 | `Defined` |
| `CASE-76-014` | `SRC-76-005`, `SRC-76-017` | 将来の consumer が item を claim した後、処理完了前に failure となる。 | claim / ack / ownership / retry semantics を定める後続 Issue / 実装で扱う。current Local Spool は claim を提供しない。 | producer-side completion に consumer ownership semantics を推測で追加しない。 | `DeferredWithSource` |
| `CASE-76-015` | `SRC-76-005`, `SRC-76-017` | 将来の consumer が claim または state 更新途中に crash し、その後 restart する。 | restart / reprocessing semantics を定める後続 Issue / 実装で扱う。 | current scope で consumer crash 後の item state を決定したことにしない。 | `DeferredWithSource` |
| `CASE-76-016` | `SRC-76-006`, `SRC-76-017` | 利用者が将来の Inbox item を未処理一覧から外す、保留する、再表示する、または archive する。 | 利用者向け state と遷移を定める後続 Issue / 実装で扱う。 | current spool JSON に transient notification state や処理済み state を流用しない。 | `DeferredWithSource` |
| `CASE-76-017` | `SRC-76-014`, `SRC-76-015`, `SRC-76-018`, `SRC-76-019` | status、repository、`source_event_id`、`occurred_at` を含む event を Windows 環境で保存する。 | 完成 file 名は Windows-safe で、UTC 時刻を先頭にした一覧順を作れ、status / repository の識別要素と source ID 由来の短い hash を含む。exact sanitization は bounded implementation contract で確定する。 | file 名を contract authority とせず、file 名から JSON の完全な意味を復元させない。 | `Defined` |
| `CASE-76-018` | `SRC-76-017` | 利用者が将来の Inbox で特定 item を search / filter したい。 | search / filter と Inbox 固有 sort を定める後続 Issue / 実装で扱う。 | current editor-visible filename を正式 Inbox の検索仕様とみなさない。 | `DeferredWithSource` |
| `CASE-76-019` | `SRC-76-011`, `SRC-76-017` | Spool item が retention 期限または容量管理の threshold に達する。 | retention、容量管理、automatic deletion、cleanup policy を定める後続 Issue / 実装で扱う。current producer は append-only boundary として振る舞う。 | 未処理 / 処理済み概念や無通知削除 policy を current scope に推測で追加しない。 | `DeferredWithSource` |
| `CASE-76-020` | `SRC-76-017` | 利用者または将来の cleanup が delete / archive を要求し、その後に recovery が必要になる。 | delete、archive、recovery semantics を定める後続 Issue / 実装で扱う。 | current spool item を復元可能または archive 済みと表示する contract を追加しない。 | `DeferredWithSource` |
| `CASE-76-021` | `SRC-76-013`, `SRC-76-016`, `SRC-76-018`, `SRC-76-019` | write が一時 file の途中、flush 後、または atomic rename 前後で中断・失敗する。 | rename 成功前の一時 file や書き途中の内容は完成 item として扱われず、完成名で見える file は schema-valid な JSON である。failure 時の provider exit は bounded implementation contract で確定する。 | partial / corrupt JSON を完成 file 名で公開しない。既存の破損 file や incompatible schema を読む consumer recovery policyは current scope で決めない。 | `Defined` |
| `CASE-76-022` | `SRC-76-005`, `SRC-76-014`, `SRC-76-017` | Windows local 環境で consumer / Inbox を初めて利用する、停止後に再利用する、または更新後に再開する。 | consumer UI、常駐、自動起動、再処理は後続 Issue / 実装で扱う。current scope では generated Spool folder と JSON を通常 editor で確認できる。 | editor inspection check を consumer startup contract とみなさない。 | `DeferredWithSource` |
| `CASE-76-023` | `SRC-76-006`, `SRC-76-017` | 将来の consumer が新規 event を検出し、補助 toast を出せる。 | toast の有無、個別 / 集約、頻度、選択時動作は後続 Issue / 実装で扱う。 | toast を正式 Inbox とせず、current callback から toast provider へ fan-out しない。 | `DeferredWithSource` |
| `CASE-76-024` | `SRC-76-004`, `SRC-76-008`, `SRC-76-019` | 旧 Windows App Notification provider または chained notify が導入済みの環境で Local Spool provider を callback 配送先にする。 | callback の current direct provider は Local Spool 一種類となり、最小互換境界は bounded implementation contract で既存 install / update / rollback behavior とともに確定される。 | compatibility の名目で callback の複数 provider fan-out を維持せず、product human decision を要求して current pass を停止しない。 | `Defined` |
| `CASE-76-025` | `SRC-76-008`, `SRC-76-012`, `SRC-76-016`, `SRC-76-019` | 既存 runtime の dedupe / log / provider input に transient `notification_status: PENDING` が含まれ得る。 | spool item の identity は `source_event_id` で判定され、versioned JSON は `observed_status` を保持する。`PENDING` は persisted spool lifecycle state にならない。既存 state / log の最小互換は bounded implementation contract で扱う。 | 旧 notification delivery state を Inbox state または spool item authority と同一視しない。 | `Defined` |
| `CASE-76-026` | `SRC-76-004`, `SRC-76-008`, `SRC-76-018`, `SRC-76-019` | installer / configuration を用いて Codex callback の provider を設定する。 | Local Spool を callback の単一 provider として設定できる。install / update / rollback の exact minimal compatibility は bounded implementation contract で確定し、その契約に対して観測可能に検証される。 | installer の変更だけを Spool behavior 完成の証拠とせず、consumer / Inbox を同時導入の必須条件にしない。 | `Defined` |
| `CASE-76-027` | `SRC-76-004`, `SRC-76-017` | Spool の event を Webhook、Slack、他サービスへ転送したい。 | 初回実装には含めず、将来の consumer または別 forwarder の拡張として扱う。 | callback から追加 provider へ直接 fan-out しない。 | `DeferredWithSource` |
| `CASE-76-028` | `SRC-76-010`, `SRC-76-017` | 複数 PC、smartphone、cloud から event を参照したい。 | Windows local producer の初回実装には含めず、外部転送・同期の後続課題として扱う。 | current Local Spool scope を multi-device / cloud 同期へ拡大しない。 | `DeferredWithSource` |
| `CASE-76-029` | `SRC-76-010` | Goal Context 生成、目的 review、PR review / remediation cycle を変更する。 | Issue #76 の behavior scope から除外する。 | producer-side Local Spool の変更を理由に既存 review workflow を再設計しない。 | `ExcludedWithReason` |

## Derived invariants

| Invariant ID | Description | Covered Case IDs | Notes |
| --- | --- | --- | --- |
| `INV-76-001` | Codex callback の直接配送先は単一の Local Spool provider であり、user-facing provider へ fan-out しない。 | `CASE-76-001`, `CASE-76-007`, `CASE-76-024`, `CASE-76-026`, `CASE-76-027` | 既存 provider との最小互換もこの境界を破らない。 |
| `INV-76-002` | callback の責務は enqueue までであり、consumer、Inbox state、search、toast、retention、external forwarding から独立する。 | `CASE-76-001`, `CASE-76-002`, `CASE-76-006`〜`CASE-76-010`, `CASE-76-014`〜`CASE-76-016`, `CASE-76-018`〜`CASE-76-023` | provider failure / timeout 時も callback は fail-open。 |
| `INV-76-003` | distinct `source_event_id` は独立した完成 file、同一 `source_event_id` は再送・並行投入でも 1 個の完成 item となる。 | `CASE-76-003`, `CASE-76-011`〜`CASE-76-013` | payload equality は identity ではない。 |
| `INV-76-004` | 完成 item は 1 event 1 schema-valid JSON file であり、atomic rename 前の一時内容や write failure の断片を含まない。 | `CASE-76-001`, `CASE-76-010`, `CASE-76-012`, `CASE-76-021` | same-directory temp + flush + atomic rename の observable postcondition。 |
| `INV-76-005` | persisted JSON 本文が authority であり、versioned 10 field を保持し、transient `notification_status: PENDING` を永続 state に流用しない。 | `CASE-76-001`, `CASE-76-005`, `CASE-76-017`, `CASE-76-025` | file 名は一覧・識別用 projection。 |
| `INV-76-006` | 利用者は専用 consumer がなくても通常 editor で Spool folder と各 JSON を閲覧できる。 | `CASE-76-004`, `CASE-76-008`, `CASE-76-017`, `CASE-76-022` | 正式 Inbox の完成を意味しない。 |
| `INV-76-007` | consumer / Inbox / notification / lifecycle policy は source-backed に後続へ defer され、current producer completion の blocker ではない。 | `CASE-76-006`, `CASE-76-014`〜`CASE-76-016`, `CASE-76-018`〜`CASE-76-020`, `CASE-76-022`, `CASE-76-023`, `CASE-76-027`, `CASE-76-028` | current spool item に claim / ack / user-facing state を追加しない。 |
| `INV-76-008` | default path、exact sanitization、collision diagnostics、atomic failure provider exit、legacy minimum compatibility は implementation-realization decision であり、source contradiction がない限り product human decision で止めない。 | `CASE-76-009`, `CASE-76-010`, `CASE-76-012`, `CASE-76-017`, `CASE-76-021`, `CASE-76-024`〜`CASE-76-026` | `implementation-contract-kernel.agent.md` の領域。本 artifact は方式を選ばない。 |

## Excluded combinations / non-goals

| Exclusion ID | Condition / behavior | Source or reason | Reopen condition |
| --- | --- | --- | --- |
| `EX-76-001` | callback から Local Spool と toast / Webhook / Slack へ同時 fan-out する。 | `SRC-76-004`, `SRC-76-007`; 明示的に採用しない方向。 | callback 責務境界を変更する新しい source requirement が承認された場合。 |
| `EX-76-002` | callback / Local Spool provider 内に Inbox UI、state、aggregation、search、retention、外部連携を置く。 | `SRC-76-003`, `SRC-76-005`, `SRC-76-007`, `SRC-76-017`; producer-side scope。 | 後続 consumer requirement として別境界に追加された場合。 |
| `EX-76-003` | Windows toast history または通常 editor の folder view を正式 Inbox とみなす。 | `SRC-76-006`, `SRC-76-014`, `SRC-76-017`; editor view は今回の inspection check に限定される。 | 正式 Inbox の behavior が後続 source で定義された場合。 |
| `EX-76-004` | filename sanitization、failure、event multiplicity と deferred consumer state の全組み合わせを列挙する。 | source が要求する結果変更境界を越えて重複 Case を作るため。 | 複合条件固有の期待結果が source に追加された場合。 |
| `EX-76-005` | Goal Context / purpose review / PR review-remediation を再設計する。 | `SRC-76-010`; 配送先の bounded change に限定する。 | 別 Issue または新しい明示要求で対象化された場合。 |
| `EX-76-006` | 複数 PC、smartphone、cloud sync を初回実装へ含める。 | `SRC-76-010`, `SRC-76-017`; Windows local producer が current scope。 | 外部転送・同期を対象とする後続要求が承認された場合。 |
| `EX-76-007` | Local Spool を claim / ack / processing state / automatic cleanup を持つ完成済み message queue と扱う。 | live Issue #76「今回の対象外」; `SRC-76-017`。 | consumer と queue lifecycle を定義する後続 source が承認された場合。 |

## Unresolved requirement-elaboration items

| Item ID | Source IDs | Missing decision / ambiguity | Blocking? | Required decision |
| --- | --- | --- | --- | --- |
| `URE-001` | `SRC-76-003`, `SRC-76-018`, `SRC-76-019` | callback の exact time budget、default Spool path、failure / timeout 時の provider exit と diagnostic。 | No | bounded implementation contract で確定する。source-backed な fail-open、破損完成 file 不在、single-provider boundary は `CASE-76-009`, `CASE-76-010` で定義済み。product human decision は不要。 |
| `URE-002` | `SRC-76-001`, `SRC-76-012`, `SRC-76-019` | hash / file collision の exact diagnostic と競合実現方法。 | No | identity と item 数は解決済み。同一 `source_event_id` は 1 item、distinct ID は独立 item とする。exact collision handling は bounded implementation contract で確定する。対象: `CASE-76-011`〜`CASE-76-013`。 |
| `URE-003` | `SRC-76-005`, `SRC-76-017` | consumer claim 後 failure / crash / restart の ownership、ack、retry。 | No | current scope には consumer / claim がなく、後続 Issue / 実装へ defer。対象: `CASE-76-014`, `CASE-76-015`。 |
| `URE-004` | `SRC-76-006`, `SRC-76-016`, `SRC-76-017` | Inbox の state 集合、処理済み操作、再 open / archive。 | No | current persisted contract に Inbox / notification state を流用せず、後続へ defer。対象: `CASE-76-006`, `CASE-76-016`。 |
| `URE-005` | `SRC-76-014`, `SRC-76-015`, `SRC-76-017` | 正式 Inbox の表示 field、sort、search / filter。 | No | current scope は UTC-first filename と editor-readable JSON までを定義済み。正式 Inbox の UX は後続へ defer。対象: `CASE-76-004`, `CASE-76-017`, `CASE-76-018`。 |
| `URE-006` | `SRC-76-011`, `SRC-76-017` | retention、capacity cleanup、delete、archive、recovery。 | No | current producer は append-only boundary。lifecycle policy は後続 Issue / 実装へ defer。対象: `CASE-76-019`, `CASE-76-020`。 |
| `URE-007` | `SRC-76-013`, `SRC-76-017`, `SRC-76-019` | existing corrupt / incompatible item を読む consumer recovery と、atomic failure 時の exact provider exit。 | No | partial content 非公開・壊れた完成 file 不在は定義済み。consumer recovery は後続、provider exit は bounded implementation contract で確定する。対象: `CASE-76-010`, `CASE-76-021`。 |
| `URE-008` | `SRC-76-005`, `SRC-76-014`, `SRC-76-017` | consumer UI、常駐、自動起動、停止中 item の発見 / reprocessing。 | No | current observable check は通常 editor で folder / JSON を閲覧できること。consumer startup / reprocessing は後続へ defer。対象: `CASE-76-004`, `CASE-76-022`。 |
| `URE-009` | `SRC-76-006`, `SRC-76-017` | consumer の補助 toast の有無、個別 / 集約、選択時動作。 | No | 後続 Issue / 実装へ defer。callback fan-out 禁止は current invariant。対象: `CASE-76-023`。 |
| `URE-010` | `SRC-76-004`, `SRC-76-008`, `SRC-76-019` | 旧 Windows provider、dedupe / log / config、installer / update / rollback の exact minimal compatibility。 | No | Local Spool の single-provider 設定と persisted contract 境界は定義済み。exact compatibility は bounded implementation contract で確定し、source contradiction がない限り product human decision で止めない。対象: `CASE-76-024`〜`CASE-76-026`。 |

## Handoff Packet

- Profile used: black-box-behavior-spec-kernel
- Behavior spec artifact: `plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`
- Source artifacts: live GitHub Issue #76 `https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/76`（updated `2026-08-01T11:52:56Z`、2026-08-01 取得）、`plans/issue-76-codex-completion-local-spool-inbox-plan.md`、本 Behavior Spec の更新前内容
- Case IDs: `CASE-76-001`〜`CASE-76-029`（rename なし）
- Files inspected: `.agents/skills/plan-coverage-residual-flow/SKILL.md`、`.github/instructions/plan-coverage-shared.instructions.md`、`plans/issue-76-codex-completion-local-spool-inbox-plan.md`、`plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`
- Files intentionally not inspected: production code、tests、schema、installer / validator 本文、APM mirror、Issue / Plan / Behavior Spec 以外の plans / docs / packages
- Decisions made: 2026-08-01 の source revision を authority とし、producer-side Local Spool を今回の完成単位にした。1 event 1 JSON、append-only、distinct event の独立性、同一 `source_event_id` の 1 final item、same-directory temp + flush + atomic rename、editor-readable folder / JSON、UTC-first Windows-safe filename、JSON body authority、versioned 10-field contract、`PENDING` 非流用、fail-open、single-provider installer / config を `Defined` に更新した。
- Excluded combinations: `EX-76-001`〜`EX-76-007`。behavior axes の全直積、consumer semantics の producer への混入、Local Spool の完成 queue 扱いは除外した。
- NeedsHumanDecision: なし。`URE-001`〜`URE-010` は rename せず、current behavior で解決済み、source-backed defer、または bounded implementation contract の非 blocking realization decision へ更新した。
- Do not redo unless new evidence appears: `CASE-76-001`〜`CASE-76-029` と `URE-001`〜`URE-010` の stable ID、Issue 追記の producer / consumer scope split、Issue 追記の 10 observable checks。Case ID / URE ID は rename しない。
- Remaining work: `plan-kernel.agent.md` が live Issue と本 artifact を基に Plan FR / AC と全 Case ID の mapping、deferred disposition、Plan readiness を更新する。その後、ready な bounded Plan に対して change-risk triage と必要な implementation contract を行う。本 artifact には Case-to-Plan mapping を追加しない。
- Recommended next step: `plan-kernel.agent.md`。source-to-case expansion は current producer scope について十分で、product human decision blocker はない。`change-risk-triage.agent.md`、implementation、verification へはこの agent から直接進まない。
