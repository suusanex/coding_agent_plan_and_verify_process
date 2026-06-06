# Team Profile / Launcher

The package is intended to be installed as a team profile such as `codex-first` or launched through a helper such as `codex-first-start`.

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
  skills/codex-first-cost-router/SKILL.md
  agents/high-planner.agent.md
  agents/standard-implementer.agent.md
  agents/cheap-repo-scanner.agent.md
  templates/codex-first-state.md
  docs/model-tier-mapping.md
```

The actual installed layout may vary by APM tool, but the ownership is the same:
profile-level instructions provide the entry behavior, while repo-level instructions keep local rules.

## Launcher behavior

The launcher should:

- load the Codex-first profile before ordinary repo work
- keep model tier mapping external to the package
- avoid overwriting repo files
- report when repo-local instructions are too large or conflicting
- offer bootstrap / dry-run merge only when profile layering is insufficient
