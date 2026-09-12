---
name: goal-context-authoring
description: Use when natural-language source material should be distilled into a portable Goal Context and Decision Context for later implementation or purpose review.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context Authoring

This skill helps create or refine a self-contained natural-language document that separates Goal Context from Decision Context. It is an optional authoring route. A context used elsewhere may have been written by a person, another agent, another repository, or an unknown process.

## Required references

Read the bundled references before authoring:

- `references/generation-prompt.md`: copyable synthesis prompt
- `references/goal-context-contract.md`: free-form interoperability contract
- `references/goal-context-template.md`: optional example, never a required schema
- `references/human-review-checklist.md`: optional quality review

## Interoperability boundary

Downstream consumers must not turn authoring conventions into a required filename, extension, frontmatter, headings, tables, tags, lifecycle state, approval record, or creation source. The authoring conventions in this package are suggestions only.

## Workflow

1. Read the source material that is actually available. Do not claim access to missing material.
2. Put the original problem, expected outcome, and purpose-critical boundaries in Goal Context.
3. Put explicitly settled scope, accepted decisions, and implementation direction in Decision Context.
4. Do not mix the two authorities or add chronology, roadmap, future architecture, unresolved planning matters, or background merely because it may help later.
5. Preserve later explicit corrections and do not invent decisions from proposals, silence, or general best practice.
6. Exclude secrets, credentials, authentication material, and unnecessary personal data.
7. If the user asks for review, use `references/human-review-checklist.md` as a quality aid. Human review is optional and must not be recorded or required unless it actually occurred.

This skill intentionally does not provide a machine validator for semantic adequacy or a prompt regression test. Judge meaning from the source and the generated text itself.

## Boundaries

This skill must not:

- turn optional examples into a required context schema;
- reject an existing context because it differs from this package's preferred organization;
- assume the context originated in a particular prompt or conversation;
- convert an inference into a user decision;
- claim human review without explicit confirmation;
- claim that authoring completes implementation, Issue creation, or purpose review.

## Output verdicts

- `GOAL_CONTEXT_CREATED`: self-contained context was saved
- `SOURCE_MATERIAL_REQUIRED`: the requested authoring task cannot identify the needed purpose or decisions from available material
- `HUMAN_DECISION_REQUIRED`: an unresolved contradiction must be decided before a trustworthy synthesis can be written
- `BLOCKED`: a tool, permission, or environment failure prevents completion
