# Slice Architecture

This template defines shared architecture semantics required before full-coverage slice decomposition.
Do not use it to redesign requirements, choose slice count, or specify class / method / file details.

## Requirement baseline and source artifacts

```yaml
baseline:
  repository_ref:
  source_repository_commit:
  tracked_sources:
    - { role: parent_plan, path: "", revision_type: content_sha256, revision: "" }
    - { role: behavior_spec, path: "N/A", revision_type: N/A, revision: "N/A" }
    - { role: change_risk_triage, path: "", revision_type: content_sha256, revision: "" }
    - { role: architecture_readiness_input, path: "", revision_type: content_sha256, revision: "" }
  watch_paths: []
  artifact_revision: 1
  generated_at:
```

`artifact_revision` is an explicit monotonically increasing ID, not this file's content hash. The readiness artifact records an externally computed content hash for this file.

Keep `watch_paths` bounded to baseline-affecting production, schema, config, and decision sources. Do not use a broad generated-artifact directory glob that would make this artifact's own commit invalidate the baseline.

- Parent Plan:
- Black-box Behavior Spec:
- Change Risk Triage:
- Architecture Slice Readiness:
- Existing architecture sources:

## Runtime participants and responsibilities

| Participant | Responsibility | Owned state | Allowed writes | Forbidden writes | Evidence mode | Source / production evidence address |
| --- | --- | --- | --- | --- | --- | --- |

## Source-of-truth matrix

| Concept | Owner / canonical source | Readers | Precedence | Conflict handling | Evidence mode | Source / production evidence address |
| --- | --- | --- | --- | --- | --- | --- |

## Canonical state model

| State domain | Canonical states | Owner | Durable / derived | Meaning |
| --- | --- | --- | --- | --- |

Cover official, preparation, execution, observation, human instruction, review, and Return Gate state when applicable.

## State transition and decision table

| Input state tuple / event | Classification | Lane / capacity | Eligibility | Permitted effect | Next state | Rejection / fail-closed behavior |
| --- | --- | --- | --- | --- | --- | --- |

## Major sequences

Describe prepare, activation, active, failure / retry, human-required, PR / result, Return Gate, release, and cleanup sequences when applicable.

## Cross-boundary contracts

| ID | Producer | Consumer | Mechanism | Fields / state | Identity continuity | Timeout / retry / recovery |
| --- | --- | --- | --- | --- | --- | --- |

## Resource coordination

| Resource | Lane / lock / reservation / capacity semantics | Acquire | Retain | Release / cleanup | Owner |
| --- | --- | --- | --- | --- | --- |

## Invariants and forbidden states

| ID | Invariant / forbidden state | Source FR / AC / Case | Enforcement owner | Verification oracle |
| --- | --- | --- | --- | --- |

## Production entrypoints and wiring

| Entrypoint | Production participant | Wiring / provider | Required state / config | Failure behavior | Evidence mode | Production evidence address |
| --- | --- | --- | --- | --- | --- | --- |

## Cross-slice verification postconditions

| Parent AC / Case | Producer action | Production path | Consumer observable | Forbidden state to deny | Required evidence strength |
| --- | --- | --- | --- | --- | --- |

## Architecture residual classification

| ID | Classification | Topic | Source / evidence | Owner | Blocking? | Next action |
| --- | --- | --- | --- | --- | --- | --- |

Allowed classifications: `ArchitectureCritical`, `NeedsHumanDecision`, `SliceLocalContract`, `ImplementationDetail`, `OutOfScopeWithSource`.

## Files inspected

| File / address | Why inspected | Architecture decisions supported |
| --- | --- | --- |

## Files intentionally not inspected

| File / area | Why not required | Revisit trigger |
| --- | --- | --- |

## Freshness rule

This artifact is `stale` when a tracked source revision/content hash changes, a diff after `source_repository_commit` touches a declared watch path or inspected production evidence address, a human decision source changes, or the explicit artifact revision changes. A HEAD change containing only generated readiness/architecture artifacts does not invalidate the baseline. Path equality alone never proves freshness.

## Readiness handoff

- Architecture baseline status: Draft / ReadyForReadinessRerun / BlockedByHumanDecision
- ArchitectureCritical residual count:
- NeedsHumanDecision residual count:
- Immediate next agent: architecture-slice-readiness.agent.md
