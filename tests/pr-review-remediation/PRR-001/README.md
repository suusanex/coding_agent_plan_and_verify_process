# PRR-001 Canonical Profile Direct Execution Smoke

`input-snapshots/`は、このactual external-model runで使用したlocal reviewer / baseline planner contract、profile、templateのimmutable copyです。現行の決定論的なbaseline contractは`validate-pr-review-remediation.ps1`で確認します。外部model smokeの再実行には明示同意が必要です。

This fixture verifies the `local-reviewer` to `review-planner` sequence with two
separate real-model `codex exec` invocations. It is a compatibility-path smoke,
not proof that Codex selected the installed custom-agent roles through
`spawn_agent`.

The runner loads each canonical profile as direct CLI configuration:

- configured agent name, profile hash, and canonical contract hash are recorded;
- the observed execution is recorded as top-level `codex exec` with agent path
  `/root`;
- `customAgentSpawnObserved` must remain `false`;
- model, reasoning effort, sandbox, session ID, turn ID, usage, duration, output
  hash, and clean Git state are read from the persisted Codex rollout;
- committed text hashes normalize CRLF to LF so the evidence is portable across
  Git checkout settings.

## External model payload

Running the smoke transmits the following fixture or repository content to the
configured Codex model service. The runner prints the resolved list and refuses
to continue unless `-ConfirmExternalModelPayload` is supplied.

Use `-DescribePayload` to print the resolved payload without invoking a model.

- `tests/pr-review-remediation/PRR-001/fixture/AGENTS.md`
- `tests/pr-review-remediation/PRR-001/fixture/README.md`
- `tests/pr-review-remediation/PRR-001/fixture/src/Fixture.cs`
- `tests/pr-review-remediation/PRR-001/fixture/.review/pr-123/review-context.json`
- `tests/pr-review-remediation/PRR-001/fixture/.review/pr-123/pr-diff.patch`
- `tests/pr-review-remediation/PRR-001/prompt-local-reviewer.txt`
- `tests/pr-review-remediation/PRR-001/prompt-review-planner.txt`
- `.github/agents/local-reviewer.agent.md`
- `.github/agents/review-planner.agent.md`
- both canonical Codex profile files, through their `developer_instructions`
  configuration values
- both canonical review output templates copied into the isolated fixture
- the local findings produced by the first run, as input to the planner run
- tool results produced while the agents inspect the isolated fixture repository,
  including fixture Git metadata

No production repository source file is copied into the scratch repository. Raw
Codex rollouts can contain system instructions and local environment context;
they are inspected locally, are never copied into this evidence directory, and
must not be committed.

## Run

From the repository root:

```powershell
pwsh apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1 `
  -ConfirmExternalModelPayload
```

Successful execution creates `local-review-findings.md`, `review-plan.md`, and
`run.json` in this directory. Validate them with:

```powershell
pwsh apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-agent-smoke.ps1
```

Until the authorized real-model run is completed, the validator must fail with
an explicit missing-evidence message.
