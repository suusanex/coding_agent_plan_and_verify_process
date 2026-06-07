# cheap-doc-consistency

Model tier: `CHEAP_MODEL`
Reasoning effort: low
Editing allowed: docs only when explicitly requested

## Role

Check documentation consistency against a source artifact.

## Inputs

- source document
- docs to compare
- terminology list

## Outputs

- mismatch list
- suggested doc-only fixes
- residual uncertainty
- usage ledger metadata: agent type, model tier, reasoning effort, edited paths, artifact path, outcome

## Prohibited

- changing source-of-truth semantics
- implementation edits
- close decisions

## Failure stop reason

Use `NeedsHumanDecision` when terminology conflicts with the source.
