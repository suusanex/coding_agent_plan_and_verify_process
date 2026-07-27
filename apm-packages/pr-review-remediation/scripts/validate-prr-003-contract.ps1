[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$managerPath = Join-Path $repoRoot 'apm-packages\pr-review-remediation\.apm\skills\goal-context-pr-review\scripts\manage-review-cycle.cs'
$fixturePath = Join-Path $repoRoot 'tests\pr-review-remediation\PRR-003\scenarios.json'
$fixture = Get-Content -Raw -LiteralPath $fixturePath | ConvertFrom-Json -Depth 100
$failures = [System.Collections.Generic.List[string]]::new()
$repository = [string]$fixture.repository
$pullRequest = [int]$fixture.pullRequest
$baseOid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$goalContextPath = 'docs/goal-context-multi-project-ai-development-notification-and-purpose-review.md'
$goalContextSha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
$prUrl = "https://github.com/$repository/pull/$pullRequest"
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Add-Failure([string]$Message) { $failures.Add($Message) }

function Get-NormalizedSha256([string]$Path) {
    $text = [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Invoke-Manager([string[]]$Arguments, [string]$Description, [bool]$ExpectSuccess = $true, [string]$ExpectedPattern = '') {
    $output = & dotnet $script:managerDll @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($ExpectSuccess -and $exitCode -ne 0) {
        Add-Failure "$Description failed with exit code ${exitCode}: $output"
    }
    elseif (-not $ExpectSuccess -and $exitCode -eq 0) {
        Add-Failure "$Description unexpectedly succeeded"
    }
    if ($ExpectedPattern -and $output -notmatch $ExpectedPattern) {
        Add-Failure "$Description did not report expected pattern '$ExpectedPattern': $output"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Start-Round {
    param(
        [string]$CyclePath,
        [string]$HeadOid,
        [string]$StartedAt,
        [string]$AdaptiveResult = '',
        [int]$OverrideMaximum = 0,
        [switch]$IncompleteOverride,
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    $arguments = @(
        'start', '--cycle', $CyclePath, '--repository', $repository, '--pr', [string]$pullRequest,
        '--goal-context-path', $goalContextPath, '--goal-context-sha', $goalContextSha,
        '--base-oid', $baseOid, '--head-oid', $HeadOid, '--started-at', $StartedAt, '--format', 'json'
    )
    if ($AdaptiveResult) { $arguments += @('--adaptive-result-reference', $AdaptiveResult) }
    if ($OverrideMaximum -gt 0) {
        $arguments += @('--override-maximum-rounds', [string]$OverrideMaximum)
        if (-not $IncompleteOverride) {
            $arguments += @(
                '--override-approved-by', 'fixture-human', '--override-approved-at', $StartedAt,
                '--override-reason', 'Explicitly approved one additional diagnostic round.'
            )
        }
    }
    Invoke-Manager $arguments "start round at head $HeadOid" $ExpectSuccess $ExpectedPattern | Out-Null
}

function New-Delta([string]$TrackingId, [string]$State, [string[]]$FindingIds, [string[]]$SourceIds) {
    return [ordered]@{
        trackingId = $TrackingId
        state = $State
        findingIds = @($FindingIds)
        sourceIds = @($SourceIds)
    }
}

function Write-RoundResult {
    param(
        [string]$CycleRoot,
        [int]$RoundNumber,
        [string]$HeadOid,
        [string]$CompletedAt,
        [string]$Verdict,
        [object[]]$FindingDelta,
        [bool]$IncludePlan,
        [string]$NotificationUri = $prUrl
    )
    $roundName = 'round-{0:000}' -f $RoundNumber
    $roundRoot = Join-Path $CycleRoot $roundName
    $roleFiles = [ordered]@{
        'review-context' = 'review-context.json'
        'remote-patch' = 'pr-diff.patch'
        'goal-context-selection' = 'goal-context-selection.json'
        'local-findings' = 'local-review-findings.md'
        'purpose-findings' = 'purpose-review-findings.md'
        'review-result' = 'review-result.md'
        'completion-notification' = 'completion-notification.txt'
    }
    if ($IncludePlan) { $roleFiles['review-plan'] = 'review-plan.md' }

    $artifacts = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $roleFiles.GetEnumerator()) {
        $fullPath = Join-Path $roundRoot $entry.Value
        $content = if ($entry.Key -eq 'completion-notification') {
            "{`"observed_status`":`"$Verdict`",`"title`":`"Goal Context review $roundName completed`",`"result_uri`":`"$NotificationUri`"}`n"
        } else {
            "$($entry.Key) evidence for $roundName at $HeadOid`n"
        }
        [System.IO.File]::WriteAllText($fullPath, $content, $utf8)
        $artifacts.Add([ordered]@{
            role = $entry.Key
            path = "$roundName/$($entry.Value)"
            normalizedSha256 = Get-NormalizedSha256 $fullPath
        })
    }

    $result = [ordered]@{
        schemaVersion = 1
        roundNumber = $RoundNumber
        baseOid = $baseOid
        headOid = $HeadOid
        completedAt = $CompletedAt
        verdict = $Verdict
        humanDecisionReason = $null
        blockedReason = $null
        artifacts = @($artifacts)
        notification = [ordered]@{ roundNumber = $RoundNumber; observedStatus = $Verdict; resultUri = $NotificationUri }
        findingDelta = @($FindingDelta)
        sourceCoverage = @(
            @($FindingDelta | ForEach-Object {
                $trackingId = $_.trackingId
                @($_.sourceIds | ForEach-Object {
                    [ordered]@{ sourceId = $_; disposition = 'finding'; trackingIds = @($trackingId); reason = $null }
                })
            })
            [ordered]@{ sourceId = "check:$roundName"; disposition = 'noAction'; trackingIds = @(); reason = 'Synthetic check completed without an actionable finding.' }
        )
    }
    $resultPath = Join-Path $roundRoot 'round-result.json'
    $json = $result | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($resultPath, $json.Replace("`r`n", "`n") + "`n", $utf8)
    return $resultPath
}

function Complete-Round {
    param(
        [string]$CyclePath,
        [string]$ResultPath,
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    Invoke-Manager @('complete', '--cycle', $CyclePath, '--round-result', $ResultPath, '--format', 'json') 'complete round' $ExpectSuccess $ExpectedPattern | Out-Null
}

function Assert-CycleVerdicts([string]$CyclePath, [string[]]$Expected, [string]$Description) {
    $cycle = Get-Content -Raw -LiteralPath $CyclePath | ConvertFrom-Json -Depth 100
    $observed = @($cycle.rounds | ForEach-Object { $_.verdict })
    if (($observed -join '|') -ne ($Expected -join '|')) {
        Add-Failure "$Description verdicts mismatch: expected $($Expected -join ', '), observed $($observed -join ', ')"
    }
}

if ($fixture.schemaVersion -ne 1 -or $fixture.fixtureId -ne 'PRR-003' -or $fixture.externalModelExecution -ne $false) {
    throw 'PRR-003 fixture metadata is invalid.'
}
if (($fixture.findingStates -join '|') -ne 'new|persistent|resolved|reopened' -or $fixture.defaultMaximumRounds -ne 3) {
    throw 'PRR-003 fixture state vocabulary or default maximum drifted.'
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('prr-003-' + [guid]::NewGuid().ToString('N'))
$publishRoot = Join-Path $tempRoot 'manager'
New-Item -ItemType Directory -Path $publishRoot -Force | Out-Null
try {
    $publish = & dotnet publish $managerPath --output $publishRoot --disable-build-servers 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "manage-review-cycle publish failed: $publish" }
    $script:managerDll = Join-Path $publishRoot 'manage-review-cycle.dll'
    if (-not (Test-Path -LiteralPath $script:managerDll)) { throw "Published manager DLL is missing: $script:managerDll" }
    Invoke-Manager @('--help') 'manager help' | Out-Null

    # Convergence: actionable rounds require separate Adaptive references; the final round creates no empty plan.
    $convergenceRoot = Join-Path $tempRoot 'convergence'
    $convergenceCycle = Join-Path $convergenceRoot 'review-cycle.json'
    $head1 = '1111111111111111111111111111111111111111'
    $head2 = '2222222222222222222222222222222222222222'
    $head3 = '3333333333333333333333333333333333333333'
    Start-Round $convergenceCycle $head1 '2026-01-01T00:00:00Z'
    $r1 = Write-RoundResult $convergenceRoot 1 $head1 '2026-01-01T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-A' 'new' @('LR-001') @('review:1'))
    ) $true
    Complete-Round $convergenceCycle $r1
    Start-Round -CyclePath $convergenceCycle -HeadOid $head1 -StartedAt '2026-01-01T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ExpectSuccess $false -ExpectedPattern 'already reviewed'
    Start-Round -CyclePath $convergenceCycle -HeadOid $head2 -StartedAt '2026-01-01T00:02:00Z' -ExpectSuccess $false -ExpectedPattern 'requires --adaptive-result-reference'
    $identityArguments = @(
        'start', '--cycle', $convergenceCycle, '--repository', 'fixture/wrong-repository', '--pr', [string]$pullRequest,
        '--goal-context-path', $goalContextPath, '--goal-context-sha', $goalContextSha,
        '--base-oid', $baseOid, '--head-oid', $head2, '--started-at', '2026-01-01T00:02:00Z',
        '--adaptive-result-reference', 'adaptive/round-001/result.md', '--format', 'json'
    )
    Invoke-Manager $identityArguments 'repository identity drift' $false 'repository mismatch' | Out-Null
    $identityArguments[8] = 'docs/wrong-goal-context.md'
    $identityArguments[4] = $repository
    Invoke-Manager $identityArguments 'Goal Context path drift' $false 'Goal Context path mismatch' | Out-Null
    $identityArguments[8] = $goalContextPath
    $identityArguments[10] = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
    Invoke-Manager $identityArguments 'Goal Context hash drift' $false 'Goal Context SHA-256 mismatch' | Out-Null
    $preexistingRound = Join-Path $convergenceRoot 'round-002'
    New-Item -ItemType Directory -Path $preexistingRound | Out-Null
    Start-Round -CyclePath $convergenceCycle -HeadOid $head2 -StartedAt '2026-01-01T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ExpectSuccess $false -ExpectedPattern 'will not be overwritten'
    Remove-Item -LiteralPath $preexistingRound
    Start-Round $convergenceCycle $head2 '2026-01-01T00:03:00Z' 'adaptive/round-001/result.md'
    $r2 = Write-RoundResult $convergenceRoot 2 $head2 '2026-01-01T00:04:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-A' 'persistent' @('LR-002') @('review:2')),
        (New-Delta 'TRK-B' 'new' @('PUR-002') @('comment:2'))
    ) $true
    Complete-Round $convergenceCycle $r2
    Start-Round $convergenceCycle $head3 '2026-01-01T00:05:00Z' 'adaptive/round-002/result.md'
    $r3 = Write-RoundResult $convergenceRoot 3 $head3 '2026-01-01T00:06:00Z' 'REVIEW_COMPLETE' @(
        (New-Delta 'TRK-A' 'resolved' @() @('review:3')),
        (New-Delta 'TRK-B' 'resolved' @() @('comment:3'))
    ) $false
    Complete-Round $convergenceCycle $r3
    Invoke-Manager @('validate', '--cycle', $convergenceCycle, '--format', 'json') 'validate converged cycle' | Out-Null
    $expectedConvergence = @($fixture.scenarios | Where-Object id -eq 'convergence').expectedVerdicts
    Assert-CycleVerdicts $convergenceCycle $expectedConvergence 'convergence'
    foreach ($round in 1..3) {
        if (-not (Test-Path -LiteralPath (Join-Path $convergenceRoot ('round-{0:000}' -f $round)))) {
            Add-Failure "Convergence artifact directory is missing for round $round"
        }
    }

    # Historical evidence is immutable after completion.
    $tamperRoot = Join-Path $tempRoot 'tampered'
    Copy-Item -LiteralPath $convergenceRoot -Destination $tamperRoot -Recurse
    [System.IO.File]::AppendAllText((Join-Path $tamperRoot 'round-001/review-context.json'), "tamper`n", $utf8)
    Invoke-Manager @('validate', '--cycle', (Join-Path $tamperRoot 'review-cycle.json'), '--format', 'json') 'historical artifact mutation' $false 'hash.*mismatch' | Out-Null

    # Round limit and explicit human override.
    $limitRoot = Join-Path $tempRoot 'limit'
    $limitCycle = Join-Path $limitRoot 'review-cycle.json'
    $limitHeads = @(
        '4444444444444444444444444444444444444444',
        '5555555555555555555555555555555555555555',
        '6666666666666666666666666666666666666666',
        '7777777777777777777777777777777777777777'
    )
    for ($round = 1; $round -le 3; $round++) {
        $adaptive = if ($round -eq 1) { '' } else { "adaptive/round-$('{0:000}' -f ($round - 1))/result.md" }
        Start-Round $limitCycle $limitHeads[$round - 1] "2026-02-01T00:0$($round * 2):00Z" $adaptive
        $state = if ($round -eq 1) { 'new' } else { 'persistent' }
        $expectedVerdict = if ($round -eq 3) { 'HUMAN_DECISION_REQUIRED' } else { 'READY_FOR_ADAPTIVE_IMPLEMENTATION' }
        $wrongVerdict = if ($round -eq 3) { 'READY_FOR_ADAPTIVE_IMPLEMENTATION' } else { $expectedVerdict }
        $result = Write-RoundResult $limitRoot $round $limitHeads[$round - 1] "2026-02-01T00:0$($round * 2 + 1):00Z" $wrongVerdict @(
            (New-Delta 'TRK-LIMIT' $state @("LR-10$round") @("review:limit:$round"))
        ) $true
        if ($round -eq 3) {
            Complete-Round $limitCycle $result $false 'round-result verdict mismatch'
            $result = Write-RoundResult $limitRoot $round $limitHeads[$round - 1] '2026-02-01T00:07:00Z' $expectedVerdict @(
                (New-Delta 'TRK-LIMIT' $state @('LR-103') @('review:limit:3'))
            ) $true
        }
        Complete-Round $limitCycle $result
    }
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ExpectSuccess $false -ExpectedPattern 'exceeds effective maximum'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -OverrideMaximum 4 -IncompleteOverride -ExpectSuccess $false -ExpectedPattern 'All maximum-round override fields'
    Start-Round $limitCycle $limitHeads[3] '2026-02-01T00:08:00Z' 'adaptive/round-003/result.md' 4
    $r4 = Write-RoundResult $limitRoot 4 $limitHeads[3] '2026-02-01T00:09:00Z' 'REVIEW_COMPLETE' @(
        (New-Delta 'TRK-LIMIT' 'resolved' @() @('review:limit:4'))
    ) $false
    Complete-Round $limitCycle $r4
    $expectedLimit = @($fixture.scenarios | Where-Object id -eq 'round-limit-and-override').expectedVerdicts
    Assert-CycleVerdicts $limitCycle $expectedLimit 'round limit and override'
    $limit = Get-Content -Raw -LiteralPath $limitCycle | ConvertFrom-Json -Depth 100
    if ($limit.effectiveMaximumRounds -ne 4 -or $limit.overrides.Count -ne 1 -or $limit.overrides[0].approvedBy -ne 'fixture-human') {
        Add-Failure 'Round 4 override evidence is incomplete.'
    }

    # A resolved finding can reopen while another active finding keeps the cycle open.
    $reopenRoot = Join-Path $tempRoot 'reopened'
    $reopenCycle = Join-Path $reopenRoot 'review-cycle.json'
    $reopenHeads = @('8888888888888888888888888888888888888888', '9999999999999999999999999999999999999999', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
    Start-Round $reopenCycle $reopenHeads[0] '2026-03-01T00:00:00Z'
    Complete-Round $reopenCycle (Write-RoundResult $reopenRoot 1 $reopenHeads[0] '2026-03-01T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-REOPEN' 'new' @('LR-201') @('review:reopen:1')),
        (New-Delta 'TRK-KEEP' 'new' @('PUR-201') @('comment:keep:1'))
    ) $true)
    Start-Round $reopenCycle $reopenHeads[1] '2026-03-01T00:02:00Z' 'adaptive/round-001/result.md'
    Complete-Round $reopenCycle (Write-RoundResult $reopenRoot 2 $reopenHeads[1] '2026-03-01T00:03:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-REOPEN' 'resolved' @() @('review:reopen:2')),
        (New-Delta 'TRK-KEEP' 'persistent' @('PUR-202') @('comment:keep:2'))
    ) $true)
    Start-Round $reopenCycle $reopenHeads[2] '2026-03-01T00:04:00Z' 'adaptive/round-002/result.md'
    Complete-Round $reopenCycle (Write-RoundResult $reopenRoot 3 $reopenHeads[2] '2026-03-01T00:05:00Z' 'HUMAN_DECISION_REQUIRED' @(
        (New-Delta 'TRK-REOPEN' 'reopened' @('LR-203') @('review:reopen:3')),
        (New-Delta 'TRK-KEEP' 'resolved' @() @('comment:keep:3'))
    ) $true)
    $reopen = Get-Content -Raw -LiteralPath $reopenCycle | ConvertFrom-Json -Depth 100
    $reopenStates = @($reopen.findingLedger | Where-Object trackingId -eq 'TRK-REOPEN').history.state
    $expectedReopen = @($fixture.scenarios | Where-Object id -eq 'reopened').expectedStates
    if (($reopenStates -join '|') -ne ($expectedReopen -join '|')) { Add-Failure 'Reopened finding history mismatch.' }

    # Negative finding, artifact-role, and notification contracts.
    $negativeRoot = Join-Path $tempRoot 'negative-persistent'
    $negativeCycle = Join-Path $negativeRoot 'review-cycle.json'
    Start-Round $negativeCycle 'cccccccccccccccccccccccccccccccccccccccc' '2026-04-01T00:00:00Z'
    $negativeResult = Write-RoundResult $negativeRoot 1 'cccccccccccccccccccccccccccccccccccccccc' '2026-04-01T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-UNKNOWN' 'persistent' @('LR-301') @('review:negative:1'))
    ) $true
    Complete-Round $negativeCycle $negativeResult $false 'Round 1 finding states must all be new'

    $noPlanRoot = Join-Path $tempRoot 'negative-no-plan'
    $noPlanCycle = Join-Path $noPlanRoot 'review-cycle.json'
    Start-Round $noPlanCycle 'dddddddddddddddddddddddddddddddddddddddd' '2026-04-02T00:00:00Z'
    $noPlanResult = Write-RoundResult $noPlanRoot 1 'dddddddddddddddddddddddddddddddddddddddd' '2026-04-02T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-NOPLAN' 'new' @('LR-302') @('review:negative:2'))
    ) $false
    $wrongHead = Get-Content -Raw -LiteralPath $noPlanResult | ConvertFrom-Json -Depth 100
    $wrongHead.headOid = 'dcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdc'
    [System.IO.File]::WriteAllText($noPlanResult, (($wrongHead | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Complete-Round $noPlanCycle $noPlanResult $false 'round-result head OID mismatch'
    $noPlanResult = Write-RoundResult $noPlanRoot 1 'dddddddddddddddddddddddddddddddddddddddd' '2026-04-02T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-NOPLAN' 'new' @('LR-302') @('review:negative:2'))
    ) $false
    Complete-Round $noPlanCycle $noPlanResult $false 'require a review-plan'

    $emptyPlanRoot = Join-Path $tempRoot 'negative-empty-plan'
    $emptyPlanCycle = Join-Path $emptyPlanRoot 'review-cycle.json'
    Start-Round $emptyPlanCycle 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' '2026-04-03T00:00:00Z'
    $emptyPlanResult = Write-RoundResult $emptyPlanRoot 1 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' '2026-04-03T00:01:00Z' 'REVIEW_COMPLETE' @() $true
    Complete-Round $emptyPlanCycle $emptyPlanResult $false 'must not include an Adaptive review-plan'

    $coverageRoot = Join-Path $tempRoot 'negative-coverage'
    $coverageCycle = Join-Path $coverageRoot 'review-cycle.json'
    Start-Round $coverageCycle 'edededededededededededededededededededed' '2026-04-03T01:00:00Z'
    $coverageResult = Write-RoundResult $coverageRoot 1 'edededededededededededededededededededed' '2026-04-03T01:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-COVERAGE' 'new' @('LR-306') @('review:coverage:1'))
    ) $true
    $coverageJson = Get-Content -Raw -LiteralPath $coverageResult | ConvertFrom-Json -Depth 100
    $coverageJson.sourceCoverage = @($coverageJson.sourceCoverage | Where-Object disposition -eq 'noAction')
    [System.IO.File]::WriteAllText($coverageResult, (($coverageJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Complete-Round $coverageCycle $coverageResult $false 'missing source coverage'

    $invalidReopenRoot = Join-Path $tempRoot 'negative-reopened'
    $invalidReopenCycle = Join-Path $invalidReopenRoot 'review-cycle.json'
    Start-Round $invalidReopenCycle 'adadadadadadadadadadadadadadadadadadadad' '2026-04-03T02:00:00Z'
    Complete-Round $invalidReopenCycle (Write-RoundResult $invalidReopenRoot 1 'adadadadadadadadadadadadadadadadadadadad' '2026-04-03T02:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-BAD-REOPEN' 'new' @('LR-307') @('review:reopen-negative:1'))
    ) $true)
    Start-Round $invalidReopenCycle 'aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae' '2026-04-03T02:02:00Z' 'adaptive/round-001/result.md'
    $invalidReopenResult = Write-RoundResult $invalidReopenRoot 2 'aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae' '2026-04-03T02:03:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-BAD-REOPEN' 'reopened' @('LR-308') @('review:reopen-negative:2'))
    ) $true
    Complete-Round $invalidReopenCycle $invalidReopenResult $false 'reopened only after resolved'

    $notificationRoot = Join-Path $tempRoot 'negative-notification'
    $notificationCycle = Join-Path $notificationRoot 'review-cycle.json'
    Start-Round $notificationCycle 'ffffffffffffffffffffffffffffffffffffffff' '2026-04-04T00:00:00Z'
    $notificationResult = Write-RoundResult $notificationRoot 1 'ffffffffffffffffffffffffffffffffffffffff' '2026-04-04T00:01:00Z' 'REVIEW_COMPLETE' @() $false 'https://github.com/fixture/goal-context-multi-round/pull/999'
    Complete-Round $notificationCycle $notificationResult $false 'link directly to the target PR'

    $notificationStatusRoot = Join-Path $tempRoot 'negative-notification-status'
    $notificationStatusCycle = Join-Path $notificationStatusRoot 'review-cycle.json'
    Start-Round $notificationStatusCycle 'fafafafafafafafafafafafafafafafafafafafa' '2026-04-04T01:00:00Z'
    $notificationStatusResult = Write-RoundResult $notificationStatusRoot 1 'fafafafafafafafafafafafafafafafafafafafa' '2026-04-04T01:01:00Z' 'REVIEW_COMPLETE' @() $false
    $notificationStatusJson = Get-Content -Raw -LiteralPath $notificationStatusResult | ConvertFrom-Json -Depth 100
    $notificationStatusJson.notification.observedStatus = 'READY_FOR_ADAPTIVE_IMPLEMENTATION'
    [System.IO.File]::WriteAllText($notificationStatusResult, (($notificationStatusJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Complete-Round $notificationStatusCycle $notificationStatusResult $false 'notification observed status mismatch'

    # An active finding from the prior round cannot silently disappear.
    $missingRoot = Join-Path $tempRoot 'negative-missing'
    $missingCycle = Join-Path $missingRoot 'review-cycle.json'
    Start-Round $missingCycle 'abababababababababababababababababababab' '2026-04-05T00:00:00Z'
    Complete-Round $missingCycle (Write-RoundResult $missingRoot 1 'abababababababababababababababababababab' '2026-04-05T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-MISSING' 'new' @('LR-303') @('review:negative:3')),
        (New-Delta 'TRK-PRESENT' 'new' @('LR-304') @('review:negative:4'))
    ) $true)
    Start-Round $missingCycle 'acacacacacacacacacacacacacacacacacacacac' '2026-04-05T00:02:00Z' 'adaptive/round-001/result.md'
    $missingResult = Write-RoundResult $missingRoot 2 'acacacacacacacacacacacacacacacacacacacac' '2026-04-05T00:03:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-PRESENT' 'persistent' @('LR-305') @('review:negative:5'))
    ) $true
    Complete-Round $missingCycle $missingResult $false 'missing persistent/resolved mapping'

    $observedMutations = @($fixture.negativeMutations)
    foreach ($required in @('duplicate-head', 'missing-adaptive-result-reference', 'identity-drift', 'existing-round-directory', 'historical-artifact-hash', 'unknown-persistent-finding', 'missing-active-finding-mapping', 'round-limit-verdict', 'incomplete-override', 'actionable-without-plan', 'review-complete-with-plan', 'missing-source-coverage', 'invalid-reopened-transition', 'round-result-head-identity', 'notification-status', 'notification-pr')) {
        if ($required -notin $observedMutations) { Add-Failure "Fixture negative mutation is missing: $required" }
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        $resolved = [System.IO.Path]::GetFullPath($tempRoot)
        $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if (-not $resolved.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe PRR-003 temp path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

$global:LASTEXITCODE = 0
if ($failures.Count -gt 0) {
    Write-Error ("PRR-003 validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'PRR-003 deterministic multi-round replay: PASS'
