# PCF-001: standalone full-coverage lifecycle

PCF-001 is a deterministic test-only fixture for the current Plan Coverage full-coverage lifecycle. It represents a synthetic producer restore followed by a consumer startup gate.

The fixture uses `artifact_mode: slice-living-record`. It applies `SL-001` and `SL-002` payloads in dependency order, runs an independent verifier after each slice, applies every stable Coverage Ledger Delta, and then exercises the production entrypoint for cross-slice verification before a separate residual decision. Each executable slice has one canonical Living Record and the final two semantic gates share one Full-Coverage Close Record.

The validator derives the required Living Record and close shapes from the current or installed Plan Coverage references. It checks section ownership, architecture `Match`, independent verification, production binding, field continuity, pending Coverage Ledger Delta count, Artifact Creation Gate policy, base artifact budget, required negative cases, and absence of the old per-slice fan-out.

This fixture does not invoke an external model and is not evidence that Codex, Copilot, or another model executed the lifecycle autonomously.
