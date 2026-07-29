[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$skillRoot = Join-Path $repoRoot 'apm-packages\pr-review-remediation\.apm\skills\goal-context-pr-review'
$manager = Join-Path $skillRoot 'scripts\manage-same-parent-review.cs'
$fakeGhSource = Join-Path $repoRoot 'apm-packages\pr-review-remediation\tests\fixtures\fake-gh.cs'
$validator = Join-Path $repoRoot 'apm-packages\goal-context-authoring\.apm\skills\goal-context-authoring\scripts\validate-goal-context.cs'
$goalContextSource = Join-Path $repoRoot 'tests\pr-review-remediation\PRR-002\fixture\docs\goal-context-direct-review-notification.md'
$failures = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('same-parent-review-' + [guid]::NewGuid().ToString('N'))

function Add-Failure([string]$Message) { $failures.Add($Message) }

function Invoke-Manager {
    param(
        [string[]]$Arguments,
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    $output = & dotnet run --file $manager -- @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($ExpectSuccess -and $exitCode -ne 0) { Add-Failure "manager failed ($exitCode): $output" }
    if (-not $ExpectSuccess -and $exitCode -eq 0) { Add-Failure "manager unexpectedly succeeded: $output" }
    if ($ExpectedPattern -and $output -notmatch $ExpectedPattern) { Add-Failure "manager output did not contain '$ExpectedPattern': $output" }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function New-FixtureRepository([string]$Name, [bool]$IncludeGoalContext = $true) {
    $root = Join-Path $tempRoot $Name
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    if ($IncludeGoalContext) {
        $docs = Join-Path $root 'docs'
        New-Item -ItemType Directory -Path $docs -Force | Out-Null
        Copy-Item -LiteralPath $goalContextSource -Destination (Join-Path $docs 'goal-context-same-parent-review.md')
    }
    return $root
}

function Start-Run([string]$FixtureRoot, [string]$Scenario = 'same-parent-ready') {
    $env:FAKE_GH_SCENARIO = $Scenario
    $env:FAKE_GH_STATE = Join-Path $FixtureRoot 'fake-gh-state.txt'
    $env:FAKE_GH_HEAD_OID = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $result = Invoke-Manager @(
        'start', '--repository-root', $FixtureRoot,
        '--gh-executable', $script:fakeGh,
        '--validator', $validator,
        '--skill-root', $skillRoot,
        '--copilot-timeout-seconds', '3', '--format', 'json'
    )
    if ($result.ExitCode -ne 0) { return $null }
    $json = $result.Output | ConvertFrom-Json
    $runRoot = Join-Path $FixtureRoot $json.runRoot
    if (-not (Test-Path -LiteralPath $runRoot)) { Add-Failure "start did not create run root: $runRoot" }
    return $runRoot
}

function Write-ReviewerRaw([string]$RunRoot, [int]$Round, [bool]$IncludeLocal) {
    $roundRoot = Join-Path $RunRoot ('round-{0:000}' -f $Round)
    if ($IncludeLocal) {
        Set-Content -LiteralPath (Join-Path $roundRoot 'local-reviewer.raw.md') -Value @'
# Local Reviewer

- Verdict: REVIEWED
- Production code changed: No

## Findings

- LR-001: Correct the fixture behavior.
'@
    }
    Set-Content -LiteralPath (Join-Path $roundRoot 'purpose-reviewer.raw.md') -Value @'
# Purpose Reviewer

- Verdict: PURPOSE_REVIEWED
- Production code changed: No

## Findings

- PUR-001: Preserve the selected Goal Context outcome.
'@
}

function Write-Assessment {
    param(
        [string]$RunRoot,
        [int]$Round,
        [string]$HeadOid,
        [string]$FindingState,
        [string]$PriorDisposition = ''
    )
    $roundName = 'round-{0:000}' -f $Round
    [array]$sources = if ($Round -eq 1) {
        @(
            @{ source = 'github-copilot'; artifact = "$roundName/review-context.json"; status = 'Complete' },
            @{ source = 'local-reviewer'; artifact = "$roundName/local-reviewer.raw.md"; status = 'Complete' },
            @{ source = 'purpose-reviewer'; artifact = "$roundName/purpose-reviewer.raw.md"; status = 'Complete' }
        )
    } else {
        @(@{ source = 'purpose-reviewer'; artifact = "$roundName/purpose-reviewer.raw.md"; status = 'Complete' })
    }
    [array]$prior = if ($Round -gt 1) {
        @(@{ trackingId = 'TRK-001'; disposition = $PriorDisposition; evidenceSourceId = 'PUR-001' })
    } else { @() }
    [array]$findings = if ($FindingState) {
        @(@{ trackingId = 'TRK-001'; state = $FindingState; summary = 'Preserve the Goal Context outcome.'; sourceIds = @($(if ($Round -eq 1) { 'LR-001' } else { 'PUR-001' })) })
    } else { @() }
    $assessment = @{
        schemaVersion = 1
        roundNumber = $Round
        reviewedHeadOid = $HeadOid
        productionCodeChangedByReviewer = $false
        mandatorySources = $sources
        priorAssessments = $prior
        findings = $findings
    }
    $path = Join-Path $RunRoot "$roundName/round-assessment.json"
    $assessment | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
    return $path
}

function Get-State([string]$RunRoot) {
    return Get-Content -Raw -LiteralPath (Join-Path $RunRoot 'run-state.json') | ConvertFrom-Json -Depth 100
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $fakePublish = Join-Path $tempRoot 'fake-gh'
    & dotnet publish $fakeGhSource -o $fakePublish | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fake gh publish failed' }
    $script:fakeGh = Join-Path $fakePublish $(if ($IsWindows) { 'fake-gh.exe' } else { 'fake-gh' })
    if (-not (Test-Path -LiteralPath $script:fakeGh)) { throw "fake gh executable missing: $script:fakeGh" }

    $converges = New-FixtureRepository 'converges'
    $runRoot = Start-Run $converges
    if ($runRoot) {
        $state = Get-State $runRoot
        if ($state.status -ne 'Round1Reviewing' -or $state.currentRound -ne 1) { Add-Failure 'start did not enter Round1Reviewing.' }
        if ($state.pullRequest.headOid -ne 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb') { Add-Failure 'start did not bind the current PR head.' }
        if (-not (Test-Path -LiteralPath (Join-Path $runRoot 'run-summary.md'))) { Add-Failure 'start did not create run-summary.md.' }
        Write-ReviewerRaw $runRoot 1 $true
        $assessment1 = Write-Assessment $runRoot 1 $state.pullRequest.headOid 'Active'
        $assessResult = Invoke-Manager @('assess', '--run', $runRoot, '--round', '1', '--assessment', $assessment1, '--format', 'json')
        if ($assessResult.ExitCode -ne 0) { throw "round 1 assessment failed: $($assessResult.Output)" }
        if ((Get-State $runRoot).status -ne 'Remediating') { Add-Failure 'active round 1 did not enter Remediating.' }

        $env:FAKE_GH_HEAD_OID = 'cccccccccccccccccccccccccccccccccccccccc'
        $nextResult = Invoke-Manager @('next-round', '--run', $runRoot, '--gh-executable', $script:fakeGh, '--skill-root', $skillRoot, '--format', 'json')
        if ($nextResult.ExitCode -ne 0) { throw "round 2 setup failed: $($nextResult.Output)" }
        $state = Get-State $runRoot
        if ($state.status -ne 'PurposeReviewing' -or $state.rounds[1].mode -ne 'purpose-only') { Add-Failure 'next-round did not create purpose-only round 2.' }
        Write-ReviewerRaw $runRoot 2 $false
        $assessment2 = Write-Assessment $runRoot 2 $state.pullRequest.headOid '' 'resolved'
        Invoke-Manager @('assess', '--run', $runRoot, '--round', '2', '--assessment', $assessment2, '--format', 'json') | Out-Null
        $state = Get-State $runRoot
        if ($state.status -ne 'Complete') { Add-Failure 'resolved purpose finding did not complete.' }
        if (($state.reviewerExecutions | ForEach-Object role) -join '|' -ne 'local-reviewer|purpose-reviewer|purpose-reviewer') { Add-Failure 'reviewer role/count ledger is incorrect.' }
        Invoke-Manager @('validate', '--run', $runRoot, '--format', 'json') | Out-Null
        $projection = Get-Content -Raw -LiteralPath (Join-Path $runRoot 'terminal-projection.json') | ConvertFrom-Json
        $projectionFields = @($projection.psobject.Properties.Name | Sort-Object)
        if (($projectionFields -join '|') -ne 'observed_status|primary_process|result_uri|schema_version|title') { Add-Failure 'terminal projection field set is not XC-001 safe.' }
        if ($projection.observed_status -ne 'Complete' -or $projection.result_uri -ne 'https://github.com/fixture/goal-context-review/pull/123') { Add-Failure 'terminal projection did not retain terminal status/current PR URI.' }
    }

    foreach ($negative in @(
        @{ Name = 'draft'; Scenario = 'same-parent-draft'; Pattern = 'Draft' },
        @{ Name = 'ambiguous'; Scenario = 'same-parent-ambiguous'; Pattern = 'ambiguous' },
        @{ Name = 'missing-pr'; Scenario = 'same-parent-missing'; Pattern = 'No Ready PR' }
    )) {
        $fixture = New-FixtureRepository $negative.Name
        $env:FAKE_GH_SCENARIO = $negative.Scenario
        $env:FAKE_GH_STATE = Join-Path $fixture 'fake-gh-state.txt'
        $env:FAKE_GH_HEAD_OID = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        Invoke-Manager @('start', '--repository-root', $fixture, '--gh-executable', $script:fakeGh, '--validator', $validator, '--skill-root', $skillRoot, '--format', 'json') $false $negative.Pattern | Out-Null
    }

    $noGoal = New-FixtureRepository 'no-goal' $false
    $env:FAKE_GH_SCENARIO = 'same-parent-ready'
    $env:FAKE_GH_STATE = Join-Path $noGoal 'fake-gh-state.txt'
    Invoke-Manager @('start', '--repository-root', $noGoal, '--gh-executable', $script:fakeGh, '--validator', $validator, '--skill-root', $skillRoot, '--format', 'json') $false 'No goal-context' | Out-Null

    $stale = New-FixtureRepository 'stale'
    $staleRun = Start-Run $stale
    if ($staleRun) {
        $state = Get-State $staleRun
        Write-ReviewerRaw $staleRun 1 $true
        $assessment = Write-Assessment $staleRun 1 $state.pullRequest.headOid 'Active'
        Invoke-Manager @('assess', '--run', $staleRun, '--round', '1', '--assessment', $assessment) | Out-Null
        Invoke-Manager @('next-round', '--run', $staleRun, '--gh-executable', $script:fakeGh, '--skill-root', $skillRoot, '--format', 'json') $false 'head has not changed' | Out-Null
        if ((Get-State $staleRun).status -ne 'Blocked') { Add-Failure 'stale head did not persist Blocked terminal state.' }
    }

    $roundLimit = New-FixtureRepository 'round-limit'
    $limitRun = Start-Run $roundLimit
    if ($limitRun) {
        $heads = @(
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            'cccccccccccccccccccccccccccccccccccccccc',
            'dddddddddddddddddddddddddddddddddddddddd'
        )
        for ($round = 1; $round -le 3; $round++) {
            $state = Get-State $limitRun
            Write-ReviewerRaw $limitRun $round ($round -eq 1)
            $assessment = Write-Assessment $limitRun $round $state.pullRequest.headOid 'Active' $(if ($round -eq 1) { '' } else { 'persistent' })
            Invoke-Manager @('assess', '--run', $limitRun, '--round', $round.ToString(), '--assessment', $assessment) | Out-Null
            if ($round -lt 3) {
                $env:FAKE_GH_HEAD_OID = $heads[$round]
                Invoke-Manager @('next-round', '--run', $limitRun, '--gh-executable', $script:fakeGh, '--skill-root', $skillRoot) | Out-Null
            }
        }
        if ((Get-State $limitRun).status -ne 'HumanDecisionRequired') { Add-Failure 'active round 3 did not stop with HumanDecisionRequired.' }
        Invoke-Manager @('next-round', '--run', $limitRun, '--gh-executable', $script:fakeGh, '--skill-root', $skillRoot) $false 'requires Remediating|terminal' | Out-Null
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    Remove-Item Env:FAKE_GH_SCENARIO -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GH_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GH_HEAD_OID -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Error ("Same-parent review validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Same-parent review validation: PASS'
