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

function Write-AdaptivePackage([string] $Root, [string] $DecisionModel, [string] $ResidualModel) {
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
                agent = 'decision-surface-implementation-owner'
                model = $DecisionModel
                model_reasoning_effort = 'high'
                sandbox_mode = 'workspace-write'
            },
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
        Write-AdaptivePackage $adaptiveRoot 'gpt-5.6-terra' 'gpt-5.6-luna'
        foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
            Set-Content -LiteralPath (Join-Parts $adaptiveRoot @('.codex', 'agents', ($agent + '.toml'))) -Value @"
name = '$agent'
description = "Fixture description"
developer_instructions = "You are the fixture agent."
"@
        }
        Assert-True ((Invoke-Finalizer @($adaptiveRoot)).ExitCode -eq 0) 'Adaptive semantic owner profiles were not applied.'

        $adaptiveOverlay = Join-Parts $adaptiveRoot @('apm_modules', 'owner', 'repo', 'apm-packages', 'adaptive-implementation-execution', 'codex-profile-overlays.json')
        (Get-Content -Raw -LiteralPath $adaptiveOverlay) -replace 'gpt-5\.6-luna', 'gpt-5.6-terra' | Set-Content -LiteralPath $adaptiveOverlay
        $sameModel = Invoke-Finalizer @($adaptiveRoot, '--check')
        Assert-True ($sameModel.ExitCode -ne 0) 'Adaptive semantic owners unexpectedly accepted the same model mapping.'
        Assert-True ($sameModel.Output -match 'semantic owners with distinct model mappings') 'Adaptive same-model failure was not explicit.'
    }
    finally {
        if (Test-Path -LiteralPath $adaptiveRoot) { Remove-Item -LiteralPath $adaptiveRoot -Recurse -Force }
    }

    Write-Output 'Codex profile finalizer validation: PASS'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
