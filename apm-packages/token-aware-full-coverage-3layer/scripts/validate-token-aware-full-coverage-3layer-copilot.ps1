[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Fail([string]$Message) {
    [void]$failures.Add($Message)
}

function Read-Text([string]$RelativePath) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "Missing file: $RelativePath"
        return ''
    }
    return [System.IO.File]::ReadAllText($path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Require([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -notmatch $Pattern) {
        Fail "Missing $Label"
    }
}

function Forbid([string]$Text, [string]$Pattern, [string]$Label) {
    if ($Text -match $Pattern) {
        Fail "Prohibited $Label"
    }
}

function Validate-ResumeEvidence([object]$Scenario, [string]$ScenarioId) {
    if ($null -eq $Scenario) {
        Fail "Committed real CLI result is missing resume scenario: $ScenarioId"
        return
    }

    $status = [string]$Scenario.status
    $declaration = $Scenario.evidence_declaration
    if ($null -eq $declaration) {
        Fail "Resume scenario $ScenarioId is missing evidence_declaration"
        return
    }

    if ($status -eq 'PASS') {
        if ([string]$declaration.evidence_source -cne 'real-cli') {
            Fail "Resume scenario $ScenarioId PASS requires real-cli evidence_source"
        }
        if ([string]$declaration.artifact_authoritative_resume -cne 'PROVEN') {
            Fail "Resume scenario $ScenarioId PASS requires explicit artifact-authoritative evidence"
        }
        if ([string]::IsNullOrWhiteSpace([string]$declaration.evidence_bundle_path) -or
            [string]$declaration.evidence_bundle_path -ceq 'N/A') {
            Fail "Resume scenario $ScenarioId PASS requires an evidence bundle path"
        }
        if ([string]$declaration.evidence_bundle_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            Fail "Resume scenario $ScenarioId PASS requires a SHA-256 evidence bundle hash"
        }
        foreach ($referenceField in @('prompt_reference', 'command_reference', 'output_reference')) {
            if ([string]::IsNullOrWhiteSpace([string]$declaration.$referenceField) -or
                [string]$declaration.$referenceField -ceq 'N/A') {
                Fail "Resume scenario $ScenarioId PASS requires $referenceField"
            }
        }
        if (@($declaration.artifact_references).Count -eq 0) {
            Fail "Resume scenario $ScenarioId PASS requires artifact references"
        }
        foreach ($artifact in @($declaration.artifact_references)) {
            if ([string]::IsNullOrWhiteSpace([string]$artifact.path) -or
                [string]$artifact.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
                Fail "Resume scenario $ScenarioId PASS requires artifact paths with SHA-256"
            }
        }
        if (@($declaration.changed_files).Count -eq 0) {
            Fail "Resume scenario $ScenarioId PASS requires changed_files evidence"
        }
        if (@($declaration.verdict_sequence).Count -eq 0) {
            Fail "Resume scenario $ScenarioId PASS requires verdict_sequence evidence"
        }
    }
    elseif ($status -eq 'UNOBSERVABLE') {
        if ([string]$declaration.artifact_authoritative_resume -cne 'NOT_PROVEN') {
            Fail "Resume scenario $ScenarioId UNOBSERVABLE must declare artifact-authoritative resume NOT_PROVEN"
        }
        if ([string]$Scenario.evidence -notmatch '(?i)artifact-authoritative.*not proven') {
            Fail "Resume scenario $ScenarioId must state that artifact-authoritative resume was not proven"
        }
    }
}

$fixtureRelative = 'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/qualification-scenarios.json'
$fixture = $null
try {
    $fixture = (Read-Text $fixtureRelative) | ConvertFrom-Json
}
catch {
    Fail "Invalid qualification fixture JSON: $($_.Exception.Message)"
}

$manifest = Read-Text 'apm-packages/token-aware-full-coverage-3layer/apm.yml'
$readme = Read-Text 'apm-packages/token-aware-full-coverage-3layer/README.md'
$runbook = Read-Text 'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/README.md'
$skill = Read-Text 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md'
$realResultText = Read-Text 'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/results/20260805-real-cli-qualification.json'
$realResult = $null
try {
    $realResult = $realResultText | ConvertFrom-Json
}
catch {
    Fail "Invalid committed real CLI result JSON: $($_.Exception.Message)"
}

foreach ($relative in @(
    $fixtureRelative,
    'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/README.md',
    'apm-packages/token-aware-full-coverage-3layer/README.md',
    'apm-packages/plan-coverage-residual-flow/scripts/run-copilot-cli-qualification.ps1',
    'apm-packages/plan-coverage-residual-flow/scripts/validate-copilot-full-package-install.ps1',
    'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/results/20260805-real-cli-qualification.json',
    'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/results/20260805-real-cli-qualification.md'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
        Fail "Missing Full Coverage Copilot qualification file: $relative"
    }
}

Require $manifest '(?m)^targets:\s*\r?\n(?:\s+- .*\r?\n)*\s+- copilot\s*$' 'Copilot target'
Require $manifest '(?m)^targets:\s*\r?\n(?:\s+- .*\r?\n)*\s+- agent-skills\s*$' 'agent-skills target'
Require $readme 'GitHub Copilot CLI' 'package README Copilot section'
Require $readme 'apm install .*--target copilot,agent-skills --https' 'package README install command'
Require $readme 'apm update .*--dry-run' 'package README update command'
Require $readme 'apm install --frozen' 'package README integrity check'
Require $readme 'apm uninstall .*--dry-run' 'package README rollback/removal command'
Require $readme 'copilot skill list' 'package README Skill discovery'
Require $readme 'copilot --resume' 'package README resume command'
Require $readme 'Troubleshooting' 'package README troubleshooting'
Require $runbook 'apm install .*--target copilot,agent-skills --https' 'remote Copilot install command'
Require $runbook 'apm update .*--dry-run' 'Copilot update command'
Require $runbook 'apm install --frozen' 'Copilot frozen integrity check'
Require $runbook 'apm audit --ci' 'Copilot audit command'
Require $runbook 'apm uninstall .*--dry-run' 'Copilot uninstall command'
Require $runbook 'copilot skill list' 'Copilot Skill discovery command'
Require $runbook 'Parent Orchestration State' 'durable Parent State resume'
Require $runbook 'compact-slice-record-v2' 'compact v2 layout'
Require $runbook 'Manual acceptance: Full Coverage artifact-authoritative new-session resume' 'manual resume acceptance section'
Require $runbook 'artifact-authoritative resume was not proven' 'artifact-authoritative resume limitation'
Require $runbook 'legacy-split-v1' 'legacy resume boundary'
Require $runbook 'Issue #69' 'Design Pair blocker'
Require $runbook 'validate-copilot-full-package-install.ps1' 'full-package installation check'
Require $runbook 'REAL_SCENARIO_INCOMPLETE' 'incomplete top-level qualification status'
Require $skill 'full_coverage_artifact_layout: compact-slice-record-v2' 'canonical v2 layout'
Require $skill 'Parent State is the mandatory resume entrypoint' 'canonical resume contract'
Require $skill 'Design Pair' 'canonical Design Pair boundary'
Require $readme 'artifact-authoritative' 'package README resume evidence boundary'

if ($null -ne $fixture) {
    if ($fixture.schema_version -ne 1) { Fail 'Qualification fixture schema_version must be 1' }
    if ($fixture.package -cne 'token-aware-full-coverage-3layer') { Fail 'Qualification fixture package name mismatch' }

    foreach ($source in @($fixture.canonical_sources)) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$source)) -PathType Leaf)) {
            Fail "Missing canonical source referenced by fixture: $source"
        }
    }

    $targets = @($fixture.installation.targets)
    if ((($targets | Sort-Object) -join ',') -cne 'agent-skills,copilot') {
        Fail 'Qualification fixture installation targets must be copilot and agent-skills'
    }
    if ($fixture.installation.deployed_skill -cne '.agents/skills/token-aware-full-coverage-3layer/SKILL.md') {
        Fail 'Qualification fixture deployed Skill path is incorrect'
    }
    if ($fixture.installation.deployed_instruction -cne '.github/instructions/token-aware-full-coverage-3layer.instructions.md') {
        Fail 'Qualification fixture deployed instruction path is incorrect'
    }
    foreach ($command in @('install', 'check', 'update_preview', 'rollback', 'cli_discovery')) {
        if ([string]::IsNullOrWhiteSpace([string]$fixture.installation.commands.$command)) {
            Fail "Qualification fixture is missing installation command: $command"
        }
    }

    if ($fixture.required_layout.fresh -cne 'compact-slice-record-v2' -or
        $fixture.required_layout.legacy_resume -cne 'legacy-split-v1' -or
        $fixture.required_layout.mixed_or_missing -cne 'BlockedByArtifactLayoutMismatch') {
        Fail 'Fixture layout rules do not preserve v2, legacy-resume, and fail-closed boundaries'
    }

    foreach ($binding in @($fixture.fixture_bindings)) {
        $fixtureDirectory = Join-Path $repoRoot ([string]$binding.source)
        if (-not (Test-Path -LiteralPath $fixtureDirectory -PathType Container)) {
            Fail "Missing full-coverage fixture directory: $($binding.source)"
            continue
        }
        $runPath = Join-Path $fixtureDirectory 'run.json'
        if (-not (Test-Path -LiteralPath $runPath -PathType Leaf)) {
            Fail "Missing run.json for fixture binding: $($binding.id)"
            continue
        }
        $run = Get-Content -Raw -LiteralPath $runPath | ConvertFrom-Json
        if ([string]$run.result -cne [string]$binding.expected) {
            Fail "Fixture result mismatch for $($binding.id): expected $($binding.expected), got $($run.result)"
        }
        $evidence = ((Get-ChildItem -LiteralPath $fixtureDirectory -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
        foreach ($token in @($binding.evidence)) {
            if ($evidence -notmatch [regex]::Escape([string]$token)) {
                Fail "Fixture $($binding.id) lacks evidence token: $token"
            }
        }
    }

    foreach ($fixtureId in @($fixture.architecture_readiness_binding.required_fixture_ids)) {
        $fixtureDirectory = Join-Path $repoRoot "tests/architecture-slice-readiness/$fixtureId"
        if (-not (Test-Path -LiteralPath $fixtureDirectory -PathType Container)) {
            Fail "Missing Architecture Slice Readiness fixture: $fixtureId"
        }
    }
    $freshnessText = if (Test-Path -LiteralPath (Join-Path $repoRoot 'tests/architecture-slice-readiness') -PathType Container) {
        Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests/architecture-slice-readiness') -Recurse -File |
            ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) } |
            Out-String
    }
    else {
        ''
    }
    foreach ($freshnessToken in @($fixture.architecture_readiness_binding.required_freshness_evidence)) {
        if ($freshnessText -notmatch [regex]::Escape([string]$freshnessToken)) {
            Fail "Architecture readiness evidence is missing: $freshnessToken"
        }
    }

    foreach ($field in @('parent_authorization', 'implementation_owner', 'bounded_completion_owner', 'independent_verifier', 'final_record_owner')) {
        if ([string]::IsNullOrWhiteSpace([string]$fixture.ownership_and_verification.$field)) {
            Fail "Ownership fixture field is missing: $field"
        }
    }
    foreach ($routeField in @('implementation_route', 'implementation_route_source')) {
        if (@($fixture.ownership_and_verification.required_route_identity) -notcontains $routeField) {
            Fail "Ownership fixture is missing route identity field: $routeField"
        }
    }

    $evidenceRequirements = $fixture.evidence_requirements
    if ($null -eq $evidenceRequirements -or
        [string]$evidenceRequirements.resume_scenario_id -cne 'new-session-parent-state-resume') {
        Fail 'Fixture is missing Full Coverage resume evidence requirements'
    }
    foreach ($requirement in @(
        'evidence_source=real-cli',
        'evidence_declaration.artifact_authoritative_resume=PROVEN',
        'evidence_declaration.evidence_bundle_path',
        'evidence_declaration.evidence_bundle_sha256',
        'evidence_declaration.prompt_reference',
        'evidence_declaration.command_reference',
        'evidence_declaration.output_reference',
        'evidence_declaration.artifact_references with path and sha256',
        'evidence_declaration.changed_files',
        'evidence_declaration.verdict_sequence'
    )) {
        if ($null -eq $evidenceRequirements -or @($evidenceRequirements.pass_requires) -notcontains $requirement) {
            Fail "Resume evidence requirement is missing: $requirement"
        }
    }
    foreach ($requirement in @(
        'evidence_declaration.artifact_authoritative_resume=NOT_PROVEN',
        'evidence text states artifact-authoritative resume was not proven'
    )) {
        if ($null -eq $evidenceRequirements -or @($evidenceRequirements.unobservable_requires) -notcontains $requirement) {
            Fail "UNOBSERVABLE resume evidence requirement is missing: $requirement"
        }
    }

    $scenarioIds = @($fixture.real_cli_scenarios | ForEach-Object { [string]$_.id })
    foreach ($requiredId in @('compact-v2-two-slice', 'parent-authorization-and-independent-verification', 'final-record-through-residual-decision', 'new-session-parent-state-resume', 'stale-or-incomplete-layout-failure', 'design-pair-e2e')) {
        if ($scenarioIds -notcontains $requiredId) {
            Fail "Real CLI scenario is missing: $requiredId"
        }
    }
    $designPairScenario = $fixture.real_cli_scenarios | Where-Object { $_.id -ceq 'design-pair-e2e' }
    if ($null -eq $designPairScenario -or $designPairScenario.default_status -cne 'BLOCKED' -or $designPairScenario.blocker -notmatch 'Issue #69') {
        Fail 'Design Pair scenario must remain explicitly blocked by Issue #69'
    }
}

if ($null -ne $realResult) {
    if ([string]$realResult.package -cne 'token-aware-full-coverage-3layer') {
        Fail 'Committed real CLI result package mismatch'
    }
    if ([string]$realResult.source_ref -cne '8d7527cbf5c0172148346463fd6c61f25fb33e24') {
        Fail 'Committed real CLI result must identify the reviewed PR head'
    }
    if ([string]$realResult.qualification_status -cne 'REAL_SCENARIO_INCOMPLETE') {
        Fail 'Committed real CLI result must not claim qualification while scenarios are unresolved'
    }
    if ([string]$realResult.execution_kind -cne 'real-cli') {
        Fail 'Committed real CLI result must identify execution_kind real-cli'
    }
    if ([string]$realResult.evidence_requirements.resume_scenario_id -cne 'new-session-parent-state-resume' -or
        [string]$realResult.evidence_requirements.current_status -cne 'UNOBSERVABLE' -or
        [string]$realResult.evidence_requirements.artifact_authoritative_resume -cne 'NOT_PROVEN') {
        Fail 'Committed Full Coverage resume evidence requirements must remain explicitly UNOBSERVABLE and NOT_PROVEN'
    }
    if ([string]$realResult.full_package_install.status -cne 'PASS' -or
        [string]$realResult.full_package_install.lock_ref -cne [string]$realResult.source_ref) {
        Fail 'Committed real CLI result is missing final-head installation evidence'
    }
    if ([string]$realResult.local_package_directory.status -cne 'FAIL_EXPECTED' -or
        [string]$realResult.local_package_directory.reason -notmatch 'git:\s*parent') {
        Fail 'Committed real CLI result must keep the APM local package-directory limitation honest'
    }
    $realIds = @($realResult.scenarios | ForEach-Object { [string]$_.id })
    foreach ($requiredId in @('compact-v2-two-slice', 'parent-authorization-and-independent-verification', 'final-record-through-residual-decision', 'new-session-parent-state-resume', 'stale-or-incomplete-layout-failure', 'design-pair-e2e')) {
        if ($realIds -notcontains $requiredId) {
            Fail "Committed real CLI result is missing scenario: $requiredId"
        }
    }
    $realResume = $realResult.scenarios | Where-Object { $_.id -ceq 'new-session-parent-state-resume' }
    if ($null -eq $realResume -or [string]$realResume.status -cne 'UNOBSERVABLE') {
        Fail 'Committed Full Coverage new-session-parent-state-resume must remain UNOBSERVABLE'
    }
    Validate-ResumeEvidence $realResume 'new-session-parent-state-resume'
    $realDesignPair = $realResult.scenarios | Where-Object { $_.id -ceq 'design-pair-e2e' }
    if ($null -eq $realDesignPair -or [string]$realDesignPair.status -cne 'BLOCKED') {
        Fail 'Committed real CLI result must keep Design Pair BLOCKED'
    }
}

$packageFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'apm-packages/token-aware-full-coverage-3layer') -Recurse -File |
    Where-Object { $_.FullName -ne $PSCommandPath }
foreach ($file in $packageFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    Forbid $text '(?i)codex-first|copilot-fallback' "retired aggregate dependency in $($file.FullName.Substring($repoRoot.Length + 1))"
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure -ErrorAction Continue
    }
    throw "Full Coverage Copilot qualification validation failed with $($failures.Count) error(s)."
}

Write-Host 'Full Coverage Copilot qualification validation: PASS'
