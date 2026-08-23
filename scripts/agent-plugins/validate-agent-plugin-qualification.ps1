[CmdletBinding()]
param([string[]]$Package)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentPlugin.Common.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$schemaPath = Join-Path $repoRoot 'tests/agent-plugins/qualification.schema.json'
$schema = Get-Content -Raw -LiteralPath $schemaPath | ConvertFrom-Json
if ($schema.additionalProperties -ne $false -or @($schema.required).Count -eq 0) { throw 'Qualification schema must be closed and declare required fields.' }
if (-not $Package -or $Package.Count -eq 0) {
    $Package = @('adaptive-implementation-execution','design-pair-implementation-execution','goal-context-authoring','pr-review-remediation','persistent-purpose-review','plan-coverage-residual-flow')
}
$allowedStatuses = @('PASS','FAIL','HOLD','NOT_RUN','UNOBSERVABLE')
$allowedModes = @('LIVE','REUSED','PARTIAL','NONE')

foreach ($name in $Package) {
    $packageRoot = Join-Path $repoRoot "apm-packages/$name"
    $path = Join-Path $packageRoot 'tests/agent-plugin/qualification.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing qualification record: $path" }
    $result = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    foreach ($required in @($schema.required)) {
        if ($result.PSObject.Properties.Name -notcontains $required) { throw "Qualification record missing $required for $name" }
    }
    foreach ($property in $result.PSObject.Properties.Name) {
        if ($schema.properties.PSObject.Properties.Name -notcontains $property) { throw "Qualification record contains unsupported field $property for $name" }
    }
    if ([int]$result.schemaVersion -ne 1 -or [string]$result.package -cne $name) { throw "Invalid qualification identity: $name" }
    $currentFingerprint = Get-AgentPluginCanonicalFingerprint (Join-Path $packageRoot '.apm')
    if ([string]$result.canonicalFingerprint -cne $currentFingerprint) { throw "Qualification fingerprint is not current for $name" }
    if ([string]$result.candidateCommit -notmatch '^(?:[a-f0-9]{40}|UNCOMMITTED)$') { throw "Invalid candidateCommit for $name" }
    if ([string]$result.runtime.surface -cne 'github-copilot-cli') { throw "Invalid runtime surface for $name" }
    $distributions = @($result.assessments | ForEach-Object distribution)
    if (($distributions | Sort-Object) -join '|' -cne 'agent-plugin-direct|apm') { throw "Qualification must contain exactly APM and direct assessments for $name" }
    foreach ($assessment in @($result.assessments)) {
        if ($allowedStatuses -notcontains [string]$assessment.status) { throw "Invalid status for $name/$($assessment.distribution)" }
        if ($allowedModes -notcontains [string]$assessment.evidenceMode) { throw "Invalid evidenceMode for $name/$($assessment.distribution)" }
        if ([string]::IsNullOrWhiteSpace([string]$assessment.reason)) { throw "Missing reason for $name/$($assessment.distribution)" }
        if ([string]$assessment.status -ceq 'PASS' -and @($assessment.evidenceRefs).Count -eq 0) { throw "PASS requires evidenceRefs for $name/$($assessment.distribution)" }
        if ([string]$assessment.status -eq 'PASS' -and [string]$assessment.evidenceMode -eq 'NONE') { throw "PASS cannot use evidenceMode NONE for $name/$($assessment.distribution)" }
    }
    Write-Output "Agent Plugin qualification record: PASS ($name)"
}
