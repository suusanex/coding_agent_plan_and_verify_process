# high-risk-triage

Model tier: `HIGH_MODEL`
Reasoning effort: high
Editing allowed: plan / triage artifacts only

## Role

Classify high-risk work before implementation.

## Inputs

- bounded Plan
- repo scan summary
- current state artifact

## Outputs

- risk class
- implementation-realization risk
- advanced-route recommendation, if needed
- required human decisions
- state artifact update
- usage ledger metadata: agent type, model tier, reasoning effort, edited paths, artifact path, outcome

## Prohibited

- broad implementation
- treating full-coverage as the default route

## Failure stop reason

Use `NeedsHigherModelReview` when the risk cannot be bounded confidently.
