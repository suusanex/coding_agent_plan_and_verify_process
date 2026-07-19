[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Assert-FileExists {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing file: $RelativePath"
    }
}

function Assert-Contains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -notmatch $Pattern) {
        Add-Failure "$RelativePath does not contain $Description"
    }
}

function Assert-NotContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

function Get-TomlString {
    param(
        [string]$RelativePath,
        [string]$Key
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    $match = Select-String -LiteralPath $path -Pattern ("^\s*" + [regex]::Escape($Key) + '\s*=\s*"([^"]+)"\s*$') | Select-Object -First 1
    if ($null -eq $match) {
        return $null
    }

    return $match.Matches[0].Groups[1].Value
}

function Get-FrontmatterString {
    param(
        [string]$RelativePath,
        [string]$Key
    )

    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    $match = Select-String -LiteralPath $path -Pattern ("^" + [regex]::Escape($Key) + ':\s*(.+?)\s*$') | Select-Object -First 1
    if ($null -eq $match) {
        return $null
    }

    return $match.Matches[0].Groups[1].Value
}

$requiredFiles = @(
    '.github/agents/high-implementation-starter.agent.md',
    '.github/agents/standard-implementation-completer.agent.md',
    '.github/workflows/validate-adaptive-implementation-execution.yml',
    '.github/workflows/validate-design-pair-implementation-execution.yml',
    'apm-packages/adaptive-implementation-execution/apm.yml',
    'apm-packages/adaptive-implementation-execution/README.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/intent.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md',
    'apm-packages/adaptive-implementation-execution/codex-agents/high-implementation-starter.toml',
    'apm-packages/adaptive-implementation-execution/codex-agents/standard-implementation-completer.toml',
    'apm-packages/adaptive-implementation-execution/docs/install-guide.md',
    'apm-packages/adaptive-implementation-execution/docs/usage-guide.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/legacy-adaptive-handoff.md',
    'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs',
    'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1',
    'apm-packages/design-pair-implementation-execution/apm.yml',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/handoff.md',
    'apm-packages/token-aware-guardrail-kernel-flow/apm.yml',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/token-aware-full-coverage-3layer/apm.yml',
    'apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md',
    'apm-packages/codex-first-ai-development-process/apm.yml',
    'apm-packages/codex-first-ai-development-process/templates/codex-first-state.md',
    'apm-packages/codex-first-ai-development-process/templates/codex-first-audit.md',
    'apm-packages/codex-first-ai-development-process/scripts/codex-first-start.ps1',
    'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/high-implementation-starter.toml',
    'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-implementation-completer.toml',
    'apm-packages/copilot-fallback-ai-development-process/apm.yml',
    'apm-packages/copilot-fallback-ai-development-process/templates/codex-first-state.md',
    'apm-packages/copilot-fallback-ai-development-process/templates/github/agents/high-implementation-starter.agent.md',
    'apm-packages/copilot-fallback-ai-development-process/templates/github/agents/standard-implementation-completer.agent.md',
    'scripts/provision-work-repo-agents.cs'
)

foreach ($file in $requiredFiles) {
    Assert-FileExists $file
}

$packageAgentsFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution') -Filter 'AGENTS.md' -File -Recurse)
if ($packageAgentsFiles.Count -gt 0) {
    Add-Failure ('Package must not contain AGENTS.md guidance: ' + (($packageAgentsFiles.FullName) -join ', '))
}

$manifest = 'apm-packages/adaptive-implementation-execution/apm.yml'
Assert-Contains $manifest '(?m)^name:\s*adaptive-implementation-execution\s*$' 'package name'
Assert-Contains $manifest '(?m)^version:\s*0\.2\.0\s*$' 'package version 0.2.0'
Assert-Contains $manifest '(?m)^\s*-\s+codex\s*$' 'codex target'
Assert-Contains $manifest '(?m)^\s*-\s+agent-skills\s*$' 'agent-skills target'
Assert-NotContains $manifest '(?m)^\s*-\s+copilot\s*$' 'unverified Copilot target'
Assert-NotContains $manifest 'token-aware|codex-first|plan-coverage' 'Plan Coverage or Codex-first dependency'
Assert-NotContains $manifest 'path:\s+.*(?:implementation-intent|implementation-completion-handoff)\.md' 'standalone template dependency'

# APM 0.18.0 materializes the complete package below a deep Git cache prefix on Windows.
# Keep every repository-relative package path bounded instead of checking only deployed skill files.
$maxWindowsPackagePathLength = 110
$packageRelativeRoot = 'apm-packages/adaptive-implementation-execution'
$packageFiles = @(& git -C $repoRoot ls-files --cached --others --exclude-standard -- $packageRelativeRoot)
if ($LASTEXITCODE -ne 0) {
    Add-Failure 'Cannot enumerate Git package payload for Windows path compatibility validation'
}
foreach ($relativePath in $packageFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
        continue
    }
    if ($relativePath.Length -gt $maxWindowsPackagePathLength) {
        Add-Failure "APM package path exceeds Windows compatibility budget ($($relativePath.Length) > $maxWindowsPackagePathLength): $relativePath"
    }
}

$manifestPath = Join-Path $repoRoot $manifest
if (Test-Path -LiteralPath $manifestPath) {
    $dependencyPaths = Select-String -LiteralPath $manifestPath -Pattern '^\s*path:\s*(.+?)\s*$' | ForEach-Object {
        $_.Matches[0].Groups[1].Value.Trim()
    }
    foreach ($dependencyPath in $dependencyPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $dependencyPath))) {
            Add-Failure "Manifest dependency does not exist: $dependencyPath"
        }
    }
}

$integratedManifests = @(
    @{ Path = 'apm-packages/token-aware-guardrail-kernel-flow/apm.yml'; Version = '0\.6\.0' },
    @{ Path = 'apm-packages/token-aware-full-coverage-3layer/apm.yml'; Version = '0\.4\.0' },
    @{ Path = 'apm-packages/codex-first-ai-development-process/apm.yml'; Version = '0\.5\.0' },
    @{ Path = 'apm-packages/copilot-fallback-ai-development-process/apm.yml'; Version = '0\.2\.0' }
)

foreach ($integratedManifest in $integratedManifests) {
    $integratedManifestPath = $integratedManifest.Path
    Assert-Contains $integratedManifestPath ("(?m)^version:\s*" + $integratedManifest.Version + '\s*$') "expected package version $($integratedManifest.Version -replace '\\', '')"

    $absoluteManifestPath = Join-Path $repoRoot $integratedManifestPath
    if (-not (Test-Path -LiteralPath $absoluteManifestPath)) {
        continue
    }

    $dependencyPaths = Select-String -LiteralPath $absoluteManifestPath -Pattern '^\s*path:\s*(.+?)\s*$' | ForEach-Object {
        $_.Matches[0].Groups[1].Value.Trim()
    }
    foreach ($dependencyPath in $dependencyPaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $dependencyPath))) {
            Add-Failure "$integratedManifestPath dependency does not exist: $dependencyPath"
        }
    }
}

foreach ($integratedManifestPath in @(
    'apm-packages/token-aware-guardrail-kernel-flow/apm.yml',
    'apm-packages/token-aware-full-coverage-3layer/apm.yml',
    'apm-packages/codex-first-ai-development-process/apm.yml',
    'apm-packages/copilot-fallback-ai-development-process/apm.yml'
)) {
    Assert-Contains $integratedManifestPath 'apm-packages/adaptive-implementation-execution/\.apm/skills/adaptive-implementation-execution' 'Adaptive Implementation skill dependency'
    Assert-Contains $integratedManifestPath '\.github/agents/high-implementation-starter\.agent\.md' 'canonical HIGH agent dependency'
    Assert-Contains $integratedManifestPath '\.github/agents/standard-implementation-completer\.agent\.md' 'canonical STANDARD agent dependency'
    Assert-Contains $integratedManifestPath '\.github/agents/implementation-execution\.agent\.md' 'legacy implementation dependency'
}

$planCoverageSkill = 'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md'
Assert-Contains $planCoverageSkill 'Every non-trivial pass starts with `high-implementation-starter\.agent\.md` on `HIGH_MODEL`' 'Plan Coverage HIGH_MODEL start'
Assert-Contains $planCoverageSkill '`READY_FOR_STANDARD_COMPLETION`.*`standard-implementation-completer\.agent\.md`' 'Plan Coverage bounded STANDARD completion'
Assert-Contains $planCoverageSkill '`NEEDS_HIGH_MODEL_REENTRY`.*`high-implementation-starter\.agent\.md`' 'Plan Coverage HIGH_MODEL re-entry'
Assert-Contains $planCoverageSkill 'plans/<slug>-implementation-execution\.md' 'stable implementation result artifact name'
Assert-Contains $planCoverageSkill 'completion handoff inline unless resume, another thread/model, or another worker requires a tracked' 'inline completion handoff default'
Assert-Contains $planCoverageSkill 'Implementation Self-Map Delta' 'per-phase implementation traceability delta'
Assert-Contains $planCoverageSkill 'Related Plan item.*Related Behavior Case IDs.*Related SL / XC / RC / TP / IC / Gap item.*Assumption made.*Review hint' 'complete Self-Map traceability schema'
Assert-Contains $planCoverageSkill 'orchestrator is the single aggregation owner' 'Self-Map aggregation ownership'
Assert-Contains '.github/agents/change-risk-triage.agent.md' 'implementation-internal.*implementation phase' 'risk triage shape boundary'

$codexRouter = 'apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md'
Assert-Contains $codexRouter 'let `high-implementation-starter` resolve implementation-internal design uncertainty' 'HIGH_MODEL implementation-internal uncertainty ownership'
Assert-Contains $codexRouter 'stop only when the Plan, authorized scope, or acceptance criteria must change' 'HIGH_MODEL stop boundary'
Assert-Contains $codexRouter '`STANDARD_MODEL`: bounded implementation completion after a valid handoff' 'STANDARD_MODEL bounded completion summary'
Assert-NotContains $codexRouter '`STANDARD_MODEL`: normal implementation' 'legacy STANDARD_MODEL normal implementation summary'
Assert-NotContains $codexRouter 'stop if new design uncertainty appears' 'reversed design-uncertainty stop condition'

$fullCoverageSkill = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md'
Assert-Contains $fullCoverageSkill 'non-trivial READY slice.*high-implementation-starter' 'per-slice HIGH_MODEL start'
Assert-Contains $fullCoverageSkill 'READY_FOR_STANDARD_COMPLETION.*standard-implementation-completer' 'per-slice STANDARD completion gate'
Assert-Contains $fullCoverageSkill 'NEEDS_HIGH_MODEL_REENTRY.*high-implementation-starter' 'per-slice HIGH_MODEL re-entry'
Assert-Contains $fullCoverageSkill 'HIGH and STANDARD write owners did not overlap' 'per-slice serial ownership audit'
Assert-Contains $fullCoverageSkill '`slice-impl`.*legacy compatibility' 'legacy slice implementation notice'
Assert-Contains $fullCoverageSkill 'BlockedByMissingAdaptiveImplementationDelegation' 'missing adaptive delegation blocker'
Assert-Contains $fullCoverageSkill 'plans/<ticket-or-slug>-implementation-execution\.md' 'full-coverage durable implementation result artifact'
Assert-Contains $fullCoverageSkill 'Completion Handoff.*inline' 'full-coverage inline completion handoff default'
$fullCoverageInstruction = 'apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md'
Assert-Contains $fullCoverageInstruction 'high-implementation-starter' 'full-coverage instruction HIGH start'
Assert-Contains $fullCoverageInstruction 'standard-implementation-completer' 'full-coverage instruction STANDARD completion'
Assert-Contains $fullCoverageInstruction 'NEEDS_HIGH_MODEL_REENTRY' 'full-coverage instruction HIGH re-entry'
Assert-Contains $fullCoverageInstruction '`slice-impl`.*legacy compatibility' 'full-coverage instruction legacy notice'
Assert-NotContains $fullCoverageInstruction 'BlockedByMissingSliceImplDelegation' 'obsolete missing slice-impl blocker'

Assert-Contains '.github/agents/implementation-execution.agent.md' 'Compatibility status: legacy' 'legacy Plan Coverage implementation notice'
Assert-Contains 'apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md' 'Compatibility status: legacy' 'legacy slice implementation notice'
Assert-Contains 'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-implementer.toml' 'Compatibility status: legacy' 'legacy Codex-first implementation notice'
Assert-Contains 'apm-packages/copilot-fallback-ai-development-process/templates/github/agents/copilot-standard-implementer.agent.md' 'Compatibility status: legacy' 'legacy Copilot implementation notice'

$skill = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
Assert-Contains $skill 'high-implementation-starter' 'HIGH_MODEL start route'
Assert-Contains $skill 'standard-implementation-completer' 'STANDARD_MODEL completion route'
Assert-Contains $skill 'READY_FOR_STANDARD_COMPLETION' 'standard delegation gate'
Assert-Contains $skill 'NEEDS_HIGH_MODEL_REENTRY' 'HIGH_MODEL re-entry route'
Assert-Contains $skill 'write-heavy agent を並列に起動しません' 'write-heavy serial execution rule'
Assert-Contains $skill 'Plan Coverage artifacts が存在しないことは blocker ではありません' 'Plan Coverage independence'
Assert-Contains $skill 'Final review status' 'final review boundary'
Assert-Contains $skill 'Validation expectation: inferred from repository' 'validation inference reporting'
Assert-Contains $skill 'acceptance status table' 'acceptance evidence output'
Assert-Contains $skill 'delegation_surface_reduced' 'bounded re-delegation evidence'
Assert-Contains $skill 'N/A.*理由' 'evidence-backed applicability N/A'
Assert-Contains $skill 'incoming value \+ 1' 're-entry count increment rule'
Assert-Contains $skill '双方向に一致' 'bidirectional acceptance mapping gate'
Assert-Contains $skill 'existing code から scope を狭めない' 'safe non-goal inference rule'
Assert-Contains $skill 'package が導入されているだけで.*自動適用しません' 'non-automatic skill selection rule'
Assert-Contains $skill 'Design Pair Implementation Handoff' 'Design Pair handoff input support'
Assert-Contains $skill '(?s)binding なのは.*Locked Decisions.*だけ' 'Design Pair binding-only rule'
Assert-Contains $skill 'Affected files / symbols.*Allowed edit surface.*扱いません' 'Design Pair file-symbol non-allowlist rule'
Assert-Contains $skill 'automatic Design Pair re-entry' 'no automatic Design Pair re-entry'
Assert-Contains $skill '新規 intake と resume を分けます' 'fresh intake and resume distinction'
Assert-Contains $skill '欠落や矛盾を Adaptive へ補完しません' 'resume route fail-closed rule'
Assert-Contains $skill 'route_metadata_normalization: legacy-adaptive-handoff' 'legacy handoff normalization marker'

$highAgent = '.github/agents/high-implementation-starter.agent.md'
Assert-Contains $highAgent 'edit production code and tests' 'real implementation loop'
Assert-Contains $highAgent 'CONTINUE_HIGH_IMPLEMENTATION' 'continue-high verdict'
Assert-Contains $highAgent 'COMPLETED_BY_HIGH_MODEL' 'high completion verdict'
Assert-Contains $highAgent 'Allowed edit surface' 'handoff allowed surface'
Assert-Contains $highAgent 'acceptance status table' 'high-model acceptance evidence output'
Assert-Contains $highAgent '一度 re-entry した後' 'high-model re-entry ownership'
Assert-Contains $highAgent 'すべての `Incomplete` acceptance item' 'high-model incomplete acceptance mapping gate'
Assert-Contains $highAgent 're-entry handoff の `reentry_count` を維持' 'high-model re-entry count propagation'
Assert-Contains $highAgent 'You are the "High Implementation Starter" agent\.' 'APM stub high-agent opening'
Assert-Contains $highAgent 'Implementation Self-Map Delta' 'HIGH_MODEL Self-Map delta output'
Assert-Contains $highAgent 'Related Plan item.*Related Behavior Case IDs.*Related SL / XC / RC / TP / IC / Gap item.*Assumption made.*Review hint' 'HIGH_MODEL Self-Map schema'
Assert-Contains $highAgent 'Design Pair Implementation Handoff' 'HIGH_MODEL Design Pair input support'
Assert-Contains $highAgent 'Locked Decision conflict' 'HIGH_MODEL Locked Decision conflict stop'

$standardAgent = '.github/agents/standard-implementation-completer.agent.md'
Assert-Contains $standardAgent 'NEEDS_HIGH_MODEL_REENTRY' 're-entry verdict'
Assert-Contains $standardAgent 'Locked decisions' 'locked decision boundary'
Assert-Contains $standardAgent 'Allowed edit surface' 'allowed edit boundary'
Assert-Contains $standardAgent 'Final code review performed|final review status' 'review boundary'
Assert-Contains $standardAgent 'acceptance status table' 'standard-model acceptance evidence output'
Assert-Contains $standardAgent '一度 re-entry した後' 'standard-model re-entry ownership'
Assert-Contains $standardAgent 'incoming Implementation Completion Handoff の値に1を加える' 'standard-model re-entry count increment'
Assert-Contains $standardAgent '双方向に一致' 'standard-model acceptance mapping authorization'
Assert-Contains $standardAgent 'You are the "Standard Implementation Completer" agent\.' 'APM stub standard-agent opening'
Assert-Contains $standardAgent 'Implementation Self-Map Delta' 'STANDARD_MODEL Self-Map delta output'
Assert-Contains $standardAgent 'Related Plan item.*Related Behavior Case IDs.*Related SL / XC / RC / TP / IC / Gap item.*Assumption made.*Review hint' 'STANDARD_MODEL Self-Map schema'
Assert-Contains $standardAgent 'Design Pair Decision IDs' 'STANDARD_MODEL Design Pair Decision propagation'
Assert-Contains $standardAgent 'Legacy Adaptive handoff normalization' 'STANDARD_MODEL legacy handoff normalization'
Assert-Contains $standardAgent 'LEGACY-HIGH-D01' 'STANDARD_MODEL deterministic legacy Decision IDs'
Assert-Contains $standardAgent 'Design Pair evidenceがあるresume.*使用しません' 'legacy normalization excludes Design Pair resumes'

$handoff = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md'
foreach ($field in @(
    'Verdict',
    'Handoff persistence',
    'Plan reference',
    'Validation performed',
    'Acceptance status',
    'Applicability evidence',
    'Implemented',
    'Locked decisions',
    'Remaining work',
    'Allowed edit surface',
    'Validation commands',
    'High-model re-entry triggers',
    'reentry_count',
    'previous_reentry_trigger',
    'delegation_surface_reduced',
    'Known assumptions / unresolved observations',
    'Design Pair handoff',
    'Design Pair Decision compliance'
)) {
    Assert-Contains $handoff ([regex]::Escape($field)) "handoff field $field"
}
Assert-Contains $handoff 'Remaining work mapping \(Work ID\)' 'acceptance-to-work mapping column'
Assert-Contains $handoff 'Work ID.*Acceptance item\(s\)' 'work-to-acceptance mapping columns'
Assert-Contains $handoff '`Blocked` を許可しない' 'blocked acceptance rejection'
Assert-Contains $handoff 'Origin.*Decision ID.*Decision.*Affected files / symbols.*Validation expectation.*Compliance evidence' 'consolidated locked decision schema'
Assert-Contains $handoff 'Legacy Adaptive handoff normalization' 'legacy Adaptive handoff normalization contract'
Assert-Contains $handoff 'LEGACY-HIGH-D01' 'deterministic legacy Decision ID rule'

$legacyFixture = 'apm-packages/adaptive-implementation-execution/docs/examples/legacy-adaptive-handoff.md'
Assert-Contains $legacyFixture 'Verdict: READY_FOR_STANDARD_COMPLETION' 'legacy handoff READY verdict'
Assert-Contains $legacyFixture '## Locked decisions\s*\r?\n\s*- ' 'legacy bullet-form Locked decisions'
Assert-NotContains $legacyFixture 'Design Pair handoff|Design Pair Decision compliance|\| Origin \| Decision ID \|' 'new Design Pair fields in legacy fixture'
foreach ($legacyField in @(
    'Plan reference',
    'Validation performed',
    'Acceptance status',
    'Applicability evidence',
    'Implemented',
    'Remaining work',
    'Allowed edit surface',
    'Validation commands',
    'High-model re-entry triggers',
    'reentry_count',
    'previous_reentry_trigger',
    'delegation_surface_reduced',
    'Known assumptions / unresolved observations'
)) {
    Assert-Contains $legacyFixture ([regex]::Escape($legacyField)) "legacy handoff former required field $legacyField"
}

$highToml = 'apm-packages/adaptive-implementation-execution/codex-agents/high-implementation-starter.toml'
$standardToml = 'apm-packages/adaptive-implementation-execution/codex-agents/standard-implementation-completer.toml'
foreach ($toml in @($highToml, $standardToml)) {
    Assert-Contains $toml '(?m)^model\s*=\s*"[^"]+"\s*$' 'top-level model'
    Assert-Contains $toml '(?m)^model_reasoning_effort\s*=\s*"[^"]+"\s*$' 'top-level reasoning effort'
    Assert-Contains $toml '(?m)^sandbox_mode\s*=\s*"workspace-write"\s*$' 'workspace-write sandbox'
}

$highAgentName = Get-TomlString $highToml 'name'
$standardAgentName = Get-TomlString $standardToml 'name'
$highModel = Get-TomlString $highToml 'model'
$standardModel = Get-TomlString $standardToml 'model'
$highConfigDescription = Get-TomlString $highToml 'description'
$standardConfigDescription = Get-TomlString $standardToml 'description'
$highPortableDescription = Get-FrontmatterString $highAgent 'description'
$standardPortableDescription = Get-FrontmatterString $standardAgent 'description'
if ($highAgentName -ne 'high-implementation-starter') {
    Add-Failure "$highToml has an unexpected agent name: $highAgentName"
}
if ($standardAgentName -ne 'standard-implementation-completer') {
    Add-Failure "$standardToml has an unexpected agent name: $standardAgentName"
}
if ($highAgentName -eq $standardAgentName) {
    Add-Failure 'HIGH_MODEL and STANDARD_MODEL must reference different custom agents'
}
if ($highModel -eq $standardModel) {
    Add-Failure 'HIGH_MODEL and STANDARD_MODEL must use distinct model mappings'
}
if ($highConfigDescription -ne $highPortableDescription) {
    Add-Failure 'HIGH_MODEL TOML and portable agent descriptions must match for APM stub recognition'
}
if ($standardConfigDescription -ne $standardPortableDescription) {
    Add-Failure 'STANDARD_MODEL TOML and portable agent descriptions must match for APM stub recognition'
}

$codexHighToml = 'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/high-implementation-starter.toml'
$codexStandardToml = 'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-implementation-completer.toml'
foreach ($mapping in @(
    @{ Adaptive = $highToml; CodexFirst = $codexHighToml },
    @{ Adaptive = $standardToml; CodexFirst = $codexStandardToml }
)) {
    foreach ($key in @('name', 'model', 'model_reasoning_effort', 'sandbox_mode')) {
        $adaptiveValue = Get-TomlString $mapping.Adaptive $key
        $codexFirstValue = Get-TomlString $mapping.CodexFirst $key
        if ($adaptiveValue -ne $codexFirstValue) {
            Add-Failure "$($mapping.CodexFirst) $key must match $($mapping.Adaptive): expected '$adaptiveValue', got '$codexFirstValue'"
        }
    }
}

$provisioner = 'scripts/provision-work-repo-agents.cs'
$highReasoningEffort = Get-TomlString $highToml 'model_reasoning_effort'
$standardReasoningEffort = Get-TomlString $standardToml 'model_reasoning_effort'
$highSandboxMode = Get-TomlString $highToml 'sandbox_mode'
$standardSandboxMode = Get-TomlString $standardToml 'sandbox_mode'
Assert-Contains $provisioner ([regex]::Escape('private const string HighImplementationStarterFileName = "high-implementation-starter.toml";')) 'canonical HIGH provision target'
Assert-Contains $provisioner ([regex]::Escape('private const string StandardImplementationCompleterFileName = "standard-implementation-completer.toml";')) 'canonical STANDARD provision target'
Assert-Contains $provisioner ([regex]::Escape('private const string HighImplementationModel = "' + $highModel + '";')) 'canonical HIGH provision model mapping'
Assert-Contains $provisioner ([regex]::Escape('private const string StandardImplementationModel = "' + $standardModel + '";')) 'canonical STANDARD provision model mapping'
if ($highReasoningEffort -ne $standardReasoningEffort) {
    Add-Failure 'Adaptive HIGH_MODEL and STANDARD_MODEL reasoning effort must share the provisioner constant'
}
else {
    Assert-Contains $provisioner ([regex]::Escape('private const string AdaptiveImplementationReasoningEffort = "' + $highReasoningEffort + '";')) 'Adaptive provision reasoning effort'
}
if ($highSandboxMode -ne $standardSandboxMode) {
    Add-Failure 'Adaptive HIGH_MODEL and STANDARD_MODEL sandbox mode must share the provisioner constant'
}
else {
    Assert-Contains $provisioner ([regex]::Escape('private const string AdaptiveImplementationSandboxMode = "' + $highSandboxMode + '";')) 'Adaptive provision sandbox mode'
}
Assert-Contains $provisioner '(?s)HighImplementationStarterDefaults\s*=.*?\["model"\]\s*=\s*HighImplementationModel.*?\["model_reasoning_effort"\]\s*=\s*AdaptiveImplementationReasoningEffort.*?\["sandbox_mode"\]\s*=\s*AdaptiveImplementationSandboxMode' 'canonical HIGH provision defaults'
Assert-Contains $provisioner '(?s)StandardImplementationCompleterDefaults\s*=.*?\["model"\]\s*=\s*StandardImplementationModel.*?\["model_reasoning_effort"\]\s*=\s*AdaptiveImplementationReasoningEffort.*?\["sandbox_mode"\]\s*=\s*AdaptiveImplementationSandboxMode' 'canonical STANDARD provision defaults'
Assert-Contains $provisioner '(?s)HighImplementationStarterFileName,\s*SliceImplOrder,\s*HighImplementationStarterDefaults,\s*options\.Force,\s*true,' 'canonical HIGH expected-value enforcement'
Assert-Contains $provisioner '(?s)StandardImplementationCompleterFileName,\s*SliceImplOrder,\s*StandardImplementationCompleterDefaults,\s*options\.Force,\s*true,' 'canonical STANDARD expected-value enforcement'
Assert-Contains $provisioner 'mismatch; use --force to overwrite' 'canonical mapping mismatch guidance'

foreach ($stateTemplate in @(
    'apm-packages/codex-first-ai-development-process/templates/codex-first-state.md',
    'apm-packages/copilot-fallback-ai-development-process/templates/codex-first-state.md'
)) {
    Assert-Contains $stateTemplate 'shape_handoff_status: NotStarted / Pending / Ready / Consumed / Invalidated / NotRequired / Blocked / Unknown' 'shape handoff status enum'
    Assert-Contains $stateTemplate 'remaining_design_uncertainty: None / Unknown / <evidence-backed summary>' 'remaining design uncertainty field'
    Assert-Contains $stateTemplate 'completion_scope: N/A / Unknown / <Work IDs and allowed edit surface>' 'completion scope field'
    Assert-Contains $stateTemplate 'shape_reentry_reason: N/A / Unknown / <trigger and invalidating evidence>' 'shape re-entry reason field'
    Assert-Contains $stateTemplate '`shape_\*` fields are stable state vocabulary only' 'shape field compatibility rationale'
    foreach ($stopReason in @('ReadyForHighImplementationStart', 'ReadyForStandardCompletion', 'NeedsHighModelReentry', 'BlockedByInvalidCompletionHandoff', 'ReadyForDelegatedImplementation')) {
        Assert-Contains $stateTemplate $stopReason "stop reason $stopReason"
    }
    Assert-Contains $stateTemplate 'high-implementation-starter' 'HIGH implementation owner'
    Assert-Contains $stateTemplate 'standard-implementation-completer' 'STANDARD completion owner'
    Assert-Contains $stateTemplate 'standard-verifier|copilot-standard-verifier' 'verification owner'
    Assert-Contains $stateTemplate 'delegation_required.*(?:Yes|true).*HIGH implementation start/re-entry.*STANDARD completion|DelegationRequired = Yes.*HIGH implementation start/re-entry.*STANDARD completion' 'delegation required rule for both implementation owners'
}

$auditTemplate = 'apm-packages/codex-first-ai-development-process/templates/codex-first-audit.md'
Assert-Contains $auditTemplate 'HIGH implementation started before any standard completion' 'HIGH start audit row'
Assert-Contains $auditTemplate 'STANDARD completion delegated only after valid handoff' 'valid STANDARD handoff audit row'
Assert-Contains $auditTemplate 'NEEDS_HIGH_MODEL_REENTRY returned to HIGH implementation' 'HIGH re-entry audit row'
Assert-Contains $auditTemplate 'HIGH and STANDARD write ownership did not overlap' 'serial write ownership audit row'

$copilotHighAgent = 'apm-packages/copilot-fallback-ai-development-process/templates/github/agents/high-implementation-starter.agent.md'
$copilotStandardAgent = 'apm-packages/copilot-fallback-ai-development-process/templates/github/agents/standard-implementation-completer.agent.md'
Assert-Contains $copilotHighAgent '(?m)^name:\s*high-implementation-starter\s*$' 'Copilot canonical HIGH agent name'
Assert-Contains $copilotHighAgent '(?m)^model:\s*GPT-5\.6 Terra \(copilot\)\s*$' 'Copilot HIGH model mapping'
Assert-Contains $copilotHighAgent 'agent: standard-implementation-completer' 'Copilot completion handoff'
Assert-Contains $copilotHighAgent 'edit real production code and tests' 'Copilot real implementation loop'
Assert-Contains $copilotHighAgent 'READY_FOR_STANDARD_COMPLETION' 'Copilot HIGH handoff verdict'
Assert-Contains $copilotHighAgent 'COMPLETED_BY_HIGH_MODEL' 'Copilot HIGH completion verdict'
Assert-Contains $copilotHighAgent 'Blocked acceptance items' 'Copilot blocked acceptance rejection'
Assert-Contains $copilotHighAgent 'evidence for Complete items' 'Copilot complete acceptance evidence rule'
Assert-Contains $copilotHighAgent 'Own completion unless both Remaining work and Allowed edit surface strictly shrink' 'Copilot re-entry ownership rule'
Assert-Contains $copilotHighAgent 'Implementation Self-Map Delta' 'Copilot HIGH Self-Map delta output'
Assert-Contains $copilotStandardAgent '(?m)^name:\s*standard-implementation-completer\s*$' 'Copilot canonical STANDARD agent name'
Assert-Contains $copilotStandardAgent '(?m)^model:\s*GPT-5\.6 Luna \(copilot\)\s*$' 'Copilot STANDARD model mapping'
Assert-Contains $copilotStandardAgent 'agent: high-implementation-starter' 'Copilot HIGH re-entry handoff'
Assert-Contains $copilotStandardAgent 'NEEDS_HIGH_MODEL_REENTRY' 'Copilot HIGH re-entry verdict'
Assert-Contains $copilotStandardAgent 'Allowed edit surface' 'Copilot bounded edit surface'
Assert-Contains $copilotStandardAgent 'preserve Locked decisions' 'Copilot locked decision boundary'
Assert-Contains $copilotStandardAgent 'incremented reentry count' 'Copilot re-entry count rule'
Assert-Contains $copilotStandardAgent 'every in-scope acceptance item is Complete' 'Copilot completion evidence gate'
Assert-Contains $copilotStandardAgent 'Implementation Self-Map Delta' 'Copilot STANDARD Self-Map delta output'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'shape_handoff_status.*remaining_design_uncertainty.*completion_scope.*shape_reentry_reason' 'managed AGENTS Adaptive state guidance'

$codexInstaller = 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs'
Assert-Contains $codexInstaller 'sourceAdaptiveSkill' 'Adaptive skill bootstrap source'
Assert-Contains $codexInstaller 'sourceDesignPairSkill' 'Design Pair skill bootstrap source'
Assert-Contains $codexInstaller 'refs.*handoff\.md' 'complete handoff reference bootstrap check'
Assert-Contains $codexInstaller 'CopyCanonicalAgentFiles' 'canonical root agent bootstrap'
Assert-Contains $codexInstaller 'high-implementation-starter\.agent\.md' 'canonical HIGH agent bootstrap path'
Assert-Contains $codexInstaller 'standard-implementation-completer\.agent\.md' 'canonical STANDARD agent bootstrap path'
Assert-Contains 'README.md' '--check`.*canonical agent contracts.*`refs/handoff\.md`.*対象 repository' 'post-bootstrap file validation documentation'

$codexLauncher = 'apm-packages/codex-first-ai-development-process/scripts/codex-first-start.ps1'
Assert-Contains $codexLauncher 'adaptiveSkillSource' 'one-off launcher Adaptive skill source'
Assert-Contains $codexLauncher 'designPairSkillSource' 'one-off launcher Design Pair skill source'
Assert-Contains $codexLauncher 'skills\\adaptive-implementation-execution' 'one-off launcher Adaptive skill target'
Assert-Contains $codexLauncher 'skills\\design-pair-implementation-execution' 'one-off launcher Design Pair skill target'
Assert-Contains $codexLauncher 'Copy-Item.*adaptiveSkillSource\.Path' 'one-off launcher Adaptive payload copy'
Assert-Contains $codexLauncher 'Copy-Item.*designPairSkillSource\.Path' 'one-off launcher Design Pair payload copy'

$validation = 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md'
foreach ($id in 1..10) {
    $scenarioId = 'VAL-{0:D3}' -f $id
    Assert-Contains $validation $scenarioId "validation scenario $scenarioId"
}
foreach ($id in 1..5) {
    Assert-Contains $validation ("INT-00$id") "integration validation scenario INT-00$id"
}
Assert-Contains $validation '新規 service \+ DI \+ tests' 'new service integration scenario'
Assert-Contains $validation '大きな class からの責務分離' 'responsibility extraction integration scenario'
Assert-Contains $validation 'async \+ retry \+ cancellation' 'async retry cancellation integration scenario'
Assert-Contains $validation '既存 pattern が明確な早期 STANDARD 委譲' 'early STANDARD delegation integration scenario'
Assert-Contains $validation 'STANDARD 中の構造判断再発と HIGH re-entry' 'HIGH re-entry integration scenario'
Assert-Contains $validation '実モデル比較.*NOT RUN' 'manual runtime comparison status'

$installer = 'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs'
Assert-Contains $installer '(?m)^#:property TargetFramework=net10\.0\s*$' 'File-based app target framework'
Assert-Contains $installer '--dry-run' 'dry-run option'
Assert-Contains $installer '--check' 'check option'
Assert-Contains $installer '--remove' 'remove option'
Assert-Contains $installer 'ValidateAgentConfiguration' 'custom agent configuration validation'
Assert-Contains $installer 'must use distinct model mappings' 'distinct model mapping check'
Assert-Contains $installer 'must reference different custom agents' 'distinct custom agent check'
Assert-Contains $installer 'IsApmGeneratedAgentStub' 'APM-generated model-less agent completion gate'
Assert-Contains $installer 'allowedKeys\.All\(values\.ContainsKey\)' 'exact APM-generated stub key validation'
Assert-Contains $installer 'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local\.cs' 'repo-root usage path'
Assert-Contains $installer 'Path\.Combine\(packageRoot, "codex-agents"\)' 'custom agent source directory'
Assert-NotContains $installer 'AGENTS\.md|adaptive-implementation-execution:start|PlanManagedInstructions' 'AGENTS.md access or managed marker logic'

Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' 'APM install が skill と portable custom agents を導入する本体' 'APM-first quick start'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '`AGENTS\.md` を作成・変更・削除せず' 'documented AGENTS.md non-access'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' 'route_metadata_normalization: legacy-adaptive-handoff' 'documented legacy resume normalization marker'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '--check.*次を検証' 'documented installer checks'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' 'APM-generated model-less stub' 'documented APM stub completion policy'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' 'Migration from the former managed section' 'legacy managed section migration note'

Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '導入されているだけで.*自動適用しません' 'documented non-automatic skill selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' 'legacy-adaptive-handoff\.md' 'documented legacy resume fixture'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md' 'installer does not create, read, update, or remove `AGENTS\.md`' 'validation scenario for AGENTS.md non-access'

$workflow = '.github/workflows/validate-adaptive-implementation-execution.yml'
Assert-Contains $workflow 'validate-adaptive-implementation-execution\.ps1' 'Adaptive Implementation CI validator invocation'
foreach ($pathFilter in @(
    'apm-packages/design-pair-implementation-execution/\*\*',
    'apm-packages/token-aware-guardrail-kernel-flow/\*\*',
    'apm-packages/token-aware-full-coverage-3layer/\*\*',
    'apm-packages/codex-first-ai-development-process/\*\*',
    'apm-packages/copilot-fallback-ai-development-process/\*\*',
    'scripts/provision-work-repo-agents\.cs',
    'docs/\*\*'
)) {
    Assert-Contains $workflow $pathFilter "CI path filter $pathFilter"
}

Assert-Contains 'README.md' 'apm-packages/adaptive-implementation-execution' 'root package link'
Assert-Contains 'README.md' 'apm-packages/design-pair-implementation-execution' 'root Design Pair package link'
Assert-Contains 'README.md' '`AGENTS\.md` は操作しない' 'Adaptive helper AGENTS.md non-access statement'
Assert-NotContains 'README.md' 'install-adaptive-implementation-local\.cs[^\r\n]*`AGENTS\.md` の managed section' 'obsolete Adaptive helper AGENTS.md managed-section claim'

if ($failures.Count -gt 0) {
    Write-Error ("Adaptive Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Adaptive Implementation validation: PASS'
