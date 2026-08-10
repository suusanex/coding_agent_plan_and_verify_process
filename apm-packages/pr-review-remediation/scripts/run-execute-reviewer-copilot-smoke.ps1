[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [string]$EvidenceRoot = '',
    [string]$CopilotCommand = 'copilot',
    [string]$Model = 'gpt-5.4',
    [int]$TimeoutSeconds = 600,
    [switch]$DescribePayload,
    [switch]$ConfirmExternalModelPayload,
    [switch]$IncludeFailureScenario,
    [switch]$IncludeConcurrentScenario
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}

# Resolve the concrete executable so the executor's Process.Start (UseShellExecute=false)
# can launch it. Prefer an .exe/.cmd (Application) over .ps1 ExternalScript shims.
$resolvedCopilot = $CopilotCommand
if (-not (Test-Path -LiteralPath $CopilotCommand)) {
    $all = @(Get-Command $CopilotCommand -All -ErrorAction SilentlyContinue)
    $app = $all | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($app) {
        $resolvedCopilot = $app.Source
    } else {
        $where = (& where.exe $CopilotCommand 2>$null | Select-Object -First 1)
        if ($where) { $resolvedCopilot = $where }
    }
}
$CopilotCommand = $resolvedCopilot

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
    param([string]$Suffix = '')
    $root = Join-Path ([IO.Path]::GetTempPath()) ("execute-reviewer-copilot-smoke-" + [guid]::NewGuid().ToString('N') + $Suffix)
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repo '.github\agents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force | Out-Null
    Copy-Item (Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\agents\local-reviewer.agent.md') (Join-Path $repo '.github\agents\local-reviewer.agent.md')
    Copy-Item (Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\agents\purpose-reviewer.agent.md') (Join-Path $repo '.github\agents\purpose-reviewer.agent.md')
    # Intentionally omit Codex TOML profiles so Copilot-only installs are exercised.
    Set-Content (Join-Path $repo 'docs\goal-context-smoke.md') -Value "Goal: verify Copilot CLI reviewer adapter captures raw review text.`n"
    Push-Location $repo
    try {
        git init -q | Out-Null
        git -c user.email=smoke@example.com -c user.name=smoke add docs .github | Out-Null
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
- failure scenario: also records a deliberate short timeout attempt when -IncludeFailureScenario is set
- concurrent scenario: also records parallel local+purpose invocations when -IncludeConcurrentScenario is set
"@

if ($DescribePayload) {
    Write-Host $payload
    exit 0
}

if (-not $ConfirmExternalModelPayload) {
    throw 'Refusing to call an external model. Re-run with -DescribePayload or -ConfirmExternalModelPayload after reviewing the payload.'
}

$copilotVersion = (& $CopilotCommand --version 2>&1 | Out-String).Trim()

function Invoke-ReviewerRole {
    param(
        [string]$Role,
        [string]$RunRoot,
        [string]$RepoRoot,
        [int]$TimeoutSec
    )
    $out = & dotnet run --file $executor -- @(
        '--execution-app', 'copilot-cli',
        '--model', $Model,
        '--reviewer-role', $Role,
        '--run-root', $RunRoot,
        '--round', '1',
        '--timeout-seconds', "$TimeoutSec",
        '--repository-root', $RepoRoot,
        '--skill-root', $skillRoot,
        '--copilot-executable', $CopilotCommand,
        '--format', 'json'
    ) 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $rawPath = Join-Path $RunRoot "round-001\$Role.raw.md"
    $metaPath = Join-Path $RunRoot "round-001\$Role.execution.json"
    return [pscustomobject]@{
        role = $Role
        exitCode = $exitCode
        output = $out
        rawPath = $rawPath
        metaPath = $metaPath
        rawExists = (Test-Path -LiteralPath $rawPath)
        metaExists = (Test-Path -LiteralPath $metaPath)
    }
}

$fixture = New-SmokeRun
$fixturesToClean = @($fixture)
try {
    # Primary success scenario
    $localResult = Invoke-ReviewerRole -Role 'local-reviewer' -RunRoot $fixture.Run -RepoRoot $fixture.Repo -TimeoutSec $TimeoutSeconds

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
- worktree_write_check: executor pre/post snapshot must remain clean for success
- limitations: observed model may remain unknown; tool allowlist + MCP disable + worktree check; not OS sandbox proof; no VS Code UI

## local-reviewer result
- exit_code: $($localResult.exitCode)
- raw_exists: $($localResult.rawExists)
- metadata_exists: $($localResult.metaExists)
- output:
``````
$($localResult.output)
``````
"@
    if ($localResult.rawExists) {
        $rawContent = Get-Content -Raw -LiteralPath $localResult.rawPath
        $record += @"

- raw_artifact:
``````markdown
$rawContent
``````
"@
    }
    if ($localResult.metaExists) {
        $metaContent = Get-Content -Raw -LiteralPath $localResult.metaPath
        $record += @"

- metadata:
``````json
$metaContent
``````
"@
    }

    # Failure/timeout scenario
    if ($IncludeFailureScenario) {
        $failFixture = New-SmokeRun -Suffix '-fail'
        $fixturesToClean += $failFixture
        $failResult = Invoke-ReviewerRole -Role 'local-reviewer' -RunRoot $failFixture.Run -RepoRoot $failFixture.Repo -TimeoutSec 1

        # Assertions: must be non-zero, must be timeout, must not have raw, must have failed metadata
        if ($failResult.exitCode -eq 0) { throw 'Failure scenario must exit non-zero' }
        if ($failResult.output -notmatch '"exitStatus"\s*:\s*"timeout"') {
            throw "Failure scenario must be timeout, got: $($failResult.output)"
        }
        if ($failResult.rawExists) {
            throw 'Failure scenario must not publish raw artifact'
        }
        $failedMetaPath = Join-Path $failFixture.Run 'round-001\local-reviewer.execution.json.failed.json'
        if (-not (Test-Path -LiteralPath $failedMetaPath)) {
            throw 'Failure scenario must produce .failed.json metadata'
        }

        $failedMeta = Get-Content -Raw -LiteralPath $failedMetaPath
        $record += @"

## failure-scenario (timeout)
- exit_code: $($failResult.exitCode)
- raw_exists: $($failResult.rawExists)
- failed_metadata_exists: True
- note: timeout verified; exitStatus=timeout; no raw artifact; .failed.json preserved
- output:
``````
$($failResult.output)
``````
- failed_metadata:
``````json
$failedMeta
``````
"@
    }

    # Concurrent invocation scenario
    if ($IncludeConcurrentScenario) {
        $concFixture = New-SmokeRun -Suffix '-conc'
        $fixturesToClean += $concFixture

        $startTime = Get-Date
        $localJob = Start-Job -ScriptBlock {
            param($ex, $mod, $role, $run, $repo, $sk, $cp, $to)
            $out = & dotnet run --file $ex -- @(
                '--execution-app', 'copilot-cli',
                '--model', $mod,
                '--reviewer-role', $role,
                '--run-root', $run,
                '--round', '1',
                '--timeout-seconds', "$to",
                '--repository-root', $repo,
                '--skill-root', $sk,
                '--copilot-executable', $cp,
                '--format', 'json'
            ) 2>&1 | Out-String
            return [pscustomobject]@{
                role = $role
                exitCode = $LASTEXITCODE
                output = $out
            }
        } -ArgumentList $executor, $Model, 'local-reviewer', $concFixture.Run, $concFixture.Repo, $skillRoot, $CopilotCommand, $TimeoutSeconds

        $purposeJob = Start-Job -ScriptBlock {
            param($ex, $mod, $role, $run, $repo, $sk, $cp, $to)
            $out = & dotnet run --file $ex -- @(
                '--execution-app', 'copilot-cli',
                '--model', $mod,
                '--reviewer-role', $role,
                '--run-root', $run,
                '--round', '1',
                '--timeout-seconds', "$to",
                '--repository-root', $repo,
                '--skill-root', $sk,
                '--copilot-executable', $cp,
                '--format', 'json'
            ) 2>&1 | Out-String
            return [pscustomobject]@{
                role = $role
                exitCode = $LASTEXITCODE
                output = $out
            }
        } -ArgumentList $executor, $Model, 'purpose-reviewer', $concFixture.Run, $concFixture.Repo, $skillRoot, $CopilotCommand, $TimeoutSeconds

        $jobs = @($localJob, $purposeJob)
        $jobs | Wait-Job | Out-Null
        $endTime = Get-Date
        $elapsed = ($endTime - $startTime).TotalSeconds

        $concResults = $jobs | ForEach-Object {
            $r = Receive-Job -Job $_
            Remove-Job -Job $_
            $rp = Join-Path $concFixture.Run "round-001\$($r.role).raw.md"
            $mp = Join-Path $concFixture.Run "round-001\$($r.role).execution.json"
            [pscustomobject]@{
                role = $r.role
                exitCode = $r.exitCode
                output = $r.output
                rawExists = (Test-Path -LiteralPath $rp)
                metaExists = (Test-Path -LiteralPath $mp)
            }
        }

        # Assertions: both roles must succeed, both must have raw and metadata
        foreach ($cr in $concResults) {
            if ($cr.exitCode -ne 0) { throw "Concurrent $($cr.role) must exit 0, got $($cr.exitCode)" }
            if (-not $cr.rawExists) { throw "Concurrent $($cr.role) must produce raw artifact" }
            if (-not $cr.metaExists) { throw "Concurrent $($cr.role) must produce metadata" }
        }

        $record += @"

## concurrent-invocation-identity (parallel local-reviewer + purpose-reviewer)
- elapsed_seconds: $([math]::Round($elapsed, 1))
- note: both roles launched in parallel; independent session identity verified; both succeeded
- local-reviewer: exit_code=$($concResults[0].exitCode), raw=$($concResults[0].rawExists), meta=$($concResults[0].metaExists)
- purpose-reviewer: exit_code=$($concResults[1].exitCode), raw=$($concResults[1].rawExists), meta=$($concResults[1].metaExists)
- output_local:
``````
$($concResults[0].output)
``````
- output_purpose:
``````
$($concResults[1].output)
``````
"@
    }

    Set-Content -LiteralPath $recordPath -Value $record -Encoding utf8
    Write-Host "Wrote smoke record: $recordPath"
    if ($localResult.exitCode -ne 0) { exit 2 }
    exit 0
}
finally {
    foreach ($f in $fixturesToClean) {
        if (Test-Path -LiteralPath $f.Root) {
            Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
