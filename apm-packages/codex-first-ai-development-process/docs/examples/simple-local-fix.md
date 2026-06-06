# Example: Simple Local Fix

## Request

```text
この typo を直して。
```

## Expected behavior

- Read repo instructions.
- Confirm the target file and typo.
- Use `CHEAP_MODEL` or equivalent low-cost handling.
- Avoid unnecessary Plan-heavy flow.
- Update state only if the repo convention or ongoing work requires it.
- Run lightweight verification such as diff review or docs check.
