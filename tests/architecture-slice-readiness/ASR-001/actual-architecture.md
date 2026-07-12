# ASR-001 Actual Slice Architecture

- Artifact revision: `arch-1`
- Evidence mode: `GreenfieldDesignDecision`

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
