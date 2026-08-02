# Implementation Contract Kernel

## スコープ

live Issue #76 の 2026-08-01 縮小決定と bounded Plan を authority とし、Codex callback から Local Spool provider へ渡された completion / stop event を、producer-side の 1 event 1 JSON boundary に保存する実装方式を確定する。Guardrail Focus は `RC-001`〜`RC-003`、implementation-realization items は `IR-001`〜`IR-006` である。

consumer、Inbox UI / state、claim / ack / retry、toast、search / filter、retention / cleanup / archive、forwarding、cloud / multi-device は `OutOfScopeForThisPass` とする。Plan の product semantics は変更しない。

## Plan が要求する実装要件

| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |
| `IR-001`, `FR-001`, `AC-001`, `AC-002`, `AC-012` | normalized event から versioned 10-field spool item を作り、`notification_status` を永続化しない | current `CompletionEvent` は必要な10 fieldと transient `NotificationStatus` を provider stdin に渡す。current event schema は11 field contract | `Confirmed` |
| `IR-002`, `FR-002`, `FR-006` | portable な既定 Spool path、directory creation、editor-readable JSON | runtime home は `CODEX_NOTIFICATION_RUNTIME_HOME`、未設定時は `%LOCALAPPDATA%\CodexNotificationRuntime` として解決済み | `Confirmed` |
| `IR-003`, `FR-003`, `FR-005` | UTC-first、Windows-safe、status / repository / short source hash を含む filename と same-ID idempotency | `source_event_id` と SHA-256 helper、Windows local runtime が存在。exact realization は本 artifact で固定 | `Confirmed` |
| `IR-004`, `FR-004`, `FR-008` | same-directory temp、disk flush、atomic publish、nonzero provider failure、bounded callback fail-open | runtime は provider stdin、1〜30秒 clamp、exit判定、timeout kill、outer fail-openを実装済み。provider の filesystem behavior は新規実装が必要 | `Confirmed` |
| `IR-005`, `FR-007`, `FR-009`, `FR-010` | callback の direct provider は Local Spool 一種類。installer update / rollback と legacy disposition を定める | current installer は staged bin/config swap、previous bin/config rollback、1個の Windows provider config、既存 notify metadata を持つ | `Confirmed` |
| `IR-006`, `AC-011` | canonical、APM checked mirror、validator、installed callback→filesystem を結ぶ | canonical runtime assets、APM asset mirror validator、2つの validation workflow entrypoint が存在 | `Confirmed` |
| `NG-001`〜`NG-009` | consumer / Inbox / lifecycle / forwarding を producer に混入しない | Issue、Behavior Spec、Plan が source-backed に defer / exclude | `OutOfScopeForThisPass` |

## Dependency と API surface の確認結果

| Dependency / API / symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |
| canonical Local Spool provider | `scripts/codex-notification-runtime/` | 新規 `scripts/codex-notification-runtime/local-spool-provider.cs` | `MissingButRequired` | この exact path を production source とする。外部 package は追加しない。`net10.0` BCL のみを使う |
| persisted schema | canonical runtime assets | 新規 `scripts/codex-notification-runtime/spool-item-v1.schema.json` | `MissingButRequired` | title は `spool-item-v1`。current provider-input schemaとは別 asset |
| provider stdin | normalized completion event | `codex-notification-runtime.cs` の `CompletionEvent` / `InvokeProviderAsync` | `Confirmed` | 11-field inputから `notification_status` を除いた10 fieldを投影する |
| runtime home resolution | runtime / installer | `codex-notification-runtime.cs` lines 10-11、installer の default `installRoot` | `Confirmed` | provider default は同じ resolution rule の `<runtime-home>\spool` |
| filesystem durability | .NET BCL | `FileStream`, `Flush(flushToDisk: true)`, `File.Move(..., overwrite: false)` | `Confirmed` | same-directory tempを閉じた後に finalへ moveする |
| cross-process same-ID serialization | .NET BCL / Windows local | named `Mutex` | `Confirmed` | `Local\CodexNotificationSpool-<SHA256(source_event_id)>`、bounded acquire。filesystem lock artifactを残さない |
| single provider config | current `RuntimeConfig.Providers` / `ProviderSpec` | runtime / installer | `Confirmed` | config shapeは維持し、runtimeが `Count == 1` を要求してその1件だけを呼ぶ |
| provider timeout / exit | current runtime | `InvokeProviderAsync` | `Confirmed` | installer default `5000ms`、runtime clamp `1000..30000ms` を維持 |
| runtime dedupe / retry / log | current runtime | `state/*.claim`, `*.delivered`, `runtime.log.jsonl` | `AllowedReuse` | provider failure時claim削除、成功時delivered、outer fail-openを維持。spool item identityの代用にはしない |
| Windows App Notification provider | legacy source | `windows-app-notification-provider.cs` | `RejectedSubstitute` | sourceはlegacy / rollback referenceとして残すが、successful installではpublish/configureしない |
| fake provider | validation helper | `tests/fake-notification-command.ps1` | `RejectedSubstitute` | process/fail-open testsには再利用可。production spool evidenceには不可 |
| installer transactional swap | current installer | staged publish、`bin.previous-*`、`runtime-config.json.previous-*` | `AllowedReuse` | Local Spool binary/schemaをstage検証し、失敗時にold bin/configを復元する |
| APM mirror validation | package validator | `apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1` | `AllowedReuse` | new provider/schemaと変更 canonical assetsをchecked mirror setへ追加する |

## 選択した実装アプローチ

1. canonical production sourceを `local-spool-provider.cs`、persisted contractを `spool-item-v1.schema.json` とする。providerはstdinの current completion eventを厳格にdeserialize / validateし、`notification_status` を読んでも spool itemへ書かない。`result_uri` は常にpropertyを出力し、値なしは JSON `null` とする。schemaは10 propertyをすべて `required`、`additionalProperties: false`、`schema_version: 1` とする。
2. Spool root は `--spool-root <absolute-path>`、`CODEX_NOTIFICATION_SPOOL_HOME`、`CODEX_NOTIFICATION_RUNTIME_HOME\spool`、`%LOCALAPPDATA%\CodexNotificationRuntime\spool` の順で解決する。空値・relative path・invalid full pathはexit `2`。installerのproduction configはmachine-specific pathをargvへ焼かず、既定 resolutionを使う。明示 overrideが必要な利用者だけprovider argvまたはenvironmentを使う。新しいprovider固有 `runtime-config.json` keyは追加しない。
3. JSON bodyを authority とし、UTF-8 without BOM、indented JSON、末尾newlineで書く。filenameは `<yyyyMMddTHHmmss.fffffffZ>__<status>__<repository>__<hash16>.json` とする。timestampはitem `occurred_at` をUTC化した固定7桁、`hash16` はUTF-8 `source_event_id` のSHA-256 lowercase hex先頭16桁。statusは最大24、repositoryは最大48文字。projectionはUnicode NFKC後にlowercase ASCII `[a-z0-9]` と `-` のみを残し、その他の連続を単一 `-`、前後 `-` を除去し、空なら `unknown` とする。Windows reserved nameや末尾dot/spaceはこのalphabetで生成されない。
4. providerは同じ `hash16` の named mutexを最大2秒で取得し、取得後に `*__<hash16>*.json` のcandidate bodyを読み、同一 `source_event_id` があれば内容を書き換えずexit `0` (`idempotent-existing`) とする。これによりruntime state expiry後や、初回write成功後にprovider exitを観測できなかったretryも1 itemに収束する。
5. short-hash filenameが既存の別 `source_event_id` と衝突した場合は上書き・成功偽装しない。mutex内でSHA-256 suffixを24、32、64 hexへ順に拡張して空きfinal名を選び、stderrへ `filename-collision-disambiguated` をJSON 1行で出す。64 hexでも別IDと衝突した場合はexit `3` (`identity-collision`) とし、既存finalを保持する。distinct IDをpayload equalityで抑止しない。
6. tempはfinalと同一directoryの `.<final-name>.<guid-N>.tmp` を `FileMode.CreateNew` で作る。serialize後に`FlushAsync`、続けて `Flush(flushToDisk: true)`、close、`File.Move(temp, final, overwrite: false)` の順に公開する。Move競合時はmutex内でfinal bodyを再検査し、same IDならsuccess、別IDなら前項のsuffix拡張を行う。失敗時はtempをbest-effort削除し、partial finalを作らずexit `3`。temp retention / sweepingは追加しない。
7. exitは `0=published or idempotent-existing`、`2=invalid stdin/config/path`、`3=mutex/filesystem/flush/move/identity collision failure` とする。diagnosticはraw payload / URI / source IDを出さず、code、event hash、exception typeだけをstderr JSON 1行へ出す。runtimeはprovider stderrをbounded captureし、`provider-exit` / `provider-timeout` / diagnostic codeを`runtime.log.jsonl`へ記録するが、callback modeは既存どおりexit `0`。timeout killとprovider failure後claim削除によるretryを維持する。
8. `RuntimeConfig.Providers` のshapeは互換のため維持するが、runtimeはexactly one providerだけを許可する。0件または2件以上はproviderを呼ばず`invalid-provider-count`をlogしてfail-openする。installerは`Name = local-spool`、`Argv = [<installRoot>\bin\local-spool-provider.exe]`、`TimeoutMs = 5000` の1件だけを書く。nearby Windows providerへのfallbackやprovider loopは行わない。
9. Windows provider sourceはcanonical / APM mirrorにlegacy referenceとして残すが、successful installのstage / self-test / `bin` / runtime configから除外する。旧installのupdateではnew runtime / spool provider / schemaをstageし、bin/config swap失敗時だけprevious binとprevious runtime configを復元する。成功後はWindows provider binaryをproduction binに残さない。既存 `chained_notify` はrollback metadataとして保持するがruntime deliveryから外し、Local Spool以外へcallback fan-outしない。protected user config backupのoverwrite禁止とself-wrap検出は維持する。
10. canonical変更はroot README、runtime decision/manual verification docs、validator、workflowsへ反映し、APM packageのprovider/schema/runtime/installer/docs checked mirrorとpackage validatorを同期する。installer `--check` はruntime binary、Local Spool provider binary、schema asset、exactly-one local-spool config、resolved writable Spool directoryを確認し、Windows App support probeを要求しない。

## 必要なコード変更

- 新規: `scripts/codex-notification-runtime/local-spool-provider.cs`、`scripts/codex-notification-runtime/spool-item-v1.schema.json`。
- runtime: `scripts/codex-notification-runtime/codex-notification-runtime.cs` の `LoadConfig`、provider count gate、`InvokeProviderAsync`、diagnostic log。normalization、`source_event_id`、claim/delivered retry、outer fail-openは維持する。
- installer: `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs` の provider path、stage publish/self-test/schema copy、runtime config、`--check`、rollback assertions、source-root checks。
- canonical validation/docs: `scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`、`decision-record.md`、`manual-verification.md`、root `README.md`、関連 workflows。
- package mirror: `apm-packages/completion-notification-decorator/.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/` のnew provider/schemaと変更対象mirror、package README / usage guide、`validate-completion-notification-decorator.ps1`、`apm.yml` の説明、必要なworkflow。
- testsはdownstream test design / implementationで上記surfaceに対応して変更する。本agentは変更しない。

## 禁止される代替実装

| Similar existing path | Why it is not sufficient | Allowed reuse, if any |
| --- | --- | --- |
| `windows-app-notification-provider.cs` | toast表示でありdurable Local Spool、atomic publish、same-ID idempotencyを提供しない | URI validation等もspool contractへコピーしない。legacy source / rollback evidenceのみ |
| `fake-notification-command.ps1` / provider output JSONL | test substituteであり1 event 1 final JSON、disk flush、atomic move、installed bindingを証明しない | stdin、exit、timeout、fail-openのfixtureに限定 |
| runtime `state/*.delivered` | 30日cleanupされるdelivery stateでありappend-only spool itemでもJSON authorityでもない | redundant callback抑止とretry制御は維持 |
| `completion-notification-event-v1.schema.json` | transient `notification_status` を含むprovider-input contract | input validationに維持。persisted schemaは別asset |
| current provider loop / Windows fallback | single-provider invariantに反し、Local Spool failureをtoast successで隠す | `ProviderSpec` shapeとbounded process invocationのみ再利用 |
| `chained_notify` execution | callbackから別通知先へfan-outし得る | migration / rollback metadataとしてのみ保持 |
| temp fileをfinalとして直接更新、`File.WriteAllText`後のoverwrite move | partial visibility、same-ID race、別IDcollisionを防げずdisk flushも保証しない | installer config atomic writeとは別contract |

## 検証フック

- provider `--self-test` とschema validationで10 required fields、`result_uri: null`、`notification_status` absent、UTF-8 editor readabilityを確認する。
- isolated runtime home / spool rootで1 event、distinct IDs、same payload distinct IDs、same-ID sequential / parallel replayを実行し、final JSON数とbody identityを確認する。
- status / repositoryにWindows-invalid文字、reserved-name相当、Unicode、長文を与え、exact filename regex、UTC prefix、length bounds、body authorityを確認する。
- write / flush / move failure injectionとprovider timeoutで、final partialなし、temp best-effort cleanup、exit / stderr code、runtime log、callback exit `0`、retry成功を確認する。
- short-hash collision injection seamでdistinct ID disambiguationとsame-ID no-opを確認する。production algorithmをhash stubへ置換した結果だけで完了判定しない。
- installer temp homeでfresh install、old Windows providerからupgrade、reinstall、bin swap後failure rollback、protected backup、wrapper/self-wrapを確認する。installed configはprovider count `1`、name `local-spool`、binary/schema存在、Windows provider binary不在を確認する。
- installed runtime executableを実callback shapeで起動し、installed Local Spool providerを通してresolved production Spool folderにschema-valid final fileが現れるpostconditionを確認する。fake-only evidenceは不可。
- canonical/APM mirror hash、package validator、両workflow、`git diff --check`を確認する。

## 未解決の実装実現性項目

- Blocking itemなし。`IR-001`〜`IR-006` は本artifactのdecisionでruntime-contractへ渡せる。
- consumer / Inbox / claim / ack / retention / toast / forwardingは `OutOfScopeForThisPass`。source-backed deferでありcurrent readiness blockerではない。
- real installed callback→filesystem とfailure injectionの実行結果は未検証であり、downstream test design / implementation / verificationで `NotImplementedOrMismatch` のまま扱う。artifact decisionだけでcompletionを主張しない。

## Self-check / Readiness verdict

`READY_FOR_RUNTIME_CONTRACT`

## Self-check evidence

| Checkpoint | Evidence | Status | Notes |
| --- | --- | --- | --- |
| Plan-required path fixed | canonical provider/schema、runtime、installer、mirror addressesをexact pathで記録 | `Confirmed` | guessed external dependencyなし |
| dependency/API confirmed | .NET 10 BCL filesystem/process/mutex APIとcurrent config/provider stdinを確認 | `Confirmed` | external SDK不要 |
| persisted/input schemas separated | event-v1はprovider input、spool-item-v1は10-field body authority | `Confirmed` | `PENDING`非永続化 |
| idempotency / collision fixed | source ID mutex、body recheck、suffix extension、non-overwrite move | `Confirmed` | runtime dedupeだけに依存しない |
| atomic / failure fixed | same-directory temp、disk flush、atomic move、exit 2/3、fail-open | `Confirmed` | runtime contractでparticipant/postcondition化可能 |
| single-provider / migration fixed | provider count gate、spool-only install、legacy Windows source disposition、transaction rollback | `Confirmed` | nearest-neighbor fallback禁止 |
| fake-only completion prevented | installed callback→filesystem hookを必須化 | `Confirmed` | fake helperは限定的 reuse |
| unresolved blocker | なし | `Confirmed` | downstream evidenceは未実装として可視化 |

## Handoff Packet

- Profile used: contract-kernel
- Current phase: implementation-realization contract complete
- Plan readiness: ReadyForRiskTriage
- Documentation level: standard
- Recommended process profile: standard-slice
- Implementation route: adaptive
- Implementation route source: default
- Source artifacts: live GitHub Issue #76（2026-08-01縮小決定）、`plans/issue-76-codex-completion-local-spool-inbox-plan.md`、`plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`、`plans/issue-76-codex-completion-local-spool-inbox-change-risk-triage.md`、`.github/instructions/plan-coverage-shared.instructions.md`
- Selected contracts / IDs: `RC-001`, `RC-002`, `RC-003`; `IR-001`〜`IR-006`; `FR-001`〜`FR-010`; `AC-001`〜`AC-012`
- Files inspected: `scripts/codex-notification-runtime/codex-notification-runtime.cs`、`windows-app-notification-provider.cs`、`install-codex-notification-runtime-local.cs`、両current schema、`validate-codex-notification-runtime.ps1`の該当surface、root `README.md`のruntime section、APM package README / usage guide / validatorの該当surface、APM runtime asset file set、両validation workflowsのentrypoint
- Files intentionally not inspected: consumer / Inbox / toast / forwarding / retention実装（scope外）、repository全体、unrelated plans/packages/workflows、testsの全量、実installed user environment
- Decisions made: canonical provider/schema、portable default/override、10-field projection、exact filename/sanitization/hash、source-ID idempotency、collision disambiguation、same-directory durable atomic publish、exit/diagnostic、single-provider gate、retry/fail-open reuse、legacy Windows provider/chained notify disposition、installer upgrade/rollback、README/validator/APM syncを固定
- Do not redo unless new evidence appears: producer/consumer scope split、10-field body authority、`source_event_id` identity、single Local Spool provider、current runtime home resolution、current provider stdin / timeout / fail-open、installer staged rollback、canonical/APM checked mirror boundary
- Remaining work: `runtime-contract-kernel.agent.md` で `RC-001`〜`RC-003` のparticipant、pre/postcondition、forbidden state、diagnosticを定義し、その後 `test-design-kernel.agent.md`、`implementation-handoff-review.agent.md`。implementation permissionはまだ `No`。production code/tests/evidenceは未実装
- Residual / manual / human-decision candidates: human decisionなし。consumer/Inbox/lifecycleはsource-backed `OutOfScopeForThisPass`。real installed wiring evidenceはdownstream verification required
- Close readiness: No
- Recommended next step: `runtime-contract-kernel.agent.md`
