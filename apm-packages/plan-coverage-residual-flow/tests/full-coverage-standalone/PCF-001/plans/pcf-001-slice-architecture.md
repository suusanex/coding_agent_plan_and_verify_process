# PCF-001 Slice Architecture

- `SL-001` owns producer recovery and atomic publication of `snapshot_state`, `correlation_id`, `generation`, and `published`; no consumer may write this store.
- `SL-002` independently owns consumer startup and idempotent replay, validates the expected identity, rejects stale or incomplete publications, and binds both slices through `src/StartupFlow.ps1`.
- `XC-001` fixes the producer/consumer protocol: durable identity is `correlation_id` plus `generation`, the producer is the sole state authority, a consumer is read-only, and only a fully published matching generation may become `Accepting`.
- Forbidden state: consumer `Accepting` while the store is missing, incomplete, or has a different `correlation_id` or `generation`.
- Dependency order is `SL-001 -> SL-002`.
