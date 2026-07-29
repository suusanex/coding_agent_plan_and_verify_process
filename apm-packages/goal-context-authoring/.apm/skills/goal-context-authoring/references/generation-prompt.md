# Goal Context generation prompt

Copy the prompt below into the original design conversation after the discussion is mature enough to explain why the work exists and what user-visible change is wanted.

The output is for **purpose-achievement review**. It is not a second specification, an Issue body, an implementation plan, or a complete decision log.

```text
Create a self-contained Goal Context Markdown from the full available conversation.

Purpose
- A later Codex or other AI reviewer will receive this document without the original conversation.
- The reviewer must be able to detect an implementation that satisfies its immediate Issue or detailed specification but still fails to resolve the original problem or deliver the intended user-visible outcome.

Selection rule
Include information only when omitting it could reasonably cause that kind of false approval.

Do not include information merely because it was discussed, accepted, technically important, or useful for implementation. Detailed requirements, architecture, tasks, and test procedures belong elsewhere unless they are essential to purpose judgment.

Purpose hierarchy
Organize and interpret the source in this order:
1. Original problem and why it matters
2. Desired user-visible outcome
3. Concrete before/after user situation
4. Outcomes that would look compliant but still fail the purpose
5. Priorities, trade-offs, and purpose boundaries
6. Purpose-critical decisions and their reasons

Lower-level requirements or implementation choices must not redefine a higher-level purpose. If they conflict, preserve the conflict and make the purpose-level risk visible.

Source handling
- Cover the available conversation from the earliest relevant discussion through the latest message.
- Treat user-authored statements and assistant proposals explicitly accepted by the user as authoritative.
- Do not promote an unaccepted assistant proposal, likely implementation, or general best practice into a user decision.
- Apply later user corrections and priority changes over earlier statements.
- Mark bounded synthesis as `[Inferred]` and unresolved, missing, or contradictory points as `[Unknown]`. Confirmed user content needs no prefix.
- Do not infer product, policy, scope, priority, or acceptance decisions from silence.
- Record material missing or truncated source portions in `source_scope`. If the missing source prevents identification of the original problem or desired outcome, stop instead of guessing.
- An Issue or implementation specification may be used only as a cross-check; it must not replace the original conversation as the source of purpose.
- If the source is supplied in ordered segments, keep concise temporary notes under the output headings and draft only after the final segment. Do not create Claim IDs or a detailed provenance ledger.

Include
- the underlying user or operational pain, not merely the requested feature;
- why the existing situation is insufficient or costly;
- the observable change that would make the work valuable;
- a concrete before/after scenario showing what burden disappears or what behavior becomes possible;
- the minimum user-visible value required for success;
- non-goals, acceptable compromises, or deferred outcomes only when they prevent confusion about the purpose;
- rejected alternatives only when their rejection reason protects the purpose;
- concrete examples of implementations that could appear compliant while leaving the original problem unresolved;
- priorities and trade-offs only when they affect what should count as success;
- decisions only when a reviewer must know them to avoid approving the wrong outcome;
- later corrections that materially changed the problem, outcome, priority, or boundary;
- unresolved questions only when they affect purpose judgment.

Exclude
- exhaustive functional requirements or acceptance criteria;
- architecture, component, API, schema, class, file, command, or configuration details;
- task decomposition, implementation order, migration steps, or rollout instructions;
- complete lists of accepted decisions, constraints, assumptions, or future ideas;
- test commands, evidence inventories, traceability tables, Claim IDs, or provenance ledgers;
- issue-by-issue or message-by-message chronology;
- general engineering best practices not stated as part of the purpose;
- implementation details whose replacement would not change the user-visible outcome.

A technical decision belongs in the Goal Context only when its reason is purpose-critical. Describe the protected purpose and the consequence of violating it, not the full mechanism.

Output language
- Use the primary language of the user's substantive design and decision messages.
- Follow an explicit user request for a different output language.
- If the primary language cannot be determined, use Japanese.
- Preserve code, CLI commands, file paths, schema keys, identifiers, product names, and established technical terms in their original form where appropriate.

Safety
- Exclude secrets, credentials, tokens, authentication material, private keys, and unnecessary personal data.
- Replace a purpose-relevant sensitive value with a category marker such as `<redacted: credential>`.

Output structure

---
document_type: goal-context
topic: <durable topic summary>
created_at: <YYYY-MM-DD>
source_scope: <available conversation range and material gaps>
---

# Goal Context: <Topic>

> This document is for purpose-achievement review, not exhaustive specification checking. Judge the implementation primarily against the original problem and desired user-visible outcome.

## Original problem

## Desired user-visible outcome

## Before and after

### Before

### After

## Purpose boundaries

## Rejected or misleading outcomes

Add the following headings only when supported by material source content:

## Priorities and trade-offs

## Purpose-critical decisions

## Material corrections

## Unknowns affecting purpose judgment

Writing rules
- Keep the original problem and desired outcome visually dominant.
- Prefer a few distinct, high-value statements over exhaustive coverage.
- Do not repeat the same point in multiple sections.
- Do not add empty optional headings or filler such as “none observed.”
- Use explicit rejected or misleading outcomes when available. If none were stated, add at most a few `[Inferred]` purpose-level failure examples that follow directly from the original problem and desired outcome; do not turn them into new feature requirements.
- If the original problem or desired user-visible outcome cannot be determined, return `Goal Context generation blocked` and list the missing purpose information instead of drafting.
- Do not add an acceptance-evidence matrix, review-question list, human-review record, lifecycle status, or sensitive-data approval state.
- Do not claim that generation constitutes human review or approval.

Filename
- After the Markdown document, output one proposed filename in the form `goal-context-<topic-summary>.md`.
- Use lowercase kebab-case based on the durable purpose or desired outcome.
- Do not center the filename on an Issue number, PR number, ticket number, temporary branch, or one-time task slug.

Self-check
1. Can a later reviewer explain the original pain and desired user-visible change from the first two sections alone?
2. Does every included lower-level decision protect a stated purpose, priority, boundary, or negative outcome?
3. Have detailed requirements and implementation mechanics been removed unless essential to purpose judgment?
4. Are concrete “looks compliant but still fails” examples present without becoming new requirements?
5. Have later user corrections replaced superseded interpretations?
6. Are material unknowns preserved rather than guessed closed?
7. Is the document self-contained without becoming a second specification?
8. Is the purpose signal stronger than process, audit, or traceability detail?
9. Are secrets and unnecessary personal data excluded?

Return the Goal Context Markdown first, then the single proposed filename. Do not add commentary outside those two outputs.
```
