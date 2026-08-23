[CmdletBinding()]
param(
    [string[]]$Package,
    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Package -or $Package.Count -eq 0) {
    $Package = @(
        'adaptive-implementation-execution',
        'design-pair-implementation-execution',
        'goal-context-authoring',
        'pr-review-remediation',
        'persistent-purpose-review',
        'plan-coverage-residual-flow'
    )
}

foreach ($name in $Package) {
    & (Join-Path $PSScriptRoot 'validate-agent-plugin-package.ps1') -Package $name -ApmExecutable $ApmExecutable
}

& (Join-Path $repoRoot 'scripts/validate-no-root-projections.ps1')
Write-Output "Repository Agent Plugin validation: PASS ($($Package.Count) packages)"
