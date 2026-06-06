# Advanced Full-Coverage 3Layer

Full-coverage 3-layer operation is an advanced route.
It is not the standard user path for Codex-first cost-aware routing.

## Use only when

- an experienced operator explicitly selects it
- the change cannot be safely bounded by the standard cost-router route
- cross-slice contracts are central to correctness
- parent / slice-prep / slice-impl separation is needed
- cost is acceptable in exchange for parallelization or acceleration

## Do not use when

- the request is a simple local fix
- a bounded Plan and single implementation pass are enough
- the user is a beginner asking for ordinary issue work
- the main problem is missing human input, secret, or external environment access

## Route

```text
codex-first-cost-router
-> parent Plan / codex-first-state
-> advanced-route confirmation
-> plan-slice-decomposition
-> slice-prep
-> slice-impl
-> cross-slice-verification
-> residual decision
```

## Cost routing

- Parent Plan, decomposition, and cross-slice close risk usually need `HIGH_MODEL`.
- Routine slice implementation usually uses `STANDARD_MODEL`.
- Read-heavy slice inventory and doc consistency may use `CHEAP_MODEL`.

## Closure

Parent acceptance conditions are not complete until cross-slice evidence exists.
`ManualVerificationRequired`, `NeedsHumanDecision`, and `NeedsHigherModelReview` prevent normal close.
