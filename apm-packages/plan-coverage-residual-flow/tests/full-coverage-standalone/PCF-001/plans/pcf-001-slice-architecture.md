# PCF-001 Slice Architecture

- `SL-001` owns producer snapshot restoration and emits `snapshot_state` plus `correlation_id`.
- `SL-002` consumes the producer result, owns consumer acceptance and rejection, and binds both slices through `src/StartupFlow.ps1`.
- `XC-001` requires the producer field names and correlation value to remain unchanged across the boundary.
- Dependency order is `SL-001 -> SL-002`.
