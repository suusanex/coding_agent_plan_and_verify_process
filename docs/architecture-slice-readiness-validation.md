# Architecture Slice Readiness Validation Suite

This maintainer suite validates the routing contract added between `full-coverage` risk triage and Plan Slice Decomposition. It does not implement code, change production systems, or treat current implementation as architecture authority.

For every executable decomposed slice, the Plan Coverage parent reconfirms baseline freshness and `implementation-handoff-review` Check 11 records baseline identity, observed semantics, and `Match / Drift / Unclear`. Only a current-baseline `Match` permits implementation. `Drift` returns to Architecture Slice Readiness / Elaboration, and `Unclear` fails closed and reruns readiness. `StandardSliceSufficient` is a successful route correction and does not enter those cross-slice gates.

## Validation contract

For each fixture, record:

- Change Risk Triage profile and architecture-readiness triggers
- Architecture Slice Readiness verdict
- required artifact and residual classification
- whether decomposition is allowed
- expected next agent or stop action

## ASR-001: Stateful orchestration requires elaboration

### Fixture

```text
Participants: control plane, worker, observer, human return gate
State: durable desired state plus derived observation
Behavior: activation, retry, resume across runs, shared capacity
Missing: canonical state owner, source precedence, release sequence, cross-run identity
```

### Expected

| Field | Expected value |
| --- | --- |
| triage profile | `full-coverage` |
| readiness verdict | `NeedsArchitectureElaboration` |
| blocking residual | one or more `ArchitectureCritical` |
| next agent | `architecture-elaboration.agent.md` |
| decomposition allowed | `No` |

### Elaboration rerun freshness regression

1. R1=`NeedsArchitectureElaboration`を標準readiness pathへ出力する。
2. A1を作成し、R1を`elaboration_trigger`、`freshness_dependency: false`として保存する。
3. 同じreadiness pathをR2=`ReadyForSliceDecomposition`へ更新する。
4. A1がcurrentのままで、R2がA1の外部content hashを追跡することを確認する。
5. decompositionが許可されることを確認する。
6. R2後にParent Planまたはproduction watch pathを変更するとA1 / R2がstaleになり、decompositionがBLOCKされることを確認する。

## ASR-002: Architecture-critical deferred item blocks decomposition

### Fixture

```text
The Plan and behavior cases are complete.
Two artifacts can report the same state, but precedence is not defined.
Reservation release on retry exhaustion is also undecided.
```

### Expected

Both topics are `ArchitectureCritical`. `plan-slice-decomposition.agent.md` must not create executable slices, even if the Plan is `ReadyForRiskTriage`.

## ASR-003: Legacy triage without escalation evidence returns to risk triage

### Fixture

```text
The legacy triage recommends full-coverage before the escalation gate existed.
It contains no `Why standard-slice is insufficient` evidence and no
`Escalation gate result: Satisfied`.
```

### Expected

| Field | Expected value |
| --- | --- |
| readiness verdict | `NoArchitectureVerdict` |
| selected process after readiness | `N/A` |
| architecture artifact | `N/A` |
| readiness artifact | pre-readiness gate record only |
| decomposition allowed | `No` |
| immediate next agent | `change-risk-triage.agent.md` |
| Plan Coverage parent compatibility | `NotRun` |
| `implementation-handoff-review` Check 11 | `NotRun` |

The original triage artifact remains unchanged as audit evidence. No architecture verdict is emitted until Change Risk Triage supplies the new escalation evidence.

## ASR-004: Slice-local details do not block readiness

### Fixture

```text
Participant ownership, precedence, state transitions, identity, retry/release, schema, capacity, invariants, and production wiring are defined.
Only helper names, internal class split, and fixture paths remain undecided.
```

### Expected

The residuals are `ImplementationDetail` or `SliceLocalContract`. With a current slice architecture artifact and no blocking residual, the verdict is `ReadyForSliceDecomposition`.

## ASR-005: Pre-implementation compatibility detects drift

### Fixture

```text
Approved architecture: durable state owner is Participant A; Observation B is derived and read-only.
Slice-local pre-implementation proposal: Participant B writes the canonical state when observation is newer.
```

### Expected

The Plan Coverage parent and `implementation-handoff-review` Check 11 record `Drift`, block implementation, and route back to Architecture Slice Readiness / Elaboration. The proposal must not become a slice-local contract or expected test fixture.

## ASR-006: Human authority stops the route

### Fixture

```text
Two valid source-precedence policies exist and the requirement sources do not choose one.
The choice changes externally observable recovery behavior.
```

### Expected

The residual and verdict are `NeedsHumanDecision`. Elaboration and decomposition stop until a human decision source is recorded.

## ASR-007: Multiple slices can use existing shared semantics

### Fixture

```text
Seven independently owned adapters must be updated and verified separately.
The immutable envelope schema, ownership, ordering, failure behavior, and production wiring are already source-backed and unchanged.
The triage artifact contains a satisfied full-coverage escalation gate.
```

### Expected

| Field | Expected value |
| --- | --- |
| readiness verdict | `ArchitectureNotRequired` |
| architecture artifact | `N/A` |
| readiness artifact | required, containing a `Lightweight architecture baseline` |
| decomposition allowed | `Yes` |
| immediate next agent | `plan-slice-decomposition.agent.md` |
| Plan Coverage parent compatibility | `Match` |
| `implementation-handoff-review` Check 11 | `Match` |

This fixture protects the distinction between “no independent architecture artifact is needed” and “no decomposition is needed.”

The fixture includes `production-evidence.md` with concrete schema, authority, production-registration, and compatibility-oracle addresses. `ArchitectureNotRequired` is not accepted from Plan or triage assertions alone.

## ASR-008: A satisfied but false-positive escalation is de-escalated

### Fixture

```text
The new-format triage records Escalation gate result: Satisfied and claims independent slices.
Production reinspection shows one entrypoint, one lifecycle owner, one durable-state owner,
and one end-to-end verifier covering the platform call, UI handoff, publication, and later reader.
Implementation-realization risk is absent.
```

### Expected

| Field | Expected value |
| --- | --- |
| readiness verdict | `StandardSliceSufficient` |
| selected process after readiness | `standard-slice` |
| architecture artifact | `N/A` |
| readiness artifact | required, as route correction authority |
| decomposition allowed | `No` (successful result) |
| immediate next agent | `runtime-contract-kernel.agent.md` |
| Plan Coverage parent compatibility | `NotRun` |
| `implementation-handoff-review` Check 11 | `NotRun` |

The original new-format triage remains unchanged as audit evidence. The readiness artifact records why the source-backed production sequence contradicts the escalation premise.

## Negative scans

Run after changing the route. Matches are allowed only in historical explanation or explicit prohibition text.

```powershell
rg -n "full-coverage.*(always|必ず).*plan-slice-decomposition|immediate next.*plan-slice-decomposition" README.md docs .github apm-packages
rg -n "NeedsArchitectureElaboration|ReadyForSliceDecomposition|ArchitectureNotRequired|StandardSliceSufficient" README.md docs .github apm-packages
rg -n "architecture-slice-readiness.agent.md|architecture-elaboration.agent.md|slice-architecture.md" README.md docs .github apm-packages
```

## Validation result template

The current executed result is stored in `docs/architecture-slice-readiness-validation-result.md`. Keep this template for future reruns.

Complete durable evidence for the current run is stored under `tests/architecture-slice-readiness/ASR-001` through `ASR-008`. Each directory contains complete input artifacts, complete actual Markdown outputs, `expected.json`, `actual.json`, and `run.json`. The repository validator compares expected and actual values and verifies the run evidence.

```md
# Architecture Slice Readiness Validation Result

| Fixture | Observed verdict | Decomposition allowed | Next action | Pass / fail |
| --- | --- | --- | --- | --- |
| ASR-001 | | | | |
| ASR-002 | | | | |
| ASR-003 | | | | |
| ASR-004 | | | | |
| ASR-005 | | | | |
| ASR-006 | | | | |
| ASR-007 | | | | |
| ASR-008 | | | | |

## Static checks

- frontmatter and manifest paths:
- old direct-route scans:
- `git diff --check`:
```

## Operator procedure

1. Use a disposable repository or read-only planning thread.
2. Provide the parent Plan, behavior coverage, and triage input from one fixture.
3. Capture the readiness verdict before allowing elaboration or decomposition.
4. For ASR-001, run elaboration, verify the template sections, and rerun readiness.
5. For ASR-003, verify that the missing escalation evidence produces `NoArchitectureVerdict` and returns to Change Risk Triage.
6. For ASR-005, provide the approved architecture and drifting slice-local pre-implementation proposal to the Plan Coverage parent compatibility check and `implementation-handoff-review` Check 11.
7. For ASR-007, verify that `ArchitectureNotRequired` still permits decomposition and reaches a current-baseline `Match`.
8. For ASR-008, verify that a source-backed reinspection can correct a satisfied false-positive escalation to `StandardSliceSufficient` without decomposition.
9. Compare verdict, artifact requirement, residual classification, and next action with this suite.
10. Do not allow implementation, production writes, secrets, billing, external services, or GitHub setting changes during validation.
