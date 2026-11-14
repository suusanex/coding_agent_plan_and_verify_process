[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('codex-profile-finalizer-apm-' + [guid]::NewGuid().ToString('N'))
$userProfile = Join-Path $scratch 'home-profile'
$apmHome = Join-Path $userProfile '.apm'
$codexHome = Join-Path $scratch 'home-codex'
$previousApmHome = $env:APM_HOME
$previousUserProfile = $env:USERPROFILE
$previousHome = $env:HOME
$previousCodexHome = $env:CODEX_HOME

try {
    if (-not (Get-Command apm -ErrorAction SilentlyContinue)) {
        throw 'APM CLI is required for this smoke.'
    }

    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    $env:APM_HOME = Join-Path $scratch 'ignored-apm-home'
    $env:USERPROFILE = $userProfile
    $env:HOME = $userProfile
    $env:CODEX_HOME = $codexHome
    Push-Location $scratch
    try {
        $output = & apm install --global $packageRoot --target codex 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Global APM install failed: $output"
        }
    }
    finally {
        Pop-Location
    }

    $installed = Get-ChildItem -LiteralPath (Join-Path $apmHome 'apm_modules') -Filter 'finalize-codex-agent-profiles.cs' -File -Recurse |
        Where-Object { $_.FullName -match '[\\/]codex-profile-finalizer[\\/]scripts[\\/]finalize-codex-agent-profiles\.cs$' } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $installed) { throw "Finalizer was not placed in the global APM module store: $apmHome" }

    $fixturePackage = Join-Path $apmHome 'apm_modules\owner\repo\apm-packages\adaptive-implementation-execution'
    $agentRoot = Join-Path $fixturePackage '.apm\agents'
    $agentsRoot = Join-Path $codexHome 'agents'
    New-Item -ItemType Directory -Path $agentRoot, $agentsRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $fixturePackage 'apm.yml') -Value "name: adaptive-implementation-execution`n" -NoNewline
    foreach ($agent in @('decision-surface-implementation-owner', 'bounded-residual-implementation-owner')) {
        $agentText = @('---', "name: $agent", 'description: Fixture description', '---', '', 'CANONICAL_INSTALLED_BODY') -join "`n"
        Set-Content -LiteralPath (Join-Path $agentRoot ($agent + '.agent.md')) -Value $agentText -NoNewline
        Set-Content -LiteralPath (Join-Path $agentsRoot ($agent + '.toml')) -Value @"
name = "$agent"
description = "Fixture description"
developer_instructions = "CANONICAL_INSTALLED_BODY"
model = "gpt-6-luna"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
"@
    }
    Set-Content -LiteralPath (Join-Path $agentsRoot 'decision-surface-implementation-owner.toml') -Value @'
name = "decision-surface-implementation-owner"
description = "Fixture description"
developer_instructions = "CANONICAL_INSTALLED_BODY"
'@
    @{
        schemaVersion = 1
        package = 'adaptive-implementation-execution'
        profiles = @(@{
            agent = 'bounded-residual-implementation-owner'
            model = 'gpt-6-luna'
            model_reasoning_effort = 'high'
            sandbox_mode = 'workspace-write'
        })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixturePackage 'codex-profile-overlays.json')
    $unrelated = Join-Path $agentsRoot 'other-agent.toml'
    $config = Join-Path $codexHome 'config.toml'
    Set-Content -LiteralPath $unrelated -Value 'name = "other-agent"' -NoNewline
    Set-Content -LiteralPath $config -Value 'sentinel-config' -NoNewline
    $unrelatedHash = (Get-FileHash -LiteralPath $unrelated -Algorithm SHA256).Hash
    $configHash = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash

    try {
        $applied = & dotnet run --file $installed -- --global 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Installed finalizer did not preserve compliant global profiles.`n$applied"
        }
        $checked = & dotnet run --file $installed -- --global --check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Installed finalizer check failed for global profiles.`n$checked"
        }
    }
    finally {
    }

    $parent = Get-Content -Raw -LiteralPath (Join-Path $agentsRoot 'decision-surface-implementation-owner.toml')
    $child = Get-Content -Raw -LiteralPath (Join-Path $agentsRoot 'bounded-residual-implementation-owner.toml')
    if ($parent -notmatch 'CANONICAL_INSTALLED_BODY' -or $child -notmatch 'CANONICAL_INSTALLED_BODY') {
        throw 'Installed finalizer changed canonical portable developer instructions.'
    }
    if ($parent -match '(?m)^(model|model_reasoning_effort|sandbox_mode)\s*=') {
        throw 'Installed finalizer accepted profile fields on the parent agent.'
    }
    if ($child -notmatch 'model = "gpt-6-luna"') {
        throw 'Installed finalizer did not apply the child model.'
    }
    if ((Get-FileHash -LiteralPath $unrelated -Algorithm SHA256).Hash -ne $unrelatedHash -or
        (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -ne $configHash) {
        throw 'Installed finalizer changed an unrelated Codex file.'
    }

    Write-Output 'Codex profile finalizer global APM install: PASS'
}
finally {
    if ($null -eq $previousApmHome) { Remove-Item Env:APM_HOME -ErrorAction SilentlyContinue } else { $env:APM_HOME = $previousApmHome }
    if ($null -eq $previousUserProfile) { Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue } else { $env:USERPROFILE = $previousUserProfile }
    if ($null -eq $previousHome) { Remove-Item Env:HOME -ErrorAction SilentlyContinue } else { $env:HOME = $previousHome }
    if ($null -eq $previousCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $previousCodexHome }
    if (Test-Path -LiteralPath $scratch) {
        $resolved = [IO.Path]::GetFullPath($scratch)
        if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe scratch path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
