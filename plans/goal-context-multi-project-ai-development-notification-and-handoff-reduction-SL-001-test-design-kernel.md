# Test Design Kernel: SL-001

## スコープ

`SL1-RC-001`〜`SL1-RC-004`を対象に、`NTF-001`〜`NTF-008`、`REV-013` consumer、`SCP-003`のcoverage routeを定義する。テスト実装・実行・production bindingの完了判定は行わない。

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `SL1-TP-001` | `SL1-RC-001` | marker/envelopeなしのvalid callbackがgeneric eventを作る。 | Yes | Yes | `codex://threads/<thread-id>`を含む一件のgeneric event。 | Done |
| `SL1-TP-002` | `SL1-RC-002` | valid envelopeはdual actionを追加し、invalid/missing envelope又はunsafe URIはthread-only generic eventへfallbackする。 | Yes | Yes | result actionはoptional、current-task actionは常に残る。 | Done |
| `SL1-TP-003` | `SL1-RC-003` | replay、parallel claim、provider/chain failure、timeoutで親callbackがnonzeroにならず、適切にdedup/retryする。 | Yes | Yes | duplicateは一回のみdelivery、failure後はretry可能、parent callback exitはzero。 | Done |
| `SL1-TP-004` | `SL1-RC-003` | Windows providerのURI safetyとbutton orderingを確認する。 | Yes | Yes | concrete HTTPS result + current taskの二button、unsafe/coarse URIはcurrent taskのみ。 | Done |
| `SL1-TP-005` | `SL1-RC-004` | isolated homeでinstall/update/check/rollback/self-wrap rejectとAPM package asset availabilityを確認する。 | No | Yes | existing notify保持、top-level TOML、rollback、package install後にruntime assets/docsを利用可能。 | Done |
| `SL1-TP-006` | `SL1-RC-002` | real Windows/Codexでnormal parent terminalのthread/result actionを操作し、subagent notification count/targetを記録する。 | No | Yes | user-visible actionsとparent-centric notification observation。 | ManualOnly |

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `SL1-TP-001` | `SL1-RC-001` | fake provider callback fixture | runtime source / published binary | user-level `notify` invokes installed runtime | fixture successだけでは不十分。 |
| `SL1-TP-002` | `SL1-RC-002` | fake provider and schema fixture | runtime parser, envelope schema, provider | installed runtime → provider | `XC-001` producer integrationはDeferred。 |
| `SL1-TP-003` | `SL1-RC-003` | fake provider / chained command | claim state and provider invocation | installed runtime config provider/chain argv | chain/provider failure must remain observational. |
| `SL1-TP-004` | `SL1-RC-003` | provider self-test may be used | Windows provider source / published binary | Windows App Notification support in actual environment | manual click is additionally required. |
| `SL1-TP-005` | `SL1-RC-004` | no substitute | installer and APM package assets | temporary Codex home and APM install/update/check path | production distribution must be verified. |
| `SL1-TP-006` | `SL1-RC-002` | no substitute | installed runtime/provider | real Codex callback and Windows notification UI | close gate; no fake-only substitute. |

## 手動確認のみの項目

- `SL1-TP-006`: normal parent callback、thread button、result buttonの実機操作。
- `XC-002` / `NTF-005`: real parent + reviewer subagent executionのnotification count / target。spamを観測した場合はclose blockerとする。
- `XC-001` / `NTF-003` / `REV-013`: `SL-002` producer完成後に同一parent threadとcurrent PRの両導線を確認する。

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `NTF-001` | `SL1-RC-001` | `SL1-TP-001` | ordinary parent callback has one thread-link notification. | AutomatedPlanned | runtime fixture + installed callback | Done |
| `NTF-002` | `SL1-RC-001` | `SL1-TP-001` | blocked/human-stop callback also becomes generic notification. | AutomatedPlanned | status fixture | Done |
| `NTF-003` | `SL1-RC-002` | `SL1-TP-002`, `SL1-TP-006` | result and thread actions coexist. | DeferredWithReason | `XC-001` integration + manual click | Deferred |
| `NTF-004` | `SL1-RC-002` | `SL1-TP-002` | invalid/missing result retains thread action. | AutomatedPlanned | parser/provider fixture | Done |
| `NTF-005` | none | `SL1-TP-006` | parent-centric notifications do not scale with subagents. | ManualOnly | `XC-002` real Codex smoke | ManualOnly |
| `NTF-006` | `SL1-RC-003` | `SL1-TP-003` | replay does not duplicate notification. | AutomatedPlanned | replay/parallel fixture | Done |
| `NTF-007` | `SL1-RC-003` | `SL1-TP-003` | provider/chain failure does not fail parent turn. | AutomatedPlanned | failure/timeout fixture | Done |
| `NTF-008` | `SL1-RC-004` | `SL1-TP-005` | one installation enables normal notifications while retaining existing notify. | AutomatedPlanned | isolated install/APM smoke | Done |
| `REV-013` | `SL1-RC-002` | `SL1-TP-002`, `SL1-TP-006` | terminal review retains parent thread and optional PR action. | DeferredWithReason | `XC-001` producer/consumer integration | Deferred |
| `SCP-003` | none | none | APM distribution continues; Plugin migration is excluded. | OutOfScopeWithSource | manifest/package coverage | Done |

## 注記 / 前提

- `Done` はtest design行が完成した意味で、test実装・実行・production bindingの証明ではない。
- `SL1-TP-001`〜`005`でfake fixtureを使える場合も、installed runtime、provider、TOML notify、APM asset distributionのproduction binding確認を必須とする。
- `XC-001` / `XC-002`はslice-local automated evidenceでは完了にしない。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: SL-001 runtime/implementation contracts、parent Plan、Behavior Spec、Decomposition、SL-001 Bounded Plan。
- Selected contracts / IDs: `SL1-RC-001`〜`SL1-RC-004`; `SL1-TP-001`〜`SL1-TP-006`。
- Files inspected: runtime validator、package validator/fixtures、schemas、runtime/provider/installer。
- Files intentionally not inspected: unrelated test suites、SL-002 tests、live Windows/Codex environment。理由はbounded design scope外であるため。
- Decisions made: all substitute-based checks have production binding requirements; real UI/callback and cross-slice cases remain manual/deferred.
- Behavior case coverage: `NTF-001`〜`008` mapped; `REV-013` deferred via `XC-001`; `SCP-003` out of scope by source.
- Do not redo unless new evidence appears: stable `SL1-TP-*` mapping and manual/cross-slice dispositions.
- Remaining work: test implementation/execution, production binding verification, `XC-001` integration, `XC-002` manual smoke.
- Recommended next step: parent authorization, then `implementation-handoff-review.agent.md` followed by Adaptive implementation.
