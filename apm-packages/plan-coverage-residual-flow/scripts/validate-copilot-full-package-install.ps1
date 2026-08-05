[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('plan-coverage-residual-flow', 'token-aware-full-coverage-3layer')]
    [string]$PackageName,

    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repository,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$Ref,

    [string]$OutputRoot,

    [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' '..')))).Path
$packageRoot = Join-Path $repoRoot (Join-Path 'apm-packages' $PackageName)
$manifestPath = Join-Path $packageRoot 'apm.yml'
$defaultOutputRoot = Join-Path $packageRoot (Join-Path 'tests' (Join-Path 'copilot-cli' 'runs'))
$rawOutputRoot = if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $defaultOutputRoot } else { $OutputRoot }
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($rawOutputRoot)
$runRoot = Join-Path $resolvedOutputRoot "full-package-install-$PackageName-$(Get-Date -Format yyyyMMdd-HHmmss)-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$workspace = Join-Path $runRoot 'workspace'
$collisionWorkspace = Join-Path $runRoot 'collision-workspace'

function Write-Utf8File([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllLines($Path, $Lines, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured([string]$FilePath, [string[]]$Arguments, [string]$OutputPath) {
    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    Write-Utf8File $OutputPath @($output | ForEach-Object { [string]$_ })
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Description`: $Path"
    }
}

function Assert-Contains([string]$Text, [string]$Pattern, [string]$Description) {
    if ($Text -notmatch $Pattern) {
        throw "Missing $Description."
    }
}

function Get-LockBlock([string]$LockPath, [string]$Name) {
    Assert-File $LockPath 'APM lockfile'
    $lockText = [System.IO.File]::ReadAllText($LockPath).Replace("`r`n", "`n").Replace("`r", "`n")
    $match = [regex]::Match(
        $lockText,
        "(?ms)^- repo_url: .*?\n  name: $([regex]::Escape($Name))\n(?<block>.*?)(?=^- repo_url: |\z)"
    )
    if (-not $match.Success) {
        throw "APM lockfile has no package block for $Name."
    }
    return [pscustomobject]@{
        FullText = $match.Value
        Body = $match.Groups['block'].Value
    }
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Package manifest does not exist: $manifestPath"
}

$manifest = [System.IO.File]::ReadAllText($manifestPath).Replace("`r`n", "`n").Replace("`r", "`n")
$versionMatch = [regex]::Match($manifest, '(?m)^version:\s*(\S+)\s*$')
if (-not $versionMatch.Success) {
    throw "Package manifest has no version: $manifestPath"
}
$expectedVersion = $versionMatch.Groups[1].Value

$assetPaths = if ($PackageName -eq 'plan-coverage-residual-flow') {
    @(
        '.agents/skills/plan-coverage-residual-flow/SKILL.md',
        '.github/instructions/plan-coverage-shared.instructions.md',
        '.github/agents/plan-kernel.agent.md',
        '.github/agents/high-implementation-starter.agent.md'
    )
}
else {
    @(
        '.agents/skills/token-aware-full-coverage-3layer/SKILL.md',
        '.github/instructions/plan-coverage-shared.instructions.md',
        '.github/instructions/token-aware-full-coverage-3layer.instructions.md',
        '.github/agents/slice-prep.agent.md',
        '.github/agents/slice-impl.agent.md'
    )
}

$packageSpec = "$Repository/apm-packages/$PackageName#$Ref"
$apmVersionText = (& apm --version 2>&1 | Out-String).Trim()
if ($apmVersionText -notmatch '\b0\.26\.0\b') {
    throw "APM 0.26.0 is required for the reproducible Copilot package check. Observed: $apmVersionText"
}
$installResult = $null
$collisionResult = $null
$collisionAgent = if ($PackageName -eq 'plan-coverage-residual-flow') {
    '.github/agents/plan-kernel.agent.md'
}
else {
    '.github/agents/slice-prep.agent.md'
}
$collisionHash = $null
$resultLines = [System.Collections.Generic.List[string]]::new()

try {
    New-Item -ItemType Directory -Path $workspace, $collisionWorkspace -Force | Out-Null

    Push-Location $workspace
    try {
        $installResult = Invoke-Captured 'apm' @(
            'install',
            $packageSpec,
            '--target',
            'copilot,agent-skills',
            '--https',
            '--no-audit'
        ) (Join-Path $runRoot 'install-output.txt')
    }
    finally {
        Pop-Location
    }
    if ($installResult.ExitCode -ne 0) {
        throw "Full-package install failed with exit code $($installResult.ExitCode)."
    }

    foreach ($relativePath in $assetPaths) {
        Assert-File (Join-Path $workspace $relativePath) "deployed asset $relativePath"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workspace '.agents/skills') -PathType Container)) {
        throw 'The installed workspace has no .agents/skills directory.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workspace '.github/instructions') -PathType Container)) {
        throw 'The installed workspace has no .github/instructions directory.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $workspace '.github/agents') -PathType Container)) {
        throw 'The installed workspace has no .github/agents directory.'
    }

    $lockPath = Join-Path $workspace 'apm.lock.yaml'
    $lockBlock = Get-LockBlock $lockPath $PackageName
    Assert-Contains $lockBlock.FullText 'repo_url:\s+suusanex/coding_agent_plan_and_verify_process' 'lockfile source repository'
    Assert-Contains $lockBlock.Body "(?m)^  resolved_commit:\s*$Ref\s*$" 'lockfile resolved commit'
    Assert-Contains $lockBlock.Body "(?m)^  resolved_ref:\s*$Ref\s*$" 'lockfile resolved ref'
    Assert-Contains $lockBlock.Body "(?m)^  version:\s*$([regex]::Escape($expectedVersion))\s*$" 'lockfile package version'
    Assert-Contains $lockBlock.Body '(?m)^  content_hash:\s*sha256:[0-9a-f]{64}\s*$' 'lockfile content hash'

    $skillRelativePath = $assetPaths[0]
    $skillHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $workspace $skillRelativePath)).Hash.ToLowerInvariant()
    Assert-Contains $lockBlock.Body "(?m)^    $([regex]::Escape($skillRelativePath)): sha256:$skillHash\s*$" 'lockfile deployed Skill hash'

    $collisionAgentPath = Join-Path $collisionWorkspace $collisionAgent
    New-Item -ItemType Directory -Path (Split-Path -Parent $collisionAgentPath) -Force | Out-Null
    Write-Utf8File $collisionAgentPath @('UNMANAGED_COLLISION_SENTINEL')
    $collisionHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $collisionAgentPath).Hash
    Push-Location $collisionWorkspace
    try {
        $collisionResult = Invoke-Captured 'apm' @(
            'install',
            $packageSpec,
            '--target',
            'copilot,agent-skills',
            '--https',
            '--no-audit'
        ) (Join-Path $runRoot 'collision-output.txt')
    }
    finally {
        Pop-Location
    }
    Assert-File $collisionAgentPath 'unmanaged collision sentinel'
    $collisionHashAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $collisionAgentPath).Hash
    if ($collisionHashAfter -cne $collisionHash) {
        throw "APM overwrote an unmanaged Copilot agent collision: $collisionAgent"
    }

    [void]$resultLines.Add("# Copilot full-package installation check")
    [void]$resultLines.Add('')
    [void]$resultLines.Add("- Package: $PackageName")
    [void]$resultLines.Add("- Package source: $packageSpec")
    [void]$resultLines.Add("- Expected package version: $expectedVersion")
    [void]$resultLines.Add("- APM version: $apmVersionText")
    [void]$resultLines.Add("- Clean install exit code: $($installResult.ExitCode)")
    [void]$resultLines.Add("- Required .agents/skills, .github/instructions, and .github/agents assets: PASS")
    [void]$resultLines.Add("- Lock source/ref/version/content hash/deployed Skill hash: PASS")
    [void]$resultLines.Add("- Unmanaged collision protection: PASS (sentinel preserved; collision install exit $($collisionResult.ExitCode))")
    [void]$resultLines.Add("- Result: PASS")
    Write-Utf8File (Join-Path $runRoot 'result.md') $resultLines

    Write-Host "Copilot full-package installation check: PASS"
    Write-Host "Package: $PackageName"
    Write-Host "Source: $packageSpec"
    Write-Host "Version: $expectedVersion"
    Write-Host "Lock identity and deployed asset hashes: PASS"
    Write-Host "Unmanaged collision protection: PASS"
    Write-Host "Result: $(Join-Path $runRoot 'result.md')"
}
finally {
    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $runRoot)) {
        Remove-Item -LiteralPath $runRoot -Recurse -Force
    }
}
