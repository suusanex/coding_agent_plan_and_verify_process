[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
    Write-Error $Message -ErrorAction Continue
}

function Get-NormalizedTextSha256([string]$LiteralPath) {
    $content = [System.IO.File]::ReadAllText($LiteralPath)
    $normalizedContent = $content.Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $hashBytes = $sha256.ComputeHash($utf8WithoutBom.GetBytes($normalizedContent))
        return [System.Convert]::ToHexString($hashBytes).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Assert-FileContains([string]$RelativePath, [string]$Pattern, [string]$Label) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure("Missing file for ${Label}: $RelativePath")
        return
    }

    if (-not (Select-String -LiteralPath $path -Pattern $Pattern -Quiet)) {
        Add-Failure("Missing contract '${Label}' in $RelativePath")
    }
}

function Assert-FileNotContains([string]$RelativePath, [string]$Pattern, [string]$Label) {
    $path = Join-Path $repoRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        if (Select-String -LiteralPath $path -Pattern $Pattern -Quiet) {
            Add-Failure("Prohibited contract '${Label}' remains in $RelativePath")
        }
    }
}

$manifests = @(
    'apm-packages/plan-coverage-residual-flow/apm.yml'
)

foreach ($manifest in $manifests) {
    $manifestPath = Join-Path $repoRoot $manifest
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Add-Failure("Missing manifest: $manifest")
        continue
    }

    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        if ($line -match '^\s*path:\s*(.+?)\s*$') {
            $dependency = $Matches[1]
            if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $dependency))) {
                Add-Failure("Missing dependency '$dependency' referenced by $manifest")
            }
        }
    }

    Assert-FileNotContains $manifest '\.apm/templates/.*\.md' 'unsupported standalone template file dependency'
}

$agents = @(
    '.github/agents/architecture-slice-readiness.agent.md',
    '.github/agents/architecture-elaboration.agent.md'
)

foreach ($agent in $agents) {
    $path = Join-Path $repoRoot $agent
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure("Missing agent: $agent")
        continue
    }

    $lines = Get-Content -LiteralPath $path
    $delimiters = @($lines | Where-Object { $_ -eq '---' }).Count
    if ($lines.Count -lt 4 -or $lines[0] -ne '---' -or $delimiters -lt 2 -or $lines[1] -notmatch '^name:' -or $lines[2] -notmatch '^description:') {
        Add-Failure("Invalid frontmatter: $agent")
    }
}

Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'Lightweight architecture baseline' 'ArchitectureNotRequired baseline authority'
Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'StandardSliceSufficient' 'readiness de-escalation verdict'
Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'Selected process after readiness' 'readiness route correction authority'
Assert-FileContains '.github/agents/change-risk-triage.agent.md' 'Why standard-slice is insufficient' 'full-coverage escalation gate evidence'
Assert-FileContains '.github/agents/plan-slice-decomposition.agent.md' 'StandardSliceSufficient' 'decomposition rejection for de-escalated runs'
Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'source_repository_commit' 'freshness source commit anchor'
Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'tracked_sources' 'tracked source freshness'
Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'watch_paths' 'watch path freshness'
Assert-FileContains '.github/agents/architecture-elaboration.agent.md' 'production evidence address' 'bounded production inspection'
Assert-FileContains '.github/agents/plan-slice-decomposition.agent.md' 'Architecture source IDs / sections' 'slice-local architecture traceability'
Assert-FileContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'Architecture baseline compatibility' 'Plan Coverage parent compatibility owner'
Assert-FileContains '.github/agents/implementation-handoff-review.agent.md' 'Check 11. Architecture baseline compatibility' 'pre-implementation compatibility gate'
Assert-FileContains '.github/instructions/plan-coverage-shared.instructions.md' 'Only `Match` may proceed to implementation' 'shared Match-only implementation invariant'
Assert-FileContains 'docs/architecture-slice-readiness-validation.md' 'Plan Coverage parent compatibility' 'ASR suite current compatibility owner'
Assert-FileContains 'docs/architecture-slice-readiness-validation.md' 'implementation-handoff-review` Check 11' 'ASR suite current handoff gate owner'
Assert-FileContains 'docs/architecture-slice-readiness-validation.md' 'Only a current-baseline `Match`' 'ASR suite Match-only authorization invariant'
Assert-FileNotContains 'docs/architecture-slice-readiness-validation.md' 'slice-prep|slice-impl|Parent Review Gate|Parent review records' 'removed 3-layer compatibility owner in current ASR suite'
Assert-FileContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/slice-architecture.md' 'artifact_revision' 'explicit slice architecture revision'
Assert-FileContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/slice-architecture.md' 'elaboration_trigger' 'immutable elaboration trigger snapshot'
Assert-FileContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/slice-architecture.md' 'freshness_dependency: false' 'non-freshness elaboration trigger'
Assert-FileNotContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/slice-architecture.md' 'role:\s*architecture_readiness_input' 'readiness as architecture tracked source'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'ASR-006' 'executed validation result'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'ASR-007' 'ArchitectureNotRequired decomposition regression result'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'Legacy filenames and output headings' 'historical fixture owner vocabulary classification'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'Plan Coverage parent architecture compatibility check and `implementation-handoff-review` Check 11' 'historical-to-current ASR owner mapping'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'ASR-003.*StandardSliceSufficient.*runtime-contract-kernel.agent.md' 'ASR-003 de-escalation summary'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'ASR-007.*ArchitectureNotRequired.*Check 11=`Match`' 'ASR-007 decomposition summary'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'ASR-005.*Pre-implementation architecture compatibility=`Drift`' 'ASR-005 current owner summary'

$fixtureRoot = Join-Path $repoRoot 'tests/architecture-slice-readiness'
$runIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($fixtureId in 1..7 | ForEach-Object { 'ASR-{0:D3}' -f $_ }) {
    $fixturePath = Join-Path $fixtureRoot $fixtureId
    $requiredFiles = @('input-plan.md', 'input-triage.md', 'actual-readiness.md', 'expected.json', 'actual.json', 'run.json')
    foreach ($requiredFile in $requiredFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $fixturePath $requiredFile))) {
            Add-Failure("${fixtureId}: missing durable fixture artifact $requiredFile")
        }
    }

    if ($requiredFiles | ForEach-Object { Test-Path -LiteralPath (Join-Path $fixturePath $_) } | Where-Object { -not $_ }) {
        continue
    }

    try {
        $expected = Get-Content -LiteralPath (Join-Path $fixturePath 'expected.json') -Raw | ConvertFrom-Json
        $actual = Get-Content -LiteralPath (Join-Path $fixturePath 'actual.json') -Raw | ConvertFrom-Json
        $run = Get-Content -LiteralPath (Join-Path $fixturePath 'run.json') -Raw | ConvertFrom-Json
    }
    catch {
        Add-Failure("${fixtureId}: invalid JSON artifact: $($_.Exception.Message)")
        continue
    }

    $expectedJson = $expected | ConvertTo-Json -Depth 10 -Compress
    $actualJson = $actual | ConvertTo-Json -Depth 10 -Compress
    if (-not [string]::Equals($expectedJson, $actualJson, [StringComparison]::Ordinal)) {
        Add-Failure("${fixtureId}: actual.json does not match expected.json")
    }

    if (-not $run.run_id -or -not $runIds.Add([string]$run.run_id)) {
        Add-Failure("${fixtureId}: run_id is missing or duplicated")
    }
    if (-not $run.executed_at -or -not $run.executor -or -not $run.environment) {
        Add-Failure("${fixtureId}: run evidence lacks executed_at, executor, or environment")
    }

    foreach ($artifact in @($run.inputs)) {
        $artifactPath = Join-Path $fixturePath ([string]$artifact)
        if (-not (Test-Path -LiteralPath $artifactPath)) {
            Add-Failure("${fixtureId}: run.json references missing input artifact $artifact")
        }
    }

    $outputText = [System.Text.StringBuilder]::new()
    foreach ($artifact in @($run.outputs)) {
        $artifactPath = Join-Path $fixturePath ([string]$artifact)
        if (-not (Test-Path -LiteralPath $artifactPath)) {
            Add-Failure("${fixtureId}: run.json references missing output artifact $artifact")
            continue
        }
        if ([string]$artifact -like '*.md') {
            [void]$outputText.AppendLine((Get-Content -LiteralPath $artifactPath -Raw))
        }
    }

    $auditText = $outputText.ToString()
    foreach ($requiredValue in @($actual.initial_verdict, $actual.final_verdict, $actual.next_action_initial)) {
        if ($requiredValue -and -not $auditText.Contains([string]$requiredValue, [StringComparison]::Ordinal)) {
            Add-Failure("${fixtureId}: complete artifacts do not contain expected observed value '$requiredValue'")
        }
    }
    foreach ($classification in @($actual.blocking_residuals_initial)) {
        if (-not $auditText.Contains([string]$classification, [StringComparison]::Ordinal)) {
            Add-Failure("${fixtureId}: complete artifacts do not contain blocking classification '$classification'")
        }
    }
    if ($actual.drift_result -ne 'NotRun' -and -not $auditText.Contains([string]$actual.drift_result, [StringComparison]::Ordinal)) {
        Add-Failure("${fixtureId}: complete artifacts do not contain drift result '$($actual.drift_result)'")
    }
    if ($actual.parent_review_authorized -and -not $auditText.Contains('Can implement now: `Yes`', [StringComparison]::Ordinal)) {
        Add-Failure("${fixtureId}: parent authorization is true but full output lacks 'Can implement now: Yes'")
    }
    if ($fixtureId -eq 'ASR-001') {
        if (-not $actual.architecture_current_after_readiness_rerun -or
            -not $actual.architecture_stale_after_parent_plan_change -or
            -not $actual.architecture_stale_after_watch_path_change) {
            Add-Failure('ASR-001: freshness regression booleans are not all true')
        }
        foreach ($freshnessEvidence in @(
            'freshness_dependency: false',
            'A1 current after readiness rerun: `Yes`',
            'A1 stale: `Yes`',
            'R2 stale: `Yes`'
        )) {
            if (-not $auditText.Contains($freshnessEvidence, [StringComparison]::Ordinal)) {
                Add-Failure("ASR-001: complete outputs lack freshness evidence '$freshnessEvidence'")
            }
        }
    }
    if ($fixtureId -eq 'ASR-003') {
        if ($actual.decomposition_allowed_final -or $actual.parent_review_authorized -or $actual.drift_result -ne 'NotRun') {
            Add-Failure('ASR-003: StandardSliceSufficient must stop decomposition and cross-slice compatibility checks')
        }
        foreach ($deescalationEvidence in @(
            'Selected process after readiness: `standard-slice`',
            'Decomposition allowed now: `No`',
            'No decomposition, slice preparation, parent review, or slice implementation authorization is created'
        )) {
            if (-not $auditText.Contains($deescalationEvidence, [StringComparison]::Ordinal)) {
                Add-Failure("ASR-003: complete outputs lack de-escalation evidence '$deescalationEvidence'")
            }
        }
    }
    if ($fixtureId -eq 'ASR-007') {
        if (-not $actual.decomposition_allowed_final -or -not $actual.parent_review_authorized -or $actual.drift_result -ne 'Match') {
            Add-Failure('ASR-007: ArchitectureNotRequired must remain decomposition-capable with a current baseline')
        }
        foreach ($decompositionEvidence in @(
            'Escalation gate result: `Satisfied`',
            'Architecture source: Lightweight architecture baseline',
            'Can implement now: `Yes`'
        )) {
            if (-not $auditText.Contains($decompositionEvidence, [StringComparison]::Ordinal)) {
                Add-Failure("ASR-007: complete outputs lack decomposition evidence '$decompositionEvidence'")
            }
        }
    }
}

$resultPath = Join-Path $repoRoot 'docs/architecture-slice-readiness-validation-result.md'
$resultText = $null
if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
    Add-Failure('Missing validation result: docs/architecture-slice-readiness-validation-result.md')
}
else {
    $resultText = Get-Content -LiteralPath $resultPath -Raw
}

$validatedContracts = @(
    '.github/agents/architecture-slice-readiness.agent.md',
    '.github/agents/architecture-elaboration.agent.md',
    '.github/agents/plan-slice-decomposition.agent.md',
    '.github/agents/implementation-handoff-review.agent.md',
    '.github/instructions/plan-coverage-shared.instructions.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/slice-architecture.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md'
)

foreach ($contract in $validatedContracts) {
    $contractPath = Join-Path $repoRoot $contract
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
        Add-Failure("Missing validated contract: $contract")
        continue
    }

    $hash = Get-NormalizedTextSha256 -LiteralPath $contractPath
    if ($null -ne $resultText -and -not $resultText.Contains($hash, [StringComparison]::Ordinal)) {
        Add-Failure("Validation result is stale for ${contract}; rerun ASR-001..007 and record SHA-256 $hash")
    }
}

$prohibited = @(
    'The next step is always `plan-slice-decomposition.agent.md`.',
    'immediate next agent は必ず `plan-slice-decomposition.agent.md`',
    'full-coverage の場合は必ず plan-slice-decomposition.agent.md を immediate next agent',
    'If triage recommends `full-coverage`, run `plan-slice-decomposition.agent.md`'
)

$scanRoots = @('README.md', 'docs', '.github', 'apm-packages')
foreach ($literal in $prohibited) {
    foreach ($scanRoot in $scanRoots) {
        $path = Join-Path $repoRoot $scanRoot
        $matches = Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
            Select-String -SimpleMatch $literal
        foreach ($match in $matches) {
            Add-Failure("Direct full-coverage route remains at $($match.Path):$($match.LineNumber): $literal")
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "Architecture Slice Readiness validation: FAILED ($($failures.Count) issue(s))"
    exit 1
}

Write-Host 'Architecture Slice Readiness validation: PASS'
