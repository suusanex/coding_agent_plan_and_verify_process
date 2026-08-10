# External oracle for STD-001. Qualification harness keeps authority over this file.
$ErrorActionPreference = 'Stop'

$repoRoot = if ($PSScriptRoot) {
    if ((Split-Path -Leaf $PSScriptRoot) -ceq 'tests') {
        Split-Path -Parent $PSScriptRoot
    }
    else {
        # When invoked from qualification package path .../standard-slice/verify.ps1
        # against a worktree, the harness sets RQ_WORKTREE.
        $env:RQ_WORKTREE
    }
} else {
    $env:RQ_WORKTREE
}

if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    throw 'STD-001 verifier requires worktree root via RQ_WORKTREE or tests/ layout.'
}

$repoRoot = [System.IO.Path]::GetFullPath($repoRoot)
$loaderPath = Join-Path $repoRoot 'src/Load-AppConfig.ps1'
if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
    throw "Missing production entrypoint: $loaderPath"
}

. $loaderPath
if (-not (Get-Command Import-AppConfig -ErrorAction SilentlyContinue)) {
    throw 'Import-AppConfig function was not defined by the production entrypoint.'
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('std-001-oracle-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $validPath = Join-Path $tempRoot 'valid.json'
    @{
        AppName = 'std-001-demo'
        Port = 8080
        EnableFeatureX = $true
    } | ConvertTo-Json | Set-Content -LiteralPath $validPath -Encoding utf8

    $cfg = Import-AppConfig -Path $validPath
    if ($null -eq $cfg) { throw 'Valid config returned null.' }
    if ($cfg.AppName -cne 'std-001-demo') { throw 'AppName mismatch.' }
    if ([int]$cfg.Port -ne 8080) { throw 'Port mismatch.' }
    if ([bool]$cfg.EnableFeatureX -ne $true) { throw 'EnableFeatureX mismatch.' }

    $names = @($cfg.psobject.Properties.Name | Sort-Object)
    $expectedNames = @('AppName', 'EnableFeatureX', 'Port')
    if (($names -join ',') -cne ($expectedNames -join ',')) {
        throw "Unexpected property set: $($names -join ',')"
    }

    $cases = @(
        @{
            name = 'missing-file'
            setup = {
                Join-Path $tempRoot 'missing.json'
            }
        }
        @{
            name = 'invalid-json'
            setup = {
                $p = Join-Path $tempRoot 'invalid.json'
                Set-Content -LiteralPath $p -Value '{ not-json' -Encoding utf8
                $p
            }
        }
        @{
            name = 'missing-key'
            setup = {
                $p = Join-Path $tempRoot 'missing-key.json'
                @{ AppName = 'x'; Port = 1 } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding utf8
                $p
            }
        }
        @{
            name = 'empty-appname'
            setup = {
                $p = Join-Path $tempRoot 'empty-name.json'
                @{ AppName = ''; Port = 1; EnableFeatureX = $false } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding utf8
                $p
            }
        }
        @{
            name = 'bad-port'
            setup = {
                $p = Join-Path $tempRoot 'bad-port.json'
                @{ AppName = 'x'; Port = 0; EnableFeatureX = $false } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding utf8
                $p
            }
        }
    )

    foreach ($case in $cases) {
        $path = & $case.setup
        $threw = $false
        try {
            $partial = Import-AppConfig -Path $path
            if ($null -ne $partial) {
                throw "Case $($case.name) returned a value instead of throwing."
            }
        }
        catch {
            $threw = $true
        }
        if (-not $threw) {
            throw "Case $($case.name) did not throw."
        }
    }

    [pscustomobject]@{
        verdict = 'STD_001_VERIFIED'
        production_entrypoint = 'src/Load-AppConfig.ps1'
        valid_config_ok = $true
        negative_cases = @($cases | ForEach-Object { $_.name })
    } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
