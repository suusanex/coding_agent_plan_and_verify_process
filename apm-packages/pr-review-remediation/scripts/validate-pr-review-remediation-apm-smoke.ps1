[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repository,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref,

    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Invoke-NativeJson([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    $output = & $FilePath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE. Output: $output" }
    try { return $output | ConvertFrom-Json }
    catch { throw "$Description returned invalid JSON. Output: $output" }
}

function Invoke-NativeFailure([string]$FilePath, [string[]]$Arguments, [string]$Description, [string]$ExpectedPattern) {
    $output = & $FilePath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        throw "$Description unexpectedly succeeded."
    }
    if ($output -notmatch $ExpectedPattern) {
        throw "$Description did not expose the expected failure. Output: $output"
    }
}

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing ${Description}: $Path"
    }
}

function Assert-Contains([string]$Path, [string]$Pattern, [string]$Description) {
    Assert-File $Path $Description
    if ((Get-Content -Raw -LiteralPath $Path) -notmatch $Pattern) {
        throw "$Description does not contain the required contract: $Path"
    }
}

function Assert-NotContains([string]$Path, [string]$Pattern, [string]$Description) {
    Assert-File $Path $Description
    if ((Get-Content -Raw -LiteralPath $Path) -match $Pattern) {
        throw "$Description contains a forbidden contract: $Path"
    }
}

function Assert-Absent([string]$Path, [string]$Description) {
    if (Test-Path -LiteralPath $Path) {
        throw "Unexpected ${Description}: $Path"
    }
}

function Assert-ApmCanonicalAgent([string]$ModulesRoot, [string]$FileName) {
    $matches = @(Get-ChildItem -LiteralPath $ModulesRoot -Recurse -Force -File -Filter $FileName | Where-Object {
        $_.Directory.Name -eq 'agents' -and $_.Directory.Parent.Name -eq '.apm'
    })
    if ($matches.Count -eq 0) {
        throw "Missing canonical agent in APM modules: $FileName"
    }
}

$apmVersion = & $ApmExecutable --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "APM executable failed: $ApmExecutable"
}
if ($apmVersion -notmatch '\b0\.26\.0\b') {
    throw "APM 0.26.0 is required for the reproducible smoke. Observed: $($apmVersion.Trim())"
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$scratch = Join-Path $tempRoot ("pr-review-remediation-apm-smoke-" + [guid]::NewGuid().ToString('N'))
$outside = Join-Path $tempRoot ("pr-review-remediation-apm-outside-" + [guid]::NewGuid().ToString('N'))
$scratch = [System.IO.Path]::GetFullPath($scratch)
if (-not $scratch.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe scratch path: $scratch"
}

$previousPythonUtf8 = $env:PYTHONUTF8
$previousPythonIoEncoding = $env:PYTHONIOENCODING
New-Item -ItemType Directory -Path (Join-Path $scratch '.codex') -Force | Out-Null
New-Item -ItemType Directory -Path $outside -Force | Out-Null
Set-Content -LiteralPath (Join-Path $scratch 'AGENTS.md') -Value 'sentinel-agents'
Set-Content -LiteralPath (Join-Path $scratch '.codex/config.toml') -Value 'sentinel-config'
$agentsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch 'AGENTS.md')).Hash
$configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch '.codex/config.toml')).Hash

try {
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    $packageSpec = "$Repository/apm-packages/pr-review-remediation#$Ref"

    Push-Location $scratch
    try {
        Invoke-Native $ApmExecutable @('install', $packageSpec, '--target', 'codex,agent-skills', '--https') 'remote APM install'
    }
    finally {
        Pop-Location
    }

    $deployedReviewSkill = Join-Path $scratch '.agents/skills/pr-review-remediation'
    $deployedGoalReviewSkill = Join-Path $scratch '.agents/skills/goal-context-pr-review'
    foreach ($relative in @(
        'SKILL.md',
        'scripts/collect-pr-review-context.cs',
        'templates/local-review-findings.md',
        'templates/review-plan.md',
        'references/usage.md',
        'references/migration.md',
        'references/troubleshooting.md'
    )) {
        Assert-File (Join-Path $deployedReviewSkill $relative) "deployed review Skill asset $relative"
    }
    foreach ($relative in @(
        'SKILL.md',
        'scripts/select-goal-context.cs',
        'scripts/manage-same-parent-review.cs',
        'scripts/execute-reviewer.cs',
        'scripts/manage-review-cycle.cs',
        'templates/purpose-review-findings.md',
        'templates/round-assessment.example.json',
        'templates/review-result.example.json',
        'templates/review-round-result.example.json',
        'references/design.md',
        'references/usage.md',
        'references/troubleshooting.md',
        'references/execute-reviewer.md'
    )) {
        Assert-File (Join-Path $deployedGoalReviewSkill $relative) "deployed Goal Context review Skill asset $relative"
    }
    Assert-Absent (Join-Path $scratch '.agents/skills/adaptive-implementation-execution') 'Adaptive Skill in canonical same-parent installation'
    $parts = $Repository.Split('/')
    $repositoryModule = Join-Path $scratch ("apm_modules/{0}/{1}" -f $parts[0], $parts[1])
    foreach ($agent in @(
        'local-reviewer.agent.md',
        'purpose-reviewer.agent.md',
        'review-planner.agent.md'
    )) {
        Assert-ApmCanonicalAgent (Join-Path $scratch 'apm_modules') $agent
    }
    $installedReviewHelper = Join-Path $repositoryModule 'apm-packages/pr-review-remediation/scripts/sync-pr-review-remediation-local.cs'
    $installedFakeGh = Join-Path $repositoryModule 'apm-packages/pr-review-remediation/tests/fixtures/fake-gh.cs'
    Assert-File $installedReviewHelper 'installed review profile helper'
    Assert-File $installedFakeGh 'installed fake GitHub fixture'

    Invoke-Native 'dotnet' @('run', '--file', $installedReviewHelper, '--', $scratch) 'README review profile synchronization'
    Invoke-Native 'dotnet' @('run', '--file', $installedReviewHelper, '--', $scratch, '--check') 'README review profile check'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedReviewSkill 'scripts/collect-pr-review-context.cs'), '--', '--help') 'deployed relative collector help'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedGoalReviewSkill 'scripts/select-goal-context.cs'), '--', '--help') 'deployed Goal Context selector help'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedGoalReviewSkill 'scripts/manage-same-parent-review.cs'), '--', '--help') 'deployed canonical same-parent manager help'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedGoalReviewSkill 'scripts/execute-reviewer.cs'), '--', '--help') 'deployed deterministic reviewer executor help'
    Invoke-Native 'dotnet' @('run', '--file', (Join-Path $deployedGoalReviewSkill 'scripts/manage-review-cycle.cs'), '--', '--help') 'deployed multi-round cycle manager help'

    $freeFormGoalContext = Join-Path $scratch 'consumer-goal.txt'
    Set-Content -LiteralPath $freeFormGoalContext -Encoding utf8 -NoNewline -Value 'Users should complete review and remediation in the original task without copying structured metadata into another task.'

    Invoke-Native 'git' @('-C', $scratch, 'init', '-b', 'feature') 'empty consumer Git initialization'
    $fakeGhPublish = Join-Path $scratch '.smoke/fake-gh'
    Invoke-Native 'dotnet' @('publish', $installedFakeGh, '--output', $fakeGhPublish, '--disable-build-servers') 'installed fake GitHub fixture publish'
    $fakeGhExecutable = Join-Path $fakeGhPublish ($(if ($IsWindows) { 'fake-gh.exe' } else { 'fake-gh' }))
    Assert-File $fakeGhExecutable 'published fake GitHub fixture'
    $env:FAKE_GH_SCENARIO = 'same-parent-ready'
    $env:FAKE_GH_STATE = Join-Path $scratch '.smoke/fake-gh-state.txt'
    $env:FAKE_GH_HEAD_OID = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $startResult = Invoke-NativeJson 'dotnet' @(
        'run', '--file', (Join-Path $deployedGoalReviewSkill 'scripts/manage-same-parent-review.cs'), '--',
        'start', '--repository-root', $scratch, '--pr', '123', '--goal-context', 'consumer-goal.txt',
        '--gh-executable', $fakeGhExecutable, '--copilot-timeout-seconds', '3', '--format', 'json'
    ) 'installed canonical same-parent start from empty consumer repository'
    if ($startResult.status -ne 'Round1Reviewing' -or -not $startResult.runRoot) {
        throw 'Installed canonical same-parent manager did not reach Round1Reviewing from the published consumer commands.'
    }
    Assert-Contains ($env:FAKE_GH_STATE + '.copilot-requested') 'pr edit 123 --repo fixture/goal-context-review --add-reviewer @copilot' 'installed canonical Copilot review request'

    $selectorScript = Join-Path $deployedGoalReviewSkill 'scripts/select-goal-context.cs'
    $linkTestRoot = Join-Path $scratch 'selector-link-tests'
    $linkDocs = Join-Path $linkTestRoot 'docs'
    New-Item -ItemType Directory -Path $linkDocs -Force | Out-Null
    $outsideGoal = Join-Path $outside 'goal-context-outside.md'
    Copy-Item -LiteralPath $freeFormGoalContext -Destination $outsideGoal
    New-Item -ItemType SymbolicLink -Path (Join-Path $linkDocs 'goal-context-linked.md') -Target $outsideGoal | Out-Null
    Invoke-NativeFailure 'dotnet' @(
        'run', '--file', $selectorScript, '--', '--repository-root', $scratch,
        '--goal-context', 'selector-link-tests/docs/goal-context-linked.md',
        '--out', 'selector-link-tests/selection.json'
    ) 'file symlink input escape' 'canonical repository root'

    New-Item -ItemType SymbolicLink -Path (Join-Path $linkTestRoot 'outside-search') -Target $outside | Out-Null
    Invoke-NativeFailure 'dotnet' @(
        'run', '--file', $selectorScript, '--', '--repository-root', $scratch,
        '--search-root', 'selector-link-tests/outside-search',
        '--out', 'selector-link-tests/search-selection.json'
    ) 'directory symlink search escape' 'canonical repository root'

    Copy-Item -LiteralPath $outsideGoal -Destination (Join-Path $linkDocs 'goal-context-valid.md')
    New-Item -ItemType SymbolicLink -Path (Join-Path $linkTestRoot '.review') -Target $outside | Out-Null
    Invoke-NativeFailure 'dotnet' @(
        'run', '--file', $selectorScript, '--', '--repository-root', $scratch,
        '--goal-context', 'selector-link-tests/docs/goal-context-valid.md',
        '--out', 'selector-link-tests/.review/selection.json'
    ) 'directory symlink output escape' 'canonical repository root'

    $profileRoot = Join-Path $scratch '.codex/agents'
    foreach ($profile in @('local-reviewer.toml', 'purpose-reviewer.toml', 'review-planner.toml')) {
        $path = Join-Path $profileRoot $profile
        Assert-Contains $path '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$' "review profile $profile model"
        Assert-Contains $path '(?m)^model_reasoning_effort\s*=\s*"high"\s*$' "review profile $profile reasoning"
        Assert-Contains $path '(?m)^sandbox_mode\s*=\s*"read-only"\s*$' "review profile $profile sandbox"
    }
    Assert-Contains (Join-Path $profileRoot 'local-reviewer.toml') 'developer_instructions\s*=\s*"# Local Reviewer\\n' 'local reviewer full APM contract'
    Assert-Contains (Join-Path $profileRoot 'purpose-reviewer.toml') 'developer_instructions\s*=\s*"# Purpose Reviewer\\n' 'purpose reviewer full APM contract'
    Assert-Contains (Join-Path $profileRoot 'review-planner.toml') 'developer_instructions\s*=\s*"# Review Planner\\n' 'review planner full APM contract'
    Assert-Absent (Join-Path $profileRoot 'high-implementation-starter.toml') 'Adaptive HIGH profile in canonical same-parent installation'
    Assert-Absent (Join-Path $profileRoot 'standard-implementation-completer.toml') 'Adaptive STANDARD profile in canonical same-parent installation'

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch 'AGENTS.md')).Hash -ne $agentsHash) {
        throw 'Remote APM install or profile helpers changed AGENTS.md.'
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch '.codex/config.toml')).Hash -ne $configHash) {
        throw 'Remote APM install or profile helpers changed .codex/config.toml.'
    }

    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'pr-review-remediation' 'APM lock direct package entry'
    Assert-NotContains (Join-Path $scratch 'apm.lock.yaml') 'adaptive-implementation-execution|high-implementation-starter|standard-implementation-completer' 'APM lock canonical Adaptive dependency exclusion'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'local-reviewer' 'APM lock local reviewer dependency entry'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'purpose-reviewer' 'APM lock purpose reviewer dependency entry'
    Assert-Contains (Join-Path $scratch 'apm.lock.yaml') 'review-planner' 'APM lock review planner dependency entry'

    # Expected-failure probes invoke native commands that return non-zero. Reset the
    # process-visible native status so pwsh does not turn a successful smoke into a
    # failed GitHub Actions step on Linux.
    $global:LASTEXITCODE = 0
    Write-Output "PR Review Remediation remote APM smoke: PASS"
    Write-Output "Package: $packageSpec"
    Write-Output "APM: $($apmVersion.Trim())"
}
finally {
    Remove-Item Env:FAKE_GH_SCENARIO -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GH_STATE -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_GH_HEAD_OID -ErrorAction SilentlyContinue
    if ($null -eq $previousPythonUtf8) { Remove-Item Env:PYTHONUTF8 -ErrorAction SilentlyContinue } else { $env:PYTHONUTF8 = $previousPythonUtf8 }
    if ($null -eq $previousPythonIoEncoding) { Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $previousPythonIoEncoding }
    if (Test-Path -LiteralPath $scratch) {
        $resolved = [System.IO.Path]::GetFullPath($scratch)
        if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe scratch path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    if (Test-Path -LiteralPath $outside) {
        $resolvedOutside = [System.IO.Path]::GetFullPath($outside)
        if (-not $resolvedOutside.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe outside fixture path: $resolvedOutside"
        }
        Remove-Item -LiteralPath $resolvedOutside -Recurse -Force
    }
}
