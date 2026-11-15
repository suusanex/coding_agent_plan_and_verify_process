[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$packageRoot = Join-Path $repoRoot 'apm-packages/pr-review-remediation'
$scratchRoot = Join-Path ([IO.Path]::GetTempPath()) ('pr-review-remediation-validation-' + [guid]::NewGuid().ToString('N'))
$safeToDelete = $false

function Assert-Contains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $RelativePath)
    if ($text -notmatch $Pattern) { throw "Missing ${Description}: $RelativePath" }
}

function Assert-NotContains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $repoRoot $RelativePath)
    if ($text -match $Pattern) { throw "Forbidden ${Description}: $RelativePath" }
}

function Assert-Missing([string]$RelativePath, [string]$Description) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath)) { throw "Unexpected ${Description}: $RelativePath" }
}

try {
    foreach ($relative in @(
        'apm-packages/pr-review-remediation/apm.yml',
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md',
        'apm-packages/pr-review-remediation/tests/fixtures/remote-review-scenarios.json',
        'apm-packages/pr-review-remediation/tests/fixtures/expected-review-plan.md',
        'apm-packages/pr-review-remediation/tests/fixtures/expected-review-complete.md'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)) { throw "Missing package file: $relative" }
    }

    Assert-Missing 'apm-packages/pr-review-remediation/.apm/agents/review-planner.agent.md' 'review planner agent'
    Assert-Missing 'apm-packages/pr-review-remediation/codex-profile-overlays.json' 'Codex profile overlay'
    $agents = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot '.apm/agents') -Filter '*.agent.md' -File -ErrorAction SilentlyContinue | ForEach-Object Name)
    if ($agents.Count -ne 0) { throw "Unexpected package agents: $($agents -join ', ')" }
    $scripts = @(Get-ChildItem -LiteralPath (Join-Path $packageRoot 'scripts') -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object Name)
    if (($scripts -join '|') -ne 'validate-pr-review-remediation-apm-smoke.ps1|validate-pr-review-remediation.ps1') {
        throw "Unexpected package scripts: $($scripts -join ', ')"
    }

    Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?ms)^version:\s*0\.9\.0\s*$.*^\s*- copilot\s*$.*^\s*- codex\s*$.*^\s*- agent-skills\s*$' '0.9.0 multi-target manifest'
    Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?ms)^dependencies:\s*$\n\s*apm:\s*\[\]\s*$' 'empty APM dependency set'
    Assert-NotContains 'apm-packages/pr-review-remediation/apm.yml' 'codex-profile-finalizer' 'Codex profile finalizer dependency'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'remote evidenceの直接評価' 'current-parent direct evaluation ownership'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'すべてのremote finding/comment/checkを評価' 'all remote source evaluation'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' '利用者がAdaptive Implementationを明示的に指定' 'explicit Adaptive selection boundary'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' '/adaptive-implementation-execution' 'canonical Adaptive slash invocation'
    foreach ($relative in @(
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md'
    )) {
        Assert-NotContains $relative '\$adaptive-implementation-execution' 'dollar-prefix Adaptive invocation'
    }
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' '全source IDをdecision ledgerまたは理由付き`noAction`' 'remote source coverage contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'duplicate / conflict mapping' 'duplicate and conflict contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'waitStatus: timeout' 'timeout fail-closed contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'REMEDIATION_REQUIRED' 'same-parent remediation state'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'COMMITTED_AND_PUSHED' 'default remediation commit and push outcome'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'empty commit' 'no empty commit contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'Untrusted remote content boundary' 'untrusted remote content boundary'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'Adaptive selection evidenceは利用者の指示だけ' 'Adaptive selection evidence propagation'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md' 'headRepository\.nameWithOwner' 'PR head repository push boundary'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md' 'Resolution / Evidence' 'finding resolution evidence contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md' 'Git outcome' 'Git outcome reporting contract'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md' 'Verified push destination repository / branch' 'verified push destination evidence'
    Assert-NotContains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md' 'Planner recommendation|Planning Verdict' 'planner-owned evaluation field'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs' 'headRepository,headRepositoryOwner,isCrossRepository' 'collector head repository fields'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs' 'remoteContentIsUntrusted' 'collector trust boundary metadata'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs' 'CopilotTimeoutSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*3600\s*;' 'one-hour Copilot timeout default'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs' 'CopilotPollIntervalSeconds\s*\{\s*get;\s*set;\s*\}\s*=\s*30\s*;' '30-second Copilot poll interval default'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs' 'case "--copilot-timeout-seconds"' 'Copilot timeout CLI override'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs' 'case "--copilot-poll-interval-seconds"' 'Copilot poll interval CLI override'
    Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/troubleshooting.md' '通常のreview所要時間を制限せず.*標準のhard timeoutは1時間（3600秒）、poll間隔は30秒' 'Copilot wait timeout documentation'
    Assert-Contains 'docs/pr-review-remediation-technical-reference.md' '標準hard timeoutは3600秒（1時間）、poll間隔は30秒.*timeout.*未取得として扱い' 'technical reference timeout contract'
    Assert-Contains 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-plan.md' 'Final verdict: REVIEW_COMPLETE' 'completed remediation expected verdict'
    Assert-Contains 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-plan.md' 'Git outcome: COMMITTED_AND_PUSHED' 'completed remediation Git outcome'
    Assert-Contains 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-complete.md' 'Git outcome: NO_CHANGES' 'no-remediation Git outcome'
    Assert-NotContains 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-complete.md' 'implementation_intent|adaptive-implementation-execution|Ordered Remediation Plan' 'no-remediation implementation handoff'
    foreach ($relative in @(
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md',
        'apm-packages/pr-review-remediation/tests/fixtures/remote-review-scenarios.json'
    )) {
        Assert-NotContains $relative 'READY_FOR_ADAPTIVE_IMPLEMENTATION' 'mandatory Adaptive handoff verdict'
    }

    foreach ($relative in @(
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
    )) {
        Assert-NotContains $relative 'local-review-findings|Local Codex|Goal Context multi-round|purpose-review-findings' 'retired local/purpose planner input'
    }

    $catalog = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'tests/fixtures/remote-review-scenarios.json') | ConvertFrom-Json
    # 自然言語policyの配布面を横断し、旧gateの復活と検証問題の隠蔽を検出する。
    foreach ($relative in @(
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
        'apm-packages/pr-review-remediation/README.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/troubleshooting.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/migration.md',
        'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md',
        'docs/pr-review-remediation-technical-reference.md'
    )) {
        Assert-Contains $relative 'REVIEW_COMPLETE_WITH_VALIDATION_ISSUES' 'explicit validation-issues verdict'
        if ($relative -notmatch 'migration.md$') {
            Assert-NotContains $relative 'validation成功後|validationが成功し|成功したvalidation evidence|drift、競合、validation failure|validation failure時は成功扱いせず`BLOCKED`|validation failureを無視してcommit / pushしません' 'blanket validation Git gate'
        }
    }
    $skillPath = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md'
    Assert-Contains $skillPath 'PR準備時とreview後のremediation時の両方' 'both-phase policy'
    Assert-Contains $skillPath '必要なvalidationがすべてPASSなら`REVIEW_COMPLETE`' 'clean completion validation requirement'
    Assert-Contains $skillPath '未実装のApplyや未決定のacceptance' 'unfinished remediation boundary'
    Assert-Contains $skillPath '取得済みcheckの検証失敗とsource取得失敗を区別' 'remote check/source distinction'
    Assert-Contains $skillPath '副作用を推測して新たな承認を要求しません' 'evidence-based side-effect boundary'
    $templatePath = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
    foreach ($pattern in @('Phase / Revision', 'Command / Check source ID', 'PASS / FAIL / NOT_RUN', 'Exit code', 'PRE_EXISTING / ENVIRONMENT / CHANGE_RELATED / UNKNOWN', '影響範囲', '未解決事項', 'Git操作の可否と根拠')) {
        Assert-Contains $templatePath ([regex]::Escape($pattern)) 'validation and Git evidence fields'
    }
    $failureFixture = 'apm-packages/pr-review-remediation/tests/fixtures/expected-validation-issues.md'
    foreach ($pattern in @('Final verdict: REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'Git outcome: COMMITTED_AND_PUSHED', '| FAIL |', 'CHANGE_RELATED', '検証成功・品質保証完了ではない')) {
        Assert-Contains $failureFixture ([regex]::Escape($pattern)) 'honest validation failure report'
    }
    $expected = @{
        'REMOTE-001' = @('REVIEW_COMPLETE', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-002' = @('REVIEW_COMPLETE', 'NO_REMEDIATION', 'NO_CHANGES')
        'REMOTE-003' = @('HUMAN_DECISION_REQUIRED', 'NONE', 'NOT_ATTEMPTED')
        'REMOTE-004' = @('BLOCKED', 'NONE', 'NOT_ATTEMPTED')
        'REMOTE-005' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_PUSHED')
        'REMOTE-006' = @('HUMAN_DECISION_REQUIRED', 'NONE', 'NOT_ATTEMPTED')
        'REMOTE-007' = @('REVIEW_COMPLETE', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-008' = @('REVIEW_COMPLETE', 'EXPLICIT_ADAPTIVE', 'COMMITTED_AND_PUSHED')
        'REMOTE-009' = @('REVIEW_COMPLETE', 'CURRENT_PARENT', 'SKIPPED_BY_USER')
        'REMOTE-010' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-011' = @('REVIEW_COMPLETE', 'NO_REMEDIATION', 'NO_CHANGES')
        'REMOTE-012' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-013' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-014' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-015' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-016' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-017' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'COMMITTED_AND_PUSHED')
        'REMOTE-018' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'NO_REMEDIATION', 'NO_CHANGES')
        'REMOTE-019' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-020' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-021' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_PUSHED')
        'REMOTE-022' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-023' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'CURRENT_PARENT', 'SKIPPED_BY_USER')
        'REMOTE-024' = @('BLOCKED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-025' = @('HUMAN_DECISION_REQUIRED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-026' = @('HUMAN_DECISION_REQUIRED', 'CURRENT_PARENT', 'NOT_ATTEMPTED')
        'REMOTE-027' = @('REVIEW_COMPLETE_WITH_VALIDATION_ISSUES', 'NO_REMEDIATION', 'NO_CHANGES')
    }
    if (@($catalog.scenarios).Count -ne $expected.Count) { throw 'Unexpected remote scenario count.' }
    foreach ($scenario in @($catalog.scenarios)) {
        $id = [string]$scenario.id
        if (-not $expected.ContainsKey($id)) { throw "Unknown remote scenario: $id" }
        $actual = @([string]$scenario.expectedVerdict, [string]$scenario.expectedRoute, [string]$scenario.expectedGitOutcome)
        if (($actual -join '|') -cne ($expected[$id] -join '|')) { throw "Wrong expected outcome for $id" }
    }

    # 原因分類やphaseが失われても、期待値の文字列一致だけでは合格させない。
    $validationCases = @($catalog.scenarios | Where-Object { $_.PSObject.Properties.Name -contains 'validationResult' })
    if ($validationCases.Count -ne 15) { throw 'Missing validation policy scenarios.' }
    foreach ($phase in @('PR_PREPARATION', 'REMEDIATION')) {
        if (-not @($validationCases | Where-Object { $_.phase -ceq $phase -and $_.expectedGitOutcome -ceq 'COMMITTED_AND_PUSHED' }).Count) { throw "Missing safe progression case for $phase" }
    }
    foreach ($origin in @('PRE_EXISTING', 'ENVIRONMENT', 'CHANGE_RELATED', 'UNKNOWN')) {
        if (-not @($validationCases | Where-Object { $_.failureOrigin -ceq $origin -and $_.safetyConstraint -ceq 'NONE' }).Count) { throw "Missing failure origin: $origin" }
    }
    foreach ($scenario in $validationCases) {
        if ($scenario.validationResult -cnotin @('FAIL', 'NOT_RUN')) { throw "Invalid validation result: $($scenario.id)" }
        if ($scenario.expectedVerdict -ceq 'REVIEW_COMPLETE') { throw "Validation issue hidden: $($scenario.id)" }
        if ($scenario.safetyConstraint -ceq 'NONE' -and $scenario.expectedVerdict -cne 'REVIEW_COMPLETE_WITH_VALIDATION_ISSUES') { throw "Blanket validation block: $($scenario.id)" }
    }

    $collector = Join-Path $packageRoot '.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs'
    $null = New-Item -ItemType Directory -Path $scratchRoot -Force
    $resolvedScratch = (Resolve-Path -LiteralPath $scratchRoot).Path
    if (-not $resolvedScratch.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe scratch path: $resolvedScratch" }
    $safeToDelete = $true
    & dotnet publish $collector --output (Join-Path $resolvedScratch 'collector')
    if ($LASTEXITCODE -ne 0) { throw 'Collector publish failed.' }
    $help = (& dotnet run --file $collector -- --help | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Collector help failed.' }
    if ($help -notmatch '--copilot-timeout-seconds seconds\s+Hard wait timeout\. Default: 3600\.') { throw 'Collector help has the wrong Copilot timeout default.' }
    if ($help -notmatch '--copilot-poll-interval-seconds value\s+Poll interval\. Default: 30\.') { throw 'Collector help has the wrong Copilot poll interval default.' }

    Write-Output 'PR Review Remediation parent-owned validation: PASS'
}
finally {
    if ($safeToDelete -and (Test-Path -LiteralPath $scratchRoot)) {
        $resolved = [IO.Path]::GetFullPath($scratchRoot)
        if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove unsafe scratch path: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
