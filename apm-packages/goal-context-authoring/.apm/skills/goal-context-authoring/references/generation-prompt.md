# Goal Context generation prompt

Copy the prompt below into the ChatGPT conversation after the design and Issue content are settled. If the conversation is too long to fit in one context, provide ordered segments and use the continuation protocol at the end.

```text
Create a self-contained Goal Context Markdown from the full available conversation.

Purpose:
- A later Codex or other AI must be able to perform purpose-achievement review without access to this conversation.
- Preserve why the work matters, the desired outcome, current priorities, decisions and reasons, rejected alternatives, MVP boundaries, and ways an implementation can look compliant while still failing the purpose.

This is not an Issue body, implementation plan, or chronological conversation summary. The Issue may be used only as a cross-check. Organize the result by problem, outcome, decisions, boundaries, evidence, and review questions.

Source handling:
1. Cover the conversation from its earliest available point through the current message.
2. Identify unavailable, truncated, or unreviewed source portions explicitly.
3. Extract decisions and constraints before drafting.
4. Reconcile later user corrections and priority changes against earlier statements. Record each material supersession.
5. If explicit statements conflict without a clear later resolution, keep the conflict as Unknown. Do not choose one.
6. Separate MVP scope, Non-goals, and Future work.
7. Preserve both accepted decisions and rejected alternatives with reasons.
8. Do not infer missing product, policy, or scope decisions from silence.

Provenance:
- Prefix every material factual, requirement, decision, boundary, and assumption bullet with one of these tags:
  - [Explicit]: directly stated or confirmed in the supplied source
  - [Inferred]: bounded synthesis needed to connect explicit statements; include the supporting evidence and do not present it as a user decision
  - [Unknown]: unresolved, missing, contradictory, or intentionally undecided
- Never label an AI recommendation or likely implementation as Explicit unless the user accepted it.

Safety:
- Exclude secrets, credentials, tokens, authentication material, private keys, and unnecessary personal data.
- When a sensitive reference is decision-relevant, replace its value with a category marker such as <redacted: credential>.
- Do not reproduce source excerpts merely as evidence; use concise source pointers.

Required frontmatter:
---
document_type: goal-context
status: draft
topic: <durable topic summary>
created_at: <YYYY-MM-DD>
source_scope: <available conversation range and known gaps>
sensitive_data_review: pending
---

Required headings, in this order:
# Goal Context: <Topic>
## Document control and source boundary
## Original problem
## Desired outcome
## Concrete user situation and user scenarios
## Scope and boundaries
### MVP scope
### Non-goals
### Future work
## Decisions and reasoning
### Accepted decisions
### Rejected alternatives
## Constraints and invariants
## Success scenarios
## Acceptance evidence
## Superficially compliant but wrong
## Review questions
## Open questions and assumptions
## Conversation corrections and priority changes
## Provenance and inference ledger
## Human review record

Content requirements:
- Original problem states the underlying pain, not merely the requested feature.
- Desired outcome states observable user value.
- Concrete user situation and user scenarios explain how the result is used.
- Accepted and rejected decisions include reasons and consequences or revisit conditions.
- Acceptance evidence distinguishes evidence types where relevant.
- Superficially compliant but wrong gives concrete purpose-level failure examples.
- Open questions do not invent answers.
- Human review record remains Pending because generation is not human review.
- If a required section has no confirmed source content, write an Explicit or Unknown statement explaining that absence. Never invent an item to fill the section.

Filename proposal:
- End with one proposed filename in the form goal-context-<topic-summary>.md.
- Use lowercase kebab-case based on the durable subject or desired outcome.
- Do not center the filename on an Issue number, PR number, ticket number, or one-time task slug.

Self-check before responding:
1. Compare the draft against the full available source, not only recent messages.
2. Check that corrections and current priorities replaced superseded statements.
3. Check that rejected alternatives and negative purpose conditions remain visible.
4. Check that MVP, Non-goals, and Future work are separate.
5. Check that every material claim has an accurate provenance tag.
6. Check that unknowns were not guessed closed.
7. Check for secrets, authentication material, and unnecessary personal data.
8. Check that the result is not an Issue copy or chronological summary.

Return the Markdown document first, then the single proposed filename. Do not claim human review is complete.
```

## Long-conversation continuation protocol

When the full conversation cannot be processed at once, use ordered segments. For each non-final segment, append this instruction:

```text
This is source segment <N> of <TOTAL or unknown>. Extract a temporary coverage ledger containing topics, explicit decisions, corrections or priority changes, rejected alternatives, constraints, and unknowns. Do not draft the Goal Context yet. Do not discard earlier ledgers. Reply only with the ledger and the next segment requested.
```

For the final segment, append:

```text
This is the final source segment. Reconcile all segment ledgers against this segment, apply later explicit corrections, retain unresolved conflicts as Unknown, then execute the complete Goal Context generation prompt. State the reviewed segment range in source_scope. If any expected segment is missing, stop and request it instead of drafting.
```

The human review must still compare the generated document with the authoritative conversation or decision notes. Segment ledgers reduce omission risk but do not prove completeness.
