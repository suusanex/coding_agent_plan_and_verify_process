# Implementation Contract Kernel: SL-001

## スコープ

`SL-001` の notification runtime、Windows provider、installer、completion-notification-decorator APM package、notification documentation の実現性を確認する。実装とテスト作成は行わない。

## Plan が要求する実装要件

| Requirement | Expected by Plan | Evidence found | Status |
| --- | --- | --- | --- |
| `SL1-FR-001` | valid callbackを marker / envelopeなしでも generic candidate にする。 | `CreateCandidate` は現在 envelopeなしを抑止している。変更先は確認済み。 | Confirmed |
| `SL1-FR-002` | callback identityを保持し、valid envelopeだけが display/resultをenrichする。 | `TryReadEnvelope`、`IsAllowedResultUri`、provider button constructionが存在する。 | Confirmed |
| `SL1-FR-003` | existing notifyを保持した always-on install と APM distribution。 | installerは chain / backup / rollback / self-wrap rejectを持つ。packageは現状runtime sourceを配布しない。 | Confirmed |
| `SL1-FR-004` | dedup / timeout / provider / chain failureをobservationalにし、subagent scopeは観測する。 | runtimeのclaim/deliveredとfail-open、validatorのfailure fixtureが存在する。subagent observationはmanual-only。 | Confirmed |

## Dependency と API surface の確認結果

| Dependency / API / symbol | Expected source | Found location | Status | Notes |
| --- | --- | --- | --- | --- |
| `agent-turn-complete`, `thread-id`, `turn-id` | Codex callback | `codex-notification-runtime.cs` `CodexPayload` | Confirmed | callback identityは envelopeから導出しない。 |
| generic candidate decision | runtime | `CreateCandidate` | Confirmed | marker/envelope gatingをgeneric defaultへ変更する必要がある。 |
| optional envelope v1 | schema/parser | envelope schema、`TryReadEnvelope` | Confirmed | `primary_process` / `observed_status` は valid enrichmentでのみ必要。 |
| event v1 and provider actions | event schema/provider | event schema、`windows-app-notification-provider.cs` | Confirmed | resultはoptional、resumeは必須。 |
| user-level `notify` wiring | installer | `install-codex-notification-runtime-local.cs` | Confirmed | TOML top-level replacement、chain、backup、rollback、`--check`。 |
| APM package distribution | package manifest and includes | `apm.yml`、package README | Confirmed | sourceをコピーしない現行方針は `SL1-AC-005` と不一致。package assets/installer/docsを更新対象にする。 |

## 選択した実装アプローチ

1. `CreateCandidate` を、valid callbackならgeneric eventを先に作る経路へ変更する。generic fieldsは runtime fixed defaults と `cwd` からの repository resolve を使い、`resume_uri` は callback `thread-id` のみから作る。
2. envelope parsingは optional enrichmentに限定する。valid envelopeは process/status/title/resultを補完できるが、`thread-id`、`turn-id`、`resume_uri`、dedup identityを上書きできない。不正又は欠落したenvelopeは generic fallbackを配送する。
3. providerは result actionがある場合も current-task actionを保持し、unsafe/coarse result URIを棄却する。delivery、chain、timeout、dedup claimの失敗は非zeroをCodexへ返さない。
4. installerは always-on configとして marker依存を除去し、existing notify chain、backup/rollback、self-wrap reject、checkを維持する。runtime/provider/installer/schema/docsを APM-installed assetとして利用可能にするため、package include/installer/doc contractを整える。

## 必要なコード変更

- `scripts/codex-notification-runtime/codex-notification-runtime.cs`: generic candidate、optional enrichment、fallback diagnostics、self-testをSL-001 contractへ合わせる。
- `scripts/codex-notification-runtime/completion-notification-event-v1.schema.json` と `completion-notification-envelope-v1.schema.json`: generic fieldsとoptional enrichmentのschema整合を確認し、必要な最小変更を行う。
- `scripts/codex-notification-runtime/windows-app-notification-provider.cs`: thread action常存とresult actionの安全性を維持・検証する。
- `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs`: marker defaultを前提にしない常時 wiring、chain/rollback/self-wrap/checkを維持する。
- `scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`: ordinary markerless callback、invalid envelope fallback、install/update/check/rollbackを検証するfixtureへ更新する。
- `apm-packages/completion-notification-decorator/`: manifest/includes、package install test、validator、README/docs/Skill referenceを runtime assetsの配布とDecorator optional compatibilityへ更新する。
- `README.md`: normal notificationの導入/check、Decorator不要、manual evidence boundaryを同期する。

## 禁止される代替実装

| Similar existing path | Why it is not sufficient | Allowed reuse, if any |
| --- | --- | --- |
| marker-only `TargetMarkers` gating | ordinary callbackを抑止し `FR-001` / `ARCH-INV-001` に反する。 | `RejectedSubstitute`; diagnostics互換としてのみ扱う。 |
| envelope-required candidate | `NTF-001`、`NTF-004`のgeneric/fallback契約に反する。 | `RejectedSubstitute`; schema/parserはoptional enrichmentで再利用可。 |
| Decorator Skillを通常通知の必須入口にする | per-task Skill selectionを要求し `INV-002` に反する。 | `RejectedSubstitute`; explicit compatibility authoringのみ `AllowedReuse`。 |
| result URIをresume identityに用いる | callback identity precedenceと `ARCH-INV-002` に反する。 | `RejectedSubstitute`; result buttonのみ `AllowedReuse`。 |
| subagent hierarchy filterの推測 | official callback fieldに根拠がなく `XC-002` manual-onlyを迂回する。 | `RejectedSubstitute`。 |

## 検証フック

- `SL1-TP-001`〜`SL1-TP-004`: markerless generic callback、optional enrichment/fallback、dedup/fail-open、provider dual action。
- `SL1-TP-005`: isolated install/update/check/rollback/self-wrapと APM package install。
- `SL1-TP-006`: real Windows/Codex manual smoke。`XC-001` / `XC-002` はcross-slice/manual evidenceとして扱う。

## 未解決の実装実現性項目

- `XC-001` terminal envelope producerは `SL-002` ownershipであり `Deferred`。consumer parserは本sliceで準備するが、producer integrationはcross-slice verificationまで未完了。
- `XC-002` callback hierarchy / notification countは `ManualOnly`。推測filterは実装しない。
- package asset layoutの具体的なinclude pathは実装中に決める `AR-005` implementation detailであり、runtime assetsをpackage installで利用可能にするというPlan contractは固定する。

## Self-check / Readiness verdict

READY_FOR_RUNTIME_CONTRACT

## Self-check evidence

| Checkpoint | Evidence | Status | Notes |
| --- | --- | --- | --- |
| Plan-required path | runtime、provider、installer、package、docsの変更先を確認した。 | Confirmed | guessed production addressなし。 |
| Source-of-truth alignment | current marker/envelope gatingをPlan mismatchとして明示した。 | Confirmed | nearby behaviorを採用しない。 |
| Cross-slice authority | `XC-001` producerと`XC-002` real smokeをdefer/manualに保持した。 | Confirmed | local completion扱いしない。 |
| External decision | provider/SDK/APIの新規選択は不要。 | Confirmed | 人手判断は不要。 |

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: parent Plan、Behavior Spec、parent/per-slice triage、Readiness、Slice Architecture、Decomposition、SL-001 Bounded Plan。
- Selected contracts / IDs: `SL1-RC-001`〜`SL1-RC-004`、`XC-001` consumer、`XC-002` manual consumer/verification。
- Files inspected: notification runtime、provider、installer、schemas、runtime validator、Decorator APM manifest/README/validator/fixtures、root README。
- Files intentionally not inspected: `SL-002` source、unrelated APM packages、live Codex provider。理由はselected sliceの実現性確認に不要なため。
- Decisions made: generic default / optional enrichment / callback identity precedence / fail-open / package production distribution。
- Do not redo unless new evidence appears: current production addressesと、marker/envelope-required behaviorがPlan mismatchであるという判断。
- Remaining work: runtime/test-design downstream artifacts、parent authorization、Adaptive implementation、verification、`XC-001` integration、`XC-002` manual smoke。
- Recommended next step: `runtime-contract-kernel.agent.md` using this artifact, then `test-design-kernel.agent.md`.
