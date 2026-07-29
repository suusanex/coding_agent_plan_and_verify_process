# Test Design Kernel: SL-002

## スコープ

Runtime Contract Kernelの`SL2-RC-001`〜`SL2-RC-003`を対象に、SL-002 assigned Behavior Casesの証拠経路を定義する。ここでの`Done`はtest designの完了であり、実装・実行・feature closeを意味しない。

## Test Design Kernel

| Test Point ID | Runtime Contract ID | What to verify | Stub / fake allowed? | Production binding required? | Expected observation | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `SL2-TP-001` | `SL2-RC-001` | one-operation intake resolves a Ready PR and selected Goal Context without user-supplied thread/path/hash/JSON relay. | Yes | Yes | run summary binds current repository, PR identity, Goal Context identity, and round-1 artifact index. | Done |
| `SL2-TP-002` | `SL2-RC-001` | Draft, missing/ambiguous Goal Context, or collector identity failure stops before reviewers/remediation. | Yes | Yes | `Blocked` includes one concrete blocker and no executable remediation path. | Done |
| `SL2-TP-003` | `SL2-RC-001` | round 1 has current-head Copilot, local, and purpose raw evidence; reviewer profiles stay read-only. | Yes | Yes | mandatory source ledger and raw outputs are distinguishable; only parent diff may change production files. | Done |
| `SL2-TP-004` | `SL2-RC-002` | authorized findings are projected by stable ID, parent remediation refreshes the remote head, and stale head is rejected. | Yes | Yes | rerun consumes a new collector-declared current head rather than pre-remediation patch. | Done |
| `SL2-TP-005` | `SL2-RC-002` | rounds 2/3 are purpose-only. | Yes | Yes | no Copilot wait/local artifact; collected remote sources remain reasoned audit-only and actionable evidence is current `PUR-*`. | Done |
| `SL2-TP-006` | `SL2-RC-002` | no findings completes; human decision, missing mandatory source, or active round-3 finding stops explicitly. | Yes | Yes | verdict and finding delta match raw coverage; no empty executable plan and no round 4 auto-start. | Done |
| `SL2-TP-007` | `SL2-RC-003` | terminal projection contains only safe status/title/current concrete HTTPS PR URI. | Yes | Yes | projection excludes callback `thread-id` / `turn-id`; invalid/missing enrichment cannot change review verdict. | Done |
| `SL2-TP-008` | `SL2-RC-003` | producer-to-consumer result action has both parent-thread and PR return paths. | No | Yes | real integration/manual buttons demonstrate `XC-001`; SL-002 alone cannot mark it complete. | Deferred |
| `SL2-TP-009` | `SL2-RC-001` | reviewer subagent roles/count are recorded during a real same-parent run. | No | Yes | manual evidence supports `XC-002` notification-noise assessment without recording private callback identity. | ManualOnly |

## 必須 production binding 確認事項

| Test Point ID | Runtime Contract ID | Substitute used / expected | Production implementation to check | Production wiring / entrypoint to check | Notes |
| --- | --- | --- | --- | --- | --- |
| `SL2-TP-001` | `SL2-RC-001` | deterministic PR/Goal Context fixture | package-owned same-parent orchestrator/run-summary implementation | APM-installed `$goal-context-pr-review`, selector, collector, sync-installed profiles | fake pass alone is insufficient. |
| `SL2-TP-002` | `SL2-RC-001` | invalid identity/selection fixture | intake fail-closed branch | canonical Skill invocation and collector/selector integration | Issue substitution must remain impossible. |
| `SL2-TP-003` | `SL2-RC-001` | fake GitHub/reviewer evidence | reviewer profile enforcement and raw-output retention | TOMLs, canonical agents, sync helper, installed package | production diff ownership must be observed. |
| `SL2-TP-004` | `SL2-RC-002` | replayed head/finding fixture | parent remediation/current-head transition | actual parent repository workflow and collector | commit/push/check command remains repository-governed. |
| `SL2-TP-005` | `SL2-RC-002` | deterministic round artifacts | purpose-only source coverage/finding transition | same-parent Skill and purpose reviewer profile | no local/Copilot rerun. |
| `SL2-TP-006` | `SL2-RC-002` | decision-state fixture | terminal verdict derivation | parent terminal output and package validation | no implicit close. |
| `SL2-TP-007` | `SL2-RC-003` | projection/parser fixture | terminal projection producer | SL-002 Skill plus future SL-001 runtime wiring | consumer action requires `XC-001`. |
| `SL2-TP-008` | `SL2-RC-003` | no substitute | SL-002 projection and SL-001 provider/runtime | real Codex callback and Windows action surface | cross-slice only. |
| `SL2-TP-009` | `SL2-RC-001` | no substitute | actual read-only reviewer subagents | real Codex same-parent run and notification runtime | manual-only close evidence. |

## 手動確認のみの項目

- `SL2-TP-008`: `XC-001`で親threadとvalid PR resultの両導線を実機で開けること。
- `SL2-TP-009`: real same-parent reviewer subagent execution時のroles/countとuser-visible notification targets。callback hierarchyを推測してfilterしない。
- real model reviewer independence and parent-owned remediation are required close evidence; deterministic fixtures remain supplemental.

## Behavior case test mapping

| Case ID | Runtime Contract ID | Test Point ID | Expected behavior | Coverage disposition | Evidence target | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `REV-001` | `SL2-RC-001` | `SL2-TP-001` | same-parent one-operation start with no messenger relay | AutomatedPlanned | canonical invocation/fixture | Done |
| `REV-002` | `SL2-RC-001` | `SL2-TP-003` | three independent round-1 sources retain raw evidence | AutomatedPlanned | source-ledger fixture | Done |
| `REV-003` | `SL2-RC-001` | `SL2-TP-003` | reviewers read-only; parent alone writes | AutomatedPlanned | profile/diff ownership check | Done |
| `REV-004` | `SL2-RC-002` | `SL2-TP-004` | parent remediates and uses new current head | AutomatedPlanned | head/finding replay | Done |
| `REV-005` | `SL2-RC-002` | `SL2-TP-005` | rounds 2/3 purpose-only | AutomatedPlanned | round-mode fixture | Done |
| `REV-006` | `SL2-RC-002` | `SL2-TP-006` | resolved findings complete within bound | AutomatedPlanned | terminal decision fixture | Done |
| `REV-007` | `SL2-RC-002` | `SL2-TP-006` | round-3 active finding stops for human decision | AutomatedPlanned | terminal decision fixture | Done |
| `REV-008` | `SL2-RC-002` | `SL2-TP-006` | product decision is retained and stopped | AutomatedPlanned | terminal decision fixture | Done |
| `REV-009` | `SL2-RC-001` | `SL2-TP-002` | bad/missing input blocks concretely | AutomatedPlanned | negative fixture | Done |
| `REV-010` | `SL2-RC-001` | `SL2-TP-003` | mandatory reviewer failure cannot complete round 1 | AutomatedPlanned | source-coverage fixture | Done |
| `REV-011` | `SL2-RC-002` | `SL2-TP-005` | explicit active/resolved finding transitions | AutomatedPlanned | purpose-only replay | Done |
| `REV-012` | `SL2-RC-001` | `SL2-TP-001` | internal artifacts do not become user relay requirements | AutomatedPlanned | docs/validator/fixture | Done |
| `REV-013` | `SL2-RC-003` | `SL2-TP-008` | terminal returns to parent thread and PR when present | ManualOnly | `XC-001` integration | Deferred |
| `NTF-003` | `SL2-RC-003` | `SL2-TP-008` | result link adds to, not replaces, thread link | ManualOnly | `XC-001` integration | Deferred |
| `NTF-005` | `SL2-RC-001` | `SL2-TP-009` | parent-centric notification has no subagent spam | ManualOnly | `XC-002` real smoke | Deferred |
| `SCP-001` | none | N/A | generic multi-thread/long recovery remains excluded | OutOfScopeWithSource | non-goal/docs disposition | Done |
| `SCP-002` | none | N/A | timeline and Adaptive executor replacement remain deferred | DeferredWithReason | residual ledger | Done |
| `SCP-003` | none | N/A | APM continues; Plugin migration is not a goal | OutOfScopeWithSource | manifest/docs validation | Done |

## 注記 / 前提

実装前のtest designであり、production bindingは未確認である。`SL2-TP-008` / `SL2-TP-009`は、deterministic fixtureで代替せずcross-slice/manual gateへ引き継ぐ。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: parent Plan/behavior/triage, readiness R2, Slice Architecture, decomposition, SL-002, SL-002 implementation/runtime contracts.
- Selected contracts / IDs: `SL2-RC-001`, `SL2-RC-002`, `SL2-RC-003`; `SL2-TP-001`〜`SL2-TP-009`.
- Files inspected: relevant existing Skills, collector, manager, reviewer profiles/contracts, package validators/docs and fixture index.
- Files intentionally not inspected: unrelated tests/packages and live services; this is a design pass.
- Decisions made: every fake/deterministic test requires production binding verification; `XC-001` and `XC-002` remain Deferred/ManualOnly.
- Behavior case coverage: all SL-002 assigned `REV-*`, `NTF-*`, and `SCP-*` cases are mapped.
- Do not redo unless new evidence appears: no test substitute is close-ready evidence by itself; no automatic round 4.
- Remaining work: implementation, slice-local verification, real-model/manual evidence, then cross-slice verification.
- Recommended next step: parent review gate, then authorized adaptive implementation beginning with `high-implementation-starter`.
