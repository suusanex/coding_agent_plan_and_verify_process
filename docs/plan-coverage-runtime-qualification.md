# Plan Coverage runtime qualification matrix

This document separates **canonical Plan Coverage semantics**, **distribution projection**, and **runtime evidence**. It does not redefine process semantics.

## Canonical semantics

Authority:

```text
apm-packages/plan-coverage-residual-flow/.apm/
```

Package manifest:

```text
apm-packages/plan-coverage-residual-flow/apm.yml
```

Canonical semantics are runtime-neutral. Copilot qualification must not fork route authorization, Architecture Slice Readiness, Living Record, residual decision, Adaptive handoff, or Design Pair selection contracts.

Deterministic fingerprint (SHA-256 over LF-normalized `.apm/**` paths + contents, ordinal path sort) binds evidence to a specific canonical snapshot. When the fingerprint changes, prior Copilot QUALIFIED evidence is no longer current.

## Distribution projection

| Target | Verified by |
| --- | --- |
| `copilot` | `validate-plan-coverage-residual-flow-apm-smoke.ps1` |
| `codex` | same fresh APM smoke + checked-in Codex projection drift checks |
| `agent-skills` | same fresh APM smoke |

Fresh install smoke also checks transitive Adaptive Implementation assets and, for remote refs, installed full-coverage deterministic E2E.

## Runtime evidence — GitHub Copilot

| Field | Value |
| --- | --- |
| Qualified client surface | **GitHub Copilot CLI only** |
| Other Copilot surfaces (VS Code Agent mode, etc.) | **separate runtime qualification not performed** in Issue #106 |
| Evidence directory | `apm-packages/plan-coverage-residual-flow/tests/runtime-qualification/results/` |
| Schema | `tests/runtime-qualification/result.schema.json` |
| Authorization source | `tests/invocation-authorization-scenarios.json` (A–H; no duplicate authority) |
| Harness | `scripts/run-plan-coverage-copilot-qualification.ps1` |
| Static validator | `scripts/validate-plan-coverage-runtime-qualification.ps1` |

### Current qualification status

| Item | Status |
| --- | --- |
| overall_status | **PENDING (not QUALIFIED)** |
| client_version | pending real run |
| model | pending real run |
| APM version | pending real run |
| package version | `0.13.0` (see `apm.yml`) |
| candidate commit | pending real run |
| canonical fingerprint | computed at validation/run time |
| result file | none committed as QUALIFIED yet |
| authorization A–H | pending real run |
| standard-slice STD-001 | pending real run |
| full-coverage FULL-001 | pending real run |
| Adaptive connection | pending real run |

Update this table only when `run-plan-coverage-copilot-qualification.ps1` produces `overall_status: QUALIFIED` with a fingerprint matching the current `.apm` tree.

### Isolation and observation

- Each qualification scenario uses a temporary `COPILOT_HOME` so personal skills, agents, instructions, hooks, plugins, and saved permissions are not loaded.
- A qualification-only user-level hook observer records `sessionStart`, `userPromptSubmitted`, `subagentStart`, `subagentStop`, `agentStop`/`sessionEnd`, and `errorOccurred` to JSONL under a temporary evidence directory.
- Skill load events are often **UNOBSERVABLE** on Copilot CLI. Do not invent skill selection. Scenario PASS may still be justified from hooks, artifact deltas, verifiers, and final response.
- Raw transcripts and hook logs stay temporary unless debugging with `-KeepWorktree`. Committed evidence keeps metadata, prompts, observed agents, artifact deltas, and verdict rationale.

### Manual run

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1 `
  -ConfirmExternalModelPayload `
  -Model <available-copilot-model>

./apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-runtime-qualification.ps1
```

Optional remote package source:

```powershell
./apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1 `
  -ConfirmExternalModelPayload `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-sha> `
  -Model <available-copilot-model>
```

External model invocation is **not** part of ordinary pull_request CI.

## Runtime evidence — Codex

| Item | Boundary |
| --- | --- |
| Deterministic/static validation | existing Plan Coverage validators and standalone E2E |
| Historical runtime evidence | e.g. manual-model smoke / prior Codex runs under `tests/manual-model-smoke/` |
| Issue #106 | **does not** re-qualify Codex runtime |

## Non-claims

- Issue #106 does not revive pre-#99 Copilot qualification process semantics or the deleted 3-layer flow.
- Issue #106 does not create a separate “Copilot edition” of Plan Coverage.
- `disable-model-invocation: true` is **not** added to the Plan Coverage Skill (that would break affirmative natural-language selection).
- Design Pair is never auto-selected for Copilot qualification convenience.
