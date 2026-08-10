# Agent Plugins direct-load PoC (Issue #107)

Controlled experiment: generate an Agent Plugins v1.0.0–aware plugin-format bundle from the **same** Plan Coverage canonical source (`.apm/**`) used by APM distribution, then probe GitHub Copilot CLI direct plugin load **without** `apm install` of Plan Coverage into the fixture.

This does **not** replace [#106 runtime qualification](../runtime-qualification/README.md).

## Authority

| Concern | Authority |
| --- | --- |
| Process semantics | `../../.apm/**` only |
| Authorization A–H | `../invocation-authorization-scenarios.json` (sole catalog) |
| STD-001 / FULL-001 fixtures | `../runtime-qualification/copilot-cli/**` |
| #106 APM baseline | `../runtime-qualification/results/2026-08-10-copilot-cli.json` |
| Package version | `0.13.0` (no bump for this PoC) |

## Commands

```powershell
# Deterministic (CI-safe): build + conformance + negative mutations
./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-agent-plugin.ps1

# Build only
./apm-packages/plan-coverage-residual-flow/scripts/build-plan-coverage-agent-plugin.ps1 -OutputDir $env:TEMP/pc-plugin -Force

# Discovery/install without model
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-plugin-poc.ps1 -DiscoveryOnly

# Full external-model PoC (opt-in)
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-plugin-poc.ps1 -ConfirmExternalModelPayload
```

## Forbidden

- Editing `.apm/**` to hide plugin gaps
- Duplicating Skill/agents as a second process implementation under source `skills/` or `agents/`
- Seeding fixtures via `apm install` of Plan Coverage before plugin load
- Hand-copying `.github/instructions/plan-coverage-shared.instructions.md` into plugin fixtures to force PASS
- Rewriting #106 evidence files

## Results

Committed results live under `results/`. Schema: `result.schema.json`.
