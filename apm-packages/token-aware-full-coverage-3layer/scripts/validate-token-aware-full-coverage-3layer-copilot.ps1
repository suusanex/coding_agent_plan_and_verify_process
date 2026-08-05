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

foreach ($relative in @(
    $fixtureRelative,
    'apm-packages/token-aware-full-coverage-3layer/tests/copilot-cli/README.md',
    'apm-packages/token-aware-full-coverage-3layer/README.md',
    'apm-packages/plan-coverage-residual-flow/scripts/run-copilot-cli-qualification.ps1'
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
Require $runbook 'legacy-split-v1' 'legacy resume boundary'
Require $runbook 'Issue #69' 'Design Pair blocker'
Require $skill 'full_coverage_artifact_layout: compact-slice-record-v2' 'canonical v2 layout'
Require $skill 'Parent State is the mandatory resume entrypoint' 'canonical resume contract'
Require $skill 'Design Pair' 'canonical Design Pair boundary'

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
    foreach ($freshnessToken in @($fixture.architecture_readiness_binding.required_freshness_evidence)) {
        $freshnessText = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tests/architecture-slice-readiness') -Recurse -File |
            ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) } |
            Out-String
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
