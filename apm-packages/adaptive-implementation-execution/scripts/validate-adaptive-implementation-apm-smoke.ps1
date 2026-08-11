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

function Invoke-NativeCapture([string]$FilePath, [string[]]$Arguments, [string]$Description) {
    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) {
        Write-Host $line
    }
    if ($exitCode -ne 0) {
        throw "$Description failed with exit code $exitCode."
    }
    return ($output | Out-String)
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

function Assert-NotContains([string]$Path, [string]$Pattern, [string]$Description) {
    Assert-File $Path $Description
    if ((Get-Content -Raw -LiteralPath $Path) -match $Pattern) {
        throw "$Description contains a forbidden contract: $Path"
    }
}

function Get-Hashes([string[]]$Paths) {
    $result = @{}
    foreach ($path in $Paths) {
        Assert-File $path 'no-op hash input'
        $result[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    }
    return $result
}

function Assert-Hashes([hashtable]$Expected) {
    foreach ($path in $Expected.Keys) {
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
        if ($actual -ne $Expected[$path]) {
            throw "Reinstall changed package-managed content: $path"
        }
    }
}

$apmVersion = & $ApmExecutable --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "APM executable failed: $ApmExecutable"
}
if ($apmVersion -notmatch '\b0\.26\.0\b') {
    throw "APM 0.26.0 is required for the reproducible smoke. Observed: $($apmVersion.Trim())"
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$scratch = [System.IO.Path]::GetFullPath((Join-Path $tempRoot ("adaptive-apm-smoke-" + [guid]::NewGuid().ToString('N'))))
$collision = [System.IO.Path]::GetFullPath((Join-Path $tempRoot ("adaptive-apm-collision-" + [guid]::NewGuid().ToString('N'))))
foreach ($path in @($scratch, $collision)) {
    if (-not $path.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe scratch path: $path"
    }
}

$previousPythonUtf8 = $env:PYTHONUTF8
$previousPythonIoEncoding = $env:PYTHONIOENCODING
$packageSpec = "$Repository/apm-packages/adaptive-implementation-execution#$Ref"

try {
    $env:PYTHONUTF8 = '1'
    $env:PYTHONIOENCODING = 'utf-8'
    New-Item -ItemType Directory -Path (Join-Path $scratch '.codex') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $scratch 'AGENTS.md') -Value 'sentinel-agents'
    Set-Content -LiteralPath (Join-Path $scratch '.codex/config.toml') -Value 'sentinel-config'
    $agentsHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch 'AGENTS.md')).Hash
    $configHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch '.codex/config.toml')).Hash

    Push-Location $scratch
    try {
        $installOutput = Invoke-NativeCapture $ApmExecutable @('install', $packageSpec, '--target', 'copilot,codex,agent-skills', '--https') 'remote APM install'
        if ($installOutput -match '(?i)lossy agent compilation warnings|frontmatter field[^\r\n]*dropped|may inherit all project/session MCP servers') {
            throw 'Remote APM install reported lossy agent compilation. Canonical agents must compile without dropped frontmatter.'
        }
    }
    finally {
        Pop-Location
    }

    $skillRoot = Join-Path $scratch '.agents/skills/adaptive-implementation-execution'
    foreach ($relative in @('SKILL.md', 'refs/intent.md', 'refs/handoff.md')) {
        Assert-File (Join-Path $skillRoot $relative) "deployed Skill asset $relative"
    }
    $lockPath = Join-Path $scratch 'apm.lock.yaml'
    Assert-File $lockPath 'remote APM lock'
    $lock = Get-Content -Raw -LiteralPath $lockPath
    $lockBlock = [regex]::Match($lock.Replace("`r`n", "`n"), '(?ms)^- .*?name: adaptive-implementation-execution\n(?<block>.*?)(?=^- |\z)')
    if (-not $lockBlock.Success -or $lockBlock.Groups['block'].Value -cnotmatch '(?m)^  version:\s*0\.5\.0\s*$') {
        throw 'Remote APM lock does not contain Adaptive package version 0.5.0.'
    }
    $deployedSkill = Join-Path $skillRoot 'SKILL.md'
    Assert-Contains $deployedSkill '(?m)^disable-model-invocation:\s*true\s*$' 'deployed skill explicit-only model invocation'
    Assert-Contains $deployedSkill '(?m)^user-invocable:\s*true\s*$' 'deployed skill remains user-invocable'
    Assert-Contains $deployedSkill 'Do not select for ordinary implement-this-plan requests' 'deployed skill rejects plain implementation requests'
    Assert-Contains $deployedSkill 'do not select from natural-language mentions' 'deployed skill rejects natural-language name mentions'
    Assert-Contains $deployedSkill '/adaptive-implementation-execution' 'deployed skill documents slash invocation'
    Assert-NotContains $deployedSkill 'or when the task clearly requires' 'deployed skill has no task-requires auto-selection description'
    Assert-NotContains $deployedSkill '\$adaptive-implementation-execution' 'deployed skill has no dollar-prefix invocation example'
    Assert-Contains $deployedSkill 'Delegation basis: non-local-decisions-closed' 'deployed skill decision-closure delegation basis'
    Assert-Contains $deployedSkill 'HIGH_MODEL code changes: Yes / No' 'deployed skill zero-code HIGH state'
    Assert-Contains $deployedSkill 'Responsibility、Authorized surface、Expected behavior、Locked boundaries、Local freedom、Completion check' 'deployed skill Work Package schema'

    $copilotHigh = Join-Path $scratch '.github/agents/high-implementation-starter.agent.md'
    $copilotStandard = Join-Path $scratch '.github/agents/standard-implementation-completer.agent.md'
    Assert-NotContains $copilotHigh '(?m)^tools:' 'Copilot HIGH explicit tools frontmatter'
    Assert-Contains $copilotHigh '(?m)^model:\s*GPT-5\.6 Terra \(copilot\)\s*$' 'Copilot HIGH model'
    Assert-Contains $copilotHigh '(?m)^target:\s*vscode\s*$' 'Copilot HIGH target'
    Assert-Contains $copilotHigh '(?m)^disable-model-invocation:\s*true\s*$' 'Copilot HIGH explicit-only invocation'
    Assert-Contains $copilotHigh 'agent:\s*standard-implementation-completer' 'Copilot bounded completion handoff'
    Assert-Contains $copilotHigh 'Delegation basis.*non-local-decisions-closed' 'Copilot HIGH zero-code decision closure'
    Assert-NotContains $copilotStandard '(?m)^tools:' 'Copilot STANDARD explicit tools frontmatter'
    Assert-Contains $copilotStandard '(?m)^model:\s*GPT-5\.6 Luna \(copilot\)\s*$' 'Copilot STANDARD model'
    Assert-Contains $copilotStandard '(?m)^target:\s*vscode\s*$' 'Copilot STANDARD target'
    Assert-Contains $copilotStandard '(?m)^disable-model-invocation:\s*true\s*$' 'Copilot STANDARD explicit-only invocation'
    Assert-Contains $copilotStandard 'agent:\s*high-implementation-starter' 'Copilot HIGH re-entry handoff'
    Assert-Contains $copilotStandard 'locked済みsignatureと配置を持つclass/interface' 'Copilot STANDARD locked class implementation ownership'
    Assert-Contains $copilotStandard 'DI / factory / entrypoint wiringの実コード作成' 'Copilot STANDARD locked wiring ownership'

    $codexHigh = Join-Path $scratch '.codex/agents/high-implementation-starter.toml'
    $codexStandard = Join-Path $scratch '.codex/agents/standard-implementation-completer.toml'
    $managedPaths = @(
        (Join-Path $skillRoot 'SKILL.md'),
        $copilotHigh,
        $copilotStandard,
        $codexHigh,
        $codexStandard
    )
    $beforeReinstall = Get-Hashes $managedPaths
    Push-Location $scratch
    try {
        Invoke-Native $ApmExecutable @('install', '--frozen') 'idempotent APM reinstall'
    }
    finally {
        Pop-Location
    }
    Assert-Hashes $beforeReinstall

    $finalizer = @(Get-ChildItem -LiteralPath (Join-Path $scratch 'apm_modules') -Recurse -File -Filter 'finalize-codex-agent-profiles.cs' | Select-Object -First 1).FullName
    Assert-File $finalizer 'installed Codex profile finalizer'
    Invoke-Native 'dotnet' @('run', '--file', $finalizer, '--', $scratch) 'Codex profile completion'
    Invoke-Native 'dotnet' @('run', '--file', $finalizer, '--', $scratch, '--check') 'Codex profile check'
    Assert-Contains $codexHigh '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$' 'Codex HIGH model'
    Assert-Contains $codexStandard '(?m)^model\s*=\s*"gpt-5\.6-luna"\s*$' 'Codex STANDARD model'
    Assert-Contains $codexHigh 'non-local-decisions-closed' 'Codex HIGH decision-closure delegation basis'
    Assert-Contains $codexStandard 'method bodyのアルゴリズム' 'Codex STANDARD local implementation autonomy'

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch 'AGENTS.md')).Hash -ne $agentsHash) {
        throw 'Remote APM install or Codex finalizer changed AGENTS.md.'
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $scratch '.codex/config.toml')).Hash -ne $configHash) {
        throw 'Remote APM install or Codex finalizer changed .codex/config.toml.'
    }

    $collisionAgentDir = Join-Path $collision '.github/agents'
    New-Item -ItemType Directory -Path $collisionAgentDir -Force | Out-Null
    $customHigh = Join-Path $collisionAgentDir 'high-implementation-starter.agent.md'
    Set-Content -LiteralPath $customHigh -Value 'USER_CUSTOM_HIGH_AGENT'
    $customHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $customHigh).Hash
    Push-Location $collision
    try {
        Invoke-Native $ApmExecutable @('install', $packageSpec, '--target', 'copilot', '--https') 'collision-protection APM install'
    }
    finally {
        Pop-Location
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $customHigh).Hash -ne $customHash) {
        throw 'APM overwrote an existing unmanaged Copilot custom agent without --force.'
    }
    Assert-File (Join-Path $collisionAgentDir 'standard-implementation-completer.agent.md') 'non-conflicting Copilot STANDARD agent'

    $global:LASTEXITCODE = 0
    Write-Output 'Adaptive Implementation remote APM smoke: PASS'
    Write-Output "Package: $packageSpec"
    Write-Output "APM: $($apmVersion.Trim())"
}
finally {
    if ($null -eq $previousPythonUtf8) { Remove-Item Env:PYTHONUTF8 -ErrorAction SilentlyContinue } else { $env:PYTHONUTF8 = $previousPythonUtf8 }
    if ($null -eq $previousPythonIoEncoding) { Remove-Item Env:PYTHONIOENCODING -ErrorAction SilentlyContinue } else { $env:PYTHONIOENCODING = $previousPythonIoEncoding }
    foreach ($path in @($scratch, $collision)) {
        if (Test-Path -LiteralPath $path) {
            $resolved = [System.IO.Path]::GetFullPath($path)
            if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unsafe scratch path: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
