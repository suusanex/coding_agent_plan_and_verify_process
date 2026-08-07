[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
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

function Assert-FileNotExists {
    param([string]$RelativePath)
    $path = Join-Path $repoRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Failure "Obsolete duplicate file must not exist: $RelativePath"
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
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-manual-smoke.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-cli-real-model-e2e-2026-07-31.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/legacy-adaptive-handoff.md',
    'apm-packages/adaptive-implementation-execution/tests/routing-scenarios.json',
    'apm-packages/adaptive-implementation-execution/tests/validate-routing-scenarios.ps1',
    'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs',
    'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-apm-smoke.ps1',
    'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1',
    'apm-packages/design-pair-implementation-execution/apm.yml',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/SKILL.md',
    'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/handoff.md',
    'apm-packages/plan-coverage-residual-flow/apm.yml',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/token-aware-full-coverage-3layer/apm.yml',
    'apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md',
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
Assert-Contains $manifest '(?m)^version:\s*0\.4\.0\s*$' 'package version 0.4.0'
Assert-Contains $manifest '(?m)^\s*-\s+copilot\s*$' 'Copilot target'
Assert-Contains $manifest '(?m)^\s*-\s+codex\s*$' 'codex target'
Assert-Contains $manifest '(?m)^\s*-\s+agent-skills\s*$' 'agent-skills target'
Assert-NotContains $manifest '(?m)^\s*-\s+(?:github-copilot|vscode)\s*$' 'non-canonical Copilot target alias'
Assert-NotContains $manifest 'token-aware|codex-first|copilot-fallback|plan-coverage' 'aggregate process dependency'
Assert-NotContains $manifest 'path:\s+.*(?:implementation-intent|implementation-completion-handoff)\.md' 'standalone template dependency'

# APM remote install materializes the complete package below a deep Git cache prefix on Windows.
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
    @{ Path = 'apm-packages/plan-coverage-residual-flow/apm.yml'; Version = '0\.9\.0' },
    @{ Path = 'apm-packages/token-aware-full-coverage-3layer/apm.yml'; Version = '0\.6\.0' }
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
    'apm-packages/plan-coverage-residual-flow/apm.yml',
    'apm-packages/token-aware-full-coverage-3layer/apm.yml'
)) {
    Assert-Contains $integratedManifestPath 'apm-packages/adaptive-implementation-execution/\.apm/skills/adaptive-implementation-execution' 'Adaptive Implementation skill dependency'
    Assert-Contains $integratedManifestPath '\.github/agents/high-implementation-starter\.agent\.md' 'canonical HIGH agent dependency'
    Assert-Contains $integratedManifestPath '\.github/agents/standard-implementation-completer\.agent\.md' 'canonical STANDARD agent dependency'
    Assert-Contains $integratedManifestPath '\.github/agents/implementation-execution\.agent\.md' 'legacy implementation dependency'
}

$planCoveragePackageName = 'plan-coverage-residual-flow'
$planCoveragePackageRoot = "apm-packages/$planCoveragePackageName"
$planCoverageManifest = "$planCoveragePackageRoot/apm.yml"
$planCoverageSkill = "$planCoveragePackageRoot/.apm/skills/$planCoveragePackageName/SKILL.md"
Assert-Contains $planCoverageManifest "(?m)^name:\s*$planCoveragePackageName\s*$" 'Plan Coverage package directory and manifest name alignment'
Assert-Contains $planCoverageSkill "(?m)^name:\s*$planCoveragePackageName\s*$" 'Plan Coverage package and primary skill name alignment'
Assert-Contains $planCoverageSkill 'Every non-trivial pass starts with `high-implementation-starter\.agent\.md` on `HIGH_MODEL`' 'Plan Coverage HIGH_MODEL start'
Assert-Contains $planCoverageSkill '`READY_FOR_STANDARD_COMPLETION`.*`standard-implementation-completer\.agent\.md`' 'Plan Coverage bounded STANDARD completion'
Assert-Contains $planCoverageSkill '`NEEDS_HIGH_MODEL_REENTRY`.*`high-implementation-starter\.agent\.md`' 'Plan Coverage HIGH_MODEL re-entry'
Assert-Contains $planCoverageSkill 'plans/<slug>-implementation-execution\.md' 'stable implementation result artifact name'
Assert-Contains $planCoverageSkill 'completion handoff inline unless resume, another thread/model, or another worker requires a tracked' 'inline completion handoff default'
Assert-Contains $planCoverageSkill 'Implementation Self-Map Delta' 'per-phase implementation traceability delta'
Assert-Contains $planCoverageSkill 'Related Plan item.*Related Behavior Case IDs.*Related SL / XC / RC / TP / IC / Gap item.*Assumption made.*Review hint' 'complete Self-Map traceability schema'
Assert-Contains $planCoverageSkill 'orchestrator is the single aggregation owner' 'Self-Map aggregation ownership'
Assert-Contains '.github/agents/change-risk-triage.agent.md' 'implementation-internal.*implementation phase' 'risk triage shape boundary'

$handoffReviewAgent = '.github/agents/implementation-handoff-review.agent.md'
Assert-Contains $handoffReviewAgent 'Plan網羅チェック・残件判定フロー.*mandatory pre-implementation review gate' 'handoff review Plan Coverage placement'
Assert-Contains $handoffReviewAgent 'standalone Adaptive.*呼び出さず' 'handoff review standalone Adaptive exclusion'

$fullCoverageSkill = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md'
Assert-Contains $fullCoverageSkill 'non-trivial READY slice.*high-implementation-starter' 'per-slice HIGH_MODEL start'
Assert-Contains $fullCoverageSkill 'READY_FOR_STANDARD_COMPLETION.*standard-implementation-completer' 'per-slice STANDARD completion gate'
Assert-Contains $fullCoverageSkill 'NEEDS_HIGH_MODEL_REENTRY.*high-implementation-starter' 'per-slice HIGH_MODEL re-entry'
Assert-Contains $fullCoverageSkill 'HIGH and STANDARD write owners did not overlap' 'per-slice serial ownership audit'
Assert-Contains $fullCoverageSkill '`slice-impl`.*legacy compatibility' 'legacy slice implementation notice'
Assert-Contains $fullCoverageSkill 'BlockedByMissingAdaptiveImplementationDelegation' 'missing adaptive delegation blocker'
Assert-Contains $fullCoverageSkill 'same Slice Record Implementation section' 'full-coverage durable implementation result record'
Assert-Contains $fullCoverageSkill 'Completion Handoff.*inline' 'full-coverage inline completion handoff default'
$fullCoverageInstruction = 'apm-packages/token-aware-full-coverage-3layer/.apm/instructions/token-aware-full-coverage-3layer.instructions.md'
Assert-Contains $fullCoverageInstruction 'high-implementation-starter' 'full-coverage instruction HIGH start'
Assert-Contains $fullCoverageInstruction 'standard-implementation-completer' 'full-coverage instruction STANDARD completion'
Assert-Contains $fullCoverageInstruction 'NEEDS_HIGH_MODEL_REENTRY' 'full-coverage instruction HIGH re-entry'
Assert-Contains $fullCoverageInstruction '`slice-impl`.*legacy compatibility' 'full-coverage instruction legacy notice'
Assert-Contains $fullCoverageInstruction 'fresh intakeだけ.*`implementation_route: adaptive` / `implementation_route_source: default`' 'full-coverage instruction fresh-only Adaptive default'
Assert-Contains $fullCoverageInstruction 'resumeでは`implementation_route`と`implementation_route_source`の両方.*欠落または矛盾.*Adaptiveへ補完せず' 'full-coverage instruction resume route fail-closed rule'
Assert-NotContains $fullCoverageInstruction 'BlockedByMissingSliceImplDelegation' 'obsolete missing slice-impl blocker'

Assert-Contains '.github/agents/implementation-execution.agent.md' 'Compatibility status: legacy' 'legacy Plan Coverage implementation notice'
Assert-Contains 'apm-packages/token-aware-full-coverage-3layer/.apm/agents/slice-impl.agent.md' 'Compatibility status: legacy' 'legacy slice implementation notice'

$skill = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
Assert-Contains $skill '(?m)^disable-model-invocation:\s*true\s*$' 'skill explicit-only model invocation'
Assert-Contains $skill '(?m)^user-invocable:\s*true\s*$' 'skill remains user-invocable'
Assert-Contains $skill '(?m)^description:\s*Use only when the user explicitly invokes this skill with /adaptive-implementation-execution' 'skill description slash-invocation-only contract'
Assert-Contains $skill 'Do not select for ordinary implement-this-plan requests' 'skill description rejects plain implementation requests'
Assert-Contains $skill 'do not select from natural-language mentions' 'skill description rejects natural-language name mentions'
Assert-NotContains $skill 'or when the task clearly requires' 'obsolete task-requires auto-selection description'
Assert-NotContains $skill '\$adaptive-implementation-execution' 'obsolete dollar-prefix skill invocation example'
Assert-Contains $skill '利用者が `/adaptive-implementation-execution` で明示起動した場合だけ使用する' 'skill body slash-invocation-only rule'
Assert-Contains $skill '「実装して」「このPlanを実装して」などの実装依頼、および「Adaptive Implementationを使って」などの自然文での名前言及だけでは選択しない' 'skill body rejects plain and natural-language requests'
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
Assert-Contains $skill 'package が導入されているだけで.*自動適用しない' 'non-automatic skill selection rule'
Assert-Contains $skill 'Design Pair Implementation Handoff' 'Design Pair handoff input support'
Assert-Contains $skill '(?s)binding なのは.*Locked Decisions.*だけ' 'Design Pair binding-only rule'
Assert-Contains $skill '(?s)verdict が `READY_FOR_ADAPTIVE_IMPLEMENTATION`.*`Interaction stage: complete`.*Target Map presentation evidence.*actual user response reference.*explicit all-Adaptive delegation.*pending human-owned Target がない' 'complete post-map Design Pair readiness validation'
Assert-Contains $skill 'Target 未選択を空集合として PASS にせず.*HIGH_MODELを起動しません' 'empty Target selection fail-closed rule'
Assert-Contains $skill '(?s)Target Map ID が一意.*summary の全 Target ID が Target Map に実在.*5集合が互いに素.*和集合が Target Map 全体と完全一致.*summary 集合が Target Map row.*一致' 'Design Pair Target set reconciliation gate'
Assert-Contains $skill '(?s)Locked Decision Target ID が `Selected Target IDs` に含まれ.*Target Map row が `Locked`.*all-Adaptive delegation.*selected / pending が `None`.*全 Target row が `Adaptive-Owned`.*delegated集合と完全一致' 'Design Pair Locked and all-Adaptive invariants'
Assert-Contains $skill '架空 ID、重複 ID、未分類 Target、row / summary 不一致.*も拒否' 'Design Pair malformed Target set rejection'
Assert-Contains $skill '(?s)`Selected Target IDs`と`Delegated-to-Adaptive Target IDs`の各Targetに一件だけ`Target Disposition Evidence`.*Target Map rowと一致.*actual user message / turn reference.*post-map confirmation `Yes`' 'Design Pair Target disposition evidence gate'
Assert-Contains $skill '(?s)未選択Targetを自己判断で`Adaptive-Owned`.*利用者の最終応答なしに`Discussed-Unlocked`.*拒否' 'Design Pair AI-owned disposition rejection'
Assert-Contains $skill '(?s)selected Targetごとに`Selected Target Discussion Evidence`.*user-facing assistant turn reference.*具体的code location.*current invariant.*alternatives / trade-offs.*proposalまたはNo proposal理由.*validation expectation' 'Design Pair selected Target discussion evidence gate'
Assert-Contains $skill '抽象的な論点名だけで具体的なSelected Target discussion evidenceがないartifactも拒否' 'Design Pair abstract discussion rejection'
Assert-Contains $skill '(?s)Target Map presentation evidenceが.*全Targetのuser-facingな具体的file / symbol.*current invariant.*内部設計判断候補.*relevant evidence.*artifact linkまたは論点名だけの要約ではない' 'Design Pair concrete Target Map presentation gate'
Assert-Contains $skill 'Upstream Binding Constraints.*Design Pair Decision ID を持たない既存の binding input' 'upstream binding separation rule'
Assert-Contains $skill 'Affected files / symbols.*Allowed edit surface.*扱いません' 'Design Pair file-symbol non-allowlist rule'
Assert-Contains $skill 'automatic Design Pair re-entry' 'no automatic Design Pair re-entry'
Assert-Contains $skill '新規 intake と resume を分けます' 'fresh intake and resume distinction'
Assert-Contains $skill '欠落や矛盾を Adaptive へ補完しません' 'resume route fail-closed rule'
Assert-Contains $skill 'route_metadata_normalization: legacy-adaptive-handoff' 'legacy handoff normalization marker'
Assert-Contains $skill '(?s)```yaml.*implementation_route: adaptive.*implementation_route_source: default.*design_pair_handoff: N/A.*```' 'fresh Adaptive route identity initialization'
Assert-Contains $skill '(?s)## Step 2: Start with HIGH_MODEL.*渡すもの:.*- `implementation_route`.*- `implementation_route_source`.*HIGH_MODEL は code' 'HIGH_MODEL explicit route input payload'
Assert-Contains $skill 'Design Pair Implementation Handoff path（`adaptive / default`では明示的な`N/A`、`design-pair / explicit-user-selection`ではcurrent tracked path）' 'HIGH_MODEL explicit default N/A path payload'
Assert-Contains $skill '`adaptive / default`ではpathが明示的な`N/A`' 'parent default route path validation'
Assert-Contains $skill 'previous Implementation Completion Handoff と High-model Re-entry Handoff' 'HIGH_MODEL re-entry dual handoff payload'
Assert-Contains $skill '(?s)### NEEDS_HIGH_MODEL_REENTRY.*元の (?:tracked )?`Implementation Completion Handoff`.*両handoffの`implementation_route`、`implementation_route_source`、Design Pair handoff pathが一致' 'HIGH_MODEL re-entry route identity validation'
Assert-Contains $skill '(?s)通常はすべてのHIGH_MODEL result.*incoming durable route identityと完全一致.*唯一の例外.*`Verdict: BLOCKED`.*`Stop reason: BlockedByInvalidCompletionHandoff`.*raw observed value.*`<missing>`.*artifact repair evidence' 'parent HIGH invalid-artifact BLOCKED route exception'
Assert-Contains $skill '(?s)通常はすべてのSTANDARD_MODEL result.*incoming Implementation Completion Handoffと完全一致.*唯一の例外.*`Verdict: BLOCKED`.*`Stop reason: BlockedByInvalidCompletionHandoff`.*raw observed value.*`<missing>`.*artifact repair evidence' 'parent STANDARD invalid-artifact BLOCKED route exception'
Assert-Contains $skill '(?s)### COMPLETED_BY_HIGH_MODEL.*検証済みroute identity' 'parent validates HIGH_MODEL completion route identity'
Assert-Contains $skill '(?s)### COMPLETED.*検証済みroute identity' 'parent validates STANDARD_MODEL completion route identity'
Assert-Contains $skill '(?s)### NEEDS_HIGH_MODEL_REENTRY.*有効なImplementation Completion Handoff.*構造判断.*欠落または不一致.*`BLOCKED`.*BlockedByInvalidCompletionHandoff' 'parent separates structural re-entry from invalid handoff'
Assert-Contains $skill 'GitHub Copilot Chat in VS Code.*GPT-5\.6 Terra \(copilot\).*GPT-5\.6 Luna \(copilot\).*re-entry.*Terra' 'Copilot model route mapping'
Assert-Contains $skill 'handoff button.*手動遷移候補.*verdictを検証するrouterではありません' 'Copilot handoff UI authorization boundary'
Assert-Contains $skill 'Copilot.*tracked handoff.*会話履歴だけを唯一のstate保持手段にしません' 'Copilot tracked handoff state boundary'
Assert-Contains $skill '`COMPLETED_BY_HIGH_MODEL`とstop verdictでは次agentを起動しません' 'Copilot stop verdict routing boundary'

$highAgent = '.github/agents/high-implementation-starter.agent.md'
Assert-NotContains $highAgent '(?m)^tools:' 'explicit Copilot HIGH tools frontmatter that APM drops for Codex'
Assert-Contains $highAgent '(?m)^model:\s*GPT-5\.6 Terra \(copilot\)\s*$' 'Copilot HIGH model frontmatter'
Assert-Contains $highAgent '(?m)^target:\s*vscode\s*$' 'Copilot HIGH VS Code target'
Assert-Contains $highAgent '(?m)^disable-model-invocation:\s*true\s*$' 'Copilot HIGH explicit-only invocation'
Assert-Contains $highAgent '(?s)handoffs:.*agent:\s*standard-implementation-completer.*model:\s*GPT-5\.6 Luna \(copilot\)' 'Copilot HIGH bounded completion handoff'
Assert-Contains $highAgent 'edit production code and tests' 'real implementation loop'
Assert-Contains $highAgent 'CONTINUE_HIGH_IMPLEMENTATION' 'continue-high verdict'
Assert-Contains $highAgent 'COMPLETED_BY_HIGH_MODEL' 'high completion verdict'
Assert-Contains $highAgent 'Allowed edit surface' 'handoff allowed surface'
Assert-Contains $highAgent 'acceptance status table' 'high-model acceptance evidence output'
Assert-Contains $highAgent '一度 re-entry した後' 'high-model re-entry ownership'
Assert-Contains $highAgent 'すべての `Incomplete` acceptance item' 'high-model incomplete acceptance mapping gate'
Assert-Contains $highAgent 'scope 内の全 acceptance item.*`Acceptance status`' 'high-model complete acceptance enumeration gate'
Assert-Contains $highAgent 're-entry handoff の `reentry_count` を維持' 'high-model re-entry count propagation'
Assert-Contains $highAgent 'You are the "High Implementation Starter" agent\.' 'APM stub high-agent opening'
Assert-Contains $highAgent 'Implementation Self-Map Delta' 'HIGH_MODEL Self-Map delta output'
Assert-Contains $highAgent 'Related Plan item.*Related Behavior Case IDs.*Related SL / XC / RC / TP / IC / Gap item.*Assumption made.*Review hint' 'HIGH_MODEL Self-Map schema'
Assert-Contains $highAgent 'Design Pair Implementation Handoff' 'HIGH_MODEL Design Pair input support'
Assert-Contains $highAgent 'Locked Decision conflict' 'HIGH_MODEL Locked Decision conflict stop'
Assert-Contains $highAgent '(?s)`design-pair / explicit-user-selection`では.*`Interaction stage: complete`.*post-map user response evidence.*explicit all-Adaptive delegation.*pending human-owned Targetなし.*空集合PASS.*BlockedByInvalidCompletionHandoff' 'HIGH_MODEL complete post-map authorization gate'
Assert-Contains $highAgent 'Upstream Binding Constraints.*Design Pair Decision IDを持たない既存のbinding input' 'HIGH_MODEL upstream binding separation'
Assert-Contains $highAgent '(?s)## Required inputs.*- implementation_route.*- implementation_route_source.*- Design Pair Implementation Handoff path または `N/A`.*`BLOCKED`.*BlockedByInvalidCompletionHandoff' 'HIGH_MODEL required route input validation'
Assert-Contains $highAgent '(?s)`Implementation Completion Handoff` には次を含めます。.*- implementation_route.*- implementation_route_source.*- Validation performed' 'HIGH_MODEL required handoff route metadata'
Assert-Contains $highAgent 're-entry handoffと元のImplementation Completion Handoffから`implementation_route`、`implementation_route_source`、Design Pair handoff pathを読み.*一致' 'HIGH_MODEL re-entry route identity input'
Assert-Contains $highAgent '(?s)## Output.*通常はすべてのverdict.*唯一の例外.*`Verdict: BLOCKED`.*`Stop reason: BlockedByInvalidCompletionHandoff`.*raw observed value.*`<missing>`.*外部blocker.*完全なunchanged identity.*- implementation_route.*- implementation_route_source.*- Design Pair handoff path または `N/A`' 'HIGH_MODEL conditional route identity output'
Assert-NotContains $highAgent '(?m)^すべてのverdictでincoming route identityを変更せず返します。$' 'unconditional HIGH_MODEL route identity output'
Assert-Contains $highAgent '(?s)fieldの欠落、組み合わせ矛盾、またはevidence不一致.*`BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*推測または補完してはいけません' 'HIGH_MODEL invalid route classification and raw output'
Assert-Contains $highAgent 'Original Implementation Intent.*goal / scope / acceptance / constraints / validation' 'HIGH_MODEL original intent persistence'
Assert-Contains $highAgent 'GitHub Copilot Chat in VS Code.*必ずtracked artifact.*会話履歴だけを唯一の状態保持手段' 'Copilot HIGH tracked handoff requirement'
Assert-NotContains $highAgent 'agent:\s*copilot-standard-verifier' 'Copilot HIGH stop/completion verification handoff'

$standardAgent = '.github/agents/standard-implementation-completer.agent.md'
Assert-NotContains $standardAgent '(?m)^tools:' 'explicit Copilot STANDARD tools frontmatter that APM drops for Codex'
Assert-Contains $standardAgent '(?m)^model:\s*GPT-5\.6 Luna \(copilot\)\s*$' 'Copilot STANDARD model frontmatter'
Assert-Contains $standardAgent '(?m)^target:\s*vscode\s*$' 'Copilot STANDARD VS Code target'
Assert-Contains $standardAgent '(?m)^disable-model-invocation:\s*true\s*$' 'Copilot STANDARD explicit-only invocation'
Assert-Contains $standardAgent '(?s)handoffs:.*agent:\s*high-implementation-starter.*model:\s*GPT-5\.6 Terra \(copilot\)' 'Copilot STANDARD HIGH re-entry handoff'
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
Assert-Contains $standardAgent '(?s)条件を満たす場合、production code / testsを編集する前に.*`implementation_route: adaptive`.*`implementation_route_source: default`.*`route_metadata_normalization: legacy-adaptive-handoff`' 'STANDARD_MODEL legacy route metadata persistence'
Assert-Contains $standardAgent '(?s)## Required authorization.*- implementation_route.*- implementation_route_source.*- Validation performed' 'STANDARD_MODEL required authorization route metadata'
Assert-Contains $standardAgent '(?s)## High-model Re-entry Handoff.*- implementation_route:.*- implementation_route_source:.*- Design Pair handoff: N/A / plans/<slug>-design-pair-implementation-handoff\.md.*```' 'STANDARD_MODEL re-entry route identity fields'
Assert-Contains $standardAgent '`implementation_route`、`implementation_route_source`、Design Pair handoff pathはincoming Implementation Completion Handoffの値を変更せず維持' 'STANDARD_MODEL re-entry route identity propagation'
Assert-Contains $standardAgent 'この tracked handoff、incoming tracked Implementation Completion Handoff、元の Implementation Intent' 'STANDARD_MODEL re-entry original completion handoff retention'
Assert-Contains $standardAgent '(?s)部分的な新schema、不完全な旧schema、矛盾するevidence.*`BLOCKED`.*BlockedByInvalidCompletionHandoff' 'STANDARD_MODEL invalid legacy artifact classification'
Assert-Contains $standardAgent '(?s)片方が欠ける、矛盾する、またはevidenceと一致しないcurrent-schema handoff.*`BLOCKED`.*BlockedByInvalidCompletionHandoff' 'STANDARD_MODEL invalid current route classification'
Assert-Contains $standardAgent '(?s)`NEEDS_HIGH_MODEL_REENTRY` は.*Required authorizationを通過.*構造判断.*invalid.*re-entry handoffを作成しません' 'STANDARD_MODEL structural-only re-entry boundary'
Assert-Contains $standardAgent '(?s)## Output.*通常はすべてのverdict.*唯一の例外.*`Verdict: BLOCKED`.*`Stop reason: BlockedByInvalidCompletionHandoff`.*raw observed value.*`<missing>`.*外部blocker.*完全なunchanged identity.*- implementation_route.*- implementation_route_source.*- Design Pair handoff path または `N/A`' 'STANDARD_MODEL conditional route identity output'
Assert-NotContains $standardAgent '(?m)^すべてのverdictでincoming route identityを変更せず返します。$' 'unconditional STANDARD_MODEL route identity output'
Assert-Contains $standardAgent 'fresh intake.*直接選択.*編集せず.*tracked `READY_FOR_STANDARD_COMPLETION` handoff' 'STANDARD direct-start prohibition'
Assert-Contains $standardAgent '(?s)High-model Re-entry Handoff.*Verdict: NEEDS_HIGH_MODEL_REENTRY.*Handoff persistence: tracked.*Original Implementation Intent:.*Worktree state:' 'complete tracked re-entry metadata'
Assert-Contains $standardAgent 'state ownership、error、cancellation、retry' 'STANDARD policy decision re-entry trigger'
Assert-Contains $standardAgent '(?s)## High-model re-entry.*public / internal API、schema、serialized format、config surface.*DI / factory / entrypoint / production wiring.*state ownership / error / cancellation / retry' 'STANDARD complete structural re-entry trigger set'
Assert-Contains $standardAgent '会話履歴だけを唯一の状態保持手段にしてはいけません' 'Copilot STANDARD tracked handoff requirement'
Assert-NotContains $standardAgent 'agent:\s*copilot-standard-verifier' 'Copilot STANDARD verification handoff'

$handoff = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md'
foreach ($field in @(
    'Verdict',
    'Handoff persistence',
    'Original Implementation Intent',
    'Plan reference',
    'implementation_route',
    'implementation_route_source',
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
Assert-Contains $handoff '(?s)# Implementation Completion Handoff.*- implementation_route: adaptive / design-pair.*- implementation_route_source: default / explicit-user-selection.*## Acceptance status' 'current handoff header route metadata'
Assert-Contains $handoff 'current-schema handoff.*`BLOCKED` / `BlockedByInvalidCompletionHandoff`.*legacy normalizationで補完しない' 'current handoff invalid route classification'
Assert-Contains $handoff 'GitHub Copilot Chat in VS Code.*必ず`tracked`.*会話履歴だけをdurable stateにしない' 'Copilot handoff persistence contract'

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

foreach ($toml in @($highToml)) {
    Assert-Contains $toml 'complete Implementation Completion Handoff that preserves implementation_route and implementation_route_source' 'portable HIGH handoff route propagation'
    Assert-Contains $toml 'Accept only implementation_route: adaptive with implementation_route_source: default and an explicit N/A path, or implementation_route: design-pair with implementation_route_source: explicit-user-selection and the current tracked path' 'portable HIGH exact route identity tuples'
    Assert-Contains $toml 'Stop before editing and return BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff when any route identity field is missing.*raw observed field value or <missing> plus repair evidence; never infer or fabricate' 'portable HIGH invalid route classification and raw output'
    Assert-Contains $toml 'Normally return unchanged implementation_route, implementation_route_source, and the Design Pair Implementation Handoff path or N/A with every implementation result and completion handoff.*only exception is BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff.*raw observed values or <missing>.*Other BLOCKED results still require the complete unchanged identity' 'portable HIGH conditional route output continuity'
    Assert-Contains $toml 'require READY_FOR_ADAPTIVE_IMPLEMENTATION, interaction stage complete, Target Map presentation and selection-request evidence, an actual post-map user response, non-empty selected Targets or explicit all-Adaptive delegation, no pending human-owned Target' 'portable HIGH complete post-map authorization gate'
    Assert-Contains $toml 'require unique Target Map IDs; every summary Target ID to exist in the map; Selected, Delegated-to-Adaptive, No-Change, Upstream-Decision-Required, and Pending sets to be pairwise disjoint and exactly cover the map; and each set to match its row Disposition' 'portable HIGH Target set reconciliation gate'
    Assert-Contains $toml 'Require every Locked Decision Target to be Selected with a Locked row.*explicit all-Adaptive delegation.*Selected and Pending to be None.*every Target row to be Adaptive-Owned and present in the Delegated set' 'portable HIGH Locked and all-Adaptive invariants'
    Assert-Contains $toml 'Reject invented IDs, overlaps, unclassified Targets, or row/summary mismatches with BlockedByInvalidCompletionHandoff' 'portable HIGH malformed Target set rejection'
    Assert-Contains $toml 'For every Selected or Delegated-to-Adaptive Target, require exactly one Target Disposition Evidence row.*actual post-map user message or turn reference.*confirmation Yes' 'portable HIGH Target disposition evidence gate'
    Assert-Contains $toml 'Reject missing or duplicate evidence, invented Target IDs, row/evidence disposition mismatches, pre-map references, AI-generated confirmation, undelegated Adaptive-Owned Targets, and Discussed-Unlocked Targets without a final user response' 'portable HIGH invalid disposition evidence rejection'
    Assert-Contains $toml 'For every selected Target, require Selected Target Discussion Evidence with a user-facing assistant turn reference, concrete code location, current invariant, alternatives and trade-offs, a non-binding proposal or an evidence-backed No proposal reason, and validation expectations' 'portable HIGH selected Target discussion evidence gate'
    Assert-Contains $toml 'A topic label, artifact link, or abstract option list alone is invalid' 'portable HIGH abstract discussion rejection'
    Assert-Contains $toml "Require Target Map presentation evidence to reference a user-facing turn that presented every Target's concrete file and symbol, current invariant, internal design decision candidate, and relevant evidence" 'portable HIGH concrete Target Map presentation gate'
    Assert-Contains $toml 'An artifact link, Target ID, or topic summary alone is invalid presentation evidence' 'portable HIGH abstract Target Map rejection'
    Assert-Contains $toml 'keep the original Plan and Upstream Binding Constraints as separate binding inputs without Design Pair Decision IDs' 'portable HIGH upstream binding separation'
}
foreach ($toml in @($standardToml)) {
    Assert-Contains $toml 'including implementation_route and implementation_route_source, before editing' 'portable STANDARD route authorization'
    Assert-Contains $toml 'accept only implementation_route: adaptive with implementation_route_source: default, or implementation_route: design-pair with implementation_route_source: explicit-user-selection' 'portable STANDARD exact route pairs'
    Assert-Contains $toml 'Reject a missing, contradictory, or evidence-inconsistent current-schema route identity before editing.*raw observed field value or <missing> plus repair evidence.*explicit N/A Design Pair Implementation Handoff path for implementation_route: adaptive.*current tracked path' 'portable STANDARD route identity fail-closed rule'
    Assert-Contains $toml 'Persist implementation_route: adaptive, implementation_route_source: default.*legacy-adaptive-handoff normalization record' 'portable STANDARD legacy route persistence'
    Assert-Contains $toml 'High-model Re-entry Handoff.*unchanged implementation_route and implementation_route_source.*unchanged Design Pair Implementation Handoff path or N/A' 'portable STANDARD re-entry route identity propagation'
    Assert-Contains $toml 'Normally return unchanged implementation_route, implementation_route_source, and the Design Pair Implementation Handoff path or N/A with every completion or re-entry result.*only exception is BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff.*raw observed values or <missing>.*Other BLOCKED results still require the complete unchanged identity' 'portable STANDARD conditional route output continuity'
    Assert-Contains $toml 'Reject a missing, contradictory, or evidence-inconsistent current-schema route identity before editing by returning BLOCKED with Stop reason: BlockedByInvalidCompletionHandoff; return each raw observed field value or <missing> plus repair evidence' 'portable STANDARD invalid route classification'
    Assert-Contains $toml 'Reserve NEEDS_HIGH_MODEL_REENTRY for a structural decision discovered after a current-schema or normalized handoff has passed authorization' 'portable STANDARD structural-only re-entry boundary'
}

Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md' 'VAL-012: Portable agent route validation' 'portable route validation scenario'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md' 'missing, contradictory, or evidence-inconsistent current-schema handoff returns `BLOCKED` with `BlockedByInvalidCompletionHandoff` and does not emit `NEEDS_HIGH_MODEL_REENTRY`' 'invalid handoff validation scenario'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md' 'fresh `adaptive / default` intake initializes `design_pair_handoff: N/A`' 'fresh default N/A validation scenario'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md' 'invalid-artifact `BLOCKED` returns raw observed values or `<missing>` for each identity field plus repair evidence; parent accepts this stop result without requiring a complete pair' 'invalid-artifact BLOCKED output exception scenario'
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

foreach ($sharedMarker in @(
    'READY_FOR_STANDARD_COMPLETION',
    'Original Implementation Intent',
    'implementation_route',
    'implementation_route_source',
    'Design Pair handoff',
    'Decision ID',
    'Allowed edit surface',
    'Implementation Self-Map Delta'
)) {
    Assert-Contains $highAgent ([regex]::Escape($sharedMarker)) "canonical HIGH shared marker $sharedMarker"
}

foreach ($sharedMarker in @(
    'NEEDS_HIGH_MODEL_REENTRY',
    'Original Implementation Intent',
    'implementation_route',
    'implementation_route_source',
    'Design Pair handoff',
    'Decision ID',
    'Allowed edit surface',
    'Implementation Self-Map Delta'
)) {
    Assert-Contains $standardAgent ([regex]::Escape($sharedMarker)) "canonical STANDARD shared marker $sharedMarker"
}
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
Assert-Contains $validation '実モデル run.*NOT RUN' 'manual runtime run status'
Assert-Contains $validation 'VAL-013: GitHub Copilot VS Code package configuration' 'Copilot package configuration validation scenario'
Assert-Contains $validation 'Copilot CLI real-model orchestration.*PASS' 'Copilot CLI real-model validation status'
Assert-Contains $validation 'omits `tools` so Copilot uses its default tool set' 'Copilot default tool-set contract'

$routingScenarios = 'apm-packages/adaptive-implementation-execution/tests/routing-scenarios.json'
$routingValidator = 'apm-packages/adaptive-implementation-execution/tests/validate-routing-scenarios.ps1'
Assert-Contains $routingValidator 'Get-ScenarioErrors' 'routing state-machine validator'
Assert-Contains $routingValidator 'Assert-RejectedMutation' 'negative routing mutation checks'
try {
    & (Join-Path $repoRoot $routingValidator) -FixturePath (Join-Path $repoRoot $routingScenarios) | Write-Output
}
catch {
    Add-Failure "Executable routing scenario validation failed: $($_.Exception.Message)"
}

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

$apmSmoke = 'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-apm-smoke.ps1'
Assert-Contains $apmSmoke 'APM 0\.26\.0 is required' 'pinned APM 0.26.0 requirement'
Assert-Contains $apmSmoke 'copilot,codex,agent-skills' 'combined Copilot Codex Skill install target'
Assert-Contains $apmSmoke 'apm-packages/adaptive-implementation-execution#\$Ref' 'commit or ref pinned package spec'
Assert-Contains $apmSmoke "'install', '--frozen'" 'idempotent frozen reinstall'
Assert-Contains $apmSmoke 'USER_CUSTOM_HIGH_AGENT' 'existing Copilot customization collision fixture'
Assert-Contains $apmSmoke 'without --force' 'default collision protection assertion'
Assert-Contains $apmSmoke '(?s)Copilot HIGH model.*Copilot STANDARD model' 'Copilot model deployment assertions'
Assert-Contains $apmSmoke '(?s)Copilot HIGH explicit-only invocation.*Copilot STANDARD explicit-only invocation' 'deployed Copilot explicit-only invocation assertions'
Assert-Contains $apmSmoke 'deployed skill explicit-only model invocation' 'deployed skill disable-model-invocation assertion'
Assert-Contains $apmSmoke 'deployed skill rejects plain implementation requests' 'deployed skill plain-request rejection assertion'
Assert-Contains $apmSmoke '(?s)Codex HIGH model.*Codex STANDARD model' 'Codex model compatibility assertions'
Assert-Contains $apmSmoke 'lossy agent compilation warnings' 'lossy APM compilation rejection'
Assert-Contains $apmSmoke 'frontmatter field' 'dropped APM frontmatter rejection'
Assert-Contains $apmSmoke 'Assert-NotContains.*Copilot HIGH explicit tools frontmatter' 'deployed Copilot tools omission assertion'

Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' 'APM install が skill と portable custom agents を導入する本体' 'APM-first quick start'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '`AGENTS\.md` を作成・変更・削除せず' 'documented AGENTS.md non-access'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '`disable-model-invocation: true`.*明示選択.*subagent起動を禁止' 'documented explicit-only Copilot agents'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '`/adaptive-implementation-execution` で slash 起動した場合だけ起動' 'documented skill slash-invocation-only selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '「実装して」や自然文での名前言及だけでは自動選択しません' 'documented plain and natural-language non-selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' 'frontmatter は `disable-model-invocation: true` と `user-invocable: true`' 'documented skill invocation frontmatter'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '/adaptive-implementation-execution この Plan を実装してください' 'documented Copilot slash invocation example'
Assert-NotContains 'apm-packages/adaptive-implementation-execution/README.md' '\$adaptive-implementation-execution' 'obsolete README dollar-prefix skill invocation'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' 'route_metadata_normalization: legacy-adaptive-handoff' 'documented legacy resume normalization marker'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '--check.*次を検証' 'documented installer checks'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' 'APM-generated model-less stub' 'documented APM stub completion policy'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' 'Migration from the former managed section' 'legacy managed section migration note'

Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '導入されているだけで.*自動適用しません' 'documented non-automatic skill selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '`/adaptive-implementation-execution` で slash 起動した場合だけ選択' 'documented slash-invocation-only skill selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '「実装して」「このPlanを実装して」、および「Adaptive Implementationを使って」などの自然文での名前言及だけでは選択しません' 'documented plain and natural-language non-selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '`disable-model-invocation: true`.*`user-invocable: true`' 'documented skill invocation frontmatter'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '/adaptive-implementation-execution 直前の Plan を実装してください' 'usage-guide Copilot slash invocation example'
Assert-NotContains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '\$adaptive-implementation-execution' 'obsolete usage-guide dollar-prefix skill invocation'
Assert-NotContains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' 'または現在の task がこの package の HIGH_MODEL → STANDARD_MODEL 直列 workflow を明確に必要とする場合に選択' 'obsolete usage-guide task-requires auto-selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '`/adaptive-implementation-execution` で slash 起動した場合だけ選択' 'install-guide slash-invocation-only skill selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '「実装して」「このPlanを実装して」、および「Adaptive Implementationを使って」などの自然文での名前言及だけでは選択されません' 'install-guide plain and natural-language non-selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '`disable-model-invocation: true`' 'install-guide skill disable-model-invocation'
Assert-NotContains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' '\$adaptive-implementation-execution' 'obsolete install-guide dollar-prefix skill invocation'
Assert-NotContains 'apm-packages/adaptive-implementation-execution/docs/install-guide.md' 'またはtaskがこのpackageの直列workflowを明確に必要とする場合に選択' 'obsolete install-guide task-requires auto-selection'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' 'legacy-adaptive-handoff\.md' 'documented legacy resume fixture'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/examples/adaptive-routing-validation.md' 'installer does not create, read, update, or remove `AGENTS\.md`' 'validation scenario for AGENTS.md non-access'

$copilotManualSmoke = 'apm-packages/adaptive-implementation-execution/docs/examples/copilot-manual-smoke.md'
Assert-Contains $copilotManualSmoke '(?s)VS Code version.*GitHub Copilot / Copilot Chat extension version' 'manual Copilot environment record'
Assert-Contains $copilotManualSmoke 'Selected agent.*Requested model.*Observed model.*Files changed.*Validation commands / results.*Terminal verdict.*Unexpected automatic handoff' 'manual Copilot phase evidence schema'
Assert-Contains $copilotManualSmoke '(?s)このPlanを実装して.*adaptive-implementation-execution.*暗黙選択' 'manual plain implementation non-auto-select check'
Assert-Contains $copilotManualSmoke '(?s)Adaptive Implementationを使ってこのPlanを実装して.*自動ロードにならない' 'manual natural-language name non-auto-select check'
Assert-Contains $copilotManualSmoke '(?s)/adaptive-implementation-execution この Plan を実装してください.*slash 明示起動' 'manual explicit Adaptive slash invocation check'
Assert-Contains $copilotManualSmoke 'plain implementation request did not auto-select Adaptive skill' 'manual completion decision for plain request'
Assert-Contains $copilotManualSmoke 'natural-language "Adaptive Implementationを使って" did not auto-select Adaptive skill' 'manual completion decision for natural-language name'
Assert-Contains $copilotManualSmoke 'explicit `/adaptive-implementation-execution` slash invocation still works' 'manual completion decision for slash invocation'
Assert-NotContains $copilotManualSmoke '\$adaptive-implementation-execution' 'obsolete manual-smoke dollar-prefix skill invocation'
Assert-Contains $copilotManualSmoke 'COMPLETED_BY_HIGH_MODEL.*STANDARDへ自動handoffされず' 'manual direct HIGH completion check'
Assert-Contains $copilotManualSmoke '(?is)NEEDS_HIGH_MODEL_REENTRY.*original Implementation Intent|original Implementation Intent.*NEEDS_HIGH_MODEL_REENTRY' 'manual structural re-entry state check'
Assert-Contains $copilotManualSmoke '利用可否はCopilot planとorganization policyに依存' 'Copilot model availability caveat'
Assert-Contains $copilotManualSmoke 'NOT RUN' 'manual smoke unexecuted disclosure'
Assert-Contains $copilotManualSmoke 'GitHub Copilot CLI.*copilot-cli-real-model-e2e-2026-07-31.md' 'Copilot CLI automation equivalence'

$copilotCliEvidence = 'apm-packages/adaptive-implementation-execution/docs/examples/copilot-cli-real-model-e2e-2026-07-31.md'
Assert-Contains $copilotCliEvidence '816268eea12ae4e61a40f045de9448d180ef4a2c' 'real-model source commit'
Assert-Contains $copilotCliEvidence 'gpt-5\.6-terra -> gpt-5\.6-luna -> gpt-5\.6-terra' 'observed Terra Luna Terra route'
Assert-Contains $copilotCliEvidence 'COMPLETED_BY_HIGH_MODEL' 'real-model HIGH completion verdict'
Assert-Contains $copilotCliEvidence 'READY_FOR_STANDARD_COMPLETION' 'real-model bounded handoff verdict'
Assert-Contains $copilotCliEvidence 'NEEDS_HIGH_MODEL_REENTRY' 'real-model structural re-entry verdict'
Assert-Contains $copilotCliEvidence 'BlockedByInvalidCompletionHandoff' 'real-model invalid handoff rejection'
Assert-Contains $copilotCliEvidence 'unknown fields ignored: target, handoffs' 'Copilot CLI VS Code field limitation'

$workflow = '.github/workflows/validate-adaptive-implementation-execution.yml'
Assert-Contains $workflow 'validate-adaptive-implementation-execution\.ps1' 'Adaptive Implementation CI validator invocation'
Assert-Contains $workflow '(?m)^\s*runs-on:\s*ubuntu-latest\s*$' 'APM-supported Linux runner'
Assert-Contains $workflow 'actions/setup-dotnet@v5' '.NET setup action'
Assert-Contains $workflow "dotnet-version: '10\.0\.x'" '.NET 10 SDK for File-based app smoke'
Assert-Contains $workflow 'microsoft/apm-action@v1' 'APM setup action'
Assert-Contains $workflow "apm-version: '0\.26\.0'" 'pinned APM workflow version'
Assert-Contains $workflow 'validate-adaptive-implementation-apm-smoke\.ps1' 'remote APM install smoke invocation'
Assert-Contains $workflow 'github\.event\.pull_request\.head\.repo\.full_name.*github\.repository' 'fork-safe remote smoke repository'
Assert-Contains $workflow 'github\.event\.pull_request\.head\.sha.*github\.sha' 'commit SHA pinned smoke ref'
foreach ($pathFilter in @(
    'apm-packages/design-pair-implementation-execution/\*\*',
    'apm-packages/plan-coverage-residual-flow/\*\*',
    'apm-packages/token-aware-full-coverage-3layer/\*\*',
    'scripts/provision-work-repo-agents\.cs',
    'docs/\*\*'
)) {
    Assert-Contains $workflow $pathFilter "CI path filter $pathFilter"
}

Assert-Contains 'README.md' 'apm-packages/adaptive-implementation-execution' 'root package link'
Assert-Contains 'README.md' 'apm-packages/design-pair-implementation-execution' 'root Design Pair package link'
Assert-Contains 'apm-packages/adaptive-implementation-execution/README.md' '`AGENTS\.md` を作成・変更・削除せず' 'Adaptive helper AGENTS.md non-access statement'
Assert-NotContains 'apm-packages/adaptive-implementation-execution/README.md' 'install-adaptive-implementation-local\.cs[^\r\n]*`AGENTS\.md` の managed section' 'obsolete Adaptive helper AGENTS.md managed-section claim'

if ($failures.Count -gt 0) {
    Write-Error ("Adaptive Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Adaptive Implementation validation: PASS'
