# Deterministic reviewer executor

`scripts/execute-reviewer.cs` is the package-owned launch/wait/result-capture address for `local-reviewer` and `purpose-reviewer`. Parent assessment and round transitions remain outside this utility.

## Typed configuration

Required:

- `--execution-app` `codex-exec` | `copilot-cli`
- `--model` supported model or alias for the selected app
- `--reviewer-role` `local-reviewer` | `purpose-reviewer`
- `--run-root` same-thread run root
- `--round` `1` | `2` | `3`

Optional:

- `--timeout-seconds` (default `600`)
- `--repository-root`
- `--skill-root`
- `--codex-executable` / `--copilot-executable` (tests and non-PATH installs)
- `--additional-context-path` (parent remediation notes for purpose-only rounds)
- `--format` `json` | `text` (default `json`)

Arbitrary raw command strings (`--command ...`) are rejected. Adapter argument lists are built only inside the selected adapter.

## Outputs

On success:

- `round-NNN/{role}.raw.md` — final review body (atomic publish)
- `round-NNN/{role}.execution.json` — execution metadata

Metadata fields:

- `executionApp`
- `requestedModel`
- `observedModel` (`unknown` when the platform does not echo the model)
- `reviewerRole`
- `startedAt` / `completedAt`
- `exitStatus`
- `rawOutputPath`
- `limitations`
- `commandShape` (secrets redacted; prompt body replaced)

On failure, final `*.raw.md` is not published. Failure statuses include `timeout`, `auth_failure`, `non_zero_exit`, `empty_output`, `malformed_output`, `process_start_failure`, `unsupported`, and `failed`. Failures are never interpreted as “no findings”.

## Adapters

### Codex exec

Invokes non-interactive with prompt on **stdin** (not argv):

```text
codex exec --json --strict-config --ignore-user-config -C <repo> -m <model> -s read-only -c ... -o <temp>
# stdin: full reviewer assignment
```

Limitations (recorded, not disguised):

- top-level `codex exec`, not native `spawn_agent`
- no parent session inheritance / child thread UI / project custom-agent UI selection
- sandbox is requested as read-only; OS write impossibility is not proven (worktree mutation still fails closed)

### GitHub Copilot CLI

Invokes non-interactive with a **short** `-p` that references a prompt file under `--add-dir` (full assignment is never placed on argv):

```text
copilot -p <short-prompt-ref> --model <model> -C <repo> -s --output-format text \
  --no-ask-user --no-custom-instructions --disable-builtin-mcps \
  --available-tools view,grep,glob,read_file,list_dir,search_codebase \
  --deny-tool write --deny-tool shell --deny-tool task --deny-tool memory ...
```

VS Code UI is not required. Observed model may remain `unknown`. Copilot-only installs do not require Codex TOML profiles; role contracts resolve from `.github/agents` or `apm_modules/**/.apm/agents`.

## Safety contracts

- raw `*.raw.md` and `*.execution.json` are published as one pair; metadata failure rolls back raw
- timeout / auth / non-zero / empty / malformed / process-start / write-detected never mean “no findings”
- final body must include `Production code changed: No` and role-compatible markers
- full `pr-diff.patch` is referenced by path and must be read completely (no silent truncation success)
- pre/post worktree snapshot rejects repository mutations

## Parent responsibilities after execution

1. Read raw markdown evidence.
2. Project findings into `round-assessment.json`.
3. Run `manage-same-parent-review.cs assess`.

Do not move semantic assessment into this executor.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Unsupported execution app/model/role | Use typed allowlist values only |
| Existing raw artifact | Do not overwrite; start a new round or clean only intentional test fixtures |
| timeout / auth / empty | Treat as execution failure; do not assess as no findings |
| Partial `*.partial-*` files | Ignore; final name is published only after successful extraction |
| Copilot write observed | Record failure and stop; do not treat as successful review |

## Validation

```powershell
dotnet publish apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/execute-reviewer.cs -o <temporary-output>
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-execute-reviewer.ps1
```
