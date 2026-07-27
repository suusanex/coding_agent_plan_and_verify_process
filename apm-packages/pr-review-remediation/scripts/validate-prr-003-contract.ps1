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
        throw "$Description failed with exit code ${exitCode}: $output"
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
        [string]$ResolveDecision = '',
        [switch]$IncompleteDecision,
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    $arguments = @(
        'start', '--cycle', $CyclePath, '--repository', $repository, '--pr', [string]$pullRequest,
        '--goal-context-path', $goalContextPath, '--goal-context-sha', $goalContextSha,
        '--base-oid', $baseOid, '--head-oid', $HeadOid, '--started-at', $StartedAt, '--format', 'json'
    )
    if ($AdaptiveResult) { $arguments += @('--adaptive-result-reference', $AdaptiveResult) }
    if ($ResolveDecision) {
        $arguments += @('--resolve-decision', $ResolveDecision)
        if (-not $IncompleteDecision) {
            $arguments += @(
                '--decision-resolution', 'Continue after explicit human review.',
                '--decision-approved-by', 'fixture-human', '--decision-approved-at', $StartedAt
            )
        }
    }
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
        [string]$NotificationUri = $prUrl,
        [string]$HumanDecisionReason = ''
    )
    $roundName = 'round-{0:000}' -f $RoundNumber
    $roundRoot = Join-Path $CycleRoot $roundName
    $roleFiles = [ordered]@{
        'review-context' = 'review-context.json'
        'remote-patch' = 'pr-diff.patch'
        'goal-context-selection' = 'goal-context-selection.json'
        'local-findings' = 'local-review-findings.md'
        'purpose-findings' = 'purpose-review-findings.md'
        'review-result' = 'review-result.json'
        'completion-notification' = 'completion-notification.txt'
    }
    if ($IncludePlan) { $roleFiles['review-plan'] = 'review-plan.md' }

    $contextSourceIds = @($FindingDelta | ForEach-Object { $_.sourceIds } | Select-Object -Unique)
    $coverageBySource = [ordered]@{}
    foreach ($delta in $FindingDelta) {
        foreach ($sourceId in @($delta.sourceIds) + @($delta.findingIds)) {
            if (-not $coverageBySource.Contains($sourceId)) {
                $coverageBySource[$sourceId] = [System.Collections.Generic.List[string]]::new()
            }
            if (-not $coverageBySource[$sourceId].Contains([string]$delta.trackingId)) {
                $coverageBySource[$sourceId].Add([string]$delta.trackingId)
            }
        }
    }
    $sourceCoverage = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $coverageBySource.GetEnumerator()) {
        $sourceCoverage.Add([ordered]@{ sourceId = $entry.Key; disposition = 'finding'; trackingIds = @($entry.Value); reason = $null })
    }
    $checkSourceId = "check:$roundName"
    $sourceCoverage.Add([ordered]@{ sourceId = $checkSourceId; disposition = 'noAction'; trackingIds = @(); reason = 'Synthetic check completed without an actionable finding.' })

    $reviewContext = [ordered]@{
        schemaVersion = '1.0'
        target = [ordered]@{ repository = $repository; pullRequest = $pullRequest; baseRefOid = $baseOid; headRefOid = $HeadOid }
        artifacts = [ordered]@{ remotePatch = 'pr-diff.patch' }
        sources = [ordered]@{
            pullRequest = [ordered]@{ number = $pullRequest; baseRefOid = $baseOid; headRefOid = $HeadOid }
            reviews = @()
            issueComments = @($contextSourceIds | ForEach-Object -Begin { $id = 0 } -Process { $id++; [ordered]@{ id = $id; sourceId = $_ } })
            inlineComments = @()
            checks = @([ordered]@{ id = 9000 + $RoundNumber; sourceId = $checkSourceId; status = 'COMPLETED'; conclusion = 'SUCCESS' })
        }
    }
    $reviewContextPath = Join-Path $roundRoot $roleFiles['review-context']
    [System.IO.File]::WriteAllText($reviewContextPath, (($reviewContext | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n"), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['remote-patch']), "diff --git a/fixture.txt b/fixture.txt`n# $roundName $HeadOid`n", $utf8)

    $selection = [ordered]@{ schemaVersion = 2; selectionStatus = 'SELECTED'; selectedPath = $goalContextPath; validation = 'PASS'; contentSha256 = $goalContextSha }
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['goal-context-selection']), (($selection | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"), $utf8)

    $localIds = @($FindingDelta | ForEach-Object { $_.findingIds } | Where-Object { $_ -match '^LR-\d+$' } | Select-Object -Unique)
    $localRows = if ($localIds.Count -eq 0) { '| N/A | N/A | N/A | No local actionable finding. | N/A | N/A | N/A |' } else { @($localIds | ForEach-Object { "| $_ | P1 | fixture | Synthetic local finding. | fixture | fixture | fixture |" }) -join "`n" }
    $localContent = @"
# Local Review Findings

## Verdict

- Verdict: REVIEWED
- Production code changed: No

## PR Identity

- Repository: $repository
- PR: $pullRequest
- Base branch / OID: main / $baseOid
- Head branch / OID: feature / $HeadOid

## Findings

| Finding ID | Severity | Location | Summary | Evidence | Risk | Suggested remediation |
| --- | --- | --- | --- | --- | --- | --- |
$localRows
"@
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['local-findings']), $localContent.Replace("`r`n", "`n") + "`n", $utf8)

    $purposeIds = @($FindingDelta | ForEach-Object { $_.findingIds } | Where-Object { $_ -match '^PUR-\d+$' } | Select-Object -Unique)
    $purposeRows = if ($purposeIds.Count -eq 0) { '| N/A | N/A | No purpose actionable finding. | N/A | N/A | N/A |' } else { @($purposeIds | ForEach-Object { "| $_ | Desired outcome | Synthetic purpose finding. | fixture | fixture | fixture |" }) -join "`n" }
    $purposeContent = @"
# Purpose Review Findings

## Verdict

- Verdict: PURPOSE_REVIEWED
- Production code changed: No

## PR and Goal Context Identity

- Repository: $repository
- PR: $pullRequest
- Base branch / OID: main / $baseOid
- Head branch / OID: feature / $HeadOid
- Goal Context: $goalContextPath
- Goal Context SHA-256: $goalContextSha

## Findings

| ID | Goal Context section | Summary | PR evidence | Purpose risk | Suggested outcome |
| --- | --- | --- | --- | --- | --- |
$purposeRows
"@
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['purpose-findings']), $purposeContent.Replace("`r`n", "`n") + "`n", $utf8)

    if ($IncludePlan) {
        $activeDelta = @($FindingDelta | Where-Object { $_.state -in @('new', 'persistent', 'reopened') })
        $orderedRows = [System.Collections.Generic.List[string]]::new()
        $scopeLines = [System.Collections.Generic.List[string]]::new()
        $acceptanceLines = [System.Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt $activeDelta.Count; $index++) {
            $number = $index + 1
            $scopeId = 'SI-{0:000}' -f $number
            $acceptanceId = 'AC-{0:000}' -f $number
            $findingIds = @($activeDelta[$index].findingIds) -join ', '
            $orderedRows.Add("| $number | $scopeId | $acceptanceId | $findingIds | Remediate $($activeDelta[$index].trackingId). | fixture artifact | Finding is resolved. | Contract replay |")
            $scopeLines.Add("    - ${scopeId}: Remediate $($activeDelta[$index].trackingId).")
            $acceptanceLines.Add("    - ${acceptanceId}: Verify $($activeDelta[$index].trackingId) is resolved.")
        }
        $planReference = "$roundName/review-plan.md"
        $planContent = @"
# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: $Verdict
- Production code changed: No

## PR Identity

- Repository: $repository
- PR: $pullRequest
- Base branch / OID: main / $baseOid
- Head branch / OID: feature / $HeadOid

## Goal Context Boundary

- Selected Goal Context: $goalContextPath
- Goal Context SHA-256: $goalContextSha

## Ordered Remediation Plan

| Step | Scope ID | Acceptance ID | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
$($orderedRows -join "`n")

## Implementation Intent

``````yaml
implementation_intent:
  goal: Resolve the actionable findings recorded for $roundName.
  scope:
$($scopeLines -join "`n")
  non_goals:
    - Automatic Adaptive startup.
  acceptance:
$($acceptanceLines -join "`n")
  constraints:
    - Preserve the separate parent turn boundary.
  validation:
    - Run the deterministic contract replay.
  plan_reference: $planReference
  goal_context_reference: $goalContextPath
``````

## Separate Parent Turn Handoff

``````text
`$adaptive-implementation-execution を使って $planReference を実装してください。
review-plan.md の implementation_intent を source of truth としてください。
``````
"@
        [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['review-plan']), $planContent.Replace("`r`n", "`n") + "`n", $utf8)
    }

    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['completion-notification']), "{`"observed_status`":`"$Verdict`",`"title`":`"Goal Context review $roundName completed`",`"result_uri`":`"$NotificationUri`"}`n", $utf8)

    $artifactBindings = [System.Collections.Generic.List[object]]::new()
    foreach ($role in @('review-context', 'remote-patch', 'goal-context-selection', 'local-findings', 'purpose-findings', 'review-plan')) {
        if ($roleFiles.Contains($role)) {
            $bindingPath = Join-Path $roundRoot $roleFiles[$role]
            $artifactBindings.Add([ordered]@{ role = $role; normalizedSha256 = Get-NormalizedSha256 $bindingPath })
        }
    }
    $reviewResult = [ordered]@{
        schemaVersion = 1
        repository = $repository
        pullRequest = $pullRequest
        roundNumber = $RoundNumber
        baseOid = $baseOid
        headOid = $HeadOid
        goalContext = [ordered]@{ path = $goalContextPath; normalizedSha256 = $goalContextSha }
        verdict = $Verdict
        findingDelta = @($FindingDelta)
        sourceCoverage = @($sourceCoverage)
        artifactBindings = @($artifactBindings)
    }
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['review-result']), (($reviewResult | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n"), $utf8)

    $artifacts = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $roleFiles.GetEnumerator()) {
        $fullPath = Join-Path $roundRoot $entry.Value
        $artifacts.Add([ordered]@{ role = $entry.Key; path = "$roundName/$($entry.Value)"; normalizedSha256 = Get-NormalizedSha256 $fullPath })
    }

    $result = [ordered]@{
        schemaVersion = 1
        roundNumber = $RoundNumber
        baseOid = $baseOid
        headOid = $HeadOid
        completedAt = $CompletedAt
        verdict = $Verdict
        humanDecisionReason = if ($HumanDecisionReason) { $HumanDecisionReason } else { $null }
        blockedReason = $null
        artifacts = @($artifacts)
        notification = [ordered]@{ roundNumber = $RoundNumber; observedStatus = $Verdict; resultUri = $NotificationUri }
        findingDelta = @($FindingDelta)
        sourceCoverage = @($sourceCoverage)
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

function Sync-MutatedArtifactHashes([string]$ResultPath, [string[]]$BoundRoles) {
    $roundRoot = Split-Path -Parent $ResultPath
    $result = Get-Content -Raw -LiteralPath $ResultPath | ConvertFrom-Json -Depth 100
    $reviewResultArtifact = $result.artifacts | Where-Object role -eq 'review-result'
    $reviewResultPath = Join-Path $roundRoot ([System.IO.Path]::GetFileName([string]$reviewResultArtifact.path))
    if ($BoundRoles.Count -gt 0) {
        $reviewResult = Get-Content -Raw -LiteralPath $reviewResultPath | ConvertFrom-Json -Depth 100
        foreach ($role in $BoundRoles) {
            $artifact = $result.artifacts | Where-Object role -eq $role
            $artifactPath = Join-Path $roundRoot ([System.IO.Path]::GetFileName([string]$artifact.path))
            ($reviewResult.artifactBindings | Where-Object role -eq $role).normalizedSha256 = Get-NormalizedSha256 $artifactPath
            $artifact.normalizedSha256 = Get-NormalizedSha256 $artifactPath
        }
        [System.IO.File]::WriteAllText($reviewResultPath, (($reviewResult | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    }
    $reviewResultArtifact.normalizedSha256 = Get-NormalizedSha256 $reviewResultPath
    [System.IO.File]::WriteAllText($ResultPath, (($result | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
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

    $earlyOverrideRoot = Join-Path $tempRoot 'negative-early-override'
    $earlyOverrideCycle = Join-Path $earlyOverrideRoot 'review-cycle.json'
    Start-Round -CyclePath $earlyOverrideCycle -HeadOid '1010101010101010101010101010101010101010' -StartedAt '2025-12-31T00:00:00Z' -OverrideMaximum 4 -ExpectSuccess $false -ExpectedPattern 'only for round 4 or later'
    if (Test-Path -LiteralPath $earlyOverrideCycle) { Add-Failure 'Rejected early override mutated review-cycle.json.' }

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
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ExpectSuccess $false -ExpectedPattern 'must be explicitly resolved'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ResolveDecision 'HD-999' -OverrideMaximum 4 -ExpectSuccess $false -ExpectedPattern 'resolved human decision ID mismatch'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ResolveDecision 'HD-003' -IncompleteDecision -ExpectSuccess $false -ExpectedPattern 'All human decision resolution fields'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ResolveDecision 'HD-003' -ExpectSuccess $false -ExpectedPattern 'exceeds effective maximum'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ResolveDecision 'HD-003' -OverrideMaximum 4 -IncompleteOverride -ExpectSuccess $false -ExpectedPattern 'All maximum-round override fields'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ResolveDecision 'HD-003' -OverrideMaximum 4
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

    # A non-limit human decision also requires an explicit matching resolution before the next round.
    $humanRoot = Join-Path $tempRoot 'human-decision'
    $humanCycle = Join-Path $humanRoot 'review-cycle.json'
    $humanHead1 = '7878787878787878787878787878787878787878'
    $humanHead2 = '7979797979797979797979797979797979797979'
    Start-Round $humanCycle $humanHead1 '2026-02-02T00:00:00Z'
    $humanResult1 = Write-RoundResult -CycleRoot $humanRoot -RoundNumber 1 -HeadOid $humanHead1 -CompletedAt '2026-02-02T00:01:00Z' -Verdict 'HUMAN_DECISION_REQUIRED' -FindingDelta @(
        (New-Delta 'TRK-HUMAN' 'new' @('PUR-150') @('pr-comment:human:1'))
    ) -IncludePlan $true -HumanDecisionReason 'Human scope choice is required.'
    Complete-Round $humanCycle $humanResult1
    Start-Round -CyclePath $humanCycle -HeadOid $humanHead2 -StartedAt '2026-02-02T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ExpectSuccess $false -ExpectedPattern 'must be explicitly resolved'
    Start-Round -CyclePath $humanCycle -HeadOid $humanHead2 -StartedAt '2026-02-02T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ResolveDecision 'HD-001'
    $humanResult2 = Write-RoundResult $humanRoot 2 $humanHead2 '2026-02-02T00:03:00Z' 'REVIEW_COMPLETE' @(
        (New-Delta 'TRK-HUMAN' 'resolved' @() @('pr-comment:human:2'))
    ) $false
    Complete-Round $humanCycle $humanResult2
    $expectedHuman = @($fixture.scenarios | Where-Object id -eq 'human-decision-resolution').expectedVerdicts
    Assert-CycleVerdicts $humanCycle $expectedHuman 'human decision resolution'

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

    $mappingRoot = Join-Path $tempRoot 'negative-source-tracking-swap'
    $mappingCycle = Join-Path $mappingRoot 'review-cycle.json'
    Start-Round $mappingCycle 'ecececececececececececececececececececec' '2026-04-03T01:10:00Z'
    $mappingResult = Write-RoundResult $mappingRoot 1 'ecececececececececececececececececececec' '2026-04-03T01:11:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-MAP-A' 'new' @('LR-501') @('review:mapping:a')),
        (New-Delta 'TRK-MAP-B' 'new' @('LR-502') @('review:mapping:b'))
    ) $true
    $mappingJson = Get-Content -Raw -LiteralPath $mappingResult | ConvertFrom-Json -Depth 100
    ($mappingJson.sourceCoverage | Where-Object sourceId -eq 'review:mapping:a').trackingIds = @('TRK-MAP-B')
    ($mappingJson.sourceCoverage | Where-Object sourceId -eq 'review:mapping:b').trackingIds = @('TRK-MAP-A')
    [System.IO.File]::WriteAllText($mappingResult, (($mappingJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Complete-Round $mappingCycle $mappingResult $false 'Source-to-tracking mapping mismatch'

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

    # Role-aware content mutations retain matching file hashes and must still fail semantic cross-checks.
    $contentRoot = Join-Path $tempRoot 'negative-artifact-content'
    $contentCycle = Join-Path $contentRoot 'review-cycle.json'
    $contentHead = 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1'
    Start-Round $contentCycle $contentHead '2026-04-06T00:00:00Z'
    $contentDelta = @((New-Delta 'TRK-CONTENT' 'new' @('LR-401') @('review:content:1')))

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $contextPath = Join-Path $contentRoot 'round-001/review-context.json'
    $contextJson = Get-Content -Raw -LiteralPath $contextPath | ConvertFrom-Json -Depth 100
    $contextJson.target.repository = 'fixture/wrong-artifact-repository'
    [System.IO.File]::WriteAllText($contextPath, (($contextJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-context')
    Complete-Round $contentCycle $contentResult $false 'review-context repository mismatch'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $selectionPath = Join-Path $contentRoot 'round-001/goal-context-selection.json'
    $selectionJson = Get-Content -Raw -LiteralPath $selectionPath | ConvertFrom-Json -Depth 100
    $selectionJson.contentSha256 = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    [System.IO.File]::WriteAllText($selectionPath, (($selectionJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @('goal-context-selection')
    Complete-Round $contentCycle $contentResult $false 'Goal Context selection SHA-256 mismatch'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $reviewResultPath = Join-Path $contentRoot 'round-001/review-result.json'
    $reviewResultJson = Get-Content -Raw -LiteralPath $reviewResultPath | ConvertFrom-Json -Depth 100
    $reviewResultJson.verdict = 'REVIEW_COMPLETE'
    [System.IO.File]::WriteAllText($reviewResultPath, (($reviewResultJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @()
    Complete-Round $contentCycle $contentResult $false 'review-result verdict mismatch'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $contextJson = Get-Content -Raw -LiteralPath $contextPath | ConvertFrom-Json -Depth 100
    $contextJson.sources.issueComments = @($contextJson.sources.issueComments) + @([pscustomobject]@{ id = 999; sourceId = 'pr-comment:uncovered' })
    [System.IO.File]::WriteAllText($contextPath, (($contextJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-context')
    Complete-Round $contentCycle $contentResult $false 'source coverage does not exactly match review artifacts'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $planPath = Join-Path $contentRoot 'round-001/review-plan.md'
    $planContent = [System.IO.File]::ReadAllText($planPath).Replace('implementation_intent:', 'invalid_intent:')
    [System.IO.File]::WriteAllText($planPath, $planContent, $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-plan')
    Complete-Round $contentCycle $contentResult $false 'canonical implementation_intent'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $planContent = [System.IO.File]::ReadAllText($planPath).Replace('  acceptance:', '  omitted_acceptance:')
    [System.IO.File]::WriteAllText($planPath, $planContent, $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-plan')
    Complete-Round $contentCycle $contentResult $false 'missing acceptance'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $planContent = [System.IO.File]::ReadAllText($planPath).Replace('| LR-401 | Remediate', '| LR-999 | Remediate')
    [System.IO.File]::WriteAllText($planPath, $planContent, $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-plan')
    Complete-Round $contentCycle $contentResult $false 'active finding mapping mismatch'

    if (-not $IsWindows) {
        $outsideCycleRoot = Join-Path $tempRoot 'outside-linked-cycle-root'
        [System.IO.Directory]::CreateDirectory($outsideCycleRoot) | Out-Null
        $linkedCycleRoot = Join-Path $tempRoot 'linked-cycle-root'
        New-Item -ItemType SymbolicLink -Path $linkedCycleRoot -Target $outsideCycleRoot | Out-Null
        Start-Round (Join-Path $linkedCycleRoot 'review-cycle.json') 'b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1b1' '2026-04-07T00:00:00Z' -ExpectSuccess $false -ExpectedPattern 'root must not be a symlink or junction'

        $linkedFileRoot = Join-Path $tempRoot 'linked-cycle-file'
        [System.IO.Directory]::CreateDirectory($linkedFileRoot) | Out-Null
        $outsideCycleFile = Join-Path $tempRoot 'outside-review-cycle.json'
        [System.IO.File]::WriteAllText($outsideCycleFile, "{}`n", $utf8)
        New-Item -ItemType SymbolicLink -Path (Join-Path $linkedFileRoot 'review-cycle.json') -Target $outsideCycleFile | Out-Null
        Start-Round (Join-Path $linkedFileRoot 'review-cycle.json') 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2' '2026-04-07T00:01:00Z' -ExpectSuccess $false -ExpectedPattern 'resolves outside review cycle root'

        $linkedRoundRoot = Join-Path $tempRoot 'linked-round-directory'
        $linkedRoundCycle = Join-Path $linkedRoundRoot 'review-cycle.json'
        Start-Round $linkedRoundCycle 'b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3' '2026-04-07T00:02:00Z'
        Remove-Item -LiteralPath (Join-Path $linkedRoundRoot 'round-001') -Force
        $outsideRound = Join-Path $tempRoot 'outside-round-001'
        [System.IO.Directory]::CreateDirectory($outsideRound) | Out-Null
        New-Item -ItemType SymbolicLink -Path (Join-Path $linkedRoundRoot 'round-001') -Target $outsideRound | Out-Null
        $linkedRoundResult = Write-RoundResult $linkedRoundRoot 1 'b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3b3' '2026-04-07T00:03:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
            (New-Delta 'TRK-LINKED-ROUND' 'new' @('LR-601') @('review:linked-round'))
        ) $true
        Complete-Round $linkedRoundCycle $linkedRoundResult $false 'resolves outside review cycle root'

        $linkedArtifactRoot = Join-Path $tempRoot 'linked-artifact-file'
        $linkedArtifactCycle = Join-Path $linkedArtifactRoot 'review-cycle.json'
        Start-Round $linkedArtifactCycle 'b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4' '2026-04-07T00:04:00Z'
        $linkedArtifactResult = Write-RoundResult $linkedArtifactRoot 1 'b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4' '2026-04-07T00:05:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
            (New-Delta 'TRK-LINKED-ARTIFACT' 'new' @('LR-602') @('review:linked-artifact'))
        ) $true
        $linkedPlanPath = Join-Path $linkedArtifactRoot 'round-001/review-plan.md'
        $outsidePlanPath = Join-Path $tempRoot 'outside-review-plan.md'
        Copy-Item -LiteralPath $linkedPlanPath -Destination $outsidePlanPath
        Remove-Item -LiteralPath $linkedPlanPath -Force
        New-Item -ItemType SymbolicLink -Path $linkedPlanPath -Target $outsidePlanPath | Out-Null
        Complete-Round $linkedArtifactCycle $linkedArtifactResult $false 'resolves outside review cycle root'
    }

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
    foreach ($required in @('duplicate-head', 'missing-adaptive-result-reference', 'identity-drift', 'existing-round-directory', 'historical-artifact-hash', 'unknown-persistent-finding', 'missing-active-finding-mapping', 'round-limit-verdict', 'incomplete-override', 'actionable-without-plan', 'review-complete-with-plan', 'missing-source-coverage', 'source-tracking-swap', 'invalid-reopened-transition', 'round-result-head-identity', 'notification-status', 'notification-pr', 'early-override', 'unresolved-human-decision', 'wrong-human-decision-id', 'review-context-content', 'goal-context-selection-content', 'review-result-content', 'uncovered-artifact-source', 'review-plan-intent', 'review-plan-acceptance', 'review-plan-finding-mapping', 'cycle-root-link-escape', 'cycle-file-link-escape', 'round-directory-link-escape', 'artifact-file-link-escape')) {
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
