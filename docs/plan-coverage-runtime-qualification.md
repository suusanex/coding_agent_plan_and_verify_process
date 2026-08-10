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
| overall_status | **QUALIFIED** |
| client_version | GitHub Copilot CLI 1.0.78 |
| model | client-selected-or-unobserved |
| APM version | 0.26.0 |
| package version | `0.13.0` |
| candidate commit | recorded in result file (worktree dirty at evidence time) |
| canonical fingerprint | `98a49a9a3efa807363d3f4411f01f15992642fd1f4224fa8d8a57de2aa0e4ffb` |
| result file | `tests/runtime-qualification/results/2026-08-10-copilot-cli.json` |
| authorization A–H | PASS |
| standard-slice STD-001 | PASS |
| full-coverage FULL-001 | PASS |
| Adaptive connection | PASS (HIGH/STANDARD evidence on STD-001 and/or FULL-001) |
| Design Pair auto-selection | not observed |

Update this table only when `run-plan-coverage-copilot-qualification.ps1` produces `overall_status: QUALIFIED` with a fingerprint matching the current `.apm` tree. After canonical `.apm` changes, re-run qualification; stale fingerprints must not remain QUALIFIED.

### Isolation and observation

- Each qualification scenario uses a temporary `COPILOT_HOME` so personal skills, agents, instructions, hooks, plugins, and saved permissions are not loaded.
- A qualification-only user-level hook observer records `sessionStart`, `userPromptSubmitted`, `subagentStart`, `subagentStop`, `agentStop`/`sessionEnd`, and `errorOccurred` to JSONL under a temporary evidence directory.
- Skill load events are often **UNOBSERVABLE** on Copilot CLI. Do not invent skill selection. Scenario PASS may still be justified from hooks, artifact deltas, verifiers, and final response.
- Fixture verifiers run under **pwsh** (PowerShell 7+), not Windows PowerShell 5.1.
- Raw transcripts and hook logs stay temporary unless debugging with `-KeepWorktree`. Committed evidence keeps metadata, prompts, observed agents, artifact deltas, and verdict rationale.
- Kept-worktree re-evaluation without new model calls:
  `run-plan-coverage-copilot-qualification.ps1 -ReevaluateFromRunRoot <temp-run-root>`

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
