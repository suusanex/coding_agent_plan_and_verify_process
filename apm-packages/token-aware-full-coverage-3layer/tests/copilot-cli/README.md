# GitHub Copilot CLI qualification

The full-coverage package uses the same APM-to-Copilot boundary as Plan
Coverage. The canonical Skill, instruction, `slice-prep`, and Adaptive agent
contracts remain the source of truth; this document only maps the CLI entry
point and evidence surface.

## Install and inspect

From a disposable repository, pin the package to a full commit SHA:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer#<full-commit-sha> --target copilot,agent-skills --https
copilot --version
apm --version
copilot skill list
```

The observed deployed paths are:

```text
.agents/skills/token-aware-full-coverage-3layer/SKILL.md
.agents/skills/token-aware-full-coverage-3layer/references/*
.github/instructions/token-aware-full-coverage-3layer.instructions.md
.github/instructions/plan-coverage-shared.instructions.md
.github/agents/*.agent.md
```

APM 0.26.0 is the validated package lifecycle boundary. A local package
directory with root `git: parent` dependencies is not a full-package install;
use a remote full commit for dependency-graph evidence. The shared harness
records a local Skill-only fallback as a different install mode when working
tree changes are not yet published.

## Update, rollback, check, and remove

```powershell
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer --dry-run
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer --yes
apm install --frozen
apm audit --ci
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer#<known-good-commit-sha> --target copilot,agent-skills --https
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/token-aware-full-coverage-3layer
apm prune --dry-run
```

Use `--force` only after an unmanaged custom-agent collision is confirmed to
be package-owned.

## Use and durable resume

Start this process only after the parent Plan Coverage `full-coverage` route,
Architecture Slice Readiness, and slice decomposition gates authorize it. Do
not select it from task size or risk, and do not re-enter the parent flow for
each slice.

Fresh work records:

```yaml
full_coverage_artifact_layout: compact-slice-record-v2
implementation_route: adaptive
implementation_route_source: default
```

`Parent Orchestration State` is the mandatory durable resume entrypoint. It
must point to the canonical Coverage Ledger, Slice Records, and Final Record.
New-session conversation resume can use the CLI:

```powershell
copilot --continue
copilot --resume=<session-id>
```

The process state must still be reloaded from the tracked Parent State. Missing,
stale, mixed, or contradictory layout, route, baseline, authorization, or
freshness metadata returns `BlockedByArtifactLayoutMismatch` or the applicable
fail-closed verdict. Existing `legacy-split-v1` runs remain legacy-resume only;
they are not migrated.

## Qualification and evidence

The package-owned deterministic fixture binds Architecture Slice Readiness,
compact v2 ownership, Parent Authorization, Adaptive delegation,
independent verification, Final Record, residual decisions, legacy resume, and
stale-layout failures:

```powershell
.\apm-packages\token-aware-full-coverage-3layer\scripts\validate-token-aware-full-coverage-3layer-copilot.ps1
```

Run the shared real CLI harness from the repository root:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\run-copilot-cli-qualification.ps1 `
  -PackageName token-aware-full-coverage-3layer `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-commit-sha>
```

Use the shared [qualification result template](../../../plan-coverage-residual-flow/tests/copilot-cli/result-template.md)
for the model scenario matrix. Keep full-coverage-specific fixture bindings in
`qualification-scenarios.json` in this directory.

The Design Pair scenario remains `BLOCKED` until Issue #69 merges its
canonical Copilot support. Do not implement a local Design Pair adapter or
claim Adaptive fallback as qualification evidence.

Copilot CLI model selection is session-scoped and may not expose a reliable
per-agent HIGH/STANDARD/HIGH lock. Record requested and observed values
separately and classify an unavailable observation as unsupported or manual.
