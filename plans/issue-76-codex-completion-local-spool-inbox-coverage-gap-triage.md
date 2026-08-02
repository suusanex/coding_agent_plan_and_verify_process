# Coverage Gap Triage

## スコープ

Source A の `plans/issue-76-codex-completion-local-spool-inbox-verification-kernel.md` を使用し、caller が明示した `VK-76-001`〜`VK-76-009` を triage 対象とした。Source A に unresolved items が存在するため、integration-test coverage artifact との merge は行っていない。

分類では Source A の `Runtime contract 検証`、`Parent Plan smoke scan`、`Stub-to-Production Binding 確認`、`テスト観測結果`、`未解決項目`を正規化した。`Stub-to-Production Binding 確認`には unresolved row がないため、追加 item はない。参照 authority は次に限定した。

- Plan: `plans/issue-76-codex-completion-local-spool-inbox-plan.md`
- Runtime Contract Kernel: `plans/issue-76-codex-completion-local-spool-inbox-runtime-contract-kernel.md` (`RC-001`〜`RC-003`)
- Test Design Kernel: `plans/issue-76-codex-completion-local-spool-inbox-test-design-kernel.md` (`TP-001`〜`TP-014`)
- Implementation Contract Kernel: `plans/issue-76-codex-completion-local-spool-inbox-implementation-contract-kernel.md` (`IR-001`〜`IR-006`)

本 pass は `triage-only` であり、production code、test code、Plan、contract artifact、verification artifact の修復または status 更新は行わない。

## Gap 分類

| ID | Current status | Plan requirement / contract | Gap type | Suggested next action | Recommended target profile |
| --- | --- | --- | --- | --- | --- |
| `VK-76-001` | `NotImplementedOrMismatch` / `fails` | `FR-001`, `FR-010`; `AC-001`, `AC-012`; `RC-001`; `TP-002`; `IR-001` | `ContractMismatch` | `Runtime contract 検証`の `RC-001` input validation rows、`Parent Plan smoke scan`の `PSS-005`、`テスト観測結果`の `TP-002`、`未解決項目`の本 ID を対象に、production provider の11-field stdin validationを contract と一致させる。required `notification_status`欠落を含む invalid inputをexit `2`で拒否し、final/temp非生成を automated oracle で確認する。 | `fix-slice` |
| `VK-76-002` | `PartiallyDone` | `FR-001`; `AC-002`; `RC-001`; `TP-001`; `IR-001` | `TestOracleMissing` | `テスト観測結果`の `TP-001` と `未解決項目`の本 ID を対象に、canonical validator の `Assert-Item` へ `resume_uri` と value/null の `result_uri` のexact assertionを追加し、10-field projectionのoracleを完成させる。 | `fix-slice` |
| `VK-76-003` | `PartiallyDone` | `FR-002`, `FR-003`; `AC-003`, `AC-004`; `RC-002`; `TP-004`, `TP-005`; `IR-003` | `TestOracleMissing` | `テスト観測結果`の `TP-004`, `TP-005` と `未解決項目`の本 ID を対象に、distinct-ID parallel投入、production provider直接のsame-ID race、existing finalの内容非更新を検証する process-level oracleを追加する。 | `fix-slice` |
| `VK-76-004` | `PartiallyDone` / `missing` | `FR-003`, `FR-005`; `AC-004`, `AC-006`; `RC-002`; `TP-006`; `IR-003` | `TestOracleMissing` | `Runtime contract 検証`の collision behavior row、`テスト観測結果`の `TP-006`、`未解決項目`の本 ID を対象に、valid bodyで16/24/32/64候補を占有するcollision oracleを追加し、suffix expansion、terminal exit `3`、既存final不変を観測する。 | `fix-slice` |
| `VK-76-005` | `PartiallyDone` | `FR-004`; `AC-005`, `AC-010`; `RC-002`; `TP-007`; `IR-004` | `TestOracleMissing` | `Runtime contract 検証`の write / flush / move failure row、`テスト観測結果`の `TP-007`、`未解決項目`の本 ID を対象に、production providerのwrite、flush、move各failure surfaceを個別に観測し、exit `3`、partial final不在、temp best-effort cleanup、既存final不変をassertする。 | `fix-slice` |
| `VK-76-006` | `PartiallyDone` / `missing` | `FR-007`, `FR-008`; `AC-009`, `AC-010`; `RC-001`; `TP-008`; `IR-004` | `TestOracleMissing` | `Runtime contract 検証`の timeout / nonzero / retry row、`テスト観測結果`の `TP-008`、`未解決項目`の本 ID を対象に、`InvokeProviderAsync`のnonzero / timeout、process-tree停止、claim release、callback exit `0`、次回real provider retryでexactly one finalを観測する。fake / hanging providerはruntime boundary fixtureに限定する。 | `fix-slice` |
| `VK-76-007` | `PartiallyDone` / `missing` | `FR-007`, `FR-009`, `FR-010`; `AC-001`, `AC-008`, `AC-011`; `RC-003`; `TP-009`〜`TP-011`, `TP-013`; `IR-005`, `IR-006` | `TestOracleMissing` | `Runtime contract 検証`の update / rollback / installed callback rows、`テスト観測結果`の `TP-009`〜`TP-011`, `TP-013`、`未解決項目`の本 ID を対象に、0/multiple provider非起動、reinstall、legacy update、rollback matrix、installed runtime→installed provider→real filesystemのpostconditionを追加する。 | `fix-slice` |
| `VK-76-008` | `ManualOnly` / `manual-only; not run in this pass` | `FR-006`; `AC-007`; `RC-003`; `TP-014` | `ManualEnvironmentRequired` | `Runtime contract 検証`と `テスト観測結果`の `TP-014`、`未解決項目`の本 ID を対象に、real installed Windows callback、resolved production Spool folder、UTC-first file listing、editor-readable JSONを誰がどの環境で確認するか explicit に決定する。 | `triage-only` |
| `VK-76-009` | `NotImplementedOrMismatch` | `FR-001`, `FR-007`, `FR-010`; `AC-001`, `AC-008`, `AC-012`; `RC-001`, `RC-003`; `IR-001`, `IR-005`, `IR-006` | `PlanProhibitedPatternDetected` | `Parent Plan smoke scan`の `PSS-005`, `PSS-006` と `未解決項目`の本 ID を対象に、invalid inputからfinalをpublishする禁止状態を `VK-76-001` のcontract fixで除去し、root `README.md:140` の旧Windows provider / chain説明をsingle Local Spool contractへ同期する。 | `fix-slice` |

## 推奨修正スライス

| Slice | Included ID(s) / gap type(s) | Why grouped | Target files / addresses | Recommended agent | Recommended profile | Preconditions / human decision needed |
| --- | --- | --- | --- | --- | --- | --- |
| Provider contract・automated oracle・smoke sync | `verification-kernel.md#未解決項目: VK-76-001 / ContractMismatch`; `VK-76-002`〜`VK-76-007 / TestOracleMissing`; `VK-76-009 / PlanProhibitedPatternDetected`。関連 row は `Runtime contract 検証: RC-001`〜`RC-003`、`Parent Plan smoke scan: PSS-005, PSS-006`、`テスト観測結果: TP-001, TP-002, TP-004`〜`TP-011, TP-013` | すべて同一 Local Spool producer boundaryと、そのcanonical/APM validator・documentation mirrorを対象にする。provider input contract修正後の同一 automated validation passで、projection、race/collision/atomic failure、timeout/retry、installer matrix、installed callback、禁止patternの解消をまとめて再観測できる。 | canonical / APM mirror `local-spool-provider.cs`; `scripts/codex-notification-runtime/completion-notification-event-v1.schema.json`; `scripts/codex-notification-runtime/validate-codex-notification-runtime.ps1`; `scripts/codex-notification-runtime/codex-notification-runtime.cs` の `InvokeProviderAsync`; `tests/fake-notification-command.ps1`; `scripts/codex-notification-runtime/install-codex-notification-runtime-local.cs`; `apm-packages/completion-notification-decorator/.apm/skills/completion-notification-decorator/assets/codex-notification-runtime/`; `apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1`; root `README.md:140` | `coverage-gap-resolution-slice.agent.md` | `fix-slice` | なし。`VK-76-008`のhuman decisionとは独立して開始できる。selected IDsとtargetsからscopeを広げない。 |
| Real installed Windows evidence disposition | `verification-kernel.md#Runtime contract 検証: TP-014 / ManualEnvironmentRequired`; `#テスト観測結果: TP-014 / ManualEnvironmentRequired`; `#未解決項目: VK-76-008 / ManualEnvironmentRequired` | automated fixと独立したreal user environment / editor observationであり、実行 owner と evidence method のexplicit decisionが必要となる。 | real user `config.toml`; installed runtime/provider/schema; `%LOCALAPPDATA%\CodexNotificationRuntime\spool`;通常のeditor | `residual-decision-gate.agent.md` | `triage-only` | human decision required。`ManualVerificationDelegated`、`DeferredWithOwner`、`AbortedWithReason`等の許可された disposition を explicit に選び、必要ならowner、環境、evidenceを指定してからmanual verificationへ進む。 |

## 人間の判断が必要な項目

| ID | Gap type | Decision needed | Suggested action |
| --- | --- | --- | --- |
| `VK-76-008` | `ManualEnvironmentRequired` | `TP-014`のreal installed Windows callback / production Spool folder / editor確認を実施するか、誰にどの環境とevidence methodで委任するか、またはowner付きdefer / reason付きabortとするか。 | automated fix sliceと再verificationを妨げず独立に進める。その後 `residual-decision-gate.agent.md` へ本 ID を渡し、manual residualをexplicitに dispositionする。 |

## Handoff Packet

- Profile used: triage-only
- Source artifact type: verification-kernel
- Source artifact: `plans/issue-76-codex-completion-local-spool-inbox-verification-kernel.md`
- Reference artifacts: `plans/issue-76-codex-completion-local-spool-inbox-plan.md`; `plans/issue-76-codex-completion-local-spool-inbox-runtime-contract-kernel.md`; `plans/issue-76-codex-completion-local-spool-inbox-test-design-kernel.md`; `plans/issue-76-codex-completion-local-spool-inbox-implementation-contract-kernel.md`
- Items reviewed: `VK-76-001`〜`VK-76-009`
- Downstream selectors: `plans/issue-76-codex-completion-local-spool-inbox-verification-kernel.md#Runtime contract 検証 + #テスト観測結果 + #未解決項目: VK-76-001 / ContractMismatch / canonical・APM mirror local-spool-provider.cs, completion-notification-event-v1.schema.json, TP-002`; `#テスト観測結果 + #未解決項目: VK-76-002 / TestOracleMissing / canonical validator Assert-Item, TP-001`; `#テスト観測結果 + #未解決項目: VK-76-003 / TestOracleMissing / canonical validator・provider process tests, TP-004・TP-005`; `#Runtime contract 検証 + #テスト観測結果 + #未解決項目: VK-76-004 / TestOracleMissing / canonical validator・provider collision candidates, TP-006`; `#Runtime contract 検証 + #テスト観測結果 + #未解決項目: VK-76-005 / TestOracleMissing / canonical provider・validator failure surfaces, TP-007`; `#Runtime contract 検証 + #テスト観測結果 + #未解決項目: VK-76-006 / TestOracleMissing / runtime InvokeProviderAsync・fake helper・real provider retry, TP-008`; `#Runtime contract 検証 + #テスト観測結果 + #未解決項目: VK-76-007 / TestOracleMissing / installer・runtime・canonical/APM validators, TP-009〜TP-011・TP-013`; `#Runtime contract 検証 + #テスト観測結果 + #未解決項目: VK-76-008 / ManualEnvironmentRequired / real user config.toml・%LOCALAPPDATA%\CodexNotificationRuntime\spool, TP-014`; `#Parent Plan smoke scan + #未解決項目: VK-76-009 / PlanProhibitedPatternDetected / provider validation・README.md:140, PSS-005・PSS-006`
- Items intentionally not reviewed: Source A が source-backed defer / out-of-scope とした `CASE-76-006`, `CASE-76-014`〜`CASE-76-016`, `CASE-76-018`〜`CASE-76-020`, `CASE-76-022`, `CASE-76-023`, `CASE-76-027`, `CASE-76-028`, `CASE-76-029`、および consumer / Inbox / toast / forwarding / retention scope。caller-selected `VK-76-001`〜`VK-76-009`外であり、本 triage でscopeを広げないため。
- Decisions made: `VK-76-001`をreal production implementationと`RC-001`の `ContractMismatch`、`VK-76-002`〜`VK-76-007`をplanned automated observationの欠落・不完全による `TestOracleMissing`、`VK-76-008`をreal environmentが必要な `ManualEnvironmentRequired`、`VK-76-009`をselected production/doc addressにある `PlanProhibitedPatternDetected` と分類した。automated 8 itemsを1 bounded fix sliceにまとめ、manual itemを独立させた。
- Do not redo unless new evidence appears: required `notification_status`欠落probeがexit `0`かつfinal 1件を生成したという Source A evidence、production provider/runtime/installer wiringが存在するというSource A判断、`VK-76-002`〜`VK-76-007`の不足oracle一覧、`TP-014`がreal installed environmentを要求すること、`PSS-005`と`PSS-006`のblocking observation。
- Remaining work: `VK-76-001`〜`VK-76-007`, `VK-76-009`のbounded automated repairと再verification。`VK-76-008`はhuman decisionと、そのdecisionが要求するmanual evidenceまたはexplicit residual dispositionが未完了。
- Recommended next step: 1. `coverage-gap-resolution-slice.agent.md`へ automated selector `VK-76-001`〜`VK-76-007`, `VK-76-009` と上記target addressesを渡す。2. 修復後に `verification-kernel.agent.md`を同じ `RC-001`〜`RC-003`, `TP-001`〜`TP-014`で再実行する。3. `residual-decision-gate.agent.md`へ `VK-76-008` / `TP-014`を渡し、manual verificationのdelegation / defer / abortをexplicitに決定する。automated fix sliceは `VK-76-008` のdecisionを待たず開始できる。
