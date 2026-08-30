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

function Get-NormalizedTextSha256([string]$Path) {
    $normalizedText = Get-NormalizedText $Path
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($normalizedText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ChangeRiskResultSchemaErrors([object]$Result) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $requiredTopLevel = @(
        'scenario_id',
        'bounded_runtime_sequence',
        'execution_models',
        'recommended_profile',
        'required_sections',
        'candidate_bounded_sequence',
        'independent_implementation_slices_required',
        'shared_semantics_that_must_remain_fixed',
        'why_one_bounded_parent_pass_is_insufficient',
        'failure_mode_that_decomposition_prevents',
        'escalation_gate_result',
        'recommendation_confidence',
        'evidence_that_would_lower_the_profile',
        'evidence_that_would_raise_the_profile'
    )
    $requiredSectionNames = @(
        'bounded_runtime_sequence',
        'execution_model_classification',
        'risk_semantics',
        'why_standard_slice_is_insufficient',
        'recommendation_confidence',
        'profile_change_evidence'
    )
    $executionModelEnum = @(
        'Same-process ABI / FFI boundary',
        'Cross-process IPC',
        'Cross-process durable-state observation',
        'External or independently deployed service',
        'Local asynchronous operation / UI-thread handoff',
        'Independent background worker',
        'Persistent queue / replayable job'
    )

    if ($null -eq $Result -or $Result -isnot [pscustomobject]) {
        $errors.Add('root must be an object')
        return $errors.ToArray()
    }

    $actualTopLevel = @($Result.psobject.Properties.Name | Sort-Object)
    $expectedTopLevel = @($requiredTopLevel | Sort-Object)
    if (($actualTopLevel -join ',') -cne ($expectedTopLevel -join ',')) {
        $errors.Add('top-level required and additionalProperties constraints failed')
    }

    if ($Result.scenario_id -isnot [string] -or @('CRT-001', 'CRT-002', 'CRT-003') -cnotcontains $Result.scenario_id) {
        $errors.Add('scenario_id must be an allowed string')
    }

    foreach ($arrayField in @('bounded_runtime_sequence', 'execution_models', 'independent_implementation_slices_required', 'shared_semantics_that_must_remain_fixed')) {
        $value = $Result.$arrayField
        if ($value -isnot [System.Array]) {
            $errors.Add("$arrayField must be an array")
            continue
        }
        if ($arrayField -in @('bounded_runtime_sequence', 'execution_models') -and $value.Count -lt 1) {
            $errors.Add("$arrayField must contain at least one item")
        }
        foreach ($item in $value) {
            if ($item -isnot [string] -or $item.Length -lt 1) {
                $errors.Add("$arrayField items must be non-empty strings")
            }
        }
    }

    if ($Result.execution_models -is [System.Array]) {
        foreach ($model in $Result.execution_models) {
            if ($executionModelEnum -cnotcontains $model) {
                $errors.Add("execution_models contains an unknown value: $model")
            }
        }
    }

    if ($Result.recommended_profile -isnot [string] -or @('lightweight', 'standard-slice', 'contract-kernel', 'full-coverage') -cnotcontains $Result.recommended_profile) {
        $errors.Add('recommended_profile must be an allowed string')
    }

    if ($Result.required_sections -isnot [pscustomobject]) {
        $errors.Add('required_sections must be an object')
    }
    else {
        $actualSectionNames = @($Result.required_sections.psobject.Properties.Name | Sort-Object)
        $expectedSectionNames = @($requiredSectionNames | Sort-Object)
        if (($actualSectionNames -join ',') -cne ($expectedSectionNames -join ',')) {
            $errors.Add('required_sections required and additionalProperties constraints failed')
        }
        foreach ($sectionName in $requiredSectionNames) {
            if ($Result.required_sections.$sectionName -isnot [bool] -or $Result.required_sections.$sectionName -ne $true) {
                $errors.Add("required_sections.$sectionName must be boolean true")
            }
        }
    }

    foreach ($stringField in @(
        'candidate_bounded_sequence',
        'why_one_bounded_parent_pass_is_insufficient',
        'failure_mode_that_decomposition_prevents',
        'evidence_that_would_lower_the_profile',
        'evidence_that_would_raise_the_profile'
    )) {
        if ($Result.$stringField -isnot [string] -or $Result.$stringField.Length -lt 1) {
            $errors.Add("$stringField must be a non-empty string")
        }
    }

    if ($Result.escalation_gate_result -isnot [string] -or @('Satisfied', 'NotSatisfied', 'N/A') -cnotcontains $Result.escalation_gate_result) {
        $errors.Add('escalation_gate_result must be an allowed string')
    }
    if ($Result.recommendation_confidence -isnot [string] -or @('High', 'Medium', 'Low') -cnotcontains $Result.recommendation_confidence) {
        $errors.Add('recommendation_confidence must be an allowed string')
    }

    return $errors.ToArray()
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

$planCoverageOwnedAgentNames = @(
    'plan-kernel',
    'black-box-behavior-spec-kernel',
    'change-risk-triage',
    'architecture-slice-readiness',
    'architecture-elaboration',
    'plan-slice-decomposition',
    'implementation-contract-kernel',
    'implementation-contract-review-kernel',
    'runtime-contract-kernel',
    'test-design-kernel',
    'implementation-handoff-review',
    'implementation-execution',
    'code-review-focus-kernel',
    'verification-kernel',
    'cross-slice-verification-kernel',
    'coverage-gap-triage',
    'coverage-gap-resolution-slice',
    'residual-decision-gate'
)
$canonicalAgentsRelativeRoot = 'apm-packages/plan-coverage-residual-flow/.apm/agents'
$canonicalSharedInstructionsRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/instructions/plan-coverage-shared.instructions.md'
$skillRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md'
$coverageLedgerRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/coverage-ledger.md'
$sliceLivingRecordRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/full-coverage-slice-living-record.md'
$fullCoverageCloseRelativePath = 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/references/full-coverage-close.md'
$manifestRelativePath = 'apm-packages/plan-coverage-residual-flow/apm.yml'
$packageReadmeRelativePath = 'apm-packages/plan-coverage-residual-flow/README.md'
$purposeDocumentationRelativePath = 'docs/plan-coverage-purpose.md'
$processDocumentationRelativePath = 'docs/plan-coverage-process-and-agents.md'
$fullCoverageDocumentationRelativePath = 'docs/token-aware-full-coverage-decomposition-flow.md'
$asrValidationDocumentationRelativePath = 'docs/architecture-slice-readiness-validation.md'
$installationDocumentationRelativePath = 'docs/installation-and-maintenance.md'
$sharedInstructionsRelativePath = $canonicalSharedInstructionsRelativePath
$changeRiskRelativePath = "$canonicalAgentsRelativeRoot/change-risk-triage.agent.md"
$architectureReadinessRelativePath = "$canonicalAgentsRelativeRoot/architecture-slice-readiness.agent.md"
$decompositionRelativePath = "$canonicalAgentsRelativeRoot/plan-slice-decomposition.agent.md"
$changeRiskOracleRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/oracles.json'
$changeRiskInputRelativePaths = @(
    'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/inputs/CRT-001.md',
    'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/inputs/CRT-002.md',
    'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/inputs/CRT-003.md'
)
$changeRiskInvalidResultRelativePaths = @(
    'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/invalid-results/required-sections-missing.json',
    'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/invalid-results/invalid-enum.json',
    'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/invalid-results/wrong-nested-types.json'
)
$changeRiskReadmeRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/README.md'
$changeRiskTemplateRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/result-template.md'
$changeRiskResultSchemaRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/result.schema.json'
$changeRiskResultSummaryRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/results/2026-08-09.md'
$changeRiskHashRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/agent.sha256'
$scenarioRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/invocation-authorization-scenarios.json'
$decisionOwnershipScenarioRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/decision-ownership-scenarios.json'
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
    $sliceLivingRecordRelativePath,
    $fullCoverageCloseRelativePath,
    $manifestRelativePath,
    $packageReadmeRelativePath,
    $purposeDocumentationRelativePath,
    $processDocumentationRelativePath,
    $fullCoverageDocumentationRelativePath,
    $asrValidationDocumentationRelativePath,
    $canonicalSharedInstructionsRelativePath,
    $installationDocumentationRelativePath,
    $changeRiskRelativePath,
    $architectureReadinessRelativePath,
    $decompositionRelativePath,
    $changeRiskOracleRelativePath,
    $changeRiskReadmeRelativePath,
    $changeRiskTemplateRelativePath,
    $changeRiskResultSchemaRelativePath,
    $changeRiskResultSummaryRelativePath,
    $changeRiskHashRelativePath,
    $scenarioRelativePath,
    $decisionOwnershipScenarioRelativePath,
    $manualReadmeRelativePath,
    $manualTemplateRelativePath,
    $standaloneE2ERelativePath,
    $standaloneFixtureReadmeRelativePath,
    $standaloneFixtureExpectedRelativePath,
    $apmSmokeRelativePath,
    $workflowRelativePath
)
$requiredFiles += $changeRiskInputRelativePaths
$requiredFiles += $changeRiskInvalidResultRelativePaths

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
    Assert-Matches $manifest '(?m)^version:\s*0\.15\.0\s*$' 'package version must be 0.15.0'
    Assert-Matches $manifest '(?m)^includes:\s*auto\s*$' 'package must distribute package-owned .apm primitives via includes: auto'
    Assert-Matches $manifest '(?ms)dependencies:\s*\n\s*apm:\s*\n(?:\s*#[^\n]*\n)*\s*-\s*git:\s*parent\s*\n\s*path:\s*apm-packages/adaptive-implementation-execution\s*$' 'Adaptive dependency must use the Adaptive package boundary only'
    Assert-NotMatches $manifest '\.github/agents/' 'Plan Coverage manifest must not re-own agents via root .github/agents dependencies'
    Assert-NotMatches $manifest '\.github/instructions/' 'Plan Coverage manifest must not re-own shared instructions via root .github/instructions dependencies'
    Assert-NotMatches $manifest 'decision-surface-implementation-owner|bounded-residual-implementation-owner' 'Plan Coverage must not duplicate Adaptive decision-surface / bounded-residual agent ownership'
    Assert-NotMatches $manifest 'adaptive-implementation-execution/\.apm/skills/' 'Plan Coverage must depend on the Adaptive package root, not an internal Skill path'

    foreach ($agentName in $planCoverageOwnedAgentNames) {
        $canonicalAgentRelativePath = "$canonicalAgentsRelativeRoot/$agentName.agent.md"
        Assert-True (Test-Path -LiteralPath (Join-Path $repoRoot $canonicalAgentRelativePath) -PathType Leaf) "Missing canonical Plan Coverage agent: $canonicalAgentRelativePath"
    }
    foreach ($adaptiveAgentName in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/$adaptiveAgentName.agent.md"))) "Adaptive agent $adaptiveAgentName must not be copied into Plan Coverage .apm/agents"
    }

    $adaptiveValidator = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1')
    $designPairValidator = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/design-pair-implementation-execution/scripts/validate.ps1')
    Assert-Matches $adaptiveValidator 'decision-surface-implementation-owner\.agent\.md' 'Adaptive validator must own the decision-surface-implementation-owner agent contract'
    Assert-Matches $adaptiveValidator 'bounded-residual-implementation-owner\.agent\.md' 'Adaptive validator must own the bounded-residual-implementation-owner agent contract'
    Assert-Matches $designPairValidator 'Plan Coverage package version 0\.15\.0' 'Design Pair validator package version pin must be 0.15.0'

    Assert-Matches $skill 'package-owned canonical agent definitions' 'Skill must identify package-owned canonical agents as the contract authority'
    Assert-Matches $skill 'Do not treat `\.github/agents` or `\.codex/agents` as independent contract authorities' 'Skill must reject runtime projections as independent contract authorities'
    Assert-Matches $skill 'Do not require a source checkout of `apm-packages/\.\.\./\.apm/agents/` as a runtime dependency' 'Skill must not require package source checkout at runtime'
    Assert-NotMatches $skill 'source of truth for agent-specific rules.*remains `\.github/agents/\*\.agent\.md`' 'Skill must not treat root .github/agents as the agent contract authority'
    Assert-Matches $skill 'The `design-pair-implementation-execution` package remains a separate package' 'Design Pair must remain a separate package without target-specific qualification'
    Assert-Matches $skill 'both packages are installed for the same target and the user explicitly selects Design Pair' 'Design Pair route must require same-target installation and explicit selection'
    Assert-Matches $skill 'keep `plan-coverage-residual-flow` selection evidence separate from Design Pair implementation route selection evidence' 'Plan Coverage and Design Pair selection evidence must remain separate'
    Assert-Matches $skill 'While Design Pair is waiting, do not fall back to Adaptive' 'Design Pair waiting state must block Adaptive fallback'
    Assert-NotMatches $skill 'formal targets .*copilot.*codex.*agent-skills' 'PR #90 target enumeration must not remain in Plan Coverage'
    Assert-NotMatches $skill 'Plan Coverage parent runtime qualif(?:ication).*Design Pair.*Adaptive.*GitHub Copilot CLI' 'PR #90 Copilot qualification claim must not remain in Plan Coverage'
    Assert-NotMatches $skill 'Plan Coverage Copilot CLI\s+issue' 'PR #90 Copilot qualification issue handoff must not remain in Plan Coverage'

    $changeRisk = Get-NormalizedText (Join-Path $repoRoot $changeRiskRelativePath)
    $architectureReadiness = Get-NormalizedText (Join-Path $repoRoot $architectureReadinessRelativePath)
    $decomposition = Get-NormalizedText (Join-Path $repoRoot $decompositionRelativePath)
    $sharedInstructions = Get-NormalizedText (Join-Path $repoRoot $sharedInstructionsRelativePath)
    $implementationContract = Get-NormalizedText (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/implementation-contract-kernel.agent.md")
    $handoffReview = Get-NormalizedText (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/implementation-handoff-review.agent.md")
    $verificationKernel = Get-NormalizedText (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/verification-kernel.agent.md")
    $gapResolution = Get-NormalizedText (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/coverage-gap-resolution-slice.agent.md")
    $boundedResidualOwner = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/.apm/agents/bounded-residual-implementation-owner.agent.md')
    $packageReadme = Get-NormalizedText (Join-Path $repoRoot $packageReadmeRelativePath)
    $purposeDocumentation = Get-NormalizedText (Join-Path $repoRoot $purposeDocumentationRelativePath)
    $processDocumentation = Get-NormalizedText (Join-Path $repoRoot $processDocumentationRelativePath)
    $fullCoverageDocumentation = Get-NormalizedText (Join-Path $repoRoot $fullCoverageDocumentationRelativePath)
    $asrValidationDocumentation = Get-NormalizedText (Join-Path $repoRoot $asrValidationDocumentationRelativePath)
    $installationDocumentation = Get-NormalizedText (Join-Path $repoRoot $installationDocumentationRelativePath)
    $runtimeQualificationSchema = Get-NormalizedText (Join-Path $packageRoot 'tests/runtime-qualification/result.schema.json')
    $runtimeQualificationScenarioLib = Get-NormalizedText (Join-Path $packageRoot 'scripts/plan-coverage-copilot-scenario-lib.ps1')
    $runtimeQualificationValidator = Get-NormalizedText (Join-Path $packageRoot 'scripts/validate-plan-coverage-runtime-qualification.ps1')
    $sliceLivingRecord = Get-NormalizedText (Join-Path $repoRoot $sliceLivingRecordRelativePath)
    $fullCoverageClose = Get-NormalizedText (Join-Path $repoRoot $fullCoverageCloseRelativePath)
    Assert-Matches $skill '(?m)^documentation_level: standard$' 'full-coverage must record the standard documentation level'
    Assert-Matches $skill '(?m)^selected_process: full-coverage$' 'full-coverage must record the selected process'
    Assert-Matches $skill '(?m)^artifact_mode: slice-living-record$' 'full-coverage must record Living Record artifact mode'
    Assert-Matches $skill 'Do not re-enter each executable slice as a new standard Plan Coverage run' 'full-coverage slices must use the Living Record lifecycle instead of fresh standard re-entry'
    Assert-Matches $skill 'Plan Coverage parent/router is the only repository writer for Slice Living Records and the canonical Coverage Ledger' 'Plan Coverage parent must own both canonical writes'
    Assert-Matches $skill 'base durable artifact budget is `5 \+ executable slice count \+ 1`.*at most `6 \+ executable slice count`' 'full-coverage artifact budget must be explicit'
    Assert-Matches $skill 'cross-thread-handoff.*parallel-write-isolation.*human-approval-wait.*external-audit-evidence.*record-size-limit' 'Artifact Creation Gate reason codes must be complete'
    Assert-Matches $skill 'Before invoking Adaptive.*parent must first apply a matching `Artifact Exceptions` row.*`cross-thread-handoff`.*bounded-residual-implementation-handoff\.md' 'tracked completion handoff must pass the Artifact Creation Gate'
    Assert-Matches $skill 'When invoking the bounded-residual owner.*artifact_mode: slice-living-record.*reentry_handoff_path: plans/<slug>-slice-SL-xxx-decision-surface-reentry-handoff\.md.*output_contract: parent-persisted-handoff-payload.*`NEEDS_DECISION_SURFACE_REENTRY` uses delayed registration.*returns the complete Decision-Surface Re-entry Handoff.*unpersisted parent payload.*applies an `Artifact Exceptions` row.*persists the payload.*resumes `decision-surface-implementation-owner\.agent\.md`' 'tracked re-entry handoff must use delayed parent registration before persistence and decision-surface-owner resume'
    Assert-Matches $skill 'CROSS_SLICE_PARTIAL_WITH_FIX_CANDIDATES.*do not run `residual-decision-gate\.agent\.md`.*coverage-gap-triage\.agent\.md.*coverage-gap-resolution-slice\.agent\.md.*rerun `verification-kernel\.agent\.md`.*rerun `cross-slice-verification-kernel\.agent\.md`' 'FixNow candidates must complete the Living Record repair and re-verification loop before residual decision'
    Assert-Matches $skill 'pre-redesign artifact with no mode.*existing artifact set clearly matches the old contract.*do not silently migrate' 'legacy resume must be recognized without forced migration'
    Assert-Matches $decomposition 'canonical Living Record baseline' 'decomposition must produce Living Record baselines'
    Assert-Matches $decomposition '(?m)^## Artifact Budget\s*$' 'decomposition must emit an Artifact Budget'
    Assert-Matches $decomposition 'Living Recordとcanonical Coverage Ledgerのrepository writerはPlan Coverage parent/routerだけ' 'decomposition must preserve parent-only write ownership'
    Assert-Matches $sliceLivingRecord '(?m)^## Section ownership\s*$' 'Living Record reference must define section ownership'
    Assert-Matches $sliceLivingRecord '(?m)^## Section delta protocol\s*$' 'Living Record reference must define section delta protocol'
    Assert-Matches $sliceLivingRecord '(?m)^## Artifact Creation Gate\s*$' 'Living Record reference must define Artifact Creation Gate'
    Assert-Matches $fullCoverageClose 'cross-slice-verification-kernel.*residual-decision-gate.*separate semantic owners' 'close reference must preserve separate semantic owners'
    Assert-Matches $fullCoverageClose '(?m)^## FixNow Repair Loop\s*$' 'close reference must preserve conditional FixNow repair history'
    Assert-Matches $skill 'Architecture baseline compatibility' 'Plan Coverage parent must own the pre-slice architecture compatibility check'
    Assert-Matches $skill 'Only a current-baseline `Match` may proceed.*`Drift` returns to Architecture Slice Readiness / Elaboration.*`Unclear` fails closed' 'Plan Coverage must fail closed on architecture Drift or Unclear'
    Assert-Matches $sharedInstructions 'Only `Match` may proceed to implementation.*`Drift` returns to Architecture Slice Readiness / Elaboration.*`Unclear` fails closed' 'shared guardrails must require Match before full-coverage implementation'
    Assert-Matches $sharedInstructions 'owns the implementation feedback loop.*for as long as an unresolved decision surface remains' 'shared guardrails must assign decision-surface implementation ownership for as long as the decision surface remains open'
    Assert-Matches $sharedInstructions '`bounded-residual-implementation-owner` owns only the bounded residual completion.*locked contracts and semantics.*`NEEDS_DECISION_SURFACE_REENTRY` only when a new or previously locked decision surface must be reopened' 'shared guardrails must assign bounded-residual completion and use the decision-surface re-entry boundary'
    Assert-Matches $runtimeQualificationSchema '(?s)"decision_surface_execution".*"bounded_residual_handoff".*"bounded_residual_execution".*"bounded_residual_transfer_satisfied"' 'runtime qualification schema must expose semantic-owner connection fields'
    Assert-Matches $runtimeQualificationScenarioLib '(?s)decision_surface_execution = \$decisionSurface.*bounded_residual_handoff = \$handoff.*bounded_residual_execution = \$boundedResidual' 'runtime qualification scenarios must emit semantic-owner connection evidence'
    Assert-Matches $runtimeQualificationValidator 'contains historical 0\.5 field' 'runtime qualification validator must reject historical Adaptive fields for current snapshots'
    Assert-Matches $handoffReview '(?m)^#### Check 11\. Architecture baseline compatibility\s*$' 'implementation handoff review must own the architecture compatibility gate'
    Assert-Matches $handoffReview '\| Slice ID \| Readiness verdict \| Baseline authority \| Baseline identity \| Observed semantics \| Match / Drift / Unclear \| Required action \|' 'implementation handoff review must emit architecture compatibility evidence'
    Assert-Matches $handoffReview '`ArchitectureNotRequired`.*Lightweight architecture baseline' 'ArchitectureNotRequired must retain baseline comparison'
    Assert-Matches $sharedInstructions 'Decision ownership is durable.*SliceLocalContract.*NeedsHumanDecision' 'shared guardrails must preserve upstream decision ownership'
    Assert-Matches $decomposition '(?s)Unresolved Decision Ownership.*Classification.*Decision owner.*Human input required.*Resolution phase' 'decomposition must project decision ownership into every executable slice'
    Assert-Matches $implementationContract '(?m)^## Decision Ownership Gate\s*$' 'implementation contract must define the Decision Ownership Gate'
    $implementationContractLivingMode = [regex]::Match($implementationContract, '(?ms)^### Slice Living Record mode\s*$.*?(?=^### Normal mode\s*$)').Value
    Assert-Matches $implementationContractLivingMode '(?s)Implementation Contract Decisions.*Decision Ownership Gate.*Upstream classification / owner.*Coverage Ledger Delta' 'Slice Living Record implementation-contract output must include the Decision Ownership Gate and ledger delta'
    Assert-Matches $implementationContract 'greenfield item.*`NeedsHumanDecision` にしない' 'implementation contract must not escalate a missing greenfield address by itself'
    Assert-Matches $implementationContract 'credential mechanism.*ManualOnly.*secret' 'implementation contract must separate credential mechanism from the secret value'
    Assert-Matches $handoffReview 'Decision Ownership Gate.*SliceLocalContract.*Blocking として差し戻す' 'handoff review must reject unjustified human escalation'
    Assert-NotMatches $processDocumentation 'Slice preparation and parent review return `Match`' 'active docs must not assign architecture compatibility to removed 3-layer owners'

    Assert-Matches $changeRisk '(?m)^## Bounded runtime sequence\s*$' 'Change Risk Triage must emit a bounded runtime sequence before profile selection'
    foreach ($executionModel in @(
        'Same-process ABI / FFI boundary',
        'Cross-process IPC',
        'Cross-process durable-state observation',
        'External or independently deployed service',
        'Local asynchronous operation / UI-thread handoff',
        'Independent background worker',
        'Persistent queue / replayable job'
    )) {
        Assert-Matches $changeRisk ([regex]::Escape($executionModel)) "Change Risk Triage must classify execution model '$executionModel'"
    }
    Assert-Matches $changeRisk '(?m)^## Why standard-slice is insufficient\s*$' 'Change Risk Triage must emit the full-coverage escalation evidence section'
    Assert-Matches $changeRisk '(?s)Candidate bounded sequence.*Independent implementation slices required.*Shared semantics that must remain fixed before decomposition.*Why one bounded parent pass is insufficient.*Failure mode that decomposition prevents.*Escalation gate result' 'Change Risk Triage must emit all escalation gate fields'
    Assert-Matches $changeRisk '(?s)Recommendation confidence: High / Medium / Low.*Evidence that would lower the profile:.*Evidence that would raise the profile:' 'Change Risk Triage must emit profile confidence audit fields'
    Assert-Matches $changeRisk '`decision-surface-implementation-owner` が actual code と verification evidence を使って判断する' 'Change Risk Triage must defer implementation ownership assessment to the decision-surface owner'
    Assert-NotMatches $changeRisk 'high-implementation-starter|standard-implementation-completer|completion delegability' 'Change Risk Triage must not retain the removed Adaptive ownership contract'
    foreach ($directNonGround in @('authentication / authorization', 'OS API', 'P/Invoke', 'startup wiring', '一つのdurable store', 'local UI asynchronous operation', 'stub / fake', '複数project')) {
        Assert-Matches $changeRisk ([regex]::Escape($directNonGround)) "Change Risk Triage must reject '$directNonGround' as a direct full-coverage ground"
    }
    Assert-Matches $architectureReadiness '(?s)StandardSliceSufficient.*selected_process: standard-slice' 'Architecture Slice Readiness must define the standard-slice route correction'
    Assert-Matches $architectureReadiness '(?s)StandardSliceSufficient.*Decomposition allowed now: No.*implementation-contract-kernel\.agent\.md.*runtime-contract-kernel\.agent\.md' 'Architecture Slice Readiness must define successful de-escalation routing'
    Assert-Matches $architectureReadiness '(?s)ArchitectureNotRequired.*複数slice.*plan-slice-decomposition\.agent\.md' 'ArchitectureNotRequired must remain decomposition-capable'
    Assert-Matches $decomposition '(?s)StandardSliceSufficient.*decompositionを開始せず' 'Plan Slice Decomposition must reject de-escalated runs'
    Assert-Matches $decomposition '(?s)Why standard-slice is insufficient.*Escalation gate result: Satisfied' 'Plan Slice Decomposition must require the full-coverage escalation gate'
    Assert-Matches $skill 'legacy or stale triage without the current escalation gate must return to `change-risk-triage\.agent\.md`' 'Plan Coverage must rerun legacy pre-decomposition triage'
    Assert-Matches $skill 'already has decomposition or slice implementation evidence.*not dismantled by retrospective de-escalation' 'Plan Coverage must preserve post-decomposition artifact mode'

    $sectionDeltaContracts = @(
        @{ Path = "$canonicalAgentsRelativeRoot/change-risk-triage.agent.md"; Section = 'Slice Risk / Guardrail Selection'; Owner = 'change-risk-triage' },
        @{ Path = "$canonicalAgentsRelativeRoot/implementation-contract-kernel.agent.md"; Section = 'Implementation Contract Decisions'; Owner = 'implementation-contract-kernel' },
        @{ Path = "$canonicalAgentsRelativeRoot/runtime-contract-kernel.agent.md"; Section = 'Runtime Contract'; Owner = 'runtime-contract-kernel' },
        @{ Path = "$canonicalAgentsRelativeRoot/test-design-kernel.agent.md"; Section = 'Test Design'; Owner = 'test-design-kernel' },
        @{ Path = "$canonicalAgentsRelativeRoot/implementation-handoff-review.agent.md"; Section = 'Inline Ready Gate'; Owner = 'implementation-handoff-review' },
        @{ Path = "$canonicalAgentsRelativeRoot/verification-kernel.agent.md"; Section = 'Verification Result'; Owner = 'verification-kernel' },
        @{ Path = "$canonicalAgentsRelativeRoot/coverage-gap-triage.agent.md"; Section = 'Slice Residuals / Handoff'; Owner = 'coverage-gap-triage' },
        @{ Path = "$canonicalAgentsRelativeRoot/coverage-gap-resolution-slice.agent.md"; Section = 'Gap Repair Evidence'; Owner = 'coverage-gap-resolution-slice' },
        @{ Path = "$canonicalAgentsRelativeRoot/implementation-contract-review-kernel.agent.md"; Section = 'Implementation Contract Decisions / Independent Review'; Owner = 'implementation-contract-review-kernel' }
    )
    foreach ($contract in $sectionDeltaContracts) {
        $contractText = Get-NormalizedText (Join-Path $repoRoot $contract.Path)
        Assert-Matches $contractText 'artifact_mode: slice-living-record' "$($contract.Path) must support Living Record mode"
        Assert-Matches $contractText 'output_contract: section-delta' "$($contract.Path) must require section-delta output"
        Assert-Matches $contractText ([regex]::Escape("Target section: $($contract.Section)")) "$($contract.Path) must target its owned section"
        Assert-Matches $contractText ([regex]::Escape("Semantic owner: $($contract.Owner)")) "$($contract.Path) must identify its semantic owner"
        Assert-Matches $contractText 'Plan Coverage parent/router.*(?:only|唯一|だけ)' "$($contract.Path) must leave repository writes to the parent"
    }
    $crossContract = Get-NormalizedText (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/cross-slice-verification-kernel.agent.md")
    $residualContract = Get-NormalizedText (Join-Path $repoRoot "$canonicalAgentsRelativeRoot/residual-decision-gate.agent.md")
    Assert-Matches $crossContract 'Target section: Cross-Slice Verification' 'cross-slice verification must target its close-record section'
    Assert-Matches $residualContract 'Target section: Residual Decision' 'residual decision must target its close-record section'
    Assert-Matches $verificationKernel 'pending.*ledger delta|未適用.*Coverage Ledger Delta|Coverage Ledger Delta.*未適用' 'verification must fail closed on pending earlier ledger deltas'
    $gapResolutionLivingMode = [regex]::Match($gapResolution, '(?ms)^#### Slice Living Record mode\s*$.*?(?=^#### Normal / legacy-separate mode\s*$)').Value
    if ([string]::IsNullOrWhiteSpace($gapResolutionLivingMode)) { throw 'coverage-gap-resolution-slice must define a bounded Slice Living Record implementation-contract precondition.' }
    Assert-NotMatches $gapResolutionLivingMode 'plans/<ticket-or-slug>-implementation-contract-kernel\.md' 'Living Record gap resolution must not authorize or target a separate implementation-contract artifact'
    Assert-Matches $gapResolutionLivingMode '(?s)Implementation Contract Decisions.*別の implementation contract artifactを作成せず.*implementation-contract-kernel\.agent\.md.*output_contract: section-delta.*resume condition' 'Living Record gap resolution must request the implementation-contract semantic owner and wait for parent-applied deltas'
    Assert-Matches $boundedResidualOwner '(?s)UNPERSISTED_PARENT_PAYLOAD.*reentry_handoff_path.*output_contract: parent-persisted-handoff-payload.*Artifact Exceptions.*起動してはいけません' 'bounded-residual owner re-entry must return an unpersisted payload and leave gate/persistence writes to the Plan Coverage parent'

    Assert-Matches $packageReadme '(?s)full-coverage.*each Slice Living Record.*slice-local risk and required kernel section deltas.*architecture baseline compatibility: Match.*Adaptive Implementation.*independent verification.*Full-Coverage Close Record.*cross-slice-verification.*residual-decision-gate' 'package README must describe the Living Record lifecycle in order'
    Assert-Matches $packageReadme 'base artifact budget.*parent control-plane 5件.*sliceごとにLiving Record 1件.*final close 1件' 'package README must document the artifact budget'
    Assert-Matches $packageReadme 'pre-redesign run.*explicit legacy/separate mode.*silent migration' 'package README must document legacy resume compatibility'
    Assert-Matches $packageReadme 'implementation-realization gap.*Implementation Contract Decisions.*別artifactやsectionを作成せず.*section-delta' 'package README must document implementation-contract owner re-entry for Living Record repairs'
    Assert-Matches $packageReadme 'Decision-Surface Re-entry Handoff.*bounded-residual-implementation-ownerが未保存payload.*parentが例外行を適用.*tracked fileを保存.*decision-surface-implementation-ownerを再開' 'package README must document delayed re-entry handoff registration'
    Assert-Matches $packageReadme 'apm-packages/plan-coverage-residual-flow/\.apm/' 'package README must identify package .apm as canonical authoring source'
    Assert-Matches $packageReadme 'canonical contractを修正するときは `\.apm` を修正する|canonical.*\.apm' 'package README must direct contract edits to .apm'
    Assert-Matches $packageReadme 'Adaptive Implementationは別package ownership|Adaptive Implementation.*separate package|Adaptive package' 'package README must keep Adaptive ownership separate'
    Assert-Matches $processDocumentation 'apm-packages/plan-coverage-residual-flow/\.apm/' 'process docs must identify package .apm as canonical authoring source'
    Assert-Matches $installationDocumentation 'apm-packages/plan-coverage-residual-flow/\.apm/' 'installation docs must identify package .apm as canonical authoring source'
    Assert-Matches $installationDocumentation 'Adaptive Implementation package' 'installation docs must describe Adaptive package-boundary dependency'
    Assert-Matches $purposeDocumentation 'every executable slice becomes one canonical Slice Living Record.*existing semantic agents return owned section deltas.*independently verified.*Full-Coverage Close Record' 'purpose policy must describe the self-contained Living Record lifecycle'
    Assert-Matches $purposeDocumentation 'two-slice base run uses at most eight durable artifacts' 'purpose policy must state the two-slice budget'
    Assert-Matches $fullCoverageDocumentation 'canonical Slice Living Record.*does not re-enter as a fresh standard Plan Coverage run' 'decomposition policy must use Living Records'
    Assert-Matches $fullCoverageDocumentation 'five parent control-plane artifacts, one Living Record per executable slice, and one final close record' 'decomposition policy must state the artifact budget'
    Assert-Matches $processDocumentation '(?m)^## Current process flows\s*$' 'detailed process documentation must identify the current flows'
    Assert-Matches $processDocumentation '(?m)^## Plan Coverage ownership boundary\s*$' 'detailed process documentation must state the current Plan Coverage ownership boundary'
    Assert-Matches $processDocumentation 'full-coverage remains self-contained under Plan Coverage ownership from Architecture Slice Readiness through Residual Decision' 'detailed process documentation must keep full-coverage under Plan Coverage ownership'
    Assert-Matches $processDocumentation 'artifact_mode: slice-living-record.*Plan Coverage parent/router is the only Living Record and canonical ledger writer' 'detailed process documentation must define Living Record ownership'
    Assert-NotMatches $processDocumentation '(?m)^## (?:Agent creation order|Suggested README update|Recommended process flows)\s*$|(?m)^Required changes:\s*$' 'obsolete future agent revision planning must not remain in active process documentation'
    Assert-Matches $asrValidationDocumentation 'Plan Coverage parent compatibility.*`Match`' 'ASR suite must assign architecture compatibility to the Plan Coverage parent'
    Assert-Matches $asrValidationDocumentation '`implementation-handoff-review` Check 11.*records baseline identity.*`Match`' 'ASR suite must require current implementation handoff evidence'
    Assert-NotMatches $asrValidationDocumentation 'slice-prep|slice-impl|Parent Review Gate|Parent review records' 'ASR suite must not assign current compatibility ownership to removed 3-layer stages'

    $activeDocumentation = @($packageReadme, $purposeDocumentation, $processDocumentation, $fullCoverageDocumentation, $asrValidationDocumentation, $installationDocumentation) -join "`n"
    Assert-NotMatches $activeDocumentation 'formal targets .*copilot.*codex.*agent-skills|Plan Coverage parent runtime qualif(?:ication)|Plan Coverage Copilot CLI\s+issue' 'PR #90 Plan Coverage-specific qualification wording must not remain in active documentation'

    $retiredFlowRelativePaths = @(
        'README.md',
        $packageReadmeRelativePath,
        $skillRelativePath,
        $purposeDocumentationRelativePath,
        $processDocumentationRelativePath,
        $fullCoverageDocumentationRelativePath,
        "$canonicalAgentsRelativeRoot/change-risk-triage.agent.md",
        "$canonicalAgentsRelativeRoot/coverage-gap-triage.agent.md",
        "$canonicalAgentsRelativeRoot/cross-slice-verification-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-contract-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-contract-review-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-execution.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-handoff-review.agent.md",
        "$canonicalAgentsRelativeRoot/plan-slice-decomposition.agent.md",
        "$canonicalAgentsRelativeRoot/runtime-contract-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/test-design-kernel.agent.md",
        'apm-packages/plan-coverage-residual-flow/tests/full-coverage-standalone/PCF-001/plans/pcf-001-change-risk-triage.md'
    )
    $retiredFlowPattern = 'full-autonomous-plan-first-flow|Full [Aa]utonomous Plan-first|full autonomous flow|Flow C|plan-generation(?:\.agent\.md)?(?![-A-Za-z0-9_])|plan-review(?:\.agent\.md)?(?![-A-Za-z0-9_])|runtime-evidence(?:\.agent\.md)?(?![-A-Za-z0-9_])|integration-test-design(?:\.agent\.md)?(?![-A-Za-z0-9_])|integration-test-verification-implementation(?:\.agent\.md)?(?![-A-Za-z0-9_])|coverage-gap-resolution(?:\.agent\.md)?(?![-A-Za-z0-9_])|implementation-contract-generation(?:\.agent\.md)?(?![-A-Za-z0-9_])|implementation-contract-review(?:\.agent\.md)?(?![-A-Za-z0-9_])'
    foreach ($relativePath in $retiredFlowRelativePaths) {
        Assert-NotMatches (Get-NormalizedText (Join-Path $repoRoot $relativePath)) $retiredFlowPattern "retired Full Autonomous reference must not remain in $relativePath"
    }

    $rollbackContractRelativePaths = @(
        $skillRelativePath,
        $coverageLedgerRelativePath,
        $packageReadmeRelativePath,
        $sharedInstructionsRelativePath,
        $decompositionRelativePath,
        "$canonicalAgentsRelativeRoot/change-risk-triage.agent.md",
        "$canonicalAgentsRelativeRoot/coverage-gap-resolution-slice.agent.md",
        "$canonicalAgentsRelativeRoot/coverage-gap-triage.agent.md",
        "$canonicalAgentsRelativeRoot/cross-slice-verification-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-contract-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-contract-review-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-execution.agent.md",
        "$canonicalAgentsRelativeRoot/implementation-handoff-review.agent.md",
        "$canonicalAgentsRelativeRoot/residual-decision-gate.agent.md",
        "$canonicalAgentsRelativeRoot/runtime-contract-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/test-design-kernel.agent.md",
        "$canonicalAgentsRelativeRoot/verification-kernel.agent.md",
        $processDocumentationRelativePath,
        $purposeDocumentationRelativePath,
        $fullCoverageDocumentationRelativePath,
        $asrValidationDocumentationRelativePath
    )
    $prohibitedRollbackPatterns = @(
        '(?m)^artifact_mode:\s*compact-slice-record-v2\s*$',
        '(?m)^## Parent Orchestration State\s*$',
        '(?m)^## Parent Authorization\s*$',
        'Slice Preparation Delta',
        'Full-Coverage Final Record',
        '(?m)^artifact_mode:\s*full-coverage-slice-v2\s*$',
        '(?m)^artifact_mode:\s*legacy-split-v1\s*$',
        'slice-prep\.agent\.md',
        'slice-impl\.agent\.md'
    )
    foreach ($relativePath in $rollbackContractRelativePaths) {
        $contractText = Get-NormalizedText (Join-Path $repoRoot $relativePath)
        foreach ($pattern in $prohibitedRollbackPatterns) {
            Assert-NotMatches $contractText $pattern "PR #80 compact-v2 semantic '$pattern' must not remain in $relativePath"
        }
    }

    $coverageLedgerPath = Join-Path $repoRoot $coverageLedgerRelativePath
    $sliceLivingRecordPath = Join-Path $repoRoot $sliceLivingRecordRelativePath
    $fullCoverageClosePath = Join-Path $repoRoot $fullCoverageCloseRelativePath

    $changeRiskOracles = @(Get-Content -Raw -LiteralPath (Join-Path $repoRoot $changeRiskOracleRelativePath) | ConvertFrom-Json)
    Assert-True ($changeRiskOracles.Count -eq 3) 'Change Risk Triage oracle must contain exactly CRT-001 through CRT-003'
    Assert-True ((@($changeRiskOracles.id) -join ',') -ceq 'CRT-001,CRT-002,CRT-003') 'Change Risk Triage oracle IDs must be ordered CRT-001 through CRT-003'
    Assert-True ((@($changeRiskOracles.expected_profile) -join ',') -ceq 'standard-slice,standard-slice,full-coverage') 'Change Risk Triage expected profiles must preserve both de-escalation cases and one positive full-coverage case'
    Assert-True ((@($changeRiskOracles.escalation_gate) -join ',') -ceq 'NotSatisfied,NotSatisfied,Satisfied') 'Change Risk Triage escalation results must reject CRT-001/002 and satisfy CRT-003'

    foreach ($inputRelativePath in $changeRiskInputRelativePaths) {
        $inputText = Get-NormalizedText (Join-Path $repoRoot $inputRelativePath)
        Assert-NotMatches $inputText '(?i)expected[_ -]?(?:profile|execution|gate)|escalation[_ -]?gate|recommended[_ -]?profile|standard-slice|full-coverage|NotSatisfied|Satisfied' "$inputRelativePath must not expose oracle answers"
    }

    $requiredExecutionModels = @(
        'Same-process ABI / FFI boundary',
        'Local asynchronous operation / UI-thread handoff',
        'Cross-process durable-state observation'
    )
    foreach ($executionModel in $requiredExecutionModels) {
        Assert-True (@($changeRiskOracles[0].execution_models) -ccontains $executionModel) "CRT-001 must include execution model '$executionModel'"
    }
    Assert-True (@($changeRiskOracles[1].execution_models) -ccontains 'Cross-process IPC') 'CRT-002 must include Cross-process IPC'
    Assert-True ((@($changeRiskOracles[1].execution_models) -join ',') -ceq 'Cross-process IPC') 'CRT-002 must classify only its direct cross-process message hop'
    Assert-True ([int]$changeRiskOracles[2].independent_slice_count -eq 2) 'CRT-003 oracle must require independent runtime slices'
    Assert-True (@($changeRiskOracles[2].execution_models) -ccontains 'External or independently deployed service') 'CRT-003 must classify its independently released runtime components'

    $changeRiskReadme = Get-NormalizedText (Join-Path $repoRoot $changeRiskReadmeRelativePath)
    $changeRiskTemplate = Get-NormalizedText (Join-Path $repoRoot $changeRiskTemplateRelativePath)
    $changeRiskResultSchema = Get-NormalizedText (Join-Path $repoRoot $changeRiskResultSchemaRelativePath) | ConvertFrom-Json
    Assert-Matches $changeRiskReadme 'fresh session three times' 'Change Risk Triage manual smoke must require three fresh sessions per scenario'
    Assert-Matches $changeRiskReadme 'Never provide `oracles.json`' 'Change Risk Triage manual smoke must hide oracle answers from model sessions'
    Assert-Matches $changeRiskReadme 'CI does not invoke an external model' 'Change Risk Triage CI evidence must remain separate from external-model observations'
    Assert-Matches $changeRiskReadme '`NOT RUN` and `UNOBSERVABLE` do not count as passes' 'Change Risk Triage manual smoke must not count missing observations as passes'
    Assert-Matches $changeRiskReadme 'historical evidence for the agent revision recorded in that summary' 'Change Risk Triage must identify dated observations as historical evidence'
    Assert-Matches $changeRiskReadme 'those observations do not qualify the current contract' 'Change Risk Triage must not reuse historical observations for the current contract'
    Assert-True ($changeRiskResultSchema.additionalProperties -eq $false) 'Change Risk Triage result schema must reject unknown top-level fields'
    Assert-True ((@($changeRiskResultSchema.required) -ccontains 'bounded_runtime_sequence') -and (@($changeRiskResultSchema.required) -ccontains 'escalation_gate_result')) 'Change Risk Triage result schema must require bounded sequence and escalation evidence'
    Assert-True (@($changeRiskResultSchema.properties.execution_models.items.enum).Count -eq 7) 'Change Risk Triage result schema must enumerate all seven execution models'
    foreach ($invalidRelativePath in $changeRiskInvalidResultRelativePaths) {
        $invalidResult = Get-Content -LiteralPath (Join-Path $repoRoot $invalidRelativePath) -Raw | ConvertFrom-Json
        $invalidErrors = @(Get-ChangeRiskResultSchemaErrors $invalidResult)
        Assert-True ($invalidErrors.Count -gt 0) "$invalidRelativePath must be rejected by nested result-schema validation"
    }
    foreach ($scenarioId in 'CRT-001', 'CRT-002', 'CRT-003') {
        foreach ($run in 1..3) {
            Assert-Matches $changeRiskTemplate "(?m)^\| $scenarioId \| $run \| NOT RUN \|" "Change Risk Triage result template must include $scenarioId run $run"
        }
    }

    $changeRiskResultRoot = Join-Path $repoRoot 'apm-packages/plan-coverage-residual-flow/tests/change-risk-triage/results'
    $changeRiskResultFiles = @(Get-ChildItem -LiteralPath $changeRiskResultRoot -File -Filter 'CRT-*-run-*.json' | Sort-Object Name)
    Assert-True ($changeRiskResultFiles.Count -eq 9) 'Change Risk Triage results must contain exactly nine fresh-session JSON observations'
    $expectedResultNames = @(
        foreach ($scenarioId in 'CRT-001', 'CRT-002', 'CRT-003') {
            foreach ($run in 1..3) { "$scenarioId-run-$run.json" }
        }
    )
    Assert-True ((@($changeRiskResultFiles.Name) -join ',') -ceq ($expectedResultNames -join ',')) 'Change Risk Triage result filenames must cover three runs for every scenario'
    foreach ($resultFile in $changeRiskResultFiles) {
        $result = Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json
        $nameMatch = [regex]::Match($resultFile.Name, '^(?<scenario>CRT-00[1-3])-run-(?<run>[1-3])\.json$')
        Assert-True ($nameMatch.Success -and $result.scenario_id -ceq $nameMatch.Groups['scenario'].Value) "$($resultFile.Name) scenario ID must match its filename"
        $schemaErrors = @(Get-ChangeRiskResultSchemaErrors $result)
        Assert-True ($schemaErrors.Count -eq 0) "$($resultFile.Name) must satisfy every nested result schema constraint: $($schemaErrors -join '; ')"

        $oracle = @($changeRiskOracles | Where-Object { $_.id -ceq $result.scenario_id })[0]
        $actualModelSet = @($result.execution_models | Sort-Object)
        $oracleModelSet = @($oracle.execution_models | Sort-Object)
        Assert-True (($actualModelSet -join ',') -ceq ($oracleModelSet -join ',')) "$($resultFile.Name) execution-model classification set must match its CI-only oracle"
        Assert-True (@($result.execution_models | Select-Object -Unique).Count -eq @($result.execution_models).Count) "$($resultFile.Name) execution models must be unique"
        Assert-True ($result.recommended_profile -ceq $oracle.expected_profile) "$($resultFile.Name) profile must match its CI-only oracle"
        Assert-True ($result.escalation_gate_result -ceq $oracle.escalation_gate) "$($resultFile.Name) escalation gate must match its CI-only oracle"
        Assert-True (@($result.independent_implementation_slices_required).Count -eq [int]$oracle.independent_slice_count) "$($resultFile.Name) independent slice count must match its CI-only oracle"
        if ($null -ne $oracle.minimum_shared_semantic_count) {
            Assert-True (@($result.shared_semantics_that_must_remain_fixed).Count -ge [int]$oracle.minimum_shared_semantic_count) "$($resultFile.Name) must retain the minimum source-backed shared semantics"
        }
    }
    $changeRiskResultSummary = Get-NormalizedText (Join-Path $repoRoot $changeRiskResultSummaryRelativePath)
    foreach ($resultName in $expectedResultNames) {
        Assert-Matches $changeRiskResultSummary ([regex]::Escape($resultName)) "Change Risk Triage summary must link $resultName"
    }
    Assert-Matches $changeRiskResultSummary '(?m)^\| CRT-003 \| Yes \| Yes \| Yes \| PASS \|$' 'Change Risk Triage summary must record CRT-003 consistency PASS'

    $hashPin = (Get-NormalizedText (Join-Path $repoRoot $changeRiskHashRelativePath)).Trim()
    $hashMatch = [regex]::Match($hashPin, '\A(?<hash>[0-9a-f]{64})\s+apm-packages/plan-coverage-residual-flow/\.apm/agents/change-risk-triage\.agent\.md\z')
    Assert-True $hashMatch.Success 'Change Risk Triage agent hash pin must use the canonical package agent path'
    if ($hashMatch.Success) {
        $actualChangeRiskHash = Get-NormalizedTextSha256 (Join-Path $repoRoot $changeRiskRelativePath)
        Assert-True ($actualChangeRiskHash -ceq $hashMatch.Groups['hash'].Value) 'Change Risk Triage agent hash pin is stale'
        Assert-Matches $changeRiskResultSummary 'e46425255412840c59fe57a36d1705b76c43ca90629fa85bed6b40630b694077' 'Change Risk Triage historical result summary must preserve its observed agent revision'
        Assert-True ($actualChangeRiskHash -cne 'e46425255412840c59fe57a36d1705b76c43ca90629fa85bed6b40630b694077') 'Change Risk Triage current contract must not reuse the historical agent revision'
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

    $decisionOwnershipScenarios = @(Get-Content -Raw -LiteralPath (Join-Path $repoRoot $decisionOwnershipScenarioRelativePath) | ConvertFrom-Json)
    Assert-True ($decisionOwnershipScenarios.Count -eq 3) 'Decision ownership fixture must contain exactly DO-001 through DO-003'
    Assert-True ((@($decisionOwnershipScenarios.id) -join ',') -ceq 'DO-001,DO-002,DO-003') 'Decision ownership scenario IDs must be ordered DO-001 through DO-003'
    foreach ($scenario in $decisionOwnershipScenarios) {
        foreach ($field in @('name', 'upstream_artifact_markdown', 'task', 'expected_verdicts', 'required_markers', 'forbidden_human_requests', 'manual_acceptance')) {
            Assert-True ($scenario.psobject.Properties.Name -contains $field) "Decision ownership scenario $($scenario.id) missing field: $field"
        }
    }
    $do001 = @($decisionOwnershipScenarios | Where-Object { $_.id -eq 'DO-001' } | Select-Object -First 1)
    Assert-True ($do001.Count -eq 1) 'DO-001 must exist exactly once'
    if ($do001.Count -eq 1) {
        foreach ($field in @('artifact_mode', 'living_record_path', 'canonical_coverage_ledger', 'output_contract')) {
            Assert-True ($do001[0].psobject.Properties.Name -contains $field) "DO-001 missing Slice Living Record field: $field"
        }
        Assert-True ($do001[0].artifact_mode -ceq 'slice-living-record') 'DO-001 must execute the Slice Living Record path'
        Assert-True ($do001[0].output_contract -ceq 'section-delta') 'DO-001 must require a section-delta output'
    }
    Assert-True (-not (@($decisionOwnershipScenarios | Where-Object { $_.id -eq 'DO-001' }).expected_verdicts -contains 'NEEDS_HUMAN_DECISION')) 'DO-001 must not expect NeedsHumanDecision'
    Assert-True (-not (@($decisionOwnershipScenarios | Where-Object { $_.id -eq 'DO-002' }).expected_verdicts -contains 'NEEDS_HUMAN_DECISION')) 'DO-002 must not expect NeedsHumanDecision'
    Assert-True ((@($decisionOwnershipScenarios | Where-Object { $_.id -eq 'DO-003' }).expected_verdicts -contains 'NEEDS_HUMAN_DECISION')) 'DO-003 must require an isolated NeedsHumanDecision'

    $manualReadme = Get-NormalizedText (Join-Path $repoRoot $manualReadmeRelativePath)
    $manualTemplate = Get-NormalizedText (Join-Path $repoRoot $manualTemplateRelativePath)
    Assert-Matches $manualReadme 'Scenarios A, B, C, E, G, and H.*not selected.*no Plan Coverage artifact.*no Plan Coverage agent' 'manual smoke must define unauthorized observations'
    Assert-Matches $manualReadme 'Scenarios D and F.*accepts.*existing flow can proceed' 'manual smoke must define authorized observations'
    Assert-Matches $manualReadme '`NOT RUN`.*`UNOBSERVABLE`.*Neither status counts as a pass' 'manual smoke must keep unexecuted or unobservable evidence separate'
    Assert-Matches $manualReadme '(?s)Decision ownership regression smoke.*Codex.*GitHub Copilot CLI.*ManualOnly' 'manual smoke must define the cross-client decision ownership regression boundary'
    Assert-Matches $manualReadme 'DO-001.*Slice Living Record.*section-delta' 'manual smoke must exercise decision ownership through the Slice Living Record path'
    foreach ($scenarioId in 'A'..'H') {
        Assert-Matches $manualTemplate "(?m)^\| $scenarioId \| NOT RUN \|" "manual result template must include Scenario $scenarioId"
    }
    foreach ($scenarioId in @('DO-001', 'DO-002', 'DO-003')) {
        Assert-Matches $manualTemplate "(?m)^\| $scenarioId \| NOT RUN \|" "manual result template must include decision ownership scenario $scenarioId"
    }

    $standaloneE2E = Get-NormalizedText (Join-Path $repoRoot $standaloneE2ERelativePath)
    $copilotQualification = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/plan-coverage-residual-flow/scripts/run-plan-coverage-copilot-qualification.ps1')
    $standaloneFixtureReadme = Get-NormalizedText (Join-Path $repoRoot $standaloneFixtureReadmeRelativePath)
    $standaloneFixtureExpected = Get-NormalizedText (Join-Path $repoRoot $standaloneFixtureExpectedRelativePath)
    $apmSmoke = Get-NormalizedText (Join-Path $repoRoot $apmSmokeRelativePath)
    $workflow = Get-NormalizedText (Join-Path $repoRoot $workflowRelativePath)
    Assert-Matches $packageReadme 'Standalone full-coverage E2E fixture' 'package README must link the standalone full-coverage E2E fixture'
    Assert-Matches $packageReadme 'validate-plan-coverage-full-coverage-e2e\.ps1' 'package README must document the standalone E2E command'
    Assert-Matches $packageReadme '外部modelは実行しない.*自律実行した証拠ではありません' 'package README must separate deterministic evidence from external-model evidence'
    Assert-Matches $standaloneFixtureReadme 'deterministic test-only fixture' 'PCF-001 must identify itself as deterministic test-only evidence'
    Assert-Matches $standaloneFixtureReadme 'does not invoke an external model' 'PCF-001 must not claim external-model execution evidence'
    Assert-Matches $standaloneFixtureReadme '(?s)current or installed Plan Coverage references.*section ownership.*production binding.*Coverage Ledger Delta.*artifact budget.*negative cases' 'PCF-001 must describe current authority-derived Living Record validation'
    Assert-Matches $standaloneFixtureExpected '(?s)"ReadyForRiskTriage".*"full-coverage".*"ReadyForSliceDecomposition".*"SL-001".*"SL-002".*"CROSS_SLICE_VERIFIED".*"READY_TO_CLOSE_WITH_NO_RESIDUALS"' 'PCF-001 must preserve the full lifecycle stage order'
    Assert-Matches $standaloneE2E '\[string\]\$InstalledRoot' 'standalone E2E validator must support installed-root contract resolution'
    foreach ($authorityCheck in @('Get-MarkdownTemplate', 'Add-TemplateShapeErrors', 'SliceLivingRecord', 'FullCoverageClose')) {
        Assert-Matches $standaloneE2E ([regex]::Escape($authorityCheck)) "standalone E2E validator must enforce current artifact authority through $authorityCheck"
    }
    Assert-Matches $copilotQualification "'### Decision Ownership Gate'" 'Slice Living Record qualification oracle must require the agent-defined heading level'
    Assert-Matches $copilotQualification '\$decisionOutputText = \[string\]\$Run\.Stdout' 'decision ownership verdicts must be read from model output, not the loaded agent contract'
    Assert-Matches $copilotQualification '(?s)\[int\]\$Run\.ExitCode -ne 0.*\$failures\.Add' 'decision ownership oracle must fail closed on Copilot CLI errors'
    Assert-Matches $copilotQualification '(?s)terminalVerdictPattern.*Self-check / Readiness verdict.*terminalVerdictMatches\.Count -ne 1' 'decision ownership oracle must compare one explicit terminal verdict'
    Assert-Matches $copilotQualification '(?s)function New-RunFromEvidenceDir.*\[int\]\$ExitCode.*ExitCode = \$ExitCode' 'kept evidence re-evaluation must preserve the recorded Copilot exit code'
    Assert-Matches $copilotQualification '(?s)\$priorExitCode.*exit_code.*New-RunFromEvidenceDir.*\$priorExitCode' 'decision ownership re-evaluation must pass the recorded exit code into the oracle'
    Assert-Matches $copilotQualification '(?s)decision-ownership-\$sid.*Evaluate-DecisionOwnershipScenario' 'kept qualification evidence must re-evaluate decision ownership scenarios'
    foreach ($negativeCase in @('missing-required-section', 'owner-outside-section', 'missing-independent-verification', 'missing-production-binding', 'fake-only-evidence', 'xc-field-continuity-missing', 'mapping-missing', 'pending-before-verification', 'pending-before-close', 'ledger-contradiction', 'ungated-separate-artifact', 'artifact-budget-exceeded', 'required-slice-unverified', 'residual-before-cross', 'forced-legacy-migration', 'mixed-artifact-mode', 'removed-three-layer-semantics')) {
        Assert-Matches $standaloneE2E ([regex]::Escape($negativeCase)) "standalone E2E validator must fail closed for $negativeCase"
    }
    Assert-Matches $standaloneE2E 'foreach \(\$verdict in @\(''Drift'', ''Unclear''\)\)' 'standalone E2E validator must fail closed for architecture Drift and Unclear'
    Assert-Matches $apmSmoke '(?s)validate-plan-coverage-full-coverage-e2e\.ps1.*-InstalledRoot' 'remote APM smoke must execute standalone E2E against the installed closure'
    Assert-Matches $apmSmoke 'copilot,codex,agent-skills' 'APM smoke must install all Plan Coverage targets'
    Assert-Matches $apmSmoke 'decision-surface-implementation-owner' 'APM smoke must verify Adaptive assets arrive transitively'
    Assert-Matches $workflow 'validate-plan-coverage-full-coverage-e2e\.ps1' 'Plan Coverage workflow must execute standalone E2E in source mode'

}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure -ErrorAction Continue
    }
    throw "Plan Coverage Residual Flow validation failed with $($failures.Count) error(s)."
}

Write-Host 'Plan Coverage Residual Flow validation: PASS'
