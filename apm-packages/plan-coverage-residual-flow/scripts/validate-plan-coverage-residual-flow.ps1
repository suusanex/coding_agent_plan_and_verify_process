[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        Add-Failure $Message
    }
}

function Assert-Matches([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -cnotmatch $Pattern) {
        Add-Failure $Message
    }
}

function Assert-NotMatches([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -cmatch $Pattern) {
        Add-Failure $Message
    }
}

function Get-NormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Test-AffirmativeDirectRouteSelection([string]$Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) {
        return $false
    }

    $routeName = '(?<![A-Za-z0-9-])plan-coverage-residual-flow(?![A-Za-z0-9-])'
    $negativeSelection = "(?i)(?:\b(?:do not|don't|not)\s+(?:use|run|invoke|start|select).*${routeName}|${routeName}\s*(?:は|を)?\s*(?:使わない|使用しない|使わず|使用せず|選択しない|選ばない))"
    $affirmativeSelection = "(?i)(?:\b(?:use|run|invoke|start|select)\s+(?:the\s+)?${routeName}|${routeName}\s*(?:を)?\s*(?:使(?:って|い)|使用して|実行して|開始して|選択して|で進めて))"

    return (($Message -cnotmatch $negativeSelection) -and ($Message -cmatch $affirmativeSelection))
}

$skillRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md'
$deployedSkillRelativePath = '.agents/skills/plan-coverage-residual-flow/SKILL.md'
$coverageLedgerRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
$deployedCoverageLedgerRelativePath = '.agents/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
$manifestRelativePath = 'apm-packages/plan-coverage-residual-flow/apm.yml'
$packageReadmeRelativePath = 'apm-packages/plan-coverage-residual-flow/README.md'
$purposeDocumentationRelativePath = 'docs/plan-coverage-purpose.md'
$processDocumentationRelativePath = 'docs/plan-coverage-process-and-agents.md'
$fullCoverageDocumentationRelativePath = 'docs/token-aware-full-coverage-decomposition-flow.md'
$asrValidationDocumentationRelativePath = 'docs/architecture-slice-readiness-validation.md'
$sharedInstructionsRelativePath = '.github/instructions/plan-coverage-shared.instructions.md'
$decompositionRelativePath = '.github/agents/plan-slice-decomposition.agent.md'
$scenarioRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/invocation-authorization-scenarios.json'
$manualReadmeRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/manual-model-smoke/README.md'
$manualTemplateRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/manual-model-smoke/result-template.md'
$standaloneE2ERelativePath = 'apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-full-coverage-e2e.ps1'
$standaloneFixtureReadmeRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/full-coverage-standalone/PCF-001/README.md'
$standaloneFixtureExpectedRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/full-coverage-standalone/PCF-001/expected.json'
$apmSmokeRelativePath = 'apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1'
$workflowRelativePath = '.github/workflows/validate-plan-coverage-residual-flow.yml'

$requiredFiles = @(
    $skillRelativePath,
    $coverageLedgerRelativePath,
    $manifestRelativePath,
    $packageReadmeRelativePath,
    $purposeDocumentationRelativePath,
    $processDocumentationRelativePath,
    $fullCoverageDocumentationRelativePath,
    $asrValidationDocumentationRelativePath,
    $sharedInstructionsRelativePath,
    $decompositionRelativePath,
    $scenarioRelativePath,
    $manualReadmeRelativePath,
    $manualTemplateRelativePath,
    $standaloneE2ERelativePath,
    $standaloneFixtureReadmeRelativePath,
    $standaloneFixtureExpectedRelativePath,
    $apmSmokeRelativePath,
    $workflowRelativePath
)

foreach ($relativePath in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath) -PathType Leaf) "Missing required file: $relativePath"
}

if ($failures.Count -eq 0) {
    $skillPath = Join-Path $repoRoot $skillRelativePath
    $skill = Get-NormalizedText $skillPath
    $skillMatch = [regex]::Match($skill, '\A---\n(?<frontmatter>.*?)\n---\n(?<body>.*)\z', [Text.RegularExpressions.RegexOptions]::Singleline)
    Assert-True $skillMatch.Success 'SKILL.md must contain one parseable frontmatter block'

    if ($skillMatch.Success) {
        $frontmatter = $skillMatch.Groups['frontmatter'].Value
        $body = $skillMatch.Groups['body'].Value
        $descriptionMatch = [regex]::Match($frontmatter, '(?ms)^description:\s*>\s*\n(?<description>(?:[ \t]+.*(?:\n|\z))+)$')
        Assert-True $descriptionMatch.Success 'frontmatter description must use an explicit folded block'

        $description = if ($descriptionMatch.Success) {
            (($descriptionMatch.Groups['description'].Value -replace '(?m)^\s+', '') -replace '\s+', ' ').Trim()
        }
        else {
            ''
        }

        Assert-Matches $description '(?i)explicit-invocation-only' 'frontmatter must identify the Skill as explicit-invocation-only'
        Assert-Matches $description 'current user explicitly and affirmatively selects.*`plan-coverage-residual-flow`' 'frontmatter must require affirmative exact direct user selection'
        Assert-Matches $description 'upstream process.*durable evidence.*user explicitly selected this exact route' 'frontmatter must require durable upstream user-selection evidence'
        Assert-Matches $description 'Never select, recommend, or propose.*generic.*implementation, fix, continue, or proceed' 'frontmatter must exclude generic implementation requests'
        Assert-Matches $description 'task size.*difficulty.*risk.*complexity.*architecture' 'frontmatter must exclude task characteristics'
        Assert-Matches $description 'existing Plan or.*coverage artifacts.*repository history.*Skill availability' 'frontmatter must exclude artifact, history, and availability inference'
        Assert-Matches $description 'question, quote, negation, comparison, or informational mention.*not an invocation.*do not activate or read this Skill' 'frontmatter must reject non-invocation route mentions before Skill activation'
        Assert-NotMatches $frontmatter 'bounded Plan-first work|should decide the next phase|required artifact, stop condition' 'legacy broad discovery conditions must not remain in frontmatter'

        $firstH2 = [regex]::Match($body, '(?m)^##\s+(.+?)\s*$')
        Assert-True ($firstH2.Success -and $firstH2.Groups[1].Value -eq 'Invocation authorization') 'Invocation authorization must be the first H2 section'

        $gateMatch = [regex]::Match($body, '(?ms)^## Invocation authorization\s*\n(?<gate>.*?)(?=^##\s|\z)')
        Assert-True $gateMatch.Success 'Invocation authorization section is missing'
        if ($gateMatch.Success) {
            $gate = $gateMatch.Groups['gate'].Value
            Assert-Matches $gate 'Before reading any repository artifact.*creating or updating any Plan Coverage artifact.*invoking any agent' 'authorization must precede repository reads, artifact writes, and agent invocation'
            Assert-Matches $gate 'current user message.*explicitly and affirmatively selects.*exact literal route name `plan-coverage-residual-flow`' 'direct authorization must require affirmative exact current-message route selection'
            Assert-Matches $gate 'literal, quoted, negated, rejected, comparative, question-based, or informational mention.*not direct authorization' 'direct authorization must reject non-affirmative route mentions'
            Assert-Matches $gate 'process_route:\s*plan-coverage-residual-flow' 'upstream authorization must require process_route'
            Assert-Matches $gate 'process_route_source:\s*explicit-user-selection' 'upstream authorization must require explicit-user-selection'
            Assert-Matches $gate 'user_selection_evidence:.*actual user message' 'upstream authorization must require actual user message evidence'
            Assert-Matches $gate 'upstream process, agent, or AI recommendation is not user selection evidence' 'AI or upstream recommendation must not count as evidence'
            Assert-Matches $gate '`実装して`.*`修正して`.*`続けて`.*`このPlanを実装して`' 'generic request examples must be denied'
            Assert-Matches $gate 'large, difficult, high-risk, complex, or architecture-heavy' 'task characteristics must not authorize the route'
            Assert-Matches $gate 'existing Plan.*Plan Coverage artifact.*coverage ledger.*prior handoff' 'existing artifacts must not authorize the route'
            Assert-Matches $gate 'prior use of this process in the repository' 'repository history must not authorize the route'
            Assert-Matches $gate 'Skill being installed or otherwise available' 'Skill availability must not authorize the route'
            Assert-Matches $gate 'do not read repository artifacts on behalf of this flow' 'unauthorized repository reads must be forbidden'
            Assert-Matches $gate 'do not create or update Plan Coverage artifacts' 'unauthorized artifact writes must be forbidden'
            Assert-Matches $gate 'do not invoke Plan Coverage agents' 'unauthorized agent invocation must be forbidden'
            Assert-Matches $gate 'do not recommend or propose this route' 'unauthorized route recommendation must be forbidden'
            Assert-Matches $gate "return control to the caller or the repository's normal implementation route" 'unauthorized control must return to caller or normal route'
            Assert-Matches $gate 'do not select another large process from this Skill' 'unauthorized fallback must not select another large process'
        }

        Assert-NotMatches $body '(?m)^## Use when\s*$|Use this skill when:' 'legacy broad Use when selection section must not remain'
        $authorizedUseIndex = $body.IndexOf('## Authorized use', [StringComparison]::Ordinal)
        $requiredInputsIndex = $body.IndexOf('## Required inputs', [StringComparison]::Ordinal)
        Assert-True ($authorizedUseIndex -gt $gateMatch.Index) 'Authorized use must follow the authorization gate'
        Assert-True ($requiredInputsIndex -gt $authorizedUseIndex) 'Required inputs must follow authorized use'
    }

    $manifest = Get-NormalizedText (Join-Path $repoRoot $manifestRelativePath)
    Assert-Matches $manifest '(?m)^name:\s*plan-coverage-residual-flow\s*$' 'package name must remain stable'
    Assert-Matches $manifest '(?m)^version:\s*0\.10\.0\s*$' 'package version must be 0.10.0'

    $adaptiveValidator = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1')
    $designPairValidator = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/design-pair-implementation-execution/scripts/validate.ps1')
    Assert-Matches $adaptiveValidator "plan-coverage-residual-flow/apm\.yml'; Version = '0\\\.10\\\.0'" 'Adaptive validator package version pin must be 0.10.0'
    Assert-Matches $designPairValidator 'Plan Coverage package version 0\.10\.0' 'Design Pair validator package version pin must be 0.10.0'

    Assert-Matches $skill 'The `design-pair-implementation-execution` package remains a separate package' 'Design Pair must remain a separate package without target-specific qualification'
    Assert-Matches $skill 'both packages are installed for the same target and the user explicitly selects Design Pair' 'Design Pair route must require same-target installation and explicit selection'
    Assert-Matches $skill 'keep `plan-coverage-residual-flow` selection evidence separate from Design Pair implementation route selection evidence' 'Plan Coverage and Design Pair selection evidence must remain separate'
    Assert-Matches $skill 'While Design Pair is waiting, do not fall back to Adaptive' 'Design Pair waiting state must block Adaptive fallback'
    Assert-NotMatches $skill 'formal targets .*copilot.*codex.*agent-skills' 'PR #90 target enumeration must not remain in Plan Coverage'
    Assert-NotMatches $skill 'Plan Coverage parent runtime qualif(?:ication).*Design Pair.*Adaptive.*GitHub Copilot CLI' 'PR #90 Copilot qualification claim must not remain in Plan Coverage'
    Assert-NotMatches $skill 'Plan Coverage Copilot CLI\s+issue' 'PR #90 Copilot qualification issue handoff must not remain in Plan Coverage'

    $decomposition = Get-NormalizedText (Join-Path $repoRoot $decompositionRelativePath)
    $sharedInstructions = Get-NormalizedText (Join-Path $repoRoot $sharedInstructionsRelativePath)
    $handoffReview = Get-NormalizedText (Join-Path $repoRoot '.github/agents/implementation-handoff-review.agent.md')
    $packageReadme = Get-NormalizedText (Join-Path $repoRoot $packageReadmeRelativePath)
    $purposeDocumentation = Get-NormalizedText (Join-Path $repoRoot $purposeDocumentationRelativePath)
    $processDocumentation = Get-NormalizedText (Join-Path $repoRoot $processDocumentationRelativePath)
    $fullCoverageDocumentation = Get-NormalizedText (Join-Path $repoRoot $fullCoverageDocumentationRelativePath)
    $asrValidationDocumentation = Get-NormalizedText (Join-Path $repoRoot $asrValidationDocumentationRelativePath)
    Assert-Matches $skill 'Treat every executable `plans/<slug>-slice-SL-xxx\.md` artifact as a bounded Plan that re-enters this Plan Coverage flow' 'full-coverage slices must re-enter Plan Coverage as bounded Plans'
    Assert-Matches $decomposition 'executable slice については.*bounded Plan として読む' 'decomposition must produce bounded Plan slice artifacts'
    Assert-Matches $skill 'Architecture baseline compatibility' 'Plan Coverage parent must own the pre-slice architecture compatibility check'
    Assert-Matches $skill 'Only a current-baseline `Match` may proceed.*`Drift` returns to Architecture Slice Readiness / Elaboration.*`Unclear` fails closed' 'Plan Coverage must fail closed on architecture Drift or Unclear'
    Assert-Matches $sharedInstructions 'Only `Match` may proceed to implementation.*`Drift` returns to Architecture Slice Readiness / Elaboration.*`Unclear` fails closed' 'shared guardrails must require Match before full-coverage implementation'
    Assert-Matches $handoffReview '(?m)^#### Check 11\. Architecture baseline compatibility\s*$' 'implementation handoff review must own the architecture compatibility gate'
    Assert-Matches $handoffReview '\| Slice ID \| Readiness verdict \| Baseline authority \| Baseline identity \| Observed semantics \| Match / Drift / Unclear \| Required action \|' 'implementation handoff review must emit architecture compatibility evidence'
    Assert-Matches $handoffReview '`ArchitectureNotRequired`.*Lightweight architecture baseline' 'ArchitectureNotRequired must retain baseline comparison'
    Assert-NotMatches $processDocumentation 'Slice preparation and parent review return `Match`' 'active docs must not assign architecture compatibility to removed 3-layer owners'

    Assert-Matches $packageReadme '(?m)^full-coverage\n  -> architecture-slice-readiness\n     -> architecture-elaboration -> readiness rerun, when required\n     -> plan-slice-decomposition, when authorized\n  -> each bounded slice\n     -> standard Plan Coverage pre-implementation gates\n     -> architecture baseline compatibility: Match\n     -> Adaptive Implementation\n     -> independent verification\n  -> cross-slice-verification\n  -> residual-decision-gate$' 'package README must order each bounded slice through pre-implementation gates, architecture Match, Adaptive Implementation, independent verification, cross-slice verification, and residual decision'
    Assert-Matches $packageReadme 'Living Record.*lightweight lifecycle.*未実装' 'package README must state that lightweight full-coverage artifact reduction is not implemented'
    Assert-Matches $purposeDocumentation '(?s)Architecture Slice Readiness / Elaboration.*Plan Slice Decomposition.*each executable slice re-enters the standard Plan Coverage chain.*Cross-Slice Verification.*Residual Decision' 'purpose policy must describe the self-contained full-coverage lifecycle'
    Assert-Matches $purposeDocumentation 'repeated artifact and handoff cost remains an unresolved optimization boundary' 'purpose policy must keep current per-slice artifact cost explicit'
    Assert-Matches $fullCoverageDocumentation 'normal Plan Coverage artifact and handoff set for every executable slice' 'decomposition policy must preserve normal per-slice Plan Coverage artifacts'
    Assert-Matches $fullCoverageDocumentation 'Living Record.*lightweight full-coverage lifecycle has not been implemented' 'decomposition policy must not claim an implemented lightweight lifecycle'
    Assert-Matches $processDocumentation '(?m)^## Current process flows\s*$' 'detailed process documentation must identify the current flows'
    Assert-Matches $processDocumentation '(?m)^## Full Autonomous boundary\s*$' 'detailed process documentation must state the current Full Autonomous boundary'
    Assert-Matches $processDocumentation 'full-coverage remains self-contained under Plan Coverage ownership from Architecture Slice Readiness through Residual Decision' 'detailed process documentation must keep full-coverage under Plan Coverage ownership'
    Assert-NotMatches $processDocumentation '(?m)^## (?:Agent creation order|Suggested README update|Recommended process flows)\s*$|(?m)^Required changes:\s*$' 'obsolete future agent revision planning must not remain in active process documentation'
    Assert-Matches $asrValidationDocumentation 'Plan Coverage parent compatibility.*`Match`' 'ASR suite must assign architecture compatibility to the Plan Coverage parent'
    Assert-Matches $asrValidationDocumentation '`implementation-handoff-review` Check 11.*records baseline identity.*`Match`' 'ASR suite must require current implementation handoff evidence'
    Assert-NotMatches $asrValidationDocumentation 'slice-prep|slice-impl|Parent Review Gate|Parent review records' 'ASR suite must not assign current compatibility ownership to removed 3-layer stages'

    $activeDocumentation = @($packageReadme, $purposeDocumentation, $processDocumentation, $fullCoverageDocumentation, $asrValidationDocumentation) -join "`n"
    Assert-NotMatches $activeDocumentation 'formal targets .*copilot.*codex.*agent-skills|Plan Coverage parent runtime qualif(?:ication)|Plan Coverage Copilot CLI\s+issue' 'PR #90 Plan Coverage-specific qualification wording must not remain in active documentation'

    $rollbackContractRelativePaths = @(
        $skillRelativePath,
        $coverageLedgerRelativePath,
        $packageReadmeRelativePath,
        $sharedInstructionsRelativePath,
        $decompositionRelativePath,
        '.github/agents/change-risk-triage.agent.md',
        '.github/agents/coverage-gap-resolution-slice.agent.md',
        '.github/agents/coverage-gap-triage.agent.md',
        '.github/agents/cross-slice-verification-kernel.agent.md',
        '.github/agents/high-implementation-starter.agent.md',
        '.github/agents/implementation-contract-kernel.agent.md',
        '.github/agents/implementation-contract-review-kernel.agent.md',
        '.github/agents/implementation-execution.agent.md',
        '.github/agents/implementation-handoff-review.agent.md',
        '.github/agents/residual-decision-gate.agent.md',
        '.github/agents/runtime-contract-kernel.agent.md',
        '.github/agents/standard-implementation-completer.agent.md',
        '.github/agents/test-design-kernel.agent.md',
        '.github/agents/verification-kernel.agent.md',
        $processDocumentationRelativePath,
        $purposeDocumentationRelativePath,
        $fullCoverageDocumentationRelativePath,
        $asrValidationDocumentationRelativePath
    )
    $prohibitedRollbackPatterns = @(
        'compact-slice-record-v2',
        'Parent Orchestration State',
        'Parent Authorization',
        'Slice Preparation Delta',
        'Full-Coverage Final Record',
        'full-coverage-slice-v2',
        'legacy-split-v1',
        'slice-prep\.agent\.md',
        'slice-impl'
    )
    foreach ($relativePath in $rollbackContractRelativePaths) {
        $contractText = Get-NormalizedText (Join-Path $repoRoot $relativePath)
        foreach ($pattern in $prohibitedRollbackPatterns) {
            Assert-NotMatches $contractText $pattern "PR #80 compact-v2 semantic '$pattern' must not remain in $relativePath"
        }
    }

    $coverageLedgerPath = Join-Path $repoRoot $coverageLedgerRelativePath
    $deployedSkillPath = Join-Path $repoRoot $deployedSkillRelativePath
    $deployedCoverageLedgerPath = Join-Path $repoRoot $deployedCoverageLedgerRelativePath
    $deployedSkillExists = Test-Path -LiteralPath $deployedSkillPath -PathType Leaf
    $deployedLedgerExists = Test-Path -LiteralPath $deployedCoverageLedgerPath -PathType Leaf
    Assert-True ($deployedSkillExists -eq $deployedLedgerExists) 'deployed Plan Coverage projections must be present as a complete pair when provisioned'
    if ($deployedSkillExists -and $deployedLedgerExists) {
        Assert-True ((Get-NormalizedText $skillPath) -ceq (Get-NormalizedText $deployedSkillPath)) 'provisioned Skill projection must match the canonical Skill'
        Assert-True ((Get-NormalizedText $coverageLedgerPath) -ceq (Get-NormalizedText $deployedCoverageLedgerPath)) 'provisioned coverage ledger projection must match the canonical reference'
    }

    $scenarios = @(Get-Content -Raw -LiteralPath (Join-Path $repoRoot $scenarioRelativePath) | ConvertFrom-Json)
    Assert-True ($scenarios.Count -eq 8) 'Scenario fixture must contain exactly A through H'
    Assert-True ((@($scenarios.id) -join ',') -ceq 'A,B,C,D,E,F,G,H') 'Scenario IDs must be ordered A through H'
    foreach ($scenario in $scenarios) {
        $message = [string]$scenario.current_user_message
        $directAuthorized = Test-AffirmativeDirectRouteSelection $message
        $upstream = $scenario.upstream_artifact
        $upstreamAuthorized = $null -ne $upstream -and
            $upstream.process_route -ceq 'plan-coverage-residual-flow' -and
            $upstream.process_route_source -ceq 'explicit-user-selection' -and
            [string]$upstream.user_selection_evidence -cmatch '^(?:user-message|user-turn):.+'
        $actualAuthorized = $directAuthorized -or $upstreamAuthorized

        Assert-True ($actualAuthorized -eq [bool]$scenario.expected_authorized) "Scenario $($scenario.id) authorization result does not match the contract"
        if (-not $actualAuthorized) {
            Assert-True ((@($scenario.expected_forbidden_actions) -join ',') -ceq 'read-repository-artifacts-for-flow,write-plan-coverage-artifacts,invoke-plan-coverage-agents,recommend-route') "Scenario $($scenario.id) must forbid every unauthorized side effect"
            Assert-True ($scenario.expected_return -ceq 'caller-or-normal-route') "Scenario $($scenario.id) must return to caller or normal route"
        }
        else {
            Assert-True (@($scenario.expected_forbidden_actions).Count -eq 0) "Scenario $($scenario.id) must not report unauthorized-only prohibitions"
            Assert-True ($scenario.expected_return -ceq 'authorized-flow') "Scenario $($scenario.id) must enter the authorized flow"
        }
    }

    $manualReadme = Get-NormalizedText (Join-Path $repoRoot $manualReadmeRelativePath)
    $manualTemplate = Get-NormalizedText (Join-Path $repoRoot $manualTemplateRelativePath)
    Assert-Matches $manualReadme 'Scenarios A, B, C, E, G, and H.*not selected.*no Plan Coverage artifact.*no Plan Coverage agent' 'manual smoke must define unauthorized observations'
    Assert-Matches $manualReadme 'Scenarios D and F.*accepts.*existing flow can proceed' 'manual smoke must define authorized observations'
    Assert-Matches $manualReadme '`NOT RUN`.*`UNOBSERVABLE`.*Neither status counts as a pass' 'manual smoke must keep unexecuted or unobservable evidence separate'
    foreach ($scenarioId in 'A'..'H') {
        Assert-Matches $manualTemplate "(?m)^\| $scenarioId \| NOT RUN \|" "manual result template must include Scenario $scenarioId"
    }

    $standaloneE2E = Get-NormalizedText (Join-Path $repoRoot $standaloneE2ERelativePath)
    $standaloneFixtureReadme = Get-NormalizedText (Join-Path $repoRoot $standaloneFixtureReadmeRelativePath)
    $standaloneFixtureExpected = Get-NormalizedText (Join-Path $repoRoot $standaloneFixtureExpectedRelativePath)
    $apmSmoke = Get-NormalizedText (Join-Path $repoRoot $apmSmokeRelativePath)
    $workflow = Get-NormalizedText (Join-Path $repoRoot $workflowRelativePath)
    Assert-Matches $packageReadme 'Standalone full-coverage E2E fixture' 'package README must link the standalone full-coverage E2E fixture'
    Assert-Matches $packageReadme 'validate-plan-coverage-full-coverage-e2e\.ps1' 'package README must document the standalone E2E command'
    Assert-Matches $packageReadme '外部modelは実行しない.*自律実行した証拠ではありません' 'package README must separate deterministic evidence from external-model evidence'
    Assert-Matches $standaloneFixtureReadme 'deterministic test-only fixture' 'PCF-001 must identify itself as deterministic test-only evidence'
    Assert-Matches $standaloneFixtureReadme 'does not invoke an external model' 'PCF-001 must not claim external-model execution evidence'
    Assert-Matches $standaloneFixtureExpected '(?s)"ReadyForRiskTriage".*"full-coverage".*"ReadyForSliceDecomposition".*"SL-001".*"SL-002".*"CROSS_SLICE_VERIFIED".*"READY_TO_CLOSE_WITH_NO_RESIDUALS"' 'PCF-001 must preserve the full lifecycle stage order'
    Assert-Matches $standaloneE2E '\[string\]\$InstalledRoot' 'standalone E2E validator must support installed-root contract resolution'
    foreach ($negativeCase in @('missing-sl-002-verification', 'missing-production-binding', 'missing-cross-slice-verdict', 'residual-before-cross-slice', 'removed-dependency-reference')) {
        Assert-Matches $standaloneE2E ([regex]::Escape($negativeCase)) "standalone E2E validator must fail closed for $negativeCase"
    }
    Assert-Matches $standaloneE2E 'foreach \(\$verdict in @\(''Drift'', ''Unclear''\)\)' 'standalone E2E validator must fail closed for architecture Drift and Unclear'
    Assert-Matches $apmSmoke '(?s)validate-plan-coverage-full-coverage-e2e\.ps1.*-InstalledRoot' 'remote APM smoke must execute standalone E2E against the installed closure'
    Assert-Matches $workflow 'validate-plan-coverage-full-coverage-e2e\.ps1' 'Plan Coverage workflow must execute standalone E2E in source mode'

}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure -ErrorAction Continue
    }
    throw "Plan Coverage Residual Flow validation failed with $($failures.Count) error(s)."
}

Write-Host 'Plan Coverage Residual Flow validation: PASS'
