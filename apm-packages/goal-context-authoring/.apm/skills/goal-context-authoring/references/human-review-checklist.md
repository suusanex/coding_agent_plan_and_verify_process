# Goal Context human review checklist

The reviewer must have access to the source conversation or authoritative decision notes. Structural validator success is not a substitute for this review.

## Purpose and boundaries

- [ ] Original problem describes the underlying pain, not only the requested feature.
- [ ] Desired outcome states the observable user value and current priority.
- [ ] Concrete user situations and scenarios match how the result will actually be used.
- [ ] MVP scope is complete enough to deliver the intended value.
- [ ] Non-goals and future work are separate from the MVP.

## Decisions and negative conditions

- [ ] Accepted decisions include the reasons that matter to later design choices.
- [ ] Rejected alternatives and rejection reasons are present and accurate.
- [ ] No rejected alternative was silently reintroduced as a recommendation.
- [ ] `Superficially compliant but wrong` includes concrete ways to satisfy the wording while missing the purpose.
- [ ] Review questions would expose those purpose-level failures.

## Conversation fidelity

- [ ] The full available conversation, including its early portion, was covered.
- [ ] Later corrections supersede earlier statements where the user actually changed direction.
- [ ] Priority changes are visible and not flattened into an undated list.
- [ ] The document is organized by purpose and decision, not by message chronology.
- [ ] The document adds context beyond an Issue copy without adding unsupported requirements.

## Provenance and uncertainty

- [ ] Material statements use `[Explicit]`, `[Inferred]`, or `[Unknown]` accurately.
- [ ] Inferences name their evidence and are not presented as user decisions.
- [ ] Contradictions and missing source remain open rather than being guessed closed.
- [ ] Assumptions state the consequence if they are wrong.

## Evidence and safety

- [ ] Acceptance evidence would demonstrate the desired outcome, not only task completion.
- [ ] Automated, runtime, document-review, and human evidence are distinguished where relevant.
- [ ] Secrets, credentials, authentication material, and private keys are absent.
- [ ] Unnecessary names, email addresses, account identifiers, and other personal data are absent or generalized.
- [ ] Necessary redactions retain only decision-relevant meaning.

## Naming and finalization

- [ ] Filename matches `goal-context-<topic-summary>.md` in lowercase kebab-case.
- [ ] The topic summary describes the durable subject and is not centered on an Issue, PR, ticket, or one-time task slug.
- [ ] Known source gaps are recorded under Document control and source boundary.
- [ ] Requested corrections from this review have been applied.
- [ ] Human review record identifies the reviewer, date, confirmations, and review changes.
- [ ] Frontmatter is changed to `status: human-reviewed` and `sensitive_data_review: passed` only after all checks above pass.

