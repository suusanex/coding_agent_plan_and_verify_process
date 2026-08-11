[CmdletBinding()]
param(
    [string]$ResultPath,
    [switch]$RequireQualified
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$rqRoot = Join-Path $packageRoot 'tests/runtime-qualification'
$schemaPath = Join-Path $rqRoot 'result.schema.json'
$templatePath = Join-Path $rqRoot 'result-template.json'
$resultsDir = Join-Path $rqRoot 'results'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'
$canonicalRoot = Join-Path $packageRoot '.apm'
$docsPath = Join-Path $repoRoot 'docs/plan-coverage-runtime-qualification.md'
$authPath = Join-Path $packageRoot 'tests/invocation-authorization-scenarios.json'
$decisionOwnershipPath = Join-Path $packageRoot 'tests/decision-ownership-scenarios.json'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Get-NormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-Sha256Text([string]$Text) {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256File([string]$Path) {
    return Get-Sha256Text (Get-NormalizedText $Path)
}

function Get-CanonicalFingerprint([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object {
            $_.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        })
    $builder = [System.Text.StringBuilder]::new()
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        $content = Get-NormalizedText $file.FullName
        [void]$builder.Append($rel)
        [void]$builder.Append("`n")
        [void]$builder.Append($content)
        if (-not $content.EndsWith("`n")) {
            [void]$builder.Append("`n")
        }
        [void]$builder.Append("`n")
    }
    return Get-Sha256Text $builder.ToString()
}

function Get-PackageVersion([string]$ManifestPath) {
    $text = Get-NormalizedText $ManifestPath
    if ($text -cmatch '(?m)^version:\s*(\S+)\s*$') {
        return $Matches[1]
    }
    throw "Unable to read package version from $ManifestPath"
}

function Test-SchemaShape($Result) {
    $required = @(
        'schema_version', 'date', 'runtime', 'client_version', 'model_requested', 'model_observed',
        'apm_version', 'candidate_commit', 'plan_coverage_package_version', 'canonical_fingerprint',
        'install_targets', 'apm_lock_sha256', 'platform', 'distribution_smoke', 'overall_status', 'scenarios'
    )
    foreach ($name in $required) {
        if (-not ($Result.psobject.Properties.Name -contains $name)) {
            Add-Failure "Result missing required field: $name"
        }
    }
    if ($Result.schema_version -ne 1) {
        Add-Failure 'schema_version must be 1'
    }
    if ($Result.canonical_fingerprint -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'canonical_fingerprint must be 64-char lowercase hex'
    }
    if ($Result.runtime.qualified_client_surface -cne 'github-copilot-cli') {
        Add-Failure 'qualified_client_surface must be github-copilot-cli'
    }
    if ($Result.runtime.surface -cne 'github-copilot') {
        Add-Failure 'runtime.surface must be github-copilot'
    }
    $targets = @($Result.install_targets)
    foreach ($t in @('copilot', 'codex', 'agent-skills')) {
        if ($targets -cnotcontains $t) {
            Add-Failure "install_targets must include $t"
        }
    }
    if (@('QUALIFIED', 'PENDING', 'FAIL') -cnotcontains $Result.overall_status) {
        Add-Failure 'overall_status must be QUALIFIED, PENDING, or FAIL'
    }
    if ($null -eq $Result.scenarios -or @($Result.scenarios).Count -lt 1) {
        Add-Failure 'scenarios must be a non-empty array'
        return
    }
    $scenarioRequired = @(
        'id', 'kind', 'exact_prompt', 'upstream_route_evidence', 'exit_code', 'skill_observation',
        'agents_observed', 'created_artifacts', 'changed_artifacts', 'verifier_results', 'route_observed',
        'verdict', 'stop_reason', 'status', 'rationale', 'transcript_sha256', 'hook_log_sha256'
    )
    foreach ($scenario in @($Result.scenarios)) {
        foreach ($name in $scenarioRequired) {
            if (-not ($scenario.psobject.Properties.Name -contains $name)) {
                Add-Failure "Scenario $($scenario.id) missing field: $name"
            }
        }
        if (@('PASS', 'FAIL', 'NOT_RUN', 'UNOBSERVABLE') -cnotcontains $scenario.status) {
            Add-Failure "Scenario $($scenario.id) has invalid status"
        }
        if ($scenario.status -ceq 'UNOBSERVABLE' -and $Result.overall_status -ceq 'QUALIFIED') {
            Add-Failure "Scenario $($scenario.id) is UNOBSERVABLE but overall_status is QUALIFIED"
        }
    }
}

function Assert-InfrastructurePresent {
    $requiredPaths = @(
        $schemaPath,
        $templatePath,
        (Join-Path $rqRoot 'README.md'),
        (Join-Path $rqRoot 'copilot-cli/standard-slice/request.md'),
        (Join-Path $rqRoot 'copilot-cli/standard-slice/verify.ps1'),
        (Join-Path $rqRoot 'copilot-cli/standard-slice/seed/src/Load-AppConfig.ps1'),
        (Join-Path $rqRoot 'copilot-cli/full-coverage/request.md'),
        (Join-Path $rqRoot 'copilot-cli/full-coverage/verify.ps1'),
        (Join-Path $rqRoot 'copilot-cli/full-coverage/seed/src/ProducerState.ps1'),
        (Join-Path $rqRoot 'copilot-cli/full-coverage/seed/src/ConsumerGate.ps1'),
        (Join-Path $rqRoot 'copilot-cli/full-coverage/seed/src/StartupFlow.ps1'),
        (Join-Path $packageRoot 'scripts/run-plan-coverage-copilot-qualification.ps1'),
        $docsPath,
        $authPath,
        $decisionOwnershipPath
    )
    foreach ($path in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            Add-Failure "Missing runtime qualification asset: $path"
        }
    }

    # Authorization authority must remain the package-canonical JSON (no duplicate A-H authority).
    $auth = Get-Content -Raw -LiteralPath $authPath | ConvertFrom-Json
    $ids = @($auth | ForEach-Object { $_.id })
    foreach ($id in @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H')) {
        if ($ids -cnotcontains $id) {
            Add-Failure "Canonical authorization scenarios missing $id"
        }
    }

    $decisionOwnership = Get-Content -Raw -LiteralPath $decisionOwnershipPath | ConvertFrom-Json
    $decisionOwnershipIds = @($decisionOwnership | ForEach-Object { $_.id })
    foreach ($id in @('DO-001', 'DO-002', 'DO-003')) {
        if ($decisionOwnershipIds -cnotcontains $id) {
            Add-Failure "Decision ownership scenarios missing $id"
        }
    }

    $dupCandidates = @(
        Get-ChildItem -LiteralPath $rqRoot -Recurse -File -Filter '*authorization*' -ErrorAction SilentlyContinue
    )
    foreach ($f in $dupCandidates) {
        if ($f.Name -match 'scenarios\.json$') {
            Add-Failure "Do not duplicate A-H authorization scenarios under runtime-qualification: $($f.FullName)"
        }
    }
}

function Resolve-ResultPath {
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        return (Resolve-Path -LiteralPath $ResultPath).Path
    }
    if (-not (Test-Path -LiteralPath $resultsDir -PathType Container)) {
        return $null
    }
    $files = @(Get-ChildItem -LiteralPath $resultsDir -File -Filter '*-copilot-cli*.json' | Sort-Object -Property LastWriteTime, Name -Descending)
    if ($files.Count -eq 0) {
        return $null
    }
    return $files[0].FullName
}

Assert-InfrastructurePresent

$currentFingerprint = Get-CanonicalFingerprint $canonicalRoot
$currentPackageVersion = Get-PackageVersion $apmYmlPath
$resolvedResult = Resolve-ResultPath

if (-not $resolvedResult) {
    if ($RequireQualified) {
        Add-Failure 'No runtime qualification result JSON found and -RequireQualified was set.'
    }
    else {
        Write-Host "No committed copilot-cli result JSON yet. Infrastructure checks only."
        Write-Host "current_canonical_fingerprint=$currentFingerprint"
        Write-Host "current_package_version=$currentPackageVersion"
        if ($failures.Count -gt 0) {
            Write-Host 'Plan Coverage runtime qualification validator: FAIL'
            $failures | ForEach-Object { Write-Host " - $_" }
            exit 1
        }
        Write-Host 'Plan Coverage runtime qualification validator: PASS (infrastructure; qualification PENDING)'
        exit 0
    }
}

Write-Host "Validating result: $resolvedResult"
$result = Get-Content -Raw -LiteralPath $resolvedResult | ConvertFrom-Json
Test-SchemaShape $result

if ($result.plan_coverage_package_version -cne $currentPackageVersion) {
    if ($result.overall_status -ceq 'QUALIFIED') {
        Add-Failure "QUALIFIED result package version $($result.plan_coverage_package_version) != current $currentPackageVersion"
    }
}

if ($result.canonical_fingerprint -cne $currentFingerprint) {
    if ($result.overall_status -ceq 'QUALIFIED') {
        Add-Failure "QUALIFIED result fingerprint does not match current canonical source ($currentFingerprint)"
    }
    else {
        Write-Host "Note: result fingerprint differs from current canonical source (allowed while PENDING/FAIL)."
    }
}

$docsText = if (Test-Path -LiteralPath $docsPath) { Get-NormalizedText $docsPath } else { '' }
if ($result.overall_status -ceq 'QUALIFIED') {
    if ($docsText -cnotmatch 'QUALIFIED' -and $docsText -cnotmatch 'qualified') {
        Add-Failure 'Result is QUALIFIED but docs/plan-coverage-runtime-qualification.md does not record qualified status.'
    }
}
if ($docsText -cmatch '(?i)VS Code Agent mode[^\n]*qualified' -and $docsText -cnotmatch 'not.*qualified|separate') {
    Add-Failure 'Docs must not claim VS Code Agent mode runtime qualification for this Issue.'
}

$byId = @{}
foreach ($s in @($result.scenarios)) {
    $byId[[string]$s.id] = $s
}

$requiredIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'DO-001', 'DO-002', 'DO-003', 'STD-001', 'FULL-001')
foreach ($id in $requiredIds) {
    if (-not $byId.ContainsKey($id)) {
        if ($result.overall_status -ceq 'QUALIFIED' -or $RequireQualified) {
            Add-Failure "Missing required scenario $id"
        }
    }
}

if ($result.overall_status -ceq 'QUALIFIED' -or $RequireQualified) {
    if ($result.distribution_smoke.status -cne 'PASS') {
        Add-Failure 'distribution_smoke must be PASS for QUALIFIED evidence'
    }
    foreach ($id in $requiredIds) {
        if (-not $byId.ContainsKey($id)) { continue }
        $s = $byId[$id]
        if ($s.status -cne 'PASS') {
            Add-Failure "Required scenario $id status is $($s.status), expected PASS"
        }
        if ($s.status -ceq 'UNOBSERVABLE') {
            Add-Failure "Required scenario $id must not use UNOBSERVABLE as overall scenario status"
        }
        if ($s.status -ceq 'NOT_RUN') {
            Add-Failure "Required scenario $id is NOT_RUN"
        }
        if ($s.status -ceq 'FAIL') {
            Add-Failure "Required scenario $id is FAIL"
        }
    }

    $std = $byId['STD-001']
    $full = $byId['FULL-001']
    $adaptiveOk = $false
    $handoffOk = $false
    foreach ($s in @($std, $full)) {
        if ($null -eq $s) { continue }
        $ac = $s.adaptive_connection
        if (-not $ac) { continue }

        # Reject weak boolean-only claims without structured phases when present on newer evidence.
        if ($ac.psobject.Properties.Name -contains 'connection_satisfied') {
            if ($ac.connection_satisfied) { $adaptiveOk = $true }
            if ($ac.high_to_standard_handoff_satisfied) { $handoffOk = $true }

            foreach ($phaseName in @('high_execution', 'handoff', 'standard_execution')) {
                if (-not ($ac.psobject.Properties.Name -contains $phaseName)) {
                    Add-Failure "$($s.id) adaptive_connection missing phase $phaseName"
                    continue
                }
                $phase = $ac.$phaseName
                $st = [string]$phase.status
                if ($st -like 'OBSERVED_*' -and [string]::IsNullOrWhiteSpace([string]$phase.evidence)) {
                    Add-Failure "$($s.id).$phaseName OBSERVED_* requires evidence path/ref"
                }
                # READY_FOR_STANDARD_COMPLETION alone must not imply STANDARD execution.
                if ($phaseName -ceq 'standard_execution' -and $st -like 'OBSERVED_*') {
                    if ([string]$phase.evidence -match 'READY_FOR_STANDARD_COMPLETION' -and [string]$phase.evidence -notmatch 'standard-implementation-completer|COMPLETED_BY_STANDARD|hooks/session') {
                        Add-Failure "$($s.id).standard_execution must not treat READY_FOR_STANDARD_COMPLETION alone as STANDARD execution"
                    }
                }
            }

            if ($ac.high_observed -and $ac.high_execution.status -notlike 'OBSERVED_*') {
                Add-Failure "$($s.id) high_observed=true but high_execution is not OBSERVED_*"
            }
            if ($ac.standard_observed -and $ac.standard_execution.status -notlike 'OBSERVED_*') {
                Add-Failure "$($s.id) standard_observed=true but standard_execution is not OBSERVED_*"
            }
            if ($ac.handoff_observed -and $ac.handoff.status -notlike 'OBSERVED_*') {
                Add-Failure "$($s.id) handoff_observed=true but handoff is not OBSERVED_*"
            }
        }
        else {
            # Legacy boolean-only shape is insufficient for QUALIFIED.
            Add-Failure "$($s.id) adaptive_connection lacks structured phases required for QUALIFIED evidence"
        }

        if ($ac.design_pair_auto_selected) {
            Add-Failure "Design Pair auto-selection evidence present in $($s.id)"
        }
    }
    if (-not $adaptiveOk) {
        Add-Failure 'Adaptive connection_satisfied evidence missing from STD-001/FULL-001 (structured HIGH durable/hook evidence required)'
    }

    if (-not ($result.psobject.Properties.Name -contains 'source_run') -or $null -eq $result.source_run) {
        Add-Failure 'QUALIFIED result must include source_run frozen identity'
    }
    else {
        $sr = $result.source_run
        foreach ($field in @('source_run_id', 'candidate_commit', 'canonical_fingerprint', 'apm_yml_sha256', 'package_version', 'apm_lock_sha256', 'client_version')) {
            if (-not ($sr.psobject.Properties.Name -contains $field) -or [string]::IsNullOrWhiteSpace([string]$sr.$field)) {
                Add-Failure "source_run missing $field"
            }
        }
        if ([string]$sr.canonical_fingerprint -cne [string]$result.canonical_fingerprint) {
            Add-Failure 'result.canonical_fingerprint must equal source_run.canonical_fingerprint (no re-bind)'
        }
        if ([string]$sr.candidate_commit -cne [string]$result.candidate_commit) {
            Add-Failure 'result.candidate_commit must equal source_run.candidate_commit (no re-bind)'
        }
        if ([string]$sr.package_version -cne [string]$result.plan_coverage_package_version) {
            Add-Failure 'result.plan_coverage_package_version must equal source_run.package_version'
        }
        if ([string]$sr.apm_yml_sha256 -cne [string]$result.apm_yml_sha256) {
            Add-Failure 'result.apm_yml_sha256 must equal source_run.apm_yml_sha256'
        }
        if ([string]$sr.canonical_fingerprint -cne $currentFingerprint) {
            Add-Failure "QUALIFIED source_run fingerprint must match current canonical source ($currentFingerprint)"
        }
    }

    if ($result.canonical_fingerprint -cne $currentFingerprint) {
        Add-Failure 'QUALIFIED evidence fingerprint must match current canonical .apm source'
    }
    if ($result.plan_coverage_package_version -cne $currentPackageVersion) {
        Add-Failure 'QUALIFIED evidence package version must match current apm.yml'
    }
}
else {
    # PENDING/FAIL evidence must not be treated as current qualification in docs.
    if ($docsText -cmatch '(?m)^.*\bQUALIFIED\b.*GitHub Copilot CLI' -and $docsText -cnotmatch 'PENDING|not qualified|NOT QUALIFIED') {
        # Allow historical wording if PENDING is also explicit.
        if ($docsText -cnotmatch 'overall_status:\s*PENDING' -and $docsText -cnotmatch 'status:\s*PENDING' -and $docsText -cnotmatch 'PENDING \(not QUALIFIED\)') {
            Add-Failure 'Docs appear to claim QUALIFIED while result overall_status is not QUALIFIED'
        }
    }
}

# Template must remain valid sample
$template = Get-Content -Raw -LiteralPath $templatePath | ConvertFrom-Json
if ($template.overall_status -cne 'PENDING') {
    Add-Failure 'result-template.json overall_status must remain PENDING'
}

if ($failures.Count -gt 0) {
    Write-Host 'Plan Coverage runtime qualification validator: FAIL'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host "current_canonical_fingerprint=$currentFingerprint"
Write-Host "result_overall_status=$($result.overall_status)"
Write-Host 'Plan Coverage runtime qualification validator: PASS'
exit 0
