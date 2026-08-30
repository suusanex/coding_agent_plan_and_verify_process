# Completion Notification Decorator integration validation

## Automated fixtures

`tests/integration-fixtures.json` covers two independent existing process families:

| Fixture | Primary process | Preserved verdict | Direct result |
| --- | --- | --- | --- |
| `adaptive-implementation` | `adaptive-implementation-execution` | `IMPLEMENTATION_COMPLETED` | repository-specific PR |
| `plan-coverage` | `plan-coverage-residual-flow` | `READY_TO_CLOSE_WITH_NO_RESIDUALS` | repository-specific Issue |

The validator derives each process package and Skill path from `primary_process`, then requires the canonical `apm.yml` and `.apm/skills/<primary_process>/SKILL.md` to exist and declare the same name. It also requires `observed_status` to appear as a verdict token in that canonical Skill and the fixture output to begin with the exact `Verdict: <observed_status>` line. Negative self-tests ensure an invented process, an unknown verdict, and a mismatched output verdict are rejected.

After binding each fixture to those canonical contracts, the contract validator and Local Spool integration validator run as separate checks. The integration validator verifies the checked canonical runtime mirror and sends a real completion event through the production Local Spool provider. It verifies the stable 10-field JSON projection, `primary_process`, `observed_status`, repository identity, result link, thread resume link, and source event identity without using a fake provider as the persistence substitute.

The Local Spool integration check keeps the runtime self-test for ordinary markerless callbacks, invalid-envelope fallback, callback identity, and fail-open behavior. Local Spool failure remains fail-open for the completed Codex turn and never produces a partial final JSON item.

Run from the repository root:

```powershell
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator-contract.ps1
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1
```

This is a reproducible integration fixture, not a claim that the full internal Adaptive or Plan Coverage agent sequence ran inside the test. Those existing contracts remain unchanged and outside the decorator.

## Live Local Spool evidence

The canonical runtime's installed callback-to-Spool-folder and editor-readable JSON evidence is recorded in `scripts/codex-notification-runtime/manual-verification.md`. The decorator integration reuses that runtime rather than duplicating its persistence logic.
