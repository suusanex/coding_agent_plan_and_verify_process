# ASR-008 Input Plan

Update a local platform operation and its status presentation while preserving one existing durable-state path.

- The UI invokes one same-process platform boundary and receives completion through the existing UI-thread handoff.
- The same operation owner writes one existing durable store.
- A later process reads that state through the existing startup path.
- Acceptance condition: one production entrypoint and one end-to-end verifier cover the complete ordered sequence.
- Plan readiness: `ReadyForRiskTriage`.
