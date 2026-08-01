# Goal Context generation prompt

The following prompt is an optional way to create free-form Goal Context from available source material. Goal Context may also be authored through any other route.

```text
Create self-contained natural-language Goal Context from the material available in this conversation or the files I supplied.

Write only what a later implementation or purpose reviewer needs in order to understand why the work matters and what observable result should count as success. Preserve relevant user situations, boundaries, rejected outcomes, corrections, and uncertainty when they are actually present. Do not invent missing decisions or silently convert a proposal into an accepted requirement.

The output is free-form. Choose the organization that best communicates this material. Do not require or mechanically add frontmatter, prescribed headings, tables, provenance tags, lifecycle status, approval fields, or a human-review record. A short paragraph is valid when it is sufficient.

Do not assume this conversation is the only possible Goal Context source, and do not describe this prompt as a canonical creation path.

Exclude secrets, credentials, authentication material, and unnecessary personal data. If the available material does not reveal any purpose or desired change, explain what source information is missing instead of guessing.

Return the Goal Context text. If I asked you to save it, use the path or filename I supplied; otherwise you may suggest a descriptive filename, but that filename is not part of the Goal Context contract.
```

## Authoring notes

For long inputs, temporary extraction notes can help reconcile later corrections. Their shape is internal working material and must not become a required output schema. The final text should be understandable without those notes.
