[CmdletBinding()]
param(
    [string]$Repository,
    [string]$Ref,
    [string]$Model,
    [string]$CopilotCommand = 'copilot',
    [string]$ResultsDir,
    [string[]]$ScenarioIds,
    [int]$TimeoutSeconds = 1800,
    [switch]$SkipDistributionSmoke,
    [switch]$KeepWorktree,
    [switch]$DescribePayload,
    [switch]$ConfirmExternalModelPayload
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

if ([string]::IsNullOrWhiteSpace($Repository) -xor [string]::IsNullOrWhiteSpace($Ref)) {
    throw 'Repository and Ref must be supplied together.'
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$rqRoot = Join-Path $packageRoot 'tests/runtime-qualification'
$authScenarioPath = Join-Path $packageRoot 'tests/invocation-authorization-scenarios.json'
$schemaPath = Join-Path $rqRoot 'result.schema.json'
$templatePath = Join-Path $rqRoot 'result-template.json'
$stdFixtureRoot = Join-Path $rqRoot 'copilot-cli/standard-slice'
$fullFixtureRoot = Join-Path $rqRoot 'copilot-cli/full-coverage'
$smokeScript = Join-Path $PSScriptRoot 'validate-plan-coverage-residual-flow-apm-smoke.ps1'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'
$canonicalRoot = Join-Path $packageRoot '.apm'

if ([string]::IsNullOrWhiteSpace($ResultsDir)) {
    $ResultsDir = Join-Path $rqRoot 'results'
}
$ResultsDir = [System.IO.Path]::GetFullPath($ResultsDir)

$planCoverageOwnedAgents = @(
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
$adaptiveAgents = @(
    'high-implementation-starter',
    'standard-implementation-completer'
)
$allTrackedAgents = @($planCoverageOwnedAgents + $adaptiveAgents + @('design-pair-implementation-execution'))

function Get-NormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256Text([string]$Text) {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    return Get-Sha256Bytes $bytes
}

function Get-Sha256File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return Get-Sha256Text (Get-NormalizedText $Path)
}

function Get-CanonicalFingerprint([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object {
            $_.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        })
    $builder = [System.Text.StringBuilder]::new()
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        $content = Get-NormalizedText $file.FullName
        [void]$builder.Append($rel)
        [void]$builder.Append("`n")
        [void]$builder.Append($content)
        if (-not $content.EndsWith("`n")) {
            [void]$builder.Append("`n")
        }
        [void]$builder.Append("`n")
    }
    return Get-Sha256Text $builder.ToString()
}

function Write-Utf8File([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Initialize-GitFixture([string]$Worktree, [string]$Message) {
    Push-Location $Worktree
    try {
        & git init -q 2>$null | Out-Null
        & git config core.autocrlf false 2>$null | Out-Null
        & git config user.email qualification@example.com 2>$null | Out-Null
        & git config user.name qualification 2>$null | Out-Null
        & git add -A 2>$null | Out-Null
        & git commit --quiet -m $Message 2>$null | Out-Null
    }
    finally {
        Pop-Location
    }
}

function Ensure-CopilotAuthEnv {
    $existing = @(
        [Environment]::GetEnvironmentVariable('COPILOT_GITHUB_TOKEN'),
        [Environment]::GetEnvironmentVariable('GH_TOKEN'),
        [Environment]::GetEnvironmentVariable('GITHUB_TOKEN')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($existing.Count -gt 0) {
        return
    }
    try {
        $token = & gh auth token 2>$null
        if (-not [string]::IsNullOrWhiteSpace($token)) {
            $env:GH_TOKEN = ([string]$token).Trim()
            Write-Host 'Using gh auth token for Copilot CLI authentication under isolated COPILOT_HOME.'
        }
    }
    catch {
        Write-Host 'Warning: no GH_TOKEN/COPILOT_GITHUB_TOKEN and gh auth token unavailable; isolated COPILOT_HOME may fail authentication.'
    }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Resolve-CopilotExecutable([string]$CommandName) {
    if (Test-Path -LiteralPath $CommandName) {
        return (Resolve-Path -LiteralPath $CommandName).Path
    }
    $all = @(Get-Command $CommandName -All -ErrorAction SilentlyContinue)
    $app = $all | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
    if ($app) { return $app.Source }
    $where = (& where.exe $CommandName 2>$null | Select-Object -First 1)
    if ($where) { return $where }
    throw "Unable to resolve Copilot executable: $CommandName"
}

function Get-PackageVersion([string]$ManifestPath) {
    $text = Get-NormalizedText $ManifestPath
    if ($text -cmatch '(?m)^version:\s*(\S+)\s*$') {
        return $Matches[1]
    }
    throw "Unable to read package version from $ManifestPath"
}

function ConvertTo-JsonCompat($Object) {
    return ($Object | ConvertTo-Json -Depth 100)
}

function New-EmptyScenario([string]$Id, [string]$Kind, [string]$Prompt, $Upstream) {
    return [ordered]@{
        id = $Id
        kind = $Kind
        exact_prompt = $Prompt
        upstream_route_evidence = $Upstream
        exit_code = $null
        skill_observation = 'UNOBSERVABLE'
        agents_observed = @()
        created_artifacts = @()
        changed_artifacts = @()
        verifier_results = @()
        route_observed = $null
        verdict = $null
        stop_reason = $null
        status = 'NOT_RUN'
        rationale = 'Not executed.'
        transcript_sha256 = $null
        hook_log_sha256 = $null
        evidence_boundary = 'Hook log + artifact delta + final response; skill load may be UNOBSERVABLE.'
    }
}

function Install-PlanCoverageInto([string]$TargetRoot) {
    $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $stageRoot = Join-Path $tempParent ('plan-coverage-rq-stage-' + [Guid]::NewGuid().ToString('N'))
    try {
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            $stagePackage = Join-Path $stageRoot 'apm-packages\plan-coverage-residual-flow'
            $stageAdaptive = Join-Path $stageRoot 'apm-packages\adaptive-implementation-execution'
            New-Item -ItemType Directory -Path (Join-Path $stageRoot 'apm-packages') -Force | Out-Null
            Copy-DirectoryContents $packageRoot $stagePackage
            Copy-DirectoryContents (Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution') $stageAdaptive
            $stageAdaptiveAgents = Join-Path $stageAdaptive '.apm\agents'
            New-Item -ItemType Directory -Path $stageAdaptiveAgents -Force | Out-Null
            foreach ($adaptiveAgent in @('high-implementation-starter.agent.md', 'standard-implementation-completer.agent.md')) {
                $src = Join-Path $repoRoot ".github\agents\$adaptiveAgent"
                if (Test-Path -LiteralPath $src -PathType Leaf) {
                    Copy-Item -LiteralPath $src -Destination (Join-Path $stageAdaptiveAgents $adaptiveAgent) -Force
                }
            }

            $stageAdaptiveResolved = (Resolve-Path -LiteralPath $stageAdaptive).Path
            $stagePackageResolved = (Resolve-Path -LiteralPath $stagePackage).Path
            $adaptiveVersion = Get-PackageVersion (Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution\apm.yml')
            $packageVersion = Get-PackageVersion $apmYmlPath
            $adaptiveManifest = @"
name: adaptive-implementation-execution
version: $adaptiveVersion
description: Adaptive serial implementation routing
type: hybrid
targets:
  - copilot
  - codex
  - agent-skills
includes: auto
"@
            Write-Utf8File (Join-Path $stageAdaptiveResolved 'apm.yml') ($adaptiveManifest.Replace("`r`n", "`n"))
            $packageManifest = @"
name: plan-coverage-residual-flow
version: $packageVersion
description: Plan Coverage Check and Residual Decision Flow
type: hybrid
targets:
  - copilot
  - codex
  - agent-skills
includes: auto

dependencies:
  apm:
    - path: $stageAdaptiveResolved
"@
            Write-Utf8File (Join-Path $stagePackageResolved 'apm.yml') ($packageManifest.Replace("`r`n", "`n"))
            $installArguments = @('install', $stagePackageResolved, '--target', 'copilot,codex,agent-skills')
        }
        else {
            $source = "$Repository/apm-packages/plan-coverage-residual-flow#$Ref"
            $installArguments = @('install', $source, '--target', 'copilot,codex,agent-skills', '--https')
        }

        Push-Location $TargetRoot
        try {
            & apm @installArguments
            if ($LASTEXITCODE -ne 0) {
                throw "apm install failed with exit code $LASTEXITCODE"
            }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Initialize-CopilotHome([string]$CopilotHome, [string]$HookLogPath) {
    New-Item -ItemType Directory -Path (Join-Path $CopilotHome 'hooks') -Force | Out-Null
    $observerPath = Join-Path $CopilotHome 'hooks/qualification-observer.ps1'
    $observer = @'
param()
$ErrorActionPreference = "Stop"
$logPath = $env:RQ_HOOK_LOG
if ([string]::IsNullOrWhiteSpace($logPath)) { exit 0 }
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "{}" }
$line = ($raw -replace "[\r\n]+", " ").Trim()
Add-Content -LiteralPath $logPath -Value $line -Encoding utf8
Write-Output "{}"
'@
    Write-Utf8File $observerPath ($observer.Replace("`r`n", "`n"))

    $hookConfig = [ordered]@{
        version = 1
        hooks = [ordered]@{
            sessionStart = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
            userPromptSubmitted = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
            subagentStart = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
            subagentStop = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
            agentStop = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
            sessionEnd = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
            errorOccurred = @(@{ type = 'command'; powershell = $observerPath; timeoutSec = 10 })
        }
    }
    Write-Utf8File (Join-Path $CopilotHome 'hooks/qualification-observer.json') (ConvertTo-JsonCompat $hookConfig)
    Write-Utf8File (Join-Path $CopilotHome 'settings.json') (ConvertTo-JsonCompat ([ordered]@{
                experimental = $true
                enabledPlugins = @{}
            }))
    # Ensure log exists
    Write-Utf8File $HookLogPath ''
}

function Get-GitSnapshot([string]$Worktree) {
    $status = @(& git -C $Worktree status --porcelain 2>$null)
    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $status) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $path = $line.Substring(3).Trim().Trim('"')
        if ($path -match ' -> ') {
            $path = ($path -split ' -> ', 2)[1].Trim().Trim('"')
        }
        $norm = $path.Replace('\', '/')
        $full = Join-Path $Worktree $path
        if (Test-Path -LiteralPath $full -PathType Container) {
            $children = @(Get-ChildItem -LiteralPath $full -Recurse -File -ErrorAction SilentlyContinue)
            foreach ($child in $children) {
                $rel = $child.FullName.Substring((Resolve-Path -LiteralPath $Worktree).Path.Length).TrimStart('\', '/').Replace('\', '/')
                if (-not $files.Contains($rel)) { $files.Add($rel) }
            }
        }
        else {
            if (-not $files.Contains($norm)) { $files.Add($norm) }
        }
    }
    # Also include tracked modifications via name-only diff.
    foreach ($d in @(& git -C $Worktree diff --name-only 2>$null)) {
        $n = ([string]$d).Replace('\', '/')
        if (-not [string]::IsNullOrWhiteSpace($n) -and -not $files.Contains($n)) { $files.Add($n) }
    }
    return @($files)
}

function Add-ObservedAgent([System.Collections.Generic.List[string]]$Observed, [string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    foreach ($candidate in $allTrackedAgents) {
        if ($Text -ceq $candidate -or $Text -like "*$candidate*" -or $Text -match [regex]::Escape($candidate)) {
            if (-not $Observed.Contains($candidate)) {
                $Observed.Add($candidate)
            }
        }
    }
}

function Get-AgentsFromHookLog([string]$HookLogPath) {
    $observed = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $HookLogPath -PathType Leaf)) {
        return @()
    }
    foreach ($line in Get-Content -LiteralPath $HookLogPath -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        Add-ObservedAgent $observed $line
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            continue
        }
        foreach ($propName in @('agentName', 'agent_name', 'agentType', 'agent_type', 'agentDisplayName', 'agent_display_name', 'toolName', 'tool_name')) {
            Add-ObservedAgent $observed ([string]$obj.$propName)
        }
        if ($obj.data) {
            foreach ($propName in @('agentName', 'agent_name', 'agentType', 'agent_type', 'toolName', 'tool_name')) {
                Add-ObservedAgent $observed ([string]$obj.data.$propName)
            }
        }
    }
    return @($observed)
}

function Get-AgentsFromSessionEvents([string]$CopilotHome) {
    $observed = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $CopilotHome)) { return @() }
    $eventFiles = @(Get-ChildItem -LiteralPath $CopilotHome -Recurse -Filter 'events.jsonl' -File -ErrorAction SilentlyContinue)
    foreach ($file in $eventFiles) {
        foreach ($line in Get-Content -LiteralPath $file.FullName -ErrorAction SilentlyContinue) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $obj = $line | ConvertFrom-Json -ErrorAction Stop
            }
            catch { continue }

            # Only structured agent/subagent fields — never whole skill-body dumps.
            foreach ($propName in @('agentName', 'agent_name', 'agentType', 'agent_type', 'agentDisplayName', 'agent_display_name')) {
                if ($obj.psobject.Properties.Name -contains $propName) {
                    Add-ObservedAgent $observed ([string]$obj.$propName)
                }
                if ($obj.data -and $obj.data.psobject.Properties.Name -contains $propName) {
                    Add-ObservedAgent $observed ([string]$obj.data.$propName)
                }
            }

            # Custom agent file reads / task tool targets.
            $toolName = $null
            if ($obj.psobject.Properties.Name -contains 'toolName') { $toolName = [string]$obj.toolName }
            elseif ($obj.data -and $obj.data.psobject.Properties.Name -contains 'toolName') { $toolName = [string]$obj.data.toolName }
            elseif ($obj.data -and $obj.data.psobject.Properties.Name -contains 'tool_name') { $toolName = [string]$obj.data.tool_name }

            $toolArgs = $null
            if ($obj.psobject.Properties.Name -contains 'toolArgs') { $toolArgs = $obj.toolArgs }
            elseif ($obj.data -and $obj.data.psobject.Properties.Name -contains 'toolArgs') { $toolArgs = $obj.data.toolArgs }
            elseif ($obj.data -and $obj.data.psobject.Properties.Name -contains 'tool_input') { $toolArgs = $obj.data.tool_input }

            if ($toolArgs) {
                $argText = ($toolArgs | ConvertTo-Json -Depth 6 -Compress)
                if ($argText -match '\.github/agents/([a-z0-9-]+)\.agent\.md') {
                    Add-ObservedAgent $observed $Matches[1]
                }
                if ($argText -match 'agent["\s:=]+([a-z0-9-]+)') {
                    Add-ObservedAgent $observed $Matches[1]
                }
                if ($toolName -match 'task|agent' -and $argText -match '([a-z0-9-]+)') {
                    foreach ($candidate in $allTrackedAgents) {
                        if ($argText -match [regex]::Escape($candidate)) {
                            Add-ObservedAgent $observed $candidate
                        }
                    }
                }
            }
        }
    }
    return @($observed)
}

function Get-AgentsFromArtifactPaths([string[]]$Paths) {
    $observed = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $Paths) {
        $norm = $path.Replace('\', '/')
        if ($norm -notmatch '(^|/)plans/') { continue }
        if ($norm -match 'change-risk-triage') { Add-ObservedAgent $observed 'change-risk-triage' }
        if ($norm -match 'architecture-slice-readiness') { Add-ObservedAgent $observed 'architecture-slice-readiness' }
        if ($norm -match 'architecture-elaboration|slice-architecture') { Add-ObservedAgent $observed 'architecture-elaboration' }
        if ($norm -match 'slice-decomposition') { Add-ObservedAgent $observed 'plan-slice-decomposition' }
        if ($norm -match 'verification-kernel' -and $norm -notmatch 'cross-slice') { Add-ObservedAgent $observed 'verification-kernel' }
        if ($norm -match 'cross-slice-verification|full-coverage-close') { Add-ObservedAgent $observed 'cross-slice-verification-kernel' }
        if ($norm -match 'residual-decision') { Add-ObservedAgent $observed 'residual-decision-gate' }
        if ($norm -match 'implementation-completion-handoff|high-model-reentry|implementation-execution') {
            Add-ObservedAgent $observed 'high-implementation-starter'
            Add-ObservedAgent $observed 'standard-implementation-completer'
        }
        if ($norm -match 'plan-coverage-lite|plans/[a-z0-9-]+\.md$') {
            Add-ObservedAgent $observed 'plan-kernel'
        }
        if ($norm -match 'design-pair') {
            Add-ObservedAgent $observed 'design-pair-implementation-execution'
        }
        if ($norm -match 'slice-SL-') {
            # Living records imply decomposition ownership at minimum.
            Add-ObservedAgent $observed 'plan-slice-decomposition'
        }
    }
    return @($observed)
}

function Test-DesignPairAutoSelected([string[]]$Agents, [string[]]$Paths, [string]$Text) {
    $artifactHit = @($Paths | Where-Object { $_ -match 'design-pair' }).Count -gt 0
    if ($artifactHit) { return $true }
    if ($Agents -contains 'design-pair-implementation-execution') { return $true }
    if ($Text -cmatch '(?i)invok(?:e|ed|ing)\s+design-pair' -or $Text -cmatch '(?i)skill\(design-pair') {
        return $true
    }
    return $false
}

function Get-PlanCoverageArtifactDelta([string[]]$Paths) {
    $created = @()
    foreach ($path in $Paths) {
        $norm = $path.Replace('\', '/')
        if ($norm -like 'plans/*' -or $norm -like '*/plans/*') {
            $created += $norm
        }
        if ($norm -match 'plan-coverage|coverage-ledger|residual-decision|change-risk-triage|slice-SL-|full-coverage-close|living-record') {
            if ($created -notcontains $norm) { $created += $norm }
        }
    }
    return $created
}

function Test-ResponseMentionsRouteRecommendation([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    # Only affirmative recommendation / proposal counts. Explanations of non-selection do not.
    $negativeContext = @(
        'won''t invoke',
        'will not invoke',
        'won''t activate',
        'will not activate',
        'won''t select',
        'will not select',
        'do not select',
        'must not',
        'not select',
        'not invoke',
        'not activate',
        'without that skill',
        'without this skill',
        'I won''t',
        'I will not'
    )
    foreach ($n in $negativeContext) {
        if ($Text -cmatch [regex]::Escape($n)) {
            return $false
        }
    }
    $patterns = @(
        '(?i)you should use\s+`?plan-coverage-residual-flow',
        '(?i)recommend(?:ed|ing)?\s+(?:using\s+)?`?plan-coverage-residual-flow',
        '(?i)I recommend\s+`?plan-coverage-residual-flow',
        'plan-coverage-residual-flowを使ってください',
        'plan-coverage-residual-flow を使うべき'
    )
    foreach ($p in $patterns) {
        if ($Text -cmatch $p) { return $true }
    }
    return $false
}

function Test-AuthorizationAccepted([string]$Text, [string[]]$Agents) {
    if ($Agents -and $Agents.Count -gt 0) {
        foreach ($a in $Agents) {
            if ($planCoverageOwnedAgents -contains $a) { return $true }
        }
    }
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $positive = @(
        'authorization accepted',
        'authorized',
        'invocation authorization',
        '認可を受理',
        '認可済み',
        '起動を受理',
        'plan-coverage-residual-flow.*受理',
        'ReadyForRiskTriage',
        'plan-kernel',
        'intake'
    )
    foreach ($p in $positive) {
        if ($Text -cmatch $p) { return $true }
    }
    return $false
}

function Invoke-CopilotScenario {
    param(
        [string]$Worktree,
        [string]$Prompt,
        [string]$ScenarioId,
        [string]$EvidenceDir,
        [string]$CopilotExe,
        [string]$ModelName,
        [int]$TimeoutSec
    )

    $scenarioDir = Join-Path $EvidenceDir $ScenarioId
    New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
    $hookLog = Join-Path $scenarioDir 'hooks.jsonl'
    $stdoutPath = Join-Path $scenarioDir 'stdout.txt'
    $stderrPath = Join-Path $scenarioDir 'stderr.txt'
    $sharePath = Join-Path $scenarioDir 'session.md'
    $copilotHome = Join-Path $scenarioDir 'copilot-home'
    Initialize-CopilotHome -CopilotHome $copilotHome -HookLogPath $hookLog

    $before = @(Get-GitSnapshot $Worktree)
    $beforeSet = @{}
    foreach ($b in $before) {
        if (-not [string]::IsNullOrWhiteSpace($b)) {
            $beforeSet[[string]$b] = $true
        }
    }

    # Keep -p short and stable; full multi-line task body lives in the worktree to avoid
    # argument mangling of newlines across job/process boundaries.
    $promptPath = Join-Path $Worktree 'QUALIFICATION_PROMPT.md'
    Write-Utf8File $promptPath $Prompt
    $shortPrompt = @'
Read QUALIFICATION_PROMPT.md in this repository root and execute it completely without asking clarifying questions. If REQUEST.md also exists, treat QUALIFICATION_PROMPT.md as authoritative and REQUEST.md as supporting source requirement detail. Do not stop for human product decisions that the fixture already closed.
'@.Trim()

    $args = @(
        '--no-ask-user',
        '-p', $shortPrompt,
        '-C', $Worktree,
        '--allow-all',
        '--disable-builtin-mcps',
        '--no-custom-instructions',
        '--share', $sharePath,
        '--output-format', 'text'
    )
    if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
        $args = @('--model', $ModelName) + $args
    }

    $env:COPILOT_HOME = $copilotHome
    $env:RQ_HOOK_LOG = $hookLog
    $env:COPILOT_ALLOW_ALL = 'true'
    $env:CI = 'true'  # disable auto-update noise

    $stdout = ''
    $stderr = ''
    $exitCode = -1
    $previousCopilotHome = $env:COPILOT_HOME
    $previousHookLog = $env:RQ_HOOK_LOG
    $previousAllowAll = $env:COPILOT_ALLOW_ALL
    $previousCi = $env:CI
    try {
        $env:COPILOT_HOME = $copilotHome
        $env:RQ_HOOK_LOG = $hookLog
        $env:COPILOT_ALLOW_ALL = 'true'
        $env:CI = 'true'

        $argList = @()
        foreach ($a in $args) { $argList += [string]$a }

        # Direct invocation preserves argv boundaries. TimeoutSec is advisory for documentation;
        # long FULL-001 sessions are allowed to complete without an intermediate job wrapper.
        Push-Location $Worktree
        try {
            $outputLines = & $CopilotExe @argList 2>&1
            $exitCode = $LASTEXITCODE
            if ($null -eq $exitCode) { $exitCode = 0 }
            $stdout = ($outputLines | ForEach-Object { [string]$_ }) -join "`n"
            $stderr = ''
        }
        catch {
            $exitCode = -1
            $stderr = "$_"
            $stdout = ''
        }
        finally {
            Pop-Location
        }
        Write-Utf8File $stdoutPath $(if ($null -eq $stdout) { '' } else { $stdout })
        Write-Utf8File $stderrPath $(if ($null -eq $stderr) { '' } else { $stderr })
    }
    finally {
        if ($null -ne $previousCopilotHome) { $env:COPILOT_HOME = $previousCopilotHome } else { Remove-Item Env:COPILOT_HOME -ErrorAction SilentlyContinue }
        if ($null -ne $previousHookLog) { $env:RQ_HOOK_LOG = $previousHookLog } else { Remove-Item Env:RQ_HOOK_LOG -ErrorAction SilentlyContinue }
        if ($null -ne $previousAllowAll) { $env:COPILOT_ALLOW_ALL = $previousAllowAll } else { Remove-Item Env:COPILOT_ALLOW_ALL -ErrorAction SilentlyContinue }
        if ($null -ne $previousCi) { $env:CI = $previousCi } else { Remove-Item Env:CI -ErrorAction SilentlyContinue }
    }

    if ($null -eq $stdout) { $stdout = '' }
    if ($null -eq $stderr) { $stderr = '' }
    if (-not (Test-Path -LiteralPath $stdoutPath)) { Write-Utf8File $stdoutPath $stdout }
    if (-not (Test-Path -LiteralPath $stderrPath)) { Write-Utf8File $stderrPath $stderr }

    $after = Get-GitSnapshot $Worktree
    $created = @()
    $changed = @()
    foreach ($path in $after) {
        if ($beforeSet.ContainsKey($path)) {
            $changed += $path
        }
        else {
            $created += $path
        }
    }

    # Also include untracked comparison via git diff for content changes on tracked files
    $diffNames = @(& git -C $Worktree diff --name-only 2>$null)
    foreach ($d in $diffNames) {
        $n = $d.Replace('\', '/')
        if ($changed -notcontains $n -and $created -notcontains $n) {
            $changed += $n
        }
    }

    $agents = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @(Get-AgentsFromHookLog $hookLog)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    foreach ($a in @(Get-AgentsFromSessionEvents $copilotHome)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    foreach ($a in @(Get-AgentsFromArtifactPaths (@($created) + @($changed)))) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    $combinedText = @"
$stdout

$stderr

$(if (Test-Path -LiteralPath $sharePath) { Get-Content -LiteralPath $sharePath -Raw -ErrorAction SilentlyContinue })
"@

    $modelObserved = 'client-selected-or-unobserved'
    if ($combinedText -cmatch '(?i)\bmodel(?:\s+is|\s*[:=])\s*([a-z0-9._-]+)') {
        $modelObserved = $Matches[1]
    }

    $exitInt = 0
    try { $exitInt = [int]$exitCode } catch {
        if ($exitCode -is [psobject] -and $exitCode.psobject.Properties['value']) {
            $exitInt = [int]$exitCode.value
        }
        else {
            $exitInt = -1
        }
    }

    return [pscustomobject]@{
        ExitCode = $exitInt
        Stdout = $stdout
        Stderr = $stderr
        SharePath = $sharePath
        HookLog = $hookLog
        Agents = @($agents)
        Created = $created
        Changed = $changed
        CombinedText = $combinedText
        ModelObserved = $modelObserved
        TranscriptSha = if (Test-Path -LiteralPath $sharePath) { Get-Sha256File $sharePath } else { Get-Sha256Text $stdout }
        HookSha = Get-Sha256File $hookLog
    }
}

function New-AuthWorktree([string]$BaseInstallRoot, [object]$Scenario, [string]$ScenarioDir) {
    $worktree = Join-Path $ScenarioDir 'repo'
    New-Item -ItemType Directory -Path $worktree -Force | Out-Null
    # Copy installed projection assets
    foreach ($rel in @('.agents', '.github', '.codex', 'apm.lock.yaml')) {
        $src = Join-Path $BaseInstallRoot $rel
        if (Test-Path -LiteralPath $src) {
            $dest = Join-Path $worktree $rel
            if ((Get-Item -LiteralPath $src).PSIsContainer) {
                Copy-DirectoryContents $src $dest
            }
            else {
                New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
        }
    }

    if ($Scenario.context.existing_plan -or $Scenario.context.existing_plan_coverage_artifacts) {
        New-Item -ItemType Directory -Path (Join-Path $worktree 'plans') -Force | Out-Null
        Write-Utf8File (Join-Path $worktree 'plans/existing-placeholder.md') "# Existing plan placeholder`n"
        Write-Utf8File (Join-Path $worktree 'plans/existing-placeholder-coverage-ledger.md') "# Existing coverage ledger placeholder`n"
    }

    if ($Scenario.context.large -or $Scenario.context.high_risk -or $Scenario.context.architecture_change) {
        Write-Utf8File (Join-Path $worktree 'TASK_CONTEXT.md') @"
# Task context (fixture metadata only; not authorization)

- large: $($Scenario.context.large)
- high_risk: $($Scenario.context.high_risk)
- architecture_change: $($Scenario.context.architecture_change)
"@
    }

    if ($null -ne $Scenario.upstream_artifact) {
        $yaml = @()
        $ua = $Scenario.upstream_artifact
        foreach ($p in $ua.psobject.Properties) {
            $yaml += "$($p.Name): $($p.Value)"
        }
        New-Item -ItemType Directory -Path (Join-Path $worktree 'plans') -Force | Out-Null
        Write-Utf8File (Join-Path $worktree 'plans/upstream-route-evidence.md') @"
# Upstream route evidence

``````yaml
$($yaml -join "`n")
``````
"@
    }

    Write-Utf8File (Join-Path $worktree 'README.md') "# Disposable qualification repository`n"
    Initialize-GitFixture $worktree 'qualification fixture'
    return $worktree
}

function New-E2EWorktree([string]$BaseInstallRoot, [string]$SeedRoot, [string]$OracleVerifyPath, [string[]]$ExtraOraclePaths, [string]$ScenarioDir, [string]$RequestPath) {
    $worktree = Join-Path $ScenarioDir 'repo'
    New-Item -ItemType Directory -Path $worktree -Force | Out-Null
    foreach ($rel in @('.agents', '.github', '.codex', 'apm.lock.yaml')) {
        $src = Join-Path $BaseInstallRoot $rel
        if (Test-Path -LiteralPath $src) {
            $dest = Join-Path $worktree $rel
            if ((Get-Item -LiteralPath $src).PSIsContainer) {
                Copy-DirectoryContents $src $dest
            }
            else {
                New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
                Copy-Item -LiteralPath $src -Destination $dest -Force
            }
        }
    }
    Copy-DirectoryContents $SeedRoot $worktree
    $testsDir = Join-Path $worktree 'tests'
    New-Item -ItemType Directory -Path $testsDir -Force | Out-Null
    if ($OracleVerifyPath) {
        $destName = if ((Split-Path -Leaf $OracleVerifyPath) -ceq 'verify.ps1') {
            if ($ScenarioDir -match 'FULL') { 'verify-full-001.ps1' } else { 'verify-std-001.ps1' }
        } else {
            Split-Path -Leaf $OracleVerifyPath
        }
        # Detect from parent folder name
        if ($SeedRoot -match 'standard-slice') {
            $destName = 'verify-std-001.ps1'
        }
        elseif ($SeedRoot -match 'full-coverage') {
            $destName = 'verify-full-001.ps1'
        }
        Copy-Item -LiteralPath $OracleVerifyPath -Destination (Join-Path $testsDir $destName) -Force
    }
    foreach ($extra in $ExtraOraclePaths) {
        if (Test-Path -LiteralPath $extra -PathType Leaf) {
            Copy-Item -LiteralPath $extra -Destination (Join-Path $testsDir (Split-Path -Leaf $extra)) -Force
        }
    }
    Copy-Item -LiteralPath $RequestPath -Destination (Join-Path $worktree 'REQUEST.md') -Force

    # Store oracle hashes outside worktree authority path for harness checks
    $oracleMeta = Join-Path $ScenarioDir 'oracle-hashes.json'
    $hashes = [ordered]@{}
    Get-ChildItem -LiteralPath $testsDir -Filter 'verify*.ps1' -File | ForEach-Object {
        $hashes[$_.Name] = Get-Sha256File $_.FullName
    }
    Write-Utf8File $oracleMeta (ConvertTo-JsonCompat $hashes)

    Initialize-GitFixture $worktree 'qualification e2e fixture'
    return $worktree
}

function Assert-OracleIntact([string]$Worktree, [string]$OracleMetaPath) {
    if (-not (Test-Path -LiteralPath $OracleMetaPath)) { return @() }
    $meta = Get-Content -Raw -LiteralPath $OracleMetaPath | ConvertFrom-Json
    $failures = @()
    foreach ($prop in $meta.psobject.Properties) {
        $path = Join-Path $Worktree "tests/$($prop.Name)"
        $actual = Get-Sha256File $path
        if ($actual -cne $prop.Value) {
            $failures += "Oracle tampered: $($prop.Name)"
        }
    }
    return $failures
}

function Invoke-WorktreeVerifier([string]$Worktree, [string]$RelativeScript) {
    $scriptPath = Join-Path $Worktree $RelativeScript
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        return [pscustomobject]@{ name = $RelativeScript; status = 'FAIL'; detail = 'missing' }
    }
    $env:RQ_WORKTREE = $Worktree
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ name = $RelativeScript; status = 'FAIL'; detail = $output.Trim() }
        }
        return [pscustomobject]@{ name = $RelativeScript; status = 'PASS'; detail = $output.Trim() }
    }
    catch {
        return [pscustomobject]@{ name = $RelativeScript; status = 'FAIL'; detail = "$_" }
    }
    finally {
        Remove-Item Env:RQ_WORKTREE -ErrorAction SilentlyContinue
    }
}

function Evaluate-AuthScenario([object]$Scenario, $Run) {
    $pcAgents = @($Run.Agents | Where-Object { $planCoverageOwnedAgents -contains $_ })
    $artifactDelta = Get-PlanCoverageArtifactDelta (@($Run.Created) + @($Run.Changed))
    # Ignore pre-seeded placeholders that were not modified beyond existence for C
    $wroteArtifacts = @($artifactDelta | Where-Object {
            $_ -notmatch 'existing-placeholder' -and $_ -notmatch 'upstream-route-evidence'
        })
    $recommended = Test-ResponseMentionsRouteRecommendation $Run.CombinedText
    $accepted = Test-AuthorizationAccepted $Run.CombinedText $Run.Agents

    $result = [ordered]@{
        id = [string]$Scenario.id
        kind = $(if ($Scenario.expected_authorized) { 'authorization-positive' } else { 'authorization-negative' })
        exact_prompt = $Scenario.current_user_message
        upstream_route_evidence = $Scenario.upstream_artifact
        exit_code = $Run.ExitCode
        skill_observation = 'UNOBSERVABLE'
        agents_observed = @($Run.Agents)
        created_artifacts = @($Run.Created)
        changed_artifacts = @($Run.Changed)
        verifier_results = @()
        route_observed = $null
        verdict = $null
        stop_reason = $null
        status = 'FAIL'
        rationale = ''
        transcript_sha256 = $Run.TranscriptSha
        hook_log_sha256 = $Run.HookSha
        evidence_boundary = 'skill_observation=UNOBSERVABLE; judged from hooks/agents, artifact delta, and final response.'
    }

    if ($Scenario.expected_authorized) {
        if ($accepted -or $pcAgents.Count -gt 0) {
            $result.status = 'PASS'
            $result.verdict = 'authorized-flow'
            $result.stop_reason = $(if ($wroteArtifacts.Count -eq 0 -and $pcAgents.Count -eq 0) { 'intake-stop-or-authorization-only' } else { 'authorized-progress' })
            $result.rationale = "Authorization acceptance observed. agents=$($pcAgents -join ','); artifacts_written=$($wroteArtifacts.Count)."
        }
        else {
            $result.status = 'FAIL'
            $result.rationale = 'Expected authorization acceptance was not observed in agents or final response.'
        }
    }
    else {
        $failures = @()
        if ($pcAgents.Count -gt 0) { $failures += "plan-coverage agents invoked: $($pcAgents -join ',')" }
        if ($wroteArtifacts.Count -gt 0) { $failures += "plan-coverage artifacts written: $($wroteArtifacts -join ',')" }
        if ($recommended) { $failures += 'route recommendation detected in response' }
        if ($failures.Count -eq 0) {
            $result.status = 'PASS'
            $result.verdict = 'caller-or-normal-route'
            $result.rationale = 'No Plan Coverage agents, artifact writes, or route recommendations observed.'
        }
        else {
            $result.status = 'FAIL'
            $result.rationale = ($failures -join '; ')
        }
    }
    return $result
}

function Evaluate-StdScenario($Run, [string]$Worktree, [string]$OracleMeta) {
    $oracleFailures = Assert-OracleIntact $Worktree $OracleMeta
    $verifier = Invoke-WorktreeVerifier $Worktree 'tests/verify-std-001.ps1'
    $agents = @($Run.Agents)
    $hasHigh = $agents -contains 'high-implementation-starter'
    $hasStd = $agents -contains 'standard-implementation-completer'
    $hasPlan = $agents -contains 'plan-kernel'
    $hasRisk = $agents -contains 'change-risk-triage'
    $hasVerify = $agents -contains 'verification-kernel'
    $hasResidual = $agents -contains 'residual-decision-gate'
    $hasDesignPair = Test-DesignPairAutoSelected $agents (@($Run.Created) + @($Run.Changed)) $Run.CombinedText
    $pcArtifacts = Get-PlanCoverageArtifactDelta (@($Run.Created) + @($Run.Changed))
    # When custom subagents are unobservable, accept durable artifact evidence for route stages.
    $text = [string]$Run.CombinedText
    if (-not $hasPlan -and ($pcArtifacts.Count -gt 0 -or $text -match 'plan-kernel|Plan readiness|documentation_level')) { $hasPlan = $true }
    if (-not $hasRisk -and ($pcArtifacts -match 'change-risk-triage' -or $text -match 'selected_process:\s*standard-slice|recommended process path|Guardrail Focus')) { $hasRisk = $true }
    if (-not $hasHigh -and ($text -match 'high-implementation-starter|HIGH_MODEL|READY_FOR_STANDARD_COMPLETION|implementation_route:\s*adaptive')) { $hasHigh = $true }
    if (-not $hasStd -and ($text -match 'standard-implementation-completer|STANDARD_MODEL|READY_FOR_STANDARD_COMPLETION|Adaptive route used|implementation_route:\s*adaptive')) { $hasStd = $true }
    if (-not $hasVerify -and ($pcArtifacts -match 'verification' -or $text -match 'verification-kernel|PARENT_PLAN_VERIFIED|Verification Summary|verify-std-001')) { $hasVerify = $true }
    if (-not $hasResidual -and ($pcArtifacts -match 'residual' -or $text -match 'residual-decision|ReadyToClose|READY_TO_CLOSE|Close readiness')) { $hasResidual = $true }
    if (-not $hasRisk -and ($text -match 'standard-slice|documentation_level:\s*lite|Why separate standard artifacts are not required')) { $hasRisk = $true }

    $checks = @()
    $checks += $verifier
    $checks += [pscustomobject]@{ name = 'oracle-intact'; status = $(if ($oracleFailures.Count -eq 0) { 'PASS' } else { 'FAIL' }); detail = ($oracleFailures -join '; ') }
    $checks += [pscustomobject]@{ name = 'plan-kernel'; status = $(if ($hasPlan) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'change-risk-triage'; status = $(if ($hasRisk) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'high-before-or-with-standard'; status = $(if ($hasHigh) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'standard-after-handoff'; status = $(if ($hasStd) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'verification-kernel'; status = $(if ($hasVerify) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'residual-decision-gate'; status = $(if ($hasResidual) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'no-design-pair-auto'; status = $(if (-not $hasDesignPair) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'plan-artifacts-present'; status = $(if ($pcArtifacts.Count -gt 0) { 'PASS' } else { 'FAIL' }) }

    $failed = @($checks | Where-Object { $_.status -cne 'PASS' })
    $status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }

    return [ordered]@{
        id = 'STD-001'
        kind = 'standard-slice-e2e'
        exact_prompt = (Get-NormalizedText (Join-Path $stdFixtureRoot 'request.md'))
        upstream_route_evidence = $null
        exit_code = $Run.ExitCode
        skill_observation = 'UNOBSERVABLE'
        agents_observed = $agents
        created_artifacts = @($Run.Created)
        changed_artifacts = @($Run.Changed)
        verifier_results = @($checks)
        route_observed = 'standard-slice'
        verdict = $(if ($status -ceq 'PASS') { 'READY_TO_CLOSE_WITH_NO_RESIDUALS_OR_EQUIVALENT' } else { 'INCOMPLETE' })
        stop_reason = $(if ($status -ceq 'PASS') { 'fixture-verified' } else { ($failed | ForEach-Object { $_.name }) -join ',' })
        status = $status
        rationale = $(if ($status -ceq 'PASS') {
                'STD-001 fixture verifier passed; required agents and Adaptive HIGH->STANDARD connection observed; no Design Pair auto-selection.'
            } else {
                "Failed checks: $((@($failed | ForEach-Object { $_.name })) -join ', ')"
            })
        transcript_sha256 = $Run.TranscriptSha
        hook_log_sha256 = $Run.HookSha
        adaptive_connection = [ordered]@{
            high_observed = [bool]$hasHigh
            standard_observed = [bool]$hasStd
            handoff_observed = [bool]($hasHigh -and $hasStd)
            design_pair_auto_selected = [bool]$hasDesignPair
        }
        evidence_boundary = 'skill_observation=UNOBSERVABLE; route judged from hooks, artifacts, and external verifier.'
    }
}

function Evaluate-FullScenario($Run, [string]$Worktree, [string]$OracleMeta) {
    $oracleFailures = Assert-OracleIntact $Worktree $OracleMeta
    $v1 = Invoke-WorktreeVerifier $Worktree 'tests/verify-sl-001.ps1'
    $v2 = Invoke-WorktreeVerifier $Worktree 'tests/verify-sl-002.ps1'
    $vx = Invoke-WorktreeVerifier $Worktree 'tests/verify-full-001.ps1'
    $agents = @($Run.Agents)
    $hasArch = $agents -contains 'architecture-slice-readiness'
    $hasDecomp = $agents -contains 'plan-slice-decomposition'
    $hasCross = $agents -contains 'cross-slice-verification-kernel'
    $hasResidual = $agents -contains 'residual-decision-gate'
    $hasHigh = $agents -contains 'high-implementation-starter'
    $hasStd = $agents -contains 'standard-implementation-completer'
    $hasDesignPair = Test-DesignPairAutoSelected $agents (@($Run.Created) + @($Run.Changed)) $Run.CombinedText
    $living = @($Run.Created + $Run.Changed | Where-Object { $_ -match 'slice-SL-' })
    $hasPlan = @($Run.Created + $Run.Changed | Where-Object { $_ -match 'plans/.+\.md' }).Count -gt 0
    $text = [string]$Run.CombinedText
    $paths = @($Run.Created) + @($Run.Changed)
    if (-not $hasArch -and ($paths -match 'architecture-slice-readiness' -or $text -match 'architecture-slice-readiness|ReadyForSliceDecomposition|StandardSliceSufficient')) { $hasArch = $true }
    if (-not $hasDecomp -and ($paths -match 'slice-decomposition|slice-SL-' -or $text -match 'plan-slice-decomposition')) { $hasDecomp = $true }
    if (-not $hasCross -and ($paths -match 'cross-slice|full-coverage-close' -or $text -match 'cross-slice-verification|CROSS_SLICE_')) { $hasCross = $true }
    if (-not $hasResidual -and ($paths -match 'residual' -or $text -match 'residual-decision|READY_TO_CLOSE|ReadyToClose')) { $hasResidual = $true }
    if (-not $hasHigh -and ($text -match 'high-implementation-starter|HIGH_MODEL|READY_FOR_STANDARD_COMPLETION|Adaptive')) { $hasHigh = $true }
    if (-not $hasStd -and ($text -match 'standard-implementation-completer|STANDARD_MODEL|READY_FOR_STANDARD_COMPLETION')) { $hasStd = $true }

    $checks = @($v1, $v2, $vx)
    $checks += [pscustomobject]@{ name = 'oracle-intact'; status = $(if ($oracleFailures.Count -eq 0) { 'PASS' } else { 'FAIL' }); detail = ($oracleFailures -join '; ') }
    $checks += [pscustomobject]@{ name = 'architecture-slice-readiness'; status = $(if ($hasArch) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'plan-slice-decomposition'; status = $(if ($hasDecomp) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'living-records'; status = $(if ($living.Count -ge 2) { 'PASS' } else { 'FAIL' }); detail = ($living -join ',') }
    $checks += [pscustomobject]@{ name = 'cross-slice-verification'; status = $(if ($hasCross -or $vx.status -ceq 'PASS') { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'residual-decision-gate'; status = $(if ($hasResidual) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'adaptive-connection'; status = $(if ($hasHigh) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'no-design-pair-auto'; status = $(if (-not $hasDesignPair) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'plan-created'; status = $(if ($hasPlan) { 'PASS' } else { 'FAIL' }) }

    $failed = @($checks | Where-Object { $_.status -cne 'PASS' })
    $status = if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }

    return [ordered]@{
        id = 'FULL-001'
        kind = 'full-coverage-e2e'
        exact_prompt = (Get-NormalizedText (Join-Path $fullFixtureRoot 'request.md'))
        upstream_route_evidence = $null
        exit_code = $Run.ExitCode
        skill_observation = 'UNOBSERVABLE'
        agents_observed = $agents
        created_artifacts = @($Run.Created)
        changed_artifacts = @($Run.Changed)
        verifier_results = @($checks)
        route_observed = 'full-coverage'
        verdict = $(if ($status -ceq 'PASS') { 'READY_TO_CLOSE_WITH_NO_RESIDUALS_OR_EQUIVALENT' } else { 'INCOMPLETE' })
        stop_reason = $(if ($status -ceq 'PASS') { 'fixture-verified' } else { ($failed | ForEach-Object { $_.name }) -join ',' })
        status = $status
        rationale = $(if ($status -ceq 'PASS') {
                'FULL-001 verifiers passed; architecture/decomposition/living records/cross-slice/residual and Adaptive connection observed; no Design Pair auto-selection.'
            } else {
                "Failed checks: $((@($failed | ForEach-Object { $_.name })) -join ', ')"
            })
        transcript_sha256 = $Run.TranscriptSha
        hook_log_sha256 = $Run.HookSha
        adaptive_connection = [ordered]@{
            high_observed = [bool]$hasHigh
            standard_observed = [bool]$hasStd
            handoff_observed = [bool]($hasHigh -and $hasStd)
            design_pair_auto_selected = [bool]$hasDesignPair
        }
        evidence_boundary = 'skill_observation=UNOBSERVABLE; route judged from hooks, artifacts, and external verifiers.'
    }
}

function Build-PromptFromAuthScenario($Scenario) {
    if (-not [string]::IsNullOrWhiteSpace($Scenario.current_user_message)) {
        $prompt = [string]$Scenario.current_user_message
        if ($Scenario.context.large -or $Scenario.context.high_risk -or $Scenario.context.architecture_change) {
            $prompt = @"
$prompt

Additional task facts (not a route selection):
- The change is large: $($Scenario.context.large)
- The change is high risk: $($Scenario.context.high_risk)
- The change includes architecture change: $($Scenario.context.architecture_change)
"@
        }
        if ($Scenario.context.existing_plan -or $Scenario.context.existing_plan_coverage_artifacts) {
            $prompt = @"
$prompt

Repository already contains plans/existing-placeholder.md and a coverage ledger placeholder from prior work.
"@
        }
        return $prompt.Trim()
    }

    # Upstream-only scenarios: put the durable tuple in the prompt itself so the model
    # treats it as forwarded upstream evidence, not as a random repository claim.
    if ($Scenario.upstream_artifact) {
        $ua = $Scenario.upstream_artifact
        $fields = @()
        foreach ($p in $ua.psobject.Properties) {
            $fields += ("{0}: {1}" -f $p.Name, $p.Value)
        }
        $tuple = $fields -join "`n"
        $complete = ($ua.psobject.Properties.Name -contains 'process_route') -and
            ($ua.psobject.Properties.Name -contains 'process_route_source') -and
            ($ua.psobject.Properties.Name -contains 'user_selection_evidence') -and
            ([string]$ua.process_route_source -ceq 'explicit-user-selection') -and
            (-not [string]::IsNullOrWhiteSpace([string]$ua.user_selection_evidence))
        if ($complete) {
            return @"
You are an upstream process handing off to the current agent.

The following durable route evidence is authoritative upstream evidence of an actual prior user selection (user-turn reference included). It is not a generic repository artifact claim:

``````yaml
$tuple
``````

Apply plan-coverage-residual-flow invocation authorization using this complete durable explicit-user-selection tuple.
If authorized, explicitly acknowledge authorization acceptance and stop at intake because no implementation target is supplied.
Do not ask the human to re-select the route.
Do not implement code.
"@.Trim()
        }
        return @"
You are an upstream process handing off to the current agent.

The following durable route evidence is all that the upstream process provided:

``````yaml
$tuple
``````

Apply plan-coverage-residual-flow invocation authorization.
If the durable tuple is incomplete, do not start Plan Coverage, do not create Plan Coverage artifacts, do not invoke Plan Coverage agents, and do not recommend the route. Return control upstream.
Do not ask the human to select the route.
Do not implement code.
"@.Trim()
    }
    return 'Continue.'
}

# --- main ---

$canonicalFingerprint = Get-CanonicalFingerprint $canonicalRoot
$apmYmlSha = Get-Sha256File $apmYmlPath
$packageVersion = Get-PackageVersion $apmYmlPath
$candidateCommitRaw = & git -C $repoRoot rev-parse HEAD 2>$null
if ($candidateCommitRaw) { $candidateCommit = ([string]$candidateCommitRaw).Trim() } else { $candidateCommit = 'UNOBSERVABLE' }
$dirty = @(& git -C $repoRoot status --porcelain 2>$null)
if ($dirty.Count -gt 0) {
    $candidateCommit = "$candidateCommit-dirty"
}

$payload = @"
Plan Coverage GitHub Copilot CLI runtime qualification
- package: plan-coverage-residual-flow $packageVersion
- candidate: $candidateCommit
- canonical_fingerprint: $canonicalFingerprint
- model: $(if ($Model) { $Model } else { 'client-selected' })
- scenarios: A-H authorization + STD-001 + FULL-001
- isolation: temporary COPILOT_HOME per scenario (no personal skills/agents/hooks/plugins)
- external model: yes
- secrets on argv: none
"@

if ($DescribePayload) {
    Write-Host $payload
    exit 0
}

if (-not $ConfirmExternalModelPayload) {
    throw 'Refusing to call an external model. Re-run with -DescribePayload or -ConfirmExternalModelPayload after reviewing the payload.'
}

$copilotExe = Resolve-CopilotExecutable $CopilotCommand
Ensure-CopilotAuthEnv
$copilotVersion = ((& $copilotExe --version 2>&1 | Out-String).Trim())
if ([string]::IsNullOrWhiteSpace($copilotVersion)) { $copilotVersion = 'UNOBSERVABLE' }
$apmVersion = ((& apm --version 2>&1 | Out-String).Trim())
if ([string]::IsNullOrWhiteSpace($apmVersion)) { $apmVersion = 'UNOBSERVABLE' }

$runStamp = Get-Date -Format 'yyyy-MM-dd'
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$runRoot = Join-Path $tempParent ('plan-coverage-rq-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runRoot, $ResultsDir -Force | Out-Null
$evidenceRoot = Join-Path $runRoot 'evidence'
$installRoot = Join-Path $runRoot 'install-seed'
New-Item -ItemType Directory -Path $evidenceRoot, $installRoot -Force | Out-Null

Write-Host $payload
Write-Host "Run root: $runRoot"

$authScenarios = Get-Content -Raw -LiteralPath $authScenarioPath | ConvertFrom-Json
$selectedFilter = $null
if ($ScenarioIds -and @($ScenarioIds).Count -gt 0) {
    $expandedIds = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in @($ScenarioIds)) {
        foreach ($part in ([string]$raw -split '[,;\s]+')) {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                $expandedIds.Add($part.Trim())
            }
        }
    }
    $selectedFilter = @{}
    foreach ($id in $expandedIds) {
        $selectedFilter[$id.ToUpperInvariant()] = $true
    }
    Write-Host ("Scenario filter: " + (($selectedFilter.Keys | Sort-Object) -join ', '))
}

$distributionSmoke = [ordered]@{
    status = 'NOT_RUN'
    command = './apm-packages/plan-coverage-residual-flow/scripts/validate-plan-coverage-residual-flow-apm-smoke.ps1'
    rationale = 'Not executed in this run.'
}

try {
    if (-not $SkipDistributionSmoke) {
        Write-Host 'Running fresh APM distribution smoke...'
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            & $smokeScript
        }
        else {
            & $smokeScript -Repository $Repository -Ref $Ref
        }
        if ($LASTEXITCODE -ne 0) {
            $distributionSmoke.status = 'FAIL'
            $distributionSmoke.rationale = "Smoke failed with exit code $LASTEXITCODE"
            throw $distributionSmoke.rationale
        }
        $distributionSmoke.status = 'PASS'
        $distributionSmoke.rationale = 'Fresh APM install smoke passed (copilot,codex,agent-skills + transitive Adaptive + installed E2E when remote).'
    }

    Write-Host 'Installing Plan Coverage into qualification seed worktree...'
    Install-PlanCoverageInto $installRoot
    $lockPath = Join-Path $installRoot 'apm.lock.yaml'
    $lockSha = if (Test-Path -LiteralPath $lockPath) { Get-Sha256File $lockPath } else { 'MISSING' }

    $scenarioResults = [System.Collections.Generic.List[object]]::new()
    $modelObservedGlobal = $(if ($Model) { $Model } else { 'client-selected-or-unobserved' })

    foreach ($scenario in $authScenarios) {
        $sid = [string]$scenario.id
        if ($selectedFilter -and -not $selectedFilter.ContainsKey($sid.ToUpperInvariant())) { continue }
        Write-Host "=== Authorization scenario $sid ==="
        $scenarioDir = Join-Path $evidenceRoot "auth-$sid"
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        $worktree = New-AuthWorktree -BaseInstallRoot $installRoot -Scenario $scenario -ScenarioDir $scenarioDir
        $prompt = Build-PromptFromAuthScenario $scenario
        Write-Utf8File (Join-Path $scenarioDir 'prompt.md') $prompt
        $run = Invoke-CopilotScenario -Worktree $worktree -Prompt $prompt -ScenarioId $sid -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec $TimeoutSeconds
        if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
            $modelObservedGlobal = $run.ModelObserved
        }
        $evaluated = Evaluate-AuthScenario $scenario $run
        $scenarioResults.Add($evaluated)
        Write-Host "Scenario $sid => $($evaluated.status)"
    }

    if (-not $selectedFilter -or $selectedFilter.ContainsKey('STD-001')) {
        Write-Host '=== STD-001 standard-slice E2E ==='
        $scenarioDir = Join-Path $evidenceRoot 'STD-001'
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        $worktree = New-E2EWorktree -BaseInstallRoot $installRoot -SeedRoot (Join-Path $stdFixtureRoot 'seed') -OracleVerifyPath (Join-Path $stdFixtureRoot 'verify.ps1') -ExtraOraclePaths @() -ScenarioDir $scenarioDir -RequestPath (Join-Path $stdFixtureRoot 'request.md')
        $prompt = Get-NormalizedText (Join-Path $worktree 'REQUEST.md')
        $run = Invoke-CopilotScenario -Worktree $worktree -Prompt $prompt -ScenarioId 'STD-001' -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec $TimeoutSeconds
        if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
            $modelObservedGlobal = $run.ModelObserved
        }
        $oracleMeta = Join-Path $scenarioDir 'oracle-hashes.json'
        $evaluated = Evaluate-StdScenario $run $worktree $oracleMeta
        $scenarioResults.Add($evaluated)
        Write-Host "STD-001 => $($evaluated.status)"
    }

    if (-not $selectedFilter -or $selectedFilter.ContainsKey('FULL-001')) {
        Write-Host '=== FULL-001 full-coverage E2E ==='
        $scenarioDir = Join-Path $evidenceRoot 'FULL-001'
        New-Item -ItemType Directory -Path $scenarioDir -Force | Out-Null
        $extra = @(
            (Join-Path $fullFixtureRoot 'seed/tests/verify-sl-001.ps1'),
            (Join-Path $fullFixtureRoot 'seed/tests/verify-sl-002.ps1')
        )
        $worktree = New-E2EWorktree -BaseInstallRoot $installRoot -SeedRoot (Join-Path $fullFixtureRoot 'seed') -OracleVerifyPath (Join-Path $fullFixtureRoot 'verify.ps1') -ExtraOraclePaths $extra -ScenarioDir $scenarioDir -RequestPath (Join-Path $fullFixtureRoot 'request.md')
        $prompt = Get-NormalizedText (Join-Path $worktree 'REQUEST.md')
        $run = Invoke-CopilotScenario -Worktree $worktree -Prompt $prompt -ScenarioId 'FULL-001' -EvidenceDir $scenarioDir -CopilotExe $copilotExe -ModelName $Model -TimeoutSec ([Math]::Max($TimeoutSeconds, 3600))
        if ($run.ModelObserved -and $run.ModelObserved -cne 'client-selected-or-unobserved') {
            $modelObservedGlobal = $run.ModelObserved
        }
        $oracleMeta = Join-Path $scenarioDir 'oracle-hashes.json'
        $evaluated = Evaluate-FullScenario $run $worktree $oracleMeta
        $scenarioResults.Add($evaluated)
        Write-Host "FULL-001 => $($evaluated.status)"
    }

    $requiredIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'STD-001', 'FULL-001')
    $byId = @{}
    foreach ($s in $scenarioResults) { $byId[$s.id] = $s }
    $allPass = $true
    foreach ($id in $requiredIds) {
        $idKey = $id.ToUpperInvariant()
        if (-not $selectedFilter -or $selectedFilter.ContainsKey($idKey)) {
            if (-not $byId.ContainsKey($id) -or $byId[$id].status -cne 'PASS') {
                $allPass = $false
            }
        }
    }
    if ($distributionSmoke.status -cne 'PASS' -and -not $SkipDistributionSmoke) {
        $allPass = $false
    }

    $overall = if ($allPass -and (-not $selectedFilter)) { 'QUALIFIED' } elseif ($allPass) { 'PENDING' } else { 'FAIL' }

    $result = [ordered]@{
        schema_version = 1
        date = $runStamp
        runtime = [ordered]@{
            surface = 'github-copilot'
            qualified_client_surface = 'github-copilot-cli'
            other_surfaces = @('vscode-agent-mode: separate-runtime-qualification-not-performed')
        }
        client_version = $copilotVersion
        model_requested = $(if ($Model) { $Model } else { $null })
        model_observed = $modelObservedGlobal
        apm_version = $apmVersion
        candidate_commit = $candidateCommit
        plan_coverage_package_version = $packageVersion
        canonical_fingerprint = $canonicalFingerprint
        apm_yml_sha256 = $apmYmlSha
        install_targets = @('copilot', 'codex', 'agent-skills')
        apm_lock_sha256 = $lockSha
        platform = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
        distribution_smoke = $distributionSmoke
        overall_status = $overall
        qualification_matrix_notes = 'Qualified client surface is GitHub Copilot CLI only. Codex was not re-qualified in this run beyond existing static/historical evidence. VS Code Agent mode was not runtime-qualified.'
        scenarios = @($scenarioResults)
    }

    $jsonPath = Join-Path $ResultsDir "$runStamp-copilot-cli.json"
    $mdPath = Join-Path $ResultsDir "$runStamp-copilot-cli.md"
    Write-Utf8File $jsonPath (ConvertTo-JsonCompat $result)

    $md = @"
# Plan Coverage GitHub Copilot CLI runtime qualification

- date: $runStamp
- overall_status: $overall
- client_version: $copilotVersion
- model_requested: $(if ($Model) { $Model } else { 'null' })
- model_observed: $modelObservedGlobal
- apm_version: $apmVersion
- candidate_commit: $candidateCommit
- plan_coverage_package_version: $packageVersion
- canonical_fingerprint: $canonicalFingerprint
- install_targets: copilot,codex,agent-skills
- distribution_smoke: $($distributionSmoke.status)
- platform: $($result.platform)
- temporary_evidence: $runRoot

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
$(($scenarioResults | ForEach-Object { "| $($_.id) | $($_.kind) | $($_.status) | $((@($_.agents_observed) -join ', ')) | $($_.stop_reason) |" }) -join "`n")

## Notes

- skill_observation is UNOBSERVABLE unless Copilot CLI emits a dedicated skill-load event.
- Authorization negatives require no Plan Coverage agents, no Plan Coverage artifact writes, and no route recommendation.
- STD-001 / FULL-001 use external oracles hash-checked by the harness.
- Personal COPILOT_HOME customizations were isolated via temporary COPILOT_HOME.
"@
    Write-Utf8File $mdPath $md.Replace("`r`n", "`n")

    Write-Host "Wrote $jsonPath"
    Write-Host "Wrote $mdPath"
    Write-Host "overall_status=$overall"

    if ($overall -cne 'QUALIFIED') {
        exit 1
    }
}
finally {
    if (-not $KeepWorktree) {
        $resolved = [System.IO.Path]::GetFullPath($runRoot)
        if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('plan-coverage-rq-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "Kept worktree: $runRoot"
    }
}
