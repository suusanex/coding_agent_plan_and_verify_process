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
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-review-cycle.cs',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/purpose-review-findings.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/round-assessment.example.json',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-result.example.json',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/templates/review-round-result.example.json',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/design.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/usage.md',
    'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/troubleshooting.md',
    'apm-packages/pr-review-remediation/codex-agents/local-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/purpose-reviewer.toml',
    'apm-packages/pr-review-remediation/codex-agents/review-planner.toml',
    'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs',
    'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-agent-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-prr-002-contract.cs',
    'apm-packages/pr-review-remediation/scripts/validate-prr-003-contract.ps1',
    'apm-packages/pr-review-remediation/scripts/validate-same-parent-review.ps1',
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
    'tests/pr-review-remediation/PRR-003/collector-snapshots/round-001-review-context.json',
    'tests/pr-review-remediation/PRR-003/collector-snapshots/round-002-review-context.json',
    'tests/pr-review-remediation/PRR-003/collector-snapshots/round-003-review-context.json',
    'tests/pr-review-remediation/manual-model-smoke/README.md',
    'tests/pr-review-remediation/manual-model-smoke/result-template.md'
)) {
    Assert-Exists $path
}

Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^name:\s*pr-review-remediation\s*$' 'package name'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' '(?m)^version:\s*0\.5\.0\s*$' 'package version'
Assert-NotContains 'apm-packages/pr-review-remediation/apm.yml' 'goal-context-authoring' 'Goal Context authoring-path dependency in canonical review package'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/local-reviewer\.agent\.md' 'canonical local reviewer dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/purpose-reviewer\.agent\.md' 'canonical purpose reviewer dependency'
Assert-Contains 'apm-packages/pr-review-remediation/apm.yml' 'path:\s*\.github/agents/review-planner\.agent\.md' 'canonical review planner dependency'
Assert-NotContains 'apm-packages/pr-review-remediation/apm.yml' 'adaptive-implementation-execution|high-implementation-starter|standard-implementation-completer' 'canonical package Adaptive dependency'

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
Assert-Contains $skill 'gh pr edit 123 --repo owner/name --add-reviewer @copilot' 'baseline explicit Copilot review request'
Assert-Contains $skill 'Phase 2はcanonical same-parent flowの導入要件ではありません' 'baseline optional Adaptive boundary'
Assert-Contains $skill 'templates/local-review-findings\.md' 'relative local findings template'
Assert-Contains $skill 'templates/review-plan\.md' 'relative review plan template'
$sharedPlanTemplate = 'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/templates/review-plan.md'
Assert-Contains $sharedPlanTemplate 'Multi-round role threads: fixed / N/A for single-round' 'fixed multi-round role task contract'
Assert-Contains $sharedPlanTemplate '基礎版のsingle-round利用ではrole thread IDを要求せず' 'single-round role binding non-requirement'
Assert-Contains $sharedPlanTemplate '固定taskを再開できない場合は、新taskへ自動移管せず`BLOCKED`' 'fixed role task fail-closed boundary'

$goalSkill = 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md'
Assert-Contains $goalSkill 'name:\s*goal-context-pr-review' 'Goal Context Skill name'
Assert-Contains $goalSkill 'scripts/select-goal-context\.cs' 'Goal Context selector asset'
Assert-Contains $goalSkill 'scripts/manage-same-parent-review\.cs' 'canonical same-parent manager asset'
Assert-Contains $goalSkill 'Complete.*HumanDecisionRequired.*Blocked' 'canonical terminal verdict vocabulary'
Assert-Contains $goalSkill 'purpose-reviewer' 'independent purpose reviewer'
Assert-Contains $goalSkill 'Round 1.*GitHub Copilot sources.*local reviewer.*purpose reviewer' 'full first-round mode'
Assert-Contains $goalSkill 'Rounds 2 and 3: purpose-only' 'purpose-only later-round mode'
Assert-Contains $goalSkill '唯一のwrite ownerは、このSkillを開始した元の親agent' 'original parent write ownership'
Assert-Contains $goalSkill '別top-level Review / Implementation task、thread ID、artifact path、hash、JSON、result reference' 'no manual messenger normal path'
Assert-Contains $goalSkill '自動round 4' 'automatic round 4 prohibition'
Assert-Contains $goalSkill '--no-wait-for-copilot' 'later-round Copilot wait suppression'
Assert-Contains $goalSkill 'Issue本文はGoal Contextの代替になりません' 'no Issue-only purpose fallback'
Assert-Contains $goalSkill 'historical compatibility utility' 'fixed two-task historical boundary'
Assert-Contains $goalSkill 'thread-id.*turn-id.*生成・推測・受領しません' 'XC-001 callback identity exclusion'
Assert-Contains $goalSkill '自然言語のfree-form text' 'free-form Goal Context contract'
Assert-Contains $goalSkill '\.agents/skills/goal-context-pr-review/scripts/manage-same-parent-review\.cs' 'installed Skill start path'
Assert-Contains $goalSkill 'completion-notification\.txt.*raw text.*最終assistant messageの末尾' 'terminal notification handoff to last assistant message'
Assert-Contains $goalSkill 'gh pr edit <number> --add-reviewer @copilot' 'canonical explicit Copilot review request'
Assert-Contains $goalSkill 'reviewOnly.*reviewAndInline.*どちらも受理' 'collector-complete no-inline acceptance'
Assert-Contains 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/references/design.md' 'Canonical responsibility address' 'same-parent production address decision'
Assert-Contains '.github/agents/purpose-reviewer.agent.md' '実装担当および`local-reviewer`から独立' 'purpose reviewer independence'
Assert-Contains '.github/agents/purpose-reviewer.agent.md' 'コード上のbug.*`local-reviewer`' 'purpose and code quality separation'
$sameParentManager = 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-same-parent-review.cs'
Assert-Contains $sameParentManager '(?m)^#:property TargetFramework=net10\.0\s*$' 'same-parent File-based App target framework'
Assert-Contains $sameParentManager 'ResolveTargetReadyPullRequest' 'branch-aware Ready PR resolution'
Assert-Contains $sameParentManager 'ParsePullRequestReference' 'explicit PR number or URL resolution'
Assert-Contains $sameParentManager 'RequestCopilotReview' 'round 1 Copilot review request'
Assert-Contains $sameParentManager '"--add-reviewer", "@copilot"' 'official Copilot reviewer request arguments'
Assert-Contains $sameParentManager 'CopilotIsComplete' 'collector completion authority'
Assert-Contains $sameParentManager 'MaximumRounds = 3' 'same-parent maximum of three rounds'
Assert-Contains $sameParentManager 'github-copilot.*local-reviewer.*purpose-reviewer' 'round 1 exact source coverage'
Assert-Contains $sameParentManager 'purpose-only round must not contain local-reviewer output' 'purpose-only local reviewer rejection'
Assert-Contains $sameParentManager 'Prior assessments must cover every previously active tracking ID exactly once' 'explicit prior finding assessment'
Assert-Contains $sameParentManager 'The current PR head has not changed after remediation' 'new current head gate'
Assert-Contains $sameParentManager 'Terminal projection must contain only schema/process/status/title/current PR URI' 'XC-001 safe projection validation'
Assert-Contains $sameParentManager 'Terminal projection must not contain callback identity' 'XC-001 identity exclusion'
Assert-NotContains $sameParentManager 'review-thread-id|implementation-thread-id|adaptive-result-reference|override-maximum-rounds' 'fixed task and round 4 inputs in canonical manager'
$cycleManager = 'apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/scripts/manage-review-cycle.cs'
Assert-Contains $cycleManager '(?m)^#:property TargetFramework=net10\.0\s*$' 'multi-round File-based App target framework'
Assert-Contains $cycleManager 'DefaultMaximumRounds = 3' 'default maximum of three rounds'
Assert-Contains $cycleManager 'SchemaVersion = 2' 'multi-round schema version 2'
Assert-Contains $cycleManager 'PurposeOnlyReviewMode = "purpose-only"' 'purpose-only mode vocabulary'
Assert-Contains $cycleManager 'Purpose-only review round must not include local-findings' 'later-round local artifact rejection'
Assert-Contains $cycleManager 'Purpose-only external source must be retained as reasoned noAction' 'later-round external source audit-only rule'
Assert-Contains $cycleManager 'Prior Finding Assessment coverage mismatch' 'prior active finding assessment coverage'
Assert-Contains $cycleManager 'schemaVersion 1 is read-only historical evidence' 'legacy cycle append rejection'
Assert-Contains $cycleManager '(?s)"new".*"persistent".*"resolved".*"reopened"' 'finding transition vocabulary'
Assert-Contains $cycleManager '(?s)READY_FOR_ADAPTIVE_IMPLEMENTATION.*HUMAN_DECISION_REQUIRED' 'round-limit verdict transition'
Assert-Contains $cycleManager 'SourceCoverageEntry' 'per-round source coverage contract'
Assert-Contains $cycleManager 'ValidateArtifactContents' 'role-aware artifact content cross-validation'
Assert-Contains $cycleManager 'review-context repository' 'review-context identity cross-validation'
Assert-Contains $cycleManager 'review-result finding delta' 'planner result delta cross-validation'
Assert-Contains $cycleManager 'ValidateReviewPlan' 'Adaptive review plan content validation'
Assert-Contains $cycleManager 'Review plan active finding mapping mismatch' 'review plan active finding mapping'
Assert-Contains $cycleManager 'scope ID sets must match exactly' 'intent and ordered scope exact matching'
Assert-Contains $cycleManager 'acceptance ID sets must match exactly' 'intent and ordered acceptance exact matching'
Assert-Contains $cycleManager 'Source-to-tracking mapping mismatch' 'bidirectional source-to-tracking validation'
Assert-Contains $cycleManager 'ClassifySourceHeadRelationship' 'current historical and unknown source classification'
Assert-Contains $cycleManager 'review-context remote patch path' 'collector remote patch path binding'
Assert-Contains $cycleManager 'Goal Context selection schema version' 'historical Goal Context selection schema validation'
Assert-Contains $cycleManager 'strict Goal Context lifecycle' 'historical strict Goal Context lifecycle validation'
Assert-Contains $cycleManager 'TryParseExact' 'strict invariant timestamp parsing'
Assert-Contains $cycleManager 'explicit Z or UTC offset' 'explicit timestamp timezone requirement'
Assert-Contains $cycleManager 'ResolvePhysicalPath' 'symlink and junction physical path containment'
Assert-Contains $cycleManager 'must be resolved with a validated approved plan before Adaptive execution' 'pending human decision pre-Adaptive gate'
Assert-Contains $cycleManager 'Review Thread and Implementation Thread must be different Codex tasks' 'distinct role task identity'
Assert-Contains $cycleManager 'start requires cycle, repository, PR, Goal Context identity, base/head OID, started-at, review-thread-id, and implementation-thread-id' 'both role task IDs required at cycle start'
Assert-Contains $cycleManager 'Equal\("Implementation Thread ID", cycle\.RoleThreads\.Implementation\.ThreadId, implementationThreadId\)' 'fixed Implementation Thread identity'
Assert-Contains $cycleManager 'Equal\("Review Thread ID", cycle\.RoleThreads\.Review\.ThreadId, reviewThreadId\)' 'fixed Review Thread identity'
Assert-Contains $cycleManager 'ThreadUri' 'manager-derived Codex task URI'
Assert-NotContains $cycleManager 'bind-thread|rebind-thread|portable-handoff|threadMode|binding history' 'removed role task fallback implementation'
Assert-Contains $cycleManager 'Maximum-round override is accepted only for round 4 or later' 'early override rejection'
Assert-Contains $cycleManager '"resolve" => ReviewCycleManager.Resolve' 'independent human decision resolution command'
Assert-Contains $cycleManager 'verdict is "REVIEW_COMPLETE" or "HUMAN_DECISION_REQUIRED"' 'human decision no-plan verdict branch'
Assert-Contains $cycleManager 'must not include an executable Adaptive review-plan artifact' 'human decision executable plan rejection'
Assert-Contains $cycleManager 'ApprovedPlanNormalizedSha256' 'approved plan hash binding'
Assert-Contains $cycleManager 'APPROVED_FOR_ADAPTIVE_IMPLEMENTATION' 'post-decision Adaptive approval state'
Assert-Contains $cycleManager 'startedAt precedes the human decision approval' 'human approval chronology gate'
Assert-Contains $cycleManager 'ValidateCycle\(cyclePath, cycle, requireCompletedCurrentRound: false\);\s*SaveCycle' 'pre-save final state validation'
Assert-NotContains $cycleManager 'Process\.Start|adaptive-implementation-execution|completion-notification-decorator' 'internal process orchestration'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'Validate multi-round replay and symlink containment on Linux' 'Linux symlink containment evidence'
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
Assert-Contains $reviewPlan 'HUMAN_DECISION_REQUIRED.*Adaptive handoffも出しません' 'human decision no-handoff template guidance'
Assert-Contains '.github/agents/review-planner.agent.md' 'READY_FOR_ADAPTIVE_IMPLEMENTATION \| REVIEW_COMPLETE \| HUMAN_DECISION_REQUIRED \| BLOCKED' 'multi-round planner verdict vocabulary'
Assert-Contains '.github/agents/review-planner.agent.md' '空のAdaptive向けplanを生成しない' 'no empty Adaptive plan rule'
Assert-Contains '.github/agents/review-planner.agent.md' 'HUMAN_DECISION_REQUIRED.*実行可能なreview plan.*Adaptive開始promptを出力しない' 'planner human decision handoff gate'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'deterministic-multi-round-replay' 'PRR-003 evidence mode'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'HUMAN_DECISION_REQUIRED' 'PRR-003 maximum-round verdict'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'collector-realistic-convergence' 'PRR-003 real multi-round collector path'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'current.*historical.*unknown' 'PRR-003 source head relationships'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' '"reviewModes":\s*\["full",\s*"purpose-only",\s*"purpose-only"\]' 'PRR-003 round review mode sequence'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'purpose-only-local-artifact' 'PRR-003 later-round local artifact mutation'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'missing-prior-finding-assessment' 'PRR-003 prior assessment mutation'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'reviewThreadContinuity.*same-task' 'PRR-003 Review Thread continuity'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'implementationThreadContinuity.*same-task' 'PRR-003 Implementation Thread continuity'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'implementationThreadIncludesInitialImplementation.*true' 'PRR-003 initial implementation continuity'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'missing-implementation-thread-id' 'PRR-003 required Implementation Thread mutation'
Assert-NotContains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'late-implementation-thread-binding|portable-cold-start|incomplete-thread-rebind|thread-history-overwrite|portable-without-approval' 'removed fallback scenarios'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'adaptive-before-decision' 'PRR-003 pre-approval Adaptive rejection'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'resolve-with-adaptive-result' 'PRR-003 resolution rejects post-Adaptive evidence'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'approved-plan-hash' 'PRR-003 approved plan tamper rejection'
Assert-Contains 'tests/pr-review-remediation/PRR-003/scenarios.json' 'start-before-decision-approval' 'PRR-003 human approval chronology rejection'
Assert-Contains 'tests/pr-review-remediation/PRR-003/README.md' '外部model.*実行しません' 'PRR-003 external-model disclosure'
Assert-Contains 'tests/pr-review-remediation/PRR-003/README.md' 'Issue #61 acceptance coverage' 'Issue acceptance contract matrix'

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
Assert-Contains $collector '\["isComplete"\]\s*=\s*IsComplete' 'collector completion output'
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
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' '(?s)pull_request:.*apm-packages/goal-context-authoring/\*\*.*push:.*apm-packages/goal-context-authoring/\*\*' 'Goal Context Authoring package path filters for pull request and push events'
Assert-Contains '.github/workflows/validate-pr-review-remediation.yml' 'git diff --check origin/main\.\.\.HEAD' 'branch-range whitespace gate'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'apm install|@\(''install''' 'real remote APM install command'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' '\$installedReviewHelper.*README review profile synchronization' 'consumer command uses installed module review helper'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'installed canonical same-parent start from empty consumer repository' 'consumer repository same-parent start smoke'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'Round1Reviewing' 'consumer repository startability outcome'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'Assert-Absent.*adaptive-implementation-execution' 'canonical consumer Adaptive Skill exclusion'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'Assert-NotContains.*adaptive-implementation-execution.*APM lock' 'canonical consumer Adaptive lock exclusion'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' 'finally\s*\{' 'remote smoke cleanup boundary'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/validate-pr-review-remediation-apm-smoke.ps1' '\$global:LASTEXITCODE\s*=\s*0' 'Linux success exit reset after expected native failures'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1' 'ConfirmExternalModelPayload' 'actual agent smoke external-payload consent gate'
Assert-Contains 'apm-packages/pr-review-remediation/scripts/run-pr-review-remediation-agent-smoke.ps1' 'DescribePayload' 'no-send payload description mode'
foreach ($documentation in @(
    'README.md',
    'apm-packages/pr-review-remediation/.apm/skills/pr-review-remediation/references/usage.md'
)) {
    Assert-Contains $documentation '(?s)run-pr-review-remediation-agent-smoke\.ps1.*-DescribePayload.*run-pr-review-remediation-agent-smoke\.ps1.*-ConfirmExternalModelPayload' 'payload preview and authorized smoke commands'
}
Assert-Contains 'tests/pr-review-remediation/PRR-001/README.md' 'customAgentSpawnObserved.*false' 'actual execution disclosure'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' '(?s)(?=.*disposable target repository)(?=.*external model payload)(?=.*local-reviewer)(?=.*purpose-reviewer)(?=.*同じ親task)(?=.*元のparentだけが修正)(?=.*purpose-only)(?=.*HumanDecisionRequired)' 'same-parent real-model smoke boundary and acceptance sequence'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' '(?s)(?=.*人手での作業が必要)(?=.*notification runtime install)(?=.*real Windows/Codex callback count)(?=.*ManualOnly)' 'manual approval and notification evidence boundary'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' '別top-level Review/Implementation taskを作成せず、thread ID、cycle path、hash、JSON、result referenceを転記しません' 'no manual messenger smoke invocation'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' '(?s)通常のCodex task.*このタスクを開く.*completion-notification\.txt.*結果を開く.*reviewer subagent' 'manual notification end-to-end steps'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' 'automatic round 4はありません|round 4を自動開始しない' 'manual smoke round cap'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/README.md' 'unsupported callback hierarchy filterを推測しない' 'manual callback hierarchy boundary'
Assert-Contains 'tests/pr-review-remediation/manual-model-smoke/result-template.md' '(?s)(?=.*Same original implementation parent used)(?=.*GitHub Copilot review request issued successfully)(?=.*Collector completion/state)(?=.*Reviewer roles executed)(?=.*Original parent was sole write owner)(?=.*Round 2/3 local reviewer absent)(?=.*Automatic round 4 absent)(?=.*User-visible notification count)' 'same-parent real-model evidence checklist'

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
$sameParentValidator = Join-Path $packageRoot 'scripts\validate-same-parent-review.ps1'
Invoke-Native 'pwsh' @('-NoProfile', '-File', $sameParentValidator) 'canonical same-parent deterministic replay' | Out-Null

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-review-remediation-validation-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $collectorOut = Join-Path $tempRoot 'collector'
    $fakeOut = Join-Path $tempRoot 'fake-gh'
    $syncOut = Join-Path $tempRoot 'sync'
    $selectorOut = Join-Path $tempRoot 'selector'
    $sameParentOut = Join-Path $tempRoot 'same-parent-manager'
    $replayValidatorOut = Join-Path $tempRoot 'prr-002-replay-validator'
    $adaptiveSyncOut = Join-Path $tempRoot 'adaptive-sync'
    $collectorPath = Join-Path $repoRoot $collector
    $fakePath = Join-Path $packageRoot 'tests\fixtures\fake-gh.cs'
    $syncPath = Join-Path $packageRoot 'scripts\sync-pr-review-remediation-local.cs'
    $selectorPath = Join-Path $packageRoot '.apm\skills\goal-context-pr-review\scripts\select-goal-context.cs'
    $sameParentPath = Join-Path $packageRoot '.apm\skills\goal-context-pr-review\scripts\manage-same-parent-review.cs'
    $replayValidatorPath = Join-Path $packageRoot 'scripts\validate-prr-002-contract.cs'
    $adaptiveSyncPath = Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution\scripts\install-adaptive-implementation-local.cs'

    Invoke-Native 'dotnet' @('publish', $collectorPath, '--output', $collectorOut, '--disable-build-servers') 'collector publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $fakePath, '--output', $fakeOut, '--disable-build-servers') 'fake gh publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $syncPath, '--output', $syncOut, '--disable-build-servers') 'profile sync helper publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $selectorPath, '--output', $selectorOut, '--disable-build-servers') 'Goal Context selector publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $sameParentPath, '--output', $sameParentOut, '--disable-build-servers') 'same-parent manager publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $replayValidatorPath, '--output', $replayValidatorOut, '--disable-build-servers') 'PRR-002 replay validator publish' | Out-Null
    Invoke-Native 'dotnet' @('publish', $adaptiveSyncPath, '--output', $adaptiveSyncOut, '--disable-build-servers') 'Adaptive profile helper publish' | Out-Null

    $collectorExe = Join-Path $collectorOut 'collect-pr-review-context.exe'
    $fakeExe = Join-Path $fakeOut 'fake-gh.exe'
    $syncExe = Join-Path $syncOut 'sync-pr-review-remediation-local.exe'
    $selectorExe = Join-Path $selectorOut 'select-goal-context.exe'
    $sameParentExe = Join-Path $sameParentOut 'manage-same-parent-review.exe'
    $replayValidatorExe = Join-Path $replayValidatorOut 'validate-prr-002-contract.exe'
    $adaptiveSyncExe = Join-Path $adaptiveSyncOut 'install-adaptive-implementation-local.exe'
    foreach ($exe in @($collectorExe, $fakeExe, $syncExe, $selectorExe, $sameParentExe, $replayValidatorExe, $adaptiveSyncExe)) {
        if (-not (Test-Path -LiteralPath $exe)) {
            Add-Failure "Missing published executable: $exe"
        }
    }

    Invoke-Native $collectorExe @('--help') 'collector help' | Out-Null
    Invoke-Native $syncExe @('--help') 'profile sync helper help' | Out-Null
    Invoke-Native $selectorExe @('--help') 'Goal Context selector help' | Out-Null
    Invoke-Native $sameParentExe @('--help') 'same-parent manager help' | Out-Null
    Invoke-Native $replayValidatorExe @('--help') 'PRR-002 replay validator help' | Out-Null
    Invoke-Native $collectorExe @('--unknown-option') 'collector invalid argument' $false | Out-Null
    Invoke-Native $syncExe @('--unknown-option') 'profile sync helper invalid argument' $false | Out-Null
    Invoke-Native $selectorExe @('--unknown-option') 'Goal Context selector invalid argument' $false | Out-Null

    $selectorRepository = Join-Path $tempRoot 'goal-context-repository'
    $selectorDocs = Join-Path $selectorRepository 'docs'
    New-Item -ItemType Directory -Path $selectorDocs -Force | Out-Null
    $goalContextFixture = Join-Path $selectorDocs 'goal-context-free-form.md'
    Set-Content -LiteralPath $goalContextFixture -Encoding utf8 -NoNewline -Value 'People should finish review and remediation without a separate handoff task. This fixture intentionally has no headings or metadata.'
    Invoke-Native $selectorExe @('--repository-root', $selectorRepository, '--search-root', 'docs', '--out', '.review/pr-123/goal-context-selection.json') 'unique free-form Goal Context selection' | Out-Null
    $selectionArtifactPath = Join-Path $selectorRepository '.review\pr-123\goal-context-selection.json'
    $selectionArtifact = Get-Content -Raw -LiteralPath $selectionArtifactPath | ConvertFrom-Json
    if ($selectionArtifact.selectionStatus -ne 'SELECTED' -or
        $selectionArtifact.selectionMode -ne 'auto-unique' -or
        $selectionArtifact.validation -ne 'PASS' -or
        $selectionArtifact.validationContract -ne 'readable-free-form' -or
        $selectionArtifact.schemaVersion -ne 3 -or
        $selectionArtifact.contentSha256 -notmatch '^[a-f0-9]{64}$') {
        Add-Failure 'Goal Context selector did not record the free-form selection contract.'
    }

    Copy-Item -LiteralPath $goalContextFixture -Destination (Join-Path $selectorDocs 'goal-context-second-candidate.md')
    $multipleSelection = Invoke-Native $selectorExe @('--repository-root', $selectorRepository, '--search-root', 'docs', '--out', '.review/multiple.json') 'ambiguous Goal Context selection' $false
    if ($multipleSelection.Output -notmatch 'HUMAN_DECISION_REQUIRED.*multiple Goal Context candidates') { Add-Failure 'Goal Context selector did not fail closed on multiple candidates.' }
    Remove-Item -LiteralPath (Join-Path $selectorDocs 'goal-context-second-candidate.md') -Force

    $missingRepository = Join-Path $tempRoot 'missing-goal-context-repository'
    New-Item -ItemType Directory -Path $missingRepository -Force | Out-Null
    $missingSelection = Invoke-Native $selectorExe @('--repository-root', $missingRepository, '--search-root', '.', '--out', '.review/missing.json') 'missing Goal Context selection' $false
    if ($missingSelection.Output -notmatch 'NO_GOAL_CONTEXT.*baseline \$pr-review-remediation') { Add-Failure 'Goal Context selector did not require an explicit baseline choice when no candidate exists.' }

    $explicitRepository = Join-Path $tempRoot 'explicit-free-form-repository'
    New-Item -ItemType Directory -Path $explicitRepository -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $explicitRepository 'purpose-notes.txt') -Encoding utf8 -NoNewline -Value 'A one-paragraph arbitrary filename is valid Goal Context.'
    Invoke-Native $selectorExe @('--repository-root', $explicitRepository, '--goal-context', 'purpose-notes.txt', '--out', '.review/explicit.json') 'explicit arbitrary Goal Context file' | Out-Null
    $explicitArtifact = Get-Content -Raw -LiteralPath (Join-Path $explicitRepository '.review\explicit.json') | ConvertFrom-Json
    if ($explicitArtifact.selectionMode -ne 'user-specified') { Add-Failure 'Explicit arbitrary Goal Context did not use user-specified selection mode.' }

    $emptyRepository = Join-Path $tempRoot 'empty-goal-context-repository'
    New-Item -ItemType Directory -Path $emptyRepository -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $emptyRepository 'empty.txt') -Encoding utf8 -NoNewline -Value '   '
    $emptySelection = Invoke-Native $selectorExe @('--repository-root', $emptyRepository, '--goal-context', 'empty.txt', '--out', 'selection.json') 'empty Goal Context selection' $false
    if ($emptySelection.Output -notmatch 'Selected Goal Context is empty') { Add-Failure 'Goal Context selector did not reject empty text.' }

    $junctionRepository = Join-Path $tempRoot 'selector-junction-repository'
    $junctionOutside = Join-Path $tempRoot 'selector-junction-outside'
    New-Item -ItemType Directory -Path $junctionRepository, $junctionOutside -Force | Out-Null
    Copy-Item -LiteralPath $goalContextFixture -Destination $junctionOutside
    New-Item -ItemType Junction -Path (Join-Path $junctionRepository 'docs') -Target $junctionOutside | Out-Null
    $junctionInput = Invoke-Native $selectorExe @('--repository-root', $junctionRepository, '--search-root', 'docs', '--out', 'selection.json') 'selector junction input escape' $false
    if ($junctionInput.Output -notmatch 'canonical repository root') { Add-Failure 'Goal Context selector followed a junction outside the repository for input.' }

    $outputRepository = Join-Path $tempRoot 'selector-output-junction-repository'
    $outputDocs = Join-Path $outputRepository 'docs'
    $outputOutside = Join-Path $tempRoot 'selector-output-junction-outside'
    New-Item -ItemType Directory -Path $outputDocs, $outputOutside -Force | Out-Null
    Copy-Item -LiteralPath $goalContextFixture -Destination $outputDocs
    New-Item -ItemType Junction -Path (Join-Path $outputRepository '.review') -Target $outputOutside | Out-Null
    $junctionOutput = Invoke-Native $selectorExe @('--repository-root', $outputRepository, '--search-root', 'docs', '--out', '.review/selection.json') 'selector junction output escape' $false
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

    Invoke-Fixture 'review-only' @('--copilot-timeout-seconds', '3', '--copilot-poll-interval-seconds', '1', '--copilot-stable-samples', '1') | Out-Null
    $reviewOnly = Read-Context (Join-Path $tempRoot 'review-only')
    if ($null -ne $reviewOnly) {
        if ($reviewOnly.copilotReviewWait.waitStatus -ne 'completed' -or -not $reviewOnly.copilotReviewWait.isComplete) { Add-Failure 'review-only fixture was not emitted as collector-complete' }
        if ($reviewOnly.copilotReviewWait.observedReviewState -ne 'reviewOnly' -or $reviewOnly.copilotReviewWait.actualInlineCommentCount -ne 0) { Add-Failure 'review-only fixture did not preserve the no-inline terminal review state' }
    }

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

    Invoke-Fixture 'copilot-actor-alias' @('--copilot-timeout-seconds', '5', '--copilot-poll-interval-seconds', '1', '--copilot-stable-samples', '2') | Out-Null
    $actorAlias = Read-Context (Join-Path $tempRoot 'copilot-actor-alias')
    if ($null -ne $actorAlias) {
        if ($actorAlias.copilotReviewWait.waitStatus -ne 'completed') { Add-Failure 'copilot-actor-alias fixture did not complete when the review and inline endpoints used different official actor names' }
        if ($actorAlias.copilotReviewWait.selectedReviewId -ne 100 -or $actorAlias.copilotReviewWait.actualInlineCommentCount -ne 1) { Add-Failure 'copilot-actor-alias fixture did not correlate the inline comment by review id' }
    }

    Invoke-Fixture 'copilot-app-url' @('--no-wait-for-copilot') | Out-Null
    $appUrl = Read-Context (Join-Path $tempRoot 'copilot-app-url')
    if ($null -ne $appUrl) {
        if ($appUrl.copilotReviewWait.selectedReviewId -ne 100 -or $appUrl.copilotReviewWait.actualInlineCommentCount -ne 1) { Add-Failure 'copilot-app-url fixture did not recognize the official GitHub App profile URL' }
    }

    Invoke-Fixture 'copilot-human-reply' @('--no-wait-for-copilot') | Out-Null
    $humanReply = Read-Context (Join-Path $tempRoot 'copilot-human-reply')
    if ($null -ne $humanReply) {
        if ($humanReply.copilotReviewWait.actualInlineCommentCount -ne 1 -or $humanReply.copilotReviewWait.inlineCommentIds[0] -ne 1001) { Add-Failure 'copilot-human-reply fixture counted a human reply as a Copilot-generated inline comment' }
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

    # Prove the canonical setup without Adaptive first, then exercise the optional
    # baseline Phase 2 add-on as a separate installation/check boundary.
    $scratch = Join-Path $tempRoot 'scratch-repository'
    $scratchCodex = Join-Path $scratch '.codex'
    New-Item -ItemType Directory -Path $scratchCodex -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $scratch 'AGENTS.md') -Value 'sentinel-agents'
    Set-Content -LiteralPath (Join-Path $scratchCodex 'config.toml') -Value 'sentinel-config'

    Invoke-Native $syncExe @($scratch, '--dry-run') 'review helper dry-run' | Out-Null
    Invoke-Native $syncExe @($scratch) 'review helper install' | Out-Null
    Invoke-Native $syncExe @($scratch, '--check') 'canonical review helper check without Adaptive' | Out-Null
    foreach ($profile in @('high-implementation-starter.toml', 'standard-implementation-completer.toml')) {
        if (Test-Path -LiteralPath (Join-Path $scratch ".codex\agents\$profile")) { Add-Failure "Canonical review setup unexpectedly installed Adaptive profile: $profile" }
    }

    $missingAdaptive = Invoke-Native $syncExe @($scratch, '--check', '--check-adaptive') 'optional Adaptive add-on missing gate' $false
    if ($missingAdaptive.Output -notmatch 'Install apm-packages/adaptive-implementation-execution separately') { Add-Failure 'optional Adaptive check did not explain the separate package installation boundary' }
    $invalidAdaptiveCheck = Invoke-Native $syncExe @($scratch, '--check-adaptive') 'optional Adaptive flag requires review check' $false
    if ($invalidAdaptiveCheck.Output -notmatch 'Usage:') { Add-Failure '--check-adaptive without --check did not fail with usage' }

    $scratchSkill = Join-Path $scratch '.agents\skills\adaptive-implementation-execution'
    $scratchAgents = Join-Path $scratch '.github\agents'
    New-Item -ItemType Directory -Path $scratchSkill, $scratchAgents -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution\.apm\skills\adaptive-implementation-execution\SKILL.md') -Destination (Join-Path $scratchSkill 'SKILL.md')
    foreach ($agent in @('high-implementation-starter.agent.md', 'standard-implementation-completer.agent.md')) {
        Copy-Item -LiteralPath (Join-Path $repoRoot ".github\agents\$agent") -Destination (Join-Path $scratchAgents $agent)
    }
    Invoke-Native $adaptiveSyncExe @($scratch, '--dry-run') 'Adaptive helper dry-run' | Out-Null
    Invoke-Native $adaptiveSyncExe @($scratch) 'Adaptive helper install' | Out-Null
    Invoke-Native $adaptiveSyncExe @($scratch, '--check') 'Adaptive helper check' | Out-Null
    Invoke-Native $syncExe @($scratch, '--check', '--check-adaptive') 'review helper optional Adaptive add-on check' | Out-Null

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
