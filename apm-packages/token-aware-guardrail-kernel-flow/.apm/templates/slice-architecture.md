# Slice Architecture

This template defines shared architecture semantics required before full-coverage slice decomposition.
Do not use it to redesign requirements, choose slice count, or specify class / method / file details.

## Requirement baseline and source artifacts

- Parent Plan:
- Black-box Behavior Spec:
- Change Risk Triage:
- Architecture Slice Readiness:
- Existing architecture sources:

## Runtime participants and responsibilities

| Participant | Responsibility | Owned state | Allowed writes | Forbidden writes |
| --- | --- | --- | --- | --- |

## Source-of-truth matrix

| Concept | Owner / canonical source | Readers | Precedence | Conflict handling |
| --- | --- | --- | --- | --- |

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

| Entrypoint | Production participant | Wiring / provider | Required state / config | Failure behavior |
| --- | --- | --- | --- | --- |

## Cross-slice verification postconditions

| Parent AC / Case | Producer action | Production path | Consumer observable | Forbidden state to deny | Required evidence strength |
| --- | --- | --- | --- | --- | --- |

## Architecture residual classification

| ID | Classification | Topic | Source / evidence | Owner | Blocking? | Next action |
| --- | --- | --- | --- | --- | --- | --- |

Allowed classifications: `ArchitectureCritical`, `NeedsHumanDecision`, `SliceLocalContract`, `ImplementationDetail`, `OutOfScopeWithSource`.

## Readiness handoff

- Architecture baseline status: Draft / ReadyForReadinessRerun / BlockedByHumanDecision
- ArchitectureCritical residual count:
- NeedsHumanDecision residual count:
- Immediate next agent: architecture-slice-readiness.agent.md
