[CmdletBinding()]
param(
    [string[]]$Package,
    [switch]$SkipNegativeMutations
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentPlugin.Common.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$schemaPath = Join-Path $repoRoot 'tests/agent-plugins/qualification.schema.json'
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) { throw "Qualification schema is missing: $schemaPath" }
if (-not $Package -or $Package.Count -eq 0) {
    $Package = @('adaptive-implementation-execution','design-pair-implementation-execution','goal-context-authoring','pr-review-remediation','persistent-purpose-review','plan-coverage-residual-flow')
}

function Add-QualificationFailure([Collections.Generic.List[string]]$Failures, [string]$Message) {
    $Failures.Add($Message) | Out-Null
}

function Get-QualificationEvidenceFailure([string]$Reference) {
    if ([string]::IsNullOrWhiteSpace($Reference)) { return 'evidence reference is empty' }
    if (Test-AgentPluginPathEscape $repoRoot $Reference) { return "evidence reference escapes repository: $Reference" }

    $relative = $Reference.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
    $rootPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) { return "evidence reference escapes repository: $Reference" }

    $current = $repoRoot
    foreach ($segment in @($relative -split '[\\/]' | Where-Object { $_ })) {
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return "evidence reference crosses a reparse point: $Reference" }
        }
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { return "evidence file does not exist: $Reference" }
    return $null
}

function Get-QualificationCandidateFailures([string]$CandidateCommit, [string]$DistributionFingerprint, [string]$ExpectedPackage) {
    $failures = [Collections.Generic.List[string]]::new()
    if ($CandidateCommit -ceq 'UNCOMMITTED') {
        Add-QualificationFailure $failures 'PASS evidence requires a committed candidate snapshot'
        return $failures
    }

    $packageRoot = Join-Path $repoRoot "apm-packages/$ExpectedPackage"
    $currentFingerprint = Get-AgentPluginDistributionFingerprint $packageRoot
    if ($DistributionFingerprint -cne $currentFingerprint) {
        Add-QualificationFailure $failures 'distribution fingerprint is not current'
    }
    return $failures
}

function Get-AgentPluginQualificationFailures([string]$Path, [string]$ExpectedPackage) {
    $failures = [Collections.Generic.List[string]]::new()
    try {
        $valid = Test-Json -LiteralPath $Path -SchemaFile $schemaPath -ErrorAction Stop
        if (-not $valid) { Add-QualificationFailure $failures 'record does not conform to qualification JSON Schema' }
    }
    catch {
        Write-Host "TRACE: $($_.Exception.ToString())"
        Add-QualificationFailure $failures "qualification JSON Schema validation failed: $($_.Exception.Message)"
        return $failures
    }

    try { $result = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json }
    catch {
        Write-Host "TRACE: $($_.Exception.ToString())"
        Add-QualificationFailure $failures "qualification JSON could not be parsed: $($_.Exception.Message)"
        return $failures
    }

    if ([string]$result.package -cne $ExpectedPackage) { Add-QualificationFailure $failures "package identity differs from $ExpectedPackage" }
    $packageRoot = Join-Path $repoRoot "apm-packages/$ExpectedPackage"
    $currentFingerprint = Get-AgentPluginCanonicalFingerprint (Join-Path $packageRoot '.apm')
    if ([string]$result.canonicalFingerprint -cne $currentFingerprint) { Add-QualificationFailure $failures 'canonical fingerprint is not current' }

    $distributions = @($result.assessments | ForEach-Object { $_.distribution })
    if (($distributions | Sort-Object) -join '|' -cne 'agent-plugin-direct|apm') {
        Add-QualificationFailure $failures 'record must contain exactly one APM and one direct assessment'
    }
    $passAssessments = @($result.assessments | Where-Object { [string]$_.status -ceq 'PASS' })
    if ($passAssessments.Count -gt 0) {
        foreach ($failure in Get-QualificationCandidateFailures ([string]$result.candidateCommit) ([string]$result.distributionFingerprint) $ExpectedPackage) {
            Add-QualificationFailure $failures $failure
        }
    }
    foreach ($assessment in @($result.assessments)) {
        $identity = "$ExpectedPackage/$($assessment.distribution)"
        $references = @($assessment.evidenceRefs)
        if ([string]$assessment.status -ceq 'PASS' -and $references.Count -eq 0) { Add-QualificationFailure $failures "PASS requires evidenceRefs for $identity" }
        if ([string]$assessment.status -ceq 'PASS' -and [string]$assessment.evidenceMode -ceq 'NONE') { Add-QualificationFailure $failures "PASS cannot use evidenceMode NONE for $identity" }
        if (($references | Sort-Object -Unique).Count -ne $references.Count) { Add-QualificationFailure $failures "duplicate evidenceRefs for $identity" }
        foreach ($reference in $references) {
            $evidenceFailure = Get-QualificationEvidenceFailure ([string]$reference)
            if ($evidenceFailure) { Add-QualificationFailure $failures "$identity $evidenceFailure" }
        }
        if ([string]$assessment.status -ceq 'PASS' -and [string]$result.candidateCommit -cne 'UNCOMMITTED') {
            $candidateMentioned = @($references | Where-Object {
                $reference = [string]$_
                if (Get-QualificationEvidenceFailure $reference) { return $false }
                $candidatePath = Join-Path $repoRoot $reference.Replace('/', [IO.Path]::DirectorySeparatorChar)
                $evidence = Get-Content -Raw -LiteralPath $candidatePath
                return $evidence.Contains([string]$result.candidateCommit) -and $evidence.Contains([string]$result.distributionFingerprint)
            }).Count -gt 0
            if (-not $candidateMentioned) { Add-QualificationFailure $failures "PASS evidence does not identify candidate commit and distribution fingerprint for $identity" }
        }
    }
    return $failures
}

foreach ($name in $Package) {
    $path = Join-Path $repoRoot "apm-packages/$name/tests/agent-plugin/qualification.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing qualification record: $path" }
    $failures = @(Get-AgentPluginQualificationFailures -Path $path -ExpectedPackage $name)
    if ($failures.Count -gt 0) { throw ("Agent Plugin qualification failed for ${name}:`n- " + ($failures -join "`n- ")) }
    Write-Output "Agent Plugin qualification record: PASS ($name)"
}

if (-not $SkipNegativeMutations) {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $mutationRoot = Join-Path $tempRoot ('agent-plugin-qualification-mutations-' + [guid]::NewGuid().ToString('N'))
    $safeToDelete = $false
    try {
        $null = New-Item -ItemType Directory -Path $mutationRoot -Force
        $resolvedMutationRoot = (Resolve-Path -LiteralPath $mutationRoot).Path
        if (-not $resolvedMutationRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe qualification mutation root: $resolvedMutationRoot" }
        $safeToDelete = $true
        $baselinePackage = [string]$Package[0]
        $baselinePath = Join-Path $repoRoot "apm-packages/$baselinePackage/tests/agent-plugin/qualification.json"

        function Assert-QualificationMutationFails([string]$Name, [scriptblock]$Mutate, [string]$ExpectedPattern) {
            $path = Join-Path $resolvedMutationRoot "$Name.json"
            Copy-Item -LiteralPath $baselinePath -Destination $path
            $record = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
            & $Mutate $record
            [IO.File]::WriteAllText($path, (($record | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
            $failures = @(Get-AgentPluginQualificationFailures -Path $path -ExpectedPackage $baselinePackage)
            if ($failures.Count -eq 0) { throw "Qualification negative mutation was not detected: $Name" }
            if (($failures -join "`n") -notmatch $ExpectedPattern) { throw "Qualification mutation did not use expected validation path: $Name" }
        }

        Assert-QualificationMutationFails 'missing-client-version' {
            param($record)
            $record.runtime.PSObject.Properties.Remove('clientVersion')
        } 'JSON Schema'
        Assert-QualificationMutationFails 'unexpected-assessment-field' {
            param($record)
            $record.assessments[0] | Add-Member -NotePropertyName unsupported -NotePropertyValue $true
        } 'JSON Schema'
        Assert-QualificationMutationFails 'uncommitted-pass' {
            param($record)
            $record.assessments[0].status = 'PASS'
            $record.assessments[0].evidenceMode = 'LIVE'
            $record.assessments[0].evidenceRefs = @('tests/agent-plugins/results/2026-08-23-runtime-qualification.md')
            $record.candidateCommit = 'UNCOMMITTED'
        } 'committed candidate snapshot'
        Assert-QualificationMutationFails 'unknown-pass-candidate' {
            param($record)
            $record.assessments[0].status = 'PASS'
            $record.assessments[0].evidenceMode = 'LIVE'
            $record.assessments[0].evidenceRefs = @('tests/agent-plugins/results/2026-08-23-runtime-qualification.md')
            $record.candidateCommit = '0000000000000000000000000000000000000000'
        } 'does not identify candidate commit and distribution fingerprint'
        Assert-QualificationMutationFails 'stale-distribution-fingerprint' {
            param($record)
            $record.distributionFingerprint = '0000000000000000000000000000000000000000000000000000000000000000'
        } 'distribution fingerprint is not current'
        Assert-QualificationMutationFails 'missing-evidence-file' {
            param($record)
            $record.assessments[0].evidenceRefs = @('tests/agent-plugins/results/does-not-exist.md')
        } 'evidence file does not exist'
        Assert-QualificationMutationFails 'escaping-evidence-path' {
            param($record)
            $record.assessments[0].evidenceRefs = @('../outside-repository.md')
        } 'escapes repository'
    }
    finally {
        if ($safeToDelete -and (Test-Path -LiteralPath $mutationRoot)) {
            $resolved = [IO.Path]::GetFullPath($mutationRoot)
            if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove unsafe qualification mutation root: $resolved" }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
