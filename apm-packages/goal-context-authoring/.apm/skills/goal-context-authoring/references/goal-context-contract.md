# Goal Context interoperability contract

## Definition

A Goal Context is natural-language context used to understand why work exists and what outcome should count as success. It may be a paragraph, notes, prose with headings, or another readable textual form.

## Required properties

- The selected file is readable and contains non-whitespace text.
- Its content is treated as the authority supplied for purpose interpretation.
- Secrets, credentials, authentication material, and unnecessary personal data are not intentionally copied into a newly authored document.

## Explicit non-requirements

No consumer may require a particular:

- filename, extension, directory, or `goal-context-*` naming pattern;
- Markdown, YAML frontmatter, heading, table, bullet, or tag structure;
- `draft`, `strict`, approval, human-review, or sensitive-review lifecycle;
- source conversation, authoring prompt, repository, tool, agent, or provenance ledger.

Discovery may use a local filename convention as a convenience. Explicit selection must accept any repository-contained readable text file, and discovery conventions must not become a content schema.

## Interpretation

Reviewers read the whole text semantically. They identify only purposes, desired changes, user situations, boundaries, rejected outcomes, or uncertainty that are actually expressed. Absence of a conventional section is not a failure and must not create a new requirement.

The normalized content SHA-256 may be recorded to bind later evidence to the exact selected text. This is internal identity, not information the user must carry between tasks.

## Authoring suggestions

When creating a new Goal Context, it is often useful to explain the underlying problem, desired observable outcome, representative situation, and outcomes that would look complete while missing the point. These are suggestions, not mandatory fields.

The bundled validator checks readable non-empty text and a small set of high-confidence credential patterns. It cannot prove semantic completeness, correctness, privacy safety, or approval.
