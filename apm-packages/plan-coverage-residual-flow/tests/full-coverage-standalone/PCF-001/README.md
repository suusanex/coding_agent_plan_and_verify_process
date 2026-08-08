# PCF-001: standalone full-coverage lifecycle

PCF-001 is a deterministic test-only fixture for the current Plan Coverage full-coverage lifecycle. It represents a synthetic producer restore followed by a consumer startup gate.

The fixture applies `SL-001` and `SL-002` payloads in dependency order, runs an independent verifier after each slice, and then exercises the production entrypoint for cross-slice verification. The artifacts use the required output sections, table headers, handoff fields, verdict vocabulary, and Agent / Skill hashes derived from the current or installed Plan Coverage agents and canonical Coverage Ledger reference. The validator therefore rejects a fixture that preserves only selected keywords while omitting the current artifact structure.

This fixture does not invoke an external model and is not evidence that Codex, Copilot, or another model executed the lifecycle autonomously.
