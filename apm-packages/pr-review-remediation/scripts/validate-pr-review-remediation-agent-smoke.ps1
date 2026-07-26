[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot,

    [Parameter()]
    [string]$EvidenceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    $failures.Add($Message)
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-Sha256 {
    param([object]$Value)
    $null -ne $Value -and $Value.ToString() -match '^[0-9a-f]{64}$'
}

function Test-Uuid {
    param([object]$Value)
    $parsed = [guid]::Empty
    $null -ne $Value -and [guid]::TryParse($Value.ToString(), [ref]$parsed)
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
} else {
    $RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
}
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $RepositoryRoot 'tests\pr-review-remediation\PRR-001'
} else {
    $EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
}

$runPath = Join-Path $EvidenceRoot 'run.json'
$localPath = Join-Path $EvidenceRoot 'local-review-findings.md'
$planPath = Join-Path $EvidenceRoot 'review-plan.md'
$schemaPath = Join-Path $EvidenceRoot 'run.schema.json'

foreach ($required in @($schemaPath, $runPath, $localPath, $planPath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        Add-Failure "required evidence is missing: $required"
    }
}

$forbiddenEvidence = @(Get-ChildItem -LiteralPath $EvidenceRoot -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -eq '.jsonl' -or $_.Name -like '*.stderr.log'
})
if ($forbiddenEvidence.Count -gt 0) {
    Add-Failure 'raw Codex JSONL or stderr logs must not be committed as PRR-001 evidence'
}

if ($failures.Count -eq 0) {
    try {
        if (-not ((Get-Content -LiteralPath $runPath -Raw) | Test-Json -SchemaFile $schemaPath)) {
            Add-Failure 'run.json does not satisfy run.schema.json'
        }
        $run = Get-Content -LiteralPath $runPath -Raw | ConvertFrom-Json
    } catch {
        Add-Failure "run.json schema validation or parsing failed: $($_.Exception.Message)"
    }
}

if ($failures.Count -eq 0) {
    if ($run.schemaVersion -ne '1.0') { Add-Failure 'schemaVersion must be 1.0' }
    if ($run.evidenceId -ne 'PRR-001') { Add-Failure 'evidenceId must be PRR-001' }
    if (-not (Test-Uuid $run.runId)) { Add-Failure 'runId must be a UUID' }
    if ($run.status -ne 'PASS') { Add-Failure 'run status must be PASS' }
    if ($run.executionMode -ne 'canonical-profile-direct-execution') {
        Add-Failure 'executionMode must disclose canonical-profile-direct-execution'
    }
    if ($run.customAgentSpawnObserved -ne $false) {
        Add-Failure 'customAgentSpawnObserved must be false for this compatibility-path evidence'
    }
    if ($run.externalModelPayloadConfirmed -ne $true) {
        Add-Failure 'externalModelPayloadConfirmed must be true'
    }

    $started = [DateTimeOffset]::MinValue
    $completed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($run.startedAtUtc.ToString(), [ref]$started) -or
        -not [DateTimeOffset]::TryParse($run.completedAtUtc.ToString(), [ref]$completed) -or
        $completed -lt $started) {
        Add-Failure 'run timestamps are missing or inconsistent'
    }

    $expectedAgents = @('local-reviewer', 'review-planner')
    if (@($run.runs).Count -ne 2) {
        Add-Failure 'runs must contain exactly local-reviewer then review-planner'
    } else {
        for ($index = 0; $index -lt 2; $index++) {
            $agentRun = $run.runs[$index]
            if ($agentRun.configuredAgent -ne $expectedAgents[$index]) {
                Add-Failure "run index $index must be $($expectedAgents[$index])"
            }
            if ($agentRun.observedExecution -ne 'top-level-codex-exec:/root') {
                Add-Failure "$($expectedAgents[$index]) must disclose the observed top-level execution"
            }
            foreach ($hashName in @('profileSha256', 'contractSha256', 'developerInstructionsSha256', 'outputSha256')) {
                if (-not (Test-Sha256 $agentRun.$hashName)) {
                    Add-Failure "$($expectedAgents[$index]).$hashName is not a SHA-256 value"
                }
            }
            if (-not (Test-Uuid $agentRun.sessionId) -or -not (Test-Uuid $agentRun.turnId)) {
                Add-Failure "$($expectedAgents[$index]) sessionId and turnId must be UUIDs"
            }
            if ([string]::IsNullOrWhiteSpace($agentRun.codexCliVersion)) {
                Add-Failure "$($expectedAgents[$index]) codexCliVersion is missing"
            }
            if ($agentRun.model -ne 'gpt-5.6-terra' -or
                $agentRun.reasoningEffort -ne 'high' -or
                $agentRun.sandboxMode -ne 'read-only') {
                Add-Failure "$($expectedAgents[$index]) effective profile does not match the canonical model/reasoning/sandbox"
            }
            if ([int64]$agentRun.durationMs -le 0 -or
                [int64]$agentRun.usage.inputTokens -le 0 -or
                [int64]$agentRun.usage.outputTokens -le 0 -or
                [int64]$agentRun.usage.totalTokens -le 0) {
                Add-Failure "$($expectedAgents[$index]) duration or token usage is missing"
            }
            if ($agentRun.gitBefore.head -ne $agentRun.gitAfter.head -or
                $agentRun.gitBefore.tree -ne $agentRun.gitAfter.tree -or
                $agentRun.gitBefore.status -ne '' -or
                $agentRun.gitAfter.status -ne '') {
                Add-Failure "$($expectedAgents[$index]) changed the isolated fixture repository"
            }

            $resolvedOutput = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $agentRun.outputPath))
            if (-not (Test-Path -LiteralPath $resolvedOutput)) {
                Add-Failure "$($expectedAgents[$index]) outputPath does not exist"
            } elseif ((Get-Sha256 $resolvedOutput) -ne $agentRun.outputSha256) {
                Add-Failure "$($expectedAgents[$index]) output hash does not match"
            }
        }
    }

    if (@($run.inputFiles).Count -lt 10) {
        Add-Failure 'inputFiles does not inventory the complete fixture and canonical profile payload'
    } else {
        foreach ($inputFile in $run.inputFiles) {
            $resolvedInput = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $inputFile.path))
            if (-not (Test-Path -LiteralPath $resolvedInput)) {
                Add-Failure "input file does not exist: $($inputFile.path)"
            } elseif (-not (Test-Sha256 $inputFile.sha256) -or
                (Get-Sha256 $resolvedInput) -ne $inputFile.sha256) {
                Add-Failure "input hash does not match: $($inputFile.path)"
            }
        }
    }

    $assertions = $run.assertions
    if ($assertions.agentOrder -ne $true -or
        $assertions.allFindingsDecided -ne $true -or
        $assertions.allAppliedFindingsMapped -ne $true -or
        $assertions.adaptiveIntentReady -ne $true -or
        $assertions.productionCodeChanged -ne $false -or
        $assertions.adaptiveAgentStarted -ne $false -or
        $assertions.phaseOneStoppedAfterPlanning -ne $true) {
        Add-Failure 'run assertions do not prove the required Phase 1 stop boundary'
    }
}

if ((Test-Path -LiteralPath $localPath) -and (Test-Path -LiteralPath $planPath)) {
    $localText = Get-Content -LiteralPath $localPath -Raw
    $planText = Get-Content -LiteralPath $planPath -Raw
    if ($localText -notmatch 'Verdict:\s*REVIEWED' -or
        $localText -notmatch 'Production code changed:\s*No') {
        Add-Failure 'local-review-findings.md does not prove a completed read-only review'
    }
    $localIds = @([regex]::Matches($localText, '\bLR-\d{3}\b') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    if ($localIds.Count -eq 0) {
        Add-Failure 'local-review-findings.md contains no stable finding ID'
    }
    foreach ($sourceId in @($localIds + @('100', '1001', '501'))) {
        $sourceLine = [regex]::Match($planText, '(?m)^\|[^\r\n]*' + [regex]::Escape($sourceId) + '[^\r\n]*\|\s*(Apply|Hold|Reject)\s*\|[^\r\n]*$')
        if (-not $sourceLine.Success) {
            Add-Failure "review-plan.md lacks an Apply/Hold/Reject decision row for source $sourceId"
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
        if ($planText -notmatch $requiredPattern) {
            Add-Failure "review-plan.md is missing required pattern: $requiredPattern"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("PRR-001 agent smoke validation: FAIL`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Host 'PRR-001 agent smoke validation: PASS'
