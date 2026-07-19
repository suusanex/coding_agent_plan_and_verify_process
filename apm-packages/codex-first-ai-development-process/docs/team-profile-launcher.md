# Team Profile / Launcher

The package includes a minimal profile template under `profiles/codex-first/` and a launcher example under `scripts/codex-first-start.ps1`.
Copy or point `CODEX_HOME` at the profile when you want ordinary requests to enter Codex-first cost-aware routing.

## Goals

- Enable Codex-first cost-aware routing without changing every target repository.
- Keep repo-local `AGENTS.md` and build/test/security rules authoritative.
- Keep global instructions short.
- Move details into skills, docs, agents, and templates.
- Let maintainers map `HIGH_MODEL`, `STANDARD_MODEL`, and `CHEAP_MODEL` to real models outside the package.

## Expected profile contents

```text
CODEX_HOME/
  AGENTS.md
  config.toml
  agents/
    high-planner.toml
    black-box-behavior-spec-kernel.toml
    high-risk-triage.toml
    implementation-handoff-review.toml
    high-implementation-contract.toml
    high-implementation-starter.toml
    high-closure-reviewer.toml
    standard-implementation-completer.toml
    standard-implementer.toml
    standard-verifier.toml
    cheap-repo-scanner.toml
    cheap-doc-consistency.toml
    cheap-artifact-format-checker.toml
  skills/codex-first-cost-router/SKILL.md
  skills/design-pair-implementation-execution/SKILL.md
  skills/design-pair-implementation-execution/map.md
  skills/design-pair-implementation-execution/handoff.md
  templates/codex-first-state.md
  templates/codex-first-audit.md
  templates/model-tier-mapping.example.md
```

The actual installed layout may vary by APM tool, but the ownership is the same:
profile-level instructions provide the entry behavior, while repo-level instructions keep local rules.

For VS Code Codex extension in repository-local operation, use `apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs` first so that `AGENTS.md`, `.codex`, `.agents/skills`, and `templates` are created in the target repository.
For App / Desktop threads, treat the Codex-first profile plus repo-local state / audit artifacts as the primary path. CLI / `codex exec` launches are compatibility paths; use them when the operator can provide equivalent profile loading, subagent invocation, and ledger evidence.

## Minimal install example

For a local trial, copy the template profile to a dedicated Codex home:

```powershell
$profile = "$env:USERPROFILE\.codex-profiles\codex-first"
New-Item -ItemType Directory -Force $profile | Out-Null
Copy-Item -Recurse -Force .\apm-packages\codex-first-ai-development-process\profiles\codex-first\* $profile
New-Item -ItemType Directory -Force "$profile\skills\codex-first-cost-router" | Out-Null
Copy-Item -Recurse -Force .\apm-packages\codex-first-ai-development-process\.apm\skills\codex-first-cost-router\* "$profile\skills\codex-first-cost-router"
New-Item -ItemType Directory -Force "$profile\skills\design-pair-implementation-execution" | Out-Null
Copy-Item -Recurse -Force .\apm-packages\design-pair-implementation-execution\.apm\skills\design-pair-implementation-execution\* "$profile\skills\design-pair-implementation-execution"
New-Item -ItemType Directory -Force "$profile\templates" | Out-Null
Copy-Item -Recurse -Force .\apm-packages\codex-first-ai-development-process\templates\* "$profile\templates"
$env:CODEX_HOME = $profile
codex status
```

For one-off use without copying, use the launcher example:

```powershell
pwsh .\apm-packages\codex-first-ai-development-process\scripts\codex-first-start.ps1 -RepoPath . status
```

To install repo-local bootstrap files for repeated local use:

```powershell
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- . --dry-run
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- .
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- . --check
```

Expected verification:

- `codex status` shows the custom `CODEX_HOME`.
- A prompt such as `Summarize the current instructions.` includes the Codex-first global guidance.
- Subagent work can use the TOML files under `agents/`, each of which sets `model` and `model_reasoning_effort`.
- Non-trivial implementation starts with `high-implementation-starter`; `standard-implementation-completer` is selectable only after a valid handoff and re-entry returns to the high starter.
- The implementation route defaults to Adaptive. When the user explicitly selects Design Pair, its tracked handoff completes before `high-implementation-starter` begins production or test edits.
- Audit artifact Agent Usage Ledger distinguishes configured model, hook observed model, reported model, and effective model when evidence is available.

## Launcher behavior

The launcher should:

- load the Codex-first profile before ordinary repo work
- allow maintainers to edit model tier defaults before team rollout
- avoid overwriting repo files
- report when repo-local instructions are too large or conflicting
- offer bootstrap / dry-run merge only when profile layering is insufficient
- document whether the current run used the App / Desktop primary path or a CLI / `codex exec` compatibility path
