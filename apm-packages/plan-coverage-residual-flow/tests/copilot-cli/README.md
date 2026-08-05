# GitHub Copilot CLI qualification

This runbook verifies the package boundary that GitHub Copilot CLI actually
consumes. It does not restate the Plan Coverage contract. The canonical
contract remains the installed Skill, shared instruction, and portable agents.

## Observed integration boundary

APM 0.26.0 installs this package for the `copilot,agent-skills` targets. In a
disposable repository the observed paths are:

```text
.agents/skills/plan-coverage-residual-flow/SKILL.md
.agents/skills/plan-coverage-residual-flow/references/*
.github/instructions/plan-coverage-shared.instructions.md
.github/agents/*.agent.md
```

GitHub Copilot CLI discovers the Skill from `.agents/skills` and custom agents
from `.github/agents`. Verify the boundary without invoking a model:

```powershell
copilot --version
apm --version
copilot skill list
```

No Copilot-only process adapter is required. APM already deploys the canonical
Skill, shared instruction, and agent files to the paths read by the CLI.

## Install

Run from the root of a disposable repository and pin a full commit SHA:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow#<full-commit-sha> --target copilot,agent-skills --https
copilot skill list
```

The package source repository is the supported full-package installation
boundary. APM 0.26.0 rejects a package directory whose root manifest still
uses `git: parent`; local package-directory installation is therefore not
evidence for the package dependency graph. The qualification harness supports
local Skill-only discovery for working-tree development and records that
limitation instead of presenting it as a full package install.

## Update, rollback, and integrity checks

Use the APM lockfile as the durable package identity:

```powershell
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow --dry-run
apm update suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow --yes
apm install --frozen
apm audit --ci
```

Rollback is an explicit reinstall of a known-good commit, followed by a
frozen install and CLI discovery:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow#<known-good-commit-sha> --target copilot,agent-skills --https
apm install --frozen
copilot skill list
```

Removal and orphan cleanup are explicit:

```powershell
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow --dry-run
apm uninstall suusanex/coding_agent_plan_and_verify_process/apm-packages/plan-coverage-residual-flow
apm prune --dry-run
```

Do not use `--force` to replace an unmanaged `.github/agents/*.agent.md`
collision without first confirming package ownership.

## Invocation, documentation level, and resume

The Skill remains explicit-invocation-only. A direct prompt must select the
literal route name:

```text
$plan-coverage-residual-flow を使って、この issue を進めてください。
```

Generic implementation requests, task size, risk, existing artifacts,
questions, quotations, comparisons, and negations do not authorize the route.
The `lite` and `standard` values are documentation levels. `strict` is not a
level, and `full-coverage` is a process profile rather than a documentation
level. The route metadata remains:

```yaml
implementation_route: adaptive
implementation_route_source: default
```

Only explicit Design Pair user selection may produce the separate
`design-pair / explicit-user-selection` pair. Issue #69 remains the explicit
blocker for the Design Pair Copilot E2E scenario; do not fall back to Adaptive
or reimplement that contract locally.

Copilot CLI conversation resume is available through the observed CLI flags:

```powershell
copilot --continue
copilot --resume=<session-id>
copilot --session-id=<session-or-task-id>
```

Conversation resume does not replace durable process state. A new session must
read the tracked Plan Coverage artifact, route metadata, authorization
evidence, coverage ledger, Parent State, Slice Records, or Final Record required
by the current phase. Missing or contradictory route or layout metadata fails
closed rather than defaulting to Adaptive.

## Manual acceptance: artifact-authoritative new-session resume

This is a human-required acceptance and is **not currently passed**. The
committed `new-session-resume` result remains `UNOBSERVABLE`. Do not promote it
to `PASS` from `copilot --resume`, `copilot --continue`, static fixtures, or
Skill discovery.

In a disposable repository, first create and commit a valid, internally
consistent set of tracked artifacts:

- Parent Orchestration State pointing to the Plan Coverage ledger and the
  current phase;
- Plan Coverage ledger with the authorized requirement rows and route
  authorization;
- `implementation_route: adaptive` and
  `implementation_route_source: default` (or an explicitly user-selected
  route with its evidence);
- the last verdict and its validation evidence; and
- the exact next action, owner, and fail-closed conditions.

Start a **fresh Copilot CLI session with no conversation history as authority**
using plain `copilot` (do not use `--continue` or `--resume` to establish
process state). Ask it to reload the tracked artifacts and continue only from
the recorded next action. Verify that it reloads the committed artifacts,
preserves route metadata, and stops fail-closed when an artifact is missing,
stale, or contradictory.

The human evidence bundle must be committed or otherwise retained at a tracked
path and record all of the following:

1. exact prompt text and the fresh-session command;
2. Copilot CLI/APM/package version and source revision;
3. raw CLI output and debug-log paths plus SHA-256 hashes;
4. every Parent State, ledger, authorization, verdict, and next-action path
   with its before/after SHA-256;
5. changed-file manifest (including an explicit no-change result);
6. the ordered verdict sequence and observed route metadata; and
7. a negative fresh-session run showing the expected fail-closed verdict for
   missing or contradictory artifacts.

Only this real, artifact-authoritative process resume evidence can justify
`artifact_authoritative_resume: PROVEN`; until then record
`artifact_authoritative_resume: NOT_PROVEN` and
`REAL_SCENARIO_INCOMPLETE`.

## Capability honesty

`copilot --model <model>` selects a session model, but the CLI does not provide a
portable proof that every process phase honors a requested per-agent model
mapping. Custom-agent frontmatter may also be ignored when the selected model
backend is unavailable. Qualification records requested and observed models
separately and marks a model-lock claim unsupported or manual when the CLI
cannot expose it. The package never claims automatic HIGH/STANDARD/HIGH
enforcement from a static file alone.

## Deterministic and real CLI evidence

The deterministic matrix reuses the existing authorization fixture and points
to the canonical Adaptive and full-coverage artifacts:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\validate-plan-coverage-residual-flow-copilot.ps1
```

The reproducible harness installs a pinned package in a repository-local run
directory, records the lockfile, deployed paths, CLI versions, and
`copilot skill list`, and can optionally execute one explicitly supplied
read-only prompt:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\run-copilot-cli-qualification.ps1 `
  -PackageName plan-coverage-residual-flow `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-commit-sha>
```

The full-package check is independent from the canonical contract validator.
It installs the exact remote head with both Copilot targets and verifies the
package version, deployed `.agents/skills`, `.github/instructions`,
`.github/agents`, lockfile source/ref/content hash/deployed-file hash, and
unmanaged custom-agent collision protection:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\validate-copilot-full-package-install.ps1 `
  -PackageName plan-coverage-residual-flow `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-commit-sha>
```

Use `-PackageName token-aware-full-coverage-3layer` for the Full Coverage
package. APM 0.26.0 may reject a package-directory install whose root
dependencies use `git: parent`; that limitation applies to local package
directory mode only and does not weaken the remote full-SHA check.

For a working-tree Skill-only probe, add
`-LocalSkillPath .\apm-packages\plan-coverage-residual-flow\.apm\skills\plan-coverage-residual-flow`.
This mode is labeled as local Skill-only evidence. It is not a substitute for
the pinned remote package install.

Use `result-template.md` for model scenarios. A completed result JSON can be
fed back to the harness with `-ScenarioResultsPath`; every non-blocked fixture
scenario must be `PASS` before the harness may emit `QUALIFICATION_PASS`.
`NOT RUN`, `UNOBSERVABLE`, and `FAIL` produce `REAL_SCENARIO_INCOMPLETE`, while
local Skill-only execution produces `LOCAL_SKILL_ONLY` and is never
qualification evidence. The Design Pair scenario is recorded as `BLOCKED`
until #69 is available.

To record an intentionally incomplete real-model run without converting it
into a pass, add `-AllowIncomplete`:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\run-copilot-cli-qualification.ps1 `
  -PackageName plan-coverage-residual-flow `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref <full-commit-sha> `
  -ScenarioResultsPath .\apm-packages\plan-coverage-residual-flow\tests\copilot-cli\results\20260805-real-cli-qualification.json `
  -AllowIncomplete
```
