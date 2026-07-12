# ASR-002 Input Plan

The Plan is `ReadyForRiskTriage` and defines all observable behavior. Two durable artifacts may report the same lifecycle state. The authoritative source and the reservation release behavior after retry exhaustion are intentionally unspecified.

- AC-001: conflicts must fail closed.
- AC-002: capacity must not leak after terminal failure.
