---
name: goal-context-authoring
description: Use when a completed ChatGPT or other design conversation must be converted into a portable, human-reviewed goal-context-*.md for later implementation or purpose review without access to the original conversation.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context Authoring

This skill converts a completed design conversation and its final corrections into a self-contained Goal Context Markdown document. The result is a durable purpose-review input, not an Issue draft, implementation plan, or chronological conversation summary.

## Required references

Read all four bundled references before generating or validating a Goal Context:

- `references/generation-prompt.md`: copyable generation prompt and multi-pass extraction procedure
- `references/goal-context-contract.md`: normative document, provenance, naming, and review contract
- `references/goal-context-template.md`: required output structure
- `references/human-review-checklist.md`: required human confirmation procedure

## Boundaries

This skill may:

- synthesize a Goal Context from source conversation material supplied in the current context or as readable files
- distinguish explicit source statements, bounded inferences, and unresolved unknowns
- identify corrections, priority changes, accepted decisions, rejected alternatives, MVP boundaries, and purpose-level failure conditions
- propose a content-centered `goal-context-<topic-summary>.md` filename
- run the package validator when it is available locally

This skill must not:

- automate the original consultation or Issue creation
- turn the result into an Issue body, implementation plan, or transcript
- claim access to missing conversation segments
- convert an inference into a user decision
- silently discard contradictory or superseded statements
- include secrets, credentials, authentication material, or unnecessary personal data
- claim human review occurred without explicit human confirmation

## Workflow

### 1. Establish the source boundary

Identify every source made available for this authoring pass: conversation segments, final user corrections, decision notes, and any Issue draft used only as a cross-check. Record missing or truncated portions. If the source needed to determine the original problem or desired outcome is unavailable, stop and request it instead of reconstructing it from the Issue alone.

For a long conversation, divide the material into ordered source segments and keep a temporary claim ledger with these columns:

| Claim ID | Segment | Source pointer | Contract dimension | Provenance | Extracted statement, reason, or evidence | Supersession / disposition |
| --- | --- | --- | --- | --- | --- | --- |

Use stable Claim IDs and precise source pointers. For every segment, consider each contract dimension: Original problem; Desired outcome; Concrete user situation; User scenario; MVP scope; Non-goal; Future work; Accepted decision and reason; Rejected alternative and reason; Constraint or invariant; Success scenario; Acceptance evidence; Superficially compliant but wrong; Review question; Open question or assumption; Correction or priority change. Record `None observed in this segment` only as temporary coverage status, never as final Goal Context content.

Before drafting, give every extracted claim exactly one final disposition: `Included`, `Superseded by <Claim ID>`, `Duplicate of <Claim ID>`, `Excluded as sensitive`, or `Retained as Unknown`. If an expected segment is missing, stop instead of drafting. The ledger is working material; do not reproduce it as the final Goal Context.

### 2. Extract before synthesizing

Use the procedure in `references/generation-prompt.md`:

1. Extract candidate facts and decisions from the full available source.
2. Reconcile later corrections and priority changes against earlier statements.
3. Separate MVP, non-goals, and future work.
4. Preserve accepted and rejected decisions with reasons.
5. Identify success scenarios, required evidence, and superficially compliant but wrong outcomes.
6. Classify every material statement as `[Explicit]`, `[Inferred]`, or `[Unknown]` according to the contract.
7. Remove sensitive or unnecessary personal information.
8. Synthesize by purpose and decision topic, not by conversation chronology.

When two explicit source statements conflict and no later correction resolves them, keep the conflict under Open questions. Do not select one silently.

### 3. Draft against the contract

Create the document using `references/goal-context-template.md`. Every required heading must remain present. Write concise, actionable content under each heading; do not leave placeholder comments in a saved draft.

The filename must:

- start with `goal-context-`
- summarize the enduring subject or desired outcome in lowercase kebab-case
- avoid centering an Issue number, PR number, ticket number, or one-time task slug

Use the repository's documented Goal Context directory when one exists. Otherwise prefer `docs/goal-context-<topic-summary>.md`.

### 4. Self-check before human review

Re-read the full available source and the draft. Confirm that:

- the original problem and desired outcome are understandable without the source conversation
- corrections and current priorities supersede earlier statements where appropriate
- rejected alternatives and their reasons remain visible
- MVP, non-goals, and future work are not mixed
- acceptance evidence is evidence, not merely an implementation task list
- the wrong-outcome section covers ways to satisfy the form while missing the purpose
- explicit statements, inferences, and unknowns are distinguishable
- secrets, credentials, authentication material, and unnecessary personal data are absent

Run the distributed canonical validator:

```powershell
dotnet run --file scripts/validate-goal-context.cs -- --goal-context <path> --mode draft --format json
```

When operating from the package source repository, the compatibility wrapper also validates package layout and fixtures:

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath <path>
```

Treat validator success as structural evidence only. It does not replace semantic or privacy review.

### 5. Obtain human review

Present the draft together with `references/human-review-checklist.md`. The human must specifically confirm Desired outcome, rejected alternatives, superficially compliant but wrong outcomes, MVP boundaries, corrections and priority changes, provenance classification, and sensitive-data removal.

Before confirmation, keep the only valid draft lifecycle pair, `status: draft` and `sensitive_data_review: pending`, with the Human review record pending. Only after explicit confirmation may the document use the other valid pair, `status: human-reviewed` and `sensitive_data_review: passed`, together with a dated reviewer record. Mixed pairs are invalid.

When human review is complete, run strict validation:

```powershell
dotnet run --file scripts/validate-goal-context.cs -- --goal-context <path> --mode strict --format json
```

The package-source compatibility command is:

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath <path> -RequireHumanReview
```

### 6. Save and hand off

Save the reviewed Markdown in the repository and report:

- Goal Context path
- source boundary and any unavailable source segments
- semantic corrections made during human review
- validator command and result
- remaining open questions or assumptions
- human review status

Do not claim that implementation, Issue creation, or purpose review was performed by this authoring flow.

## Output verdicts

- `DRAFT_READY_FOR_HUMAN_REVIEW`: structurally complete draft; human review still required
- `GOAL_CONTEXT_READY`: human-reviewed document saved and strict validation passed
- `SOURCE_MATERIAL_REQUIRED`: source boundary is too incomplete to establish the original problem or desired outcome
- `HUMAN_DECISION_REQUIRED`: unresolved contradiction or scope decision prevents a trustworthy Goal Context
- `BLOCKED`: tool, permission, or environment failure prevents completion
