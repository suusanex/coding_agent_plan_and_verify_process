# Architecture Slice Readiness Validation Suite

This maintainer suite validates the routing contract added between `full-coverage` risk triage and Plan Slice Decomposition. It does not implement code, change production systems, or treat current implementation as architecture authority.

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

## ASR-002: Architecture-critical deferred item blocks decomposition

### Fixture

```text
The Plan and behavior cases are complete.
Two artifacts can report the same state, but precedence is not defined.
Reservation release on retry exhaustion is also undecided.
```

### Expected

Both topics are `ArchitectureCritical`. `plan-slice-decomposition.agent.md` must not create executable slices, even if the Plan is `ReadyForRiskTriage`.

## ASR-003: Simple bounded change avoids architecture overhead

### Fixture

```text
One stateless component changes validation text inside an existing schema.
No new participant, durable state, identity, retry, capacity, cross-boundary contract, or production wiring is introduced.
```

### Expected

| Field | Expected value |
| --- | --- |
| readiness verdict | `ArchitectureNotRequired` |
| architecture artifact | `N/A` |
| readiness artifact | required, with source-backed simple-structure reason |
| decomposition allowed | `Yes` |
| architecture baseline authority | readiness artifactの`Lightweight architecture baseline` |
| slice-prep conformance | `Match` when no new shared semantics are introduced |
| parent drift verdict | `Match` |
| parent implementation authorization | `Can implement now? = Yes` when other gates pass |
| slice-impl architecture gate | current readiness baseline + `Match`で通過 |

This fixture is not complete at decomposition. Continue it through slice-prep, Parent Review Gate, and slice-impl authorization to prove the lightweight baseline path is closed.

## ASR-004: Slice-local details do not block readiness

### Fixture

```text
Participant ownership, precedence, state transitions, identity, retry/release, schema, capacity, invariants, and production wiring are defined.
Only helper names, internal class split, and fixture paths remain undecided.
```

### Expected

The residuals are `ImplementationDetail` or `SliceLocalContract`. With a current slice architecture artifact and no blocking residual, the verdict is `ReadyForSliceDecomposition`.

## ASR-005: Parent review detects decomposition drift

### Fixture

```text
Approved architecture: durable state owner is Participant A; Observation B is derived and read-only.
Slice-prep proposal: Participant B writes the canonical state when observation is newer.
```

### Expected

Parent review records `Drift`, sets `Can implement now? = No`, and routes back to `architecture-slice-readiness.agent.md`. The proposal must not become a slice-local contract or expected test fixture.

## ASR-006: Human authority stops the route

### Fixture

```text
Two valid source-precedence policies exist and the requirement sources do not choose one.
The choice changes externally observable recovery behavior.
```

### Expected

The residual and verdict are `NeedsHumanDecision`. Elaboration and decomposition stop until a human decision source is recorded.

## Negative scans

Run after changing the route. Matches are allowed only in historical explanation or explicit prohibition text.

```powershell
rg -n "full-coverage.*(always|必ず).*plan-slice-decomposition|immediate next.*plan-slice-decomposition" README.md docs .github apm-packages
rg -n "NeedsArchitectureElaboration|ReadyForSliceDecomposition|ArchitectureNotRequired" README.md docs .github apm-packages
rg -n "architecture-slice-readiness.agent.md|architecture-elaboration.agent.md|slice-architecture.md" README.md docs .github apm-packages
```

## Validation result template

The current executed result is stored in `docs/architecture-slice-readiness-validation-result.md`. Keep this template for future reruns.

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
5. For ASR-005, provide the approved architecture and drifting slice-prep output to the parent review gate.
6. Compare verdict, artifact requirement, residual classification, and next action with this suite.
7. Do not allow implementation, production writes, secrets, billing, external services, or GitHub setting changes during validation.
