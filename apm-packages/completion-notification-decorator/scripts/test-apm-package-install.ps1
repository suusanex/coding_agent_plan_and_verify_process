[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apmCommand = @(Get-Command apm -CommandType Application -ErrorAction Stop)[0]
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$scratchPath = Join-Path $tempRoot ('completion-notification-decorator-apm-' + [guid]::NewGuid().ToString('N'))
$resolvedScratchPath = $null
$safeToDelete = $false
$locationPushed = $false

try {
    $null = New-Item -ItemType Directory -Path $scratchPath
    $resolvedScratchPath = (Resolve-Path -LiteralPath $scratchPath).Path
    if (-not $resolvedScratchPath.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use scratch path outside the system temporary directory: $resolvedScratchPath"
    }
    $safeToDelete = $true

    Push-Location -LiteralPath $resolvedScratchPath
    $locationPushed = $true
    try {
        & $apmCommand.Source install $packageRoot --target 'codex,agent-skills'
        if ($LASTEXITCODE -ne 0) { throw "apm install failed with exit code $LASTEXITCODE" }
    }
    finally {
        Pop-Location
        $locationPushed = $false
    }

    $expectedFiles = @(
        'SKILL.md',
        'agents/openai.yaml',
        'references/envelope-authoring-contract.md'
    )
    foreach ($relativePath in $expectedFiles) {
        $sourcePath = Join-Path $packageRoot ".apm/skills/completion-notification-decorator/$relativePath"
        $installedPath = Join-Path $resolvedScratchPath ".agents/skills/completion-notification-decorator/$relativePath"
        if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) {
            throw "APM installation did not deploy required file: $relativePath"
        }
        if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash) {
            throw "Installed file does not match package source: $relativePath"
        }
    }

    Write-Output 'Completion Notification Decorator package-root APM install smoke test: PASS'
}
finally {
    if ($locationPushed) { Pop-Location }
    if ($safeToDelete -and $resolvedScratchPath -and (Test-Path -LiteralPath $resolvedScratchPath)) {
        Remove-Item -LiteralPath $resolvedScratchPath -Recurse -Force
    }
}
