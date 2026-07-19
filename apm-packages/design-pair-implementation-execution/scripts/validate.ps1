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
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath) -PathType Leaf)) {
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

    if ((Get-Content -Raw -LiteralPath $path) -notmatch $Pattern) {
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

    if ((Get-Content -Raw -LiteralPath $path) -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

$requiredFiles = @(
    '.github/agents/high-implementation-starter.agent.md',
    '.github/agents/standard-implementation-completer.agent.md',
    '.github/agents/implementation-handoff-review.agent.md',
    '.github/workflows/validate-design-pair-implementation-execution.yml',
    'apm-packages/design-pair-implementation-execution/apm.yml',
    'apm-packages/design-pair-implementation-execution/README.md',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/map.md',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/handoff.md',
    'apm-packages/design-pair-implementation-execution/docs/usage-guide.md',
    'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md',
    'apm-packages/design-pair-implementation-execution/scripts/validate.ps1',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/legacy-adaptive-handoff.md',
    'apm-packages/adaptive-implementation-execution/docs/install-guide.md',
    'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/references/full-coverage-parent-orchestration-state.md',
    'apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md',
    'apm-packages/codex-first-ai-development-process/templates/codex-first-state.md',
    'apm-packages/codex-first-ai-development-process/scripts/codex-first-start.ps1',
    'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs',
    'README.md'
)

foreach ($file in $requiredFiles) {
    Assert-FileExists $file
}

$packageAgentsFiles = @(Get-ChildItem -LiteralPath $packageRoot -Filter 'AGENTS.md' -File -Recurse)
if ($packageAgentsFiles.Count -gt 0) {
    Add-Failure ('Package must not contain repository-wide AGENTS.md guidance: ' + (($packageAgentsFiles.FullName) -join ', '))
}

$manifest = 'apm-packages/design-pair-implementation-execution/apm.yml'
Assert-Contains $manifest '(?m)^name:\s*design-pair-implementation-execution\s*$' 'package name'
Assert-Contains $manifest '(?m)^version:\s*0\.1\.0\s*$' 'package version 0.1.0'
Assert-Contains $manifest '(?m)^\s*-\s+codex\s*$' 'codex target'
Assert-Contains $manifest '(?m)^\s*-\s+agent-skills\s*$' 'agent-skills target'
Assert-NotContains $manifest '(?m)^\s*-\s+copilot\s*$' 'unverified Copilot target'
Assert-Contains $manifest 'adaptive-implementation-execution/\.apm/skills/adaptive-implementation-execution' 'Adaptive skill dependency'
Assert-Contains $manifest '\.github/agents/high-implementation-starter\.agent\.md' 'canonical HIGH agent dependency'
Assert-Contains $manifest '\.github/agents/standard-implementation-completer\.agent\.md' 'canonical STANDARD agent dependency'
Assert-NotContains $manifest 'implementation-execution\.agent\.md' 'legacy implementation orchestration dependency'

$maxWindowsPackagePathLength = 112
$packageRelativeRoot = 'apm-packages/design-pair-implementation-execution'
$packageFiles = @(& git -C $repoRoot ls-files --cached --others --exclude-standard -- $packageRelativeRoot)
if ($LASTEXITCODE -ne 0) {
    Add-Failure 'Cannot enumerate Design Pair package payload for Windows path compatibility validation'
}
foreach ($relativePath in $packageFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf)) {
        continue
    }
    if ($relativePath.Length -gt $maxWindowsPackagePathLength) {
        Add-Failure "APM package path exceeds Windows compatibility budget ($($relativePath.Length) > $maxWindowsPackagePathLength): $relativePath"
    }
}

$skill = 'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md'
Assert-Contains $skill '利用者が Design Pair route を明示的に選択した場合だけ' 'explicit-only route selection'
Assert-Contains $skill '自動選択、推奨、提案してはいけない' 'no automatic selection or recommendation'
Assert-Contains $skill 'implementation_route:\s*design-pair' 'design-pair route metadata'
Assert-Contains $skill 'implementation_route_source:\s*explicit-user-selection' 'explicit route source metadata'
Assert-Contains $skill 'Design Pair phase の完了前に production code / tests を編集してはいけない' 'no production edit before handoff'
Assert-Contains $skill 'production code の対象 symbol と直接の call sites' 'production target and call-site mapping'
Assert-Contains $skill 'tests、fixture、test seam' 'test surface mapping'
Assert-Contains $skill 'DI、factory、startup、entrypoint、production wiring' 'production wiring mapping'
Assert-Contains $skill '(?s)`Locked`.*`Discussed-Unlocked`.*`Adaptive-Owned`.*`No-Change`.*`Upstream-Decision-Required`' 'Target disposition vocabulary'
Assert-Contains $skill '全設計確定、全 unknown の除去、`Unknown == 0` は完了条件ではない' 'non-exhaustive completion condition'
Assert-Contains $skill '利用者が初期案' 'human-first discussion order'
Assert-Contains $skill 'AI の推奨案を最初から確定案として提示してはいけない' 'non-leading discussion rule'
Assert-Contains $skill 'plans/<slug>-design-pair-implementation-handoff\.md' 'tracked handoff path'
Assert-Contains $skill 'Affected files / symbols.*allowed edit surface ではない' 'file-symbol non-allowlist rule'
Assert-Contains $skill 'Locked Decisions.*binding constraint' 'binding-only Locked Decisions rule'
Assert-Contains $skill '通常の adaptive implementation と同じ authority' 'Adaptive HIGH authority invariant'
Assert-Contains $skill 'automatic Design Pair re-entry は行わない' 'no automatic Design Pair re-entry'
Assert-Contains $skill 'final code review.*独立 verification' 'final review boundary'

$map = 'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/map.md'
Assert-Contains $map 'Target ID.*File / Symbol.*Current responsibility.*Relation to requested change.*Expected modification or verification.*Evidence.*Open question.*Disposition' 'complete Target Map schema'
Assert-Contains $map 'Production symbol and direct call sites' 'production call-site coverage row'
Assert-Contains $map 'Tests / fixtures / test seam' 'test coverage row'
Assert-Contains $map 'DI / factory / startup / entrypoint / production wiring' 'wiring coverage row'
Assert-Contains $map 'allowed edit surface ではない' 'Target Map non-allowlist note'

$handoff = 'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/handoff.md'
foreach ($field in @(
    'implementation_route',
    'implementation_route_source',
    'Design Pair Target Map',
    'Locked Decisions',
    'Explicit human confirmation',
    'Discussed but Unlocked',
    'Adaptive-Owned',
    'Known Evidence',
    'Known Assumptions',
    'Upstream Decisions Required',
    'Knowledge Candidates',
    'Adaptive Implementation Result',
    'Adaptive Implementation verdict sequence',
    'Locked Decision compliance evidence',
    'Locked Decision conflict',
    'Validation performed',
    'Final review status'
)) {
    Assert-Contains $handoff ([regex]::Escape($field)) "handoff field $field"
}
Assert-Contains $handoff 'Decision ID.*Decision.*Affected files / symbols.*Rationale.*Validation expectations.*Conflict conditions.*Explicit human confirmation' 'complete Locked Decision schema'
Assert-Contains $handoff 'section に Decision ID と explicit human confirmation がある entry だけが binding' 'explicit binding rule'
Assert-Contains $handoff 'allowed edit surface ではない' 'handoff non-allowlist rule'

$adaptiveSkill = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
Assert-Contains $adaptiveSkill 'Design Pair Implementation Handoff' 'Design Pair input support'
Assert-Contains $adaptiveSkill '(?s)binding なのは.*Locked Decisions.*だけ' 'Adaptive binding-only rule'
Assert-Contains $adaptiveSkill 'Affected files / symbols.*Allowed edit surface.*扱いません' 'Adaptive non-allowlist rule'
Assert-Contains $adaptiveSkill 'Design Pair Decision ID' 'Design Pair Decision ID propagation'
Assert-Contains $adaptiveSkill 'automatic Design Pair re-entry' 'Adaptive no automatic re-entry rule'
Assert-Contains $adaptiveSkill 'Locked Decision conflict' 'Adaptive conflict stop report'
Assert-Contains $adaptiveSkill '新規 intake と resume を分けます' 'fresh intake and resume distinction'
Assert-Contains $adaptiveSkill '欠落や矛盾を Adaptive へ補完しません' 'resume fail-closed route metadata'
Assert-Contains $adaptiveSkill 'route_metadata_normalization: legacy-adaptive-handoff' 'legacy Adaptive handoff normalization marker'

$adaptiveHandoff = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md'
Assert-Contains $adaptiveHandoff 'Origin.*Decision ID.*Decision.*Affected files / symbols.*Compliance evidence' 'consolidated Locked Decision schema'
Assert-Contains $adaptiveHandoff 'Design Pair handoff' 'Design Pair handoff reference'
Assert-Contains $adaptiveHandoff 'Legacy Adaptive handoff normalization' 'legacy Adaptive handoff normalization contract'
Assert-Contains $adaptiveHandoff 'LEGACY-HIGH-D01' 'deterministic legacy Decision ID rule'

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

$highAgent = '.github/agents/high-implementation-starter.agent.md'
Assert-Contains $highAgent 'Design Pair Implementation Handoff' 'HIGH Design Pair input support'
Assert-Contains $highAgent 'Decision ID' 'HIGH Decision ID propagation'
Assert-Contains $highAgent 'Locked Decision conflict' 'HIGH conflict stop report'
Assert-Contains $highAgent 'Target Map.*allowed edit surface' 'HIGH non-allowlist rule'

$standardAgent = '.github/agents/standard-implementation-completer.agent.md'
Assert-Contains $standardAgent 'Origin.*Decision ID' 'STANDARD consolidated decision authorization'
Assert-Contains $standardAgent 'Design Pair Decision IDs' 'STANDARD Decision ID reporting'
Assert-Contains $standardAgent 'Legacy Adaptive handoff normalization' 'STANDARD legacy handoff normalization'
Assert-Contains $standardAgent 'LEGACY-HIGH-D01' 'STANDARD deterministic legacy Decision IDs'
Assert-Contains $standardAgent 'Design Pair evidenceがあるresume.*使用しません' 'STANDARD normalization exclusion for Design Pair resumes'

$planCoverageSkill = 'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md'
Assert-Contains $planCoverageSkill 'implementation_route:\s*adaptive' 'Plan Coverage default Adaptive route'
Assert-Contains $planCoverageSkill 'implementation_route_source:\s*default' 'Plan Coverage default route source'
Assert-Contains $planCoverageSkill 'design-pair-implementation-execution' 'Plan Coverage explicit Design Pair route'
Assert-Contains $planCoverageSkill 'Do not automatically select, recommend, or propose Design Pair' 'Plan Coverage no automatic Design Pair selection'
Assert-Contains $planCoverageSkill 'Missing or contradictory route metadata must not be inferred during resume' 'Plan Coverage resume fail-closed rule'

foreach ($statePath in @(
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md',
    'apm-packages/token-aware-guardrail-kernel-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/references/full-coverage-parent-orchestration-state.md',
    'apm-packages/codex-first-ai-development-process/templates/codex-first-state.md'
)) {
    Assert-Contains $statePath 'implementation_route' 'implementation route state field'
    Assert-Contains $statePath 'implementation_route_source' 'implementation route source state field'
    Assert-Contains $statePath 'design_pair_handoff' 'Design Pair handoff state field'
}

Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'implementation_route' 'handoff review route propagation'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'design-pair-implementation-execution' 'handoff review explicit next route'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' '新規 intake.*だけ `adaptive / default` を初期化' 'handoff review fresh-intake-only default'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'resume.*BLOCKED_BY_ARTIFACT_MISMATCH' 'handoff review resume fail-closed rule'

$codexManifest = 'apm-packages/codex-first-ai-development-process/apm.yml'
Assert-Contains $codexManifest 'design-pair-implementation-execution/\.apm/skills/design-pair-implementation-execution' 'Codex-first Design Pair skill dependency'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'sourceDesignPairSkill' 'Codex-first Design Pair skill bootstrap source'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'design-pair-implementation-execution' 'Codex-first Design Pair skill bootstrap target'

$launcher = 'apm-packages/codex-first-ai-development-process/scripts/codex-first-start.ps1'
Assert-Contains $launcher 'adaptiveSkillSource' 'one-off launcher Adaptive skill source'
Assert-Contains $launcher 'designPairSkillSource' 'one-off launcher Design Pair skill source'
Assert-Contains $launcher 'skills\\adaptive-implementation-execution' 'one-off launcher Adaptive skill target'
Assert-Contains $launcher 'skills\\design-pair-implementation-execution' 'one-off launcher Design Pair skill target'
Assert-Contains $launcher 'Copy-Item.*adaptiveSkillSource\.Path' 'one-off launcher Adaptive payload copy'
Assert-Contains $launcher 'Copy-Item.*designPairSkillSource\.Path' 'one-off launcher Design Pair payload copy'

$codexRouter = 'apm-packages/codex-first-ai-development-process/.apm/skills/codex-first-cost-router/SKILL.md'
Assert-Contains $codexRouter 'fresh intake.*no durable route artifact' 'Codex-first fresh-intake default boundary'
Assert-Contains $codexRouter 'On resume.*missing or contradictory metadata must stop' 'Codex-first resume fail-closed rule'

$fullCoverageSkill = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md'
Assert-Contains $fullCoverageSkill 'resumeではParent Orchestration State.*必須' 'full-coverage resume route requirement'
Assert-Contains $fullCoverageSkill 'Adaptiveへ補完せずartifact mismatchとして停止' 'full-coverage resume fail-closed rule'

foreach ($id in 1..11) {
    $scenarioId = 'DP-VAL-{0:D3}' -f $id
    Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' $scenarioId "validation scenario $scenarioId"
}

Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'GitHub Copilot.*未検証' 'unverified Copilot support statement'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'adaptive-implementation-execution --target codex,agent-skills' 'fresh install Adaptive co-install command'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'install-adaptive-implementation-local\.cs.*--check' 'fresh install Adaptive profile check'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'package単体のinstallだけでは.*model mapping' 'incomplete single-package install warning'
Assert-Contains 'apm-packages/codex-first-ai-development-process/docs/team-profile-launcher.md' 'Adaptive skill and refs, and Design Pair skill and refs' 'documented one-off launcher payload'
Assert-Contains 'README.md' 'apm-packages/design-pair-implementation-execution' 'root Design Pair package link'

if ($failures.Count -gt 0) {
    Write-Error ("Design Pair Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Design Pair Implementation validation: PASS'
