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

作成時は、原資料から取り出した中心目的を先に照合します。目的が明確ならそのまま全文を書き、達成判定が異なる解釈が残るなら、元の問題・望む状態・未解決の例だけを短く示してユーザーの応答を待ちます。訂正された意味を全文へ引き継ぎます。これは完成文の人手レビューとは別です。完成文のチェックリストは任意で、使用しても承認や状態の記録は発生しません。

## Handoff

Pass the selected context path to a consumer only when automatic discovery is unavailable or ambiguous. Internal path and content identity may be recorded by the consumer; users do not need to transfer lifecycle fields, hashes, JSON, or approval records between tasks.
