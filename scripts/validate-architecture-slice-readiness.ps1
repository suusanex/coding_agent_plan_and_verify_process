[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
    Write-Error $Message -ErrorAction Continue
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

$manifests = @(
    'apm-packages/token-aware-guardrail-kernel-flow/apm.yml',
    'apm-packages/token-aware-full-coverage-3layer/apm.yml',
    'apm-packages/codex-first-ai-development-process/apm.yml'
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
Assert-FileContains '.github/agents/architecture-slice-readiness.agent.md' 'revision_or_hash' 'readiness baseline identity'
Assert-FileContains '.github/agents/architecture-elaboration.agent.md' 'production evidence address' 'bounded production inspection'
Assert-FileContains '.github/agents/plan-slice-decomposition.agent.md' 'Architecture source IDs / sections' 'slice-local architecture traceability'
Assert-FileContains 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md' 'Architecture drift review' 'parent architecture drift gate'
Assert-FileContains 'apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/slice-architecture.md' 'architecture_artifact_revision' 'slice architecture revision'
Assert-FileContains 'docs/architecture-slice-readiness-validation-result.md' 'ASR-006' 'executed validation result'

$resultPath = Join-Path $repoRoot 'docs/architecture-slice-readiness-validation-result.md'
$resultText = Get-Content -LiteralPath $resultPath -Raw
$validatedContracts = @(
    '.github/agents/architecture-slice-readiness.agent.md',
    '.github/agents/architecture-elaboration.agent.md',
    '.github/agents/plan-slice-decomposition.agent.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-prep.agent.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/templates/slice-architecture.md'
)

foreach ($contract in $validatedContracts) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot $contract)).Hash.ToLowerInvariant()
    if (-not $resultText.Contains($hash, [StringComparison]::Ordinal)) {
        Add-Failure("Validation result is stale for ${contract}; rerun ASR-001..006 and record SHA-256 $hash")
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
