# Test Design Kernel

## スコープ

`plans/issue-76-codex-completion-local-spool-inbox-runtime-contract-kernel.md` で選択・定義された `RC-001`〜`RC-003` を対象とする。Plan、Black-box Behavior Spec、change-risk-triage、implementation contract を補助入力とし、Codex callback の正規化済み stdin から Local Spool provider、Windows local filesystem、installer / configuration、APM checked mirror、installed production entrypoint までの producer-side test points だけを設計する。

consumer、Inbox、claim / ack、toast、forwarding、retention、cleanup / recovery は対象に追加しない。test の実装・実行と production binding の確認は本 pass では行わない。

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `TP-001` | `RC-001` | valid completion / stop event が production projection を通ると、provider stdin の11 fieldから永続用10 fieldが exact に保存され、`resume_uri` と available / null の `result_uri` が保持される。 | No | Yes | final JSON は `spool-item-v1` にschema-validで、10 required propertyだけを持ち、`notification_status` は存在せず、`result_uri` は値またはJSON `null` である。 | Done |
| `TP-002` | `RC-001` | malformed stdin、invalid schema、relative / invalid spool pathをproviderが拒否する。 | No | Yes | provider exitは`2`、sanitized stderr diagnosticが1行生成され、final JSONとtemp fileは生成されない。 | Done |
| `TP-003` | `RC-002` | default runtime-home resolutionと明示absolute overrideで保存し、filename projectionとJSON body authorityを確認する。 | No | Yes | defaultは`CODEX_NOTIFICATION_RUNTIME_HOME\spool`または`%LOCALAPPDATA%\CodexNotificationRuntime\spool`、overrideは指定absolute rootにだけfinalを作る。filenameはUTC fixed-7 timestamp先頭、sanitized status / repository、source hashを含み、file一覧とUTF-8 JSONは通常のfile-based evidenceで読める。 | Done |
| `TP-004` | `RC-002` | 異なる`source_event_id`のeventを近接・並行投入し、同一payloadでも独立保持する。 | No | Yes | 投入したdistinct ID数と同数のschema-valid final JSONが残り、各bodyの`source_event_id`が一意で、上書き・黙示集約・全欠落がない。 | Done |
| `TP-005` | `RC-002` | 同一`source_event_id`を逐次retryおよび並行投入する。 | No | Yes | 全processがpublishedまたはidempotent-existingとして収束し、最終的にschema-valid finalがexactly one、内容非更新、corrupt / duplicate / temp finalなしとなる。 | Done |
| `TP-006` | `RC-002` | short-hash candidateを別IDのvalid bodyで事前配置してsuffix拡張を起こし、16/24/32/64候補がすべて別IDで占有されたterminal collisionも確認する。 | No | Yes | distinct IDは24/32/64 hexへ拡張した別finalへ保存され、diagnostic `filename-collision-disambiguated` が出る。64 hexまで衝突時はexit`3`、既存finalは不変、新規corrupt finalはない。 | Done |
| `TP-007` | `RC-002` | production providerのwrite、flush、move各failureを制御注入する。 | No | Yes | 各failureでprovider exitは`3`、sanitized diagnosticが出て、schema-invalid / partial finalは0件、tempはbest-effort cleanupされ、既存finalは不変である。 | Done |
| `TP-008` | `RC-001` | `TP-002` / `TP-006` / `TP-007`のproduction provider nonzeroと、hanging provider timeoutをruntime境界で発生させ、claim解放、diagnostic、retry、callback fail-openを確認する。 | Yes | Yes | invalid / collision / filesystem failure / timeoutはdelivery成功にならず`runtime.log.jsonl`へ記録され、callback exitは`0`、process treeはboundedに停止し、同じeventの次回成功でreal Local Spool finalがexactly one生成される。 | Done |
| `TP-009` | `RC-003` | runtime configがexactly one `local-spool` providerだけを許可し、0件または2件以上を拒否する。 | No | Yes | 1件時のみconfigured production providerへ配送される。0件 / 複数時はprovider非起動、`invalid-provider-count` log、callback exit`0`であり、Windows provider / `chained_notify`へのfallbackやfan-outはない。 | Done |
| `TP-010` | `RC-003` | temporary Codex homeでfresh install、reinstall、旧Windows provider構成からのupdateを実行する。 | No | Yes | top-level `notify`はinstalled runtime `dispatch`を1回だけ指し、runtime configはname `local-spool` / argv 1件 / timeout `5000`。runtime、provider、schemaがinstalled bin/configに存在し、Windows provider binaryはsuccessful installに残らず、protected original backupはreinstallで上書きされない。 | Done |
| `TP-011` | `RC-003` | stage / self-test / bin swap / config swap failureのrollbackとself-wrap保護を確認する。 | No | Yes | failureはinstall成功扱いにならずprevious bin / runtime configとprotected backupを復元する。legacy Windows providerは旧構成のrollback結果としてのみ復元可能で、successful Local Spool installの代替にはならない。self-wrapは拒否される。 | Done |
| `TP-012` | `RC-003` | canonical runtime assetsとAPM checked mirror、package validator、CI entrypointの同期を確認する。 | No | Yes | Local Spool provider/schemaと変更対象runtime / installer / docsのcanonical-to-mirror SHA-256が一致し、両validator / workflowが同じproduction asset setを検証する。legacy Windows providerのsource-only dispositionもmirrorで一致する。 | Done |
| `TP-013` | `RC-003` | isolated installed production entrypointをactual callback shapeで起動し、installed runtime→installed real provider→real local filesystemを通す。 | No | Yes | installed `config.toml` / `runtime-config.json` / binaries / schemaのproduction pathからresolved Spoolへschema-valid finalがexactly one生成される。fake provider output、source structure、adapter self-testだけではこの観測を満たさない。 | Done |
| `TP-014` | `RC-003` | real installed Windows環境でproduction Spool folderと生成JSONをfile listing / editorで確認する。 | No | Yes | resolved production Spool path、UTC-first filename一覧、editor-readable valid JSON、installed callbackからのnew finalを人が確認できる。VS Code固有automationは要求しない。 | ManualOnly |

このエージェントにおける `Done` は、このパスでの test design 行の記入が完了したことを意味する。test の実装、実行、または検証が完了したことを意味しない。

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `TP-001` | `RC-001` | none | `local-spool-provider.cs`; `spool-item-v1.schema.json` | `codex-notification-runtime.cs`のreal provider stdin→provider→final JSON | input schemaの合格だけでpersisted projectionを完了扱いにしない。 |
| `TP-002` | `RC-001` | none | production providerのvalidation / exit / diagnostic path | published provider executableとresolved Spool path | test-only parserだけでexit`2`を証明しない。 |
| `TP-003` | `RC-002` | none | production root resolution、filename projection、serializer | provider argv / environment→real filesystem directory | machine-specific path固定やfilename-only assertionを不可とする。 |
| `TP-004` | `RC-002` | none | production provider、SHA-256 identity、real filesystem publish | multiple real provider processes→same Spool directory | in-memory collectionの件数だけでは不十分。 |
| `TP-005` | `RC-002` | none | production named mutex、existing-body identity check、atomic publish | sequential / parallel production provider processes→same directory | runtime `*.delivered`だけをspool idempotency evidenceにしない。 |
| `TP-006` | `RC-002` | preseeded valid production-format files; no hash substitute | production SHA-256 / suffix expansion / collision diagnostic | real provider→real filesystem candidate files | fake hash algorithmだけの結果を不可とする。 |
| `TP-007` | `RC-002` | controlled failure injection; no filesystem substitute | production write / flush-to-disk / non-overwrite move / cleanup branches | production provider executable→real filesystem failure surface | local adapter shapeだけでatomic postconditionを証明しない。 |
| `TP-008` | `RC-001` | fake nonzero / hanging provider may exercise runtime boundary | production `InvokeProviderAsync`、claim / delivered state、bounded stderr log | installed runtime config、およびretry時のreal Local Spool provider | fake fixtureのfail-open合格だけでは不可。retry後のreal finalを必須とする。 |
| `TP-009` | `RC-003` | none | production `LoadConfig` / provider-count gate | installed `runtime-config.json`→exactly one installed `local-spool` executable | `ProviderSpec` shapeだけでは不可。 |
| `TP-010` | `RC-003` | isolated homes are allowed; no implementation substitute | production installer、runtime/provider/schema publish、legacy migration | temporary Codex `config.toml`→installed runtime/config/bin | freshだけでなくreinstall / legacy update dispositionを確認する。 |
| `TP-011` | `RC-003` | installer failure injection | production staged swap / rollback / backup / self-wrap guards | failed install state→previous installed entrypoint/config | rollbackをmock filesystemだけで証明しない。 |
| `TP-012` | `RC-003` | none | canonical assets、APM checked mirror、package validators | canonical validator / APM validator / validation workflow entrypoints | file存在だけでなくcontent hashとvalidator wiringを確認する。 |
| `TP-013` | `RC-003` | none | installed runtime/provider/schema binaries and real filesystem behavior | installed `config.toml notify`→runtime `dispatch`→single provider→resolved Spool | fake-only completion禁止の主要post-wiring evidence。 |
| `TP-014` | `RC-003` | none | real installed production artifacts | real user-level callback entrypointとproduction Spool path | verification-kernelでmanual / real-environment evidenceを記録する。 |

## 手動確認のみの項目

- `TP-014`: real installed Windows環境でCodex completion / stop callbackを1回発生させ、production Spool folderの新しいUTC-first final名、schema-validで通常editorから読める10-field JSON、`notification_status`不在を確認する。VS Code固有automationは不要で、file listing、raw JSON、schema validationの記録をevidenceとする。
- automatedな`TP-003`と`TP-013`が同じfile-based postconditionを十分に示せる場合も、real user config / actual installed entrypointの確認済みevidenceがない限り`TP-014`を`Bound`または完了扱いにしない。

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `CASE-76-001` | `RC-001`, `RC-003` | `TP-001`, `TP-013` | 一意なvalid eventから10-field schema-valid finalが1個生成され、`notification_status`は保存されず、単一providerで処理が終わる。 | AutomatedPlanned | projection test + installed end-to-end file | Done |
| `CASE-76-002` | `RC-003` | `TP-013` | consumerの有無に依存せずproduction Spool finalが残り、callbackはconsumerを起動しない。 | AutomatedPlanned | isolated installed callback with no consumer | Done |
| `CASE-76-003` | `RC-002` | `TP-004` | distinct IDsの並行eventがすべて独立finalとして残る。 | AutomatedPlanned | parallel process final count / body IDs | Done |
| `CASE-76-004` | `RC-002` | `TP-003` | file一覧からitemを識別でき、各JSONを通常editor相当のfile-based evidenceで読める。 | AutomatedPlanned | filename listing + UTF-8 parse + schema validation | Done |
| `CASE-76-005` | `RC-001` | `TP-001` | `resume_uri`とavailable / nullの`result_uri`がJSON bodyに保持される。 | AutomatedPlanned | exact persisted JSON fields | Done |
| `CASE-76-007` | `RC-003` | `TP-009`, `TP-013` | callbackの直接配送先はLocal Spool一種類で、consumer / notification fan-outを行わない。 | AutomatedPlanned | provider-count gate + installed config / final | Done |
| `CASE-76-008` | `RC-003` | `TP-010`, `TP-013` | Windows通知履歴やWindows providerに依存せずSpool finalが残る。 | AutomatedPlanned | installed asset/config absence + final file | Done |
| `CASE-76-009` | `RC-001` | `TP-008` | provider failure / timeoutでもcallbackはboundedにexit`0`し、失敗を記録してretry可能となる。 | AutomatedPlanned | runtime exit/log/claim + retry final | Done |
| `CASE-76-010` | `RC-001`, `RC-002` | `TP-007`, `TP-008` | filesystem failure時に壊れたfinalを残さずproviderは失敗し、callbackはfail-openしてretry可能となる。 | AutomatedPlanned | real failure surface + runtime retry evidence | Done |
| `CASE-76-011` | `RC-002` | `TP-005` | same IDの逐次retryはfinalを増殖・更新しない。 | AutomatedPlanned | before/after count and content hash | Done |
| `CASE-76-012` | `RC-002` | `TP-005` | same IDの並行競合後もschema-valid finalがexactly one残る。 | AutomatedPlanned | concurrent process results + one final | Done |
| `CASE-76-013` | `RC-002` | `TP-004` | same payloadでもdistinct IDは別eventとしてすべて残る。 | AutomatedPlanned | distinct body IDs / final count | Done |
| `CASE-76-017` | `RC-002` | `TP-003`, `TP-006` | filenameはWindows-safeなUTC-first projectionで、bodyがauthorityとなり、collision時もdistinct itemを保持する。 | AutomatedPlanned | filename grammar/order + body/schema + collision files | Done |
| `CASE-76-021` | `RC-002` | `TP-007` | write / flush / move failureでpartial / corrupt finalを公開しない。 | AutomatedPlanned | injected real-filesystem failure artifact listing | Done |
| `CASE-76-024` | `RC-003` | `TP-010`, `TP-011` | legacy Windows provider / chained notify環境をsingle Local Spoolへupdateし、失敗時だけprevious構成へrollbackできる。 | AutomatedPlanned | legacy update and rollback snapshots | Done |
| `CASE-76-025` | `RC-001`, `RC-002` | `TP-001`, `TP-005` | identityは`source_event_id`、bodyは`observed_status`を保持し、transient `PENDING`をauthorityにしない。 | AutomatedPlanned | exact fields + same-ID replay | Done |
| `CASE-76-026` | `RC-003` | `TP-009`, `TP-010`, `TP-013` | installer / configurationがsingle Local Spool providerをproduction callbackへ結び、observable finalを生成する。 | AutomatedPlanned | installed config/binaries + real filesystem final | Done |

`DeferredWithSource` の `CASE-76-006`, `014`〜`016`, `018`〜`020`, `022`, `023`, `027`, `028` と、`OutOfScopeWithSource` の `CASE-76-029` はselected producer implementation scope外なので、本mappingへ追加していない。

## 注記 / 前提

- `RC-001`〜`RC-003`と`TP-001`〜`TP-014`はstable IDとして扱い、selected外のRuntime Contract IDは追加していない。
- full-coverage escalationは不要である。3 contractsはcallback→provider→filesystemとinstaller / configuration / mirror bindingのboundedな一本のproducer chainで、implementation contractがprojection、identity、collision、atomic failure、migration / rollbackを具体化済みである。feature全体、load / long-running coverage、cross-slice architecture、既存integration suite全体の設計を必要としない。
- `TP-008`だけは既存conventionに合わせてfake / hanging providerをruntime boundary fixtureとして許容するが、production retry先のreal provider / filesystem postconditionを同じtest pointの必須観測とし、`TP-013`を別のno-substitute installed evidenceとして設計した。
- controlled failure injectionはproduction provider / installerの実際のfailure branchを再現する手段であり、in-memory filesystemやalternative providerによるsubstitute evidenceだけでは完了しない。
- `Bound`は判断していない。production provider/schema、single-provider gate、installer / mirror、installed callback→filesystemは現時点で`NotImplementedOrMismatch`または未検証であり、downstream implementation後のverification対象である。
- test実装の詳細、fixture API、failure injection mechanismはimplementation ownerが既存validator conventionに沿って具体化する。本artifactは方式を追加決定しない。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: `.agents/skills/plan-coverage-residual-flow/SKILL.md`、`.github/instructions/plan-coverage-shared.instructions.md`、`plans/issue-76-codex-completion-local-spool-inbox-plan.md`、`plans/issue-76-codex-completion-local-spool-inbox-black-box-behavior-spec.md`、`plans/issue-76-codex-completion-local-spool-inbox-change-risk-triage.md`、`plans/issue-76-codex-completion-local-spool-inbox-implementation-contract-kernel.md`、`plans/issue-76-codex-completion-local-spool-inbox-runtime-contract-kernel.md`
- Selected contracts / IDs: `RC-001`, `RC-002`, `RC-003`; `TP-001`〜`TP-014`
- Files inspected: `scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`のfake provider、parallel / retry / timeout、installer / reinstall / rollback近傍、`apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1`のmirror / installed-asset / fake-provider近傍、両validation workflow entrypoint、既存`plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-SL-001-test-design-kernel.md`のID / table convention
- Files intentionally not inspected: production source本文の追加探索とtest suite全量（upstream contractsと近傍validatorでtest designに十分）、consumer / Inbox / toast / forwarding / retention source（source-backed scope外）、unrelated plans / packages / workflows、実installed user environment（本agentは実行・binding verificationを行わない）
- Decisions made: projection / invalid input、root / filename / editor-readable evidence、distinct / same-ID concurrency、collision、write / flush / move failure、runtime retry / fail-open、exactly-one provider、install / reinstall / update / rollback / legacy disposition、APM mirror、real installed entrypointへstable TPを割り当てた。fake許容点にもproduction bindingを必須化し、real provider / filesystem / install evidenceを別に保持した。full-coverageは不要
- Behavior case coverage: `MappedToPlan`の`CASE-76-001`〜`005`, `007`〜`013`, `017`, `021`, `024`〜`026`をすべて`AutomatedPlanned`へmapping。deferred / out-of-scope Casesには拡張していない。`TP-014`はreal-environment補助evidenceとして`ManualOnly`
- Do not redo unless new evidence appears: selected `RC-001`〜`RC-003`、stable `TP-001`〜`TP-014`、17 producer Caseのmapping、fake providerをruntime failure fixtureに限定する判断、installed real provider / filesystem postconditionの必須性、full-coverage不要判断
- Remaining work: `NotImplementedOrMismatch`のproduction provider/schema/runtime gate/installer/APM mirrorとtest pointsを実装し、`TP-001`〜`TP-013`を実行する。`TP-014`のreal installed evidenceは`ManualOnly`。production binding / wiringは未確認、implementation permissionはNo、close readinessはNo
- Recommended next step: `implementation-handoff-review.agent.md`へPlan、Behavior Spec、change-risk-triage、implementation contract、runtime contract、本Test Design Kernel、`RC-001`〜`RC-003`を渡し、pre-implementation gateとParent Plan coverageを確認する。verification-kernelはimplementation後であり、次段ではない
