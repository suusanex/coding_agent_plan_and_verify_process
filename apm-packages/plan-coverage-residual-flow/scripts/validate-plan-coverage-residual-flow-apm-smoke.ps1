[CmdletBinding()]
param(
    [string]$Repository,
    [string]$Ref
)

$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $packageRoot '../..')).Path
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$tempRoot = Join-Path $tempParent ('plan-coverage-residual-flow-smoke-' + [Guid]::NewGuid().ToString('N'))

if ([string]::IsNullOrWhiteSpace($Repository) -xor [string]::IsNullOrWhiteSpace($Ref)) {
    throw 'Repository and Ref must be supplied together.'
}

$source = if ([string]::IsNullOrWhiteSpace($Repository)) {
    Join-Path $packageRoot '.apm/skills/plan-coverage-residual-flow'
}
else {
    "$Repository/apm-packages/plan-coverage-residual-flow#$Ref"
}

function Get-NormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-NormalizedTextSha256([string]$Path) {
    $content = Get-NormalizedText $Path
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($content)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Push-Location $tempRoot
    try {
        $installArguments = @('install', $source, '--target', 'agent-skills')
        if (-not [string]::IsNullOrWhiteSpace($Repository)) {
            $installArguments += '--https'
        }

        & apm @installArguments
        if ($LASTEXITCODE -ne 0) {
            throw "apm install failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $canonicalSkillPath = Join-Path $repoRoot 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow/SKILL.md'
    $installedSkillPath = Join-Path $tempRoot '.agents/skills/plan-coverage-residual-flow/SKILL.md'
    $lockPath = Join-Path $tempRoot 'apm.lock.yaml'

    if (-not (Test-Path -LiteralPath $installedSkillPath -PathType Leaf)) {
        throw 'Fresh APM install did not deploy the Plan Coverage Skill.'
    }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        throw 'Fresh APM install did not create apm.lock.yaml.'
    }
    if ((Get-NormalizedText $canonicalSkillPath) -cne (Get-NormalizedText $installedSkillPath)) {
        throw 'Fresh APM installed Skill differs from the canonical package Skill.'
    }

    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        $lock = Get-NormalizedText $lockPath
        $lockBlock = [regex]::Match($lock, '(?ms)^- .*?name: plan-coverage-residual-flow\n(?<block>.*?)(?=^- |\z)')
        if (-not $lockBlock.Success) {
            throw 'Fresh APM lock does not contain the Plan Coverage package.'
        }

        $block = $lockBlock.Groups['block'].Value
        if ($block -cnotmatch '(?m)^  version:\s*0\.8\.1\s*$') {
            throw 'Fresh APM lock does not contain Plan Coverage package version 0.8.1.'
        }

        $installedHash = Get-NormalizedTextSha256 $installedSkillPath
        if ($block -cnotmatch "(?m)^    \.agents/skills/plan-coverage-residual-flow/SKILL\.md: sha256:$installedHash\s*$") {
            throw 'Fresh APM lock deployed Skill hash does not match the installed file.'
        }
    }

    Write-Host 'Plan Coverage Residual Flow APM install smoke: PASS'
}
finally {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTempRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTempRoot).StartsWith('plan-coverage-residual-flow-smoke-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
