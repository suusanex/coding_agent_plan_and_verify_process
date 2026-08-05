# execute-reviewer real adapter smoke

Deterministic fake-CLI coverage lives in:

```powershell
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/validate-execute-reviewer.ps1
```

Real external-model smokes require explicit payload review:

```powershell
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/run-execute-reviewer-codex-smoke.ps1 -DescribePayload
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/run-execute-reviewer-codex-smoke.ps1 -ConfirmExternalModelPayload

pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/run-execute-reviewer-copilot-smoke.ps1 -DescribePayload
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/run-execute-reviewer-copilot-smoke.ps1 -ConfirmExternalModelPayload
```

Records are written under this directory and should include CLI version, requested/observed model, repository revision, input summary, command shape without secrets, raw artifact presence, exit/timeout/failure result, worktree write check, and adapter limitations.

Codex failure scenario example:

```powershell
pwsh -NoProfile -File apm-packages/pr-review-remediation/scripts/run-execute-reviewer-codex-smoke.ps1 `
  -ConfirmExternalModelPayload -IncludeFailureScenario
```

Committed smoke records (when available) live beside this README. Without a committed record, Issue #77 real-adapter acceptance is incomplete.
