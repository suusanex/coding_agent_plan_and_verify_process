# Example: Ambiguous High-Risk Change

## Request

```text
認証まわりの処理を直して。
```

## Expected behavior

- Route to `HIGH_MODEL`.
- Do not implement immediately.
- Identify auth boundary, production wiring, external provider, config, and secret risks.
- Create or update a bounded Plan.
- Produce an implementation contract before editing.
- Stop with `NeedsHumanDecision` if the intended behavior or compatibility policy is unclear.
