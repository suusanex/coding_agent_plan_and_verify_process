# GitHub Copilot CLI real-model E2E evidence for Adaptive 0.5.0 (2026-08-09)

This record is reserved for the Adaptive 0.5.0 STANDARD-ownership contract. It does not reuse the 2026-07-31 Adaptive 0.4.0 result as evidence.

## Environment

| Field | Observed value |
| --- | --- |
| Date / operator | NOT RUN |
| Source revision / remote ref | NOT RUN |
| Adaptive package version | `0.5.0` |
| Disposable repository | NOT RUN |
| APM version | NOT RUN |
| GitHub Copilot CLI version | NOT RUN |
| HIGH configured / observed model | Terra / NOT RUN |
| STANDARD configured / observed model | Luna / NOT RUN |

## Required scenarios

| Scenario | Required observation | Status |
| --- | --- | --- |
| Zero/minimal HIGH implementation | HIGH closes every non-local decision from code, wiring, signatures, call sites, and tests; `HIGH_MODEL code changes: No` is accepted | NOT RUN |
| STANDARD implementation ownership | STANDARD creates the locked class/interface, method implementation, DI registration, tests, and validation | NOT RUN |
| STANDARD local autonomy | Private helpers, branch organization, fixtures, and test data builders do not cause re-entry | NOT RUN |
| Locked wiring implementation | Implementing HIGH-locked wiring returns `COMPLETED` | NOT RUN |
| Locked boundary invalidation | A required shared-signature or architecture change returns `NEEDS_HIGH_MODEL_REENTRY` | NOT RUN |
| Direct completion exception | Initial reasonless `COMPLETED_BY_HIGH_MODEL` is rejected and valid `tiny-local-change` evidence is accepted | NOT RUN |

## Work distribution metrics

| Metric | Observed value |
| --- | --- |
| eligible_for_standard_delegation | NOT RUN |
| standard_started | NOT RUN |
| HIGH direct completion reason | NOT RUN |
| HIGH changed LOC / test LOC | NOT RUN |
| STANDARD changed LOC / test LOC | NOT RUN |
| STANDARD changed LOC share | NOT RUN |
| handoff size / token estimate | NOT RUN |
| model input / output token | NOT RUN; use `Unavailable` with a reason if the client does not expose it |
| re-entry count / trigger category | NOT RUN |
| acceptance miss | NOT RUN |
| review findings | NOT RUN |

## Completion decision

- zero/minimal HIGH implementation observed: NOT RUN
- STANDARD production implementation ownership observed: NOT RUN
- local reversible choices stayed on STANDARD: NOT RUN
- edit type alone did not trigger re-entry: NOT RUN
- locked non-local decision change triggered re-entry: NOT RUN
- baseline quality non-inferiority: NOT RUN

人手での作業が必要: candidate revisionをremote refとして利用可能にした後、secretやprivate dataを含まないdisposable synthetic repositoryへAdaptive 0.5.0をAPM installし、上記scenarioとmetricsを実測値で更新する。STANDARD start rate、LOC share、re-entry rateは観測指標でありmerge gateではない。未実行の行をPASSにせず、clientが公開しないtoken値を推測しない。
