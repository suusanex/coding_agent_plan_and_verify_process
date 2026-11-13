[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'scripts' 'finalize-codex-agent-profiles.cs'))))
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-profile-finalizer-test-' + [guid]::NewGuid().ToString('N'))

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-Finalizer([string[]] $Arguments) {
    $output = & dotnet run --file $scriptPath -- @Arguments 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Join-Parts([string] $Root, [string[]] $Parts) {
    $current = $Root
    foreach ($part in $Parts) { $current = Join-Path $current $part }
    $current
}

function Write-AgentPackage([string] $PackageRoot, [string] $PackageName, [string] $Agent, [string] $Model) {
    $agentRoot = Join-Parts $PackageRoot @('.apm', 'agents')
    New-Item -ItemType Directory -Path $agentRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $PackageRoot 'apm.yml') -Value ("name: $PackageName" + [Environment]::NewLine)
    $agentText = @("---", "name: $Agent", "description: Fixture description", "---", "", "You are the fixture agent.") -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $agentRoot ($Agent + '.agent.md')) -Value $agentText
    $json = @{
        schemaVersion = 1
        package = $PackageName
        profiles = @(@{
            agent = $Agent
            model = $Model
            model_reasoning_effort = 'high'
            sandbox_mode = 'workspace-write'
        })
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $PackageRoot 'codex-profile-overlays.json') -Value $json
}

function Write-AdaptivePackage([string] $Root, [string] $ResidualModel) {
    $packageRoot = Join-Parts $Root @('apm_modules', 'owner', 'repo', 'apm-packages', 'adaptive-implementation-execution')
    $agentRoot = Join-Parts $packageRoot @('.apm', 'agents')
    New-Item -ItemType Directory -Path $agentRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $packageRoot 'apm.yml') -Value "name: adaptive-implementation-execution`n"
    foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
        $agentText = @("---", "name: $agent", "description: Fixture description", "---", "", "You are the fixture agent.") -join [Environment]::NewLine
        Set-Content -LiteralPath (Join-Path $agentRoot ($agent + '.agent.md')) -Value $agentText
    }
    $json = @{
        schemaVersion = 1
        package = 'adaptive-implementation-execution'
        profiles = @(
            @{
                agent = 'bounded-residual-implementation-owner'
                model = $ResidualModel
                model_reasoning_effort = 'high'
                sandbox_mode = 'workspace-write'
            }
        )
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath (Join-Path $packageRoot 'codex-profile-overlays.json') -Value $json
}

try {
    $moduleRoot = Join-Parts $root @('apm_modules', 'owner', 'repo', 'apm-packages', 'fixture-package')
    $duplicate = Join-Parts $root @('apm_modules', 'owner', 'repo', 'apm-packages', 'fixture-copy')
    $agentsRoot = Join-Parts $root @('.codex', 'agents')
    New-Item -ItemType Directory -Path $agentsRoot -Force | Out-Null
    Write-AgentPackage $moduleRoot 'fixture-package' 'agent' 'gpt-5.6-terra'
    $projectionPath = Join-Path $agentsRoot 'agent.toml'
    $projection = @'
name = 'agent'
description = "Fixture description" # portable field
developer_instructions = "You are the fixture agent."
'@
    Set-Content -LiteralPath $projectionPath -Value $projection
    $portableBefore = Get-Content -LiteralPath $projectionPath -Raw

    $result = Invoke-Finalizer @($root)
    Assert-True ($result.ExitCode -eq 0) "Initial finalizer apply failed.`n$($result.Output)"
    $profile = Get-Content -LiteralPath $projectionPath -Raw
    Assert-True ($profile -match 'model = "gpt-5\.6-terra"') 'Initial model overlay was not applied.'
    Assert-True ($profile -match 'description = "Fixture description" # portable field') 'Portable projected fields or comments were changed.'
    Assert-True ((Invoke-Finalizer @($root, '--check')).ExitCode -eq 0) 'Compliant profile check failed.'

    $beforeDryRun = Get-Content -LiteralPath $projectionPath -Raw
    $dryRun = Invoke-Finalizer @($root, '--dry-run')
    Assert-True ($dryRun.ExitCode -eq 0) "Dry-run unexpectedly failed.`n$($dryRun.Output)"
    Assert-True ((Get-Content -LiteralPath $projectionPath -Raw) -ceq $beforeDryRun) 'Dry-run changed the target.'

    Set-Content -LiteralPath $projectionPath -Value ($profile -replace 'description = "Fixture description"', 'description = "Unmanaged fixture"')
    $beforeOwnership = Get-Content -LiteralPath $projectionPath -Raw
    $ownership = Invoke-Finalizer @($root)
    Assert-True ($ownership.ExitCode -ne 0) 'Portable ownership mismatch unexpectedly succeeded.'
    Assert-True ((Get-Content -LiteralPath $projectionPath -Raw) -ceq $beforeOwnership) 'Ownership mismatch changed the target.'
    $ownershipForce = Invoke-Finalizer @($root, '--force')
    Assert-True ($ownershipForce.ExitCode -ne 0) 'Ownership mismatch unexpectedly bypassed --force.'
    Assert-True ((Get-Content -LiteralPath $projectionPath -Raw) -ceq $beforeOwnership) 'Ownership mismatch changed the target with --force.'
    Set-Content -LiteralPath $projectionPath -Value $profile

    Set-Content -LiteralPath $projectionPath -Value ($profile -replace 'model = "gpt-5\.6-terra"', "model = 'gpt-4.1' # explicit")
    $beforeMismatch = Get-Content -LiteralPath $projectionPath -Raw
    $mismatch = Invoke-Finalizer @($root)
    Assert-True ($mismatch.ExitCode -ne 0) 'Explicit mismatch unexpectedly succeeded.'
    Assert-True ((Get-Content -LiteralPath $projectionPath -Raw) -ceq $beforeMismatch) 'Mismatch changed the target without --force.'
    $forced = Invoke-Finalizer @($root, '--force')
    Assert-True ($forced.ExitCode -eq 0) "Forced profile update failed.`n$($forced.Output)"
    Assert-True ((Get-Content -LiteralPath $projectionPath -Raw) -match 'model = "gpt-5\.6-terra" # explicit') ("Forced update did not preserve the trailing comment.`n" + (Get-Content -LiteralPath $projectionPath -Raw))
    Assert-True ((Get-Content -LiteralPath $projectionPath -Raw) -match 'developer_instructions = "You are the fixture agent\."') 'Portable projection changed after force.'

    Write-AgentPackage $duplicate 'fixture-copy' 'agent' 'gpt-5.6-terra'
    Assert-True ((Invoke-Finalizer @($root, '--check')).ExitCode -eq 0) 'Identical duplicate overlay was not coalesced.'
    (Get-Content -LiteralPath (Join-Path $duplicate 'codex-profile-overlays.json') -Raw) -replace 'gpt-5\.6-terra', 'gpt-5.6-luna' | Set-Content -LiteralPath (Join-Path $duplicate 'codex-profile-overlays.json')
    $conflict = Invoke-Finalizer @($root)
    Assert-True ($conflict.ExitCode -ne 0) 'Conflicting overlay unexpectedly succeeded.'
    (Get-Content -LiteralPath (Join-Path $duplicate 'codex-profile-overlays.json') -Raw) -replace 'gpt-5\.6-luna', 'gpt-5.6-terra' | Set-Content -LiteralPath (Join-Path $duplicate 'codex-profile-overlays.json')

    Set-Content -LiteralPath $projectionPath -Value ($profile + "model = 'gpt-5.6-terra'`n")
    $duplicateField = Invoke-Finalizer @($root, '--force')
    Assert-True ($duplicateField.ExitCode -ne 0) 'Duplicate top-level profile field unexpectedly succeeded.'
    Set-Content -LiteralPath $projectionPath -Value $profile

    Set-Content -LiteralPath $projectionPath -Value ($profile -replace 'description = "Fixture description"', 'description = "unterminated')
    $invalidToml = Invoke-Finalizer @($root, '--force')
    Assert-True ($invalidToml.ExitCode -ne 0) 'Malformed TOML unexpectedly succeeded.'
    Set-Content -LiteralPath $projectionPath -Value $profile

    $emptyRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-profile-finalizer-empty-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null
        Assert-True ((Invoke-Finalizer @($emptyRoot, '--check')).ExitCode -ne 0) 'Missing apm_modules unexpectedly passed --check.'
        New-Item -ItemType Directory -Path (Join-Path $emptyRoot 'apm_modules') -Force | Out-Null
        Assert-True ((Invoke-Finalizer @($emptyRoot)).ExitCode -eq 0) 'Missing overlays did not remain a no-op.'
        Assert-True ((Invoke-Finalizer @($emptyRoot, '--check')).ExitCode -ne 0) 'Missing overlays unexpectedly passed --check.'
    } finally {
        if (Test-Path -LiteralPath $emptyRoot) { Remove-Item -LiteralPath $emptyRoot -Recurse -Force }
    }

    $invalid = Join-Parts $root @('apm_modules', 'owner', 'repo', 'apm-packages', 'invalid')
    New-Item -ItemType Directory -Path $invalid -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $invalid 'apm.yml') -Value 'name: invalid'
    Set-Content -LiteralPath (Join-Path $invalid 'codex-profile-overlays.json') -Value '{ invalid json'
    $invalidResult = Invoke-Finalizer @($root)
    Assert-True ($invalidResult.ExitCode -ne 0) 'Invalid overlay unexpectedly succeeded.'
    Assert-True ($invalidResult.Output -match 'JsonException|StackTrace|at System\.') 'Invalid overlay did not include exception diagnostics.'

    $adaptiveRoot = Join-Path ([IO.Path]::GetTempPath()) ('codex-profile-finalizer-adaptive-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Parts $adaptiveRoot @('.codex', 'agents')) -Force | Out-Null
        Write-AdaptivePackage $adaptiveRoot 'gpt-5.6-luna'
        foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
            Set-Content -LiteralPath (Join-Parts $adaptiveRoot @('.codex', 'agents', ($agent + '.toml'))) -Value @"
name = '$agent'
description = "Fixture description"
developer_instructions = "You are the fixture agent."
"@
        }
        $agentsDir = Join-Parts $adaptiveRoot @('.codex', 'agents')
        $otherAgent = Join-Path $agentsDir 'other-agent.toml'
        $configPath = Join-Parts $adaptiveRoot @('.codex', 'config.toml')
        $agentsMd = Join-Path $adaptiveRoot 'AGENTS.md'
        $skillPath = Join-Parts $adaptiveRoot @('.agents', 'skills', 'adaptive-implementation-execution', 'SKILL.md')
        $copilotAgent = Join-Parts $adaptiveRoot @('.github', 'agents', 'decision-surface-implementation-owner.agent.md')
        foreach ($path in @($otherAgent, $configPath, $agentsMd, $skillPath, $copilotAgent)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value "sentinel:$path" -NoNewline
        }
        $sentinelHashes = @{}
        foreach ($path in @($otherAgent, $configPath, $agentsMd, $skillPath, $copilotAgent)) {
            $sentinelHashes[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }

        Assert-True ((Invoke-Finalizer @($adaptiveRoot)).ExitCode -eq 0) 'Adaptive semantic owner profiles were not applied.'

        $adaptiveOverlay = Join-Parts $adaptiveRoot @('apm_modules', 'owner', 'repo', 'apm-packages', 'adaptive-implementation-execution', 'codex-profile-overlays.json')
        $packageAgents = Join-Parts $adaptiveRoot @('apm_modules', 'owner', 'repo', 'apm-packages', 'adaptive-implementation-execution', '.apm', 'agents')
        $parentProjection = Join-Path $agentsDir 'decision-surface-implementation-owner.toml'
        $childProjection = Join-Path $agentsDir 'bounded-residual-implementation-owner.toml'
        $parentBefore = Get-Content -Raw -LiteralPath $parentProjection
        $childApplied = Get-Content -Raw -LiteralPath $childProjection
        Assert-True ($parentBefore -notmatch '(?m)^(model|model_reasoning_effort|sandbox_mode)\s*=') 'Parent was unexpectedly pinned.'
        Assert-True ($childApplied -match 'model = "gpt-5\.6-luna"') 'Child model overlay was not applied.'
        Assert-True ($childApplied -match 'model_reasoning_effort = "high"') 'Child reasoning overlay was not applied.'
        Assert-True ($childApplied -match 'sandbox_mode = "workspace-write"') 'Child sandbox overlay was not applied.'
        Assert-True ($childApplied -match 'You are the fixture agent\.') 'Child canonical body was not projected.'
        $parentHash = (Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash
        $childHash = (Get-FileHash -LiteralPath $childProjection -Algorithm SHA256).Hash
        Assert-True ((Invoke-Finalizer @($adaptiveRoot, '--check')).ExitCode -eq 0) 'Child-only profile check failed.'
        Assert-True ((Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash -eq $parentHash) 'Parent projection was modified.'
        Assert-True ((Get-FileHash -LiteralPath $childProjection -Algorithm SHA256).Hash -eq $childHash) 'Compliant child projection was modified.'

        foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
            Set-Content -LiteralPath (Join-Path $agentsDir ($agent + '.toml')) -Value @"
name = "$agent"
description = "Fixture description"
developer_instructions = "OLD_KEPT_USER_EDITED_BODY"
model = "old-model"
model_reasoning_effort = "low"
sandbox_mode = "danger-full-access"
"@
        }
        $beforeRepair = (Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash
        $checked = Invoke-Finalizer @($adaptiveRoot, '--check')
        Assert-True ($checked.ExitCode -ne 0 -and $checked.Output -match 'update\(s\) required') 'Stale managed body passed --check.'
        Assert-True ((Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash -eq $beforeRepair) '--check changed a managed agent.'
        $dryRun = Invoke-Finalizer @($adaptiveRoot, '--dry-run')
        Assert-True ($dryRun.ExitCode -eq 0 -and $dryRun.Output -match 'planned') 'Dry-run did not report the managed repair.'
        Assert-True ((Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash -eq $beforeRepair) '--dry-run changed a managed agent.'
        $repaired = Invoke-Finalizer @($adaptiveRoot)
        Assert-True ($repaired.ExitCode -eq 0) "Managed canonical sync failed.`n$($repaired.Output)"
        $parentRepaired = Get-Content -Raw -LiteralPath $parentProjection
        $childRepaired = Get-Content -Raw -LiteralPath $childProjection
        Assert-True ($parentRepaired -notmatch 'OLD_KEPT_USER_EDITED_BODY' -and $childRepaired -notmatch 'OLD_KEPT_USER_EDITED_BODY') 'Kept user-edited body remained.'
        Assert-True ($parentRepaired -match 'You are the fixture agent\.' -and $childRepaired -match 'You are the fixture agent\.') 'Canonical body was not restored.'
        Assert-True ($parentRepaired -notmatch '(?m)^(model|model_reasoning_effort|sandbox_mode)\s*=') 'Parent pin survived canonical sync.'
        Assert-True ($childRepaired -match 'model = "gpt-5\.6-luna"' -and $childRepaired -match 'model_reasoning_effort = "high"' -and $childRepaired -match 'sandbox_mode = "workspace-write"') 'Child settings were not restored without --force.'
        $parentHash = (Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash
        $childHash = (Get-FileHash -LiteralPath $childProjection -Algorithm SHA256).Hash
        Assert-True ((Invoke-Finalizer @($adaptiveRoot)).ExitCode -eq 0) 'Idempotent managed sync failed.'
        Assert-True ((Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash -eq $parentHash -and (Get-FileHash -LiteralPath $childProjection -Algorithm SHA256).Hash -eq $childHash) 'Idempotent sync changed managed agents.'

        $canonicalBody = "You are the fixture agent.`nLine with `"quotes`" and \slash."
        foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
            $agentText = @('---', "name: $agent", 'description: Fixture description', '---', '', $canonicalBody) -join "`n"
            Set-Content -LiteralPath (Join-Path $packageAgents ($agent + '.agent.md')) -Value $agentText -NoNewline
        }
        $manual = Invoke-Finalizer @($adaptiveRoot, '--check')
        Assert-True ($manual.ExitCode -ne 0) 'Manually stale body passed --check.'
        $synced = Invoke-Finalizer @($adaptiveRoot)
        Assert-True ($synced.ExitCode -eq 0) "Manual edit was not replaced.`n$($synced.Output)"
        $escapedParent = Get-Content -Raw -LiteralPath $parentProjection
        Assert-True ($escapedParent.Contains('Line with \"quotes\" and \\slash.')) "Canonical escaping was not projected.`n$escapedParent"
        Assert-True ($escapedParent -notmatch '(?m)^(model|model_reasoning_effort|sandbox_mode)\s*=') 'Canonical body sync pinned the parent.'
        $stableParent = (Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash
        $stableChild = (Get-FileHash -LiteralPath $childProjection -Algorithm SHA256).Hash
        Assert-True ((Invoke-Finalizer @($adaptiveRoot, '--check')).ExitCode -eq 0) 'Repaired canonical body failed --check.'
        Assert-True ((Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash -eq $stableParent -and (Get-FileHash -LiteralPath $childProjection -Algorithm SHA256).Hash -eq $stableChild) 'Check after repair changed managed agents.'
        foreach ($path in $sentinelHashes.Keys) {
            Assert-True ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $sentinelHashes[$path]) "Unrelated file changed: $path"
        }

        $overlay = Get-Content -Raw -LiteralPath $adaptiveOverlay | ConvertFrom-Json
        $overlay.profiles += @{ agent='decision-surface-implementation-owner'; model='parent-pin'; model_reasoning_effort='high'; sandbox_mode='workspace-write' }
        $overlay | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $adaptiveOverlay
        $parentPin = Invoke-Finalizer @($adaptiveRoot, '--check')
        Assert-True ($parentPin.ExitCode -ne 0 -and $parentPin.Output -match 'only the child profile') 'Parent overlay was accepted.'
        @'
{
  "schemaVersion": 1,
  "package": "adaptive-implementation-execution",
  "profiles": [
    {
      "agent": "bounded-residual-implementation-owner",
      "model": "gpt-5.6-luna",
      "model_reasoning_effort": "high",
      "sandbox_mode": "workspace-write"
    }
  ]
}
'@ | Set-Content -LiteralPath $adaptiveOverlay

        $foreign = Join-Parts $adaptiveRoot @('apm_modules', 'owner', 'repo', 'apm-packages', 'foreign-parent')
        $foreignAgents = Join-Parts $foreign @('.apm', 'agents')
        New-Item -ItemType Directory -Path $foreignAgents -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $foreign 'apm.yml') -Value "name: foreign-parent`n"
        $foreignAgent = @('---', 'name: decision-surface-implementation-owner', 'description: Foreign', '---', '', 'Foreign parent body.') -join "`n"
        Set-Content -LiteralPath (Join-Path $foreignAgents 'decision-surface-implementation-owner.agent.md') -Value $foreignAgent -NoNewline
        @{ schemaVersion = 1; package = 'foreign-parent'; profiles = @(@{ agent = 'decision-surface-implementation-owner'; model = 'parent-pin'; model_reasoning_effort = 'high'; sandbox_mode = 'workspace-write' }) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $foreign 'codex-profile-overlays.json')
        $beforeForeign = (Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash
        $foreignResult = Invoke-Finalizer @($adaptiveRoot)
        Assert-True ($foreignResult.ExitCode -ne 0 -and $foreignResult.Output -match 'cannot accept a Codex profile overlay') 'Foreign parent overlay was accepted.'
        Assert-True ((Get-FileHash -LiteralPath $parentProjection -Algorithm SHA256).Hash -eq $beforeForeign) 'Foreign parent overlay changed the parent.'
    }
    finally {
        if (Test-Path -LiteralPath $adaptiveRoot) { Remove-Item -LiteralPath $adaptiveRoot -Recurse -Force }
    }

    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $realSnapshots = @{}
    foreach ($relative in @('.codex\agents\decision-surface-implementation-owner.toml', '.codex\agents\bounded-residual-implementation-owner.toml', '.codex\config.toml')) {
        $path = Join-Path $userProfile $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $realSnapshots[$path] = [IO.File]::ReadAllBytes($path)
        }
    }
    $realAgentsMutated = $false
    $previousApmHome = $env:APM_HOME
    $previousCodexHome = $env:CODEX_HOME
    $globalApmHome = Join-Path $root 'global-apm-home'
    $globalCodexHome = Join-Path $root 'global-codex-home'
    $decoyRoot = Join-Path $root 'project-decoy'
    try {
        New-Item -ItemType Directory -Path (Join-Parts $decoyRoot @('.codex', 'agents')) -Force | Out-Null
        Write-AdaptivePackage $decoyRoot 'gpt-5.6-luna'
        foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
            Set-Content -LiteralPath (Join-Parts $decoyRoot @('.codex', 'agents', ($agent + '.toml'))) -Value @"
name = '$agent'
description = "Fixture description"
developer_instructions = "OLD_KEPT_USER_EDITED_BODY"
"@
        }
        $env:APM_HOME = $globalApmHome
        $env:CODEX_HOME = $globalCodexHome
        Write-AdaptivePackage $globalApmHome 'gpt-5.6-luna'
        $globalAgents = Join-Path $globalCodexHome 'agents'
        New-Item -ItemType Directory -Path $globalAgents -Force | Out-Null
        foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
            Set-Content -LiteralPath (Join-Path $globalAgents ($agent + '.toml')) -Value @"
name = "$agent"
description = "Fixture description"
developer_instructions = "OLD_KEPT_USER_EDITED_BODY"
model = "old-model"
"@
        }
        $globalOther = Join-Path $globalAgents 'other-agent.toml'
        $globalConfig = Join-Path $globalCodexHome 'config.toml'
        Set-Content -LiteralPath $globalOther -Value 'name = "other-agent"' -NoNewline
        Set-Content -LiteralPath $globalConfig -Value 'sentinel-config' -NoNewline
        $globalOtherHash = (Get-FileHash -LiteralPath $globalOther -Algorithm SHA256).Hash
        $globalConfigHash = (Get-FileHash -LiteralPath $globalConfig -Algorithm SHA256).Hash
        $decoyParent = Join-Parts $decoyRoot @('.codex', 'agents', 'decision-surface-implementation-owner.toml')
        $decoyBefore = Get-Content -Raw -LiteralPath $decoyParent
        $decoyResult = Invoke-Finalizer @($decoyRoot)
        Assert-True ($decoyResult.ExitCode -eq 0) "Project-local finalizer failed while global homes were set.`n$($decoyResult.Output)"
        Assert-True ((Get-Content -Raw -LiteralPath $decoyParent) -notmatch 'OLD_KEPT_USER_EDITED_BODY') 'Project-local sync did not repair its own target.'
        Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $globalAgents 'decision-surface-implementation-owner.toml')) -match 'OLD_KEPT_USER_EDITED_BODY') 'Project-local sync changed the global Codex home.'
        $combined = Invoke-Finalizer @($decoyRoot, '--global')
        Assert-True ($combined.ExitCode -ne 0) '--global accepted a target repository.'

        $globalDry = Invoke-Finalizer @('--global', '--dry-run')
        Assert-True ($globalDry.ExitCode -eq 0 -and $globalDry.Output -match [regex]::Escape($globalAgents)) 'Global dry-run did not resolve CODEX_HOME.'
        Assert-True ((Get-Content -Raw -LiteralPath (Join-Path $globalAgents 'decision-surface-implementation-owner.toml')) -match 'OLD_KEPT_USER_EDITED_BODY') 'Global dry-run changed a managed agent.'
        $globalApply = Invoke-Finalizer @('--global')
        Assert-True ($globalApply.ExitCode -eq 0) "Global canonical sync failed.`n$($globalApply.Output)"
        $globalParent = Get-Content -Raw -LiteralPath (Join-Path $globalAgents 'decision-surface-implementation-owner.toml')
        $globalChild = Get-Content -Raw -LiteralPath (Join-Path $globalAgents 'bounded-residual-implementation-owner.toml')
        Assert-True ($globalParent -notmatch 'OLD_KEPT_USER_EDITED_BODY' -and $globalChild -notmatch 'OLD_KEPT_USER_EDITED_BODY') 'Global sync kept the old body.'
        Assert-True ($globalParent -notmatch '(?m)^(model|model_reasoning_effort|sandbox_mode)\s*=') 'Global sync pinned the parent.'
        Assert-True ($globalChild -match 'model = "gpt-5\.6-luna"') 'Global sync did not apply the child model.'
        Assert-True ((Get-Content -Raw -LiteralPath $decoyParent) -cne $decoyBefore) 'Project decoy was not synchronized before the global run.'
        $decoyAfterGlobal = Get-Content -Raw -LiteralPath $decoyParent
        Assert-True ((Invoke-Finalizer @('--global', '--check')).ExitCode -eq 0) 'Global check failed after sync.'
        Assert-True ((Get-Content -Raw -LiteralPath $decoyParent) -ceq $decoyAfterGlobal) 'Global sync changed the project-local decoy.'
        Assert-True ((Get-FileHash -LiteralPath $globalOther -Algorithm SHA256).Hash -eq $globalOtherHash) 'Global sync changed an unrelated agent.'
        Assert-True ((Get-FileHash -LiteralPath $globalConfig -Algorithm SHA256).Hash -eq $globalConfigHash) 'Global sync changed Codex config.toml.'
    }
    finally {
        if ($null -eq $previousApmHome) { Remove-Item Env:APM_HOME -ErrorAction SilentlyContinue } else { $env:APM_HOME = $previousApmHome }
        if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousCodexHome }
        foreach ($path in @($realSnapshots.Keys)) {
            $current = [IO.File]::ReadAllBytes($path)
            $before = $realSnapshots[$path]
            $same = $current.Length -eq $before.Length
            if ($same) {
                for ($i = 0; $i -lt $current.Length; $i++) {
                    if ($current[$i] -ne $before[$i]) { $same = $false; break }
                }
            }
            if (-not $same) {
                [IO.File]::WriteAllBytes($path, $before)
                $realAgentsMutated = $true
            }
        }
    }
    Assert-True (-not $realAgentsMutated) 'Finalizer modified the real user Codex home.'

    Write-Output 'Codex profile finalizer validation: PASS'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
