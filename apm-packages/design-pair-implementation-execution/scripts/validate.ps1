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
    'apm-packages/design-pair-implementation-execution/scripts/validate.ps1'
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
Assert-Contains $skill '(?s)判断する問いを中心.*1ファイル＝1IDではなく.*独立に議論・判断・委任.*機械的な追随変更' 'decision-centered Target unit'
Assert-Contains $skill '(?s)何を決めるか／なぜ必要か.*調査済みの事実と制約.*実在する選択肢.*非 binding proposal.*No proposal.*未確認事項・検証期待.*因果関係.*具体的な file / symbol.*caller / wiring / lifecycle / state ownership / test seam' 'connected code-grounded decision materials'
Assert-Contains $skill '(?s)初回に全論点の詳細設計を新たに行うことではない.*未調査の仮説を確定事実や既存案とせず' 'bounded investigation without invented facts'
Assert-Contains $skill '(?s)資料へのリンク.*主要な判断上の違い・不明点.*直接進める.*資料が存在するだけ.*提示にならない.*参照できない場合' 'accessible initial presentation with meaningful entry summary'
Assert-NotContains $skill '全Target rowの全7列|固定blockを使用し、項目を省略しない|handoffの各Target rowをこの表へ同じ粒度で転記' 'mandatory duplicated explanations'
Assert-Contains $skill '(?s)初回 turn では次を禁止する.*READY_FOR_ADAPTIVE_IMPLEMENTATION.*adaptive-implementation-execution.*production code / tests.*Locked Decision' 'initial turn prohibitions'
Assert-Contains $skill '最初の依頼が「実装してください」であっても、この boundary を省略しない' 'implementation request cannot skip interaction boundary'
Assert-Contains $skill '(?s)resume では.*interaction stage.*Target Map.*presentation evidence.*Target Map 提示後の user response.*BLOCKED.*Adaptive へ fallback しない' 'resume waiting evidence fail-closed rule'
Assert-Contains $skill '(?s)user response は、test harness や parent が補足、言い換え、または必要項目を合成せず、そのまま.*対象が一意ならIDなし.*Target Map に実在する Target ID の選択だけでも受理.*同じ Target ID を再要求せず' 'verbatim direct and Target-only response handling'
Assert-Contains $skill '(?s)存在しないIDだけ.*選択未成立.*`target-selection` を維持' 'unknown Target cannot advance selection'
Assert-Contains $skill '(?s)提示済みの判断材料を再利用.*コード再読・全論点再調査を繰り返さない.*新案、情報不足、関連code / upstream条件の変更.*必要範囲.*旧版への確定を新版へ黙って適用しない' 'reuse and scoped evidence refresh'
Assert-Contains $skill '(?s)DP-T02は議論をスキップ.*残りはスキップ.*全部スキップ.*具体的ID.*実装省略や `No-Change` へ変換しない.*未指示のTargetはpending' 'explicit skip scope and semantics'
Assert-Contains $skill '(?s)`Selected Target Discussion Evidence`.*資料節・版・提示assistant turn.*実際のuser response.*初回資料.*code location.*invariant.*alternatives / trade-offs.*validation expectation.*全文転記.*要求しない' 'reference-based concrete discussion evidence'
Assert-Contains $skill '(?s)各turnは更新した論点.*差分更新.*summaryの5集合.*Readiness Check.*完了まで `Pending`.*全状態を毎回書き直したり.*確定済みartifact.*READYを解除' 'local updates and deferred finalization'
Assert-Contains $skill '(?s)## Output.*完了時のhandoff項目.*各turnの会話への全文出力や派生集合の再計算を要求しない' 'output does not reinstate per-turn global updates'
Assert-Contains $skill '(?s)会話の要約をAI提案だけにしない.*何を決めるか、案の違い、残る不明点' 'initial summary has real decision entry'
Assert-Contains $skill '(?s)全Targetへの個別の明示委任が揃った場合.*Explicit all-Adaptive delegation: Yes.*単にSelectedが空.*Yesにしてはいけない' 'individual skips require complete explicit evidence'
Assert-Contains $skill '(?s)初回資料を含む提示済みの判断材料.*A案で確定.*選択→同じ説明→再確認を挟まず受理' 'direct post-material explicit confirmation'
Assert-Contains $skill '(?s)Target Map 提示後の通常 interaction stage は `target-selection`、`disposition-confirmation`、`upstream-decision`、`complete` のいずれかだけ.*`target-map-building` は提示前の `DRAFT`.*`artifact-repair` は.*`BLOCKED`' 'closed Design Pair interaction stage vocabulary'
Assert-Contains $skill '(?s)AWAITING_USER_INPUT.*interaction_stage: disposition-confirmation' 'disposition confirmation waiting state'
Assert-Contains $skill '全 Target を Adaptive へ委ねると明示した場合.*Locked Decision を作らず READY' 'explicit all-Adaptive delegation path'
Assert-Contains $skill 'Target 未選択を空集合として PASS にしない' 'empty selection readiness prevention'
Assert-Contains $skill '(?s)user message / turn reference.*Target ID.*忠実な要約.*confirmation occurred after Target Map presentation: Yes' 'post-map confirmation evidence requirements'
Assert-Contains $skill '(?s)`Locked`、`Discussed-Unlocked`、`Adaptive-Owned`.*Targetごとに `Target Disposition Evidence` を一件.*Target ID.*final disposition.*実際の user message / turn reference.*忠実な要約.*`Confirmation after Target Map: Yes`' 'Target-level disposition evidence requirements'
Assert-Contains $skill '(?s)利用者が委任していないTargetをAIが`Adaptive-Owned`.*利用者の最終応答なしに`Discussed-Unlocked`.*禁止' 'AI cannot self-assign final human disposition'
Assert-Contains $skill 'upstream Plan、Issue、acceptance criteria、gold document、repository policy / public contract.*Upstream Binding Constraints' 'upstream constraint separation'
Assert-Contains $skill 'Target Map と code evidence の提示前に Locked Decision へ昇格しない' 'initial position is not automatic Locked Decision'
Assert-Contains $skill 'READY 判定前に、正本rowと証拠からsummary fieldとReadiness Checkをまとめて生成' 'final checks derived from canonical evidence'
Assert-Contains $skill '(?s)READY 判定前に.*Target Map の全 Target ID は一意.*concrete ID はすべて Target Map に実在.*5集合は互いに素.*和集合は Target Map の全 Target ID と完全一致' 'Target Map and summary set reconciliation'
Assert-Contains $skill '(?s)全条件を満たし.*同じ現行証拠へ同期.*Finalization status: Validated.*READY_FOR_ADAPTIVE_IMPLEMENTATION.*失敗時はREADYにせず' 'finalization fail-closed gate'
Assert-Contains $skill '(?s)初回資料の作成から最終dispositionまで.*全行程.*重複した調査・記録更新.*input / output / reasoning / cached tokens.*二重計上しない.*実測なしに削減効果を断定しない' 'whole-interaction cost comparison'
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
Assert-Contains $map 'Target ID.*Decision question / why now.*Main trade-off / unknown.*Decision materials.*Disposition' 'question-centered Target index'
Assert-Contains $map '(?s)Material version.*Evidence revision.*Presented at.*判断する問いと必要性.*事実・制約と選択肢.*File / Symbol.*Current responsibility / invariant.*Trade-off and impact on the decision.*Non-binding AI proposal.*Open questions.*Validation expectations.*対話差分' 'versioned evidence-backed material schema'
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
Assert-Contains $handoff '(?s)## Target Disposition Evidence.*Target ID.*Final disposition.*User message / turn reference.*Confirmed content quote or faithful summary.*Confirmation after Target Map' 'Target disposition evidence schema'
Assert-Contains $handoff '(?s)## Selected Target Discussion Evidence.*Material section / version.*Presentation assistant turn.*Actual post-map user turn.*Discussion delta references.*具体的code location.*current invariant.*alternatives / trade-offs.*validation expectation' 'material and actual response evidence schema'
Assert-Contains $handoff '(?s)## Readiness Check.*Finalization status: Pending.*正本.*完了直前.*現行証拠.*PendingをPASSとして受理しない' 'deferred check lifecycle'
foreach ($check in @(
    'Target Map IDs are unique and every summary ID exists in the Target Map',
    'Summary Target sets are pairwise disjoint and exactly cover the Target Map',
    'Summary classifications match every Target Map row Disposition',
    'Every Locked, Discussed-Unlocked, and Adaptive-Owned Target has matching post-map Target Disposition Evidence',
    'Locked Decisions do not conflict with upstream contracts',
    'No pending human-owned Target remains'
)) {
    Assert-Contains $handoff ([regex]::Escape($check)) "final safety check $check"
}
Assert-Contains $handoff '(?s)all-Adaptiveでも全Targetのevidence row.*5集合.*架空 ID、重複 ID、未分類 Target、row / summary 不一致.*許可しない' 'strict final reconciliation'

foreach ($id in 1..40) {
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
$smokeGuide = 'apm-packages/design-pair-implementation-execution/tests/manual-model-smoke/README.md'
Assert-Contains $smokeGuide '(?s)Forward the human response verbatim.*Target-only selection must be accepted without repeating the same selection or requiring an initial position.*AWAITING_USER_INPUT / disposition-confirmation.*FAIL' 'manual smoke verbatim Target-only selection behavior'
Assert-Contains $smokeGuide '(?s)初回資料.*因果的.*具体的file / symbol.*資料の全文再掲は不要.*ID選択を必須にせず' 'manual smoke accessible initial decision materials'
Assert-Contains $smokeGuide '(?s)Direct question / confirmation.*Partial / remaining / all skip.*New option / changed code.*Deferred finalization / invalid READY' 'manual smoke direct interaction and safety cases'
Assert-Contains $smokeGuide '(?s)同条件の全行程比較.*初回資料生成から最終dispositionまで.*input / output / reasoning / cached tokens.*二重計上しない.*scripted PASSでhuman-operated smokeを代替しない' 'manual smoke bounded honest cost comparison'
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
$dpApmSmoke = 'apm-packages/design-pair-implementation-execution/scripts/validate-dp-apm-smoke.ps1'
Assert-FileExists $dpApmSmoke
Assert-Contains $dpApmSmoke 'APM 0\.26\.0 is required' 'Design Pair APM smoke pins APM 0.26.0'
Assert-Contains $dpApmSmoke 'copilot,codex,agent-skills' 'Design Pair APM smoke installs all targets'
Assert-Contains $dpApmSmoke '\.agents/skills/design-pair-implementation-execution/SKILL\.md' 'Design Pair APM smoke verifies Design Pair Skill deployment'
Assert-Contains $dpApmSmoke 'deployed Design Pair skill name' 'Design Pair APM smoke verifies deployed skill identity'
Assert-Contains $dpApmSmoke 'Get-ManifestVersion.*apm\.yml' 'Design Pair APM smoke derives lock versions from manifests'

$evidenceRoot = Join-Path $packageRoot 'tests/manual-model-smoke/results/i159'
$evidenceIndex = Get-Content -Raw -LiteralPath (Join-Path $evidenceRoot 'index.json') | ConvertFrom-Json
$indexedFiles = @($evidenceIndex.artifacts.file | Sort-Object)
$actualFiles = @(Get-ChildItem -LiteralPath $evidenceRoot -File -Force |
    Where-Object Name -ne 'index.json' | Sort-Object Name | ForEach-Object Name)
if (($indexedFiles -join '|') -cne ($actualFiles -join '|')) {
    Add-Failure 'Issue 159 evidence index must cover every artifact exactly once'
}
foreach ($artifact in $evidenceIndex.artifacts) {
    $path = Join-Path $evidenceRoot $artifact.file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing Issue 159 evidence artifact: $($artifact.file)"
    }
    elseif ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -cne $artifact.sha256) {
        Add-Failure "Issue 159 evidence SHA-256 mismatch: $($artifact.file)"
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Design Pair Implementation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}
Write-Output 'Design Pair Implementation validation: PASS'
