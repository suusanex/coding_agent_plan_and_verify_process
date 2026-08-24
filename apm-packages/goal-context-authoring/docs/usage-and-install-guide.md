# Goal Context Authoring usage and install guide

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target copilot,codex,agent-skills
```

The package deploys an optional authoring Skill, prompt, example, quality checklist, and readability validator under `.agents/skills/goal-context-authoring/`. It does not define the only valid way to create Goal Context.

## Author or select context

Goal Context is free-form natural-language text. It can be written by a person or tool and can originate outside this repository. Use the bundled generation prompt only when helpful.

No filename, extension, directory, frontmatter, heading, table, provenance tag, lifecycle state, approval record, or source process is required. A concise paragraph can be complete. When creating new context, explain the purpose and observable desired change clearly enough for a later reviewer; add boundaries or failure outcomes only when the source supports them.

## Optional validation

```powershell
dotnet run --file .agents/skills/goal-context-authoring/scripts/validate-goal-context.cs -- --goal-context C:\path\to\context.txt --mode basic --format json
```

Compatibility aliases `--mode draft` and `--mode strict` perform the same checks. The validator verifies readable non-empty text and scans a small set of high-confidence credential patterns. It does not validate structure, semantics, completeness, privacy safety, or approval.

Human review may be performed when the user or another governing process asks for it. The optional checklist helps with fidelity and safety, but using it does not require changing the document format or adding lifecycle metadata.

## Development validation

```powershell
pwsh -NoProfile -File apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1
pwsh -NoProfile -File apm-packages/goal-context-authoring/scripts/test-apm-package-install.ps1
git diff --check
```

The package validator includes a one-paragraph free-form fixture and rejects empty, NUL-bearing, and high-confidence credential inputs. The APM smoke confirms installed files match the package source and that the installed validator accepts free-form text.

## Handoff

Pass the selected Goal Context path to a consumer only when automatic discovery is unavailable or ambiguous. Internal path and SHA identity may be recorded by the consumer; users do not need to transfer lifecycle fields, hashes, JSON, or approval records between tasks.
