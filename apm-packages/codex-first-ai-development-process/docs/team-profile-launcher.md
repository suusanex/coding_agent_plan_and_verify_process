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
    high-risk-triage.toml
    high-implementation-contract.toml
    high-closure-reviewer.toml
    standard-implementer.toml
    standard-verifier.toml
    cheap-repo-scanner.toml
    cheap-doc-consistency.toml
    cheap-artifact-format-checker.toml
  skills/codex-first-cost-router/SKILL.md
  templates/codex-first-state.md
  templates/model-tier-mapping.example.md
```

The actual installed layout may vary by APM tool, but the ownership is the same:
profile-level instructions provide the entry behavior, while repo-level instructions keep local rules.

## Minimal install example

For a local trial, copy the template profile to a dedicated Codex home:

```powershell
$profile = "$env:USERPROFILE\.codex-profiles\codex-first"
New-Item -ItemType Directory -Force $profile | Out-Null
Copy-Item -Recurse -Force .\apm-packages\codex-first-ai-development-process\profiles\codex-first\* $profile
$env:CODEX_HOME = $profile
codex status
```

For one-off use without copying, use the launcher example:

```powershell
pwsh .\apm-packages\codex-first-ai-development-process\scripts\codex-first-start.ps1 -RepoPath . status
```

Expected verification:

- `codex status` shows the custom `CODEX_HOME`.
- A prompt such as `Summarize the current instructions.` includes the Codex-first global guidance.
- Subagent work can use the TOML files under `agents/`, each of which sets `model` and `model_reasoning_effort`.

## Launcher behavior

The launcher should:

- load the Codex-first profile before ordinary repo work
- allow maintainers to edit model tier defaults before team rollout
- avoid overwriting repo files
- report when repo-local instructions are too large or conflicting
- offer bootstrap / dry-run merge only when profile layering is insufficient
