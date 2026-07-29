# Completion Notification Decorator integration validation

## Automated fixtures

`tests/integration-fixtures.json` covers two independent existing process families:

| Fixture | Primary process | Preserved verdict | Direct result |
| --- | --- | --- | --- |
| `adaptive-implementation` | `adaptive-implementation-execution` | `COMPLETED_BY_HIGH_MODEL` | repository-specific PR |
| `plan-coverage` | `plan-coverage-residual-flow` | `READY_TO_CLOSE_WITH_NO_RESIDUALS` | repository-specific Issue |

The validator derives each process package and Skill path from `primary_process`, then requires the canonical `apm.yml` and `.apm/skills/<primary_process>/SKILL.md` to exist and declare the same name. It also requires `observed_status` to appear as a verdict token in that canonical Skill and the fixture output to begin with the exact `Verdict: <observed_status>` line. Negative self-tests ensure an invented process, an unknown verdict, and a mismatched output verdict are rejected.

After binding each fixture to those canonical contracts, the validator constructs each final response by appending one envelope to the fixture's primary output, then proves that removing only the envelope recovers the original output byte-for-byte. It sends a real `agent-turn-complete` payload through the canonical runtime and a fake provider, then verifies `primary_process`, `observed_status`, repository identity, result link, thread resume link, and distinct source event IDs.

The same run verifies that a marker-only intermediate callback is suppressed until a valid terminal envelope exists, and also verifies a provider-failure callback. The failure path must exit with code 0, preserve the process status in the authored response, and record delivery failure separately in the runtime log.

Run from the repository root:

```powershell
./apm-packages/completion-notification-decorator/scripts/validate-completion-notification-decorator.ps1
```

This is a reproducible integration fixture, not a claim that the full internal Adaptive or Plan Coverage agent sequence ran inside the test. Those existing contracts remain unchanged and outside the decorator.

## Live notification evidence

The canonical runtime's Windows notification, PR direct-link, thread deep-link, and provider-failure evidence is recorded in `scripts/codex-notification-runtime/manual-verification.md`. The decorator integration reuses that runtime rather than duplicating its provider or link logic.
