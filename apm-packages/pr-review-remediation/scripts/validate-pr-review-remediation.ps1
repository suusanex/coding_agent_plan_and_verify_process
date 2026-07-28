[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packageRoot = Join-Path $repoRoot 'apm-packages\pr-review-remediation'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Assert-Exists([string]$RelativePath) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $RelativePath))) {
        Add-Failure "Missing required path: $RelativePath"
    }
}

function Assert-Contains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing $Description file: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -notmatch $Pattern) {
        Add-Failure "$RelativePath does not contain $Description"
    }
}

function Assert-NotContains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $path = Join-Path $repoRoot $RelativePath
    if ((Test-Path -LiteralPath $path) -and (Get-Content -Raw -LiteralPath $path) -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description, [bool]$ExpectSuccess = $true) {
    $output = & $FilePath @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($ExpectSuccess -and $exitCode -ne 0) {
        Add-Failure "$Description failed with exit code ${exitCode}: $output"
    }
    elseif (-not $ExpectSuccess -and $exitCode -eq 0) {
        Add-Failure "$Description unexpectedly succeeded"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}

function Read-Context([string]$OutputRoot) {
    $path = Join-Path $OutputRoot 'review-context.json'
    if (-not (Test-Path -LiteralPath $path)) {
        Add-Failure "Missing generated review context: $path"
        return $null
    }

    return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
}

foreach ($path in @(
    '.github/agents/local-reviewer.agent.md',
    '.github/agents/review-planner.agent.md',
    'apm-packages/pr-review-remediation/apm.yml',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/local-review-findings.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/migration.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/troubleshooting.md',
    'apm-packages/pr-review-remediation/codex-agents/local-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/review-planner.toml',
    'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs',
    'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-agent-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1',
    'tests/pr-review-remediation/PRR-001/README.md',
    'tests/pr-review-remediation/PRR-001/run.schema.json',
    'tests/pr-review-remediation/PRR-001/fixture/.review/pr-123/review-context.json',
    'tests/pr-review-remediation/PRR-001/fixture/.review/pr-123/pr-diff.patch'
)) {
    Assert-Exists $path
}

Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^name:\s*pr-review-remediation\s*$' 'package name'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^version:\s*0\.1\.1\s*$' 'package version'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/local-reviewer\.agent\.md' 'canonical local reviewer dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/review-planner\.agent\.md' 'canonical review planner dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*apm-packages/adaptive-implementation-execution/\.apm/skills/adaptive-implementation-execution' 'Adaptive Skill dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/high-implementation-starter\.agent\.md' 'Adaptive HIGH agent dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/standard-implementation-completer\.agent\.md' 'Adaptive STANDARD agent dependency'

foreach ($profile in @('local-reviewer.toml', 'review-planner.toml')) {
    $relative = "apm-packages/pr-review-remediation/codex-agents/$profile"
    Assert-Contains $relative '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$' 'review model'
    Assert-Contains $relative '(?m)^model_reasoning_effort\s*=\s*"high"\s*$' 'review reasoning effort'
    Assert-Contains $relative '(?m)^sandbox_mode\s*=\s*"read-only"\s*$' 'read-only sandbox'
}

$skill = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md'
Assert-Contains $skill '(?s)READY_FOR_ADAPTIVE_IMPLEMENTATION.*HUMAN_DECISION_REQUIRED.*BLOCKED' 'Phase 1 verdict vocabulary'
Assert-Contains $skill '別の親ターン' 'separate parent-turn boundary'
Assert-Contains $skill 'Adaptiveを自動起動' 'no automatic Adaptive startup rule'
Assert-Contains $skill '\$adaptive-implementation-execution を使って' 'standard explicit Adaptive prompt'
Assert-Contains $skill '\.agents/skills/adaptive-implementation-execution/SKILL\.md' 'deployed Adaptive Skill path'
Assert-Contains $skill '明示的に読み.*実装実行契約として適用' 'explicit Adaptive Skill read contract'
Assert-Contains $skill '裸のSkill名による暗黙解決には依存しない' 'no implicit Adaptive resolution rule'
Assert-Contains $skill '存在しない、または読めない.*`BLOCKED`.*`high-implementation-starter` を直接起動して迂回しない' 'missing Adaptive Skill blocker'
Assert-Contains $skill 'Draft PRを作成してはいけない' 'Draft creation prohibition'
Assert-Contains $skill 'scripts/collect-pr-review-context\.cs' 'relative collector asset'
Assert-Contains $skill 'templates/local-review-findings\.md' 'relative local findings template'
Assert-Contains $skill 'templates/review-plan\.md' 'relative review plan template'

$reviewPlan = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
foreach ($field in @('goal:', 'scope:', 'non_goals:', 'acceptance:', 'constraints:', 'validation:', 'plan_reference:')) {
    Assert-Contains $reviewPlan ([regex]::Escape($field)) "Implementation Intent field $field"
}
Assert-Contains $reviewPlan 'Apply / Hold / Reject' 'finding decision vocabulary'
Assert-Contains $reviewPlan 'Production code changed: No' 'Phase 1 no-production-edit evidence'

$legacyImplementationAgent = 'spark' + '-implementer'
$runtimeFiles = @(
    '.github/agents/local-reviewer.agent.md',
    '.github/agents/review-planner.agent.md',
    'apm-packages/pr-review-remediation/apm.yml',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/pr-review-remediation/codex-agents/local-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/review-planner.toml',
    'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/troubleshooting.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/local-review-findings.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
)
foreach ($file in $runtimeFiles) {
    Assert-NotContains $file $legacyImplementationAgent 'legacy implementation route'
}

Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/migration.md' '8c3a92b9d63dcf2384f07360e4f845ced0f02156' 'source commit inventory'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/migration.md' 'd9f7317298fdcd39dec29dd662d38bcd82ecfd0f' 'destination baseline inventory'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/migration.md' 'not retained as an agent, alias, compatibility route, fallback, template owner, or profile' 'legacy implementation removal note'

$collector = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/scripts/collect-pr-review-context.cs'
Assert-Contains $collector '(?m)^#:property TargetFramework=net10\.0\s*$' 'File-based App target framework'
Assert-Contains $collector 'baseRefOid.*headRefName.*headRefOid' 'base/head OID collection'
Assert-Contains $collector 'EnsureIdentityUnchanged' 'PR identity drift gate'
Assert-Contains $collector 'pull_request_review_id' 'review ID inline correlation'
Assert-Contains $collector 'waitStatus' 'wait lifecycle output'
Assert-Contains $collector 'observedReviewState' 'review observation output'
Assert-Contains $collector 'pr-diff\.patch' 'remote patch artifact'
Assert-Contains $collector 'The target PR is a draft' 'Draft fail-fast message'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'microsoft/apm-action@v1' 'official APM setup action'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'os:\s*ubuntu-latest\s*\r?\n\s*apm-version:\s*''0\.26\.0''' 'current Ubuntu APM smoke matrix entry'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'os:\s*windows-latest\s*\r?\n\s*apm-version:\s*''0\.18\.0''' 'legacy Windows APM smoke matrix entry'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'runs-on:\s*\$\{\{\s*matrix\.os\s*\}\}' 'remote smoke runner matrix'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '-ExpectedApmVersion\s+''\$\{\{\s*matrix\.apm-version\s*\}\}''' 'remote smoke expected APM version argument'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'PACKAGE_REPOSITORY:\s*\$\{\{\s*github\.repository\s*\}\}' 'base repository package source'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'PACKAGE_REF:\s*\$\{\{\s*github\.ref\s*\}\}' 'event ref package source'
Assert-NotContains '.github/workflows/validate-pr-review-remediation.yml' 'github\.event\.pull_request\.head\.(?:repo|sha)' 'head-only package source'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '(?s)pull_request:.*tests/pr-review-remediation/\*\*.*push:.*tests/pr-review-remediation/\*\*' 'fixed evidence path filters for pull request and push events'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'apm install|@\(''install''' 'real remote APM install command'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' '\[regex\]::Escape\(\$ExpectedApmVersion\)' 'parameterized APM version check'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'finally\s*\{' 'remote smoke cleanup boundary'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1' 'ConfirmExternalModelPayload' 'actual agent smoke external-payload consent gate'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1' 'DescribePayload' 'no-send payload description mode'
foreach ($documentation in @(
    'README.md',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md'
)) {
    Assert-Contains $documentation '(?s)run-pr-review-remediation-agent-smoke\.ps1.*-DescribePayload.*run-pr-review-remediation-agent-smoke\.ps1.*-ConfirmExternalModelPayload' 'payload preview and authorized smoke commands'
}
Assert-Contains 'tests/pr-review-remediation/PRR-001/README.md' 'customAgentSpawnObserved.*false' 'actual execution disclosure'

$fixtureLocal = 'apm-packages/pr-review-remediation/tests/fixtures/expected-local-review-findings.md'
$fixturePlan = 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-plan.md'
Assert-Contains $fixtureLocal 'LR-001' 'fixture stable local finding ID'
Assert-Contains $fixtureLocal 'Production code changed: No' 'fixture read-only review evidence'
Assert-Contains $fixturePlan '(?s)LR-001.*1001.*501' 'fixture review source coverage'
Assert-Contains $fixturePlan 'READY_FOR_ADAPTIVE_IMPLEMENTATION' 'fixture Adaptive readiness'
Assert-Contains $fixturePlan 'AC-001' 'fixture acceptance mapping'
Assert-Contains $fixturePlan '\$adaptive-implementation-execution' 'fixture separate Adaptive prompt'
Assert-Contains $fixturePlan '\.agents/skills/adaptive-implementation-execution/SKILL\.md' 'fixture explicit Adaptive Skill read path'
Assert-Contains $fixturePlan '存在しない、または読めない.*`BLOCKED`.*`high-implementation-starter` を直接起動して迂回しない' 'fixture missing Adaptive Skill blocker'

$agentSmokeValidator = Join-Path $packageRoot 'scripts\validate-pr-review-remediation-agent-smoke.ps1'
$agentSmokeRunner = Join-Path $packageRoot 'scripts\run-pr-review-remediation-agent-smoke.ps1'
$payloadDescription = Invoke-Native 'pwsh' @('-NoProfile', '-File', $agentSmokeRunner, '-RepositoryRoot', $repoRoot, '-DescribePayload') 'agent smoke payload description'
if ($payloadDescription.Output -notmatch 'No model was invoked') { Add-Failure 'agent smoke payload description did not confirm its no-send boundary' }
$missingConsent = Invoke-Native 'pwsh' @('-NoProfile', '-File', $agentSmokeRunner, '-RepositoryRoot', $repoRoot) 'agent smoke consent gate' $false
if ($missingConsent.Output -notmatch 'HUMAN_DECISION_REQUIRED') { Add-Failure 'agent smoke did not fail closed without external-payload consent' }
Invoke-Native 'pwsh' @('-NoProfile', '-File', $agentSmokeValidator, '-RepositoryRoot', $repoRoot) 'fixed actual agent smoke evidence' | Out-Null

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-review-remediation-validation-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $collectorOut = Join-Path $tempRoot 'collector'
    $fakeOut = Join-Path $tempRoot 'fake-gh'
    $syncOut = Join-Path $tempRoot 'sync'
    $adaptiveSyncOut = Join-Path $tempRoot 'adaptive-sync'
    $collectorPath = Join-Path $repoRoot $collector
    $fakePath = Join-Path $packageRoot 'tests\fixtures\fake-gh.cs'
    $syncPath = Join-Path $packageRoot 'scripts\sync-pr-review-remediation-local.cs'
    $adaptiveSyncPath = Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs'

    Invoke-Native 'dotnet' @('publish', $collectorPath, '--output', $collectorOut, '--disable-build-servers') 'collector publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $fakePath, '--output', $fakeOut, '--disable-build-servers') 'fake gh publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $syncPath, '--output', $syncOut, '--disable-build-servers') 'profile sync helper publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $adaptiveSyncPath, '--output', $adaptiveSyncOut, '--disable-build-servers') 'Adaptive profile helper publish' | Out-Null

    $collectorExe = Join-Path $collectorOut 'collect-pr-review-context.exe'
    $fakeExe = Join-Path $fakeOut 'fake-gh.exe'
    $syncExe = Join-Path $syncOut 'sync-pr-review-remediation-local.exe'
    $adaptiveSyncExe = Join-Path $adaptiveSyncOut 'install-adaptive-implementation-local.exe'
    foreach ($exe in @($collectorExe, $fakeExe, $syncExe, $adaptiveSyncExe)) {
        if (-not (Test-Path -LiteralPath $exe)) {
            Add-Failure "Missing published executable: $exe"
        }
    }

    Invoke-Native $collectorExe @('--help') 'collector help' | Out-Null
    Invoke-Native $syncExe @('--help') 'profile sync helper help' | Out-Null
    Invoke-Native $collectorExe @('--unknown-option') 'collector invalid argument' $false | Out-Null
    Invoke-Native $syncExe @('--unknown-option') 'profile sync helper invalid argument' $false | Out-Null

    function Invoke-Fixture([string]$Scenario, [string[]]$ExtraArgs = @(), [bool]$ExpectSuccess = $true) {
        $scenarioRoot = Join-Path $tempRoot $Scenario
        New-Item -ItemType Directory -Path $scenarioRoot | Out-Null
        $env:FAKE_GH_SCENARIO = $Scenario
        $env:FAKE_GH_STATE = Join-Path $scenarioRoot 'state.txt'
        $arguments = @('--repo', 'example/repo', '--pr', '123', '--out', $scenarioRoot, '--gh-executable', $fakeExe) + $ExtraArgs
        return Invoke-Native $collectorExe $arguments "collector fixture $Scenario" $ExpectSuccess
    }

    Invoke-Fixture 'ready' @('--no-wait-for-copilot') | Out-Null
    $ready = Read-Context (Join-Path $tempRoot 'ready')
    if ($null -ne $ready) {
        if ($ready.target.baseRefOid -ne 'base-001' -or $ready.target.headRefOid -ne 'head-001') { Add-Failure 'ready fixture did not preserve base/head identity' }
        if ($ready.copilotReviewWait.waitStatus -ne 'disabled') { Add-Failure 'ready fixture waitStatus must be disabled' }
        if ($ready.copilotReviewWait.observedReviewState -ne 'reviewAndInline') { Add-Failure 'ready fixture observation must be reviewAndInline' }
        if ($ready.sources.checks.Count -ne 3) { Add-Failure 'ready fixture must preserve successful, failing, and pending checks' }
        if ($ready.sources.reviews.Count -ne 1 -or $ready.sources.issueComments.Count -ne 1) { Add-Failure 'paginated fixture sources were not normalized' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'ready\pr-diff.patch'))) { Add-Failure 'ready fixture did not produce pr-diff.patch' }

    Invoke-Fixture 'old-head' @('--no-wait-for-copilot') | Out-Null
    $oldHead = Read-Context (Join-Path $tempRoot 'old-head')
    if ($null -ne $oldHead) {
        if ($oldHead.copilotReviewWait.selectedReviewId -ne 100) { Add-Failure 'old-head fixture selected a review not anchored to current head' }
        if ($oldHead.copilotReviewWait.actualInlineCommentCount -ne 1 -or $oldHead.copilotReviewWait.inlineCommentIds[0] -ne 1001) { Add-Failure 'old-head inline comment leaked into the current-head observation' }
    }

    Invoke-Fixture 'delayed' @('--copilot-timeout-seconds', '5', '--copilot-poll-interval-seconds', '1', '--copilot-stable-samples', '2') | Out-Null
    $delayed = Read-Context (Join-Path $tempRoot 'delayed')
    if ($null -ne $delayed) {
        if ($delayed.copilotReviewWait.waitStatus -ne 'completed') { Add-Failure 'delayed fixture did not reach completed wait status' }
        if ($delayed.copilotReviewWait.actualInlineCommentCount -ne 2) { Add-Failure 'delayed fixture completed before both inline comments arrived' }
        if ($delayed.copilotReviewWait.stableSamplesObserved -lt 2) { Add-Failure 'delayed fixture did not require stable samples' }
    }

    Invoke-Fixture 'inline-only' @('--copilot-timeout-seconds', '1', '--copilot-poll-interval-seconds', '1', '--copilot-stable-samples', '2') | Out-Null
    $inlineOnly = Read-Context (Join-Path $tempRoot 'inline-only')
    if ($null -ne $inlineOnly) {
        if ($inlineOnly.copilotReviewWait.waitStatus -ne 'timeout') { Add-Failure 'inline-only fixture completed without a terminal review' }
        if ($inlineOnly.copilotReviewWait.observedReviewState -ne 'inlineOnly') { Add-Failure 'inline-only fixture did not preserve its observed state at timeout' }
        if ($inlineOnly.copilotReviewWait.actualInlineCommentCount -ne 1) { Add-Failure 'inline-only fixture lost the observed current-head inline comment' }
    }

    Invoke-Fixture 'inline-then-review' @('--copilot-timeout-seconds', '5', '--copilot-poll-interval-seconds', '1', '--copilot-stable-samples', '2') | Out-Null
    $inlineThenReview = Read-Context (Join-Path $tempRoot 'inline-then-review')
    if ($null -ne $inlineThenReview) {
        if ($inlineThenReview.copilotReviewWait.waitStatus -ne 'completed') { Add-Failure 'inline-then-review fixture did not complete after the terminal review arrived' }
        if ($inlineThenReview.copilotReviewWait.observedReviewState -ne 'reviewAndInline') { Add-Failure 'inline-then-review fixture did not finish with reviewAndInline' }
        if ($inlineThenReview.copilotReviewWait.selectedReviewId -ne 100 -or $inlineThenReview.copilotReviewWait.actualInlineCommentCount -ne 2) { Add-Failure 'inline-then-review fixture completed with incomplete correlation' }
        if ($inlineThenReview.copilotReviewWait.stableSamplesObserved -lt 2) { Add-Failure 'inline-then-review fixture did not require stable terminal samples' }
    }

    Invoke-Fixture 'lookalike-login' @('--no-wait-for-copilot') | Out-Null
    $lookalike = Read-Context (Join-Path $tempRoot 'lookalike-login')
    if ($null -ne $lookalike) {
        if ($lookalike.copilotReviewWait.selectedReviewId -ne 100) { Add-Failure 'lookalike-login fixture selected a non-Copilot account' }
        if ($lookalike.copilotReviewWait.actualInlineCommentCount -ne 1 -or $lookalike.copilotReviewWait.inlineCommentIds[0] -ne 1001) { Add-Failure 'lookalike-login fixture correlated a non-Copilot inline comment' }
    }

    Invoke-Fixture 'timeout' @('--copilot-timeout-seconds', '1', '--copilot-poll-interval-seconds', '1') | Out-Null
    $timeout = Read-Context (Join-Path $tempRoot 'timeout')
    if ($null -ne $timeout) {
        if ($timeout.copilotReviewWait.waitStatus -ne 'timeout' -or -not $timeout.copilotReviewWait.timedOut) { Add-Failure 'timeout fixture was not recorded as an explicit timeout' }
        if ($timeout.copilotReviewWait.observedReviewState -ne 'none') { Add-Failure 'timeout fixture observation must be none' }
    }

    $draft = Invoke-Fixture 'draft' @('--no-wait-for-copilot') $false
    if ($draft.Output -notmatch 'target PR is a draft') { Add-Failure 'Draft fixture did not return the explicit Ready-for-review error' }

    $changed = Invoke-Fixture 'head-change' @('--copilot-timeout-seconds', '3', '--copilot-poll-interval-seconds', '1') $false
    if ($changed.Output -notmatch 'identity changed during review context collection') { Add-Failure 'head-change fixture did not fail closed' }

    $patchChanged = Invoke-Fixture 'patch-head-change' @('--no-wait-for-copilot') $false
    if ($patchChanged.Output -notmatch 'identity changed during review context collection') { Add-Failure 'patch-head-change fixture did not fail closed before writing artifacts' }
    if (Test-Path -LiteralPath (Join-Path $tempRoot 'patch-head-change\review-context.json')) { Add-Failure 'patch-head-change fixture wrote a mixed-identity artifact' }

    $badJson = Invoke-Fixture 'bad-json' @('--no-wait-for-copilot') $false
    if ($badJson.ExitCode -eq 0) { Add-Failure 'bad-json fixture did not fail closed' }

    $ghFailure = Invoke-Fixture 'gh-failure' @('--no-wait-for-copilot') $false
    if ($ghFailure.Output -notmatch 'simulated GitHub CLI failure') { Add-Failure 'GitHub CLI failure was not surfaced' }

    # Reproduce the supported two-helper local setup without relying on APM's
    # unsupported local-path resolution for transitive `git: parent` dependencies.
    $scratch = Join-Path $tempRoot 'scratch-repository'
    $scratchSkill = Join-Path $scratch '.agents\skills\adaptive-implementation-execution'
    $scratchAgents = Join-Path $scratch '.github\agents'
    $scratchCodex = Join-Path $scratch '.codex'
    New-Item -ItemType Directory -Path $scratchSkill, $scratchAgents, $scratchCodex -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution\SKILL.md') -Destination (Join-Path $scratchSkill 'SKILL.md')
    foreach ($agent in @('high-implementation-starter.agent.md', 'standard-implementation-completer.agent.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot ".github\agents\$agent") -Destination (Join-Path $scratchAgents $agent)
    }
    Set-Content -LiteralPath (Join-Path $scratch 'AGENTS.md') -Value 'sentinel-agents'
    Set-Content -LiteralPath (Join-Path $scratchCodex 'config.toml') -Value 'sentinel-config'

    $missingAdaptive = Invoke-Native $syncExe @($scratch, '--check') 'review helper missing-Adaptive gate' $false
    if ($missingAdaptive.Output -notmatch 'install-adaptive-implementation-local\.cs') { Add-Failure 'review helper did not return the existing Adaptive helper command' }

    Invoke-Native $syncExe @($scratch, '--dry-run') 'review helper dry-run' | Out-Null
    Invoke-Native $syncExe @($scratch) 'review helper install' | Out-Null
    Invoke-Native $adaptiveSyncExe @($scratch, '--dry-run') 'Adaptive helper dry-run' | Out-Null
    Invoke-Native $adaptiveSyncExe @($scratch) 'Adaptive helper install' | Out-Null
    Invoke-Native $adaptiveSyncExe @($scratch, '--check') 'Adaptive helper check' | Out-Null
    Invoke-Native $syncExe @($scratch, '--check') 'review helper check' | Out-Null

    foreach ($profile in @('local-reviewer.toml', 'review-planner.toml', 'high-implementation-starter.toml', 'standard-implementation-completer.toml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $scratch ".codex\agents\$profile"))) { Add-Failure "Missing scratch profile after helper synchronization: $profile" }
    }
    if ((Get-Content -Raw -LiteralPath (Join-Path $scratch 'AGENTS.md')).Trim() -ne 'sentinel-agents') { Add-Failure 'review helpers changed AGENTS.md' }
    if ((Get-Content -Raw -LiteralPath (Join-Path $scratchCodex 'config.toml')).Trim() -ne 'sentinel-config') { Add-Failure 'review helpers changed .codex/config.toml' }

    Set-Content -LiteralPath (Join-Path $scratch '.codex\agents\local-reviewer.toml') -Value 'name = "locally-modified"'
    $reviewCollision = Invoke-Native $syncExe @($scratch) 'review helper collision gate' $false
    if ($reviewCollision.Output -match 'install-adaptive-implementation-local\.cs') { Add-Failure 'review-only profile collision incorrectly recommended the Adaptive helper' }
    Invoke-Native $syncExe @($scratch, '--force') 'review helper force synchronization' | Out-Null
    Invoke-Native $syncExe @($scratch, '--remove', '--dry-run') 'review helper removal dry-run' | Out-Null
    Invoke-Native $syncExe @($scratch, '--remove') 'review helper removal' | Out-Null
    foreach ($profile in @('local-reviewer.toml', 'review-planner.toml')) {
        if (Test-Path -LiteralPath (Join-Path $scratch ".codex\agents\$profile")) { Add-Failure "Review helper did not remove package-owned profile: $profile" }
    }

    $apmScratch = Join-Path $tempRoot 'apm-profile-repository'
    $apmProfileRoot = Join-Path $apmScratch '.codex\agents'
    New-Item -ItemType Directory -Path $apmProfileRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $apmProfileRoot 'local-reviewer.toml') -NoNewline -Value @'
name = "local-reviewer"
description = "Review only the confirmed remote PR base/head diff and produce evidence-backed local Codex findings without editing files or GitHub state."
developer_instructions = "# Local Reviewer\n\nPreserved APM contract with an escaped \"quoted value\"."
'@
    Set-Content -LiteralPath (Join-Path $apmProfileRoot 'review-planner.toml') -NoNewline -Value @'
name = "review-planner"
description = "Consolidate local Codex findings, GitHub Copilot reviews, PR comments, and checks into an Adaptive-ready remediation plan without implementing fixes."
developer_instructions = "# Review Planner\n\nPreserved APM contract with an escaped \"quoted value\"."
'@
    Invoke-Native $syncExe @($apmScratch) 'APM-generated review profile completion' | Out-Null
    foreach ($profile in @('local-reviewer.toml', 'review-planner.toml')) {
        $content = Get-Content -Raw -LiteralPath (Join-Path $apmProfileRoot $profile)
        if ($content -notmatch '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$') { Add-Failure "APM-generated profile did not receive a concrete model: $profile" }
        if ($content -notmatch '(?m)^sandbox_mode\s*=\s*"read-only"\s*$') { Add-Failure "APM-generated profile did not receive a read-only sandbox: $profile" }
        if ($content -notmatch 'Preserved APM contract with an escaped \\"quoted value\\"') { Add-Failure "Review helper replaced the APM-generated developer instructions: $profile" }
    }
    Invoke-Native $syncExe @($apmScratch, '--remove') 'completed APM review profile removal' | Out-Null
    foreach ($profile in @('local-reviewer.toml', 'review-planner.toml')) {
        if (Test-Path -LiteralPath (Join-Path $apmProfileRoot $profile)) { Add-Failure "Review helper did not remove its completed APM profile: $profile" }
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GH_SCENARIO -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GH_STATE -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Error ("PR Review Remediation validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'PR Review Remediation validation: PASS'
