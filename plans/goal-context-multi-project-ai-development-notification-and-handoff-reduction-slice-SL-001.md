# SL-001 Bounded Plan: Always-on Codex completion notification

## Goal

user-level Codex `notify`を一度導入した後、marker / Decorator / envelopeなしのvalid turn callbackをgeneric thread-link notificationへ変換し、safe optional metadataがある場合だけresult actionを追加する。

## Non-goals

- notification timeline、additional provider、Plugin migration、Codex private API。
- unsupportedなparent / subagent hierarchy heuristic。
- same-parent review orchestration本体。

## Parent requirements covered

`FR-001`〜`FR-004`、`FR-009`のnotification consumer、`FR-012`のnotification distribution。

## Parent acceptance conditions covered

`AC-001`〜`AC-005`、`AC-011`のconsumer、`AC-012`、`AC-013`。

## Affected components / modules

- `scripts/codex-notification-runtime/`
- `apm-packages/completion-notification-decorator/`
- notification validation workflow / scripts
- `README.md` notification sections

## Expected implementation scope

- valid callbackのgeneric candidate化とoptional envelope enrichment。
- invalid / missing envelopeのgeneric fallback、resume identity precedence、URI safety、dedup、fail-open。
- installerのalways-on config、existing notify chain、rollback / check。
- runtime assetsのAPM distributionとDecoratorのoptional compatibility化。
- schemas、fixtures、docs、manual evidence ledger。

## Cross-slice dependencies

- `XC-001`: `SL-002`terminal enrichmentを消費する。
- `XC-002`: `SL-002`subagent orchestration時のreal notification behaviorを共同確認する。

## Related Cross-slice Contract IDs

`XC-001`, `XC-002`

## Architecture baseline

- Verdict: ReadyForSliceDecomposition
- Architecture: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-slice-architecture.md`
- Identity: commit `774d6da78ed67be8478b4b5169121805daec79e6`、artifact revision `1`、hash `1e791e99a059428996355d38012ea155204b073c0e6a7a77c8ed25c7b02437de`。
- Source sections: notification participants / state、`ARC-RC-001`〜`ARC-RC-004`, `ARC-RC-009`, `ARCH-INV-001`〜`ARCH-INV-005`, `ARCH-INV-010`。
- Assigned residuals: `AR-001`, `AR-002`, notification-related `AR-005`。

## Black-box behavior coverage

- Parent behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Expansion required: Yes
- Slice Plan readiness: ReadyForRiskTriage
- Assigned Behavior Case IDs: `NTF-001`〜`NTF-008`, `REV-013` consumer、`SCP-003`

### Case-to-Slice mapping

| Case ID | Parent FR / AC | Slice FR / AC | Cross-slice Contract ID | Disposition | Notes |
| --- | --- | --- | --- | --- | --- |
| `NTF-001`, `NTF-002`, `NTF-004`, `NTF-006`, `NTF-007`, `NTF-008` | `FR-001`〜`FR-003`,`FR-012` / `AC-001`〜`AC-004`,`AC-012`,`AC-013` | `SL1-FR-001`〜`SL1-FR-004` / `SL1-AC-001`〜`SL1-AC-006` | N/A | InternalToSlice | generic delivery / fallback / dedup / fail-open / install。 |
| `NTF-003`, `REV-013` | `FR-002`,`FR-009` / `AC-002`,`AC-011` | `SL1-FR-002` / `SL1-AC-002`,`SL1-AC-007` | `XC-001` | CrossSliceVerification | resultとthread action。 |
| `NTF-005` | `FR-004` / `AC-005` | `SL1-FR-004` / `SL1-AC-008` | `XC-002` | CrossSliceVerification | real subagent notification。 |
| `SCP-003` | `FR-012` / `AC-004`,`AC-012` | `SL1-FR-003` / `SL1-AC-005` | N/A | OutOfScopeWithSource | APM継続、Plugin移行なし。 |

## Slice functional requirements

- `SL1-FR-001`: every valid `agent-turn-complete` callback becomes a generic notification candidate without marker / envelope gating。
- `SL1-FR-002`: callback identity owns resume URI; valid optional envelope may enrich status / title / result only。
- `SL1-FR-003`: installer and APM package establish always-on production wiring while preserving existing notify and rollback。
- `SL1-FR-004`: dedup / timeout / provider / chain failures remain observational; real subagent behavior is explicitly verified rather than guessed。

## Slice acceptance conditions

- `SL1-AC-001`: markerless / envelopeless callback fixture emits generic event with `codex://threads/<thread-id>`。
- `SL1-AC-002`: valid enrichment emits dual actions; invalid enrichment and unsafe URI fall back to thread-only generic event。
- `SL1-AC-003`: replay and failing provider / chain do not duplicate or fail the parent turn。
- `SL1-AC-004`: clean temporary home install / update / check / rollback succeeds and retains existing notify without self-wrap。
- `SL1-AC-005`: APM-installed assets contain executable installer / runtime / provider source and docs。
- `SL1-AC-006`: static validator / File-based App publish / schema fixtures pass。
- `SL1-AC-007`: `XC-001`consumer accepts `SL-002`projection without allowing identity override。
- `SL1-AC-008`: real parent + subagent smoke records user-visible notification count / target and blocks close on spam。

## Cross-slice contract excerpts

### XC-001

- This slice role: Consumer
- Mechanism: optional terminal envelope in callback last response
- Required fields / state / identifiers: schema version、process、terminal status、safe title、optional concrete HTTPS PR URI。thread / turnはcallback。
- This slice owns: parsing、validation、generic fallback、URI safety、provider actions。
- This slice consumes: `SL-002`terminal projection。
- Unresolved: なし。invalid valueはfabricateしない。
- Authority: parent decomposition `Cross-slice contracts` / field continuity。

### XC-002

- This slice role: Consumer / verification owner
- Mechanism: real Codex parent + reviewer subagent callback observation
- Required fields / state / identifiers: reviewer roles / count、parent terminal、user-visible notification count / targets。
- This slice owns: runtime / provider observation。
- This slice consumes: `SL-002`subagent execution。
- Unresolved: callback hierarchy fieldなし。manual-only。
- Authority: parent decomposition `Cross-slice contracts` / field continuity。

## Implementation-realization risks

- marker-only gatingの近似実装を残してgeneric callbackを抑止するrisk。
- runtime canonical sourceがAPM package外で配布されないrisk。
- TOML notify chain / rollback / self-wrap。
- optional envelope schema compatibility。
- real subagent callback scope。

## Recommended route

- Recommended process profile: standard-slice
- Immediate next agent: `implementation-contract-kernel.agent.md`
- implementation_route: adaptive
- implementation_route_source: default
- design_pair_handoff: N/A

## Required inputs for next agent

parent Plan、Behavior Spec、Change Risk Triage、R2 Readiness、Slice Architecture、parent decomposition、本slice、notification source / schemas / package / validators / README。

## Stop condition

slice-local implementation / verificationを完了し、`XC-001`consumer statusと`XC-002 ManualOnly`をparent orchestrationへ返す。cross-slice closeは行わない。
