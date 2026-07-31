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
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md',
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/result-template.md',
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/fixture/plans/retry-after-plan.md',
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/fixture/src/RetryPolicy.cs',
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/fixture/src/RetryingClient.cs',
    'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/fixture/tests/RetryPolicyTests.cs',
    'apm-packages/design-pair-implementation-execution/scripts/validate.ps1',
    'apm-packages/adaptive-implementation-execution/apm.yml',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md',
    'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/refs/handoff.md',
    'apm-packages/adaptive-implementation-execution/docs/examples/legacy-adaptive-handoff.md',
    'apm-packages/adaptive-implementation-execution/docs/install-guide.md',
    'apm-packages/adaptive-implementation-execution/scripts/install-adaptive-implementation-local.cs',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md',
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
Assert-Contains $manifest '(?m)^version:\s*0\.2\.0\s*$' 'package version 0.2.0'
Assert-Contains $manifest '(?m)^\s*-\s+codex\s*$' 'codex target'
Assert-Contains $manifest '(?m)^\s*-\s+agent-skills\s*$' 'agent-skills target'
Assert-NotContains $manifest '(?m)^\s*-\s+copilot\s*$' 'unverified Copilot target'
Assert-Contains $manifest 'adaptive-implementation-execution/\.apm/skills/adaptive-implementation-execution' 'Adaptive skill dependency'
Assert-Contains $manifest '\.github/agents/high-implementation-starter\.agent\.md' 'canonical HIGH agent dependency'
Assert-Contains $manifest '\.github/agents/standard-implementation-completer\.agent\.md' 'canonical STANDARD agent dependency'
Assert-NotContains $manifest 'implementation-execution\.agent\.md' 'legacy implementation orchestration dependency'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/apm.yml' '(?m)^version:\s*0\.8\.0\s*$' 'Plan Coverage package version 0.8.0'
Assert-Contains 'apm-packages/token-aware-full-coverage-3layer/apm.yml' '(?m)^version:\s*0\.5\.0\s*$' 'full-coverage package version 0.5.0'
Assert-Contains 'apm-packages/codex-first-ai-development-process/apm.yml' '(?m)^version:\s*0\.6\.0\s*$' 'Codex-first package version 0.6.0'
Assert-Contains 'apm-packages/adaptive-implementation-execution/apm.yml' '(?m)^version:\s*0\.3\.0\s*$' 'Adaptive package version 0.3.0'

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
Assert-Contains $skill '(?s)## Phase 3: Present the Target Map and stop.*AWAITING_USER_INPUT.*interaction_stage: target-selection.*その turn を終了する' 'mandatory initial post-map turn stop'
Assert-Contains $skill '(?s)初回 turn では次を禁止する.*READY_FOR_ADAPTIVE_IMPLEMENTATION.*adaptive-implementation-execution.*production code / tests.*Locked Decision' 'initial turn prohibitions'
Assert-Contains $skill '最初の依頼が「実装してください」であっても、この boundary を省略しない' 'implementation request cannot skip interaction boundary'
Assert-Contains $skill '(?s)resume では.*interaction stage.*Target Map.*presentation evidence.*Target Map 提示後の user response.*BLOCKED.*Adaptive へ fallback しない' 'resume waiting evidence fail-closed rule'
Assert-Contains $skill '(?s)user response は、test harness や parent が補足、言い換え、または必要項目を合成せず、そのまま.*Target ID の選択だけ.*partial selection.*`AWAITING_USER_INPUT / target-selection` を維持' 'verbatim partial-selection handling'
Assert-Contains $skill '(?s)必要な selection input が揃い.*trade-off.*`AWAITING_USER_INPUT / disposition-confirmation` へ進める' 'partial selection cannot advance early'
Assert-Contains $skill '(?s)選択された Target の対話では.*handoff artifactへのlinkまたは論点名だけを返してはいけない.*Target ID と具体的な file / symbol.*現在の責務と invariant.*直接 caller、production wiring、lifecycle / state ownership、test seam.*実在する代替案.*trade-off.*非 binding の AI proposal.*`No proposal`.*validation expectation' 'selected Target minimum discussion surface'
Assert-Contains $skill '(?s)Target IDだけのpartial selectionでも.*minimum discussion surfaceを提示.*Target Map内に詳細があることをuser-facing説明の代替にせず.*`Selected Target Discussion Evidence`' 'partial selection concrete discussion evidence'
Assert-Contains $skill '(?s)各 response.*handoff header、Target Map row、summary Target sets、Readiness Check.*同じ observed evidence から再計算.*User response occurred after Target Map presentation: Yes.*同名 row.*`PASS`' 'mirrored user evidence synchronization'
Assert-Contains $skill '(?s)Target Map 提示後の通常 interaction stage は `target-selection`、`disposition-confirmation`、`upstream-decision`、`complete` のいずれかだけ.*`target-map-building` は提示前の `DRAFT`.*`artifact-repair` は.*`BLOCKED`' 'closed Design Pair interaction stage vocabulary'
Assert-Contains $skill '(?s)AWAITING_USER_INPUT.*interaction_stage: disposition-confirmation' 'disposition confirmation waiting state'
Assert-Contains $skill '全 Target を Adaptive へ委ねると明示した場合.*Locked Decision を作らず READY' 'explicit all-Adaptive delegation path'
Assert-Contains $skill 'Target 未選択を空集合として PASS にしない' 'empty selection readiness prevention'
Assert-Contains $skill '(?s)user message / turn reference.*Target ID.*忠実な要約.*confirmation occurred after Target Map presentation: Yes' 'post-map confirmation evidence requirements'
Assert-Contains $skill 'upstream Plan、Issue、acceptance criteria、gold document、repository policy / public contract.*Upstream Binding Constraints' 'upstream constraint separation'
Assert-Contains $skill 'Target Map と code evidence の提示前に Locked Decision へ昇格しない' 'initial position is not automatic Locked Decision'
Assert-Contains $skill '(?s)READY 判定前に、Target Map と summary field を集合として照合.*Target Map の全 Target ID は一意.*concrete ID はすべて Target Map に実在.*5集合は互いに素.*和集合は Target Map の全 Target ID と完全一致' 'Target Map and summary set reconciliation'
Assert-Contains $skill '(?s)`Selected Target IDs`: disposition が `Locked` または `Discussed-Unlocked`.*`Delegated-to-Adaptive Target IDs`: disposition が `Adaptive-Owned`.*`No-Change Target IDs`: disposition が `No-Change`.*`Upstream-Decision-Required Target IDs`: disposition が `Upstream-Decision-Required`.*`Pending human-owned Target IDs`: disposition が `Pending-User-Selection` または `Pending-User-Disposition`' 'summary set to row disposition mapping'
Assert-Contains $skill '(?s)各 Locked Decision の Target ID は `Selected Target IDs` に含まれ.*Target Map row は `Locked`.*`Locked` row には一件以上の valid Locked Decision' 'Locked Decision target membership invariant'
Assert-Contains $skill '(?s)`Explicit all-Adaptive delegation: Yes`.*`Selected Target IDs: None`.*`Pending human-owned Target IDs: None`.*Locked Decisionsなし.*全 Target row が `Adaptive-Owned`.*`Delegated-to-Adaptive Target IDs` が全 Target IDと完全一致' 'all-Adaptive exact coverage invariant'
Assert-Contains $skill 'plans/<slug>-design-pair-implementation-handoff\.md' 'tracked handoff path'
Assert-Contains $skill 'Affected files / symbols.*allowed edit surface ではない' 'file-symbol non-allowlist rule'
Assert-Contains $skill 'Locked Decisions.*binding constraint' 'binding-only Locked Decisions rule'
Assert-Contains $skill '通常の adaptive implementation と同じ authority' 'Adaptive HIGH authority invariant'
Assert-Contains $skill 'automatic Design Pair re-entry は行わない' 'no automatic Design Pair re-entry'
Assert-Contains $skill 'final code review.*独立 verification' 'final review boundary'

$map = 'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/map.md'
Assert-Contains $map 'Target ID.*File / Symbol.*Current responsibility.*Current invariant.*Relation to requested change.*Internal design decision candidate.*Expected modification or verification.*Relevant evidence.*Open question.*Disposition' 'complete Target Map schema'
Assert-Contains $map 'Production symbol and direct call sites' 'production call-site coverage row'
Assert-Contains $map 'Tests / fixtures / test seam' 'test coverage row'
Assert-Contains $map 'DI / factory / startup / entrypoint / production wiring' 'wiring coverage row'
Assert-Contains $map 'allowed edit surface ではない' 'Target Map non-allowlist note'
Assert-Contains $map 'Target Map presentation evidence' 'Target Map presentation evidence field'
Assert-Contains $map 'Target selection request evidence' 'Target selection request evidence field'
Assert-Contains $map 'Pending-User-Selection.*Pending-User-Disposition' 'pending human disposition vocabulary'
Assert-Contains $map '提示後の明示的な利用者応答なしに.*Locked.*Discussed-Unlocked.*Adaptive-Owned' 'no pre-response human disposition assignment'
Assert-Contains $map 'READY 判定時は Target ID を一意な集合.*handoff summary の全IDがこの表に実在.*5分類が重複なく全rowを覆う.*各分類がDispositionと一致' 'Target Map set reconciliation note'

$handoff = 'apm-packages/design-pair-implementation-execution/.apm/skills/design-pair-implementation-execution/handoff.md'
foreach ($field in @(
    'implementation_route',
    'implementation_route_source',
    'Interaction stage',
    'Target Map presentation evidence',
    'Target selection request evidence',
    'Latest user response reference',
    'User response occurred after Target Map presentation',
    'Selected Target IDs',
    'Delegated-to-Adaptive Target IDs',
    'No-Change Target IDs',
    'Upstream-Decision-Required Target IDs',
    'Explicit all-Adaptive delegation',
    'Pending human-owned Target IDs',
    'Selected Target discussion evidence',
    'Design Pair Target Map',
    'Upstream Binding Constraints',
    'Upstream User Initial Positions',
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
Assert-Contains $handoff 'Decision ID.*Target ID.*Decision.*Affected files / symbols.*Rationale.*Validation expectations.*Conflict conditions.*User message / turn reference.*Confirmed content quote or faithful summary.*Confirmation occurred after Target Map presentation' 'complete Locked Decision schema'
Assert-Contains $handoff 'section に Decision ID、presented Target ID、実際の user message / turn reference、確認内容.*Confirmation occurred after Target Map presentation: Yes.*binding' 'explicit post-map binding rule'
Assert-Contains $handoff 'allowed edit surface ではない' 'handoff non-allowlist rule'
Assert-Contains $handoff '(?s)Readiness Check.*Target Map was presented to the user.*Target selection and initial positions were requested.*A user response occurred after Target Map presentation.*Non-empty user participation or explicit all-Adaptive delegation exists.*User-selected discussion targets have final dispositions.*No pending human-owned Target remains' 'non-empty post-map readiness checks'
Assert-Contains $handoff 'Target が一件も選択されず.*Adaptive delegation.*空集合として PASS にしない' 'handoff empty-selection failure rule'
Assert-Contains $handoff 'Selected Target IDs: Pending / None / <DP-Txx list>' 'formal None value for selected Targets'
Assert-Contains $handoff '(?s)Target Map IDs are unique and every summary ID exists in the Target Map.*Summary Target sets are pairwise disjoint and exactly cover the Target Map.*Summary classifications match every Target Map row Disposition.*Locked Decision Target IDs are selected and their Target Map rows are Locked.*Explicit all-Adaptive delegation has None selected/pending, no Locked Decisions, and every Target is Adaptive-Owned' 'handoff set invariant readiness checks'
Assert-Contains $handoff '5集合を Target Map と照合し、架空 ID、重複 ID、未分類 Target、row / summary 不一致を一件でも許可しない' 'handoff set invariant failure rule'
Assert-Contains $handoff '(?s)Target IDだけ.*partial selection.*User response occurred after Target Map presentation: Yes.*Interaction stage: target-selection.*pending分類を維持' 'handoff partial-selection representation'
Assert-Contains $handoff '(?s)`design-discussion`等の独自stageを作ってはいけない.*headerとReadiness Check.*Yes / No、PASS / FAIL、user referenceを矛盾させない' 'handoff mirrored evidence consistency'
Assert-Contains $handoff 'Interaction stage: target-map-building / target-selection / disposition-confirmation / upstream-decision / complete / artifact-repair' 'handoff closed stage schema'
Assert-NotContains $handoff '(?m)^- Interaction stage:.*design-discussion' 'deprecated design-discussion stage in handoff schema'
Assert-Contains $handoff '(?s)`target-map-building`はTarget Map提示前の`DRAFT`だけ.*`artifact-repair`は.*`BLOCKED`だけ.*Target Map提示後の通常経路.*`target-selection`、`disposition-confirmation`、`upstream-decision`、`complete`以外へ遷移しない' 'handoff stage applicability rules'
Assert-Contains $handoff '(?s)## Selected Target Discussion Evidence.*Target ID.*Assistant turn reference.*Concrete file / symbol / line evidence.*Current responsibility / invariant.*Caller / wiring / lifecycle / test-seam evidence.*Alternatives and trade-offs.*Non-binding AI proposal or No proposal reason.*Validation expectation.*Open questions' 'selected Target discussion evidence schema'
Assert-Contains $handoff '(?s)Selected Targets have concrete user-facing discussion evidence.*Target IDs, assistant turn references, code locations, trade-offs, proposal, validation' 'selected Target discussion readiness check'
Assert-Contains $handoff '(?s)partial selectionでも.*具体的file / symbol.*current responsibility / invariant.*caller / wiring / lifecycle / test seam.*alternatives / trade-offs.*proposalまたはNo proposal理由.*validation expectation.*論点名だけの応答はFAIL' 'partial selection concrete handoff evidence rule'
Assert-Contains $handoff 'Plan / Issue / acceptance criteria / repository policy / public contract.*Design Pair Decision ID を付けず' 'handoff upstream constraint separation'

$adaptiveSkill = 'apm-packages/adaptive-implementation-execution/.apm/skills/adaptive-implementation-execution/SKILL.md'
Assert-Contains $adaptiveSkill 'Design Pair Implementation Handoff' 'Design Pair input support'
Assert-Contains $adaptiveSkill '(?s)binding なのは.*Locked Decisions.*だけ' 'Adaptive binding-only rule'
Assert-Contains $adaptiveSkill 'Affected files / symbols.*Allowed edit surface.*扱いません' 'Adaptive non-allowlist rule'
Assert-Contains $adaptiveSkill 'Design Pair Decision ID' 'Design Pair Decision ID propagation'
Assert-Contains $adaptiveSkill 'automatic Design Pair re-entry' 'Adaptive no automatic re-entry rule'
Assert-Contains $adaptiveSkill 'Locked Decision conflict' 'Adaptive conflict stop report'
Assert-Contains $adaptiveSkill '(?s)Target Map ID が一意.*summary の全 Target ID が Target Map に実在.*5集合が互いに素.*和集合が Target Map 全体と完全一致.*summary 集合が Target Map row.*一致' 'Adaptive Target set reconciliation gate'
Assert-Contains $adaptiveSkill '(?s)Locked Decision Target ID が `Selected Target IDs` に含まれ.*Target Map row が `Locked`.*all-Adaptive delegation.*selected / pending が `None`.*全 Target row が `Adaptive-Owned`.*delegated集合と完全一致' 'Adaptive Locked and all-Adaptive invariants'
Assert-Contains $adaptiveSkill '架空 ID、重複 ID、未分類 Target、row / summary 不一致.*も拒否' 'Adaptive malformed Target set rejection'
Assert-Contains $adaptiveSkill '(?s)selected Targetごとに`Selected Target Discussion Evidence`.*user-facing assistant turn reference.*具体的code location.*current invariant.*alternatives / trade-offs.*proposalまたはNo proposal理由.*validation expectation' 'Adaptive selected Target discussion evidence gate'
Assert-Contains $adaptiveSkill '抽象的な論点名だけで具体的なSelected Target discussion evidenceがないartifactも拒否' 'Adaptive abstract discussion rejection'
Assert-Contains $adaptiveSkill '新規 intake と resume を分けます' 'fresh intake and resume distinction'
Assert-Contains $adaptiveSkill '欠落や矛盾を Adaptive へ補完しません' 'resume fail-closed route metadata'
Assert-Contains $adaptiveSkill 'route_metadata_normalization: legacy-adaptive-handoff' 'legacy Adaptive handoff normalization marker'
Assert-Contains $adaptiveSkill '(?s)```yaml.*implementation_route: adaptive.*implementation_route_source: default.*design_pair_handoff: N/A.*```' 'fresh Adaptive route identity initialization'
Assert-Contains $adaptiveSkill '(?s)## Step 2: Start with HIGH_MODEL.*渡すもの:.*- `implementation_route`.*- `implementation_route_source`.*HIGH_MODEL は code' 'Adaptive HIGH explicit route input payload'
Assert-Contains $adaptiveSkill 'Design Pair Implementation Handoff path（`adaptive / default`では明示的な`N/A`、`design-pair / explicit-user-selection`ではcurrent tracked path）' 'Adaptive HIGH explicit default N/A path payload'
Assert-Contains $adaptiveSkill '(?s)通常はすべてのHIGH_MODEL result.*唯一の例外.*`Verdict: BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*artifact repair evidence' 'Adaptive parent HIGH invalid route exception'
Assert-Contains $adaptiveSkill '(?s)通常はすべてのSTANDARD_MODEL result.*唯一の例外.*`Verdict: BLOCKED`.*BlockedByInvalidCompletionHandoff.*raw observed value.*`<missing>`.*artifact repair evidence' 'Adaptive parent STANDARD invalid route exception'
Assert-Contains $adaptiveSkill 'previous Implementation Completion Handoff と High-model Re-entry Handoff' 'Adaptive HIGH re-entry dual handoff payload'
Assert-Contains $adaptiveSkill '(?s)### NEEDS_HIGH_MODEL_REENTRY.*元の (?:tracked )?`Implementation Completion Handoff`.*両handoffの`implementation_route`、`implementation_route_source`、Design Pair handoff pathが一致' 'Adaptive HIGH re-entry route identity validation'

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
Assert-Contains $highAgent '(?s)Target Map IDは一意.*全summary IDはTarget Mapに実在.*5集合は互いに素かつTarget Map全体を完全被覆.*各summary分類はrow Dispositionと一致' 'HIGH Target set reconciliation gate'
Assert-Contains $highAgent '(?s)Locked Decision TargetはSelectedかつrowがLocked.*all-AdaptiveではSelected / PendingがNone.*全Target rowがAdaptive-OwnedかつDelegated集合と完全一致' 'HIGH Locked and all-Adaptive invariants'
Assert-Contains $highAgent '架空ID、重複ID、未分類Target、row / summary不一致' 'HIGH malformed Target set rejection'
Assert-Contains $highAgent '(?s)selected Targetにはuser-facing assistant turn reference.*具体的code location.*current invariant.*alternatives / trade-offs.*非binding proposalまたはNo proposal理由.*validation expectation.*`Selected Target Discussion Evidence`' 'HIGH selected Target discussion evidence gate'
Assert-Contains $highAgent '抽象的な論点名だけのdiscussion evidence' 'HIGH abstract discussion rejection'
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
Assert-Contains $standardAgent 'この tracked handoff、incoming tracked Implementation Completion Handoff、元の Implementation Intent' 'STANDARD re-entry original completion handoff retention'
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
    Assert-Contains $toml 'require unique Target Map IDs; every summary Target ID to exist in the map; Selected, Delegated-to-Adaptive, No-Change, Upstream-Decision-Required, and Pending sets to be pairwise disjoint and exactly cover the map; and each set to match its row Disposition' 'portable HIGH Target set reconciliation gate'
    Assert-Contains $toml 'Require every Locked Decision Target to be Selected with a Locked row.*explicit all-Adaptive delegation.*Selected and Pending to be None.*every Target row to be Adaptive-Owned and present in the Delegated set' 'portable HIGH Locked and all-Adaptive invariants'
    Assert-Contains $toml 'Reject invented IDs, overlaps, unclassified Targets, or row/summary mismatches with BlockedByInvalidCompletionHandoff' 'portable HIGH malformed Target set rejection'
    Assert-Contains $toml 'For every selected Target, require Selected Target Discussion Evidence with a user-facing assistant turn reference, concrete code location, current invariant, alternatives and trade-offs, a non-binding proposal or an evidence-backed No proposal reason, and validation expectations' 'portable HIGH selected Target discussion evidence gate'
    Assert-Contains $toml 'A topic label, artifact link, or abstract option list alone is invalid' 'portable HIGH abstract discussion rejection'
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

$planCoverageSkill = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md'
Assert-Contains $planCoverageSkill 'implementation_route:\s*adaptive' 'Plan Coverage default Adaptive route'
Assert-Contains $planCoverageSkill 'implementation_route_source:\s*default' 'Plan Coverage default route source'
Assert-Contains $planCoverageSkill 'design-pair-implementation-execution' 'Plan Coverage explicit Design Pair route'
Assert-Contains $planCoverageSkill 'Do not automatically select, recommend, or propose Design Pair' 'Plan Coverage no automatic Design Pair selection'
Assert-Contains $planCoverageSkill 'Missing or contradictory route metadata.*must not be inferred during resume' 'Plan Coverage resume fail-closed rule'
Assert-Contains $planCoverageSkill 'design_pair_interaction_stage' 'Plan Coverage interaction stage propagation'
Assert-Contains $planCoverageSkill '(?s)first turn must present.*AWAITING_USER_INPUT / target-selection.*stop.*AWAITING_USER_INPUT / disposition-confirmation.*stop again' 'Plan Coverage mandatory Design Pair turn boundaries'
Assert-Contains $planCoverageSkill 'While Design Pair is waiting.*Do not treat waiting as completion.*verification / residual' 'Plan Coverage waiting blocks downstream flow'

foreach ($statePath in @(
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md',
    'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/references/full-coverage-parent-orchestration-state.md',
    'apm-packages/codex-first-ai-development-process/templates/codex-first-state.md'
)) {
    Assert-Contains $statePath 'implementation_route' 'implementation route state field'
    Assert-Contains $statePath 'implementation_route_source' 'implementation route source state field'
    Assert-Contains $statePath 'design_pair_handoff' 'Design Pair handoff state field'
    Assert-Contains $statePath 'design_pair_interaction_stage' 'Design Pair interaction stage state field'
    Assert-Contains $statePath 'design_pair_user_evidence' 'Design Pair user evidence state field'
}

Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'implementation_route' 'handoff review route propagation'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'design-pair-implementation-execution' 'handoff review explicit next route'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' '新規 intake.*だけ `adaptive / default` を初期化' 'handoff review fresh-intake-only default'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'resume.*BLOCKED_BY_ARTIFACT_MISMATCH' 'handoff review resume fail-closed rule'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'design_pair_interaction_stage' 'handoff review interaction stage propagation'
Assert-Contains '.github/agents/implementation-handoff-review.agent.md' 'waiting中はAdaptiveやverificationを次stepにしない' 'handoff review waiting downstream block'

$codexManifest = 'apm-packages/codex-first-ai-development-process/apm.yml'
Assert-Contains $codexManifest 'design-pair-implementation-execution/\.apm/skills/design-pair-implementation-execution' 'Codex-first Design Pair skill dependency'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'sourceDesignPairSkill' 'Codex-first Design Pair skill bootstrap source'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'design-pair-implementation-execution' 'Codex-first Design Pair skill bootstrap target'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'Path\.Combine\(sourceDesignPairSkill, "map\.md"\)' 'Codex-first Design Pair map installer input'
Assert-Contains 'apm-packages/codex-first-ai-development-process/scripts/apply-codex-first-local.cs' 'Path\.Combine\(sourceDesignPairSkill, "handoff\.md"\)' 'Codex-first Design Pair handoff installer input'

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
Assert-Contains $codexRouter '(?s)first turn must present.*AWAITING_USER_INPUT / target-selection.*stop.*AWAITING_USER_INPUT / disposition-confirmation.*stop again' 'Codex-first mandatory Design Pair turn boundaries'
Assert-Contains $codexRouter 'design_pair_interaction_stage' 'Codex-first interaction stage state'

$fullCoverageSkill = 'apm-packages/token-aware-full-coverage-3layer/.apm/skills/token-aware-full-coverage-3layer/SKILL.md'
Assert-Contains $fullCoverageSkill 'resumeではParent Orchestration State.*必須' 'full-coverage resume route requirement'
Assert-Contains $fullCoverageSkill 'Adaptiveへ補完せずartifact mismatchとして停止' 'full-coverage resume fail-closed rule'
Assert-Contains $fullCoverageSkill '(?s)最初のturnはTarget Map全体を提示.*AWAITING_USER_INPUT / target-selection.*停止.*AWAITING_USER_INPUT / disposition-confirmation.*再停止' 'full-coverage mandatory Design Pair turn boundaries'
Assert-Contains $fullCoverageSkill 'design_pair_user_evidence' 'full-coverage user evidence propagation'

foreach ($id in 1..29) {
    $scenarioId = 'DP-VAL-{0:D3}' -f $id
    Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' $scenarioId "validation scenario $scenarioId"
}

Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'GitHub Copilot.*未検証' 'unverified Copilot support statement'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'adaptive-implementation-execution --target codex,agent-skills' 'fresh install Adaptive co-install command'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'install-adaptive-implementation-local\.cs.*--check' 'fresh install Adaptive profile check'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'package単体のinstallだけでは.*model mapping' 'incomplete single-package install warning'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'AWAITING_USER_INPUT / target-selection.*その turn を終了' 'README mandatory initial stop'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/usage-guide.md' 'AWAITING_USER_INPUT / disposition-confirmation.*再停止' 'usage guide multi-turn stop'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'without adding a stop instruction' 'manual smoke verifies skill-owned stop'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Human action required' 'manual smoke human participation boundary'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '(?s)Forward the human response verbatim.*must not ask a separate harness question.*If the human returns only a Target ID.*keep `AWAITING_USER_INPUT / target-selection`.*invented stage such as `design-discussion`.*`FAIL`' 'manual smoke verbatim partial-selection behavior'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '(?s)Before every initial or resumed turn.*git rev-parse --show-toplevel.*disposable repository.*codex exec resume.*no `-C` option' 'manual smoke execution root precondition'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '(?s)resumed process observes a different worktree.*mark the run `FAIL`.*neither repository was changed.*Do not move or copy the handoff' 'manual smoke wrong-worktree failure rule'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/result-template.md' '(?m)^- Status: NOT RUN\r?$' 'manual runtime result starts unexecuted'
foreach ($field in @('Configured model', 'Configured reasoning effort', 'Process repository revision', 'Plan reference', 'Turn sequence', 'Disposable repository root', 'Observed repository root', 'Tracked handoff path', 'Verdict sequence', 'No-Change Target IDs', 'Upstream-Decision-Required Target IDs', 'Target Map / summary set reconciliation evidence', 'Selected Target Discussion Evidence')) {
    Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/result-template.md' ([regex]::Escape($field)) "manual runtime evidence field $field"
}
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/fixture/plans/retry-after-plan.md' 'upstream user input for discussion, not a confirmed Design Pair Locked Decision' 'manual fixture pre-map proposal boundary'
Assert-Contains 'apm-packages/codex-first-ai-development-process/docs/team-profile-launcher.md' 'Adaptive skill and refs, and Design Pair skill and refs' 'documented one-off launcher payload'
Assert-Contains 'README.md' 'apm-packages/design-pair-implementation-execution' 'root Design Pair package link'

if ($failures.Count -gt 0) {
    Write-Error ("Design Pair Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Design Pair Implementation validation: PASS'
