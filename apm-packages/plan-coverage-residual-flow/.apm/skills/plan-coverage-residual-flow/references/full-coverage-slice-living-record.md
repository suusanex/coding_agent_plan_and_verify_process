# Full-Coverage Slice Living Record

Use this reference only for an executable slice in a new `full-coverage` run whose decomposition records `artifact_mode: slice-living-record`.

The Plan Coverage parent/router is the only repository writer for this record and the canonical Coverage Ledger. Semantic owners return `Section Delta` plus any `Coverage Ledger Delta`; they do not edit repository files in this mode. Reject a delta that targets another section, another slice, or an unknown owner.

```md
# SL-xxx: <slice name>

## Record Metadata

- Parent Plan:
- Slice ID:
- artifact_mode: slice-living-record
- documentation_level: standard
- implementation_route:
- implementation_route_source:
- design_pair_handoff:
- design_pair_interaction_stage:
- Canonical Coverage Ledger:
- Current architecture baseline:
- Artifact exceptions:

## Slice Plan / Scope

- Goal:
- Non-goals:
- Parent requirements covered:
- Parent acceptance conditions covered:
- Affected components / modules:
- Expected implementation scope:
- Stop condition:

## Parent / Behavior Mapping

### FR / AC mapping

### Black-box Behavior Coverage

### Case-to-Slice Mapping

## Cross-Slice Contracts / Field Continuity

- Related XC IDs:
- Producer / Consumer role:
- Required fields / state / identifiers:
- Source authority:
- Deferred / unresolved items:

## Slice Risk / Guardrail Selection

- Inherited parent risks:
- Slice-local added risks:
- Slice-local removed / not-applicable risks:
- Implementation realization risk:
- Selected Runtime Contract IDs:
- Selected Test Point scope:
- Human decision blockers:
- Recommended next phase:

## Implementation Contract Decisions

N/A when no implementation-realization analysis is required.

## Runtime Contract

N/A when no Guardrail Focus runtime contract is required.

## Test Design

N/A when no Test Design Kernel is required.

## Inline Ready Gate

- Formal implementation-handoff-review verdict:
- Readiness scope:
- Parent coverage state:
- Behavior Case coverage state:
- Architecture baseline identity:
- Architecture compatibility: Match / Drift / Unclear
- Implementation allowed:
- Blocking issues:

## Implementation Evidence

- Implementation route:
- Model / owner sequence:
- Files / symbols changed:
- Validation performed:
- Acceptance evidence:
- Remaining work:

### Implementation Self-Map

| Change ID | Change | File / Symbol | Reason | Related Plan item | Related Behavior Case IDs | Related SL / XC / RC / TP / IC / Gap item | Assumption made | Review hint |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |

## Verification Result

- Formal verification-kernel verdict:
- Verification scope:
- Production binding evidence:
- Behavior Case evidence:
- Fake / stub / mock assessment:
- Remaining gaps:

## Coverage Ledger Delta

| Delta ID | Source phase | Plan item / Case ID / Residual ID | Previous status | New status | Evidence / reason | Applied to canonical ledger? |
| --- | --- | --- | --- | --- | --- | --- |

## Slice Residuals / Handoff

- FixNow candidates:
- Manual verification candidates:
- NeedsHumanDecision:
- Cross-slice verification dependencies:
- Remaining blocking items:
- Recommended next step:

## Artifact Exceptions

| Path | Reason code | Why separate artifact is required | Owner | Canonical or supplemental | Lifecycle |
| --- | --- | --- | --- | --- | --- |
```

## Section ownership

| Section | Semantic owner | Repository writer |
| --- | --- | --- |
| Record Metadata | Plan Coverage parent | Plan Coverage parent |
| Slice Plan / Scope | `plan-slice-decomposition` | Plan Coverage parent |
| Parent / Behavior Mapping | `plan-slice-decomposition` | Plan Coverage parent |
| Cross-Slice Contracts / Field Continuity | `plan-slice-decomposition` | Plan Coverage parent |
| Slice Risk / Guardrail Selection | `change-risk-triage` slice-local delta mode | Plan Coverage parent |
| Implementation Contract Decisions | `implementation-contract-kernel` | Plan Coverage parent |
| Runtime Contract | `runtime-contract-kernel` | Plan Coverage parent |
| Test Design | `test-design-kernel` | Plan Coverage parent |
| Inline Ready Gate | `implementation-handoff-review` | Plan Coverage parent |
| Implementation Evidence / Implementation Self-Map | Adaptive result aggregation | Plan Coverage parent |
| Verification Result | `verification-kernel` | Plan Coverage parent |
| Coverage Ledger Delta | semantic owner of the source phase | Plan Coverage parent |
| Slice Residuals / Handoff | verification / gap classification | Plan Coverage parent |
| Artifact Exceptions | Plan Coverage parent | Plan Coverage parent |

## Section delta protocol

Every semantic owner receives:

```yaml
artifact_mode: slice-living-record
living_record_path: plans/<slug>-slice-SL-xxx.md
canonical_coverage_ledger: plans/<slug>-coverage-ledger.md
output_contract: section-delta
```

It returns:

```md
## Section Delta

- Target record: plans/<slug>-slice-SL-xxx.md
- Target section: <owned section>
- Semantic owner: <agent name>
- Replace owned section: Yes

<complete replacement body for the owned section>

## Coverage Ledger Delta

| Delta ID | Source phase | Plan item / Case ID / Residual ID | Previous status | New status | Evidence / reason | Applied to canonical ledger? |
| --- | --- | --- | --- | --- | --- | --- |
```

The parent validates target path, target section, semantic owner, current section, and stable Delta IDs, then applies both writes atomically. It marks a delta `Applied` only after the canonical ledger write succeeds. Verification fails closed when any earlier authorization or implementation delta is pending. Close fails closed when any delta is pending or when the record contradicts the canonical ledger (`SourceOfTruthDrift`).

## Artifact Creation Gate

A separate slice-local artifact is allowed only after the parent records an `Artifact Exceptions` row with one of these reason codes:

- `cross-thread-handoff`
- `parallel-write-isolation`
- `human-approval-wait`
- `external-audit-evidence`
- `record-size-limit`

The exception is supplemental unless the existing contract explicitly requires otherwise. It must not replace the parent Plan, Slice Living Record, or canonical Coverage Ledger. Different slices may progress in parallel because they have different records; multiple writers must not edit the same slice record concurrently.
