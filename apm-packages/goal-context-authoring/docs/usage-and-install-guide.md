# Goal Context Authoring usage and install guide

## Install

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target copilot,codex,agent-skills --global
```

The package deploys an optional authoring Skill, generation prompt, example, and quality checklist under `~/.agents/skills/goal-context-authoring/`. It does not define the only valid way to create Goal Context or Decision Context.

## Author or select context

Goal Context is free-form natural-language text. It can be written by a person or tool and can originate outside this repository. Use the bundled generation prompt only when helpful.

The bundled prompt separates two authorities in one Markdown document:

- Goal Context: the original problem, expected outcome, and purpose-review information needed to judge whether the task achieved its purpose.
- Decision Context: explicitly settled scope, accepted decisions, and implementation direction that later work must not silently reopen.

Do not use either section as a place to preserve conversation chronology, roadmap, future architecture, unresolved planning matters, or background information merely because it may be useful later.

No filename, extension, directory, frontmatter, table, provenance tag, lifecycle state, approval record, or source process is required by downstream consumers. The generation prompt may choose headings for the artifact it creates; those authoring conventions do not become a consumer schema.

This package intentionally does not provide a Goal Context / Decision Context validity validator or semantic regression test. Meaning quality is evaluated from the source material and the generated text itself when review is needed.

作成時は、元の問いから途中の具体化・合意・訂正までを照合します。利用者が目的を明示して矛盾がなければ、そのまま全文を書きます。達成判定が分かれる場合や、長い構想から新規 Issue の目的・管理責務を初めて推定する場合は、問題・望む状態・未解決例だけを短く示し、一往復してから全文を書きます。これは完成文の任意の人手レビューとは別で、下流の承認記録は必要ありません。

## Handoff

Pass the selected context path to a consumer only when automatic discovery is unavailable or ambiguous. Internal path and content identity may be recorded by the consumer; users do not need to transfer lifecycle fields, hashes, JSON, or approval records between tasks.
