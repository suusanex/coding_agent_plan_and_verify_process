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
    [switch]$ConfirmExternalModelPayload,
    [string]$ReevaluateFromRunRoot
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
    $normalized = $Text.Trim()
    # Exact logical agent names only. Do not substring-match free text (false Design Pair hits).
    if ($allTrackedAgents -contains $normalized) {
        if (-not $Observed.Contains($normalized)) {
            $Observed.Add($normalized)
        }
        return
    }
    foreach ($candidate in $allTrackedAgents) {
        if ($normalized -ceq $candidate) {
            if (-not $Observed.Contains($candidate)) {
                $Observed.Add($candidate)
            }
        }
    }
}

function Add-ObservedAgentFromPathText([System.Collections.Generic.List[string]]$Observed, [string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    if ($Text -match '\.github/agents/([a-z0-9-]+)\.agent\.md') {
        Add-ObservedAgent $Observed $Matches[1]
    }
    if ($Text -match '\.codex/agents/([a-z0-9-]+)\.toml') {
        Add-ObservedAgent $Observed $Matches[1]
    }
}

function Get-AgentsFromHookLog([string]$HookLogPath) {
    $observed = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $HookLogPath -PathType Leaf)) {
        return @()
    }
    foreach ($line in Get-Content -LiteralPath $HookLogPath -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            continue
        }
        foreach ($propName in @('agentName', 'agent_name', 'agentType', 'agent_type', 'agentDisplayName', 'agent_display_name', 'agentId', 'agent_id')) {
            if ($obj.psobject.Properties.Name -contains $propName) {
                Add-ObservedAgent $observed ([string]$obj.$propName)
            }
        }
        if ($obj.data) {
            foreach ($propName in @('agentName', 'agent_name', 'agentType', 'agent_type', 'agentId', 'agent_id')) {
                if ($obj.data.psobject.Properties.Name -contains $propName) {
                    Add-ObservedAgent $observed ([string]$obj.data.$propName)
                }
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
                Add-ObservedAgentFromPathText $observed $argText
                if ($toolName -match '^(task|agent)$') {
                    foreach ($candidate in $allTrackedAgents) {
                        if ($argText -cmatch ('"' + [regex]::Escape($candidate) + '"') -or $argText -cmatch ('\b' + [regex]::Escape($candidate) + '\b')) {
                            # Prefer structured name fields; path/token hits still count for custom agents.
                            if ($candidate -cne 'design-pair-implementation-execution' -or $argText -match 'design-pair-implementation-execution\.(agent\.md|toml)') {
                                Add-ObservedAgent $observed $candidate
                            }
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
    # Only durable artifacts or explicit skill/agent invocation count.
    # Mentions in Plan text ("do not select Design Pair") must not fail the scenario.
    $artifactHit = @($Paths | Where-Object {
            $n = $_.Replace('\', '/')
            $n -match '(^|/)plans/.*design-pair' -or $n -match 'design-pair-implementation-handoff'
        }).Count -gt 0
    if ($artifactHit) { return $true }

    if ($Text -cmatch '(?i)skill\(\s*design-pair') { return $true }
    if ($Text -cmatch '(?i)\binvok(?:e|ed|ing)\s+design-pair-implementation-execution\b') { return $true }
    if ($Text -cmatch '(?i)subagentStart[^\n]{0,80}design-pair-implementation-execution') { return $true }

    # Agents list alone is insufficient: free-text false positives previously poisoned it.
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

function Resolve-PwshExecutable {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\PowerShell\7\pwsh.exe",
        "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) { return $c }
    }
    # Fall back to current host only if it is already PowerShell 7+.
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        return (Get-Process -Id $PID).Path
    }
    throw 'pwsh (PowerShell 7+) is required to run qualification fixture verifiers.'
}

function Invoke-WorktreeVerifier([string]$Worktree, [string]$RelativeScript) {
    $scriptPath = Join-Path $Worktree $RelativeScript
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        return [pscustomobject]@{ name = $RelativeScript; status = 'FAIL'; detail = 'missing' }
    }
    $env:RQ_WORKTREE = $Worktree
    $pwshExe = Resolve-PwshExecutable
    try {
        $output = & $pwshExe -NoProfile -File $scriptPath 2>&1 | Out-String
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

function Get-PlanFileEvidence([string]$Worktree) {
    $plansDir = Join-Path $Worktree 'plans'
    $items = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $plansDir -PathType Container)) {
        return @()
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $plansDir -Recurse -File -Filter '*.md')) {
        $rel = $file.FullName.Substring((Resolve-Path -LiteralPath $Worktree).Path.Length).TrimStart('\', '/').Replace('\', '/')
        $content = Get-NormalizedText $file.FullName
        $items.Add([pscustomobject]@{
                Path = $rel
                Content = $content
                Sha256 = Get-Sha256Text $content
            })
    }
    return @($items)
}

function Test-ProductionBindingPresent([string]$Worktree, [string[]]$RelativePaths) {
    foreach ($rel in $RelativePaths) {
        $full = Join-Path $Worktree $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $text = Get-NormalizedText $full
        if ($text -notmatch 'not implemented' -and $text.Length -gt 80) {
            return $true
        }
    }
    return $false
}

function Get-AdaptiveConnectionEvidence([string]$Worktree, [string[]]$HookAgents, [bool]$VerifierPassed) {
    $plans = @(Get-PlanFileEvidence $Worktree)
    $highHook = $HookAgents -contains 'high-implementation-starter'
    $stdHook = $HookAgents -contains 'standard-implementation-completer'

    $completedByHighHit = $null
    $readyForStandardHit = $null
    $standardCompletedHit = $null
    $selfMapHit = $null

    foreach ($p in $plans) {
        $c = $p.Content
        if ($c -cmatch '(?m)^- Implementation route:.*high-implementation-starter.*COMPLETED_BY_HIGH_MODEL' -or
            $c -cmatch '(?m)^- Model / owner sequence:.*high-implementation-starter \(HIGH\)' -or
            $c -cmatch 'COMPLETED_BY_HIGH_MODEL') {
            if (-not $completedByHighHit) { $completedByHighHit = $p }
        }
        if ($c -cmatch 'READY_FOR_STANDARD_COMPLETION' -and $c -cmatch '(?i)implementation-completion-handoff|Implementation Completion Handoff|READY_FOR_STANDARD') {
            # Require handoff-ish context, not a random glossary mention.
            if ($c -cmatch '(?m)^- Formal .*handoff' -or $c -cmatch 'implementation-completion-handoff' -or $c -cmatch '(?m)^- Handoff verdict:.*READY_FOR_STANDARD_COMPLETION' -or $c -cmatch 'READY_FOR_STANDARD_COMPLETION') {
                if ($c -cmatch 'READY_FOR_STANDARD_COMPLETION' -and ($c -cmatch 'handoff' -or $c -cmatch 'Handoff' -or $p.Path -match 'handoff')) {
                    if (-not $readyForStandardHit) { $readyForStandardHit = $p }
                }
            }
        }
        if ($c -cmatch '(?m)^- Implementation route:.*standard-implementation-completer' -or
            $c -cmatch '(?m)^- Model / owner sequence:.*standard-implementation-completer' -or
            $c -cmatch 'COMPLETED_BY_STANDARD_MODEL') {
            if (-not $standardCompletedHit) { $standardCompletedHit = $p }
        }
        if ($c -cmatch '### Implementation Self-Map' -and $c -cmatch 'src/') {
            if (-not $selfMapHit) { $selfMapHit = $p }
        }
    }

    $prodOk = Test-ProductionBindingPresent $Worktree @(
        'src/Load-AppConfig.ps1',
        'src/ProducerState.ps1',
        'src/ConsumerGate.ps1',
        'src/StartupFlow.ps1'
    )

    $high = [ordered]@{ status = 'NOT_OBSERVED'; evidence = $null; sha256 = $null; verdict = $null; reason = $null }
    if ($highHook) {
        $high.status = 'OBSERVED_FROM_HOOK'
        $high.evidence = 'hooks/session: agentName=high-implementation-starter'
        $high.reason = 'structured hook/session agent observation'
    }
    elseif ($completedByHighHit -and $selfMapHit -and $prodOk -and $VerifierPassed) {
        $high.status = 'OBSERVED_FROM_DURABLE_ARTIFACT'
        $high.evidence = $completedByHighHit.Path
        $high.sha256 = $completedByHighHit.Sha256
        $high.verdict = 'COMPLETED_BY_HIGH_MODEL'
        $high.reason = 'Living Record / plan records high-implementation-starter COMPLETED_BY_HIGH_MODEL with Implementation Self-Map and production binding; external verifier PASS'
    }

    $handoff = [ordered]@{ status = 'NOT_OBSERVED'; evidence = $null; sha256 = $null; verdict = $null; reason = $null }
    $standard = [ordered]@{ status = 'NOT_OBSERVED'; evidence = $null; sha256 = $null; verdict = $null; reason = $null }

    if ($readyForStandardHit) {
        $handoff.status = 'OBSERVED_FROM_DURABLE_ARTIFACT'
        $handoff.evidence = $readyForStandardHit.Path
        $handoff.sha256 = $readyForStandardHit.Sha256
        $handoff.verdict = 'READY_FOR_STANDARD_COMPLETION'
        $handoff.reason = 'durable handoff artifact/section records READY_FOR_STANDARD_COMPLETION'
        if ($stdHook) {
            $standard.status = 'OBSERVED_FROM_HOOK'
            $standard.evidence = 'hooks/session: agentName=standard-implementation-completer'
        }
        elseif ($standardCompletedHit -and $VerifierPassed) {
            $standard.status = 'OBSERVED_FROM_DURABLE_ARTIFACT'
            $standard.evidence = $standardCompletedHit.Path
            $standard.sha256 = $standardCompletedHit.Sha256
            $standard.reason = 'durable artifact records STANDARD completion after handoff; verifier PASS'
        }
        else {
            $standard.status = 'NOT_OBSERVED'
            $standard.reason = 'READY_FOR_STANDARD_COMPLETION present but STANDARD execution evidence missing'
        }
    }
    elseif ($high.status -like 'OBSERVED_*' -and $completedByHighHit -and ($completedByHighHit.Content -cmatch 'no STANDARD' -or $completedByHighHit.Content -cmatch 'COMPLETED_BY_HIGH_MODEL' -or $completedByHighHit.Content -cmatch 'HIGH\) only')) {
        $handoff.status = 'NOT_REQUIRED'
        $handoff.evidence = $completedByHighHit.Path
        $handoff.sha256 = $completedByHighHit.Sha256
        $handoff.verdict = 'COMPLETED_BY_HIGH_MODEL'
        $handoff.reason = 'HIGH completed the bounded remainder; STANDARD delegation not required'
        $standard.status = 'NOT_REQUIRED'
        $standard.evidence = $completedByHighHit.Path
        $standard.sha256 = $completedByHighHit.Sha256
        $standard.reason = 'no STANDARD remainder after HIGH completion'
    }
    elseif ($stdHook) {
        $standard.status = 'OBSERVED_FROM_HOOK'
        $standard.evidence = 'hooks/session: agentName=standard-implementation-completer'
        $standard.reason = 'STANDARD observed without separate handoff artifact'
    }

    $highObserved = $high.status -like 'OBSERVED_*'
    $stdObserved = $standard.status -like 'OBSERVED_*'
    $handoffObserved = $handoff.status -like 'OBSERVED_*'
    $highToStd = $handoffObserved -and $stdObserved -and $highObserved
    # Adaptive package connection: HIGH executed with durable/hook evidence, and either
    # HIGH->STANDARD handoff completed or HIGH-only completion was explicitly recorded.
    $connectionOk = $highObserved -and (
        $highToStd -or
        ($handoff.status -ceq 'NOT_REQUIRED' -and $standard.status -ceq 'NOT_REQUIRED' -and $VerifierPassed)
    )

    $hasDesignPair = Test-DesignPairAutoSelected $HookAgents @() ''
    # Also scan plan paths for design-pair artifacts
    foreach ($p in $plans) {
        if ($p.Path -match 'design-pair') { $hasDesignPair = $true }
    }

    return [ordered]@{
        high_execution = $high
        handoff = $handoff
        standard_execution = $standard
        connection_satisfied = [bool]$connectionOk
        high_to_standard_handoff_satisfied = [bool]$highToStd
        design_pair_auto_selected = [bool]$hasDesignPair
        high_observed = [bool]$highObserved
        standard_observed = [bool]$stdObserved
        handoff_observed = [bool]$handoffObserved
    }
}

function Get-RouteStageEvidence([string]$Worktree, [string[]]$HookAgents, [string[]]$Paths) {
    $stages = @(
        @{ name = 'plan-kernel'; path = 'plans/.+\.md|plan-coverage-lite|config-loader-plan|full-001-plan' },
        @{ name = 'change-risk-triage'; path = 'change-risk-triage' },
        @{ name = 'architecture-slice-readiness'; path = 'architecture-slice-readiness' },
        @{ name = 'plan-slice-decomposition'; path = 'slice-decomposition|slice-SL-' },
        @{ name = 'verification-kernel'; path = 'verification-kernel' },
        @{ name = 'cross-slice-verification-kernel'; path = 'full-coverage-close|cross-slice' },
        @{ name = 'residual-decision-gate'; path = 'residual-decision|full-coverage-close' },
        @{ name = 'implementation-execution'; path = 'implementation-execution' }
    )
    $out = @()
    foreach ($s in $stages) {
        $fromHook = $HookAgents -contains $s.name
        $pathHit = @($Paths | Where-Object { $_ -match $s.path }) | Select-Object -First 1
        if ($fromHook) {
            $out += [ordered]@{ stage = $s.name; status = 'OBSERVED_FROM_HOOK'; evidence = "agentName=$($s.name)" }
        }
        elseif ($pathHit) {
            $out += [ordered]@{ stage = $s.name; status = 'OBSERVED_FROM_DURABLE_ARTIFACT'; evidence = [string]$pathHit }
        }
        else {
            $out += [ordered]@{ stage = $s.name; status = 'NOT_OBSERVED'; evidence = $null }
        }
    }
    return $out
}

function Evaluate-StdScenario($Run, [string]$Worktree, [string]$OracleMeta) {
    $oracleFailures = Assert-OracleIntact $Worktree $OracleMeta
    $verifier = Invoke-WorktreeVerifier $Worktree 'tests/verify-std-001.ps1'
    $agents = @($Run.Agents) # hook/session only
    $paths = @($Run.Created) + @($Run.Changed)
    $pcArtifacts = Get-PlanCoverageArtifactDelta $paths
    $stages = @(Get-RouteStageEvidence $Worktree $agents $paths)
    $stageMap = @{}
    foreach ($s in $stages) { $stageMap[$s.stage] = $s }

    $adaptive = Get-AdaptiveConnectionEvidence $Worktree $agents ($verifier.status -ceq 'PASS')
    $hasDesignPair = [bool]$adaptive.design_pair_auto_selected

    $hasPlan = ($stageMap['plan-kernel'].status -ne 'NOT_OBSERVED') -or ($pcArtifacts.Count -gt 0)
    $hasRisk = $stageMap['change-risk-triage'].status -ne 'NOT_OBSERVED'
    $hasVerify = $stageMap['verification-kernel'].status -ne 'NOT_OBSERVED' -or ($paths -match 'verification')
    $hasResidual = $stageMap['residual-decision-gate'].status -ne 'NOT_OBSERVED' -or ($paths -match 'residual')
    # Adaptive connection check uses structured evidence, not free-text booleans.
    $adaptiveOk = [bool]$adaptive.connection_satisfied

    $checks = @()
    $checks += $verifier
    $checks += [pscustomobject]@{ name = 'oracle-intact'; status = $(if ($oracleFailures.Count -eq 0) { 'PASS' } else { 'FAIL' }); detail = ($oracleFailures -join '; ') }
    $checks += [pscustomobject]@{ name = 'plan-kernel'; status = $(if ($hasPlan) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'change-risk-triage'; status = $(if ($hasRisk) { 'PASS' } else { 'FAIL' }) }
    # Adaptive connection is suite-level (at least one E2E). STD records structured evidence without failing solely on HIGH-only absence.
    $checks += [pscustomobject]@{ name = 'adaptive-connection-evidence'; status = 'PASS'; detail = "connection_satisfied=$adaptiveOk; high=$($adaptive.high_execution.status); handoff=$($adaptive.handoff.status); standard=$($adaptive.standard_execution.status); high_to_standard=$($adaptive.high_to_standard_handoff_satisfied)" }
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
        route_stage_evidence = $stages
        created_artifacts = @($Run.Created)
        changed_artifacts = @($Run.Changed)
        verifier_results = @($checks)
        route_observed = 'standard-slice'
        verdict = $(if ($status -ceq 'PASS') { 'READY_TO_CLOSE_WITH_NO_RESIDUALS_OR_EQUIVALENT' } else { 'INCOMPLETE' })
        stop_reason = $(if ($status -ceq 'PASS') { 'fixture-verified' } else { ($failed | ForEach-Object { $_.name }) -join ',' })
        status = $status
        rationale = $(if ($status -ceq 'PASS') {
                "STD-001 fixture verifier passed; Adaptive connection_satisfied=$($adaptive.connection_satisfied) high_to_standard_handoff=$($adaptive.high_to_standard_handoff_satisfied); no Design Pair auto-selection."
            } else {
                "Failed checks: $((@($failed | ForEach-Object { $_.name })) -join ', ')"
            })
        transcript_sha256 = $Run.TranscriptSha
        hook_log_sha256 = $Run.HookSha
        adaptive_connection = $adaptive
        evidence_boundary = 'agents_observed=hook/session structured only; Adaptive HIGH/STANDARD/handoff separated into durable phases; free-text mention is not observation.'
    }
}

function Evaluate-FullScenario($Run, [string]$Worktree, [string]$OracleMeta) {
    $oracleFailures = Assert-OracleIntact $Worktree $OracleMeta
    $v1 = Invoke-WorktreeVerifier $Worktree 'tests/verify-sl-001.ps1'
    $v2 = Invoke-WorktreeVerifier $Worktree 'tests/verify-sl-002.ps1'
    $vx = Invoke-WorktreeVerifier $Worktree 'tests/verify-full-001.ps1'
    $agents = @($Run.Agents)
    $paths = @($Run.Created) + @($Run.Changed)
    $living = @($paths | Where-Object { $_ -match 'slice-SL-' })
    $hasPlan = @($paths | Where-Object { $_ -match 'plans/.+\.md' }).Count -gt 0
    $stages = @(Get-RouteStageEvidence $Worktree $agents $paths)
    $stageMap = @{}
    foreach ($s in $stages) { $stageMap[$s.stage] = $s }

    $verifiersPass = ($v1.status -ceq 'PASS' -and $v2.status -ceq 'PASS' -and $vx.status -ceq 'PASS')
    $adaptive = Get-AdaptiveConnectionEvidence $Worktree $agents $verifiersPass
    $hasDesignPair = [bool]$adaptive.design_pair_auto_selected

    $hasArch = $stageMap['architecture-slice-readiness'].status -ne 'NOT_OBSERVED'
    $hasDecomp = $stageMap['plan-slice-decomposition'].status -ne 'NOT_OBSERVED' -or $living.Count -ge 2
    $hasCross = $stageMap['cross-slice-verification-kernel'].status -ne 'NOT_OBSERVED' -or $vx.status -ceq 'PASS'
    $hasResidual = $stageMap['residual-decision-gate'].status -ne 'NOT_OBSERVED' -or ($paths -match 'residual|full-coverage-close')

    $checks = @($v1, $v2, $vx)
    $checks += [pscustomobject]@{ name = 'oracle-intact'; status = $(if ($oracleFailures.Count -eq 0) { 'PASS' } else { 'FAIL' }); detail = ($oracleFailures -join '; ') }
    $checks += [pscustomobject]@{ name = 'architecture-slice-readiness'; status = $(if ($hasArch) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'plan-slice-decomposition'; status = $(if ($hasDecomp) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'living-records'; status = $(if ($living.Count -ge 2) { 'PASS' } else { 'FAIL' }); detail = ($living -join ',') }
    $checks += [pscustomobject]@{ name = 'cross-slice-verification'; status = $(if ($hasCross) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'residual-decision-gate'; status = $(if ($hasResidual) { 'PASS' } else { 'FAIL' }) }
    $checks += [pscustomobject]@{ name = 'adaptive-connection'; status = $(if ($adaptive.connection_satisfied) { 'PASS' } else { 'FAIL' }); detail = "high=$($adaptive.high_execution.status); handoff=$($adaptive.handoff.status); standard=$($adaptive.standard_execution.status); high_to_standard=$($adaptive.high_to_standard_handoff_satisfied)" }
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
        route_stage_evidence = $stages
        created_artifacts = @($Run.Created)
        changed_artifacts = @($Run.Changed)
        verifier_results = @($checks)
        route_observed = 'full-coverage'
        verdict = $(if ($status -ceq 'PASS') { 'READY_TO_CLOSE_WITH_NO_RESIDUALS_OR_EQUIVALENT' } else { 'INCOMPLETE' })
        stop_reason = $(if ($status -ceq 'PASS') { 'fixture-verified' } else { ($failed | ForEach-Object { $_.name }) -join ',' })
        status = $status
        rationale = $(if ($status -ceq 'PASS') {
                "FULL-001 verifiers passed; Adaptive connection_satisfied=$($adaptive.connection_satisfied) high_to_standard_handoff=$($adaptive.high_to_standard_handoff_satisfied); no Design Pair auto-selection."
            } else {
                "Failed checks: $((@($failed | ForEach-Object { $_.name })) -join ', ')"
            })
        transcript_sha256 = $Run.TranscriptSha
        hook_log_sha256 = $Run.HookSha
        adaptive_connection = $adaptive
        evidence_boundary = 'agents_observed=hook/session structured only; Adaptive HIGH/STANDARD/handoff are separate durable phases; READY_FOR_STANDARD_COMPLETION alone is not STANDARD execution.'
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

function New-RunFromEvidenceDir([string]$ScenarioEvidenceDir, [string]$Worktree, [string]$ScenarioId) {
    $nested = Join-Path $ScenarioEvidenceDir $ScenarioId
    if (-not (Test-Path -LiteralPath $nested -PathType Container)) {
        $nested = $ScenarioEvidenceDir
    }
    $hookLog = Join-Path $nested 'hooks.jsonl'
    $stdoutPath = Join-Path $nested 'stdout.txt'
    $stderrPath = Join-Path $nested 'stderr.txt'
    $sharePath = Join-Path $nested 'session.md'
    $copilotHome = Join-Path $nested 'copilot-home'
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    $share = if (Test-Path -LiteralPath $sharePath) { Get-Content -LiteralPath $sharePath -Raw } else { '' }
    $combined = @"
$stdout

$stderr

$share
"@
    $created = @()
    $changed = @()
    if (Test-Path -LiteralPath $Worktree) {
        $snap = @(Get-GitSnapshot $Worktree)
        foreach ($p in $snap) {
            if ($p -match '^(src/|plans/|config/|QUALIFICATION_PROMPT)') {
                if ((Test-Path -LiteralPath (Join-Path $Worktree $p) -PathType Leaf)) {
                    # Treat all current delta paths as created/changed for re-eval.
                    $created += $p
                }
            }
        }
        # Untracked plans directory expansion already handled by Get-GitSnapshot.
        if ($created.Count -eq 0) {
            Get-ChildItem -LiteralPath (Join-Path $Worktree 'plans') -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $rel = $_.FullName.Substring((Resolve-Path -LiteralPath $Worktree).Path.Length).TrimStart('\', '/').Replace('\', '/')
                $created += $rel
            }
            foreach ($src in @('src/ProducerState.ps1', 'src/ConsumerGate.ps1', 'src/StartupFlow.ps1', 'src/Load-AppConfig.ps1')) {
                $full = Join-Path $Worktree $src
                if (Test-Path -LiteralPath $full -PathType Leaf) {
                    $txt = Get-Content -LiteralPath $full -Raw
                    if ($txt -notmatch 'not implemented') { $changed += $src }
                }
            }
        }
    }
    # agents_observed: hook/session structured only (never artifact inference).
    $agents = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @(Get-AgentsFromHookLog $hookLog)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    foreach ($a in @(Get-AgentsFromSessionEvents $copilotHome)) { if (-not $agents.Contains($a)) { $agents.Add($a) } }
    return [pscustomobject]@{
        ExitCode = 0
        Stdout = $stdout
        Stderr = $stderr
        SharePath = $sharePath
        HookLog = $hookLog
        Agents = @($agents)
        Created = @($created)
        Changed = @($changed)
        CombinedText = $combined
        ModelObserved = 'client-selected-or-unobserved'
        TranscriptSha = if (Test-Path -LiteralPath $sharePath) { Get-Sha256File $sharePath } elseif ($stdout) { Get-Sha256Text $stdout } else { $null }
        HookSha = if (Test-Path -LiteralPath $hookLog) { Get-Sha256File $hookLog } else { $null }
    }
}

function Write-RunMetadataFile([string]$RunRoot, [hashtable]$Meta) {
    $path = Join-Path $RunRoot 'run-metadata.json'
    Write-Utf8File $path (ConvertTo-JsonCompat ([ordered]@{} + $Meta))
    return $path
}

function Read-RunMetadataFile([string]$RunRoot) {
    $path = Join-Path $RunRoot 'run-metadata.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return (Get-Content -Raw -LiteralPath $path | ConvertFrom-Json)
}

if (-not [string]::IsNullOrWhiteSpace($ReevaluateFromRunRoot)) {
    $reevalRoot = [System.IO.Path]::GetFullPath($ReevaluateFromRunRoot)
    if (-not (Test-Path -LiteralPath $reevalRoot -PathType Container)) {
        throw "ReevaluateFromRunRoot not found: $reevalRoot"
    }
    Write-Host "Re-evaluating kept run without external model: $reevalRoot"
    $meta = Read-RunMetadataFile $reevalRoot
    if (-not $meta) {
        throw "run-metadata.json missing under $reevalRoot. Refuse to re-bind fingerprints from the current checkout."
    }

    $existingResultPath = Join-Path $ResultsDir "$(Get-Date -Format yyyy-MM-dd)-copilot-cli.json"
    if (-not (Test-Path -LiteralPath $existingResultPath)) {
        $hit = @(Get-ChildItem -LiteralPath $ResultsDir -Filter '*-copilot-cli.json' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1)
        if ($hit.Count -gt 0) { $existingResultPath = $hit[0].FullName }
    }
    if (-not $existingResultPath -or -not (Test-Path -LiteralPath $existingResultPath)) {
        throw 'No existing result JSON to merge authorization scenarios from.'
    }
    $base = Get-Content -Raw -LiteralPath $existingResultPath | ConvertFrom-Json
    $scenarioResults = [System.Collections.Generic.List[object]]::new()
    foreach ($s in @($base.scenarios)) {
        if (@('STD-001', 'FULL-001') -contains [string]$s.id) { continue }
        $scenarioResults.Add($s)
    }

    $stdDir = Join-Path $reevalRoot 'evidence\STD-001'
    $stdRepo = Join-Path $stdDir 'repo'
    if (Test-Path -LiteralPath $stdRepo) {
        $oracleMeta = Join-Path $stdDir 'oracle-hashes.json'
        $run = New-RunFromEvidenceDir $stdDir $stdRepo 'STD-001'
        $scenarioResults.Add((Evaluate-StdScenario $run $stdRepo $oracleMeta))
        Write-Host "STD-001 re-eval => $(( $scenarioResults | Where-Object { $_.id -eq 'STD-001' } | Select-Object -First 1).status)"
    }

    $fullDir = Join-Path $reevalRoot 'evidence\FULL-001'
    $fullRepo = Join-Path $fullDir 'repo'
    if (Test-Path -LiteralPath $fullRepo) {
        $oracleMeta = Join-Path $fullDir 'oracle-hashes.json'
        $run = New-RunFromEvidenceDir $fullDir $fullRepo 'FULL-001'
        $scenarioResults.Add((Evaluate-FullScenario $run $fullRepo $oracleMeta))
        Write-Host "FULL-001 re-eval => $(( $scenarioResults | Where-Object { $_.id -eq 'FULL-001' } | Select-Object -First 1).status)"
    }

    $byId = @{}
    foreach ($s in $scenarioResults) { $byId[[string]$s.id] = $s }
    $requiredIds = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'STD-001', 'FULL-001')
    $scenariosPass = $true
    foreach ($id in $requiredIds) {
        if (-not $byId.ContainsKey($id) -or $byId[$id].status -cne 'PASS') { $scenariosPass = $false }
    }
    $distStatus = if ($meta.distribution_smoke -and $meta.distribution_smoke.status) { $meta.distribution_smoke.status } else { $base.distribution_smoke.status }
    if ($distStatus -cne 'PASS') { $scenariosPass = $false }

    $adaptiveOk = $false
    $handoffOk = $false
    foreach ($id in @('STD-001', 'FULL-001')) {
        if (-not $byId.ContainsKey($id)) { continue }
        $ac = $byId[$id].adaptive_connection
        if ($ac -and $ac.connection_satisfied) { $adaptiveOk = $true }
        if ($ac -and $ac.high_to_standard_handoff_satisfied) { $handoffOk = $true }
    }
    if (-not $adaptiveOk) { $scenariosPass = $false }

    $sourceFp = [string]$meta.canonical_fingerprint
    $fingerprintMatchesCurrent = ($sourceFp -ceq $canonicalFingerprint)
    $packageMatches = ([string]$meta.package_version -ceq $packageVersion)
    $canQualifyCurrent = $scenariosPass -and $fingerprintMatchesCurrent -and $packageMatches
    $overall = if ($canQualifyCurrent) { 'QUALIFIED' } elseif ($scenariosPass -and -not $fingerprintMatchesCurrent) { 'PENDING' } else { 'FAIL' }

    $notes = 'Re-evaluated from kept worktree without new external model calls. source_run identity frozen from run-metadata.json. '
    if (-not $fingerprintMatchesCurrent) {
        $notes += "source fingerprint $sourceFp != current $canonicalFingerprint; cannot promote to current QUALIFIED. "
    }
    if ($adaptiveOk -and -not $handoffOk) {
        $notes += 'Adaptive connection satisfied via HIGH COMPLETED_BY_HIGH_MODEL durable evidence; HIGH->STANDARD handoff was NOT_REQUIRED (no STANDARD remainder). '
    }
    $notes += 'Qualified client surface is GitHub Copilot CLI only.'

    $clientVersion = [string]$meta.client_version
    $result = [ordered]@{
        schema_version = 1
        date = (Get-Date -Format 'yyyy-MM-dd')
        runtime = $base.runtime
        client_version = $clientVersion
        model_requested = $(if ($meta.psobject.Properties.Name -contains 'model_requested') { $meta.model_requested } else { $base.model_requested })
        model_observed = $(if ($meta.model_observed) { $meta.model_observed } else { $base.model_observed })
        apm_version = $(if ($meta.apm_version) { $meta.apm_version } else { $base.apm_version })
        # Frozen to the original live run — never re-bind from current checkout.
        candidate_commit = [string]$meta.candidate_commit
        plan_coverage_package_version = [string]$meta.package_version
        canonical_fingerprint = $sourceFp
        apm_yml_sha256 = [string]$meta.apm_yml_sha256
        install_targets = @($meta.install_targets)
        apm_lock_sha256 = [string]$meta.apm_lock_sha256
        platform = $(if ($meta.platform) { $meta.platform } else { $base.platform })
        distribution_smoke = $(if ($meta.distribution_smoke) { $meta.distribution_smoke } else { $base.distribution_smoke })
        overall_status = $overall
        qualification_matrix_notes = $notes
        source_run = [ordered]@{
            source_run_id = [string]$meta.source_run_id
            candidate_commit = [string]$meta.candidate_commit
            canonical_fingerprint = $sourceFp
            apm_yml_sha256 = [string]$meta.apm_yml_sha256
            package_version = [string]$meta.package_version
            apm_lock_sha256 = [string]$meta.apm_lock_sha256
            install_targets = @($meta.install_targets)
            client_version = $clientVersion
            apm_version = $(if ($meta.apm_version) { [string]$meta.apm_version } else { $null })
            model_requested = $(if ($meta.psobject.Properties.Name -contains 'model_requested') { $meta.model_requested } else { $null })
            model_observed = $(if ($meta.model_observed) { [string]$meta.model_observed } else { $null })
            platform = $(if ($meta.platform) { [string]$meta.platform } else { $null })
            distribution_smoke = $(if ($meta.distribution_smoke) { $meta.distribution_smoke } else { $null })
        }
        scenarios = @($scenarioResults)
    }

    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
    $jsonPath = Join-Path $ResultsDir "$($result.date)-copilot-cli.json"
    $mdPath = Join-Path $ResultsDir "$($result.date)-copilot-cli.md"
    Write-Utf8File $jsonPath (ConvertTo-JsonCompat $result)
    $md = @"
# Plan Coverage GitHub Copilot CLI runtime qualification

- date: $($result.date)
- overall_status: $overall
- reevaluation: kept-worktree-no-new-model-calls
- source_run_id: $($meta.source_run_id)
- source_run_root: $reevalRoot
- client_version: $clientVersion
- model_observed: $($result.model_observed)
- apm_version: $($result.apm_version)
- candidate_commit: $($meta.candidate_commit)
- plan_coverage_package_version: $($meta.package_version)
- canonical_fingerprint: $sourceFp
- current_checkout_fingerprint: $canonicalFingerprint
- fingerprint_matches_current: $fingerprintMatchesCurrent
- distribution_smoke: $distStatus
- adaptive_connection_satisfied: $adaptiveOk
- high_to_standard_handoff_satisfied: $handoffOk

## Scenarios

| id | kind | status | agents_observed | stop_reason |
| --- | --- | --- | --- | --- |
$(($scenarioResults | ForEach-Object { "| $($_.id) | $($_.kind) | $($_.status) | $((@($_.agents_observed) -join ', ')) | $($_.stop_reason) |" }) -join "`n")
"@
    Write-Utf8File $mdPath ($md.Replace("`r`n", "`n"))
    Write-Host "Wrote $jsonPath"
    Write-Host "Wrote $mdPath"
    Write-Host "overall_status=$overall fingerprint_matches_current=$fingerprintMatchesCurrent"
    if ($overall -cne 'QUALIFIED') { exit 1 }
    exit 0
}

if (-not $ConfirmExternalModelPayload) {
    throw 'Refusing to call an external model. Re-run with -DescribePayload, -ConfirmExternalModelPayload, or -ReevaluateFromRunRoot.'
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

    $runId = Split-Path -Leaf $runRoot
    $runMetadata = [ordered]@{
        source_run_id = $runId
        candidate_commit = $candidateCommit
        canonical_fingerprint = $canonicalFingerprint
        apm_yml_sha256 = $apmYmlSha
        package_version = $packageVersion
        apm_lock_sha256 = $lockSha
        install_targets = @('copilot', 'codex', 'agent-skills')
        client_version = ($copilotVersion -replace '[\r\n].*', '').Trim()
        apm_version = $apmVersion
        model_requested = $(if ($Model) { $Model } else { $null })
        model_observed = $(if ($Model) { $Model } else { 'client-selected-or-unobserved' })
        platform = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
        distribution_smoke = $distributionSmoke
    }
    Write-RunMetadataFile $runRoot $runMetadata
    Write-Host "Wrote run-metadata.json for source_run_id=$runId"

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
    $adaptiveOk = $false
    $handoffOk = $false
    foreach ($id in @('STD-001', 'FULL-001')) {
        if (-not $byId.ContainsKey($id)) { continue }
        $ac = $byId[$id].adaptive_connection
        if ($ac -and $ac.connection_satisfied) { $adaptiveOk = $true }
        if ($ac -and $ac.high_to_standard_handoff_satisfied) { $handoffOk = $true }
    }
    if (-not $selectedFilter -and -not $adaptiveOk) { $allPass = $false }

    $overall = if ($allPass -and (-not $selectedFilter)) { 'QUALIFIED' } elseif ($allPass) { 'PENDING' } else { 'FAIL' }

    $runMetadata.model_observed = $modelObservedGlobal
    $runMetadata.distribution_smoke = $distributionSmoke
    Write-RunMetadataFile $runRoot $runMetadata

    $clientVersionClean = ($copilotVersion -replace '[\r\n].*', '').Trim()
    $notes = 'Qualified client surface is GitHub Copilot CLI only. Codex was not re-qualified in this run beyond existing static/historical evidence. VS Code Agent mode was not runtime-qualified. '
    if ($adaptiveOk -and -not $handoffOk) {
        $notes += 'Adaptive connection satisfied via HIGH COMPLETED_BY_HIGH_MODEL durable evidence where STANDARD remainder was not required. '
    }
    $notes += "source_run_id=$runId bound via run-metadata.json."

    $result = [ordered]@{
        schema_version = 1
        date = $runStamp
        runtime = [ordered]@{
            surface = 'github-copilot'
            qualified_client_surface = 'github-copilot-cli'
            other_surfaces = @('vscode-agent-mode: separate-runtime-qualification-not-performed')
        }
        client_version = $clientVersionClean
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
        qualification_matrix_notes = $notes
        source_run = [ordered]@{
            source_run_id = $runId
            candidate_commit = $candidateCommit
            canonical_fingerprint = $canonicalFingerprint
            apm_yml_sha256 = $apmYmlSha
            package_version = $packageVersion
            apm_lock_sha256 = $lockSha
            install_targets = @('copilot', 'codex', 'agent-skills')
            client_version = $clientVersionClean
            apm_version = $apmVersion
            model_requested = $(if ($Model) { $Model } else { $null })
            model_observed = $modelObservedGlobal
            platform = $(if ($PSVersionTable.Platform) { [string]$PSVersionTable.Platform } else { 'win32' })
            distribution_smoke = $distributionSmoke
        }
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
