# PCF-001: standalone full-coverage lifecycle

PCF-001 is a deterministic test-only fixture for the current Plan Coverage full-coverage lifecycle. It represents a synthetic producer restore followed by a consumer startup gate.

The fixture uses `artifact_mode: slice-living-record`. It applies `SL-001` and `SL-002` payloads in dependency order, runs an independent verifier after each slice, records a bounded cross-slice FixNow candidate, applies triage and repair evidence to `SL-002`, reruns slice and cross-slice verification, and only then performs the separate residual decision. Each executable slice has one canonical Living Record and the final semantic gates plus repair-loop history share one Full-Coverage Close Record.

The validator derives the required Living Record, Coverage Ledger, and close shapes from the current or installed Plan Coverage references. It checks required fields and table schemas, section ownership, architecture `Match`, independent verification, the FixNow repair/re-verification loop, production binding, field continuity, pending Coverage Ledger Delta count, the pre-registered completion handoff and delayed-registration re-entry handoff Artifact Creation Gates, base artifact budget, required negative cases, and absence of ungated per-slice fan-out.

This fixture does not invoke an external model and is not evidence that Codex, Copilot, or another model executed the lifecycle autonomously.
