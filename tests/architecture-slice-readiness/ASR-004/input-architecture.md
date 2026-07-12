# ASR-004 Input Slice Architecture

- Artifact revision: `arch-1`
- Owner: Coordinator owns canonical state; Observer is read-only.
- Precedence: human instruction > canonical state > observation.
- Identity: `run_id` is stable across retry.
- Release: terminal outcome releases reservation.
- Production wiring: existing coordinator entrypoint.
- Invariant INV-001: observation cannot write canonical state.
