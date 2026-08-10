[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot,

    [Parameter()]
    [string]$EvidenceRoot,

    [Parameter()]
    [string]$CodexCommand = 'codex',

    [Parameter()]
    [switch]$DescribePayload,

    [Parameter()]
    [switch]$ConfirmExternalModelPayload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    $normalized = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-TextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $normalized = $Text.Replace("`r`n", "`n").Trim()
    $bytes = [Text.Encoding]::UTF8.GetBytes($normalized)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-RelativePathText {
    param(
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Path
    )
    [IO.Path]::GetRelativePath($Base, $Path).Replace('\', '/')
}

function Read-AgentProfile {
    param([Parameter(Mandatory)][string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    $name = [regex]::Match($text, '(?m)^name\s*=\s*"([^"]+)"\s*$').Groups[1].Value
    $model = [regex]::Match($text, '(?m)^model\s*=\s*"([^"]+)"\s*$').Groups[1].Value
    $effort = [regex]::Match($text, '(?m)^model_reasoning_effort\s*=\s*"([^"]+)"\s*$').Groups[1].Value
    $sandbox = [regex]::Match($text, '(?m)^sandbox_mode\s*=\s*"([^"]+)"\s*$').Groups[1].Value
    $instructions = [regex]::Match(
        $text,
        '(?s)developer_instructions\s*=\s*"""\s*(.*?)\s*"""'
    ).Groups[1].Value

    if (@($name, $model, $effort, $sandbox, $instructions) -contains '') {
        throw "Unable to parse the canonical profile: $Path"
    }

    [pscustomobject]@{
        Name = $name
        Model = $model
        ReasoningEffort = $effort
        SandboxMode = $sandbox
        DeveloperInstructions = $instructions
        ProfileSha256 = Get-Sha256 $Path
        DeveloperInstructionsSha256 = Get-TextSha256 $instructions
    }
}

function Get-GitState {
    param([Parameter(Mandatory)][string]$Root)
    [ordered]@{
        head = (& git -C $Root rev-parse HEAD).Trim()
        tree = (& git -C $Root rev-parse 'HEAD^{tree}').Trim()
        status = ((& git -C $Root status --porcelain=v1) -join "`n")
    }
}

function Find-RolloutFile {
    param([Parameter(Mandatory)][string]$ThreadId)

    $configuredStateRoot = [Environment]::GetEnvironmentVariable('CODEX_HOME')
    $stateRoot = if ([string]::IsNullOrWhiteSpace($configuredStateRoot)) {
        Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
    } else {
        $configuredStateRoot
    }
    $sessionsRoot = Join-Path $stateRoot 'sessions'
    if (-not (Test-Path -LiteralPath $sessionsRoot)) {
        throw "Codex session directory was not found: $sessionsRoot"
    }

    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        $file = Get-ChildItem -LiteralPath $sessionsRoot -Recurse -File -Filter "*$ThreadId.jsonl" |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $file) {
            return $file.FullName
        }
        Start-Sleep -Milliseconds 100
    }
    throw "Persisted Codex rollout was not found for thread $ThreadId. Do not use --ephemeral for this smoke."
}

function Read-RolloutEvidence {
    param(
        [Parameter(Mandatory)][string]$ThreadId,
        [Parameter(Mandatory)][pscustomobject]$Profile,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$ContractPath,
        [Parameter(Mandatory)][Collections.IDictionary]$GitBefore,
        [Parameter(Mandatory)][Collections.IDictionary]$GitAfter
    )

    $rolloutPath = Find-RolloutFile $ThreadId
    $records = @(Get-Content -LiteralPath $rolloutPath | ForEach-Object { $_ | ConvertFrom-Json })
    $session = $records | Where-Object { $_.type -eq 'session_meta' -and $_.payload.id -eq $ThreadId } | Select-Object -First 1
    $turn = $records | Where-Object { $_.type -eq 'turn_context' } | Select-Object -Last 1
    $usageEvent = $records |
        Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'token_count' } |
        Select-Object -Last 1
    $complete = $records |
        Where-Object { $_.type -eq 'event_msg' -and $_.payload.type -eq 'task_complete' } |
        Select-Object -Last 1
    $developerTexts = @(
        $records |
            Where-Object { $_.type -eq 'response_item' -and $_.payload.type -eq 'message' -and $_.payload.role -eq 'developer' } |
            ForEach-Object { $_.payload.content } |
            Where-Object { $_.type -eq 'input_text' } |
            ForEach-Object { $_.text }
    )
    $actualInstructions = $developerTexts |
        Where-Object { (Get-TextSha256 $_) -eq $Profile.DeveloperInstructionsSha256 } |
        Select-Object -First 1
    $spawnObserved = $records | Where-Object {
        $_.type -eq 'response_item' -and
        $_.payload.type -eq 'function_call' -and
        $_.payload.name -eq 'spawn_agent'
    }

    if ($null -eq $session -or $null -eq $turn -or $null -eq $usageEvent -or $null -eq $complete) {
        throw "Rollout $ThreadId does not contain the required session, turn, usage, and completion evidence."
    }
    if ($null -eq $actualInstructions) {
        throw "Rollout $ThreadId does not prove that the canonical developer instructions were loaded."
    }
    if ($spawnObserved) {
        throw "Rollout $ThreadId unexpectedly invoked spawn_agent. This smoke must stop after direct profile execution."
    }
    if ($turn.payload.model -ne $Profile.Model -or $turn.payload.effort -ne $Profile.ReasoningEffort) {
        throw "Rollout $ThreadId used a different model or reasoning effort than the canonical profile."
    }
    if ($turn.payload.sandbox_policy.type -ne $Profile.SandboxMode) {
        throw "Rollout $ThreadId used a different sandbox than the canonical profile."
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "Codex did not create the requested last-message artifact: $OutputPath"
    }

    $usage = $usageEvent.payload.info.total_token_usage
    [ordered]@{
        configuredAgent = $Profile.Name
        observedExecution = 'top-level-codex-exec:/root'
        profileSha256 = $Profile.ProfileSha256
        contractSha256 = Get-Sha256 $ContractPath
        developerInstructionsSha256 = $Profile.DeveloperInstructionsSha256
        sessionId = $session.payload.id
        turnId = $turn.payload.turn_id
        codexCliVersion = $session.payload.cli_version
        model = $turn.payload.model
        reasoningEffort = $turn.payload.effort
        sandboxMode = $turn.payload.sandbox_policy.type
        durationMs = [int64]$complete.payload.duration_ms
        usage = [ordered]@{
            inputTokens = [int64]$usage.input_tokens
            cachedInputTokens = [int64]$usage.cached_input_tokens
            outputTokens = [int64]$usage.output_tokens
            reasoningOutputTokens = [int64]$usage.reasoning_output_tokens
            totalTokens = [int64]$usage.total_tokens
        }
        outputPath = $null
        outputSha256 = Get-Sha256 $OutputPath
        gitBefore = $GitBefore
        gitAfter = $GitAfter
    }
}

function Invoke-CanonicalProfile {
    param(
        [Parameter(Mandatory)][pscustomobject]$Profile,
        [Parameter(Mandatory)][string]$ContractPath,
        [Parameter(Mandatory)][string]$ScratchRoot,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$ErrorPath
    )

    $before = Get-GitState $ScratchRoot
    if ($before.status -ne '') {
        throw "Scratch repository must be clean before invoking $($Profile.Name)."
    }

    $configArguments = @(
        "model_reasoning_effort=`"$($Profile.ReasoningEffort)`"",
        ('developer_instructions=' + $Profile.DeveloperInstructions)
    )
    $arguments = @(
        'exec',
        '--json',
        '--strict-config',
        '--ignore-user-config',
        '-C', $ScratchRoot,
        '-m', $Profile.Model,
        '-s', $Profile.SandboxMode,
        '-c', $configArguments[0],
        '-c', $configArguments[1],
        '-o', $OutputPath,
        $Prompt
    )

    $stdout = @(& $CodexCommand @arguments 2> $ErrorPath)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $errorText = if (Test-Path -LiteralPath $ErrorPath) {
            (Get-Content -LiteralPath $ErrorPath | Select-Object -First 20) -join "`n"
        } else {
            'No stderr was captured.'
        }
        throw "Codex direct execution failed for $($Profile.Name) with exit code $exitCode.`n$errorText"
    }

    $events = @($stdout | Where-Object { $_.TrimStart().StartsWith('{') } | ForEach-Object { $_ | ConvertFrom-Json })
    $thread = $events | Where-Object { $_.type -eq 'thread.started' } | Select-Object -First 1
    $completed = $events | Where-Object { $_.type -eq 'turn.completed' } | Select-Object -Last 1
    $errors = @($events | Where-Object {
        $_.type -eq 'error' -or
        (($_.PSObject.Properties.Name -contains 'item') -and $_.item.type -eq 'error')
    })
    if ($null -eq $thread -or $null -eq $completed -or $errors.Count -gt 0) {
        throw "Codex JSONL did not prove a clean completed turn for $($Profile.Name)."
    }

    $after = Get-GitState $ScratchRoot
    if ($before.head -ne $after.head -or $before.tree -ne $after.tree -or $after.status -ne '') {
        throw "$($Profile.Name) changed the scratch repository."
    }

    Read-RolloutEvidence `
        -ThreadId $thread.thread_id `
        -Profile $Profile `
        -OutputPath $OutputPath `
        -ContractPath $ContractPath `
        -GitBefore $before `
        -GitAfter $after
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
$fixtureRoot = Join-Path $RepositoryRoot 'tests\pr-review-remediation\PRR-001'
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = $fixtureRoot
} else {
    $EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
}

$localProfilePath = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\codex-agents\local-reviewer.toml'
$plannerProfilePath = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\codex-agents\review-planner.toml'
$localContractPath = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\agents\local-reviewer.agent.md'
$plannerContractPath = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\agents\review-planner.agent.md'
$localTemplatePath = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\skills\pr-review-remediation\templates\local-review-findings.md'
$plannerTemplatePath = Join-Path $RepositoryRoot 'apm-packages\pr-review-remediation\.apm\skills\pr-review-remediation\templates\review-plan.md'
$localPromptPath = Join-Path $fixtureRoot 'prompt-local-reviewer.txt'
$plannerPromptPath = Join-Path $fixtureRoot 'prompt-review-planner.txt'
$fixtureSource = Join-Path $fixtureRoot 'fixture'

$staticPayloadFiles = @(
    (Join-Path $fixtureSource 'AGENTS.md'),
    (Join-Path $fixtureSource 'README.md'),
    (Join-Path $fixtureSource 'src\Fixture.cs'),
    (Join-Path $fixtureSource '.review\pr-123\review-context.json'),
    (Join-Path $fixtureSource '.review\pr-123\pr-diff.patch'),
    $localPromptPath,
    $plannerPromptPath,
    $localContractPath,
    $plannerContractPath,
    $localProfilePath,
    $plannerProfilePath,
    $localTemplatePath,
    $plannerTemplatePath
)
foreach ($path in $staticPayloadFiles) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required smoke input is missing: $path"
    }
}

Write-Host 'The following file contents will be available to or supplied to the configured external Codex model service:'
$staticPayloadFiles | ForEach-Object { Write-Host "- $(Get-RelativePathText $RepositoryRoot $_)" }
Write-Host '- generated local-review-findings.md from the first model run'
Write-Host '- isolated fixture Git metadata returned by read-only tool calls'
if ($DescribePayload) {
    Write-Host 'Payload description complete. No model was invoked.'
    return
}
if (-not $ConfirmExternalModelPayload) {
    throw 'HUMAN_DECISION_REQUIRED: rerun with -ConfirmExternalModelPayload only after the operator authorizes this external model payload.'
}

$localProfile = Read-AgentProfile $localProfilePath
$plannerProfile = Read-AgentProfile $plannerProfilePath
if ($localProfile.Name -ne 'local-reviewer' -or $plannerProfile.Name -ne 'review-planner') {
    throw 'Canonical profile names do not match the expected smoke sequence.'
}
foreach ($profile in @($localProfile, $plannerProfile)) {
    if ($profile.Model -ne 'gpt-5.6-terra' -or
        $profile.ReasoningEffort -ne 'high' -or
        $profile.SandboxMode -ne 'read-only') {
        throw "Canonical profile $($profile.Name) does not use gpt-5.6-terra/high/read-only."
    }
}

$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$scratchParent = Join-Path $tempBase ("pr-review-remediation-agent-smoke-" + [guid]::NewGuid().ToString('N'))
$scratchRoot = Join-Path $scratchParent 'repository'
$stagingRoot = Join-Path $scratchParent 'evidence'
$startedAt = [DateTimeOffset]::UtcNow

try {
    New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $fixtureSource -Force | Copy-Item -Destination $scratchRoot -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $scratchRoot '.github\agents') -Force | Out-Null
    Copy-Item -LiteralPath $localContractPath -Destination (Join-Path $scratchRoot '.github\agents\local-reviewer.agent.md')
    Copy-Item -LiteralPath $plannerContractPath -Destination (Join-Path $scratchRoot '.github\agents\review-planner.agent.md')
    New-Item -ItemType Directory -Path (Join-Path $scratchRoot 'templates') -Force | Out-Null
    Copy-Item -LiteralPath $localTemplatePath -Destination (Join-Path $scratchRoot 'templates\local-review-findings.md')
    Copy-Item -LiteralPath $plannerTemplatePath -Destination (Join-Path $scratchRoot 'templates\review-plan.md')

    & git -C $scratchRoot init | Out-Null
    & git -C $scratchRoot add .
    & git -C $scratchRoot -c user.name='Codex Fixture' -c user.email='fixture@example.invalid' commit -m 'fixture baseline' | Out-Null

    $localOutput = Join-Path $stagingRoot 'local-review-findings.md'
    $localRun = Invoke-CanonicalProfile `
        -Profile $localProfile `
        -ContractPath $localContractPath `
        -ScratchRoot $scratchRoot `
        -Prompt (Get-Content -LiteralPath $localPromptPath -Raw) `
        -OutputPath $localOutput `
        -ErrorPath (Join-Path $stagingRoot 'local-reviewer.stderr.log')
    $localText = Get-Content -LiteralPath $localOutput -Raw
    if ($localText -notmatch 'Verdict:\s*REVIEWED' -or
        $localText -notmatch 'LR-\d{3}' -or
        $localText -notmatch 'Production code changed:\s*No') {
        throw 'local-reviewer output does not satisfy the smoke contract.'
    }

    $scratchLocalOutput = Join-Path $scratchRoot '.review\pr-123\local-review-findings.md'
    Copy-Item -LiteralPath $localOutput -Destination $scratchLocalOutput
    & git -C $scratchRoot add '.review/pr-123/local-review-findings.md'
    & git -C $scratchRoot -c user.name='Codex Fixture' -c user.email='fixture@example.invalid' commit -m 'add local review input' | Out-Null

    $plannerOutput = Join-Path $stagingRoot 'review-plan.md'
    $plannerRun = Invoke-CanonicalProfile `
        -Profile $plannerProfile `
        -ContractPath $plannerContractPath `
        -ScratchRoot $scratchRoot `
        -Prompt (Get-Content -LiteralPath $plannerPromptPath -Raw) `
        -OutputPath $plannerOutput `
        -ErrorPath (Join-Path $stagingRoot 'review-planner.stderr.log')
    $plannerText = Get-Content -LiteralPath $plannerOutput -Raw
    $localIds = @([regex]::Matches($localText, '\bLR-\d{3}\b') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    foreach ($sourceId in @($localIds + @('100', '1001', '501'))) {
        if ($plannerText -notmatch ('(?<!\d)' + [regex]::Escape($sourceId) + '(?!\d)')) {
            throw "review-planner output omitted source ID $sourceId."
        }
    }
    foreach ($requiredPattern in @(
        'Verdict:\s*READY_FOR_ADAPTIVE_IMPLEMENTATION',
        'Production code changed:\s*No',
        'implementation_intent:',
        '(?m)^\s*goal:',
        '(?m)^\s*scope:',
        '(?m)^\s*acceptance:',
        '\$adaptive-implementation-execution'
    )) {
        if ($plannerText -notmatch $requiredPattern) {
            throw "review-planner output is missing required pattern: $requiredPattern"
        }
    }

    New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
    $finalLocalOutput = Join-Path $EvidenceRoot 'local-review-findings.md'
    $finalPlannerOutput = Join-Path $EvidenceRoot 'review-plan.md'
    Copy-Item -LiteralPath $localOutput -Destination $finalLocalOutput -Force
    Copy-Item -LiteralPath $plannerOutput -Destination $finalPlannerOutput -Force
    $localRun.outputPath = Get-RelativePathText $RepositoryRoot $finalLocalOutput
    $plannerRun.outputPath = Get-RelativePathText $RepositoryRoot $finalPlannerOutput

    $inputFiles = @($staticPayloadFiles | ForEach-Object {
        [ordered]@{
            path = Get-RelativePathText $RepositoryRoot $_
            sha256 = Get-Sha256 $_
        }
    })
    $inputFiles += [ordered]@{
        path = Get-RelativePathText $RepositoryRoot $finalLocalOutput
        sha256 = Get-Sha256 $finalLocalOutput
    }

    $run = [ordered]@{
        schemaVersion = '1.0'
        evidenceId = 'PRR-001'
        runId = [guid]::NewGuid().ToString()
        status = 'PASS'
        executionMode = 'canonical-profile-direct-execution'
        customAgentSpawnObserved = $false
        externalModelPayloadConfirmed = $true
        startedAtUtc = $startedAt.ToString('O')
        completedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        inputFiles = $inputFiles
        runs = @($localRun, $plannerRun)
        assertions = [ordered]@{
            agentOrder = $true
            allFindingsDecided = $true
            allAppliedFindingsMapped = $true
            adaptiveIntentReady = $true
            productionCodeChanged = $false
            adaptiveAgentStarted = $false
            phaseOneStoppedAfterPlanning = $true
        }
    }
    $run | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'run.json') -Encoding utf8
    Write-Host "PRR-001 agent smoke: PASS ($EvidenceRoot)"
}
finally {
    $resolvedScratchParent = [IO.Path]::GetFullPath($scratchParent)
    if ($resolvedScratchParent.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedScratchParent)) {
        Remove-Item -LiteralPath $resolvedScratchParent -Recurse -Force
    }
}
