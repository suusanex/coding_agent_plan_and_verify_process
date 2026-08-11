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
$stageRoot = $null

if ([string]::IsNullOrWhiteSpace($Repository) -xor [string]::IsNullOrWhiteSpace($Ref)) {
    throw 'Repository and Ref must be supplied together.'
}

$planCoverageOwnedAgentNames = @(
    'plan-kernel',
    'black-box-behavior-spec-kernel',
    'change-risk-triage',
    'architecture-slice-readiness',
    'architecture-elaboration',
    'plan-slice-decomposition',
    'implementation-contract-kernel',
    'implementation-contract-review-kernel',
    'runtime-contract-kernel',
    'test-design-kernel',
    'implementation-handoff-review',
    'implementation-execution',
    'code-review-focus-kernel',
    'verification-kernel',
    'cross-slice-verification-kernel',
    'coverage-gap-triage',
    'coverage-gap-resolution-slice',
    'residual-decision-gate'
)

function Get-NormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Get-NormalizedTextSha256([string]$Path) {
    $content = Get-NormalizedText $Path
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Copy-DirectoryContents([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Push-Location $tempRoot
    try {
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            # Local path installs cannot resolve git:parent. Stage a monorepo slice and
            # rewrite Adaptive agent deps to absolute paths so multi-target projection
            # structure can still be validated without remote git parent context.
            # Local path installs cannot resolve git:parent. Stage package copies and
            # place Adaptive HIGH/STANDARD agents under staged Adaptive .apm/agents so
            # includes:auto can distribute them without monorepo parent context.
            $stageRoot = Join-Path $tempParent ('plan-coverage-residual-flow-stage-' + [Guid]::NewGuid().ToString('N'))
           $stagePackage = Join-Path $stageRoot 'apm-packages\plan-coverage-residual-flow'
           $stageAdaptive = Join-Path $stageRoot 'apm-packages\adaptive-implementation-execution'
            $stageFinalizer = Join-Path $stageRoot 'apm-packages\codex-profile-finalizer'
           New-Item -ItemType Directory -Path (Join-Path $stageRoot 'apm-packages') -Force | Out-Null
           Copy-DirectoryContents $packageRoot $stagePackage
           Copy-DirectoryContents (Join-Path $repoRoot 'apm-packages\adaptive-implementation-execution') $stageAdaptive
            Copy-DirectoryContents (Join-Path $repoRoot 'apm-packages\codex-profile-finalizer') $stageFinalizer
            $stageAdaptiveAgents = Join-Path $stageAdaptive '.apm\agents'
            New-Item -ItemType Directory -Path $stageAdaptiveAgents -Force | Out-Null
            foreach ($adaptiveAgent in @('high-implementation-starter.agent.md', 'standard-implementation-completer.agent.md')) {
                Copy-Item -LiteralPath (Join-Path $repoRoot "apm-packages\adaptive-implementation-execution\.apm\agents\$adaptiveAgent") -Destination (Join-Path $stageAdaptiveAgents $adaptiveAgent) -Force
            }

           $stageAdaptiveResolved = (Resolve-Path -LiteralPath $stageAdaptive).Path
           $stagePackageResolved = (Resolve-Path -LiteralPath $stagePackage).Path
            $stageFinalizerResolved = (Resolve-Path -LiteralPath $stageFinalizer).Path
            $adaptiveManifest = @"
name: adaptive-implementation-execution
version: 0.5.0
description: Adaptive serial implementation routing from ordinary Plans or completed post-map Design Pair handoffs through high-model non-local decision closure and standard-model implementation ownership
type: hybrid
targets:
  - copilot
  - codex
  - agent-skills
includes: auto

dependencies:
  apm:
    - path: $stageFinalizerResolved
"@
            [System.IO.File]::WriteAllText((Join-Path $stageAdaptiveResolved 'apm.yml'), $adaptiveManifest.Replace("`r`n", "`n"))

            $packageManifest = @"
name: plan-coverage-residual-flow
version: 0.14.0
description: Plan Coverage Check and Residual Decision Flow with durable Design Pair waiting state, full-coverage Slice Living Records, Architecture Slice Readiness, Guardrail Focus, and residual decision gating
type: hybrid
targets:
  - copilot
  - codex
  - agent-skills
includes: auto

dependencies:
  apm:
    - path: $stageAdaptiveResolved
"@
            [System.IO.File]::WriteAllText((Join-Path $stagePackageResolved 'apm.yml'), $packageManifest.Replace("`r`n", "`n"))

            $installArguments = @('install', $stagePackageResolved, '--target', 'copilot,codex,agent-skills')
        }
        else {
            $source = "$Repository/apm-packages/plan-coverage-residual-flow#$Ref"
            $installArguments = @('install', $source, '--target', 'copilot,codex,agent-skills', '--https')
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
    $canonicalSharedPath = Join-Path $repoRoot 'apm-packages/plan-coverage-residual-flow/.apm/instructions/plan-coverage-shared.instructions.md'
    $installedSharedPath = Join-Path $tempRoot '.github/instructions/plan-coverage-shared.instructions.md'
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
    if (-not (Test-Path -LiteralPath $installedSharedPath -PathType Leaf)) {
        throw 'Fresh APM install did not deploy the Plan Coverage shared instruction.'
    }
    if ((Get-NormalizedText $canonicalSharedPath) -cne (Get-NormalizedText $installedSharedPath)) {
        throw 'Fresh APM installed shared instruction differs from the canonical package instruction.'
    }

    $canonicalSkillRoot = Join-Path $repoRoot 'apm-packages/plan-coverage-residual-flow/.apm/skills/plan-coverage-residual-flow'
    $installedSkillRoot = Join-Path $tempRoot '.agents/skills/plan-coverage-residual-flow'
    $canonicalSkillFiles = @(Get-ChildItem -LiteralPath $canonicalSkillRoot -Recurse -File | Sort-Object FullName)
    foreach ($canonicalFile in $canonicalSkillFiles) {
        $relative = $canonicalFile.FullName.Substring($canonicalSkillRoot.Length).TrimStart('\', '/')
        $installedFile = Join-Path $installedSkillRoot $relative
        if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf)) {
            throw "Fresh APM install missing Skill file: $relative"
        }
        if ((Get-NormalizedText $canonicalFile.FullName) -cne (Get-NormalizedText $installedFile)) {
            throw "Fresh APM installed Skill file differs from canonical: $relative"
        }
    }

    foreach ($agentName in $planCoverageOwnedAgentNames) {
        $canonicalAgentPath = Join-Path $repoRoot "apm-packages/plan-coverage-residual-flow/.apm/agents/$agentName.agent.md"
        $installedCopilotPath = Join-Path $tempRoot ".github/agents/$agentName.agent.md"

        if (-not (Test-Path -LiteralPath $installedCopilotPath -PathType Leaf)) {
            throw "Fresh APM install missing Copilot agent projection: $agentName"
        }
        if ((Get-NormalizedText $canonicalAgentPath) -cne (Get-NormalizedText $installedCopilotPath)) {
            throw "Fresh Copilot agent projection differs from canonical: $agentName"
        }
    }

    $finalizer = @(Get-ChildItem -LiteralPath (Join-Path $tempRoot 'apm_modules') -Recurse -File -Filter 'finalize-codex-agent-profiles.cs' | Select-Object -First 1).FullName
    if ([string]::IsNullOrWhiteSpace($finalizer) -or -not (Test-Path -LiteralPath $finalizer -PathType Leaf)) {
        throw 'Fresh Plan Coverage install did not deploy the transitive Codex profile finalizer.'
    }
    Invoke-Native 'dotnet' @('run', '--file', $finalizer, '--', $tempRoot) 'Plan Coverage Codex profile finalizer'
    Invoke-Native 'dotnet' @('run', '--file', $finalizer, '--', $tempRoot, '--check') 'Plan Coverage Codex profile check'

    $adaptiveRequired = @(
        '.agents/skills/adaptive-implementation-execution/SKILL.md',
        '.github/agents/high-implementation-starter.agent.md',
        '.github/agents/standard-implementation-completer.agent.md',
        '.codex/agents/high-implementation-starter.toml',
        '.codex/agents/standard-implementation-completer.toml'
    )
    foreach ($relativePath in $adaptiveRequired) {
        if (-not (Test-Path -LiteralPath (Join-Path $tempRoot $relativePath) -PathType Leaf)) {
            throw "Fresh Plan Coverage install did not deploy Adaptive asset transitively: $relativePath"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        $lock = Get-NormalizedText $lockPath
        $lockBlock = [regex]::Match($lock, '(?ms)^- .*?name: plan-coverage-residual-flow\n(?<block>.*?)(?=^- |\z)')
        if (-not $lockBlock.Success) {
            throw 'Fresh APM lock does not contain the Plan Coverage package.'
        }

        $block = $lockBlock.Groups['block'].Value
        if ($block -cnotmatch '(?m)^  version:\s*0\.14\.0\s*$') {
            throw 'Fresh APM lock does not contain Plan Coverage package version 0.14.0.'
        }

        $installedHash = Get-NormalizedTextSha256 $installedSkillPath
        if ($block -cnotmatch "(?m)^    \.agents/skills/plan-coverage-residual-flow/SKILL\.md: sha256:$installedHash\s*$") {
            throw 'Fresh APM lock deployed Skill hash does not match the installed file.'
        }

        $standaloneE2EPath = Join-Path $packageRoot 'scripts/validate-plan-coverage-full-coverage-e2e.ps1'
        & $standaloneE2EPath -InstalledRoot $tempRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Installed Plan Coverage standalone E2E failed with exit code $LASTEXITCODE."
        }
    }

    Write-Host 'Plan Coverage Residual Flow APM install smoke: PASS'
}
finally {
    if ($stageRoot) {
        $resolvedStageRoot = [System.IO.Path]::GetFullPath($stageRoot)
        if ($resolvedStageRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedStageRoot).StartsWith('plan-coverage-residual-flow-stage-', [StringComparison]::Ordinal)) {
            Remove-Item -LiteralPath $resolvedStageRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    if ($resolvedTempRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTempRoot).StartsWith('plan-coverage-residual-flow-smoke-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
