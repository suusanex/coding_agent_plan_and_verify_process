# Goal Context document contract

## Purpose

A Goal Context is a self-contained Markdown input for a later implementation or purpose review whose reader cannot access the original design conversation. It preserves why the work matters, what outcome is wanted, which boundaries and decisions apply, and how an implementation can look compliant while still failing the purpose.

A Goal Context is not:

- an Issue body with more prose
- a chronological transcript or conversation summary
- an implementation plan or task checklist
- a replacement for human confirmation

## File and frontmatter contract

Use a content-centered lowercase kebab-case filename:

```text
goal-context-<topic-summary>.md
```

The topic summary describes the durable problem or desired outcome. Do not center the filename on an Issue number, PR number, ticket number, or one-time work slug. Prefer the repository's documented Goal Context directory; otherwise use `docs/`.

Required frontmatter:

```yaml
---
document_type: goal-context
status: draft
topic: <durable topic summary>
created_at: YYYY-MM-DD
source_scope: <what conversation material was available, including known gaps>
sensitive_data_review: pending
---
```

Allowed lifecycle values:

- `status`: `draft` or `human-reviewed`
- `sensitive_data_review`: `pending` or `passed`

`status: human-reviewed` requires explicit human confirmation, `sensitive_data_review: passed`, and a completed Human review record. AI self-review alone is not human review.

## Provenance contract

Prefix each material factual, requirement, decision, boundary, and assumption bullet with exactly one tag:

- `[Explicit]`: directly stated or clearly confirmed in the supplied source
- `[Inferred]`: a bounded synthesis needed to connect explicit source statements; include the evidence and do not present it as a user decision
- `[Unknown]`: unresolved, missing, contradictory, or intentionally undecided

Later user corrections and priority changes supersede earlier statements only when the source supports that ordering. Record the supersession in `Conversation corrections and priority changes`. If two statements conflict without a clear resolution, use `[Unknown]` and retain the conflict.

Do not use `[Explicit]` for:

- a likely implementation inferred from repository conventions
- an AI recommendation the user did not accept
- a value copied only from an Issue when the original conversation is missing
- silence or absence of disagreement

## Required sections

The following headings and responsibilities are mandatory:

| Heading | Responsibility |
| --- | --- |
| `Document control and source boundary` | Source coverage, known gaps, relationship to other artifacts |
| `Original problem` | The underlying pain or failure that motivated the discussion |
| `Desired outcome` | Observable end state and user value, not an implementation mechanism |
| `Concrete user situation and user scenarios` | Real operating context and representative scenarios |
| `Scope and boundaries` | Separate MVP scope, non-goals, and future work |
| `Decisions and reasoning` | Separate accepted decisions and rejected alternatives, both with reasons |
| `Constraints and invariants` | Conditions that later design and implementation must preserve |
| `Success scenarios` | Purpose-level flows that should work |
| `Acceptance evidence` | Evidence that would demonstrate the outcome; distinguish automated and human evidence |
| `Superficially compliant but wrong` | Implementations that satisfy form or Issue text but miss the purpose |
| `Review questions` | Questions a later purpose reviewer must answer |
| `Open questions and assumptions` | Unknowns and bounded inferences that require care or decisions |
| `Conversation corrections and priority changes` | Later corrections, superseded ideas, and priority movement |
| `Provenance and inference ledger` | Compact trace from important claims to their source status |
| `Human review record` | Explicit review status and review changes |

Empty required sections are invalid. When the source truly contains no item for a section such as rejected alternatives, say so explicitly with an `[Explicit]` or `[Unknown]` statement and describe the source limitation. Do not invent an item to fill the template.

## Quality invariants

- The document must be understandable without the original conversation.
- The Issue may be used as a cross-check, but the document must not merely restate its requirements or acceptance checklist.
- The organization follows problem, outcome, decisions, boundaries, and evidence rather than message chronology.
- Important user corrections and current priorities replace superseded wording visibly.
- MVP, non-goals, and future work remain separate.
- Rejected alternatives remain visible with reasons so a later implementation does not reintroduce them accidentally.
- Acceptance evidence describes proof, not only work to perform.
- Purpose-level negative conditions are concrete enough for a reviewer to detect superficial compliance.
- Unknowns are not silently resolved.

## Sensitive-data contract

Never copy secrets, credentials, authentication material, private keys, tokens, connection strings containing secrets, or unnecessary personal data into a Goal Context. Replace necessary references with a category-only marker such as `<redacted: credential>` and retain only the decision-relevant fact.

Before changing `sensitive_data_review` to `passed`, inspect both the generated document and excerpts retained as evidence. A validator can catch some high-confidence token shapes but cannot prove that a document is safe.

## Validation boundary

The bundled validator checks filename shape, frontmatter, required headings, meaningful section content, provenance tags, human-review state, and a small set of high-confidence secret patterns. It cannot establish semantic fidelity, completeness of a long conversation, correctness of inference, or privacy safety. Those remain AI self-check plus mandatory human review responsibilities.
