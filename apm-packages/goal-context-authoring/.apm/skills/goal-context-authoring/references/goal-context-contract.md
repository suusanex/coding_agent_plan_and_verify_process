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

The only valid lifecycle pairs are:

- `status: draft` / `sensitive_data_review: pending`
- `status: human-reviewed` / `sensitive_data_review: passed`

Mixed pairs such as `draft` / `passed` and `human-reviewed` / `pending` are invalid. `status: human-reviewed` requires explicit human confirmation and a completed Human review record. AI self-review alone is not human review.

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

Every material list or numbered-list entry in a required content section starts with exactly one allowed provenance tag followed by substantive text. Every required table contains at least one substantive data row; its provenance or classification cell contains exactly one allowed tag. The Human review record is lifecycle metadata and does not use provenance tags.

## Long-conversation coverage contract

When input is segmented, maintain a temporary claim ledger with stable Claim IDs, segment and source pointers, contract dimension, provenance, extracted content, and supersession or disposition. Each segment must be checked for Original problem, Desired outcome, concrete situations and scenarios, all three scope classes, accepted and rejected decisions with reasons, constraints, success scenarios, acceptance evidence, purpose-level wrong outcomes, review questions, open questions, and corrections or priority changes.

Before drafting, classify every extracted claim as `Included`, `Superseded by <Claim ID>`, `Duplicate of <Claim ID>`, `Excluded as sensitive`, or `Retained as Unknown`. Missing expected segments stop generation. Temporary `None observed in this segment` coverage records do not become final document content.

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
