---
document_type: goal-context
status: human-reviewed
topic: direct purpose review notification cycle
created_at: 2026-07-27
source_scope: synthetic safe fixture for Issue 55 validation
sensitive_data_review: passed
---

# Goal Context: Direct purpose review notification cycle

## Document control and source boundary

- [Explicit] This synthetic fixture covers Goal Context selection, purpose review, integrated planning, notification, and manual Adaptive handoff.

## Original problem

- [Explicit] A user must repeatedly search across tools to discover whether PR review finished and where to continue remediation.

## Desired outcome

- [Explicit] The user receives a direct-link notification after an independent purpose review and can manually start remediation from a complete integrated plan.

## Concrete user situation and user scenarios

- [Explicit] A maintainer reviews several repositories, opens the notified PR directly, and starts Adaptive Implementation in a separate Codex parent turn.

## Scope and boundaries

### MVP scope

- [Explicit] Select one confirmed Goal Context, run independent code and purpose reviews, integrate findings, stop, and notify with a direct PR link.

### Non-goals

- [Explicit] Do not start remediation automatically or merge the PR.

### Future work

- [Unknown] Cross-device notification history may be considered later.

## Decisions and reasoning

### Accepted decisions

| Provenance | Decision | Reason | Consequence |
| --- | --- | --- | --- |
| [Explicit] | Keep two parent turns. | The user must control when implementation begins. | Review planning always stops before production edits. |

### Rejected alternatives

| Provenance | Alternative | Rejection reason | Revisit condition |
| --- | --- | --- | --- |
| [Explicit] | Add another implementation agent. | It duplicates canonical Adaptive Implementation. | Never within this MVP. |

## Constraints and invariants

- [Explicit] Missing or ambiguous Goal Context must stop purpose review instead of falling back to the Issue body.

## Success scenarios

1. [Explicit] A human-reviewed Goal Context is selected, reviews are integrated, the first turn stops, and a notification opens the exact PR.
2. [Explicit] The user starts Adaptive Implementation with the review plan in a separate turn and receives its terminal notification.

## Acceptance evidence

| Provenance | Outcome to demonstrate | Required evidence | Evidence type |
| --- | --- | --- | --- |
| [Explicit] | Direct review-to-remediation handoff works. | Selection artifact, independent findings, integrated plan, direct-link envelope, and separate turn input. | automated / document review |

## Superficially compliant but wrong

- [Explicit] A review that rereads only the Issue or immediately edits production code is wrong even if it emits a plan.

## Review questions

- [Explicit] Does the PR reduce search effort while preserving the manual implementation boundary?

## Open questions and assumptions

- [Unknown] This synthetic fixture does not prove a live OS notification provider on every machine.

## Conversation corrections and priority changes

| Provenance | Earlier statement | Current statement or priority | Evidence of supersession |
| --- | --- | --- | --- |
| [Explicit] | Automate the whole cycle. | Preserve the manual boundary and prioritize direct links. | Final fixture contract. |

## Provenance and inference ledger

| Claim or section | Classification | Source evidence or reasoning | Confidence / required follow-up |
| --- | --- | --- | --- |
| Manual boundary | [Explicit] | Fixture source contract. | Confirmed for this test. |

## Human review record

- Review status: Complete
- Reviewer: Fixture operator
- Reviewed at: 2026-07-27
- Desired outcome confirmed: Yes
- Rejected alternatives confirmed: Yes
- Superficially compliant but wrong outcomes confirmed: Yes
- MVP / Non-goals / Future work boundary confirmed: Yes
- Corrections and priority changes confirmed: Yes
- Provenance and unknowns confirmed: Yes
- Sensitive-data review confirmed: Yes
- Changes requested during review: None
