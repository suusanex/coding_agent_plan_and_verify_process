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
    '.github/agents/purpose-reviewer.agent.md',
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
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/select-goal-context.cs',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-review-cycle.cs',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/purpose-review-findings.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-result.example.json',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-round-result.example.json',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/design.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/usage.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/troubleshooting.md',
    'apm-packages/goal-context-authoring/.apm/skills/goal-context-authoring/scripts/validate-goal-context.cs',
    'apm-packages/pr-review-remediation/codex-agents/local-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/purpose-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/review-planner.toml',
    'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs',
    'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-agent-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-prr-002-contract.cs',
    'apm-packages/pr-review-remediation/scripts/validate-prr-003-contract.ps1',
    'tests/pr-review-remediation/PRR-001/README.md',
    'tests/pr-review-remediation/PRR-001/run.schema.json',
    'tests/pr-review-remediation/PRR-001/fixture/.review/pr-123/review-context.json',
    'tests/pr-review-remediation/PRR-001/fixture/.review/pr-123/pr-diff.patch',
    'tests/pr-review-remediation/PRR-002/README.md',
    'tests/pr-review-remediation/PRR-002/run.json',
    'tests/pr-review-remediation/PRR-002/fixture/docs/goal-context-direct-review-notification.md',
    'tests/pr-review-remediation/PRR-002/fixture/.review/pr-123/review-context.json',
    'tests/pr-review-remediation/PRR-002/fixture/.review/pr-123/pr-diff.patch',
    'tests/pr-review-remediation/PRR-002/goal-context-selection.json',
    'tests/pr-review-remediation/PRR-002/local-review-findings.md',
    'tests/pr-review-remediation/PRR-002/purpose-review-findings.md',
    'tests/pr-review-remediation/PRR-002/review-plan.md',
    'tests/pr-review-remediation/PRR-002/completion-notification.txt',
    'tests/pr-review-remediation/PRR-002/adaptive-turn-input.txt',
    'tests/pr-review-remediation/PRR-003/README.md',
    'tests/pr-review-remediation/PRR-003/scenarios.json',
    'tests/pr-review-remediation/manual-model-smoke/README.md',
    'tests/pr-review-remediation/manual-model-smoke/result-template.md'
)) {
    Assert-Exists $path
}

Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^name:\s*pr-review-remediation\s*$' 'package name'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^version:\s*0\.3\.0\s*$' 'package version'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*apm-packages/goal-context-authoring/\.apm/skills/goal-context-authoring' 'canonical Goal Context Authoring Skill dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/local-reviewer\.agent\.md' 'canonical local reviewer dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/purpose-reviewer\.agent\.md' 'canonical purpose reviewer dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/review-planner\.agent\.md' 'canonical review planner dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*apm-packages/adaptive-implementation-execution/\.apm/skills/adaptive-implementation-execution' 'Adaptive Skill dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/high-implementation-starter\.agent\.md' 'Adaptive HIGH agent dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/standard-implementation-completer\.agent\.md' 'Adaptive STANDARD agent dependency'

foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml')) {
    $relative = "apm-packages/pr-review-remediation/codex-agents/$profile"
    Assert-Contains $relative '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$' 'review model'
    Assert-Contains $relative '(?m)^model_reasoning_effort\s*=\s*"high"\s*$' 'review reasoning effort'
    Assert-Contains $relative '(?m)^sandbox_mode\s*=\s*"read-only"\s*$' 'read-only sandbox'
}

$skill = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md'
Assert-Contains $skill '(?s)READY_FOR_ADAPTIVE_IMPLEMENTATION.*HUMAN_DECISION_REQUIRED.*BLOCKED' 'Phase 1 verdict vocabulary'
Assert-Contains $skill '別の親ターン' 'separate parent-turn boundary'
Assert-Contains $skill 'Adaptiveを自動起動' 'no automatic Adaptive startup rule'
Assert-Contains $skill 'Draft PRを作成してはいけない' 'Draft creation prohibition'
Assert-Contains $skill 'scripts/collect-pr-review-context\.cs' 'relative collector asset'
Assert-Contains $skill 'templates/local-review-findings\.md' 'relative local findings template'
Assert-Contains $skill 'templates/review-plan\.md' 'relative review plan template'

$goalSkill = 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md'
Assert-Contains $goalSkill 'name:\s*goal-context-pr-review' 'Goal Context Skill name'
Assert-Contains $goalSkill 'scripts/select-goal-context\.cs' 'Goal Context selector asset'
Assert-Contains $goalSkill 'scripts/manage-review-cycle\.cs' 'multi-round cycle manager asset'
Assert-Contains $goalSkill 'REVIEW_COMPLETE' 'multi-round completion verdict'
Assert-Contains $goalSkill 'override-maximum-rounds 4' 'explicit fourth-round override'
Assert-Contains $goalSkill '次roundを内部起動しません' 'manual next-round boundary'
Assert-Contains $goalSkill 'purpose-reviewer' 'independent purpose reviewer'
Assert-Contains $goalSkill 'Issue本文だけで目的reviewを代替せず停止' 'no Issue-only purpose fallback'
Assert-Contains $goalSkill 'Adaptiveを内部呼び出ししません' 'manual Adaptive boundary'
Assert-Contains $goalSkill 'completion-notification' 'notification decorator envelope example'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/design.md' '別packageではなく.*別Skill' 'same-package separate-Skill decision'
Assert-Contains '.github/agents/purpose-reviewer.agent.md' '実装担当および`local-reviewer`から独立' 'purpose reviewer independence'
Assert-Contains '.github/agents/purpose-reviewer.agent.md' 'コード上のbug.*`local-reviewer`' 'purpose and code quality separation'
$cycleManager = 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-review-cycle.cs'
Assert-Contains $cycleManager '(?m)^#:property TargetFramework=net10\.0\s*$' 'multi-round File-based App target framework'
Assert-Contains $cycleManager 'DefaultMaximumRounds = 3' 'default maximum of three rounds'
Assert-Contains $cycleManager '(?s)"new".*"persistent".*"resolved".*"reopened"' 'finding transition vocabulary'
Assert-Contains $cycleManager '(?s)READY_FOR_ADAPTIVE_IMPLEMENTATION.*HUMAN_DECISION_REQUIRED' 'round-limit verdict transition'
Assert-Contains $cycleManager 'SourceCoverageEntry' 'per-round source coverage contract'
Assert-Contains $cycleManager 'ValidateArtifactContents' 'role-aware artifact content cross-validation'
Assert-Contains $cycleManager 'review-context repository' 'review-context identity cross-validation'
Assert-Contains $cycleManager 'review-result finding delta' 'planner result delta cross-validation'
Assert-Contains $cycleManager 'A pending human decision must be explicitly resolved' 'pending human decision gate'
Assert-Contains $cycleManager 'Maximum-round override is accepted only for round 4 or later' 'early override rejection'
Assert-Contains $cycleManager 'ValidateCycle\(cyclePath, cycle, requireCompletedCurrentRound: false\);\s*SaveCycle' 'pre-save final state validation'
Assert-NotContains $cycleManager 'Process\.Start|adaptive-implementation-execution|completion-notification-decorator' 'internal process orchestration'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-round-result.example.json' '"sourceCoverage"' 'round-result source coverage example'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-round-result.example.json' '"roundNumber": 2' 'round notification identity example'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-result.example.json' '"artifactBindings"' 'planner result artifact binding example'

$reviewPlan = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
foreach ($field in @('goal:', 'scope:', 'non_goals:', 'acceptance:', 'constraints:', 'validation:', 'plan_reference:', 'goal_context_reference:')) {
    Assert-Contains $reviewPlan ([regex]::Escape($field)) "Implementation Intent field $field"
}
Assert-Contains $reviewPlan 'Apply / Hold / Reject' 'finding decision vocabulary'
Assert-Contains $reviewPlan 'Production code changed: No' 'Phase 1 no-production-edit evidence'
Assert-Contains $reviewPlan 'Goal Context Boundary' 'Goal Context plan boundary'
Assert-Contains $reviewPlan 'Purpose review:' 'purpose review input status'
Assert-Contains $reviewPlan '`PUR-\*` rows are Goal Context mode only; omit them in Baseline mode\.' 'baseline-safe purpose row guidance'
Assert-Contains $reviewPlan '(?m)^\| LR-001 \| Local Codex' 'separate baseline local finding example'
Assert-Contains $reviewPlan '(?m)^\| PUR-001 \| Purpose \(Goal Context mode only\)' 'separate optional purpose finding example'
Assert-Contains $reviewPlan 'new / persistent / resolved / reopened' 'multi-round finding delta vocabulary'
Assert-Contains '.github/agents/review-planner.agent.md' 'READY_FOR_ADAPTIVE_IMPLEMENTATION \| REVIEW_COMPLETE \| HUMAN_DECISION_REQUIRED \| BLOCKED' 'multi-round planner verdict vocabulary'
Assert-Contains '.github/agents/review-planner.agent.md' '空のAdaptive向けplanを生成しない' 'no empty Adaptive plan rule'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'deterministic-multi-round-replay' 'PRR-003 evidence mode'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'HUMAN_DECISION_REQUIRED' 'PRR-003 maximum-round verdict'
Assert-Contains 'tests/pr-review-remediation/PRR-003/README.md' '外部model.*実行しません' 'PRR-003 external-model disclosure'

$legacyImplementationAgent = 'spark' + '-implementer'
$runtimeFiles = @(
    '.github/agents/local-reviewer.agent.md',
    '.github/agents/purpose-reviewer.agent.md',
    '.github/agents/review-planner.agent.md',
    'apm-packages/pr-review-remediation/apm.yml',
    'apm-packages/pr-review-remediation/README.md',
    'apm-packages/pr-review-remediation/codex-agents/local-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/purpose-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/review-planner.toml',
    'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/SKILL.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/troubleshooting.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/local-review-findings.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/design.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/usage.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/troubleshooting.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/purpose-review-findings.md'
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
Assert-Contains $collector 'sourceId' 'stable review source identifiers'
Assert-Contains $collector 'StableSourceId' 'deterministic check source identifier fallback'
Assert-Contains $collector 'The target PR is a draft' 'Draft fail-fast message'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'microsoft/apm-action@v1' 'official APM setup action'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'apm-version:\s*''0\.26\.0''' 'pinned APM version'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'PACKAGE_REPOSITORY:\s*\$\{\{\s*github\.repository\s*\}\}' 'base repository package source'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'PACKAGE_REF:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha \|\| github\.sha\s*\}\}' 'full PR head or push SHA package source'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '(?s)checkout@v4.*ref:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha \|\| github\.sha\s*\}\}' 'full PR head or push SHA checkout source'
Assert-NotContains '.github/workflows/validate-pr-review-remediation.yml' 'github\.event\.pull_request\.head\.repo' 'fork repository package source'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '(?s)pull_request:.*tests/pr-review-remediation/\*\*.*push:.*tests/pr-review-remediation/\*\*' 'fixed evidence path filters for pull request and push events'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '(?s)pull_request:.*purpose-reviewer\.agent\.md.*push:.*purpose-reviewer\.agent\.md' 'purpose reviewer path filters for pull request and push events'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '(?s)pull_request:.*apm-packages/goal-context-authoring/\*\*.*push:.*apm-packages/goal-context-authoring/\*\*' 'Goal Context Authoring dependency path filters for pull request and push events'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'git diff --check origin/main\.\.\.HEAD' 'branch-range whitespace gate'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'apm install|@\(''install''' 'real remote APM install command'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'finally\s*\{' 'remote smoke cleanup boundary'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' '\$global:LASTEXITCODE\s*=\s*0' 'Linux success exit reset after expected native failures'
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
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' '(?s)full head SHA.*disposable target.*送信を承認.*local-reviewer.*purpose-reviewer.*Phase 1.*別親ターン.*Adaptive' 'manual real-model smoke boundary and acceptance sequence'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' '(?s)completion-notification-decorator.*NotificationInstaller.*--dry-run.*--check' 'manual direct-link notification installation preflight'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/result-template.md' '(?s)External model payload approved.*Local finding.*Purpose-only finding.*Phase 1 stopped.*Direct-link notification.*Adaptive handoff' 'manual smoke evidence checklist'

$fixtureLocal = 'apm-packages/pr-review-remediation/tests/fixtures/expected-local-review-findings.md'
$fixturePlan = 'apm-packages/pr-review-remediation/tests/fixtures/expected-review-plan.md'
Assert-Contains $fixtureLocal 'LR-001' 'fixture stable local finding ID'
Assert-Contains $fixtureLocal 'Production code changed: No' 'fixture read-only review evidence'
Assert-Contains $fixturePlan '(?s)LR-001.*1001.*501' 'fixture review source coverage'
Assert-Contains $fixturePlan 'READY_FOR_ADAPTIVE_IMPLEMENTATION' 'fixture Adaptive readiness'
Assert-Contains $fixturePlan 'AC-001' 'fixture acceptance mapping'
Assert-Contains $fixturePlan '\$adaptive-implementation-execution' 'fixture separate Adaptive prompt'

Assert-Contains 'tests/pr-review-remediation/PRR-002/purpose-review-findings.md' 'Verdict: PURPOSE_REVIEWED' 'Goal Context fixture purpose verdict'
Assert-Contains 'tests/pr-review-remediation/PRR-002/local-review-findings.md' 'Verdict: REVIEWED' 'Goal Context fixture local verdict'
Assert-Contains 'tests/pr-review-remediation/PRR-002/local-review-findings.md' 'LR-001' 'Goal Context fixture stable local finding ID'
Assert-Contains 'tests/pr-review-remediation/PRR-002/fixture/.review/pr-123/review-context.json' '(?s)"schemaVersion":\s*"1\.0".*"target":.*"sources":.*"reviews":.*"issueComments":.*"inlineComments":.*"checks":' 'Goal Context fixture uses the shared collector schema'
Assert-Contains 'tests/pr-review-remediation/PRR-002/purpose-review-findings.md' 'PUR-001' 'Goal Context fixture stable purpose finding ID'
Assert-Contains 'tests/pr-review-remediation/PRR-002/review-plan.md' '(?s)LR-001.*PUR-001.*RC-001' 'Goal Context fixture integrated source coverage'
Assert-Contains 'tests/pr-review-remediation/PRR-002/review-plan.md' 'Goal Context Boundary' 'Goal Context fixture boundary'
Assert-Contains 'tests/pr-review-remediation/PRR-002/review-plan.md' 'goal_context_reference:' 'Goal Context fixture Adaptive reference'
Assert-Contains 'tests/pr-review-remediation/PRR-002/completion-notification.txt' '"result_uri":"https://github.com/fixture/goal-context-review/pull/123"' 'Goal Context fixture direct PR link'
Assert-Contains 'tests/pr-review-remediation/PRR-002/adaptive-turn-input.txt' '(?s)\$completion-notification-decorator.*\$adaptive-implementation-execution.*review-plan\.md' 'Goal Context fixture separate notification Adaptive turn'

$notificationFixture = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'tests/pr-review-remediation/PRR-002/completion-notification.txt')
$notificationMatch = [regex]::Match($notificationFixture, '(?ms)```completion-notification\s*(?<json>\{.*?\})\s*```')
if (-not $notificationMatch.Success) {
    Add-Failure 'Goal Context fixture notification envelope is missing.'
} else {
    $notificationSchema = Join-Path $repoRoot 'scripts/codex-notification-runtime/completion-notification-envelope-v1.schema.json'
    if (-not ($notificationMatch.Groups['json'].Value | Test-Json -SchemaFile $notificationSchema)) {
        Add-Failure 'Goal Context fixture notification envelope does not satisfy the shared runtime schema.'
    }
}

$agentSmokeValidator = Join-Path $packageRoot 'scripts\validate-pr-review-remediation-agent-smoke.ps1'
$agentSmokeRunner = Join-Path $packageRoot 'scripts\run-pr-review-remediation-agent-smoke.ps1'
$payloadDescription = Invoke-Native 'pwsh' @('-NoProfile', '-File', $agentSmokeRunner, '-RepositoryRoot', $repoRoot, '-DescribePayload') 'agent smoke payload description'
if ($payloadDescription.Output -notmatch 'No model was invoked') { Add-Failure 'agent smoke payload description did not confirm its no-send boundary' }
$missingConsent = Invoke-Native 'pwsh' @('-NoProfile', '-File', $agentSmokeRunner, '-RepositoryRoot', $repoRoot) 'agent smoke consent gate' $false
if ($missingConsent.Output -notmatch 'HUMAN_DECISION_REQUIRED') { Add-Failure 'agent smoke did not fail closed without external-payload consent' }
Invoke-Native 'pwsh' @('-NoProfile', '-File', $agentSmokeValidator, '-RepositoryRoot', $repoRoot) 'fixed actual agent smoke evidence' | Out-Null
$prr003Validator = Join-Path $packageRoot 'scripts\validate-prr-003-contract.ps1'
Invoke-Native 'pwsh' @('-NoProfile', '-File', $prr003Validator) 'PRR-003 deterministic multi-round replay' | Out-Null

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-review-remediation-validation-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $collectorOut = Join-Path $tempRoot 'collector'
    $fakeOut = Join-Path $tempRoot 'fake-gh'
    $syncOut = Join-Path $tempRoot 'sync'
    $selectorOut = Join-Path $tempRoot 'selector'
    $canonicalValidatorOut = Join-Path $tempRoot 'canonical-goal-context-validator'
    $replayValidatorOut = Join-Path $tempRoot 'prr-002-replay-validator'
    $adaptiveSyncOut = Join-Path $tempRoot 'adaptive-sync'
    $collectorPath = Join-Path $repoRoot $collector
    $fakePath = Join-Path $packageRoot 'tests\fixtures\fake-gh.cs'
    $syncPath = Join-Path $packageRoot 'scripts\sync-pr-review-remediation-local.cs'
    $selectorPath = Join-Path $packageRoot '.apm\skills\goal-context-pr-review\scripts\select-goal-context.cs'
    $canonicalValidatorPath = Join-Path $repoRoot 'apm-packages\goal-context-authoring\.apm\skills\goal-context-authoring\scripts\validate-goal-context.cs'
    $replayValidatorPath = Join-Path $packageRoot 'scripts\validate-prr-002-contract.cs'
    $adaptiveSyncPath = Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs'

    Invoke-Native 'dotnet' @('publish', $collectorPath, '--output', $collectorOut, '--disable-build-servers') 'collector publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $fakePath, '--output', $fakeOut, '--disable-build-servers') 'fake gh publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $syncPath, '--output', $syncOut, '--disable-build-servers') 'profile sync helper publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $selectorPath, '--output', $selectorOut, '--disable-build-servers') 'Goal Context selector publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $canonicalValidatorPath, '--output', $canonicalValidatorOut, '--disable-build-servers') 'canonical Goal Context validator publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $replayValidatorPath, '--output', $replayValidatorOut, '--disable-build-servers') 'PRR-002 replay validator publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $adaptiveSyncPath, '--output', $adaptiveSyncOut, '--disable-build-servers') 'Adaptive profile helper publish' | Out-Null

    $collectorExe = Join-Path $collectorOut 'collect-pr-review-context.exe'
    $fakeExe = Join-Path $fakeOut 'fake-gh.exe'
    $syncExe = Join-Path $syncOut 'sync-pr-review-remediation-local.exe'
    $selectorExe = Join-Path $selectorOut 'select-goal-context.exe'
    $canonicalValidatorExe = Join-Path $canonicalValidatorOut 'validate-goal-context.exe'
    $replayValidatorExe = Join-Path $replayValidatorOut 'validate-prr-002-contract.exe'
    $adaptiveSyncExe = Join-Path $adaptiveSyncOut 'install-adaptive-implementation-local.exe'
    foreach ($exe in @($collectorExe, $fakeExe, $syncExe, $selectorExe, $canonicalValidatorExe, $replayValidatorExe, $adaptiveSyncExe)) {
        if (-not (Test-Path -LiteralPath $exe)) {
            Add-Failure "Missing published executable: $exe"
        }
    }

    Invoke-Native $collectorExe @('--help') 'collector help' | Out-Null
    Invoke-Native $syncExe @('--help') 'profile sync helper help' | Out-Null
    Invoke-Native $selectorExe @('--help') 'Goal Context selector help' | Out-Null
    Invoke-Native $canonicalValidatorExe @('--help') 'canonical Goal Context validator help' | Out-Null
    Invoke-Native $replayValidatorExe @('--help') 'PRR-002 replay validator help' | Out-Null
    Invoke-Native $collectorExe @('--unknown-option') 'collector invalid argument' $false | Out-Null
    Invoke-Native $syncExe @('--unknown-option') 'profile sync helper invalid argument' $false | Out-Null
    Invoke-Native $selectorExe @('--unknown-option') 'Goal Context selector invalid argument' $false | Out-Null

    $selectorRepository = Join-Path $tempRoot 'goal-context-repository'
    $selectorDocs = Join-Path $selectorRepository 'docs'
    New-Item -ItemType Directory -Path $selectorDocs -Force | Out-Null
    $goalContextFixture = Join-Path $repoRoot 'tests\pr-review-remediation\PRR-002\fixture\docs\goal-context-direct-review-notification.md'
    Copy-Item -LiteralPath $goalContextFixture -Destination $selectorDocs
    Invoke-Native $selectorExe @('--repository-root', $selectorRepository, '--search-root', 'docs', '--out', '.review/pr-123/goal-context-selection.json', '--validator', $canonicalValidatorPath) 'unique human-reviewed Goal Context selection' | Out-Null
    $selectionArtifactPath = Join-Path $selectorRepository '.review\pr-123\goal-context-selection.json'
    $selectionArtifact = Get-Content -Raw -LiteralPath $selectionArtifactPath | ConvertFrom-Json
    if ($selectionArtifact.selectionStatus -ne 'SELECTED' -or $selectionArtifact.lifecycleStatus -ne 'human-reviewed') {
        Add-Failure 'Goal Context selector did not record a confirmed unique selection.'
    }
    $expectedSelection = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'tests\pr-review-remediation\PRR-002\goal-context-selection.json') | ConvertFrom-Json
    if ($selectionArtifact.selectedPath -ne $expectedSelection.selectedPath -or
        $selectionArtifact.selectionMode -ne $expectedSelection.selectionMode -or
        $selectionArtifact.validation -ne $expectedSelection.validation -or
        $selectionArtifact.schemaVersion -ne 2 -or
        $selectionArtifact.validationContractVersion -ne $expectedSelection.validationContractVersion -or
        $selectionArtifact.validationMode -ne $expectedSelection.validationMode -or
        $selectionArtifact.contentSha256 -ne $expectedSelection.contentSha256) {
        Add-Failure 'Goal Context selector output does not match the committed PRR-002 selection contract.'
    }

    Copy-Item -LiteralPath $goalContextFixture -Destination (Join-Path $selectorDocs 'goal-context-second-candidate.md')
    $multipleSelection = Invoke-Native $selectorExe @('--repository-root', $selectorRepository, '--search-root', 'docs', '--out', '.review/multiple.json', '--validator', $canonicalValidatorPath) 'ambiguous Goal Context selection' $false
    if ($multipleSelection.Output -notmatch 'HUMAN_DECISION_REQUIRED.*multiple Goal Context candidates') { Add-Failure 'Goal Context selector did not fail closed on multiple candidates.' }
    Remove-Item -LiteralPath (Join-Path $selectorDocs 'goal-context-second-candidate.md') -Force

    $missingRepository = Join-Path $tempRoot 'missing-goal-context-repository'
    New-Item -ItemType Directory -Path $missingRepository -Force | Out-Null
    $missingSelection = Invoke-Native $selectorExe @('--repository-root', $missingRepository, '--search-root', '.', '--out', '.review/missing.json', '--validator', $canonicalValidatorPath) 'missing Goal Context selection' $false
    if ($missingSelection.Output -notmatch 'NO_GOAL_CONTEXT.*baseline \$pr-review-remediation') { Add-Failure 'Goal Context selector did not require an explicit baseline choice when no candidate exists.' }

    $invalidRepository = Join-Path $tempRoot 'invalid-goal-context-repository'
    $invalidDocs = Join-Path $invalidRepository 'docs'
    New-Item -ItemType Directory -Path $invalidDocs -Force | Out-Null
    $invalidPath = Join-Path $invalidDocs 'goal-context-invalid-document.md'
    (Get-Content -Raw -LiteralPath $goalContextFixture).Replace('## Desired outcome', '## Desired result') | Set-Content -LiteralPath $invalidPath
    $invalidSelection = Invoke-Native $selectorExe @('--repository-root', $invalidRepository, '--goal-context', 'docs/goal-context-invalid-document.md', '--out', '.review/invalid.json', '--validator', $canonicalValidatorPath) 'invalid Goal Context selection' $false
    if ($invalidSelection.Output -notmatch '(?s)INVALID_GOAL_CONTEXT.*Missing required heading: ## Desired outcome') { Add-Failure 'Goal Context selector accepted a missing required section.' }

    $draftRepository = Join-Path $tempRoot 'draft-goal-context-repository'
    $draftDocs = Join-Path $draftRepository 'docs'
    New-Item -ItemType Directory -Path $draftDocs -Force | Out-Null
    $draftPath = Join-Path $draftDocs 'goal-context-draft-review.md'
    (Get-Content -Raw -LiteralPath $goalContextFixture).Replace('status: human-reviewed', 'status: draft').Replace('sensitive_data_review: passed', 'sensitive_data_review: pending') | Set-Content -LiteralPath $draftPath
    $draftBlocked = Invoke-Native $selectorExe @('--repository-root', $draftRepository, '--goal-context', 'docs/goal-context-draft-review.md', '--out', '.review/draft-blocked.json', '--validator', $canonicalValidatorPath) 'draft Goal Context default gate' $false
    if ($draftBlocked.Output -notmatch 'requires an exact --goal-context path plus explicit --allow-draft') { Add-Failure 'Goal Context selector accepted draft content without explicit override.' }
    Invoke-Native $selectorExe @('--repository-root', $draftRepository, '--goal-context', 'docs/goal-context-draft-review.md', '--allow-draft', '--out', '.review/draft-selected.json', '--validator', $canonicalValidatorPath) 'explicit draft Goal Context override' | Out-Null
    $draftArtifact = Get-Content -Raw -LiteralPath (Join-Path $draftRepository '.review\draft-selected.json') | ConvertFrom-Json
    if (-not $draftArtifact.draftOverride -or $draftArtifact.selectionMode -ne 'user-specified-draft-override') { Add-Failure 'Goal Context selector did not record the explicit draft override.' }

    function Test-SelectorMutation([string]$Scenario, [string]$MutatedContent, [string]$ExpectedPattern) {
        $repository = Join-Path $tempRoot "selector-$Scenario"
        $docs = Join-Path $repository 'docs'
        New-Item -ItemType Directory -Path $docs -Force | Out-Null
        $path = Join-Path $docs "goal-context-$Scenario.md"
        Set-Content -LiteralPath $path -Value $MutatedContent -Encoding utf8 -NoNewline
        $result = Invoke-Native $selectorExe @(
            '--repository-root', $repository,
            '--goal-context', "docs/goal-context-$Scenario.md",
            '--out', '.review/selection.json',
            '--validator', $canonicalValidatorPath
        ) "selector negative fixture $Scenario" $false
        if ($result.Output -notmatch $ExpectedPattern) { Add-Failure "Goal Context selector did not reject $Scenario with canonical evidence." }
    }

    $reviewedContent = Get-Content -Raw -LiteralPath $goalContextFixture
    Test-SelectorMutation 'missing-mvp' ($reviewedContent.Replace('### MVP scope', '### MVP omitted')) 'Missing required heading: ### MVP scope'
    Test-SelectorMutation 'missing-reviewer' ([regex]::Replace($reviewedContent, '(?m)^- Reviewer:.*\r?\n', '', 1)) 'requires a non-pending Reviewer'
    Test-SelectorMutation 'missing-reviewed-at' ([regex]::Replace($reviewedContent, '(?m)^- Reviewed at:.*\r?\n', '', 1)) 'requires Reviewed at'
    Test-SelectorMutation 'confirmation-no' ($reviewedContent.Replace('- Desired outcome confirmed: Yes', '- Desired outcome confirmed: No')) 'Desired outcome confirmed: Yes'
    Test-SelectorMutation 'placeholder' ($reviewedContent + "`n<!-- unresolved -->") 'Unresolved template placeholder'
    $fakeSecret = 's' + 'k-' + ('x' * 24)
    Test-SelectorMutation 'credential' ($reviewedContent + "`napi_key = $fakeSecret") 'Potential exposed secret or credential'

    $junctionRepository = Join-Path $tempRoot 'selector-junction-repository'
    $junctionOutside = Join-Path $tempRoot 'selector-junction-outside'
    New-Item -ItemType Directory -Path $junctionRepository, $junctionOutside -Force | Out-Null
    Copy-Item -LiteralPath $goalContextFixture -Destination $junctionOutside
    New-Item -ItemType Junction -Path (Join-Path $junctionRepository 'docs') -Target $junctionOutside | Out-Null
    $junctionInput = Invoke-Native $selectorExe @('--repository-root', $junctionRepository, '--search-root', 'docs', '--out', 'selection.json', '--validator', $canonicalValidatorPath) 'selector junction input escape' $false
    if ($junctionInput.Output -notmatch 'canonical repository root') { Add-Failure 'Goal Context selector followed a junction outside the repository for input.' }

    $outputRepository = Join-Path $tempRoot 'selector-output-junction-repository'
    $outputDocs = Join-Path $outputRepository 'docs'
    $outputOutside = Join-Path $tempRoot 'selector-output-junction-outside'
    New-Item -ItemType Directory -Path $outputDocs, $outputOutside -Force | Out-Null
    Copy-Item -LiteralPath $goalContextFixture -Destination $outputDocs
    New-Item -ItemType Junction -Path (Join-Path $outputRepository '.review') -Target $outputOutside | Out-Null
    $junctionOutput = Invoke-Native $selectorExe @('--repository-root', $outputRepository, '--search-root', 'docs', '--out', '.review/selection.json', '--validator', $canonicalValidatorPath) 'selector junction output escape' $false
    if ($junctionOutput.Output -notmatch 'canonical repository root') { Add-Failure 'Goal Context selector followed a junction outside the repository for output.' }

    $prr002Root = Join-Path $repoRoot 'tests\pr-review-remediation\PRR-002'
    Invoke-Native $replayValidatorExe @('--fixture-root', $prr002Root, '--format', 'json') 'PRR-002 deterministic replay' | Out-Null

    function Update-ReplayArtifactHash([string]$ScenarioRoot, [string]$Role) {
        $runPath = Join-Path $ScenarioRoot 'run.json'
        $run = Get-Content -Raw -LiteralPath $runPath | ConvertFrom-Json -Depth 100
        $artifact = @($run.artifacts | Where-Object role -eq $Role)
        if ($artifact.Count -ne 1) { throw "Replay mutation artifact role is not unique: $Role" }
        $artifactPath = Join-Path $ScenarioRoot $artifact[0].path
        $normalized = [IO.File]::ReadAllText($artifactPath).Replace("`r`n", "`n").Replace("`r", "`n")
        $artifact[0].normalizedSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($normalized))).ToLowerInvariant()
        $run | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $runPath -Encoding utf8 -NoNewline
    }

    function Test-ReplayMutation([string]$Scenario, [scriptblock]$Mutation, [string]$ExpectedPattern) {
        $scenarioRoot = Join-Path $tempRoot "prr-002-$Scenario"
        Copy-Item -LiteralPath $prr002Root -Destination $scenarioRoot -Recurse
        & $Mutation $scenarioRoot
        $result = Invoke-Native $replayValidatorExe @('--fixture-root', $scenarioRoot, '--format', 'json') "PRR-002 negative replay $Scenario" $false
        if ($result.Output -notmatch $ExpectedPattern) { Add-Failure "PRR-002 negative replay did not expose the expected $Scenario failure." }
    }

    Test-ReplayMutation 'identity' {
        param($root)
        $path = Join-Path $root 'local-review-findings.md'
        (Get-Content -Raw -LiteralPath $path).Replace('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'cccccccccccccccccccccccccccccccccccccccc') | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
        Update-ReplayArtifactHash $root 'local-findings'
    } 'local findings does not contain exact contract value'
    Test-ReplayMutation 'collector-schema' {
        param($root)
        $path = Join-Path $root 'fixture/.review/pr-123/review-context.json'
        $context = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
        $context.schemaVersion = '0.9'
        $context | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
        Update-ReplayArtifactHash $root 'review-context'
    } 'review-context schemaVersion mismatch'
    Test-ReplayMutation 'source-coverage' {
        param($root)
        $path = Join-Path $root 'run.json'
        $run = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
        $run.sourceBindings = @($run.sourceBindings | Where-Object sourceId -ne 'pr-comment:2700')
        $run | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
    } 'Review source is not covered: pr-comment:2700'
    Test-ReplayMutation 'apply-mapping' {
        param($root)
        $path = Join-Path $root 'review-plan.md'
        (Get-Content -Raw -LiteralPath $path).Replace('SI-002 / AC-002', 'SI-999 / AC-999') | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
        Update-ReplayArtifactHash $root 'review-plan'
    } 'Apply finding has invalid scope/acceptance mapping'
    Test-ReplayMutation 'duplicate-reference' {
        param($root)
        $path = Join-Path $root 'review-plan.md'
        (Get-Content -Raw -LiteralPath $path).Replace('| LR-001 | N/A | SI-001 / AC-001 |', '| UNKNOWN-001 | N/A | SI-001 / AC-001 |') | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
        Update-ReplayArtifactHash $root 'review-plan'
    } 'unknown duplicate/conflict target'
    Test-ReplayMutation 'goal-context-hash' {
        param($root)
        $path = Join-Path $root 'run.json'
        $run = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 100
        $run.goalContext.normalizedSha256 = '0000000000000000000000000000000000000000000000000000000000000000'
        $run | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
    } 'Goal Context hash mismatch'
    Test-ReplayMutation 'plan-path' {
        param($root)
        $path = Join-Path $root 'adaptive-turn-input.txt'
        (Get-Content -Raw -LiteralPath $path).Replace('tests/pr-review-remediation/PRR-002/review-plan.md', 'tests/pr-review-remediation/PRR-002/other-plan.md') | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
        Update-ReplayArtifactHash $root 'adaptive-input'
    } 'Adaptive input does not contain exact contract value'
    Test-ReplayMutation 'notification-pr' {
        param($root)
        $path = Join-Path $root 'completion-notification.txt'
        (Get-Content -Raw -LiteralPath $path).Replace('/pull/123', '/pull/124') | Set-Content -LiteralPath $path -Encoding utf8 -NoNewline
        Update-ReplayArtifactHash $root 'completion-notification'
    } 'notification result URI mismatch'
    Test-ReplayMutation 'artifact-hash' {
        param($root)
        Add-Content -LiteralPath (Join-Path $root 'local-review-findings.md') -Value 'tampered'
    } 'artifact hash local-findings mismatch'

    function Invoke-Fixture([string]$Scenario, [string[]]$ExtraArgs = @(), [bool]$ExpectSuccess = $true) {
        $scenarioRoot = Join-Path $tempRoot $Scenario
        New-Item -ItemType Directory -Path $scenarioRoot | Out-Null
        $env:FAKE_GH_SCENARIO = $Scenario
        $env:FAKE_GH_STATE = Join-Path $scenarioRoot 'state.txt'
        $fixtureRepository = if ($Scenario -eq 'prr-002') { 'fixture/goal-context-review' } else { 'example/repo' }
        $arguments = @('--repo', $fixtureRepository, '--pr', '123', '--out', $scenarioRoot, '--gh-executable', $fakeExe) + $ExtraArgs
        return Invoke-Native $collectorExe $arguments "collector fixture $Scenario" $ExpectSuccess
    }

    function Get-CollectorProjection([string]$Path) {
        $context = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -Depth 100
        $context.PSObject.Properties.Remove('generatedAt')
        foreach ($property in @('startedAt', 'completedAt', 'elapsedSeconds')) {
            $context.copilotReviewWait.PSObject.Properties.Remove($property)
        }
        return ($context | ConvertTo-Json -Depth 100 -Compress)
    }

    Invoke-Fixture 'prr-002' @('--no-wait-for-copilot') | Out-Null
    $generatedReplayRoot = Join-Path $tempRoot 'prr-002'
    $generatedProjection = Get-CollectorProjection (Join-Path $generatedReplayRoot 'review-context.json')
    $committedProjection = Get-CollectorProjection (Join-Path $prr002Root 'fixture/.review/pr-123/review-context.json')
    if ($generatedProjection -cne $committedProjection) {
        $generatedProjectionHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($generatedProjection))).ToLowerInvariant()
        $committedProjectionHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($committedProjection))).ToLowerInvariant()
        Add-Failure "PRR-002 review-context drifted from the shared collector canonical projection (generated $generatedProjectionHash, committed $committedProjectionHash)."
    }
    $generatedPatch = (Get-Content -Raw -LiteralPath (Join-Path $generatedReplayRoot 'pr-diff.patch')).Replace("`r`n", "`n").Replace("`r", "`n")
    $committedPatch = (Get-Content -Raw -LiteralPath (Join-Path $prr002Root 'fixture/.review/pr-123/pr-diff.patch')).Replace("`r`n", "`n").Replace("`r", "`n")
    if ($generatedPatch -cne $committedPatch) {
        Add-Failure 'PRR-002 remote patch drifted from the shared collector fake-gh input.'
    }

    Invoke-Fixture 'ready' @('--no-wait-for-copilot') | Out-Null
    $ready = Read-Context (Join-Path $tempRoot 'ready')
    if ($null -ne $ready) {
        if ($ready.target.baseRefOid -ne 'base-001' -or $ready.target.headRefOid -ne 'head-001') { Add-Failure 'ready fixture did not preserve base/head identity' }
        if ($ready.copilotReviewWait.waitStatus -ne 'disabled') { Add-Failure 'ready fixture waitStatus must be disabled' }
        if ($ready.copilotReviewWait.observedReviewState -ne 'reviewAndInline') { Add-Failure 'ready fixture observation must be reviewAndInline' }
        if ($ready.sources.checks.Count -ne 3) { Add-Failure 'ready fixture must preserve successful, failing, and pending checks' }
        if ($ready.sources.reviews.Count -ne 1 -or $ready.sources.issueComments.Count -ne 1) { Add-Failure 'paginated fixture sources were not normalized' }
        if ($ready.sources.reviews[0].sourceId -notmatch '^review:\d+$') { Add-Failure 'ready fixture review has no stable sourceId' }
        if ($ready.sources.issueComments[0].sourceId -notmatch '^pr-comment:\d+$') { Add-Failure 'ready fixture PR comment has no stable sourceId' }
        if ($ready.sources.inlineComments[0].sourceId -notmatch '^inline-comment:\d+$') { Add-Failure 'ready fixture inline comment has no stable sourceId' }
        if (@($ready.sources.checks | Where-Object sourceId -notmatch '^check:(?:run:)?[a-z0-9]+$').Count -gt 0) { Add-Failure 'ready fixture check has no stable sourceId' }
        $allSourceIds = @($ready.sources.reviews.sourceId) + @($ready.sources.issueComments.sourceId) + @($ready.sources.inlineComments.sourceId) + @($ready.sources.checks.sourceId)
        if (@($allSourceIds | Select-Object -Unique).Count -ne $allSourceIds.Count) { Add-Failure 'ready fixture source IDs are not unique' }
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

    foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml', 'high-implementation-starter.toml', 'standard-implementation-completer.toml')) {
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
    foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml')) {
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
    Set-Content -LiteralPath (Join-Path $apmProfileRoot 'purpose-reviewer.toml') -NoNewline -Value @'
name = "purpose-reviewer"
description = "Evaluate whether a confirmed PR diff achieves the selected Goal Context without duplicating code-quality review or editing repository state."
developer_instructions = "# Purpose Reviewer\n\nPreserved APM contract with an escaped \"quoted value\"."
'@
    Set-Content -LiteralPath (Join-Path $apmProfileRoot 'review-planner.toml') -NoNewline -Value @'
name = "review-planner"
description = "Consolidate local Codex, optional Goal Context purpose findings, GitHub Copilot reviews, PR comments, and checks into an Adaptive-ready remediation plan without implementing fixes."
developer_instructions = "# Review Planner\n\nPreserved APM contract with an escaped \"quoted value\"."
'@
    Invoke-Native $syncExe @($apmScratch) 'APM-generated review profile completion' | Out-Null
    foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml')) {
        $content = Get-Content -Raw -LiteralPath (Join-Path $apmProfileRoot $profile)
        if ($content -notmatch '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$') { Add-Failure "APM-generated profile did not receive a concrete model: $profile" }
        if ($content -notmatch '(?m)^sandbox_mode\s*=\s*"read-only"\s*$') { Add-Failure "APM-generated profile did not receive a read-only sandbox: $profile" }
        if ($content -notmatch 'Preserved APM contract with an escaped \\"quoted value\\"') { Add-Failure "Review helper replaced the APM-generated developer instructions: $profile" }
    }
    Invoke-Native $syncExe @($apmScratch, '--remove') 'completed APM review profile removal' | Out-Null
    foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml')) {
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
