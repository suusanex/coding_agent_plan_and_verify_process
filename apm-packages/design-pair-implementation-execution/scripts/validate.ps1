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
    'apm-packages/adaptive-implementation-execution/.apm/agents/decision-surface-implementation-owner.agent.md',
    'apm-packages/adaptive-implementation-execution/.apm/agents/bounded-residual-implementation-owner.agent.md',
    'apm-packages/plan-coverage-residual-flow/.apm/agents/implementation-handoff-review.agent.md',
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
    'apm-packages/adaptive-implementation-execution/docs/examples/copilot-cli-real-model-e2e-2026-08-30.md',
    'apm-packages/adaptive-implementation-execution/docs/install-guide.md',
    'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json',
    'apm-packages/codex-profile-finalizer/apm.yml',
    'apm-packages/codex-profile-finalizer/.apm/.gitkeep',
    'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs',
    'apm-packages/codex-profile-finalizer/tests/validate-finalizer.ps1',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/plan-coverage-lite.md',
    'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md',
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
Assert-Contains $manifest '(?m)^version:\s*0\.4\.0\s*$' 'package version 0.4.0'
Assert-Contains $manifest '(?m)^\s*-\s+copilot\s*$' 'copilot target'
Assert-Contains $manifest '(?m)^\s*-\s+codex\s*$' 'codex target'
Assert-Contains $manifest '(?m)^\s*-\s+agent-skills\s*$' 'agent-skills target'
Assert-NotContains $manifest '(?m)^\s*-\s+github-copilot\s*$' 'invalid github-copilot target alias'
Assert-NotContains $manifest '(?m)^\s*-\s+vscode\s*$' 'invalid bare vscode target alias'
Assert-Contains $manifest 'path:\s*apm-packages/adaptive-implementation-execution\s*$' 'Adaptive package boundary dependency'
Assert-NotContains $manifest '\.github/agents/' 'no root .github/agents dependency'
Assert-NotContains $manifest 'implementation-execution\.agent\.md' 'legacy implementation orchestration dependency'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/apm.yml' '(?m)^version:\s*0\.15\.0\s*$' 'Plan Coverage package version 0.15.0'
Assert-Contains 'apm-packages/adaptive-implementation-execution/apm.yml' '(?m)^version:\s*0\.6\.0\s*$' 'Adaptive package version 0.6.0'
Assert-Contains 'apm-packages/adaptive-implementation-execution/apm.yml' '(?m)^\s*-\s+copilot\s*$' 'Adaptive package copilot target parity'

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
Assert-Contains $skill '初期案、問題の捉え方、質問、検討したい技術や構造は任意' 'optional human initial position'
Assert-Contains $skill 'AI の推奨案を最初から確定案として提示してはいけない' 'non-leading discussion rule'
Assert-Contains $skill '(?s)## Phase 3: Present the Target Map and stop.*AWAITING_USER_INPUT.*interaction_stage: target-selection.*その turn を終了する' 'mandatory initial post-map turn stop'
Assert-Contains $skill '(?s)handoff artifactへのlinkまたはTarget IDと論点名の要約だけではTarget Map提示と認めない.*各TargetのTarget ID、具体的file / symbol、current responsibility / invariant、requested changeとの関係、内部設計判断候補、expected modification or verification、relevant evidence、open question' 'concrete user-facing initial Target Map'
Assert-Contains $skill '(?s)初回のuser-facing responseは次のMarkdown構造を省略せず使用する.*## Design Pair Target Map.*Target ID.*File / Symbol.*Current responsibility / invariant.*Relation to change / internal decision.*Expected modification or verification.*Relevant evidence.*Open question.*### Coverage evidence.*Production symbol and direct callers.*Tests / fixtures / test seam.*DI / factory / startup / production wiring.*Lifecycle / cancellation / state ownership.*### Selection request' 'required initial Target Map response schema'
Assert-Contains $skill '(?s)turn終了前にuser-facing responseをself-check.*全Target rowの全7列とCoverage evidence.*handoff artifact内だけに詳細.*短い箇条書きへ圧縮.*PASSにせず、応答を修復' 'initial response content self-check'
Assert-Contains $skill '(?s)初回 turn では次を禁止する.*READY_FOR_ADAPTIVE_IMPLEMENTATION.*adaptive-implementation-execution.*production code / tests.*Locked Decision' 'initial turn prohibitions'
Assert-Contains $skill '最初の依頼が「実装してください」であっても、この boundary を省略しない' 'implementation request cannot skip interaction boundary'
Assert-Contains $skill '(?s)resume では.*interaction stage.*Target Map.*presentation evidence.*Target Map 提示後の user response.*BLOCKED.*Adaptive へ fallback しない' 'resume waiting evidence fail-closed rule'
Assert-Contains $skill '(?s)user response は、test harness や parent が補足、言い換え、または必要項目を合成せず、そのまま.*Target Map に実在する Target ID の選択だけでも.*初期案、懸念、質問は任意.*同じ Target ID を再要求せず.*`AWAITING_USER_INPUT / disposition-confirmation`' 'verbatim Target-only selection handling'
Assert-Contains $skill '(?s)Target Map に存在しない ID だけ.*選択未成立.*`target-selection` を維持' 'unknown Target cannot advance selection'
Assert-Contains $skill '(?s)選択された Target の対話では.*handoff artifactへのlinkまたは論点名だけを返してはいけない.*Target ID と具体的な file / symbol.*現在の責務と invariant.*直接 caller、production wiring、lifecycle / state ownership、test seam.*実在する代替案.*trade-off.*非 binding の AI proposal.*`No proposal`.*validation expectation' 'selected Target minimum discussion surface'
Assert-Contains $skill '(?s)Target IDだけの選択でも.*minimum discussion surfaceを提示.*初期案がないことを理由に同じ Target の選択を再要求しない.*Target Map内に詳細があることをuser-facing説明の代替にせず.*`Selected Target Discussion Evidence`' 'Target-only selection concrete discussion evidence'
Assert-Contains $skill '(?s)選択Targetのuser-facing responseは.*## <DP-Txx> Internal design discussion.*Code location.*Current responsibility / invariant.*Callers / wiring / lifecycle / state / test seam.*Internal design decision needed.*Alternatives and trade-offs.*Non-binding AI proposal.*Validation expectations.*Open questions' 'required selected Target discussion response schema'
Assert-Contains $skill '(?s)各 response.*handoff header、Target Map row、summary Target sets、Readiness Check.*同じ observed evidence から再計算.*User response occurred after Target Map presentation: Yes.*同名 row.*`PASS`' 'mirrored user evidence synchronization'
Assert-Contains $skill '(?s)Target Map 提示後の通常 interaction stage は `target-selection`、`disposition-confirmation`、`upstream-decision`、`complete` のいずれかだけ.*`target-map-building` は提示前の `DRAFT`.*`artifact-repair` は.*`BLOCKED`' 'closed Design Pair interaction stage vocabulary'
Assert-Contains $skill '(?s)AWAITING_USER_INPUT.*interaction_stage: disposition-confirmation' 'disposition confirmation waiting state'
Assert-Contains $skill '全 Target を Adaptive へ委ねると明示した場合.*Locked Decision を作らず READY' 'explicit all-Adaptive delegation path'
Assert-Contains $skill 'Target 未選択を空集合として PASS にしない' 'empty selection readiness prevention'
Assert-Contains $skill '(?s)user message / turn reference.*Target ID.*忠実な要約.*confirmation occurred after Target Map presentation: Yes' 'post-map confirmation evidence requirements'
Assert-Contains $skill '(?s)`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`.*Targetごとに `Target Disposition Evidence` を一件.*Target ID.*final disposition.*実際の user message / turn reference.*忠実な要約.*`Confirmation after Target Map: Yes`' 'Target-level disposition evidence requirements'
Assert-Contains $skill '(?s)利用者が委任していないTargetをAIが`Adaptive-Owned`.*利用者の最終応答なしに`Discussed-Unlocked`.*禁止' 'AI cannot self-assign final human disposition'
Assert-Contains $skill 'upstream Plan、Issue、acceptance criteria、gold document、repository policy / public contract.*Upstream Binding Constraints' 'upstream constraint separation'
Assert-Contains $skill 'Target Map と code evidence の提示前に Locked Decision へ昇格しない' 'initial position is not automatic Locked Decision'
Assert-Contains $skill '(?s)READY 判定前に、Target Map と summary field を集合として照合.*Target Map の全 Target ID は一意.*concrete ID はすべて Target Map に実在.*5集合は互いに素.*和集合は Target Map の全 Target ID と完全一致' 'Target Map and summary set reconciliation'
Assert-Contains $skill '(?s)`Selected Target IDs`: disposition が `Locked` または `Discussed-Unlocked`.*`Delegated-to-Adaptive Target IDs`: disposition が `Adaptive-Owned`.*`No-Change Target IDs`: disposition が `No-Change`.*`Upstream-Decision-Required Target IDs`: disposition が `Upstream-Decision-Required`.*`Pending human-owned Target IDs`: disposition が `Pending-User-Selection` または `Pending-User-Disposition`' 'summary set to row disposition mapping'
Assert-Contains $skill '(?s)各 Locked Decision の Target ID は `Selected Target IDs` に含まれ.*Target Map row は `Locked`.*`Locked` row には一件以上の valid Locked Decision' 'Locked Decision target membership invariant'
Assert-Contains $skill '(?s)`Explicit all-Adaptive delegation: Yes`.*`Selected Target IDs: None`.*`Pending human-owned Target IDs: None`.*Locked Decisionsなし.*全 Target row が `Adaptive-Owned`.*`Delegated-to-Adaptive Target IDs` が全 Target IDと完全一致' 'all-Adaptive exact coverage invariant'
Assert-Contains $skill '(?s)READY判定では`Target Disposition Evidence`も集合照合.*`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`のTarget全集合.*完全一致.*各Targetが一回だけ.*actual user turn.*all-Adaptiveでも全Targetに一件ずつ' 'Target disposition evidence reconciliation'
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
    'Target Disposition Evidence',
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
Assert-Contains $handoff '(?s)## Target Disposition Evidence.*Target ID.*Final disposition.*User message / turn reference.*Confirmed content quote or faithful summary.*Confirmation after Target Map' 'Target disposition evidence schema…7603 tokens truncated…ow/.apm/agents/implementation-handoff-review.agent.md' '新規 intake.*だけ `adaptive / default` を初期化' 'handoff review fresh-intake-only default'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/.apm/agents/implementation-handoff-review.agent.md' 'design_pair_interaction_stage' 'handoff review interaction stage propagation'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/.apm/agents/implementation-handoff-review.agent.md' 'waiting中はAdaptiveやverificationを次stepにしない' 'handoff review waiting downstream block'

foreach ($id in 1..31) {
    $scenarioId = 'DP-VAL-{0:D3}' -f $id
    Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' $scenarioId "validation scenario $scenarioId"
}

Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' '正式 target は `copilot`、`codex`、`agent-skills`' 'formal Copilot target support statement'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'adaptive-implementation-execution --target copilot,agent-skills' 'fresh install Adaptive Copilot co-install command'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'design-pair-implementation-execution --target copilot,agent-skills' 'fresh install Design Pair Copilot co-install command'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'adaptive-implementation-execution --target codex,agent-skills' 'fresh install Adaptive Codex co-install command'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'finalize-codex-agent-profiles\.cs' 'fresh install Adaptive profile finalizer'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'package単体のinstallだけでは.*model mapping' 'incomplete single-package install warning'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'AWAITING_USER_INPUT / target-selection.*その turn を終了' 'README mandatory initial stop'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' '--agent decision-surface-implementation-owner' 'README Copilot Adaptive agent entry after READY'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' '新しい CLI 起動で' 'README requires new CLI process for Adaptive agent'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' 'Issue #69 / #86 境界' 'README documents #69/#86 boundary'
Assert-Contains 'apm-packages/design-pair-implementation-execution/README.md' '正式 acceptance は GitHub Copilot CLI' 'README CLI acceptance surface'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/usage-guide.md' 'AWAITING_USER_INPUT / disposition-confirmation.*再停止' 'usage guide multi-turn stop'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/usage-guide.md' '正式 target は `copilot`、`codex`、`agent-skills`' 'usage guide formal Copilot target'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' '(?s)DP-VAL-008: Copilot support boundary.*formal target 名 `copilot`.*GitHub Copilot CLI.*real multi-turn evidence' 'DP-VAL-008 Copilot formal support'
Assert-Contains 'apm-packages/adaptive-implementation-execution/apm.yml' '(?m)^\s*-\s+copilot\s*$' 'Adaptive install guide copilot target parity'
Assert-Contains 'apm-packages/adaptive-implementation-execution/docs/usage-guide.md' '(?s)Design Pair:.*implementation_route:\s*design-pair.*design_pair_handoff:\s*plans/<slug>-design-pair-implementation-handoff\.md' 'Adaptive usage guide documents Design Pair route handoff path'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'The `design-pair-implementation-execution` package remains a separate package' 'Plan Coverage target-neutral Design Pair package boundary'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'both packages are installed for the same target and the user explicitly selects Design Pair' 'Plan Coverage same-target explicit Design Pair selection boundary'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'keep `plan-coverage-residual-flow` selection evidence separate from Design Pair implementation route selection evidence' 'Plan Coverage and Design Pair selection evidence separation'
Assert-Contains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'While Design Pair is waiting, do not fall back to Adaptive' 'Plan Coverage Design Pair waiting fallback boundary'
Assert-NotContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'Plan Coverage parent runtime qualif(?:ication).*Design Pair.*Adaptive.*GitHub Copilot CLI' 'removed Plan Coverage Copilot qualification claim'
Assert-NotContains 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md' 'Plan Coverage Copilot CLI\s+issue' 'removed Plan Coverage Copilot qualification issue handoff'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'without adding a stop instruction' 'manual smoke verifies skill-owned stop'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Human action required' 'manual smoke human participation boundary'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'GitHub Copilot CLI' 'manual smoke Copilot CLI surface'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '--agent decision-surface-implementation-owner' 'manual smoke Copilot Adaptive agent selection'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'new CLI process' 'manual smoke requires new process Adaptive entry'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Waiting-state new-session resume' 'manual smoke waiting new-session resume scenario'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Explicit all-Adaptive' 'manual smoke all-Adaptive scenario'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Locked Decision conflict' 'manual smoke Locked conflict scenario'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Issue #86' 'manual smoke defers Plan Coverage E2E to #86'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'tracked handoff remains the durable authority' 'manual smoke Copilot durable resume authority'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'Commit sanitized raw CLI outputs' 'manual smoke requires committed raw evidence'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '(?s)Forward the human response verbatim.*must not ask a separate harness question.*Target-only selection must be accepted.*without repeating the same selection or requiring an initial position.*move to `AWAITING_USER_INPUT / disposition-confirmation`.*return to `target-selection` for a valid Target ID.*`FAIL`' 'manual smoke verbatim Target-only selection behavior'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' "every Target's concrete file and symbol, current responsibility and invariant, relation to the change, expected modification or verification, relevant evidence, and open question" 'manual smoke concrete initial Target Map evidence'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'required seven-column `Design Pair Target Map`, Coverage evidence, and Selection request structure' 'manual smoke initial response structure'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' 'required `<DP-Txx> Internal design discussion` block' 'manual smoke selected Target response structure'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '(?s)Before every initial or resumed turn.*git rev-parse --show-toplevel.*disposable repository.*codex exec resume.*no `-C` option' 'manual smoke execution root precondition'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md' '(?s)resumed process observes a different worktree.*mark the run `FAIL`.*neither repository was changed.*Do not move or copy the handoff' 'manual smoke wrong-worktree failure rule'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/result-template.md' '(?m)^- Status: NOT RUN\r?$' 'manual runtime result starts unexecuted'
foreach ($field in @('Configured model', 'Configured reasoning effort', 'Process repository revision', 'Design Pair package version', 'Adaptive package version', 'Plan reference', 'Turn sequence', 'Disposable repository root', 'Observed repository root', 'Tracked handoff path', 'Verdict sequence', 'No-Change Target IDs', 'Upstream-Decision-Required Target IDs', 'Target Map / summary set reconciliation evidence', 'Selected Target Discussion Evidence', 'Target Disposition Evidence', 'CLI version', 'Execution surface', 'Agent selection flags', 'Unsupported capability notes', 'New CLI session resume used tracked handoff as authority', 'Ordinary Plan route exercised')) {
    Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/result-template.md' ([regex]::Escape($field)) "manual runtime evidence field $field"
}
$historicalRuntimeResult = 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/results/20260731-333c8e1.md'
Assert-FileExists $historicalRuntimeResult
Assert-Contains $historicalRuntimeResult '(?m)^- Status: PASS\r?$' 'historical real-model smoke PASS record'
Assert-Contains $historicalRuntimeResult 'Process repository revision: `333c8e10fb86843e296091457820ff492779ee71`' 'historical process revision evidence'
Assert-Contains $historicalRuntimeResult '(?s)Configured model: `gpt-5\.6-terra`.*Configured reasoning effort: `medium`' 'historical model and reasoning evidence'
Assert-Contains $historicalRuntimeResult '(?s)AWAITING_USER_INPUT / target-selection.*AWAITING_USER_INPUT / disposition-confirmation.*READY_FOR_ADAPTIVE_IMPLEMENTATION / complete.*COMPLETED_BY_HIGH_MODEL' 'historical verdict sequence'
Assert-Contains $historicalRuntimeResult '(?s)Selected Target IDs: `DP-T01`.*Delegated-to-Adaptive Target IDs: `DP-T02, DP-T03`.*Pending human-owned Target IDs: `None`.*Locked Decision IDs: `DP-D01`' 'historical reconciled Target sets and Locked Decision'
Assert-Contains $historicalRuntimeResult '(?s)Target-only selection advanced to disposition-confirmation.*PASS.*Ambiguous unselected-Target delegation remained fail-closed: PASS.*Adaptive started only after READY: PASS' 'historical interaction and Adaptive timing evidence'
$historicalRebasedRuntimeResult = 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/results/20260731-4b50aad.md'
Assert-FileExists $historicalRebasedRuntimeResult
Assert-Contains $historicalRebasedRuntimeResult '(?m)^- Status: PASS\r?$' 'historical rebased real-model smoke PASS'
Assert-Contains $historicalRebasedRuntimeResult 'Process repository revision: `4b50aad41476a14efdf8d75c8d36ad9b491e6e55`' 'historical rebased process revision evidence'
Assert-Contains $historicalRebasedRuntimeResult '(?s)Design Pair package version: `0\.2\.0`.*Adaptive package version: `0\.4\.0`.*Configured model: `gpt-5\.6-terra`.*Configured reasoning effort: `medium`' 'historical rebased package, model, and reasoning evidence'
Assert-Contains $historicalRebasedRuntimeResult '(?s)AWAITING_USER_INPUT / target-selection.*AWAITING_USER_INPUT / disposition-confirmation.*ambiguous DP-T02/DP-T03 delegation rejected.*READY_FOR_ADAPTIVE_IMPLEMENTATION / complete.*COMPLETED_BY_HIGH_MODEL' 'historical rebased verdict sequence'
Assert-Contains $historicalRebasedRuntimeResult '(?s)DP-T01 / `Locked` / user turn 3.*DP-T02 / `Adaptive-Owned` / user turn 4.*DP-T03 / `Adaptive-Owned` / user turn 4' 'historical rebased Target disposition evidence'
Assert-Contains $historicalRebasedRuntimeResult '(?s)Every Locked / Discussed-Unlocked / Adaptive-Owned Target has matching post-map disposition evidence: PASS.*Explicit multi-Target delegation has one disposition evidence row per Target: PASS.*Adaptive started only after READY: PASS' 'historical rebased disposition and Adaptive timing validation'
Assert-Contains 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/fixture/plans/retry-after-plan.md' 'upstream user input for discussion, not a confirmed Design Pair Locked Decision' 'manual fixture pre-map proposal boundary'
Assert-Contains 'apm-packages/design-pair-implementation-execution/docs/examples/design-pair-validation.md' '(?s)DP-VAL-032.*Undelegated Target cannot become Adaptive-Owned.*DP-VAL-033.*Discussed-Unlocked requires final user disposition.*DP-VAL-034.*Explicit multi-Target delegation.*DP-VAL-035.*Explicit all-Adaptive delegation has complete evidence' 'Target disposition evidence validation scenarios'
$historicalCopilotRuntimeResult = 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/results/20260805-copilot-issue69.md'
Assert-FileExists $historicalCopilotRuntimeResult
Assert-Contains $historicalCopilotRuntimeResult '(?m)^- Status: PASS\r?$' 'historical Copilot CLI real-model smoke PASS'
Assert-Contains $historicalCopilotRuntimeResult 'Execution surface: GitHub Copilot CLI' 'historical Copilot CLI execution surface evidence'
Assert-Contains $historicalCopilotRuntimeResult 'CLI version: `1\.0\.78`' 'historical Copilot CLI version evidence'
Assert-Contains $historicalCopilotRuntimeResult '(?s)Design Pair package version: `0\.3\.0`.*Adaptive package version: `0\.4\.0`' 'historical Copilot package version evidence'
Assert-Contains $historicalCopilotRuntimeResult 'deferred to Issue #86' 'historical Copilot record defers Plan Coverage E2E to #86'
Assert-Contains $historicalCopilotRuntimeResult '(?s)AWAITING_USER_INPUT / target-selection.*AWAITING_USER_INPUT / disposition-confirmation.*READY_FOR_ADAPTIVE_IMPLEMENTATION / complete.*NEW process: copilot --agent high-implementation-starter.*COMPLETED_BY_HIGH_MODEL' 'historical Copilot Adaptive route'
Assert-Contains $historicalCopilotRuntimeResult 'Canonical Adaptive entry used `--agent high-implementation-starter` in a new CLI process: PASS' 'historical Copilot explicit Adaptive agent path PASS'
Assert-Contains $historicalCopilotRuntimeResult 'High Implementation Starter' 'historical Copilot observed agent identity'
Assert-Contains $historicalCopilotRuntimeResult 'gpt-5\.6-terra' 'historical Copilot observed model identity'
Assert-Contains $historicalCopilotRuntimeResult 'New CLI session resume \*\*while waiting\*\* used tracked handoff as authority: PASS' 'historical Copilot waiting-state resume PASS'
Assert-Contains $historicalCopilotRuntimeResult 'Explicit all-Adaptive delegation: PASS' 'historical Copilot all-Adaptive PASS'
Assert-Contains $historicalCopilotRuntimeResult 'Design Pair not selected keeps Adaptive default: PASS' 'historical Copilot no-Design-Pair route'
Assert-Contains $historicalCopilotRuntimeResult 'Locked Decision conflict stop without silent change: PASS' 'historical Copilot Locked conflict stop'
Assert-Contains $historicalCopilotRuntimeResult 'Ordinary Plan route exercised: PASS' 'historical Copilot ordinary Plan evidence'
Assert-Contains $historicalCopilotRuntimeResult 'Upstream proposal not converted to Locked Decision: PASS' 'historical Copilot upstream proposal boundary'
Assert-Contains $historicalCopilotRuntimeResult 'Ambiguous unselected-Target delegation remained fail-closed: PASS' 'historical Copilot ambiguous delegation fail-closed'
Assert-Contains $historicalCopilotRuntimeResult 'Raw evidence artifacts committed with SHA-256 index: PASS' 'historical Copilot raw evidence'
Assert-NotContains $historicalCopilotRuntimeResult 'codex-first-ai-development-process|copilot-fallback-ai-development-process' 'historical Copilot smoke excludes removed aggregate processes'
$copilotEvidenceDir = 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/results/c69'
foreach ($artifact in @('INDEX.md', 'aa.txt', 'w1.txt', 'w2.txt', 'all1.txt', 'all2.txt', 'nodp.txt', 'conf.txt', 'h-ready.md', 'h-wait.md', 'h-all.md', 'h-conf.md', 'd-aa.patch', 'd-conf.patch')) {
    Assert-FileExists "$copilotEvidenceDir/$artifact"
}
Assert-Contains "$copilotEvidenceDir/INDEX.md" 'aa\.txt' 'Copilot evidence index lists adaptive-with-agent log'
Assert-Contains "$copilotEvidenceDir/aa.txt" 'High Implementation Starter' 'adaptive-with-agent log has HIGH agent identity'
Assert-Contains "$copilotEvidenceDir/aa.txt" 'gpt-5\.6-terra' 'adaptive-with-agent log has Terra model identity'
Assert-Contains "$copilotEvidenceDir/aa.txt" 'COMPLETED_BY_HIGH_MODEL' 'adaptive-with-agent log has completion verdict'
Assert-Contains "$copilotEvidenceDir/w2.txt" 'disposition-confirmation' 'waiting new-session log reached disposition-confirmation'
Assert-Contains "$copilotEvidenceDir/h-all.md" 'Explicit all-Adaptive delegation: Yes' 'all-Adaptive handoff snapshot'
Assert-Contains "$copilotEvidenceDir/nodp.txt" 'implementation_route' 'no-Design-Pair log reports route field'
Assert-Contains "$copilotEvidenceDir/nodp.txt" '`adaptive`' 'no-Design-Pair adaptive route value'
Assert-Contains "$copilotEvidenceDir/nodp.txt" '`default`' 'no-Design-Pair default route source'
Assert-Contains "$copilotEvidenceDir/nodp.txt" 'Design Pair started:\*\* No' 'no-Design-Pair did not start Design Pair'
Assert-Contains "$copilotEvidenceDir/conf.txt" 'HUMAN_DECISION_REQUIRED' 'conflict log stop verdict'
Assert-Contains "$copilotEvidenceDir/conf.txt" 'DP-D01' 'conflict log Locked Decision id'
Assert-Contains 'README.md' 'apm-packages/design-pair-implementation-execution' 'root Design Pair package link'

$dpApmSmoke = 'apm-packages/design-pair-implementation-execution/scripts/validate-dp-apm-smoke.ps1'
Assert-FileExists $dpApmSmoke
Assert-Contains $dpApmSmoke 'APM 0\.26\.0 is required' 'Design Pair APM smoke pins APM 0.26.0'
Assert-Contains $dpApmSmoke 'copilot,codex,agent-skills' 'Design Pair APM smoke installs all targets'
Assert-Contains $dpApmSmoke '\.agents/skills/design-pair-implementation-execution/SKILL\.md' 'Design Pair APM smoke verifies Design Pair Skill deployment'
Assert-Contains $dpApmSmoke 'deployed Design Pair skill name' 'Design Pair APM smoke verifies deployed skill identity'
Assert-Contains $dpApmSmoke '\.agents/skills/adaptive-implementation-execution/SKILL\.md' 'Design Pair APM smoke verifies transitive Adaptive Skill'
Assert-Contains $dpApmSmoke '\.github/agents/decision-surface-implementation-owner\.agent\.md' 'Design Pair APM smoke verifies transitive Decision-Surface Implementation Owner agent'
Assert-Contains $dpApmSmoke '\.github/agents/bounded-residual-implementation-owner\.agent\.md' 'Design Pair APM smoke verifies transitive Bounded-Residual Implementation Owner agent'
Assert-Contains $dpApmSmoke 'finalize-codex-agent-profiles\.cs' 'Design Pair APM smoke verifies installed profile finalizer'
Assert-Contains $dpApmSmoke 'design-pair-implementation-execution.*0\.4\.0' 'Design Pair APM smoke verifies lock version'
Assert-Contains $dpApmSmoke 'adaptive-implementation-execution.*0\.6\.0' 'Design Pair APM smoke verifies transitive Adaptive lock version'

$dpWorkflow = '.github/workflows/validate-design-pair-implementation-execution.yml'
Assert-Contains $dpWorkflow 'validate-dp-apm-smoke\.ps1' 'Design Pair workflow runs remote APM install smoke'
Assert-Contains $dpWorkflow 'microsoft/apm-action@v1' 'Design Pair workflow sets up APM'
Assert-Contains $dpWorkflow "apm-version:\s*'0\.26\.0'" 'Design Pair workflow pins APM 0.26.0'

$adaptiveHighAgent = 'apm-packages/adaptive-implementation-execution/.apm/agents/decision-surface-implementation-owner.agent.md'
$adaptiveStandardAgent = 'apm-packages/adaptive-implementation-execution/.apm/agents/bounded-residual-implementation-owner.agent.md'
Assert-Contains $adaptiveHighAgent '(?m)^name:\s*decision-surface-implementation-owner\s*$' 'portable Decision-Surface Implementation Owner agent identity'
Assert-Contains $adaptiveHighAgent '(?m)^description:' 'portable Decision-Surface Implementation Owner description'
Assert-Contains $adaptiveStandardAgent '(?m)^name:\s*bounded-residual-implementation-owner\s*$' 'portable Bounded-Residual Implementation Owner agent identity'
Assert-Contains $adaptiveStandardAgent '(?m)^description:' 'portable Bounded-Residual Implementation Owner description'
Assert-Contains 'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json' 'decision-surface-implementation-owner' 'Adaptive Decision-Surface Implementation Owner profile overlay'
Assert-Contains 'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json' 'bounded-residual-implementation-owner' 'Adaptive Bounded-Residual Implementation Owner profile overlay'

if ($failures.Count -gt 0) {
    Write-Error ("Design Pair Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}
Write-Output 'Design Pair Implementation validation: PASS'
