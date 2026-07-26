---
document_type: goal-context
status: human-reviewed
topic: resumable local batch export
created_at: 2026-07-26
source_scope: all four segments of docs/examples/source-conversation-fixture.md; no known gaps
sensitive_data_review: passed
---

# Goal Context: Resumable local batch export

## Document control and source boundary

- [Explicit] Source material reviewed: all four ordered segments in `source-conversation-fixture.md`.
- [Explicit] Unavailable or truncated source: none in this fixture.
- [Explicit] Related Issue or artifact used only as a cross-check: none.

## Original problem

- [Explicit] Long-running exports across several customer workspaces can fail after unattended execution, and the user currently has to inspect each log to discover the failure and determine what work is safe to repeat.
- [Explicit] Re-running a whole export risks repeating confirmed work and endangering the last known-good output.

## Desired outcome

- [Explicit] On the same offline Windows machine, the user can identify the exact failed record, preserve confirmed output, and deliberately resume from durable progress without re-exporting records already confirmed as successful.
- [Explicit] Preserving known-good output has higher priority than fast notification.

## Concrete user situation and user scenarios

- [Explicit] Situation: the user starts exports for several customer workspaces before leaving work and returns after the processes may have succeeded, failed, or been interrupted.
- [Explicit] Scenario: a run fails on one record, exposes a local report and non-zero exit status, and provides a deterministic resume command that skips confirmed records.
- [Explicit] Scenario: a process is terminated abruptly, and the next invocation can recover from durable progress without treating unconfirmed work as complete.

## Scope and boundaries

### MVP scope

- [Explicit] Offline CLI execution on the same Windows machine.
- [Explicit] A durable local run manifest updated during execution.
- [Explicit] Protection of the last known-good export until a new run completes.
- [Explicit] Exact failure location, a printed local report path, and a non-zero exit code on failure.
- [Explicit] A deterministic, human-triggered resume operation that skips confirmed records and fails closed on input or configuration mismatch.

### Non-goals

- [Explicit] Dashboard or other graphical UI.
- [Explicit] Cloud telemetry, customer-data upload, and email notification.
- [Explicit] Automatic retry in the MVP.

### Future work

- [Explicit] A UI may be reconsidered after the CLI-first MVP proves the recovery contract.
- [Unknown] Remote notification may be reconsidered only with a separate privacy and operating-boundary decision.

## Decisions and reasoning

### Accepted decisions

| Provenance | Decision | Reason | Consequence |
| --- | --- | --- | --- |
| [Explicit] | Use a durable local run manifest and local failure report. | The workflow must operate offline and preserve enough progress for deterministic recovery. | State must be persisted during the run, not only in an end-of-run report. |
| [Explicit] | Keep the MVP CLI-first. | Recovery and output safety are the user value; the dashboard was only an early UI idea. | UI work cannot delay the recovery contract. |
| [Explicit] | Require human-triggered resume. | Automatic retries can cost money or duplicate external side effects. | The tool provides a deterministic command but does not decide when to retry. |
| [Explicit] | Fail closed when manifest input or configuration does not match. | Resuming against a different work set could skip or duplicate records incorrectly. | Resume requires identity and configuration validation. |

### Rejected alternatives

| Provenance | Alternative | Rejection reason | Revisit condition |
| --- | --- | --- | --- |
| [Explicit] | Dashboard as the MVP center. | It does not solve safe recovery and exact resume by itself. | Revisit after the CLI recovery contract is proven. |
| [Explicit] | Hosted telemetry and email. | Customer identifiers and export contents must not leave the machine, and the MVP must work offline. | Requires a separate privacy and operating-boundary decision. |
| [Explicit] | Automatic transient-error retries. | Requests may incur cost or duplicate an external side effect. | Requires an explicit idempotency and cost policy outside this MVP. |
| [Explicit] | Overwrite the previous good output during export. | An interrupted or failed run could destroy the known-good result. | Never within the current safety invariant. |

## Constraints and invariants

- [Explicit] Customer identifiers and export contents do not leave the local machine.
- [Explicit] An incomplete run never overwrites the last known-good export.
- [Explicit] A record is not marked complete until its export is confirmed.
- [Explicit] Resume skips confirmed records and stops on manifest/input/configuration mismatch.
- [Explicit] Progress is durable before normal process completion.
- [Inferred] Atomic promotion or an equivalently safe commit boundary is needed to satisfy the explicit known-good-output invariant; the source accepts atomic promotion as a direction but does not prescribe a storage implementation.

## Success scenarios

1. [Explicit] A run fails on record 42; records 1 through 41 remain confirmed, the known-good export remains intact, and a deterministic resume starts at the first unconfirmed record.
2. [Explicit] A process is terminated abruptly; persisted progress limits rework without marking an unconfirmed record complete.
3. [Explicit] A resume is attempted with changed input or export configuration; the tool refuses to continue and explains the mismatch.
4. [Explicit] A complete run promotes new output without exposing a partial result as the known-good export.

## Acceptance evidence

| Provenance | Outcome to demonstrate | Required evidence | Evidence type |
| --- | --- | --- | --- |
| [Explicit] | Confirmed records are not re-exported after a failure. | Controlled failure on record 42 followed by resume evidence showing records 1-41 skipped. | automated integration/runtime |
| [Explicit] | Known-good output survives interruption and failure. | Before/after file identity and content evidence across failed and terminated runs. | automated integration/runtime |
| [Explicit] | Invalid resume state fails closed. | Corrupted or mismatched manifest cases refuse resume with actionable diagnostics. | automated negative test |
| [Explicit] | Failure is actionable. | Non-zero exit code, exact failed record, local report path, and deterministic resume command are observable. | runtime and human review |
| [Inferred] | Durability/performance choice has a bounded loss window. | Documentation and interruption test identify the maximum possible rework after termination. | document review and runtime |

## Superficially compliant but wrong

- [Explicit] A dashboard reports that a run failed but provides no safe resume position or protection for confirmed output.
- [Explicit] A final report is written only on normal exit, so abrupt termination loses all progress.
- [Explicit] Resume starts near the failure but silently re-exports records already confirmed.
- [Explicit] Partial output replaces the last known-good export before the run is complete.
- [Explicit] A retry occurs automatically even though the endpoint may charge or perform a non-idempotent side effect.
- [Inferred] A manifest exists but is trusted without verifying its input set and export configuration, allowing an unsafe resume.

## Review questions

- [Explicit] Can the user recover after both a controlled record failure and abrupt termination without losing the known-good output?
- [Explicit] Does resume skip every confirmed record and refuse mismatched state?
- [Explicit] Are automatic retries, cloud telemetry, email, and dashboard work absent from the MVP?
- [Inferred] Does the implementation make the maximum rework window observable and consistent with the chosen persistence cadence?

## Open questions and assumptions

- [Unknown] Persistence after every record versus small batches is not decided; implementation may choose after measuring the durability/performance trade-off.
- [Explicit] Any chosen cadence must document maximum rework after interruption and must never mark an unconfirmed record complete.
- [Inferred] A scheduler can consume the non-zero exit code, but scheduler integration itself was not requested as an MVP deliverable.

## Conversation corrections and priority changes

| Provenance | Earlier statement | Current statement or priority | Evidence of supersession |
| --- | --- | --- | --- |
| [Explicit] | A dashboard was the initial proposed solution. | CLI-first safe recovery is the MVP; UI is future work. | The user clarified that dashboard was only the first imagined UI and later finalized a CLI-first MVP. |
| [Explicit] | Hosted telemetry and email were proposed. | Operation must remain offline with no customer-data upload. | The user explicitly excluded both from the MVP. |
| [Explicit] | Automatic retries were proposed. | Resume is deterministic but human-triggered. | The user rejected automatic retry because of cost and side-effect risk. |
| [Explicit] | Fast notification appeared central early. | Preserving known-good output is the highest priority; notification is secondary. | The user explicitly reprioritized safety above notification. |

## Provenance and inference ledger

| Claim or section | Classification | Source evidence or reasoning | Confidence / required follow-up |
| --- | --- | --- | --- |
| CLI-first MVP | [Explicit] | Confirmed in segments 2 and 4. | High. |
| No automatic retry | [Explicit] | Rejected in segment 3 with cost and side-effect reasons. | High. |
| Atomic or equivalent promotion boundary | [Inferred] | Connects the accepted atomic-promotion direction to the explicit known-good-output invariant. | Implementation may choose an equivalent mechanism and must prove the invariant. |
| Persistence cadence | [Unknown] | Explicitly left undecided in segment 4. | Requires implementation evidence and documentation, not a product decision unless trade-off changes the invariant. |

## Human review record

- Review status: Complete
- Reviewer: Fixture maintainer
- Reviewed at: 2026-07-26
- Desired outcome confirmed: Yes
- Rejected alternatives confirmed: Yes
- Superficially compliant but wrong outcomes confirmed: Yes
- MVP / Non-goals / Future work boundary confirmed: Yes
- Corrections and priority changes confirmed: Yes
- Provenance and unknowns confirmed: Yes
- Sensitive-data review confirmed: Yes
- Changes requested during review: Clarified that fast notification is secondary to output safety and retained persistence cadence as Unknown.

