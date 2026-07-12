# Slice Architecture

This template defines shared architecture semantics required before full-coverage slice decomposition.
Do not use it to redesign requirements, choose slice count, or specify class / method / file details.

## Requirement baseline and source artifacts

```yaml
baseline:
  repository_ref:
  repository_commit:
  parent_plan: { path: "", revision_or_hash: "" }
  behavior_spec: { path: "N/A", revision_or_hash: "N/A" }
  change_risk_triage: { path: "", revision_or_hash: "" }
  architecture_readiness: { path: "", revision_or_hash: "" }
  architecture_artifact_revision:
  generated_at:
```

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

This artifact is `stale` when an upstream baseline revision/hash, repository commit affecting an inspected production evidence address, human decision source, or this artifact revision changes after readiness evaluation. Path equality alone never proves freshness.

## Readiness handoff

- Architecture baseline status: Draft / ReadyForReadinessRerun / BlockedByHumanDecision
- ArchitectureCritical residual count:
- NeedsHumanDecision residual count:
- Immediate next agent: architecture-slice-readiness.agent.md
