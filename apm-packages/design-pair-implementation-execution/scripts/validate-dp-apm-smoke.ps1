[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repository,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Ref,

    [string]$ApmExecutable = 'apm'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

function Assert-File([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing ${Description}: $Path"
    }
}

function Assert-Contains([string]$Path, [string]$Pattern, [string]$Description) {
    Assert-File $Path $Description
    if ((Get-Content -Raw -LiteralPath $Path) -notmatch $Pattern) {
        throw "$Description does not contain the required contract: $Path"
    }
}

# APM 0.26.0 is required for multi-target Design Pair install smoke.
$null = & $ApmExecutable --version
if ($LASTEXITCODE -ne 0) {
    throw 'APM 0.26.0 is required but apm was not found on PATH.'
}

$scratch = Join-Path ([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())) ('dp-apm-smoke-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
    Push-Location $scratch
    try {
        $source = "$Repository/apm-packages/design-pair-implementation-execution#$Ref"
        Invoke-Native $ApmExecutable @('install', $source, '--target', 'copilot,codex,agent-skills', '--https') 'Design Pair remote APM install'
    }
    finally {
        Pop-Location
    }

    $designPairSkill = Join-Path $scratch '.agents/skills/design-pair-implementation-execution/SKILL.md'
    $designPairMap = Join-Path $scratch '.agents/skills/design-pair-implementation-execution/map.md'
    $designPairHandoff = Join-Path $scratch '.agents/skills/design-pair-implementation-execution/handoff.md'
    Assert-File $designPairSkill 'Design Pair Skill'
    Assert-File $designPairMap 'Design Pair Target Map reference'
    Assert-File $designPairHandoff 'Design Pair handoff reference'
    Assert-Contains $designPairSkill '(?m)^name:\s*design-pair-implementation-execution\s*$' 'deployed Design Pair skill name'
    Assert-Contains $designPairSkill 'implementation_route:\s*design-pair' 'deployed Design Pair route metadata'

    $adaptiveSkill = Join-Path $scratch '.agents/skills/adaptive-implementation-execution/SKILL.md'
    Assert-File $adaptiveSkill 'transitive Adaptive Skill'
    Assert-Contains $adaptiveSkill '(?m)^disable-model-invocation:\s*true\s*$' 'transitive Adaptive skill explicit-only invocation'

    $copilotHigh = Join-Path $scratch '.github/agents/high-implementation-starter.agent.md'
    $copilotStandard = Join-Path $scratch '.github/agents/standard-implementation-completer.agent.md'
    Assert-File $copilotHigh 'transitive Copilot HIGH agent'
    Assert-File $copilotStandard 'transitive Copilot STANDARD agent'
    Assert-Contains $copilotHigh '(?m)^model:\s*GPT-5\.6 Terra \(copilot\)\s*$' 'transitive Copilot HIGH model'
    Assert-Contains $copilotHigh '(?m)^disable-model-invocation:\s*true\s*$' 'transitive Copilot HIGH explicit-only invocation'
    Assert-Contains $copilotStandard '(?m)^model:\s*GPT-5\.6 Luna \(copilot\)\s*$' 'transitive Copilot STANDARD model'
    Assert-Contains $copilotStandard '(?m)^disable-model-invocation:\s*true\s*$' 'transitive Copilot STANDARD explicit-only invocation'

    $finalizer = @(Get-ChildItem -LiteralPath (Join-Path $scratch 'apm_modules') -Recurse -File -Filter 'finalize-codex-agent-profiles.cs' | Select-Object -First 1).FullName
    Assert-File $finalizer 'installed Codex profile finalizer'
    Invoke-Native 'dotnet' @('run', '--file', $finalizer, '--', $scratch) 'Codex profile completion'
    Invoke-Native 'dotnet' @('run', '--file', $finalizer, '--', $scratch, '--check') 'Codex profile check'
    $codexHigh = Join-Path $scratch '.codex/agents/high-implementation-starter.toml'
    $codexStandard = Join-Path $scratch '.codex/agents/standard-implementation-completer.toml'
    Assert-File $codexHigh 'transitive Codex HIGH profile'
    Assert-File $codexStandard 'transitive Codex STANDARD profile'
    Assert-Contains $codexHigh '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$' 'Codex HIGH model'
    Assert-Contains $codexStandard '(?m)^model\s*=\s*"gpt-5\.6-luna"\s*$' 'Codex STANDARD model'

    $lockPath = Join-Path $scratch 'apm.lock.yaml'
    Assert-File $lockPath 'remote APM lock'
    $lock = Get-Content -Raw -LiteralPath $lockPath
    $designPairBlock = [regex]::Match($lock.Replace("`r`n", "`n"), '(?ms)^- .*?name: design-pair-implementation-execution\n(?<block>.*?)(?=^- |\z)')
    # design-pair-implementation-execution 0.3.1 lock entry
    if (-not $designPairBlock.Success -or $designPairBlock.Groups['block'].Value -cnotmatch '(?m)^  version:\s*0\.3\.1\s*$') {
        throw 'Remote APM lock does not contain Design Pair package version 0.3.1.'
    }
    $adaptiveBlock = [regex]::Match($lock.Replace("`r`n", "`n"), '(?ms)^- .*?name: adaptive-implementation-execution\n(?<block>.*?)(?=^- |\z)')
    # adaptive-implementation-execution 0.5.0 transitive lock entry
    if (-not $adaptiveBlock.Success -or $adaptiveBlock.Groups['block'].Value -cnotmatch '(?m)^  version:\s*0\.5\.0\s*$') {
        throw 'Remote APM lock does not contain transitive Adaptive package version 0.5.0.'
    }

    Write-Host 'Design Pair APM install smoke: PASS'
}
finally {
    $resolved = [System.IO.Path]::GetFullPath($scratch)
    if ($resolved.StartsWith([System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('dp-apm-smoke-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
