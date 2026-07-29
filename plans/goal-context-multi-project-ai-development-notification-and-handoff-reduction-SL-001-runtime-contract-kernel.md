# Runtime Contract Kernel: SL-001

## スコープ

per-slice triageとImplementation Contractに基づき、`SL1-RC-001`〜`SL1-RC-004`だけを扱う。`XC-001`はconsumer-side boundary、`XC-002`はmanual-only close gateとして明示する。

## Runtime Contract Kernel

| Contract ID | Scenario | Producer | Consumer | Message / API / Event | Required fields | Error / timeout behavior | Production implementation address | Verification hook |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `SL1-RC-001` | ordinary terminal callback | Codex host | `codex-notification-runtime.cs` | argv JSON `agent-turn-complete` callback | `type`, `thread-id`, `turn-id`, `cwd`; `thread-id` / `turn-id` are source identity | malformed/non-terminal callback is ignored; valid callback must not be marker/envelope-suppressed | `scripts/codex-notification-runtime/codex-notification-runtime.cs` (`CodexPayload`, `CreateCandidate`) | `SL1-TP-001` |
| `SL1-RC-002` | optional terminal enrichment | same-parent Skill / generic task terminal response | notification runtime | optional `completion-notification` fenced envelope in `last-assistant-message` | schema version, process, status, safe title, optional concrete HTTPS result URI; identity is not an envelope field | absent/invalid envelope produces generic fallback; unsafe URI omits only result action | runtime parser plus `completion-notification-envelope-v1.schema.json` | `SL1-TP-002`, `SL1-TP-006` |
| `SL1-RC-003` | notification dispatch | notification runtime | Windows App Notification provider and existing chained notify | event JSON on provider stdin; original callback JSON to chain | event schema fields, `resume_uri`, optional `result_uri`, `source_event_id` | provider/chain/timeout failure is observational; claim is released for retry; duplicate source event is suppressed | runtime dispatch/claim code, provider source, event schema | `SL1-TP-003`, `SL1-TP-004` |
| `SL1-RC-004` | always-on installation and package delivery | notification installer / APM package | Codex user config and installed runtime | top-level TOML `notify` argv, `runtime-config.json`, APM installed assets | installed runtime/provider paths, provider config, preserved chained argv, backup state | stage failure rolls back; self-wrap is rejected; `--check` reports structural failure or provider degradation without corrupting config | installer, `apm-packages/completion-notification-decorator/`, root/package docs | `SL1-TP-005` |

## Plan / implementation contract 適合性

| Runtime Contract ID | Plan requirement | Implementation contract decision | Runtime contract address | Conformance |
| --- | --- | --- | --- | --- |
| `SL1-RC-001` | `SL1-FR-001`, `SL1-AC-001` | generic candidateをvalid callbackの既定とする | runtime `CreateCandidate` | Conformant |
| `SL1-RC-002` | `SL1-FR-002`, `SL1-AC-002`, `AC-007` | envelopeはoptional、callback identityが優先 | parser/schema/provider | Conformant |
| `SL1-RC-003` | `SL1-FR-004`, `SL1-AC-003` | dedup/fail-open/dual actionを維持する | runtime/provider/event schema | Conformant |
| `SL1-RC-004` | `SL1-FR-003`, `SL1-AC-004`〜`006` | marker依存なしのwiringとpackage production distribution | installer/package/docs | Conformant |

## 注記 / 前提

- 現行sourceはまだ `SL1-RC-001` のtarget behaviorを実装していない。これは runtime contractの未確定ではなく、明示済みのimplementation gapである。
- `XC-001`: `SL-002` が terminal status / safe title / PR URIをproducerとして作る。SL-001はcallback identityを保持し、invalid/missing valueをgeneric fallbackにする。Status: `Deferred`。
- `XC-002`: parent/subagent hierarchyのofficial callback fieldは確認できない。runtime filterを推測せず、real Codex manual smokeでnotification count / targetを観測する。Status: `ManualOnly`。
- Slice Architectureがすでに `ReadyForSliceDecomposition` を与えているため、新しいshared semanticsは導入しない。

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: SL-001 implementation contract、parent triage、Plan、Behavior Spec、Slice Architecture、Decomposition、SL-001 Bounded Plan。
- Selected contracts / IDs: `SL1-RC-001`〜`SL1-RC-004`。
- Files inspected: runtime/provider/installer/schemas/validator、Decorator package metadata/docs/validator/fixtures、root README。
- Files intentionally not inspected: `SL-002` implementation、unrelated providers、live Codex state。理由はcross-slice/manual scopeのため。
- Decisions made: explicit participant/boundary、callback identity precedence、enrichment fallback、APM wiring boundaryを固定した。
- Do not redo unless new evidence appears: each RCのproducer/consumerとproduction address。
- Remaining work: test point design、implementation、production binding verification、`XC-001` integrationと`XC-002` manual evidence。
- Recommended next step: `test-design-kernel.agent.md` with `SL1-RC-001`〜`SL1-RC-004` and assigned behavior cases.
