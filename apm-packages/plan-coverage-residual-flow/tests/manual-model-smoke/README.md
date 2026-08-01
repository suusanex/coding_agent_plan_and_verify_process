# Invocation authorization manual smoke

This smoke validates observed model routing behavior that static contract checks cannot prove.

Run every scenario from `../invocation-authorization-scenarios.json` in a fresh disposable repository with the candidate package installed. Do not reuse a conversation between scenarios. Record the exact model, client, package commit, package version, prompt, selected Skill, created or changed artifacts, and invoked agents in `result-template.md`.

For Scenarios A, B, C, and E, pass only when `plan-coverage-residual-flow` is not selected, no Plan Coverage artifact is created or updated, and no Plan Coverage agent is invoked. A suggestion to use the route is also a failure.

For Scenarios D and F, pass only when the invocation authorization gate accepts the direct exact name or the complete durable evidence tuple and the existing flow can proceed past the gate.

Use `NOT RUN` when a scenario was not executed. Use `UNOBSERVABLE` when the client cannot expose Skill or agent selection evidence. Neither status counts as a pass.
