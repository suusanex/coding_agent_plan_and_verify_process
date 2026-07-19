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
Assert-Contains $adaptiveSkill '(?s)```yaml.*implementation_route: adaptive.*implementation_route_source: default.*design_pair_handoff: N/A.*```' 'fresh Adaptive route identity initialization'
Assert-Contains $adaptiveSkill '(?s)## Step 2: Start with HIGH_MODEL.*渡すもの:.*- `implementation_route`.*- `implementation_route_source`.*HIGH_MODEL は code' 'Adaptive HIGH explicit route input payload'
Assert-Contains $adaptiveSkill 'Design Pair Implementation Handoff path（`adaptive / default`では明示的な`N/A`、`design-pair / explicit-user-selection`ではcurrent tracked path）' 'Adaptive HIGH explicit default N/A path payload'
Assert-Contains $adaptiveSkill '(?s)通常はすべてのHIGH_MODEL result.*唯一の例外.*`Verdict: BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*artifact repair evidence' 'Adaptive parent HIGH invalid route exception'
Assert-Contains $adaptiveSkill '(?s)通常はすべてのSTANDARD_MODEL result.*唯一の例外.*`Verdict: BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*artifact repair evidence' 'Adaptive parent STANDARD invalid route exception'
Assert-Contains $adaptiveSkill 'previous Implementation Completion Handoff と High-model Re-entry Handoff' 'Adaptive HIGH re-entry dual handoff payload'
Assert-Contains $adaptiveSkill '(?s)### NEEDS_HIGH_MODEL_REENTRY.*元の `Implementation Completion Handoff`.*両handoffの`implementation_route`、`implementation_route_source`、Design Pair handoff pathが一致' 'Adaptive HIGH re-entry route identity validation'

$adaptiveHandoff = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md'
Assert-Contains $adaptiveHandoff 'Origin.*Decision ID.*Decision.*Affected files / symbols.*Compliance evidence' 'consolidated Locked Decision schema'
Assert-Contains $adaptiveHandoff 'Design Pair handoff' 'Design Pair handoff reference'
Assert-Contains $adaptiveHandoff 'Legacy Adaptive handoff normalization' 'legacy Adaptive handoff normalization contract'
Assert-Contains $adaptiveHandoff 'LEGACY-HIGH-D01' 'deterministic legacy Decision ID rule'
Assert-Contains $adaptiveHandoff '(?s)# Implementation Completion Handoff.*- implementation_route: adaptive / design-pair.*- implementation_route_source: default / explicit-user-selection.*## Acceptance status' 'current completion handoff route metadata'

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
Assert-Contains $highAgent '(?s)## Required inputs.*- implementation_route.*- implementation_route_source.*- Design Pair Implementation Handoff path または `N/A`.*`BLOCKED`.*BlockedByInvalidCompletionHandoff' 'HIGH required route input validation'
Assert-Contains $highAgent '(?s)`Implementation Completion Handoff` には次を含めます。.*- implementation_route.*- implementation_route_source.*- Validation performed' 'HIGH completion handoff route propagation'
Assert-Contains $highAgent 're-entry handoffと元のImplementation Completion Handoffから`implementation_route`、`implementation_route_source`、Design Pair handoff pathを読み.*一致' 'HIGH re-entry route identity input'
Assert-Contains $highAgent '(?s)## Output.*通常はすべてのverdict.*唯一の例外.*`Verdict: BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*外部blocker.*完全なunchanged identity.*- implementation_route.*- implementation_route_source.*- Design Pair handoff path または `N/A`' 'HIGH conditional route identity output'
Assert-NotContains $highAgent '(?m)^すべてのverdictでincoming route identityを変更せず返します。$' 'unconditional HIGH route identity output'

$standardAgent = '.github/agents/standard-implementation-completer.agent.md'
Assert-Contains $standardAgent 'Origin.*Decision ID' 'STANDARD consolidated decision authorization'
Assert-Contains $standardAgent 'Design Pair Decision IDs' 'STANDARD Decision ID reporting'
Assert-Contains $standardAgent 'Legacy Adaptive handoff normalization' 'STANDARD legacy handoff normalization'
Assert-Contains $standardAgent 'LEGACY-HIGH-D01' 'STANDARD deterministic legacy Decision IDs'
Assert-Contains $standardAgent 'Design Pair evidenceがあるresume.*使用しません' 'STANDARD normalization exclusion for Design Pair resumes'
Assert-Contains $standardAgent '(?s)条件を満たす場合、production code / testsを編集する前に.*`implementation_route: adaptive`.*`implementation_route_source: default`.*`route_metadata_normalization: legacy-adaptive-handoff`' 'STANDARD legacy route metadata persistence'
Assert-Contains $standardAgent '(?s)## Required authorization.*- implementation_route.*- implementation_route_source.*- Validation performed' 'STANDARD route metadata authorization'
Assert-Contains $standardAgent '(?s)## High-model Re-entry Handoff.*- implementation_route:.*- implementation_route_source:.*- Design Pair handoff: N/A / plans/<slug>-design-pair-implementation-handoff\.md.*```' 'STANDARD re-entry route identity fields'
Assert-Contains $standardAgent '`implementation_route`、`implementation_route_source`、Design Pair handoff pathはincoming Implementation Completion Handoffの値を変更せず維持' 'STANDARD re-entry route identity propagation'
Assert-Contains $standardAgent 'この handoff、incoming Implementation Completion Handoff、元の Implementation Intent' 'STANDARD re-entry original completion handoff retention'
Assert-Contains $standardAgent '(?s)片方が欠ける、矛盾する、またはevidenceと一致しないcurrent-schema handoff.*`BLOCKED`.*BlockedByInvalidCompletionHandoff' 'STANDARD invalid current route classification'
Assert-Contains $standardAgent '(?s)`NEEDS_HIGH_MODEL_REENTRY` は.*Required authorizationを通過.*構造判断.*invalid.*re-entry handoffを作成しません' 'STANDARD structural-only re-entry boundary'
Assert-Contains $standardAgent '(?s)## Output.*通常はすべてのverdict.*唯一の例外.*`Verdict: BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*外部blocker.*完全なunchanged identity.*- implementation_route.*- implementation_route_source.*- Design Pair handoff path または `N/A`' 'STANDARD conditional route identity output'
Assert-NotContains $standardAgent '(?m)^すべてのverdictでincoming route identityを変更せず返します。$' 'unconditional STANDARD route identity output'

$adaptiveHighToml = 'apm-packages/adaptive-implementation-execution/codex-agents/high-implementation-starter.toml'
$adaptiveStandardToml = 'apm-packages/adaptive-implementation-execution/codex-agents/standard-implementation-completer.toml'
$codexHighToml = 'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/high-implementation-starter.toml'
$codexStandardToml = 'apm-packages/codex-first-ai-development-process/profiles/codex-first/agents/standard-implementation-completer.toml'
foreach ($toml in @($adaptiveHighToml, $codexHighToml)) {
    Assert-Contains $toml 'Accept only implementation_route: adaptive with implementation_route_source: default and an explicit N/A path, or implementation_route: design-pair with implementation_route_source: explicit-user-selection and the current tracked path' 'portable HIGH exact route identity tuples'
    Assert-Contains $toml 'Stop before editing and return BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff when any route identity field is missing.*raw observed field value or <missing> plus repair evidence; never infer or fabricate' 'portable HIGH invalid route classification and raw output'
    Assert-Contains $toml 'Normally return unchanged implementation_route, implementation_route_source, and the Design Pair Implementation Handoff path or N/A.*only exception is BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff.*raw observed values or <missing>.*Other BLOCKED results still require the complete unchanged identity' 'portable HIGH conditional route output'
}
foreach ($toml in @($adaptiveStandardToml, $codexStandardToml)) {
    Assert-Contains $toml 'accept only implementation_route: adaptive with implementation_route_source: default, or implementation_route: design-pair with implementation_route_source: explicit-user-selection' 'portable STANDARD exact route pairs'
    Assert-Contains $toml 'Reject a missing, contradictory, or evidence-inconsistent current-schema route identity before editing.*raw observed field value or <missing> plus repair evidence.*explicit N/A Design Pair Implementation Handoff path for implementation_route: adaptive.*current tracked path' 'portable STANDARD route identity fail-closed rule'
    Assert-Contains $toml 'High-model Re-entry Handoff.*unchanged implementation_route and implementation_route_source.*unchanged Design Pair Implementation Handoff path or N/A' 'portable STANDARD re-entry route identity propagation'
    Assert-Contains $toml 'Reject a missing, contradictory, or evidence-inconsistent current-schema route identity before editing by returning BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff; return each raw observed field value or <missing> plus repair evidence' 'portable STANDARD invalid route classification'
    Assert-Contains $toml 'Normally return unchanged implementation_route, implementation_route_source, and the Design Pair Implementation Handoff path or N/A.*only exception is BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff.*raw observed values or <missing>.*Other BLOCKED results still require the complete unchanged identity' 'portable STANDARD conditional route output'
    Assert-Contains $toml 'Reserve NEEDS_HIGH_MODEL_REENTRY for a structural decision discovered after a current-schema or normalized handoff has passed authorization' 'portable STANDARD structural-only re-entry boundary'
}

Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' 'DP-VAL-012: Portable agent route contract' 'portable Design Pair route validation scenario'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' 'invalid artifactを`NEEDS_HIGH_MODEL_REENTRY`として扱わない' 'invalid artifact is not re-entry scenario'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' '`design_pair_handoff: N/A`' 'fresh default N/A scenario'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' 'invalid-artifact `BLOCKED`だけはraw observed valueまたは`<missing>`とrepair evidenceを返す' 'invalid-artifact BLOCKED route output exception scenario'

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
