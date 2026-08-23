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
$script:validationContext = $null

. (Join-Path $PSScriptRoot 'PlanCoverageRuntimeQualification.Common.ps1')

function Add-Failure([string]$Message) {
    $prefix = if ([string]::IsNullOrWhiteSpace($script:validationContext)) { '' } else { "[$script:validationContext] " }
    $failures.Add("$prefix$Message")
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
        'apm_yml_sha256', 'install_targets', 'apm_lock_sha256', 'platform', 'distribution_smoke',
        'overall_status', 'source_run', 'scenarios'
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
    if ($Result.apm_yml_sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'apm_yml_sha256 must be 64-char lowercase hex'
    }
    if ($Result.psobject.Properties.Name -contains 'qualification_input_fingerprint' -and
        $null -ne $Result.qualification_input_fingerprint -and
        [string]$Result.qualification_input_fingerprint -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'qualification_input_fingerprint must be null or 64-char lowercase hex'
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
    if ($null -eq $Result.source_run) {
        Add-Failure 'source_run frozen identity is required for every evidence verdict'
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
        (Join-Path $packageRoot 'scripts/PlanCoverageRuntimeQualification.Common.ps1'),
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

function Resolve-ResultPaths {
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        return @((Resolve-Path -LiteralPath $ResultPath).Path)
    }
    if (-not (Test-Path -LiteralPath $resultsDir -PathType Container)) {
        return @()
    }
    return @(Get-ChildItem -LiteralPath $resultsDir -File -Filter '*-copilot-cli*.json' | Sort-Object Name)
}

function Test-ResultJsonSchema([string]$JsonText) {
    try {
        if (-not ($JsonText | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
            Add-Failure 'Result does not satisfy result.schema.json'
        }
    }
    catch {
        Write-Host "TRACE: $($_.Exception.ToString())"
        Add-Failure "Result schema validation failed: $($_.Exception.Message)"
    }
}

function Test-SourceRunIdentity($Result) {
    if ($null -eq $Result.source_run) { return }
    $sr = $Result.source_run
    foreach ($field in @('source_run_id', 'candidate_commit', 'canonical_fingerprint', 'apm_yml_sha256', 'package_version', 'apm_lock_sha256', 'client_version')) {
        if (-not ($sr.psobject.Properties.Name -contains $field) -or [string]::IsNullOrWhiteSpace([string]$sr.$field)) {
            Add-Failure "source_run missing $field"
        }
    }
    foreach ($field in @('apm_version', 'model_requested', 'model_observed', 'platform', 'distribution_smoke')) {
        if (-not ($sr.psobject.Properties.Name -contains $field)) {
            Add-Failure "source_run missing $field"
        }
    }
    if ([string]$sr.canonical_fingerprint -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'source_run.canonical_fingerprint must be 64-char lowercase hex'
    }
    if ([string]$sr.apm_yml_sha256 -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'source_run.apm_yml_sha256 must be 64-char lowercase hex'
    }
    $resultHasQualificationInput = $Result.psobject.Properties.Name -contains 'qualification_input_fingerprint'
    $sourceHasQualificationInput = $sr.psobject.Properties.Name -contains 'qualification_input_fingerprint'
    if ($resultHasQualificationInput -ne $sourceHasQualificationInput) {
        Add-Failure 'result and source_run must either both record qualification_input_fingerprint or both omit it'
    }
    if ($sourceHasQualificationInput -and $null -ne $sr.qualification_input_fingerprint -and
        [string]$sr.qualification_input_fingerprint -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'source_run.qualification_input_fingerprint must be null or 64-char lowercase hex'
    }

    $pairs = @(
        @('canonical_fingerprint', 'canonical_fingerprint'),
        @('candidate_commit', 'candidate_commit'),
        @('plan_coverage_package_version', 'package_version'),
        @('apm_yml_sha256', 'apm_yml_sha256'),
        @('qualification_input_fingerprint', 'qualification_input_fingerprint'),
        @('apm_lock_sha256', 'apm_lock_sha256'),
        @('client_version', 'client_version'),
        @('apm_version', 'apm_version'),
        @('model_requested', 'model_requested'),
        @('model_observed', 'model_observed'),
        @('platform', 'platform')
    )
    foreach ($pair in $pairs) {
        $resultField = $pair[0]
        $sourceField = $pair[1]
        if ([string]$Result.$resultField -cne [string]$sr.$sourceField) {
            Add-Failure "result.$resultField must equal source_run.$sourceField (frozen identity; no re-bind)"
        }
    }
    if ((@($Result.install_targets) -join "`n") -cne (@($sr.install_targets) -join "`n")) {
        Add-Failure 'result.install_targets must equal source_run.install_targets'
    }
    if ([string]$Result.distribution_smoke.status -cne [string]$sr.distribution_smoke.status) {
        Add-Failure 'result.distribution_smoke.status must equal source_run.distribution_smoke.status'
    }
    if ([string]$Result.distribution_smoke.command -cne [string]$sr.distribution_smoke.command) {
        Add-Failure 'result.distribution_smoke.command must equal source_run.distribution_smoke.command'
    }
    if ([string]$Result.distribution_smoke.rationale -cne [string]$sr.distribution_smoke.rationale) {
        Add-Failure 'result.distribution_smoke.rationale must equal source_run.distribution_smoke.rationale'
    }
}

function Test-ScenarioEvidenceInvariants($Result) {
    $byId = @{}
    foreach ($scenario in @($Result.scenarios)) {
        $id = [string]$scenario.id
        if ($byId.ContainsKey($id)) {
            Add-Failure "Duplicate scenario $id"
            continue
        }
        $byId[$id] = $scenario
    }
    if ($Result.overall_status -ceq 'PENDING') {
        if ($Result.distribution_smoke.status -cne 'PASS') {
            Add-Failure "PENDING evidence distribution_smoke status is $($Result.distribution_smoke.status), expected PASS"
        }
        foreach ($scenario in @($Result.scenarios)) {
            if ($scenario.status -cne 'PASS') {
                Add-Failure "PENDING evidence scenario $($scenario.id) status is $($scenario.status), expected PASS for every recorded targeted scenario"
            }
        }
    }
}

function Test-FullQualificationEvidence($Result) {
    $byId = @{}
    foreach ($scenario in @($Result.scenarios)) {
        $id = [string]$scenario.id
        $byId[$id] = $scenario
    }

    $requiredIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'STD-001', 'FULL-001')
    $packageSemVer = $null
    if ([version]::TryParse([string]$Result.plan_coverage_package_version, [ref]$packageSemVer) -and $packageSemVer -ge [version]'0.14.0') {
        $requiredIds = @($requiredIds[0..7]) + @('DO-001', 'DO-002', 'DO-003') + @($requiredIds[8..9])
    }
    foreach ($id in $requiredIds) {
        if (-not $byId.ContainsKey($id)) {
            Add-Failure "Missing required scenario $id"
            continue
        }
        if ($byId[$id].status -cne 'PASS') {
            Add-Failure "Required scenario $id status is $($byId[$id].status), expected PASS"
        }
    }
    if ($Result.distribution_smoke.status -cne 'PASS') {
        Add-Failure 'distribution_smoke must be PASS for QUALIFIED evidence'
    }

    $adaptiveOk = $false
    foreach ($id in @('STD-001', 'FULL-001')) {
        if (-not $byId.ContainsKey($id)) { continue }
        $scenario = $byId[$id]
        $ac = $scenario.adaptive_connection
        if (-not $ac -or -not ($ac.psobject.Properties.Name -contains 'connection_satisfied')) {
            Add-Failure "$id adaptive_connection lacks structured phases required for QUALIFIED evidence"
            continue
        }
        if ($ac.connection_satisfied) { $adaptiveOk = $true }
        foreach ($phaseName in @('high_execution', 'handoff', 'standard_execution')) {
            if (-not ($ac.psobject.Properties.Name -contains $phaseName)) {
                Add-Failure "$id adaptive_connection missing phase $phaseName"
                continue
            }
            $phase = $ac.$phaseName
            $phaseStatus = [string]$phase.status
            if ($phaseStatus -like 'OBSERVED_*' -and [string]::IsNullOrWhiteSpace([string]$phase.evidence)) {
                Add-Failure "$id.$phaseName OBSERVED_* requires evidence path/ref"
            }
            if ($phaseName -ceq 'standard_execution' -and $phaseStatus -like 'OBSERVED_*' -and
                [string]$phase.evidence -match 'READY_FOR_STANDARD_COMPLETION' -and
                [string]$phase.evidence -notmatch 'standard-implementation-completer|COMPLETED_BY_STANDARD|hooks/session') {
                Add-Failure "$id.standard_execution must not treat READY_FOR_STANDARD_COMPLETION alone as STANDARD execution"
            }
        }
        if ($ac.high_observed -and $ac.high_execution.status -notlike 'OBSERVED_*') {
            Add-Failure "$id high_observed=true but high_execution is not OBSERVED_*"
        }
        if ($ac.standard_observed -and $ac.standard_execution.status -notlike 'OBSERVED_*') {
            Add-Failure "$id standard_observed=true but standard_execution is not OBSERVED_*"
        }
        if ($ac.handoff_observed -and $ac.handoff.status -notlike 'OBSERVED_*') {
            Add-Failure "$id handoff_observed=true but handoff is not OBSERVED_*"
        }
        if ($ac.design_pair_auto_selected) {
            Add-Failure "Design Pair auto-selection evidence present in $id"
        }
    }
    if (-not $adaptiveOk) {
        Add-Failure 'Adaptive connection_satisfied evidence missing from STD-001/FULL-001'
    }
}

Assert-InfrastructurePresent

$currentFingerprint = Get-CanonicalFingerprint $canonicalRoot
$currentPackageVersion = Get-PackageVersion $apmYmlPath
$currentApmYmlSha256 = Get-Sha256File $apmYmlPath
$currentQualificationInputFingerprint = Get-PlanCoverageQualificationInputFingerprint $repoRoot
$resolvedResults = @(Resolve-ResultPaths)
$hasCurrentQualifiedEvidence = $false

if ($resolvedResults.Count -eq 0 -and $RequireQualified) {
    Add-Failure 'No runtime qualification result JSON found and -RequireQualified was set.'
}

foreach ($resolvedResult in $resolvedResults) {
    $script:validationContext = Split-Path -Leaf $resolvedResult
    Write-Host "Validating result: $resolvedResult"
    $failuresBeforeResult = $failures.Count
    $resultJson = Get-Content -Raw -LiteralPath $resolvedResult
    Test-ResultJsonSchema $resultJson
    $result = $resultJson | ConvertFrom-Json
    Test-SchemaShape $result
    Test-SourceRunIdentity $result
    Test-ScenarioEvidenceInvariants $result

    $isCurrentSnapshot = (
        [string]$result.canonical_fingerprint -ceq $currentFingerprint -and
        [string]$result.plan_coverage_package_version -ceq $currentPackageVersion -and
        [string]$result.apm_yml_sha256 -ceq $currentApmYmlSha256 -and
        $result.psobject.Properties.Name -contains 'qualification_input_fingerprint' -and
        [string]$result.qualification_input_fingerprint -ceq $currentQualificationInputFingerprint
    )
    $snapshotRelation = if ($isCurrentSnapshot) {
        'CURRENT_SNAPSHOT'
    }
    elseif ($result.overall_status -ceq 'QUALIFIED') {
        'HISTORICAL_BASELINE'
    }
    else {
        'DIFFERENT_SNAPSHOT'
    }

    if ($result.overall_status -ceq 'QUALIFIED') {
        Test-FullQualificationEvidence $result
    }
    if ($isCurrentSnapshot -and $result.overall_status -ceq 'QUALIFIED' -and $failures.Count -eq $failuresBeforeResult) {
        $hasCurrentQualifiedEvidence = $true
    }

    Write-Host "evidence_verdict=$($result.overall_status)"
    Write-Host "snapshot_relation=$snapshotRelation"
}

$script:validationContext = 'result-template.json'
$templateJson = Get-Content -Raw -LiteralPath $templatePath
Test-ResultJsonSchema $templateJson
$template = $templateJson | ConvertFrom-Json
Test-SchemaShape $template
Test-SourceRunIdentity $template
if ($template.overall_status -cne 'PENDING') {
    Add-Failure 'overall_status must remain PENDING'
}

$script:validationContext = 'policy-doc'
$docsText = if (Test-Path -LiteralPath $docsPath) { Get-NormalizedText $docsPath } else { '' }
foreach ($term in @('evidence validity', 'evidence verdict', 'support assessment', 'targeted runtime risk', 'full runtime risk')) {
    if ($docsText -notmatch [regex]::Escape($term)) {
        Add-Failure "Runtime qualification policy must define $term"
    }
}
if ($docsText -cmatch '(?i)VS Code Agent mode[^\n]*qualified' -and $docsText -cnotmatch 'not.*qualified|separate|別') {
    Add-Failure 'Docs must not claim VS Code Agent mode runtime qualification.'
}

if ($RequireQualified -and -not $hasCurrentQualifiedEvidence) {
    $script:validationContext = $null
    Add-Failure 'No full QUALIFIED evidence matches the current canonical fingerprint, package version, apm.yml hash, and runtime-relevant qualification input fingerprint.'
}

$script:validationContext = $null
Write-Host "current_canonical_fingerprint=$currentFingerprint"
Write-Host "current_package_version=$currentPackageVersion"
Write-Host "current_apm_yml_sha256=$currentApmYmlSha256"
Write-Host "current_qualification_input_fingerprint=$currentQualificationInputFingerprint"

if ($failures.Count -gt 0) {
    Write-Host 'Plan Coverage runtime qualification validator: FAIL'
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

$mode = if ($RequireQualified) { 'strict current qualification' } else { 'ordinary evidence integrity' }
Write-Host "Plan Coverage runtime qualification validator: PASS ($mode)"
exit 0
