[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\finalize-codex-agent-profiles.cs'))
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-profile-finalizer-test-' + [guid]::NewGuid().ToString('N'))

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-Finalizer([string[]] $Arguments) {
    $output = & dotnet run --file $scriptPath -- @Arguments 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Write-AgentPackage([string] $PackageRoot, [string] $PackageName, [string] $Agent, [string] $Model) {
    New-Item -ItemType Directory -Path (Join-Path $PackageRoot '.apm\agents') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $PackageRoot 'apm.yml') -Value ("name: $PackageName" + [Environment]::NewLine)
    Set-Content -LiteralPath (Join-Path $PackageRoot '.apm\agents\agent.agent.md') -Value ("---" + [Environment]::NewLine + "name: $Agent" + [Environment]::NewLine + "---" + [Environment]::NewLine)
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

try {
    $package = Join-Path $root 'apm_modules\owner\repo\apm-packages\adaptive-implementation-execution'
    $duplicate = Join-Path $root 'apm_modules\owner\repo\apm-packages\adaptive-copy'
    New-Item -ItemType Directory -Path (Join-Path $root '.codex\agents') -Force | Out-Null
    Write-AgentPackage $package 'adaptive-implementation-execution' 'agent' 'gpt-5.6-terra'
    Set-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Value ('name = "agent"' + [Environment]::NewLine + 'description = "fixture"' + [Environment]::NewLine + 'developer_instructions = "fixture"' + [Environment]::NewLine)

    $result = Invoke-Finalizer @($root)
    Assert-True ($result.ExitCode -eq 0) 'Initial finalizer apply failed.'
    $profile = Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw
    Assert-True ($profile -match 'model = "gpt-5\.6-terra"') 'Initial model overlay was not applied.'
    Assert-True ($profile -match 'description = "fixture"') 'Portable projected fields were changed.'
    Assert-True ((Invoke-Finalizer @($root, '--check')).ExitCode -eq 0) 'Compliant profile check failed.'

    $beforeDryRun = Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw
    $dryRun = Invoke-Finalizer @($root, '--dry-run')
    Assert-True ($dryRun.ExitCode -eq 0) 'Dry-run unexpectedly failed.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw) -ceq $beforeDryRun) 'Dry-run changed the target.'

    Set-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Value ($profile -replace 'name = "agent"', 'name = "other"')
    $beforeOwnership = Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw
    $ownership = Invoke-Finalizer @($root)
    Assert-True ($ownership.ExitCode -ne 0) 'Projection ownership mismatch unexpectedly succeeded.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw) -ceq $beforeOwnership) 'Ownership mismatch changed the target.'
    Set-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Value $profile

    Set-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Value ($profile -replace 'gpt-5\.6-terra', 'gpt-4.1')
    $beforeMismatch = Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw
    $mismatch = Invoke-Finalizer @($root)
    Assert-True ($mismatch.ExitCode -ne 0) 'Explicit mismatch unexpectedly succeeded.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root '.codex\agents\agent.toml') -Raw) -ceq $beforeMismatch) 'Mismatch changed the target without --force.'
    Assert-True ((Invoke-Finalizer @($root, '--force')).ExitCode -eq 0) 'Forced profile update failed.'

    Write-AgentPackage $duplicate 'adaptive-copy' 'agent' 'gpt-5.6-terra'
    Assert-True ((Invoke-Finalizer @($root, '--check')).ExitCode -eq 0) 'Identical duplicate overlay was not coalesced.'
    (Get-Content -LiteralPath (Join-Path $duplicate 'codex-profile-overlays.json') -Raw) -replace 'gpt-5\.6-terra', 'gpt-5.6-luna' | Set-Content -LiteralPath (Join-Path $duplicate 'codex-profile-overlays.json')
    $conflict = Invoke-Finalizer @($root)
    Assert-True ($conflict.ExitCode -ne 0) 'Conflicting overlay unexpectedly succeeded.'

    Write-Output 'Codex profile finalizer validation: PASS'
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}
