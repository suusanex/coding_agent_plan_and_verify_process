[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$apmCommand = @(Get-Command apm -CommandType Application -ErrorAction Stop)[0]
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$scratchPath = Join-Path $tempRoot ("goal-context-authoring-apm-" + [guid]::NewGuid().ToString('N'))
$resolvedScratchPath = $null
$safeToDelete = $false
$locationPushed = $false

try {
    $null = New-Item -ItemType Directory -Path $scratchPath
    $resolvedScratchPath = (Resolve-Path -LiteralPath $scratchPath).Path
    $requiredPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedScratchPath.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use scratch path outside the system temporary directory: $resolvedScratchPath"
    }
    $safeToDelete = $true

    Push-Location -LiteralPath $resolvedScratchPath
    $locationPushed = $true
    try {
        # Exercise the package-root apm install path, including apm.yml and target resolution.
        & $apmCommand.Source install $packageRoot --target 'codex,agent-skills'
        if ($LASTEXITCODE -ne 0) {
            throw "apm install failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
        $locationPushed = $false
    }

    $expectedFiles = @(
        'SKILL.md',
        'references/generation-prompt.md',
        'references/goal-context-contract.md',
        'references/goal-context-template.md',
        'references/human-review-checklist.md',
        'scripts/validate-goal-context.cs'
    )
    foreach ($relativePath in $expectedFiles) {
        $sourcePath = Join-Path $packageRoot ".apm/skills/goal-context-authoring/$relativePath"
        $installedPath = Join-Path $resolvedScratchPath ".agents/skills/goal-context-authoring/$relativePath"
        if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) {
            throw "APM installation did not deploy required file: $relativePath"
        }

        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash
        if ($sourceHash -ne $installedHash) {
            throw "Installed file does not match package source: $relativePath"
        }
    }

    $installedValidator = Join-Path $resolvedScratchPath '.agents/skills/goal-context-authoring/scripts/validate-goal-context.cs'
    & dotnet run --file $installedValidator -- --help
    if ($LASTEXITCODE -ne 0) {
        throw "Installed Goal Context validator help failed with exit code $LASTEXITCODE"
    }
    & dotnet run --file $installedValidator -- --goal-context (Join-Path $packageRoot 'docs/examples/goal-context-resumable-local-batch-export.md') --mode strict --format json
    if ($LASTEXITCODE -ne 0) {
        throw "Installed Goal Context validator rejected the reviewed example with exit code $LASTEXITCODE"
    }

    Write-Output 'Goal Context Authoring package-root APM install smoke test: PASS'
}
finally {
    if ($locationPushed) {
        Pop-Location
    }
    if ($safeToDelete -and $resolvedScratchPath -and (Test-Path -LiteralPath $resolvedScratchPath)) {
        Remove-Item -LiteralPath $resolvedScratchPath -Recurse -Force
    }
}
