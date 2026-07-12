# ASR-001 Actual Slice Architecture

- Artifact revision: `arch-1`
- Evidence mode: `GreenfieldDesignDecision`

## Baseline

```yaml
tracked_sources:
  - { role: parent_plan, path: input-plan.md, revision_type: content_sha256, revision: fixture-plan-v1 }
  - { role: change_risk_triage, path: input-triage.md, revision_type: content_sha256, revision: fixture-triage-v1 }
watch_paths: []
artifact_revision: arch-1
```

## Elaboration trigger

```yaml
elaboration_trigger:
  readiness_path: plans/example-architecture-slice-readiness.md
  readiness_revision: readiness-r1
  blocking_residual_ids: [AR-001, AR-002, AR-003, AR-004]
  decision_sources: [input-plan.md, input-triage.md]
  freshness_dependency: false
```

R1 is retained for audit only and is intentionally absent from `tracked_sources`.

## Runtime participants

- Control plane owns desired state and capacity reservation.
- Worker owns execution state and may not write desired state.
- Observer produces derived read-only observation.
- Human Return Gate owns explicit resume / abort instruction.

## Source precedence

Human instruction > durable desired state > worker execution state > derived observation.

## Identity and resource coordination

- `run_id` is allocated by the control plane and retained across retry / resume.
- Capacity is acquired before activation, retained during retry, and released on terminal result, abort, or accepted Return Gate outcome.

## Forbidden states

- Observer writes canonical desired state.
- Two active reservations share one capacity slot.
- Retry creates a new `run_id`.
