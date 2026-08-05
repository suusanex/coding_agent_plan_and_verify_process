[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$EvidenceRoot = '',
    [string]$CopilotCommand = 'copilot',
    [string]$Model = 'gpt-5.4',
    [int]$TimeoutSeconds = 600,
    [switch]$DescribePayload,
    [switch]$ConfirmExternalModelPayload
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}

$executor = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\skills\goal-context-pr-review\scripts\execute-reviewer.cs'
$skillRoot = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\skills\goal-context-pr-review'
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $RepositoryRoot 'tests\pr-review-remediation\execute-reviewer-smoke'
} else {
    $EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMddTHHmmssZ'
$recordPath = Join-Path $EvidenceRoot "copilot-smoke-$stamp.md"

function New-SmokeRun {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("execute-reviewer-copilot-smoke-" + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repo '.github\agents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null
    Copy-Item (Join-Path $RepositoryRoot '.github\agents\local-reviewer.agent.md') (Join-Path $repo '.github\agents\local-reviewer.agent.md')
    Copy-Item (Join-Path $RepositoryRoot '.github\agents\purpose-reviewer.agent.md') (Join-Path $repo '.github\agents\purpose-reviewer.agent.md')
    # Intentionally omit Codex TOML profiles so Copilot-only installs are exercised.
    Set-Content (Join-Path $repo 'docs\goal-context-smoke.md') -Value "Goal: verify Copilot CLI reviewer adapter captures raw review text.`n"
    Push-Location $repo
    try {
        git init -q | Out-Null
        git -c user.email=smoke@example.com -c user.name=smoke add docs .github apm-packages | Out-Null
        git -c user.email=smoke@example.com -c user.name=smoke commit -qm 'smoke fixture' | Out-Null
    } finally { Pop-Location }

    $run = Join-Path $repo '.review\pr-1\same-thread\20260805T000000Z-smoke001'
    $round = Join-Path $run 'round-001'
    New-Item -ItemType Directory -Path $round -Force | Out-Null
    @{
        repository = 'smoke/execute-reviewer'
        pullRequest = 1
        baseOid = ('a' * 40)
        headOid = ('b' * 40)
        isDraft = $false
        copilotObservedState = 'reviewOnly'
        copilotTimedOut = $false
        copilotIsComplete = $true
    } | ConvertTo-Json | Set-Content (Join-Path $round 'review-context.json')
    Set-Content (Join-Path $round 'pr-diff.patch') "diff --git a/docs/goal-context-smoke.md b/docs/goal-context-smoke.md`n+smoke`n"
    @{
        selectedPath = 'docs/goal-context-smoke.md'
        contentSha256 = ('c' * 64)
        status = 'SELECTED'
    } | ConvertTo-Json | Set-Content (Join-Path $round 'goal-context-selection.json')
    return [pscustomobject]@{ Root = $root; Repo = $repo; Run = $run }
}

$payload = @"
Real GitHub Copilot CLI smoke for execute-reviewer.cs
- execution-app: copilot-cli
- model: $Model
- role: local-reviewer
- timeout-seconds: $TimeoutSeconds
- repository revision: $((git -C $RepositoryRoot rev-parse HEAD 2>$null))
- command shape: copilot -p <short-prompt-ref> --model $Model -C <scratch> -s --output-format text --no-ask-user --no-custom-instructions --disable-builtin-mcps --available-tools <read-only> --deny-tool write/shell/...
- secrets: none on argv (full assignment is a workdir file, not argv)
- VS Code UI: not required
- Codex TOML profiles: not required for Copilot-only path
"@

if ($DescribePayload) {
    Write-Host $payload
    exit 0
}

if (-not $ConfirmExternalModelPayload) {
    throw 'Refusing to call an external model. Re-run with -DescribePayload or -ConfirmExternalModelPayload after reviewing the payload.'
}

$copilotVersion = (& $CopilotCommand --version 2>&1 | Out-String).Trim()
$fixture = New-SmokeRun
try {
    $out = & dotnet run --file $executor -- @(
        '--execution-app', 'copilot-cli',
        '--model', $Model,
        '--reviewer-role', 'local-reviewer',
        '--run-root', $fixture.Run,
        '--round', '1',
        '--timeout-seconds', "$TimeoutSeconds",
        '--repository-root', $fixture.Repo,
        '--skill-root', $skillRoot,
        '--copilot-executable', $CopilotCommand,
        '--format', 'json'
    ) 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $rawPath = Join-Path $fixture.Run 'round-001\local-reviewer.raw.md'
    $metaPath = Join-Path $fixture.Run 'round-001\local-reviewer.execution.json'

    $record = @"
# execute-reviewer GitHub Copilot CLI smoke

- timestamp: $stamp
- copilot_cli_version: $copilotVersion
- repository_revision: $((git -C $RepositoryRoot rev-parse HEAD 2>$null))
- requested_model: $Model
- observed_model: unknown unless metadata reports otherwise
- execution_app: copilot-cli
- command_shape_without_secrets: copilot -p <short-prompt-ref> --model $Model -C <repo> -s --output-format text --no-ask-user --no-custom-instructions --disable-builtin-mcps --available-tools <read-only> --deny-tool write/shell/task/memory ...
- input_summary: disposable repo with review-context.json, pr-diff.patch, goal-context-selection.json, role contracts (no Codex TOML)
- concurrent_invocation_identity: single local-reviewer invocation in this record
- worktree_write_check: executor pre/post snapshot must remain clean for success
- limitations: observed model may remain unknown; tool allowlist + MCP disable + worktree check; not OS sandbox proof; no VS Code UI

## Result
- exit_code: $exitCode
- raw_exists: $(Test-Path -LiteralPath $rawPath)
- metadata_exists: $(Test-Path -LiteralPath $metaPath)
- output:
``````
$out
``````
"@
    if (Test-Path -LiteralPath $rawPath) {
        $record += "`n- raw_artifact:`n``````markdown`n$(Get-Content -Raw -LiteralPath $rawPath)`n``````n"
    }
    if (Test-Path -LiteralPath $metaPath) {
        $record += "`n- metadata:`n``````json`n$(Get-Content -Raw -LiteralPath $metaPath)`n``````n"
    }

    Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8
    Write-Host "Wrote smoke record: $recordPath"
    if ($exitCode -ne 0) { exit 2 }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $fixture.Root) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
