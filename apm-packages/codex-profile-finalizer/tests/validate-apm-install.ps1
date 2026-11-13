[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('codex-profile-finalizer-apm-' + [guid]::NewGuid().ToString('N'))

try {
    if (-not (Get-Command apm -ErrorAction SilentlyContinue)) {
        throw 'APM CLI is required for this smoke.'
    }

    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Push-Location $scratch
    try {
        $output = & apm install $packageRoot --target codex 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Local APM install failed: $output"
        }
    }
    finally {
        Pop-Location
    }

    $installed = Join-Path $scratch 'apm_modules/_local/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs'
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) {
        throw "Finalizer was not placed in the APM module: $installed"
    }

    $apmHome = Join-Path $scratch 'home-apm'
    $codexHome = Join-Path $scratch 'home-codex'
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
developer_instructions = "OLD_KEPT_USER_EDITED_BODY"
model = "old-model"
"@
    }
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

    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $realSnapshots = @{}
    foreach ($relative in @('.codex\agents\decision-surface-implementation-owner.toml', '.codex\agents\bounded-residual-implementation-owner.toml', '.codex\config.toml')) {
        $path = Join-Path $userProfile $relative
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $realSnapshots[$path] = [IO.File]::ReadAllBytes($path)
        }
    }
    $previousApmHome = $env:APM_HOME
    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:APM_HOME = $apmHome
        $env:CODEX_HOME = $codexHome
        $applied = & dotnet run --file $installed -- --global 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Installed finalizer did not synchronize the global managed agents.`n$applied"
        }
        $checked = & dotnet run --file $installed -- --global --check 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Installed finalizer check failed after global sync.`n$checked"
        }
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
                throw "Installed finalizer modified the real Codex home: $path"
            }
        }
    }

    $parent = Get-Content -Raw -LiteralPath (Join-Path $agentsRoot 'decision-surface-implementation-owner.toml')
    $child = Get-Content -Raw -LiteralPath (Join-Path $agentsRoot 'bounded-residual-implementation-owner.toml')
    if ($parent -match 'OLD_KEPT_USER_EDITED_BODY' -or $child -match 'OLD_KEPT_USER_EDITED_BODY') {
        throw 'Installed finalizer kept the old managed body.'
    }
    if ($parent -notmatch 'CANONICAL_INSTALLED_BODY' -or $child -notmatch 'CANONICAL_INSTALLED_BODY') {
        throw 'Installed finalizer did not project the canonical body.'
    }
    if ($parent -match '(?m)^(model|model_reasoning_effort|sandbox_mode)\s*=') {
        throw 'Installed finalizer pinned the parent agent.'
    }
    if ($child -notmatch 'model = "gpt-6-luna"') {
        throw 'Installed finalizer did not apply the child model.'
    }
    if ((Get-FileHash -LiteralPath $unrelated -Algorithm SHA256).Hash -ne $unrelatedHash -or
        (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -ne $configHash) {
        throw 'Installed finalizer changed an unrelated Codex file.'
    }

    Write-Output 'Codex profile finalizer local APM install: PASS'
}
finally {
    if (Test-Path -LiteralPath $scratch) {
        $resolved = [IO.Path]::GetFullPath($scratch)
        if (-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unsafe scratch path: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
