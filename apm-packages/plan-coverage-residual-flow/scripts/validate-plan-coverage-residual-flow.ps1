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
$scenarioRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/invocation-authorization-scenarios.json'
$manualReadmeRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/manual-model-smoke/README.md'
$manualTemplateRelativePath = 'apm-packages/plan-coverage-residual-flow/tests/manual-model-smoke/result-template.md'

$requiredFiles = @(
    $skillRelativePath,
    $coverageLedgerRelativePath,
    $manifestRelativePath,
    $scenarioRelativePath,
    $manualReadmeRelativePath,
    $manualTemplateRelativePath
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
    Assert-Matches $manifest '(?m)^version:\s*0\.9\.1\s*$' 'package version must be 0.9.1'

    $adaptiveValidator = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/adaptive-implementation-execution/scripts/validate-adaptive-implementation-execution.ps1')
    $designPairValidator = Get-NormalizedText (Join-Path $repoRoot 'apm-packages/design-pair-implementation-execution/scripts/validate.ps1')
    Assert-Matches $adaptiveValidator "plan-coverage-residual-flow/apm\.yml'; Version = '0\\\.9\\\.1'" 'Adaptive validator package version pin must be 0.9.1'
    Assert-Matches $designPairValidator 'Plan Coverage package version 0\.9\.1' 'Design Pair validator package version pin must be 0.9.1'

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

}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure -ErrorAction Continue
    }
    throw "Plan Coverage Residual Flow validation failed with $($failures.Count) error(s)."
}

Write-Host 'Plan Coverage Residual Flow validation: PASS'
