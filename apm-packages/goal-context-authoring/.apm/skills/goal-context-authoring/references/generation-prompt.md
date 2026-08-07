# Goal Context generation prompt

The following prompt is an optional way to create free-form Goal Context from available source material. Goal Context may also be authored through any other route.

```text
Create self-contained natural-language Goal Context from the material
available in this conversation or the files I supplied.

Output language
- Use the primary language of the user's substantive design and decision messages.
- Follow an explicit user request for a different output language.
- If the primary language cannot be determined, use Japanese.
- Preserve code, CLI commands, file paths, schema keys, identifiers, product names, and established technical terms in their original form where appropriate.

The Goal Context has two downstream uses:

1. Help a later implementation or purpose reviewer understand why the
   work exists and what observable result should count as success.
2. Carry forward the decisions, constraints, rejected alternatives,
   premises, and unresolved matters already established in this
   conversation so later planning does not silently reopen or contradict them.

Keep the original problem and desired outcome semantically dominant.
Lower-level technical decisions must not redefine the higher-level purpose.

Include every current, source-confirmed decision or constraint whose
omission could reasonably cause later planning to:
- contradict an already accepted decision;
- reintroduce an explicitly rejected alternative;
- violate a stated boundary or invariant; or
- rely on a premise without knowing that it still needs verification.

Preserve enough reason and scope for each decision to prevent it from
being applied more broadly than intended.

Clearly distinguish, in natural language:
- decisions and constraints explicitly stated or clearly accepted by the user;
- premises or working assumptions that may need revalidation;
- proposals that were discussed but not accepted;
- unresolved matters intentionally left for later planning.

Do not invent missing decisions or silently convert an assistant proposal,
general best practice, likely implementation, or user silence into an
accepted requirement. Apply later user corrections over superseded
statements.

Do not turn the output into an exhaustive specification, Issue body,
implementation plan, acceptance checklist, task list, test plan, or
complete contract inventory. Include technical detail only when it was
actually settled in the source conversation or is necessary to understand
the scope and reason of a settled decision.

Preserve relevant user situations, boundaries, rejected outcomes,
corrections, and uncertainty when they are actually present.

The output is free-form. Choose an organization that makes the purpose
context and the settled planning context easy to distinguish. Do not
require or mechanically add frontmatter, prescribed headings, tables,
provenance tags, lifecycle status, approval fields, or a human-review
record. A short paragraph is valid when it is sufficient.

Exclude secrets, credentials, authentication material, and unnecessary
personal data. If the available material is too incomplete to establish
the purpose or distinguish accepted decisions from proposals, state what
is missing instead of guessing.

Return the Goal Context text. If I asked you to save it, use the path or
filename I supplied; otherwise you may suggest a descriptive filename,
but that filename is not part of the Goal Context contract.
```

## Authoring notes

For long inputs, temporary extraction notes can help reconcile later corrections. Their shape is internal working material and must not become a required output schema. The final text should be understandable without those notes.
