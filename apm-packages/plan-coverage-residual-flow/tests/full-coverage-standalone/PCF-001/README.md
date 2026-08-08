# PCF-001: standalone full-coverage lifecycle

PCF-001 is a deterministic test-only fixture for the current Plan Coverage full-coverage lifecycle. It represents a synthetic producer restore followed by a consumer startup gate.

The fixture applies `SL-001` and `SL-002` payloads in dependency order, runs an independent verifier after each slice, and then exercises the production entrypoint for cross-slice verification. The artifacts preserve the normal bounded Plan, pre-implementation, architecture compatibility, implementation, verification, coverage, and residual-decision evidence expected by the current contract.

This fixture does not invoke an external model and is not evidence that Codex, Copilot, or another model executed the lifecycle autonomously.
