# SL-001 Change Risk Triage

## スコープ

`SL-001` の Always-on Codex completion notification だけを対象にする。親 Plan の `FR-001`〜`FR-004`、`FR-009` consumer、`FR-012` notification distribution と、`AC-001`〜`AC-005`、`AC-011` consumer、`AC-012`、`AC-013` を縮小せずに扱う。

## Plan readiness check

| Check | Result | Evidence |
| --- | --- | --- |
| Slice authority | Ready | `slice-SL-001.md` の Goal、FR、AC、Case-to-Slice mapping。 |
| Behavior expansion | Ready | `black-box-behavior-spec.md` の `NTF-001`〜`NTF-008`、`REV-013`、`SCP-003`。 |
| Architecture authority | ReadyForSliceDecomposition | Slice Architecture の `ARC-RC-001`〜`004`、`009` と `ARCH-INV-001`〜`005`、`010`。 |
| Implementation route metadata | Confirmed | `implementation_route: adaptive`、`implementation_route_source: default`。 |

## Risk inventory

| Risk ID | Boundary | Risk | Evidence | Disposition |
| --- | --- | --- | --- | --- |
| `SL1-RISK-001` | callback to runtime | 現行 `CreateCandidate` は envelope 不在時に `not-targeted` / `awaiting-terminal-envelope` を返し、ordinary callback を抑止する。 | `scripts/codex-notification-runtime/codex-notification-runtime.cs`。 | Present; `SL1-RC-001` で修正契約化。 |
| `SL1-RISK-002` | optional enrichment | envelope が callback identity を上書きする、又は不正 envelope が generic event を失わせる危険。 | `ARC-RC-001`、`ARC-RC-002`、`ARCH-INV-002`、`003`。 | Present; `SL1-RC-002`。 |
| `SL1-RISK-003` | runtime to provider | result action が thread action を置換する、再送・provider failure が親 turn を失敗にする危険。 | runtime/provider source、`ARCH-INV-002`、`004`。 | Present; `SL1-RC-003`。 |
| `SL1-RISK-004` | installer and package | marker-dependent TOML wiring、self-wrap、rollback、canonical runtimeを package から配布できない危険。 | installer source、package README、`ARC-RC-004`。 | Present; `SL1-RC-004`。 |
| `SL1-RISK-005` | real subagent callbacks | callback payload に hierarchy field がないまま subagent suppression を推測実装する危険。 | `AR-002`、`XC-002`、`ARCH-INV-005`。 | ManualOnly; 実装対象外。 |

## Selected runtime contracts

| Contract ID | Parent / architecture source | Selected concern | Status |
| --- | --- | --- | --- |
| `SL1-RC-001` | `RC-001`, `ARC-RC-001` | valid `agent-turn-complete` callback の generic candidate 化と callback identity。 | Selected |
| `SL1-RC-002` | `RC-001`, `RC-005`, `ARC-RC-002`, `ARC-RC-009` | optional envelope enrichment、fallback、URI safety、`XC-001` consumer。 | Selected |
| `SL1-RC-003` | `RC-001`, `ARC-RC-003` | provider dual actions、dedup、timeout、chain/provider fail-open。 | Selected |
| `SL1-RC-004` | `RC-002`, `ARC-RC-004` | install/update/check/rollback と APM production distribution。 | Selected |

## Cross-slice and residual handling

- `XC-001` は `SL-002` が terminal projection を producer とする `Deferred` contract。SL-001 は parser、validation、generic fallback、URI safety を consumer-side に実装するが、producer/consumer 統合完了は宣言しない。
- `XC-002` は real Codex parent + reviewer subagent による user-visible notification count / target の `ManualOnly` close gate。callback hierarchy を source にない field から推測しない。
- `SCP-003` は `OutOfScopeWithSource`。Plugin migration は行わず APM distribution を維持する。

## Recommended route

- Recommended process profile: standard-slice
- implementation_route: adaptive
- implementation_route_source: default
- Immediate next artifact: `SL-001-implementation-contract-kernel.md`
- Separate implementation-contract review: Not required. Self-checkで implementation address、禁止代替、未解決項目を明示できる。

## Handoff Packet

- Profile used: slice-prep
- Source artifacts: parent Plan、Behavior Spec、parent triage、Architecture Slice Readiness、Slice Architecture、Slice Decomposition、`SL-001` Bounded Plan。
- Selected contracts / IDs: `SL1-RC-001`〜`SL1-RC-004`。
- Files inspected: notification runtime、Windows provider、installer、schemas、runtime validator、completion-notification-decorator package manifest/README/validator/fixtures、root README。
- Files intentionally not inspected: `SL-002` production sources、unrelated packages、live Codex/Windows state。理由はこの slice の bounded preparation 外であるため。
- Decisions made: generic callbackを既定、envelopeをoptional enrichment、callback `thread-id` / `turn-id`をidentity authority、`XC-001` / `XC-002`をdeferred/manualとして保持する。
- Remaining work: contract、test design、parent authorization後のAdaptive implementation、slice verification、cross-slice verification、manual smoke。
- Recommended next step: parent review後に `implementation-handoff-review.agent.md`、次いで Adaptive implementation route の `high-implementation-starter.agent.md`。
