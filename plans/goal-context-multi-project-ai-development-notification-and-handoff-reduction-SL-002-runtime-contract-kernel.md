# Runtime Contract Kernel: SL-002

## スコープ

`SL2-RC-001`〜`SL2-RC-003`のみを対象とする。`XC-001`のnotification consumerと`XC-002`のreal callback observationはcross-slice verificationへDeferredとする。

## Runtime contracts

| Contract ID | Producer | Consumer | Boundary mechanism | Required fields / state | Error / timeout behavior | Production implementation address | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `SL2-RC-001` | same-parent Goal Context review orchestrator | Goal Context selector, collector, local/purpose reviewers | one-operation intake, package-owned run root, collector artifacts and read-only subagent returns | repository, Ready PR number/URL/base/head OID, Goal Context selected path/SHA, round=`1`, raw-output artifact index, source coverage | missing/ambiguous Goal Context, Draft PR, collector failure, head drift, or mandatory reviewer failure → `Blocked`; no inferred source coverage | canonical entry: `goal-context-pr-review` Skill; selector/collector/profiles confirmed; same-parent orchestration/run-summary code address MissingButRequired | PartiallyDone |
| `SL2-RC-002` | parent implementation agent | collector and new purpose reviewer | parent-owned remediation, current-head refresh, purpose-only current-round artifacts | reviewed head OID, current head OID, round `2`/`3`, active/resolved/NeedsHumanDecision tracking IDs, prior assessment, mandatory-source coverage, terminal verdict | stale/unavailable head or missing required evidence → `Blocked`; product decision → `HumanDecisionRequired`; round 3 active finding → `HumanDecisionRequired`; no automatic round 4 | orchestrator/run summary MissingButRequired; collector `TargetIdentity` and purpose-reviewer contract confirmed | PartiallyDone |
| `SL2-RC-003` | same-parent terminal projection | `XC-001` notification runtime consumer | optional terminal envelope/projection | schema version, primary process, terminal status, safe title, current concrete HTTPS PR URI; excludes `thread-id` and `turn-id` | missing/invalid projection → generic notification fallback without changing review verdict; invalid/no PR URI omits result enrichment | Skill-compatible terminal projection; runtime consumer owned by SL-001 | Deferred |

## Participant and ownership mapping

| Participant | Owns | May write | Must not write |
| --- | --- | --- | --- |
| same-parent orchestrator | run summary projection, round decision, terminal projection | package-owned review artifacts and parent terminal metadata | reviewer raw evidence, callback identity, production code as a reviewer |
| collector | current remote PR identity, patch, collected source snapshot | designated context/patch output | GitHub state, verdict, source edits |
| local/purpose reviewers | raw findings and stated unknowns | returned raw output only | production/tests/GitHub/orchestration state |
| parent implementation agent | remediation source/test/doc changes, validation, PR head update | authorized target-repository changes and run summary transition | reviewer identity/evidence fabrication, unapproved product decisions |
| notification runtime (SL-001) | callback identity and return-action derivation | runtime event/delivery state | review verdict authority |

## Sequence and precedence

1. Resolve current repository, Ready PR, and selected Goal Context from parent context; do not ask the user to carry IDs, hashes, or paths in the normal path.
2. Bind the collector-declared base/head/remote patch and selected Goal Context identity into round 1 artifacts.
3. Collect Copilot sources and independently run read-only local/purpose reviewers. Missing mandatory source stops; it does not mean no findings.
4. Parent projects raw findings by stable ID, remediates authorized items, validates, and refreshes current remote head before any rerun.
5. Rounds 2/3 use `purpose-only`: no Copilot wait and no local reviewer. Current `PUR-*` evidence plus explicit prior assessment drives finding transitions.
6. Derive `Complete`, `HumanDecisionRequired`, or `Blocked` from mandatory coverage, active findings, decision requirement, and round limit. A terminal projection can enrich notification but cannot alter the decision.

Precedence: remote current head and raw reviewer/collector artifacts > run summary > terminal projection. Goal Context: explicit valid path > unique discovery; Issue text cannot substitute. Callback `thread-id` / `turn-id` remain outside this slice.

## Production binding and unresolved status

| Contract ID | Production implementation required | Production wiring / entrypoint | Unresolved status |
| --- | --- | --- | --- |
| `SL2-RC-001` | same-parent orchestration and durable minimal summary | APM-installed `$goal-context-pr-review`, selector, collector, read-only profiles, sync helper | NotImplementedOrMismatch until fixed-two-task normal authority is replaced and install/check is verified |
| `SL2-RC-002` | parent-owned remediation transition and purpose-only state projection | same Skill in original parent thread plus repository git/validation workflow | NotImplementedOrMismatch until current-head gate and parent-only write evidence are verified |
| `SL2-RC-003` | safe terminal projection | SL-002 producer plus SL-001 runtime/provider consumer | Deferred pending `XC-001` integration |

## Handoff Packet

- Profile used: contract-kernel
- Source artifacts: parent Plan/behavior/triage, readiness R2, Slice Architecture, decomposition, SL-002, SL-002 implementation contract.
- Selected contracts / IDs: `SL2-RC-001`, `SL2-RC-002`, `SL2-RC-003`.
- Files inspected: Goal Context Skill, collector, manager, reviewer contracts/profiles, manifest/sync helper, validators and docs.
- Files intentionally not inspected: unrelated runtime/provider code, full test-suite internals, live external state.
- Decisions made: raw remote/reviewer evidence has precedence over summary; parent is sole writer; purpose-only is a strict mode; terminal projection excludes callback identity.
- Do not redo unless new evidence appears: consumer ownership and callback identity remain with SL-001; fixed two-task manager cannot define normal-path semantics.
- Remaining work: implement package-owned same-parent source address and verify all production bindings; manual `XC-002` observation.
- Recommended next step: `test-design-kernel.agent.md` for `SL2-RC-001`〜`SL2-RC-003`.
