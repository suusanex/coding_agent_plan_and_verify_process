# Adaptive Routing Validation

この文書は `adaptive-implementation-execution` の routing contract を検証するシナリオです。各 scenario は、input、observed evidence、expected route、禁止事項を記録できる形にします。

## Common evidence

実行 validation では次を保存します。

- source Plan / Implementation Intent
- agent verdict sequence
- implementation owner by phase
- files changed by each agent
- validation commands and results
- acceptance status and evidence for every in-scope item
- handoff persistence
- re-entry handoff, if any
- final review status

## VAL-001: Early delegation

Input:

- external behavior is small
- existing implementation pattern is clear
- HIGH_MODEL edits a representative production case and runs a focused test
- only same-pattern cases and tests remain

Expected:

```text
READY_FOR_STANDARD_COMPLETION -> COMPLETED
```

Checks:

- HIGH_MODEL edited production code or tests before delegation
- handoff names files, symbols, expected behavior, and allowed surface
- handoff records acceptance status and applicability evidence, including reasons for any N/A concern
- every Incomplete acceptance item and Remaining work row has a bidirectional Work ID mapping, no Blocked item exists, and every Complete item has evidence
- STANDARD_MODEL makes no structural change

## VAL-002: Mid-implementation delegation

Input:

- class responsibility, DI, representative production path, and test seam require decisions
- HIGH_MODEL implements those decisions and passes build / smoke test
- validation branches and test cases remain

Expected:

```text
READY_FOR_STANDARD_COMPLETION -> COMPLETED
```

Checks:

- locked decisions include responsibility, wiring, signature, and test seam
- STANDARD_MODEL handles only remaining branches and tests

## VAL-003: HIGH_MODEL completes

Input:

- state ownership, error handling, and API shape decisions continue through implementation
- no natural delegation point exists

Expected:

```text
COMPLETED_BY_HIGH_MODEL
```

Checks:

- no artificial skeleton or broken intermediate state is created for delegation
- HIGH_MODEL records completed scope and checks
- every in-scope acceptance item is Complete with implementation or validation evidence

## VAL-004: Re-entry from STANDARD_MODEL

Input:

- HIGH_MODEL initially delegates
- STANDARD_MODEL discovers that test seam or production wiring must change

Expected:

```text
READY_FOR_STANDARD_COMPLETION
  -> NEEDS_HIGH_MODEL_REENTRY
  -> high-implementation-starter resumes
```

Checks:

- STANDARD_MODEL does not redesign the seam or wiring
- High-model Re-entry Handoff contains invalidating evidence and worktree state
- STANDARD_MODEL increments incoming reentry_count and preserves incoming previous_reentry_trigger
- HIGH_MODEL preserves the incremented count and copies the returned Trigger to previous_reentry_trigger only when a strictly smaller handoff is safe
- agents run serially
- HIGH_MODEL owns completion after the first re-entry unless Remaining work and Allowed edit surface both strictly shrink and the same trigger has not recurred

## VAL-005: Insufficient Plan

Input:

- Plan contains a goal but scope or acceptance cannot be determined

Expected:

```text
REPLAN_REQUIRED or HUMAN_DECISION_REQUIRED
```

Checks:

- no production code or tests are edited
- missing product / scope / acceptance decision is explicit

## VAL-006: Plan Coverage independence

Input:

- ordinary Plan exists
- no change-risk-triage, runtime-contract, test-design, handoff-review, coverage-ledger, or residual-decision artifact exists

Expected:

- skill starts from the ordinary Plan
- missing Plan Coverage artifacts are not blockers

Manifest check:

- package has no dependency on `token-aware-guardrail-kernel-flow`, `token-aware-full-coverage-3layer`, or `codex-first-ai-development-process`

## VAL-007: No write-heavy parallelism

Input:

- a valid HIGH_MODEL handoff exists

Expected:

- STANDARD_MODEL starts only after HIGH_MODEL run and handoff validation complete
- re-entry starts only after STANDARD_MODEL stops and returns its handoff

Checks:

- no overlap between HIGH_MODEL and STANDARD_MODEL write ownership
- parent / router does not edit production code or tests

## VAL-008: Installation

Steps:

1. Install the package with APM for `codex,agent-skills`.
2. Confirm skill and both reference templates are deployed.
3. Confirm both portable agents are available to Codex.
4. Apply the profile mapping with `install-adaptive-implementation-local.cs`.
5. Run installer `--check`.
6. Confirm Codex can select the skill and both custom agents.
7. Review collision behavior with an existing `AGENTS.md` and same-name TOML.
8. Dry-run APM uninstall, profile removal, and orphan prune before rollback.

Expected:

- skill, references, portable agents, profile guidance, both TOMLs, and docs are present in the package
- installed skill references are available under `.agents/skills/adaptive-implementation-execution/references`
- concrete agent TOMLs contain model, reasoning effort, and workspace-write sandbox fields
- HIGH_MODEL and STANDARD_MODEL use different custom agent names and different model mappings
- existing `AGENTS.md` content outside the managed section remains unchanged
- collisions fail closed unless `--force` is explicit

## Repository static validation

```powershell
./scripts/validate-adaptive-implementation-execution.ps1
dotnet publish ./scripts/install-adaptive-implementation-local.cs
git diff --check
```

The static validator checks the package layout, standalone dependency avoidance, Plan Coverage independence, verdict contracts, profile fields, root README entry, and presence of VAL-001 through VAL-008.

## Local validation result

Validated on 2026-07-13 with APM CLI 0.18.0 and a .NET 11 preview SDK targeting `net10.0`:

| Check | Result | Evidence |
| --- | --- | --- |
| Static package contract | PASS | `validate-adaptive-implementation-execution.ps1` |
| Static validator CI wiring | PASS | `validate-adaptive-implementation-execution.yml` invokes the package validator for relevant agent, package, workflow, and README changes |
| Full package local-path dry-run | PASS | APM accepted the package manifest and listed the local package install plan |
| File-based app publish | PASS | `dotnet publish install-adaptive-implementation-local.cs` |
| Skill local install | PASS | APM deployed `SKILL.md` and both `references/*.md` files under `.agents/skills/adaptive-implementation-execution` |
| Profile dry-run / install / check | PASS | installer produced the managed `AGENTS.md` section and both `.codex/agents/*.toml` files, then `--check` returned OK |
| Distinct mapping negative check | PASS | changing the installed STANDARD_MODEL mapping to the HIGH_MODEL mapping made `--check` fail with `must use distinct model mappings`; restoring the package profile returned OK |
| Profile remove dry-run / remove / remove-check | PASS | managed content and package-owned TOMLs were removed, then `--remove --check` returned OK |
| Remote branch package install | PASS | APM resolved the virtual package and both `git: parent` portable agents from `#codex/issue-45` at `66e1234b`, then deployed the skill, references, and both Codex agents |
| Remote rollback | PASS | `apm uninstall` removed the direct package and skill, profile removal deleted the managed guidance and TOMLs, and `apm prune` removed both orphaned portable agent packages; no integrated skill, agent, or package files remained |
| Agent discovery contract | PASS | remote install created both named `.codex/agents` entries and the static validator confirmed that the skill routes to those names |
| Runtime multi-agent orchestration | NOT RUN | installation validation does not execute the skill and both implementation agents; this remains a separate Codex runtime validation |
| Full package local-path install | NOT APPLICABLE | APM 0.18.0 cannot inherit `git: parent` from a local path dependency; the supported remote repository route is validated separately above |

The full-package local-path limitation does not change the package manifest. The remote branch validation confirms that the `git: parent` convention resolves the root portable agents when APM installs the repository subdirectory package.
