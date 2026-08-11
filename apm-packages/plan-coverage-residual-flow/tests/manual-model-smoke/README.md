# Invocation authorization manual smoke

This smoke validates observed model routing behavior that static contract checks cannot prove.

Run every scenario from `../invocation-authorization-scenarios.json` in a fresh disposable repository with the candidate package installed. Do not reuse a conversation between scenarios. Record the exact model, client, package commit, package version, prompt, selected Skill, created or changed artifacts, and invoked agents in `result-template.md`.

For Scenarios A, B, C, E, G, and H, pass only when `plan-coverage-residual-flow` is not selected, no Plan Coverage artifact is created or updated, and no Plan Coverage agent is invoked. A suggestion to use the route is also a failure.

For Scenarios D and F, pass only when the invocation authorization gate accepts the direct exact name or the complete durable evidence tuple and the existing flow can proceed past the gate.

Use `NOT RUN` when a scenario was not executed. Use `UNOBSERVABLE` when the client cannot expose Skill or agent selection evidence. Neither status counts as a pass.

The latest observed A-H run is recorded in `results/20260801-99e88a8.md`. Its evidence uses the model's final routing response together with JSONL command/artifact deltas; Codex CLI does not expose a separate internal Skill-router event.

## Decision ownership regression smoke

Run `../decision-ownership-scenarios.json` in a fresh disposable repository for both Codex and GitHub Copilot CLI. Each scenario supplies the upstream decision authority through `UPSTREAM.md`; do not add a secret, token, PAT, credential value, or private repository content.

For every `DO-001` through `DO-003`, record the exact client, model, prompt, observed agent evidence, terminal verdict, and the `Decision Ownership Gate` evidence. `DO-001` must run through the Slice Living Record path with `artifact_mode: slice-living-record`, its supplied Living Record path, canonical ledger path, and `output_contract: section-delta`; confirm the returned section delta contains `Implementation Contract Decisions`, `Decision Ownership Gate`, and `Coverage Ledger Delta`. Use the scenario's `manual_acceptance` field as the pass criterion. `NOT RUN` and `UNOBSERVABLE` are not PASS, and a result for one client does not stand in for the other client.

This is ManualOnly regression evidence. It is not an ordinary CI requirement and it does not replace the deterministic package validator, standalone fixture, or Copilot qualification harness.
