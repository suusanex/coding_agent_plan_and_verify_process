[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$managerPath = Join-Path $repoRoot 'apm-packages\pr-review-remediation\.apm\skills\goal-context-pr-review\scripts\manage-review-cycle.cs'
$fixturePath = Join-Path $repoRoot 'tests\pr-review-remediation\PRR-003\scenarios.json'
$collectorSnapshotRoot = Join-Path $repoRoot 'tests\pr-review-remediation\PRR-003\collector-snapshots'
$fixture = Get-Content -Raw -LiteralPath $fixturePath | ConvertFrom-Json -Depth 100
$failures = [System.Collections.Generic.List[string]]::new()
$repository = [string]$fixture.repository
$pullRequest = [int]$fixture.pullRequest
$baseOid = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$goalContextPath = 'docs/goal-context-multi-project-ai-development-notification-and-purpose-review.md'
$goalContextSha = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
$prUrl = "https://github.com/$repository/pull/$pullRequest"
$reviewThreadId = '019fa6ca-847e-73b3-a2e7-189638eb1327'
$implementationThreadId = '019fa8a6-8b70-7da1-8007-12c3ae26828f'
$reviewThreadUri = "codex://threads/$reviewThreadId"
$implementationThreadUri = "codex://threads/$implementationThreadId"
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
        [string]$ReviewThreadId = $script:reviewThreadId,
        [string]$ImplementationThreadId = $script:implementationThreadId,
        [string]$AdaptiveThreadId = $script:implementationThreadId,
        [string]$ThreadMode = 'role-thread-reuse',
        [string]$PortableReason = '',
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    $arguments = @(
        'start', '--cycle', $CyclePath, '--repository', $repository, '--pr', [string]$pullRequest,
        '--goal-context-path', $goalContextPath, '--goal-context-sha', $goalContextSha,
        '--base-oid', $baseOid, '--head-oid', $HeadOid, '--started-at', $StartedAt,
        '--thread-mode', $ThreadMode, '--review-thread-id', $ReviewThreadId, '--format', 'json'
    )
    if ($ImplementationThreadId) { $arguments += @('--implementation-thread-id', $ImplementationThreadId) }
    if ($AdaptiveResult) { $arguments += @('--adaptive-result-reference', $AdaptiveResult, '--adaptive-thread-id', $AdaptiveThreadId) }
    if ($ThreadMode -eq 'portable-handoff') {
        $arguments += @(
            '--portable-reason', $(if ($PortableReason) { $PortableReason } else { 'Explicit portability fixture.' }),
            '--portable-approved-by', 'fixture-human', '--portable-approved-at', $StartedAt
        )
    }
    Invoke-Manager $arguments "start round at head $HeadOid" $ExpectSuccess $ExpectedPattern | Out-Null
}

function Change-ThreadBinding {
    param(
        [string]$CyclePath,
        [string]$Operation,
        [string]$Role,
        [string]$NewThreadId,
        [string]$ApprovedAt,
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    Invoke-Manager @(
        $Operation, '--cycle', $CyclePath, '--thread-role', $Role, '--new-thread-id', $NewThreadId,
        '--thread-change-reason', 'Human-approved task recovery.', '--thread-change-approved-by', 'fixture-human',
        '--thread-change-approved-at', $ApprovedAt, '--format', 'json'
    ) "$Operation $Role thread" $ExpectSuccess $ExpectedPattern | Out-Null
}

function New-Delta([string]$TrackingId, [string]$State, [string[]]$FindingIds, [string[]]$SourceIds) {
    return [ordered]@{
        trackingId = $TrackingId
        state = $State
        findingIds = @($FindingIds)
        sourceIds = @($SourceIds)
    }
}

function Write-ReviewPlan {
    param(
        [string]$CycleRoot,
        [int]$RoundNumber,
        [string]$HeadOid,
        [string]$Verdict,
        [object[]]$FindingDelta,
        [string]$OutputPath,
        [string]$PlanReference
    )
    $roundName = 'round-{0:000}' -f $RoundNumber
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
    $cycle = Get-Content -Raw -LiteralPath (Join-Path $CycleRoot 'review-cycle.json') | ConvertFrom-Json -Depth 100
    $threadMode = [string]$cycle.threadMode
    $handoffMetadata = if ($threadMode -eq 'role-thread-reuse') {
@"
- Thread mode: role-thread-reuse
- Target Implementation Thread ID: $($cycle.roleThreads.implementation.threadId)
- Target Implementation Thread URI: $($cycle.roleThreads.implementation.resumeUri)
- Return Review Thread ID: $($cycle.roleThreads.review.threadId)
- Return Review Thread URI: $($cycle.roleThreads.review.resumeUri)
- Plan SHA-256 source: round manifest artifact binding
"@
    } else {
@"
- Thread mode: portable-handoff
- Target Implementation Thread ID: N/A
- Target Implementation Thread URI: N/A
- Return Review Thread ID: N/A
- Return Review Thread URI: N/A
- Plan SHA-256 source: round manifest artifact binding
- Recovery boundary: Explicitly approved artifact-only cold-start.
"@
    }
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
  plan_reference: $PlanReference
  goal_context_reference: $goalContextPath
``````

## Explicit Implementation Turn Handoff

$handoffMetadata

``````text
`$adaptive-implementation-execution を使って $PlanReference を実装してください。
review-plan.md の implementation_intent を source of truth としてください。
``````
"@
    [System.IO.File]::WriteAllText($OutputPath, $planContent.Replace("`r`n", "`n") + "`n", $utf8)
}

function Resolve-HumanDecision {
    param(
        [string]$CyclePath,
        [int]$RoundNumber,
        [string]$HeadOid,
        [object[]]$FindingDelta,
        [string]$DecisionId,
        [string]$ApprovedAt,
        [int]$OverrideMaximum = 0,
        [switch]$IncompleteDecision,
        [switch]$IncompleteOverride,
        [switch]$OmitApprovedPlan,
        [switch]$RemoveHandoff,
        [switch]$IncludeAdaptiveResult,
        [bool]$ExpectSuccess = $true,
        [string]$ExpectedPattern = ''
    )
    $cycleRoot = Split-Path -Parent $CyclePath
    $roundName = 'round-{0:000}' -f $RoundNumber
    $candidatePath = Join-Path $cycleRoot "approved-plan-candidate-$DecisionId.md"
    $planReference = "$roundName/approved-review-plan.md"
    if (-not $OmitApprovedPlan) {
        Write-ReviewPlan $cycleRoot $RoundNumber $HeadOid 'APPROVED_FOR_ADAPTIVE_IMPLEMENTATION' $FindingDelta $candidatePath $planReference
        if ($RemoveHandoff) {
            $content = Get-Content -Raw -LiteralPath $candidatePath
            $content = [regex]::Replace($content, '(?ms)^## Explicit Implementation Turn Handoff\s+.*\z', '')
            [System.IO.File]::WriteAllText($candidatePath, $content.Replace("`r`n", "`n"), $utf8)
        }
    }
    $arguments = @('resolve', '--cycle', $CyclePath, '--resolve-decision', $DecisionId)
    if (-not $IncompleteDecision) {
        $arguments += @(
            '--decision-resolution', 'Continue after explicit human review.',
            '--decision-approved-by', 'fixture-human', '--decision-approved-at', $ApprovedAt
        )
        if (-not $OmitApprovedPlan) { $arguments += @('--approved-plan', $candidatePath) }
    }
    if ($OverrideMaximum -gt 0) {
        $arguments += @('--override-maximum-rounds', [string]$OverrideMaximum)
        if (-not $IncompleteOverride) {
            $arguments += @(
                '--override-approved-by', 'fixture-human', '--override-approved-at', $ApprovedAt,
                '--override-reason', 'Explicitly approved one additional diagnostic round.'
            )
        }
    }
    if ($IncludeAdaptiveResult) { $arguments += @('--adaptive-result-reference', 'adaptive/already-executed/result.md') }
    Invoke-Manager $arguments "resolve human decision $DecisionId" $ExpectSuccess $ExpectedPattern | Out-Null
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
        [string]$HumanDecisionReason = '',
        [object[]]$ReviewSources = @(),
        [object[]]$IssueCommentSources = @(),
        [object[]]$InlineCommentSources = @(),
        [object[]]$CheckSources = @(),
        [string]$RemotePatchPointer = 'pr-diff.patch',
        [string]$ReviewContextFixture = ''
    )
    $roundName = 'round-{0:000}' -f $RoundNumber
    $reviewMode = if ($RoundNumber -eq 1) { 'full' } else { 'purpose-only' }
    $roundRoot = Join-Path $CycleRoot $roundName
    $roleFiles = [ordered]@{
        'review-context' = 'review-context.json'
        'remote-patch' = 'pr-diff.patch'
        'goal-context-selection' = 'goal-context-selection.json'
        'purpose-findings' = 'purpose-review-findings.md'
        'review-result' = 'review-result.json'
        'completion-notification' = 'completion-notification.txt'
    }
    if ($reviewMode -eq 'full') { $roleFiles['local-findings'] = 'local-review-findings.md' }
    if ($IncludePlan) { $roleFiles['review-plan'] = 'review-plan.md' }

    $fixtureContext = $null
    if ($ReviewContextFixture) {
        if (-not (Test-Path -LiteralPath $ReviewContextFixture -PathType Leaf)) { throw "Review Context fixture is missing: $ReviewContextFixture" }
        $fixtureContext = Get-Content -Raw -LiteralPath $ReviewContextFixture | ConvertFrom-Json -Depth 100
        $ReviewSources = @($fixtureContext.sources.reviews)
        $IssueCommentSources = @($fixtureContext.sources.issueComments)
        $InlineCommentSources = @($fixtureContext.sources.inlineComments)
        $CheckSources = @($fixtureContext.sources.checks)
        $RemotePatchPointer = [string]$fixtureContext.artifacts.remotePatch
    }

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
    $checkSourceId = "check:$roundName"
    $explicitSources = $ReviewSources.Count + $IssueCommentSources.Count + $InlineCommentSources.Count + $CheckSources.Count -gt 0
    $effectiveReviews = @($ReviewSources)
    $effectiveInlineComments = @($InlineCommentSources)
    $effectiveIssueComments = if ($explicitSources) {
        @($IssueCommentSources)
    } elseif ($reviewMode -eq 'purpose-only') {
        @()
    } else {
        @($FindingDelta | ForEach-Object { $_.sourceIds } | Select-Object -Unique | ForEach-Object -Begin { $id = 0 } -Process { $id++; [ordered]@{ id = $id; sourceId = $_; body = 'Synthetic source.' } })
    }
    $effectiveChecks = if ($CheckSources.Count -gt 0) {
        @($CheckSources)
    } else {
        @([ordered]@{ id = 9000 + $RoundNumber; sourceId = $checkSourceId; name = 'fixture-contract'; status = 'COMPLETED'; conclusion = 'SUCCESS' })
    }
    $contextSources = @($effectiveReviews) + @($effectiveIssueComments) + @($effectiveInlineComments) + @($effectiveChecks)
    $sourceCoverage = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $coverageBySource.GetEnumerator()) {
        $sourceCoverage.Add([ordered]@{ sourceId = $entry.Key; disposition = 'finding'; trackingIds = @($entry.Value); reason = $null })
    }
    foreach ($source in $contextSources) {
        $sourceId = [string]$source.sourceId
        if ($reviewMode -eq 'purpose-only') {
            $sourceCoverage.Add([ordered]@{ sourceId = $sourceId; disposition = 'noAction'; trackingIds = @(); reason = 'Audit-only external source in purpose-only round.' })
        } elseif (-not $coverageBySource.Contains($sourceId)) {
            $sourceCoverage.Add([ordered]@{ sourceId = $sourceId; disposition = 'noAction'; trackingIds = @(); reason = 'Collected source has no actionable finding in this round.' })
        }
    }

    $reviewContext = [ordered]@{
        schemaVersion = '1.0'
        generatedAt = $CompletedAt
        target = [ordered]@{
            repository = $repository; pullRequest = $pullRequest; url = $prUrl; state = 'OPEN'; isDraft = $false
            baseRefName = 'main'; baseRefOid = $baseOid; headRefName = 'feature'; headRefOid = $HeadOid
        }
        copilotReviewWait = if ($reviewMode -eq 'full') {
            [ordered]@{ waitStatus = 'completed'; observedReviewState = 'reviewAndInline'; timedOut = $false }
        } else {
            [ordered]@{ waitStatus = 'disabled'; observedReviewState = 'notWaited'; timedOut = $false }
        }
        artifacts = [ordered]@{ remotePatch = $RemotePatchPointer }
        sources = [ordered]@{
            pullRequest = [ordered]@{
                number = $pullRequest; title = 'PRR-003 collector-realistic fixture'; state = 'OPEN'; url = $prUrl
                baseRefName = 'main'; baseRefOid = $baseOid; headRefName = 'feature'; headRefOid = $HeadOid; isDraft = $false
            }
            reviews = @($effectiveReviews)
            issueComments = @($effectiveIssueComments)
            inlineComments = @($effectiveInlineComments)
            checks = @($effectiveChecks)
        }
    }
    $reviewContextPath = Join-Path $roundRoot $roleFiles['review-context']
    if ($null -ne $fixtureContext) {
        if ($reviewMode -eq 'purpose-only') {
            $fixtureContext.copilotReviewWait.waitStatus = 'disabled'
            $fixtureContext.copilotReviewWait.observedReviewState = 'notWaited'
            $fixtureContext.copilotReviewWait.timedOut = $false
        }
        [System.IO.File]::WriteAllText($reviewContextPath, (($fixtureContext | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    } else {
        [System.IO.File]::WriteAllText($reviewContextPath, (($reviewContext | ConvertTo-Json -Depth 30).Replace("`r`n", "`n") + "`n"), $utf8)
    }
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['remote-patch']), "diff --git a/fixture.txt b/fixture.txt`n# $roundName $HeadOid`n", $utf8)

    $selection = [ordered]@{
        schemaVersion = 2
        selectionStatus = 'SELECTED'
        selectedPath = $goalContextPath
        selectionMode = 'user-specified'
        lifecycleStatus = 'human-reviewed'
        sensitiveDataReview = 'passed'
        draftOverride = $false
        validation = 'PASS'
        validationContractVersion = 1
        validationMode = 'strict'
        contentSha256 = $goalContextSha
    }
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['goal-context-selection']), (($selection | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"), $utf8)

    if ($reviewMode -eq 'full') {
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
    }

    $purposeIds = @($FindingDelta | ForEach-Object { $_.findingIds } | Where-Object { $_ -match '^PUR-\d+$' } | Select-Object -Unique)
    $purposeRows = if ($purposeIds.Count -eq 0) { '| N/A | N/A | No purpose actionable finding. | N/A | N/A | N/A |' } else { @($purposeIds | ForEach-Object { "| $_ | Desired outcome | Synthetic purpose finding. | fixture | fixture | fixture |" }) -join "`n" }
    $priorRows = '| N/A | N/A | N/A | N/A | N/A | N/A |'
    if ($reviewMode -eq 'purpose-only') {
        $cycle = Get-Content -Raw -LiteralPath (Join-Path $CycleRoot 'review-cycle.json') | ConvertFrom-Json -Depth 100
        $states = @{}
        foreach ($priorRound in @($cycle.rounds | Where-Object { $_.roundNumber -lt $RoundNumber -and $_.status -eq 'COMPLETED' })) {
            foreach ($entry in @($priorRound.findingDelta)) { $states[[string]$entry.trackingId] = [string]$entry.state }
        }
        $adaptiveReference = [string](@($cycle.rounds | Where-Object roundNumber -eq $RoundNumber)[0].adaptiveResultReference)
        $rows = foreach ($trackingId in @($states.Keys | Sort-Object)) {
            if ($states[$trackingId] -notin @('new', 'persistent', 'reopened')) { continue }
            $mapped = @($FindingDelta | Where-Object trackingId -eq $trackingId)
            if ($mapped.Count -eq 1) { "| $trackingId | $($states[$trackingId]) | $($mapped[0].state) | $adaptiveReference | Current patch evidence. | Purpose-only transition assessment. |" }
        }
        $priorRows = @($rows) -join "`n"
    }
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

## Prior Finding Assessment

| Tracking ID | Previous state | Current state | Adaptive result reference | Current PR evidence | Rationale |
| --- | --- | --- | --- | --- | --- |
$priorRows

## Findings

| ID | Goal Context section | Summary | PR evidence | Purpose risk | Suggested outcome |
| --- | --- | --- | --- | --- | --- |
$purposeRows
"@
    [System.IO.File]::WriteAllText((Join-Path $roundRoot $roleFiles['purpose-findings']), $purposeContent.Replace("`r`n", "`n") + "`n", $utf8)

    if ($IncludePlan) {
        Write-ReviewPlan $CycleRoot $RoundNumber $HeadOid $Verdict $FindingDelta (Join-Path $roundRoot $roleFiles['review-plan']) "$roundName/review-plan.md"
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
        schemaVersion = 2
        repository = $repository
        pullRequest = $pullRequest
        roundNumber = $RoundNumber
        reviewMode = $reviewMode
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
        schemaVersion = 2
        roundNumber = $RoundNumber
        reviewMode = $reviewMode
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

if ($fixture.schemaVersion -ne 2 -or $fixture.fixtureId -ne 'PRR-003' -or $fixture.externalModelExecution -ne $false) {
    throw 'PRR-003 fixture metadata is invalid.'
}
if (($fixture.findingStates -join '|') -ne 'new|persistent|resolved|reopened' -or $fixture.defaultMaximumRounds -ne 3) {
    throw 'PRR-003 fixture state vocabulary or default maximum drifted.'
}
$collectorScenario = $fixture.scenarios | Where-Object id -eq 'collector-realistic-convergence'
if ((@($collectorScenario.reviewModes) -join '|') -ne 'full|purpose-only|purpose-only') { throw 'PRR-003 review mode sequence drifted.' }
if ($null -eq $collectorScenario -or ($collectorScenario.sourceHeadRelationships -join '|') -ne 'current|historical|unknown') {
    throw 'PRR-003 collector-realistic source relationship coverage drifted.'
}
foreach ($snapshot in @($collectorScenario.collectorSnapshots)) {
    $snapshotPath = Join-Path (Split-Path -Parent $fixturePath) ([string]$snapshot)
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { throw "PRR-003 collector snapshot is missing: $snapshot" }
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
    Invoke-Manager @(
        'start', '--cycle', $earlyOverrideCycle, '--repository', $repository, '--pr', [string]$pullRequest,
        '--goal-context-path', $goalContextPath, '--goal-context-sha', $goalContextSha,
        '--base-oid', $baseOid, '--head-oid', '1010101010101010101010101010101010101010',
        '--started-at', '2025-12-31T00:00:00Z', '--override-maximum-rounds', '4',
        '--review-thread-id', $reviewThreadId, '--implementation-thread-id', $implementationThreadId,
        '--override-approved-by', 'fixture-human', '--override-approved-at', '2025-12-31T00:00:00Z',
        '--override-reason', 'Invalid early override.', '--format', 'json'
    ) 'early start override' $false 'must use the separate resolve command' | Out-Null
    if (Test-Path -LiteralPath $earlyOverrideCycle) { Add-Failure 'Rejected early override mutated review-cycle.json.' }

    $timestampRoot = Join-Path $tempRoot 'negative-timestamp'
    Start-Round -CyclePath (Join-Path $timestampRoot 'locale-date.json') -HeadOid '1212121212121212121212121212121212121212' -StartedAt '07/28/2026 09:00:00' -ExpectSuccess $false -ExpectedPattern 'explicit Z or UTC offset'
    Start-Round -CyclePath (Join-Path $timestampRoot 'missing-offset.json') -HeadOid '1313131313131313131313131313131313131313' -StartedAt '2026-07-28T09:00:00' -ExpectSuccess $false -ExpectedPattern 'explicit Z or UTC offset'
    Start-Round -CyclePath (Join-Path $timestampRoot 'valid-offset.json') -HeadOid '1414141414141414141414141414141414141414' -StartedAt '2026-07-28T09:00:00+09:00'

    # Collector-realistic convergence: later snapshots retain sources from prior heads while target identity advances.
    $convergenceRoot = Join-Path $tempRoot 'convergence'
    $convergenceCycle = Join-Path $convergenceRoot 'review-cycle.json'
    $head1 = '1111111111111111111111111111111111111111'
    $head2 = '2222222222222222222222222222222222222222'
    $head3 = '3333333333333333333333333333333333333333'
    Start-Round $convergenceCycle $head1 '2026-01-01T00:00:00Z'
    $r1 = Write-RoundResult $convergenceRoot 1 $head1 '2026-01-01T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-A' 'new' @('LR-001') @('review:1001', 'inline-comment:1101'))
    ) $true -ReviewContextFixture (Join-Path $collectorSnapshotRoot 'round-001-review-context.json')
    Complete-Round $convergenceCycle $r1
    Start-Round -CyclePath $convergenceCycle -HeadOid $head1 -StartedAt '2026-01-01T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ExpectSuccess $false -ExpectedPattern 'already reviewed'
    Start-Round -CyclePath $convergenceCycle -HeadOid $head2 -StartedAt '2026-01-01T00:02:00Z' -ExpectSuccess $false -ExpectedPattern 'requires --adaptive-result-reference'
    $identityArguments = @(
        'start', '--cycle', $convergenceCycle, '--repository', 'fixture/wrong-repository', '--pr', [string]$pullRequest,
        '--goal-context-path', $goalContextPath, '--goal-context-sha', $goalContextSha,
        '--base-oid', $baseOid, '--head-oid', $head2, '--started-at', '2026-01-01T00:02:00Z',
        '--adaptive-result-reference', 'adaptive/round-001/result.md', '--adaptive-thread-id', $implementationThreadId,
        '--review-thread-id', $reviewThreadId, '--implementation-thread-id', $implementationThreadId, '--format', 'json'
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
        (New-Delta 'TRK-A' 'persistent' @('PUR-002') @('PUR-002')),
        (New-Delta 'TRK-B' 'new' @('PUR-003') @('PUR-003'))
    ) $true -ReviewContextFixture (Join-Path $collectorSnapshotRoot 'round-002-review-context.json')
    Complete-Round $convergenceCycle $r2
    Start-Round $convergenceCycle $head3 '2026-01-01T00:05:00Z' 'adaptive/round-002/result.md'
    $r3 = Write-RoundResult $convergenceRoot 3 $head3 '2026-01-01T00:06:00Z' 'REVIEW_COMPLETE' @(
        (New-Delta 'TRK-A' 'resolved' @() @()),
        (New-Delta 'TRK-B' 'resolved' @() @())
    ) $false -ReviewContextFixture (Join-Path $collectorSnapshotRoot 'round-003-review-context.json')
    Complete-Round $convergenceCycle $r3
    Invoke-Manager @('validate', '--cycle', $convergenceCycle, '--format', 'json') 'validate converged cycle' | Out-Null
    $expectedConvergence = @($fixture.scenarios | Where-Object id -eq 'collector-realistic-convergence').expectedVerdicts
    Assert-CycleVerdicts $convergenceCycle $expectedConvergence 'convergence'
    $convergenceJson = Get-Content -Raw -LiteralPath $convergenceCycle | ConvertFrom-Json -Depth 100
    if ($convergenceJson.threadMode -ne 'role-thread-reuse') { Add-Failure 'Convergence cycle did not use role-thread-reuse.' }
    if (@($convergenceJson.rounds | Where-Object reviewThreadId -ne $reviewThreadId).Count -ne 0) { Add-Failure 'Review Thread identity changed across convergence rounds.' }
    if (@($convergenceJson.rounds | Where-Object { $_.roundNumber -gt 1 -and $_.adaptiveThreadId -ne $implementationThreadId }).Count -ne 0) { Add-Failure 'Implementation Thread identity changed across convergence remediations.' }
    if ($convergenceJson.roleThreads.review.threadId -eq $convergenceJson.roleThreads.implementation.threadId) { Add-Failure 'Review and Implementation role threads were not distinct.' }

    $threadMismatchRoot = Join-Path $tempRoot 'negative-thread-mismatch'
    $threadMismatchCycle = Join-Path $threadMismatchRoot 'review-cycle.json'
    Start-Round $threadMismatchCycle '1515151515151515151515151515151515151515' '2026-01-02T00:00:00Z'
    Complete-Round $threadMismatchCycle (Write-RoundResult $threadMismatchRoot 1 '1515151515151515151515151515151515151515' '2026-01-02T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-THREAD' 'new' @('LR-015') @('review:thread:1'))
    ) $true)
    $wrongReviewThread = '019fa6ca-847e-73b3-a2e7-189638eb1399'
    Start-Round -CyclePath $threadMismatchCycle -HeadOid '1616161616161616161616161616161616161615' -StartedAt '2026-01-02T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ReviewThreadId $wrongReviewThread -ExpectSuccess $false -ExpectedPattern 'Review Thread ID mismatch'
    $wrongImplementationThread = '019fa8a6-8b70-7da1-8007-12c3ae268999'
    Start-Round -CyclePath $threadMismatchCycle -HeadOid '1616161616161616161616161616161616161616' -StartedAt '2026-01-02T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -AdaptiveThreadId $wrongImplementationThread -ExpectSuccess $false -ExpectedPattern 'Adaptive Implementation Thread ID mismatch'
    Start-Round -CyclePath (Join-Path $tempRoot 'negative-same-role-thread/review-cycle.json') -HeadOid '1717171717171717171717171717171717171717' -StartedAt '2026-01-02T00:03:00Z' -ImplementationThreadId $reviewThreadId -ExpectSuccess $false -ExpectedPattern 'must be different Codex tasks'
    Start-Round -CyclePath (Join-Path $tempRoot 'negative-malformed-thread/review-cycle.json') -HeadOid '1818181818181818181818181818181818181818' -StartedAt '2026-01-02T00:04:00Z' -ReviewThreadId 'not-a-task-id' -ExpectSuccess $false -ExpectedPattern 'must be a Codex task UUID'
    Invoke-Manager @(
        'start', '--cycle', (Join-Path $tempRoot 'negative-missing-thread/review-cycle.json'),
        '--repository', $repository, '--pr', [string]$pullRequest, '--goal-context-path', $goalContextPath,
        '--goal-context-sha', $goalContextSha, '--base-oid', $baseOid,
        '--head-oid', '1818181818181818181818181818181818181819', '--started-at', '2026-01-02T00:05:00Z', '--format', 'json'
    ) 'missing Review Thread ID' $false 'review-thread-id' | Out-Null

    $lateBindRoot = Join-Path $tempRoot 'late-implementation-thread-binding'
    $lateBindCycle = Join-Path $lateBindRoot 'review-cycle.json'
    Start-Round -CyclePath $lateBindCycle -HeadOid '1818181818181818181818181818181818181820' -StartedAt '2026-01-02T00:06:00Z' -ImplementationThreadId ''
    Change-ThreadBinding $lateBindCycle 'bind-thread' 'implementation' $implementationThreadId '2026-01-02T00:07:00Z'
    Complete-Round $lateBindCycle (Write-RoundResult $lateBindRoot 1 '1818181818181818181818181818181818181820' '2026-01-02T00:08:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-LATE-BIND' 'new' @('LR-018') @('review:late-bind:1'))
    ) $true)
    $lateBindJson = Get-Content -Raw -LiteralPath $lateBindCycle | ConvertFrom-Json -Depth 100
    if ($lateBindJson.roleThreads.implementation.threadId -ne $implementationThreadId -or
        @($lateBindJson.threadBindingHistory | Where-Object role -eq 'implementation').Count -ne 1) {
        Add-Failure 'Implementation Thread was not bound before actionable round completion.'
    }

    $rebindRoot = Join-Path $tempRoot 'thread-rebind'
    $rebindCycle = Join-Path $rebindRoot 'review-cycle.json'
    Start-Round $rebindCycle '1919191919191919191919191919191919191919' '2026-01-02T01:00:00Z'
    Complete-Round $rebindCycle (Write-RoundResult $rebindRoot 1 '1919191919191919191919191919191919191919' '2026-01-02T01:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-REBIND' 'new' @('LR-019') @('review:rebind:1'))
    ) $true)
    $reboundReviewThread = '019fa6ca-847e-73b3-a2e7-189638eb1400'
    Change-ThreadBinding $rebindCycle 'rebind-thread' 'review' $reboundReviewThread '2026-01-02T01:02:00Z'
    Start-Round -CyclePath $rebindCycle -HeadOid '2020202020202020202020202020202020202020' -StartedAt '2026-01-02T01:03:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ReviewThreadId $reboundReviewThread
    $rebindJson = Get-Content -Raw -LiteralPath $rebindCycle | ConvertFrom-Json -Depth 100
    if ((@($rebindJson.threadBindingHistory | Where-Object role -eq 'review').Count -ne 2) -or
        ($rebindJson.threadBindingHistory[0].newThreadId -ne $reviewThreadId) -or
        ($rebindJson.roleThreads.review.threadId -ne $reboundReviewThread)) {
        Add-Failure 'Approved Review Thread rebind did not preserve old binding history and activate the new binding.'
    }
    Invoke-Manager @('rebind-thread', '--cycle', $rebindCycle, '--thread-role', 'implementation', '--new-thread-id', $wrongImplementationThread, '--format', 'json') 'incomplete thread rebind' $false 'require cycle, role, new thread ID, reason, approver, and approval timestamp' | Out-Null
    $historyMutationRoot = Join-Path $tempRoot 'negative-thread-history-overwrite'
    Copy-Item -LiteralPath $rebindRoot -Destination $historyMutationRoot -Recurse
    $historyMutationCycle = Join-Path $historyMutationRoot 'review-cycle.json'
    $historyMutationJson = Get-Content -Raw -LiteralPath $historyMutationCycle | ConvertFrom-Json -Depth 100
    $historyMutationJson.threadBindingHistory[0].newThreadId = $wrongReviewThread
    $historyMutationJson.threadBindingHistory[0].resumeUri = "codex://threads/$wrongReviewThread"
    [System.IO.File]::WriteAllText($historyMutationCycle, (($historyMutationJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Invoke-Manager @('validate', '--cycle', $historyMutationCycle, '--format', 'json') 'overwritten thread binding history' $false 'thread binding previous ID mismatch|Review Thread ID mismatch' | Out-Null

    $portableRoot = Join-Path $tempRoot 'portable-handoff'
    $portableCycle = Join-Path $portableRoot 'review-cycle.json'
    Start-Round -CyclePath $portableCycle -HeadOid '2121212121212121212121212121212121212121' -StartedAt '2026-01-02T02:00:00Z' -ThreadMode 'portable-handoff'
    Complete-Round $portableCycle (Write-RoundResult $portableRoot 1 '2121212121212121212121212121212121212121' '2026-01-02T02:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' @(
        (New-Delta 'TRK-PORTABLE' 'new' @('LR-021') @('review:portable:1'))
    ) $true)
    $portableReview2 = '019fa6ca-847e-73b3-a2e7-189638eb1500'
    $portableImplementation2 = '019fa8a6-8b70-7da1-8007-12c3ae268500'
    Start-Round -CyclePath $portableCycle -HeadOid '2222222222222222222222222222222222222223' -StartedAt '2026-01-02T02:02:00Z' -AdaptiveResult 'adaptive/portable/result.md' -ReviewThreadId $portableReview2 -AdaptiveThreadId $portableImplementation2 -ThreadMode 'portable-handoff'
    $portableJson = Get-Content -Raw -LiteralPath $portableCycle | ConvertFrom-Json -Depth 100
    if ($portableJson.threadMode -ne 'portable-handoff' -or -not $portableJson.portableHandoffApproval.reason) { Add-Failure 'Portable handoff approval evidence was not retained.' }
    Invoke-Manager @(
        'start', '--cycle', (Join-Path $tempRoot 'negative-portable-approval/review-cycle.json'),
        '--repository', $repository, '--pr', [string]$pullRequest, '--goal-context-path', $goalContextPath,
        '--goal-context-sha', $goalContextSha, '--base-oid', $baseOid,
        '--head-oid', '2323232323232323232323232323232323232323', '--started-at', '2026-01-02T02:03:00Z',
        '--thread-mode', 'portable-handoff', '--review-thread-id', $reviewThreadId, '--format', 'json'
    ) 'portable handoff without approval' $false 'portable-handoff requires' | Out-Null
    foreach ($round in 1..3) {
        if (-not (Test-Path -LiteralPath (Join-Path $convergenceRoot ('round-{0:000}' -f $round)))) {
            Add-Failure "Convergence artifact directory is missing for round $round"
        }
    }

    $modeMismatchRoot = Join-Path $tempRoot 'negative-review-mode-mismatch'
    Copy-Item -LiteralPath $convergenceRoot -Destination $modeMismatchRoot -Recurse
    $modeMismatchCycle = Join-Path $modeMismatchRoot 'review-cycle.json'
    $modeMismatchJson = Get-Content -Raw -LiteralPath $modeMismatchCycle | ConvertFrom-Json -Depth 100
    $modeMismatchJson.rounds[1].reviewMode = 'full'
    [System.IO.File]::WriteAllText($modeMismatchCycle, (($modeMismatchJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Invoke-Manager @('validate', '--cycle', $modeMismatchCycle, '--format', 'json') 'round review mode mismatch' $false 'round review mode mismatch' | Out-Null

    $localArtifactRoot = Join-Path $tempRoot 'negative-purpose-only-local-artifact'
    Copy-Item -LiteralPath $convergenceRoot -Destination $localArtifactRoot -Recurse
    $localArtifactCycle = Join-Path $localArtifactRoot 'review-cycle.json'
    $localPath = Join-Path $localArtifactRoot 'round-002/local-review-findings.md'
    [System.IO.File]::WriteAllText($localPath, "# Local Review Findings`n", $utf8)
    $localArtifactJson = Get-Content -Raw -LiteralPath $localArtifactCycle | ConvertFrom-Json -Depth 100
    $localArtifactJson.rounds[1].artifacts = @($localArtifactJson.rounds[1].artifacts) + @([pscustomobject]@{
        role = 'local-findings'; path = 'round-002/local-review-findings.md'; normalizedSha256 = Get-NormalizedSha256 $localPath
    })
    [System.IO.File]::WriteAllText($localArtifactCycle, (($localArtifactJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Invoke-Manager @('validate', '--cycle', $localArtifactCycle, '--format', 'json') 'purpose-only local artifact' $false 'must not include local-findings' | Out-Null

    $externalMappingRoot = Join-Path $tempRoot 'negative-purpose-only-external-mapping'
    Copy-Item -LiteralPath $convergenceRoot -Destination $externalMappingRoot -Recurse
    $externalMappingCycle = Join-Path $externalMappingRoot 'review-cycle.json'
    $externalMappingJson = Get-Content -Raw -LiteralPath $externalMappingCycle | ConvertFrom-Json -Depth 100
    $externalEntry = @($externalMappingJson.rounds[1].sourceCoverage | Where-Object sourceId -eq 'review:1001')[0]
    $externalEntry.disposition = 'finding'
    $externalEntry.trackingIds = @('TRK-A')
    $externalEntry.reason = $null
    [System.IO.File]::WriteAllText($externalMappingCycle, (($externalMappingJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Invoke-Manager @('validate', '--cycle', $externalMappingCycle, '--format', 'json') 'purpose-only external source mapping' $false 'Source-to-tracking mapping mismatch' | Out-Null

    $assessmentRoot = Join-Path $tempRoot 'negative-prior-assessment'
    Copy-Item -LiteralPath $convergenceRoot -Destination $assessmentRoot -Recurse
    $assessmentCycle = Join-Path $assessmentRoot 'review-cycle.json'
    $assessmentPurpose = Join-Path $assessmentRoot 'round-002/purpose-review-findings.md'
    $assessmentContent = Get-Content -Raw -LiteralPath $assessmentPurpose
    $assessmentContent = [regex]::Replace($assessmentContent, '(?m)^\| TRK-A \|.*\r?\n', '')
    [System.IO.File]::WriteAllText($assessmentPurpose, $assessmentContent.Replace("`r`n", "`n"), $utf8)
    $assessmentReviewResult = Join-Path $assessmentRoot 'round-002/review-result.json'
    $assessmentReviewJson = Get-Content -Raw -LiteralPath $assessmentReviewResult | ConvertFrom-Json -Depth 100
    (@($assessmentReviewJson.artifactBindings | Where-Object role -eq 'purpose-findings')[0]).normalizedSha256 = Get-NormalizedSha256 $assessmentPurpose
    [System.IO.File]::WriteAllText($assessmentReviewResult, (($assessmentReviewJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    $assessmentCycleJson = Get-Content -Raw -LiteralPath $assessmentCycle | ConvertFrom-Json -Depth 100
    (@($assessmentCycleJson.rounds[1].artifacts | Where-Object role -eq 'purpose-findings')[0]).normalizedSha256 = Get-NormalizedSha256 $assessmentPurpose
    (@($assessmentCycleJson.rounds[1].artifacts | Where-Object role -eq 'review-result')[0]).normalizedSha256 = Get-NormalizedSha256 $assessmentReviewResult
    [System.IO.File]::WriteAllText($assessmentCycle, (($assessmentCycleJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Invoke-Manager @('validate', '--cycle', $assessmentCycle, '--format', 'json') 'missing prior finding assessment' $false 'Prior Finding Assessment coverage mismatch' | Out-Null

    $legacyRoot = Join-Path $tempRoot 'negative-legacy-append'
    Copy-Item -LiteralPath $convergenceRoot -Destination $legacyRoot -Recurse
    $legacyCycle = Join-Path $legacyRoot 'review-cycle.json'
    $legacyJson = Get-Content -Raw -LiteralPath $legacyCycle | ConvertFrom-Json -Depth 100
    $legacyJson.schemaVersion = 1
    [System.IO.File]::WriteAllText($legacyCycle, (($legacyJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Start-Round -CyclePath $legacyCycle -HeadOid '9898989898989898989898989898989898989898' -StartedAt '2026-01-01T00:07:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ExpectSuccess $false -ExpectedPattern 'read-only historical evidence'

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
        $findingId = if ($round -eq 1) { 'LR-101' } else { "PUR-10$round" }
        $sourceId = if ($round -eq 1) { 'review:limit:1' } else { $findingId }
        $expectedVerdict = if ($round -eq 3) { 'HUMAN_DECISION_REQUIRED' } else { 'READY_FOR_ADAPTIVE_IMPLEMENTATION' }
        $wrongVerdict = if ($round -eq 3) { 'READY_FOR_ADAPTIVE_IMPLEMENTATION' } else { $expectedVerdict }
        $result = Write-RoundResult $limitRoot $round $limitHeads[$round - 1] "2026-02-01T00:0$($round * 2 + 1):00Z" $wrongVerdict @(
            (New-Delta 'TRK-LIMIT' $state @($findingId) @($sourceId))
        ) $true
        if ($round -eq 3) {
            Complete-Round $limitCycle $result $false 'round-result verdict mismatch'
            $result = Write-RoundResult $limitRoot $round $limitHeads[$round - 1] '2026-02-01T00:07:00Z' $expectedVerdict @(
                (New-Delta 'TRK-LIMIT' $state @('PUR-103') @('PUR-103'))
            ) $true
            Complete-Round $limitCycle $result $false 'must not include an executable Adaptive review-plan artifact'
            Remove-Item -LiteralPath (Join-Path $limitRoot 'round-003/review-plan.md') -Force
            $result = Write-RoundResult $limitRoot $round $limitHeads[$round - 1] '2026-02-01T00:07:00Z' $expectedVerdict @(
                (New-Delta 'TRK-LIMIT' $state @('PUR-103') @('PUR-103'))
            ) $false
        }
        Complete-Round $limitCycle $result
    }
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:08:00Z' -AdaptiveResult 'adaptive/round-003/result.md' -ExpectSuccess $false -ExpectedPattern 'must be resolved with a validated approved plan'
    $limitDelta = @((New-Delta 'TRK-LIMIT' 'persistent' @('PUR-103') @('PUR-103')))
    Resolve-HumanDecision $limitCycle 3 $limitHeads[2] $limitDelta 'HD-999' '2026-02-01T00:08:00Z' 4 -ExpectSuccess $false -ExpectedPattern 'resolved human decision ID mismatch'
    Resolve-HumanDecision -CyclePath $limitCycle -RoundNumber 3 -HeadOid $limitHeads[2] -FindingDelta $limitDelta -DecisionId 'HD-003' -ApprovedAt '2026-02-01T00:08:00Z' -IncompleteDecision -ExpectSuccess $false -ExpectedPattern 'resolve requires cycle'
    Resolve-HumanDecision -CyclePath $limitCycle -RoundNumber 3 -HeadOid $limitHeads[2] -FindingDelta $limitDelta -DecisionId 'HD-003' -ApprovedAt '2026-02-01T00:08:00Z' -OmitApprovedPlan -ExpectSuccess $false -ExpectedPattern 'resolve requires cycle'
    Resolve-HumanDecision -CyclePath $limitCycle -RoundNumber 3 -HeadOid $limitHeads[2] -FindingDelta $limitDelta -DecisionId 'HD-003' -ApprovedAt '2026-02-01T00:08:00Z' -OverrideMaximum 4 -IncludeAdaptiveResult -ExpectSuccess $false -ExpectedPattern 'before Adaptive execution and cannot accept an Adaptive result reference'
    Resolve-HumanDecision $limitCycle 3 $limitHeads[2] $limitDelta 'HD-003' '2026-02-01T00:08:00Z' -ExpectSuccess $false -ExpectedPattern 'requires a complete maximum-round override'
    Resolve-HumanDecision -CyclePath $limitCycle -RoundNumber 3 -HeadOid $limitHeads[2] -FindingDelta $limitDelta -DecisionId 'HD-003' -ApprovedAt '2026-02-01T00:08:00Z' -OverrideMaximum 4 -IncompleteOverride -ExpectSuccess $false -ExpectedPattern 'All maximum-round override fields'
    Resolve-HumanDecision -CyclePath $limitCycle -RoundNumber 3 -HeadOid $limitHeads[2] -FindingDelta $limitDelta -DecisionId 'HD-003' -ApprovedAt '2026-02-01T00:08:00Z' -OverrideMaximum 4 -RemoveHandoff -ExpectSuccess $false -ExpectedPattern 'missing a non-empty.*Explicit Implementation Turn Handoff'
    Resolve-HumanDecision $limitCycle 3 $limitHeads[2] $limitDelta 'HD-003' '2026-02-01T00:08:00Z' 4
    $approvedLimit = Get-Content -Raw -LiteralPath $limitCycle | ConvertFrom-Json -Depth 100
    if (($approvedLimit.status -ne 'APPROVED_FOR_ADAPTIVE_IMPLEMENTATION') -or
        ($approvedLimit.humanDecisions[0].status -ne 'RESOLVED') -or
        (-not (Test-Path -LiteralPath (Join-Path $limitRoot 'round-003/approved-review-plan.md')))) {
        Add-Failure 'Human decision did not create a gated approved Adaptive plan before round 4 start.'
    }
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:07:30Z' -AdaptiveResult 'adaptive/round-003/result.md' -ExpectSuccess $false -ExpectedPattern 'precedes the human decision approval'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:09:00Z' -ExpectSuccess $false -ExpectedPattern 'requires --adaptive-result-reference'
    Start-Round -CyclePath $limitCycle -HeadOid $limitHeads[3] -StartedAt '2026-02-01T00:09:00Z' -AdaptiveResult 'adaptive/round-003/result.md'
    $r4 = Write-RoundResult $limitRoot 4 $limitHeads[3] '2026-02-01T00:10:00Z' 'REVIEW_COMPLETE' @(
        (New-Delta 'TRK-LIMIT' 'resolved' @() @())
    ) $false
    Complete-Round $limitCycle $r4
    $expectedLimit = @($fixture.scenarios | Where-Object id -eq 'round-limit-and-override').expectedVerdicts
    Assert-CycleVerdicts $limitCycle $expectedLimit 'round limit and override'
    $limit = Get-Content -Raw -LiteralPath $limitCycle | ConvertFrom-Json -Depth 100
    if ($limit.effectiveMaximumRounds -ne 4 -or $limit.overrides.Count -ne 1 -or $limit.overrides[0].approvedBy -ne 'fixture-human') {
        Add-Failure 'Round 4 override evidence is incomplete.'
    }
    $approvedTamperRoot = Join-Path $tempRoot 'tampered-approved-plan'
    Copy-Item -LiteralPath $limitRoot -Destination $approvedTamperRoot -Recurse
    [System.IO.File]::AppendAllText((Join-Path $approvedTamperRoot 'round-003/approved-review-plan.md'), "tamper`n", $utf8)
    Invoke-Manager @('validate', '--cycle', (Join-Path $approvedTamperRoot 'review-cycle.json'), '--format', 'json') 'approved plan mutation' $false 'approved plan hash.*mismatch' | Out-Null

    # A non-limit human decision also requires an explicit matching resolution before the next round.
    $humanRoot = Join-Path $tempRoot 'human-decision'
    $humanCycle = Join-Path $humanRoot 'review-cycle.json'
    $humanHead1 = '7878787878787878787878787878787878787878'
    $humanHead2 = '7979797979797979797979797979797979797979'
    Start-Round $humanCycle $humanHead1 '2026-02-02T00:00:00Z'
    $humanResult1 = Write-RoundResult -CycleRoot $humanRoot -RoundNumber 1 -HeadOid $humanHead1 -CompletedAt '2026-02-02T00:01:00Z' -Verdict 'HUMAN_DECISION_REQUIRED' -FindingDelta @(
        (New-Delta 'TRK-HUMAN' 'new' @('PUR-150') @('pr-comment:human:1'))
    ) -IncludePlan $false -HumanDecisionReason 'Human scope choice is required.'
    Complete-Round $humanCycle $humanResult1
    Start-Round -CyclePath $humanCycle -HeadOid $humanHead2 -StartedAt '2026-02-02T00:02:00Z' -AdaptiveResult 'adaptive/round-001/result.md' -ExpectSuccess $false -ExpectedPattern 'must be resolved with a validated approved plan'
    $humanDelta = @((New-Delta 'TRK-HUMAN' 'new' @('PUR-150') @('pr-comment:human:1')))
    Resolve-HumanDecision $humanCycle 1 $humanHead1 $humanDelta 'HD-001' '2026-02-02T00:02:00Z'
    Start-Round -CyclePath $humanCycle -HeadOid $humanHead2 -StartedAt '2026-02-02T00:03:00Z' -AdaptiveResult 'adaptive/round-001/result.md'
    $humanResult2 = Write-RoundResult $humanRoot 2 $humanHead2 '2026-02-02T00:04:00Z' 'REVIEW_COMPLETE' @(
        (New-Delta 'TRK-HUMAN' 'resolved' @() @())
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
        (New-Delta 'TRK-REOPEN' 'resolved' @() @()),
        (New-Delta 'TRK-KEEP' 'persistent' @('PUR-202') @('PUR-202'))
    ) $true)
    Start-Round $reopenCycle $reopenHeads[2] '2026-03-01T00:04:00Z' 'adaptive/round-002/result.md'
    Complete-Round $reopenCycle (Write-RoundResult $reopenRoot 3 $reopenHeads[2] '2026-03-01T00:05:00Z' 'HUMAN_DECISION_REQUIRED' @(
        (New-Delta 'TRK-REOPEN' 'reopened' @('PUR-203') @('PUR-203')),
        (New-Delta 'TRK-KEEP' 'resolved' @() @())
    ) $false)
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
    Complete-Round $noPlanCycle $noPlanResult $false 'requires a review-plan'

    $emptyPlanRoot = Join-Path $tempRoot 'negative-empty-plan'
    $emptyPlanCycle = Join-Path $emptyPlanRoot 'review-cycle.json'
    Start-Round $emptyPlanCycle 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' '2026-04-03T00:00:00Z'
    $emptyPlanResult = Write-RoundResult $emptyPlanRoot 1 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' '2026-04-03T00:01:00Z' 'REVIEW_COMPLETE' @() $true
    Complete-Round $emptyPlanCycle $emptyPlanResult $false 'must not include an executable Adaptive review-plan'

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
        (New-Delta 'TRK-BAD-REOPEN' 'reopened' @('PUR-308') @('PUR-308'))
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
    $selectionJson = Get-Content -Raw -LiteralPath $selectionPath | ConvertFrom-Json -Depth 100
    $selectionJson.schemaVersion = 1
    [System.IO.File]::WriteAllText($selectionPath, (($selectionJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @('goal-context-selection')
    Complete-Round $contentCycle $contentResult $false 'Goal Context selection schema version mismatch'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $selectionJson = Get-Content -Raw -LiteralPath $selectionPath | ConvertFrom-Json -Depth 100
    $selectionJson.lifecycleStatus = 'draft'
    [System.IO.File]::WriteAllText($selectionPath, (($selectionJson | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @('goal-context-selection')
    Complete-Round $contentCycle $contentResult $false 'strict Goal Context lifecycle mismatch'

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

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true -ReviewSources @(
        [ordered]@{ id = 1401; sourceId = 'review:content:1'; state = 'COMMENTED'; commit_id = 'not-a-git-oid'; body = 'Malformed source identity.' }
    )
    Complete-Round $contentCycle $contentResult $false 'commit_id must be a lowercase 40-character Git OID'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $alternatePatch = Join-Path $contentRoot 'round-001/alternate.patch'
    [System.IO.File]::WriteAllText($alternatePatch, "diff --git a/unrelated.txt b/unrelated.txt`n", $utf8)
    $remotePatchResult = Get-Content -Raw -LiteralPath $contentResult | ConvertFrom-Json -Depth 100
    $remotePatchArtifact = $remotePatchResult.artifacts | Where-Object role -eq 'remote-patch'
    $remotePatchArtifact.path = 'round-001/alternate.patch'
    $remotePatchArtifact.normalizedSha256 = Get-NormalizedSha256 $alternatePatch
    [System.IO.File]::WriteAllText($contentResult, (($remotePatchResult | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n"), $utf8)
    Sync-MutatedArtifactHashes $contentResult @('remote-patch')
    Complete-Round $contentCycle $contentResult $false 'review-context remote patch path mismatch'

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

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $planContent = [System.IO.File]::ReadAllText($planPath).Replace('  non_goals:', "    - SI-999: Perform an untracked refactor.`n  non_goals:")
    [System.IO.File]::WriteAllText($planPath, $planContent, $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-plan')
    Complete-Round $contentCycle $contentResult $false 'scope ID sets must match exactly'

    $contentResult = Write-RoundResult $contentRoot 1 $contentHead '2026-04-06T00:01:00Z' 'READY_FOR_ADAPTIVE_IMPLEMENTATION' $contentDelta $true
    $planContent = [System.IO.File]::ReadAllText($planPath).Replace('  constraints:', "    - AC-999: Accept an untracked behavior.`n  constraints:")
    [System.IO.File]::WriteAllText($planPath, $planContent, $utf8)
    Sync-MutatedArtifactHashes $contentResult @('review-plan')
    Complete-Round $contentCycle $contentResult $false 'acceptance ID sets must match exactly'

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
        (New-Delta 'TRK-PRESENT' 'persistent' @('PUR-305') @('PUR-305'))
    ) $true
    Complete-Round $missingCycle $missingResult $false 'missing persistent/resolved mapping'

    $observedMutations = @($fixture.negativeMutations)
    foreach ($required in @('duplicate-head', 'missing-adaptive-result-reference', 'identity-drift', 'existing-round-directory', 'historical-artifact-hash', 'unknown-persistent-finding', 'missing-active-finding-mapping', 'round-limit-verdict', 'incomplete-override', 'actionable-without-plan', 'review-complete-with-plan', 'missing-source-coverage', 'source-tracking-swap', 'invalid-reopened-transition', 'round-result-head-identity', 'notification-status', 'notification-pr', 'early-override', 'unresolved-human-decision', 'adaptive-before-decision', 'resolve-with-adaptive-result', 'start-before-decision-approval', 'wrong-human-decision-id', 'human-decision-with-plan', 'resolution-missing-approved-plan', 'approved-plan-missing-handoff', 'approved-plan-hash', 'review-context-content', 'goal-context-selection-content', 'goal-context-selection-schema', 'goal-context-selection-lifecycle', 'review-result-content', 'uncovered-artifact-source', 'malformed-source-oid', 'remote-patch-binding', 'review-plan-intent', 'review-plan-acceptance', 'review-plan-finding-mapping', 'intent-extra-scope', 'intent-extra-acceptance', 'non-iso-timestamp', 'missing-timestamp-offset', 'cycle-root-link-escape', 'cycle-file-link-escape', 'round-directory-link-escape', 'artifact-file-link-escape', 'review-mode-mismatch', 'purpose-only-local-artifact', 'purpose-only-external-mapping', 'missing-prior-finding-assessment', 'legacy-cycle-append', 'review-thread-mismatch', 'implementation-thread-mismatch', 'same-role-thread', 'missing-thread-id', 'malformed-thread-id', 'incomplete-thread-rebind', 'thread-history-overwrite', 'portable-without-approval')) {
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
