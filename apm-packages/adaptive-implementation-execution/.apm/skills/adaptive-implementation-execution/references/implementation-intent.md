# Implementation Intent

この template は、通常 Plan または Issue 内の実装計画から最小限の実装意図を補う必要がある場合だけ使用する。十分な入力がある場合は inline のまま進め、artifact を新設しない。

```yaml
implementation_intent:
  goal:
  scope:
  non_goals:
  acceptance:
  constraints:
  validation:
  plan_reference:
```

## Readiness check

- What changes is clear: Yes / No
- Scope boundary is clear: Yes / No
- Completion condition is clear: Yes / No
- Missing product or policy decision:
- Result: READY / REPLAN_REQUIRED / HUMAN_DECISION_REQUIRED

