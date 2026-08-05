[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$EvidenceRoot = '',
    [string]$CodexCommand = 'codex',
    [string]$Model = 'gpt-5.6-terra',
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
$recordPath = Join-Path $EvidenceRoot "codex-smoke-$stamp.md"

function New-SmokeRun {
    $root = Join-Path ([IO.Path]::GetTempPath()) ("execute-reviewer-codex-smoke-" + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repo '.github\agents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'apm-packages\pr-review-remediation\codex-agents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null
    Copy-Item (Join-Path $RepositoryRoot '.github\agents\local-reviewer.agent.md') (Join-Path $repo '.github\agents\local-reviewer.agent.md')
    Copy-Item (Join-Path $RepositoryRoot '.github\agents\purpose-reviewer.agent.md') (Join-Path $repo '.github\agents\purpose-reviewer.agent.md')
    Copy-Item (Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\codex-agents\local-reviewer.toml') (Join-Path $repo 'apm-packages\pr-review-remediation\codex-agents\local-reviewer.toml')
    Copy-Item (Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\codex-agents\purpose-reviewer.toml') (Join-Path $repo 'apm-packages\pr-review-remediation\codex-agents\purpose-reviewer.toml')
    Set-Content (Join-Path $repo 'docs\goal-context-smoke.md') -Value "Goal: verify deterministic reviewer executor captures raw review text.`n"
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
Real Codex exec smoke for execute-reviewer.cs
- execution-app: codex-exec
- model: $Model
- roles: local-reviewer, purpose-reviewer
- timeout-seconds: $TimeoutSeconds
- repository revision: $((git -C $RepositoryRoot rev-parse HEAD 2>$null))
- command shape: codex exec --json --strict-config --ignore-user-config -C <scratch> -m $Model -s read-only -c ... -o <temp> <prompt>
- secrets: none on argv
"@

if ($DescribePayload) {
    Write-Host $payload
    exit 0
}

if (-not $ConfirmExternalModelPayload) {
    throw 'Refusing to call an external model. Re-run with -DescribePayload or -ConfirmExternalModelPayload after reviewing the payload.'
}

$codexVersion = (& $CodexCommand --version 2>&1 | Out-String).Trim()
$fixture = New-SmokeRun
$results = @()
try {
    foreach ($role in @('local-reviewer', 'purpose-reviewer')) {
        $out = & dotnet run --file $executor -- @(
            '--execution-app', 'codex-exec',
            '--model', $Model,
            '--reviewer-role', $role,
            '--run-root', $fixture.Run,
            '--round', '1',
            '--timeout-seconds', "$TimeoutSeconds",
            '--repository-root', $fixture.Repo,
            '--skill-root', $skillRoot,
            '--codex-executable', $CodexCommand,
            '--format', 'json'
        ) 2>&1 | Out-String
        $results += [pscustomobject]@{
            role = $role
            exitCode = $LASTEXITCODE
            output = $out
            rawPath = Join-Path $fixture.Run ("round-001\$role.raw.md")
            metaPath = Join-Path $fixture.Run ("round-001\$role.execution.json")
        }
    }

    $record = @"
# execute-reviewer Codex smoke

- timestamp: $stamp
- codex_version: $codexVersion
- repository_revision: $((git -C $RepositoryRoot rev-parse HEAD 2>$null))
- requested_model: $Model
- execution_app: codex-exec
- command_shape_without_secrets: codex exec --json --strict-config --ignore-user-config -C <repo> -m $Model -s read-only -c model_reasoning_effort=... -c developer_instructions=<redacted> -o <temp> <prompt>
- input_summary: disposable repo with review-context.json, pr-diff.patch, goal-context-selection.json, role contracts
- limitations: top-level codex exec (not native subagent); read-only requested but OS write impossibility not proven

## Results

"@
    foreach ($item in $results) {
        $rawExists = Test-Path -LiteralPath $item.rawPath
        $metaExists = Test-Path -LiteralPath $item.metaPath
        $record += @"

### $($item.role)
- exit_code: $($item.exitCode)
- raw_exists: $rawExists
- metadata_exists: $metaExists
- output:
``````
$($item.output)
``````
"@
        if ($rawExists) {
            $record += "`n- raw_artifact:`n``````markdown`n$(Get-Content -Raw -LiteralPath $item.rawPath)`n``````n"
        }
    }

    Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8
    Write-Host "Wrote smoke record: $recordPath"
    if ($results | Where-Object { $_.exitCode -ne 0 }) { exit 2 }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $fixture.Root) {
        Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
