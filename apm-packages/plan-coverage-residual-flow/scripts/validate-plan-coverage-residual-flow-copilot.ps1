[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
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

$fixtureRelative = 'apm-packages/plan-coverage-residual-flow/tests/copilot-cli/qualification-scenarios.json'
$fixture = $null
try {
    $fixture = (Read-Text $fixtureRelative) | ConvertFrom-Json
}
catch {
    Fail "Invalid qualification fixture JSON: $($_.Exception.Message)"
}

$requiredFiles = @(
    $fixtureRelative,
    'apm-packages/plan-coverage-residual-flow/tests/copilot-cli/README.md',
    'apm-packages/plan-coverage-residual-flow/tests/copilot-cli/result-template.md',
    'apm-packages/plan-coverage-residual-flow/scripts/run-copilot-cli-qualification.ps1'
)
foreach ($relative in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) {
        Fail "Missing Copilot qualification file: $relative"
    }
}

$manifest = Read-Text 'apm-packages/plan-coverage-residual-flow/apm.yml'
$readme = Read-Text 'apm-packages/plan-coverage-residual-flow/README.md'
$runbook = Read-Text 'apm-packages/plan-coverage-residual-flow/tests/copilot-cli/README.md'
$template = Read-Text 'apm-packages/plan-coverage-residual-flow/tests/copilot-cli/result-template.md'
$harness = Read-Text 'apm-packages/plan-coverage-residual-flow/scripts/run-copilot-cli-qualification.ps1'

Require $manifest '(?m)^targets:\s*\r?\n(?:\s+- .*\r?\n)*\s+- copilot\s*$' 'Copilot target'
Require $manifest '(?m)^targets:\s*\r?\n(?:\s+- .*\r?\n)*\s+- agent-skills\s*$' 'agent-skills target'
Require $readme 'GitHub Copilot CLI' 'package README Copilot section'
Require $readme 'canonical contract' 'package README canonical contract ownership'
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
Require $runbook 'copilot --resume' 'Copilot conversation resume command'
Require $runbook 'implementation_route: adaptive' 'fresh Adaptive route metadata'
Require $runbook 'implementation_route_source: default' 'fresh Adaptive route source'
Require $runbook 'Issue #69' 'Design Pair blocker'
Require $runbook 'model-lock claim unsupported or manual' 'capability honesty'
Require $template 'UNOBSERVABLE' 'real evidence uncertainty status'
Require $template 'BLOCKED' 'Design Pair blocker status'
Require $harness '--target.*copilot,agent-skills' 'harness Copilot targets'
Require $harness 'copilot.*skill.*list' 'harness Skill discovery'
Require $harness 'local-skill-only' 'local development limitation'
Forbid $harness 'GetTempPath|\\btemp\\b' 'system temporary-directory dependency'

if ($null -ne $fixture) {
    if ($fixture.schema_version -ne 1) { Fail 'Qualification fixture schema_version must be 1' }
    if ($fixture.package -cne 'plan-coverage-residual-flow') { Fail 'Qualification fixture package name mismatch' }

    foreach ($source in @($fixture.canonical_sources)) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$source)) -PathType Leaf)) {
            Fail "Missing canonical source referenced by fixture: $source"
        }
    }

    $targets = @($fixture.installation.targets)
    if ((($targets | Sort-Object) -join ',') -cne 'agent-skills,copilot') {
        Fail 'Qualification fixture installation targets must be copilot and agent-skills'
    }
    if ($fixture.installation.deployed_skill -cne '.agents/skills/plan-coverage-residual-flow/SKILL.md') {
        Fail 'Qualification fixture deployed Skill path is incorrect'
    }
    foreach ($command in @('install', 'check', 'update_preview', 'rollback', 'cli_discovery')) {
        if ([string]::IsNullOrWhiteSpace([string]$fixture.installation.commands.$command)) {
            Fail "Qualification fixture is missing installation command: $command"
        }
    }

    $authorization = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $fixture.authorization_source.path) | ConvertFrom-Json
    $authorizationById = @{}
    foreach ($scenario in @($authorization)) {
        $authorizationById[[string]$scenario.id] = [bool]$scenario.expected_authorized
    }
    foreach ($positive in @($fixture.authorization_source.positive_ids)) {
        if (-not $authorizationById.ContainsKey([string]$positive) -or -not $authorizationById[[string]$positive]) {
            Fail "Authorization positive fixture is not authorized: $positive"
        }
    }
    foreach ($negative in @($fixture.authorization_source.negative_ids)) {
        if (-not $authorizationById.ContainsKey([string]$negative) -or $authorizationById[[string]$negative]) {
            Fail "Authorization negative fixture is authorized: $negative"
        }
    }
    if ((@($fixture.authorization_source.positive_ids).Count + @($fixture.authorization_source.negative_ids).Count) -ne $authorizationById.Count) {
        Fail 'Authorization fixture mapping does not cover every A-H scenario'
    }
    foreach ($extension in @($fixture.authorization_extensions)) {
        if ([string]$extension.kind -notin @('quotation', 'comparison', 'informational')) {
            Fail "Unsupported authorization extension kind: $($extension.id)"
        }
        if ([string]$extension.prompt -notmatch 'plan-coverage-residual-flow' -or $extension.expected_authorized -ne $false) {
            Fail "Authorization extension must reject non-invocation mention: $($extension.id)"
        }
    }
    foreach ($durable in @($fixture.durable_authorization)) {
        $complete = $durable.process_route -ceq 'plan-coverage-residual-flow' -and
            $durable.process_route_source -ceq 'explicit-user-selection' -and
            [string]$durable.user_selection_evidence -cmatch '^(?:user-message|user-turn):.+'
        if (($complete -and $durable.expected -ne 'accepted') -or (-not $complete -and $durable.expected -ne 'blocked')) {
            Fail "Durable authorization tuple classification is incorrect: $($durable.id)"
        }
    }

    $levels = @($fixture.documentation_levels)
    foreach ($requiredLevel in @('lite', 'standard')) {
        $level = $levels | Where-Object { $_.id -ceq $requiredLevel }
        if ($null -eq $level -or $level.value -cne $requiredLevel -or $level.expected -cne 'allowed') {
            Fail "Documentation level is not allowed by fixture: $requiredLevel"
        }
    }
    $strict = $levels | Where-Object { $_.id -ceq 'strict' }
    if ($null -eq $strict -or $strict.expected -cne 'forbidden') {
        Fail 'Fixture must forbid strict as a documentation level'
    }
    $fullCoverage = $levels | Where-Object { $_.id -ceq 'full-coverage' }
    if ($null -eq $fullCoverage -or $fullCoverage.expected -cne 'process-profile-not-documentation-level') {
        Fail 'Fixture must keep full-coverage as a process profile'
    }

    foreach ($route in @($fixture.route_metadata)) {
        $pairIsValid = (
            ($route.implementation_route -ceq 'adaptive' -and $route.implementation_route_source -ceq 'default' -and $route.design_pair_handoff -ceq 'N/A') -or
            ($route.implementation_route -ceq 'design-pair' -and $route.implementation_route_source -ceq 'explicit-user-selection' -and $route.design_pair_handoff -ne 'N/A')
        )
        $expected = if ($route.design_pair_evidence -eq $true) { 'blocked' } else { $route.expected }
        $accepted = $pairIsValid -and $route.design_pair_evidence -ne $true
        if ($accepted -and $expected -ne 'accepted') {
            Fail "Valid route metadata is not accepted: $($route.id)"
        }
        if (-not $accepted -and $expected -ne 'blocked') {
            Fail "Invalid route metadata is not blocked: $($route.id)"
        }
    }

    $handoffRequired = @($fixture.adaptive_handoff.required_fields)
    foreach ($requiredField in @('Verdict', 'implementation_route', 'implementation_route_source', 'Design Pair handoff', 'Acceptance status', 'Remaining work', 'Allowed edit surface', 'Validation commands', 'High-model re-entry triggers')) {
        if ($handoffRequired -notcontains $requiredField) {
            Fail "Adaptive handoff fixture is missing required field: $requiredField"
        }
    }
    foreach ($verdict in @('READY_FOR_STANDARD_COMPLETION', 'COMPLETED', 'NEEDS_HIGH_MODEL_REENTRY', 'COMPLETED_BY_HIGH_MODEL')) {
        if (@($fixture.adaptive_handoff.required_verdict_sequence) -notcontains $verdict) {
            Fail "Adaptive handoff fixture is missing verdict: $verdict"
        }
    }
    if ($fixture.adaptive_handoff.mapping_rules.complete_requires_evidence -ne $true -or
        $fixture.adaptive_handoff.mapping_rules.incomplete_requires_remaining_work_id -ne $true -or
        $fixture.adaptive_handoff.mapping_rules.remaining_work_requires_incomplete_acceptance -ne $true -or
        $fixture.adaptive_handoff.mapping_rules.blocked_acceptance_forbids_standard_handoff -ne $true) {
        Fail 'Adaptive handoff fixture does not require bidirectional acceptance mapping and blocked-item rejection'
    }

    $scenarioIds = @($fixture.real_cli_scenarios | ForEach-Object { [string]$_.id })
    foreach ($requiredId in @('install-and-skill-discovery', 'explicit-lite', 'explicit-standard', 'unauthorized-generic', 'unauthorized-question-comparison-negation', 'durable-authorized-resume', 'default-adaptive-route', 'high-to-standard-completion', 'high-reentry', 'blocked-human-decision-replan', 'architecture-slice-readiness', 'two-slice-v2', 'independent-verification', 'final-record-residual-decision', 'new-session-resume', 'stale-incomplete-artifact-failure', 'design-pair-e2e')) {
        if ($scenarioIds -notcontains $requiredId) {
            Fail "Real CLI scenario is missing: $requiredId"
        }
    }
    $designPairScenario = $fixture.real_cli_scenarios | Where-Object { $_.id -ceq 'design-pair-e2e' }
    if ($null -eq $designPairScenario -or $designPairScenario.default_status -cne 'BLOCKED' -or $designPairScenario.blocker -notmatch 'Issue #69') {
        Fail 'Design Pair scenario must remain explicitly blocked by Issue #69'
    }
}

$packageFiles = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'apm-packages/plan-coverage-residual-flow') -Recurse -File |
    Where-Object { $_.FullName -ne $PSCommandPath }
foreach ($file in $packageFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    Forbid $text '(?i)codex-first|copilot-fallback' "retired aggregate dependency in $($file.FullName.Substring($repoRoot.Length + 1))"
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure -ErrorAction Continue
    }
    throw "Plan Coverage Copilot qualification validation failed with $($failures.Count) error(s)."
}

Write-Host 'Plan Coverage Copilot qualification validation: PASS'
