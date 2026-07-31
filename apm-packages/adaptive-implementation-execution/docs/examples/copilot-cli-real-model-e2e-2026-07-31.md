# GitHub Copilot CLI real-model E2E evidence (2026-07-31)

This record captures an automated real-model execution of the Adaptive implementation route in a disposable local Git repository. It supplements, but does not replace, VS Code-specific UI handoff coverage.

## Environment

| Field | Observed value |
| --- | --- |
| Date / operator | 2026-07-31 / Codex |
| Source pull request | `suusanex/coding_agent_plan_and_verify_process` PR #67 |
| Adaptive package commit | `816268eea12ae4e61a40f045de9448d180ef4a2c` |
| Disposable repository | `C:\WindowsTemp\adaptive-copilot-cli-e2e-pr67-816268e` |
| Fixture baseline | `81757f1` (`main`) |
| APM | 0.26.0 |
| GitHub Copilot CLI | 1.0.77 |
| Node.js | v26.4.0 |

The package was installed from the full source commit with:

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/adaptive-implementation-execution#816268eea12ae4e61a40f045de9448d180ef4a2c --target copilot,agent-skills --https
```

The install deployed both repository-local Copilot agents and the shared Skill. Each Copilot invocation explicitly selected the applicable agent with `--agent`.

## Observed model resolution

Copilot CLI debug logs recorded these resolutions:

- HIGH start and HIGH re-entry: `Using model "gpt-5.6-terra" from custom agent "high-implementation-starter" (resolved from "GPT-5.6 Terra (copilot)")`
- STANDARD completion: `Using model "gpt-5.6-luna" from custom agent "standard-implementation-completer" (resolved from "GPT-5.6 Luna (copilot)")`

The structural route therefore observed `gpt-5.6-terra -> gpt-5.6-luna -> gpt-5.6-terra`.

## Scenario evidence

All commit identifiers below belong to the disposable E2E repository.

| Scenario | Branch / evidence commit | Observed behavior | Validation | Terminal verdict |
| --- | --- | --- | --- | --- |
| Direct HIGH completion | `e2e/direct-high` / `b0420bf` | Terra implemented `increment`; route stayed `adaptive / default / N/A`; STANDARD was not started | `node --test test/counter.test.js`: 1 passed | `COMPLETED_BY_HIGH_MODEL` |
| Bounded HIGH checkpoint | `e2e/bounded-reentry` / `b375d1c` | Terra implemented and verified the representative `formatUser` path, then wrote a tracked completion handoff with acceptance mapping, Locked Decisions, Remaining Work, Allowed edit surface, validation evidence, and re-entry fields | `node --test test/report-user.test.js`: 1 passed | `READY_FOR_STANDARD_COMPLETION` |
| STANDARD bounded completion | `e2e/bounded-standard-complete` / `8dcfd9c` | Luna validated the tracked handoff, changed only `src/report.js` within the allowed surface, and left the unrelated counter path unchanged | `node --test test/report-user.test.js test/report-users.test.js`: 2 passed | `COMPLETED` |
| STANDARD structural discovery | `e2e/structural-reentry` / `39f8c5d` | Luna completed the allowed `report.js` work, observed that the public entrypoint required an out-of-surface export, did not edit `src/index.js`, and wrote a tracked re-entry handoff with `reentry_count: 1` | focused report tests: 2 passed; public API test: expected failure before re-entry | `NEEDS_HIGH_MODEL_REENTRY` |
| HIGH structural re-entry | `e2e/structural-reentry` / `b711700` | Terra consumed the original intent plus completion and re-entry artifacts, preserved route identity and Locked Decisions, retained STANDARD work, changed only `src/index.js`, and did not delegate the same trigger again | focused report tests: 2 passed; public API test: 1 passed | `COMPLETED_BY_HIGH_MODEL` |
| Incomplete handoff rejection | `e2e/negative-routing` / `430f9ff` | Luna rejected an incomplete current-schema completion handoff before production or test edits; it reported the raw route and `<missing>` source instead of inferring `default` | production/test changes: 0 | `BLOCKED / BlockedByInvalidCompletionHandoff` |
| Direct STANDARD rejection | `e2e/negative-routing` / `c2e6a00` | Luna rejected fresh intake without a tracked completion handoff; all absent route fields remained `<missing>` | production/test changes: 0 | `BLOCKED / BlockedByInvalidCompletionHandoff` |

## Completion decision

- HIGH-first observed: `PASS`
- valid tracked handoff required before Luna: `PASS`
- bounded STANDARD ownership and completion: `PASS`
- structural trigger returned from Luna to Terra: `PASS`
- original intent, route identity, and Locked Decisions retained: `PASS`
- invalid or absent handoff rejected without inferred defaults or edits: `PASS`
- no unexpected automatic agent transition: `PASS` for Copilot CLI execution
- terminal route verdicts: `PASS`

## Coverage boundary

Copilot CLI 1.0.77 loaded the agents, selected their configured models, loaded the Skill, edited files, ran tests, and produced tracked artifacts. It also logged `.github\agents\*.agent.md: unknown fields ignored: target, handoffs`. Therefore this evidence does not claim that the VS Code `target` filter or handoff button was exercised. Those are VS Code UI-specific checks and remain `NOT RUN` in the manual smoke template.

Full transient CLI logs and fixture branches were kept only in the disposable repository during execution. This committed record preserves the model-resolution lines, scenario commit identities, route artifacts, validation results, terminal verdicts, and known coverage boundary needed to audit the run.
