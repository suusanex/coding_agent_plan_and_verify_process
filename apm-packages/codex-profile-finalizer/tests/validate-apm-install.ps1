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
