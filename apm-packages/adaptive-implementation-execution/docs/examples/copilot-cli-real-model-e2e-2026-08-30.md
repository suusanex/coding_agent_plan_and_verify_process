# GitHub Copilot CLI real-model E2E evidence for Adaptive 0.6.0 (2026-08-30)

このrecordはdecision-surface ownership contractのcandidate qualification用templateです。0.4.0 / 0.5.0のrecordを0.6.0のevidenceとして再利用しません。

| Field | Value |
| --- | --- |
| Candidate commit | NOT RUN |
| Copilot CLI version | NOT RUN |
| APM version | NOT RUN |
| Disposable fixture repository | NOT RUN |
| Requested / observed models | NOT RUN |

## Scenarios

| Scenario | Expected | Evidence | Status |
| --- | --- | --- | --- |
| implementation-feedback-loop | Decision-Surface owner implements and verifies until transfer is safe | NOT RUN | NOT RUN |
| inspection-only-transfer | evidence-backed zero-code transfer remains allowed | NOT RUN | NOT RUN |
| natural-owner-completion | first owner completes without exception reason | NOT RUN | NOT RUN |
| bounded-residual-completion | residual owner completes locked work | NOT RUN | NOT RUN |
| decision-surface-reentry | new decision surface returns with durable state | NOT RUN | NOT RUN |
| progress-based-retransfer | resolved re-entry trigger may transfer again even when the remaining or allowed surface expands | NOT RUN | NOT RUN |
| invalid-old-schema | 0.5 handoff fails closed | NOT RUN | NOT RUN |

## Qualification decision

- APM distribution: NOT RUN
- Agent Plugin direct distribution: HOLD
- Overall: NOT RUN

人手での作業が必要: candidate commitをremote refとして利用可能にした後、secretやprivate dataを含まないdisposable repositoryで実行し、実測値だけを記録する。
