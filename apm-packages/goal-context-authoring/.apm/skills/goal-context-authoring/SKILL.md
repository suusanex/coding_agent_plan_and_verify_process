---
name: goal-context-authoring
description: Use when natural-language source material should be distilled into a portable free-form Goal Context for later implementation or purpose review.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context Authoring

This skill helps create or refine a Goal Context as self-contained natural-language context. It is an optional authoring route. A Goal Context used elsewhere may have been written by a person, another agent, another repository, or an unknown process.

## Required references

Read the bundled references before authoring:

- `references/generation-prompt.md`: copyable synthesis prompt
- `references/goal-context-contract.md`: free-form interoperability contract
- `references/goal-context-template.md`: optional example, never a required schema
- `references/human-review-checklist.md`: optional quality review

## Interoperability boundary

A Goal Context has no required filename, extension, frontmatter, headings, tables, tags, lifecycle state, approval record, or creation source. Do not add such requirements to downstream implementation or purpose review. The authoring conventions in this package are suggestions only.

The only machine-checkable input expectations are that the selected file is readable, non-empty text and does not expose a high-confidence credential pattern. Semantic adequacy is evaluated from the text itself.

## Workflow

1. Read the source material that is actually available. Do not claim access to missing material.
2. Distill why the work matters, what observable change is wanted, and any boundaries or failure outcomes that materially affect purpose judgment.
3. Preserve uncertainty and conflicting statements in plain language rather than inventing a decision.
4. Exclude secrets, credentials, authentication material, and unnecessary personal data.
5. Write a self-contained document in the structure that best fits the source. A short paragraph can be sufficient; headings may be used when they improve readability.
6. Optionally run the distributed validator:

```powershell
dotnet run --file .agents/skills/goal-context-authoring/scripts/validate-goal-context.cs -- --goal-context <path> --mode basic --format json
```

`--mode draft` and `--mode strict` remain compatibility aliases and do not impose lifecycle or approval semantics.

7. If the user asks for review, use `references/human-review-checklist.md` as a quality aid. Human review is optional and must not be recorded or required unless it actually occurred.

## Boundaries

This skill must not:

- turn optional examples into a required Goal Context schema;
- reject an existing Goal Context because it differs from this package's preferred organization;
- assume the Goal Context originated in a particular prompt or conversation;
- convert an inference into a user decision;
- claim human review without explicit confirmation;
- claim that authoring completes implementation, Issue creation, or purpose review.

## Output verdicts

- `GOAL_CONTEXT_CREATED`: readable self-contained context was saved
- `SOURCE_MATERIAL_REQUIRED`: the requested authoring task cannot identify any purpose from available material
- `HUMAN_DECISION_REQUIRED`: an unresolved contradiction must be decided before a trustworthy synthesis can be written
- `BLOCKED`: a tool, permission, or environment failure prevents completion
