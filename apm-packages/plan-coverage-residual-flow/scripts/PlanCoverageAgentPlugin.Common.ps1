# Shared helpers for Agent Plugins PoC build/validate (Issue #107).
# Dot-source only. Does not change Plan Coverage process semantics.

$script:PlanCoverageAgentPluginCommonVersion = 1

$script:PlanCoverageOwnedAgentNames = @(
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

$script:AgentPluginsV1SchemaId = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
$script:AgentPluginsV1AllowedTopLevel = @(
    '$schema',
    'name',
    'version',
    'description',
    'author',
    'homepage',
    'repository',
    'license',
    'keywords',
    'extensions'
)

function Get-ApNormalizedText([string]$Path) {
    return [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-ApSha256Bytes([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ApSha256Text([string]$Text) {
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    return Get-ApSha256Bytes $bytes
}

function Get-ApSha256File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return Get-ApSha256Text (Get-ApNormalizedText $Path)
}

function Get-ApRawSha256File([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return Get-ApSha256Bytes $bytes
}

function Get-ApCanonicalFingerprint([string]$Root) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object {
            $_.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        })
    $builder = [System.Text.StringBuilder]::new()
    foreach ($file in $files) {
        $rel = $file.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
        $content = Get-ApNormalizedText $file.FullName
        [void]$builder.Append($rel)
        [void]$builder.Append("`n")
        [void]$builder.Append($content)
        if (-not $content.EndsWith("`n")) {
            [void]$builder.Append("`n")
        }
        [void]$builder.Append("`n")
    }
    return Get-ApSha256Text $builder.ToString()
}

function Write-ApUtf8File([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Copy-ApDirectoryContents([string]$Source, [string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    # Hidden / dot directories are not matched by '*' on Windows robocopy-less copy.
    Get-ChildItem -LiteralPath $Source -Force | Where-Object {
        $_.PSIsContainer -and $_.Name.StartsWith('.')
    } | ForEach-Object {
        $destChild = Join-Path $Destination $_.Name
        if (-not (Test-Path -LiteralPath $destChild)) {
            Copy-Item -LiteralPath $_.FullName -Destination $destChild -Recurse -Force
        }
    }
    Get-ChildItem -LiteralPath $Source -Force -File | Where-Object {
        $_.Name.StartsWith('.')
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Force
    }
}

function Get-ApPackageField {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][ValidateSet('name', 'version', 'description')][string]$Field
    )
    $text = Get-ApNormalizedText $ManifestPath
    $pattern = "(?m)^${Field}:\s*(.+?)\s*$"
    if ($text -cmatch $pattern) {
        return $Matches[1].Trim()
    }
    throw "Unable to read $Field from $ManifestPath"
}

function Get-ApYamlScalarMap([string]$ManifestPath) {
    return [ordered]@{
        name        = Get-ApPackageField -ManifestPath $ManifestPath -Field name
        version     = Get-ApPackageField -ManifestPath $ManifestPath -Field version
        description = Get-ApPackageField -ManifestPath $ManifestPath -Field description
    }
}

function Get-ApRepoRootFromPackage([string]$PackageRoot) {
    return (Resolve-Path (Join-Path $PackageRoot '../..')).Path
}

function Resolve-ApAdaptiveAgentSources([string]$RepoRoot) {
    $packageAgents = Join-Path $RepoRoot 'apm-packages/adaptive-implementation-execution/.apm/agents'
    $rootAgents = Join-Path $RepoRoot '.github/agents'
    $names = @('high-implementation-starter.agent.md', 'standard-implementation-completer.agent.md')
    $resolved = @()
    foreach ($name in $names) {
        $pkgPath = Join-Path $packageAgents $name
        $rootPath = Join-Path $rootAgents $name
        if (Test-Path -LiteralPath $pkgPath -PathType Leaf) {
            $resolved += [pscustomobject]@{ Name = $name; Path = $pkgPath; Source = 'package-canonical' }
        }
        elseif (Test-Path -LiteralPath $rootPath -PathType Leaf) {
            $resolved += [pscustomobject]@{ Name = $name; Path = $rootPath; Source = 'root-projection-fallback' }
        }
        else {
            throw "Adaptive agent not found in package canonical or root projection: $name"
        }
    }
    return $resolved
}

function New-ApDependencyStage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$StageRoot
    )

    $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ([string]::IsNullOrWhiteSpace($StageRoot)) {
        $StageRoot = Join-Path $tempParent ('plan-coverage-agent-plugin-stage-' + [Guid]::NewGuid().ToString('N'))
    }
    $stagePackage = Join-Path $StageRoot 'apm-packages\plan-coverage-residual-flow'
    $stageAdaptive = Join-Path $StageRoot 'apm-packages\adaptive-implementation-execution'
    New-Item -ItemType Directory -Path (Join-Path $StageRoot 'apm-packages') -Force | Out-Null
    Copy-ApDirectoryContents $PackageRoot $stagePackage
    Copy-ApDirectoryContents (Join-Path $RepoRoot 'apm-packages\adaptive-implementation-execution') $stageAdaptive

    $stageAdaptiveAgents = Join-Path $stageAdaptive '.apm\agents'
    New-Item -ItemType Directory -Path $stageAdaptiveAgents -Force | Out-Null
    foreach ($agent in @(Resolve-ApAdaptiveAgentSources $RepoRoot)) {
        Copy-Item -LiteralPath $agent.Path -Destination (Join-Path $stageAdaptiveAgents $agent.Name) -Force
    }

    $stageAdaptiveResolved = (Resolve-Path -LiteralPath $stageAdaptive).Path
    $stagePackageResolved = (Resolve-Path -LiteralPath $stagePackage).Path
    $adaptiveVersion = Get-ApPackageField -ManifestPath (Join-Path $RepoRoot 'apm-packages\adaptive-implementation-execution\apm.yml') -Field version
    $packageMeta = Get-ApYamlScalarMap (Join-Path $PackageRoot 'apm.yml')

    $adaptiveManifest = @"
name: adaptive-implementation-execution
version: $adaptiveVersion
description: Adaptive serial implementation routing from ordinary Plans or completed post-map Design Pair handoffs through high-model non-local decision closure and standard-model implementation ownership
type: hybrid
targets:
  - copilot
  - codex
  - agent-skills
includes: auto
"@
    Write-ApUtf8File (Join-Path $stageAdaptiveResolved 'apm.yml') ($adaptiveManifest.Replace("`r`n", "`n"))

    # Install-stage manifest uses absolute path deps (same pattern as APM smoke / #106).
    # Pack-stage keeps original git:parent apm.yml — local path deps are rejected by apm pack.
    $installManifest = @"
name: $($packageMeta.name)
version: $($packageMeta.version)
description: $($packageMeta.description)
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
    $installPackage = Join-Path $StageRoot 'install-package'
    Copy-ApDirectoryContents $stagePackageResolved $installPackage
    Write-ApUtf8File (Join-Path $installPackage 'apm.yml') ($installManifest.Replace("`r`n", "`n"))
    # Lock-seed install keeps plugin.json so APM emits a pack-embeddable lock that does not
    # pin ephemeral local dependency paths (those break `apm pack`). Full multi-target source
    # install attestation remains validate-plan-coverage-residual-flow-apm-smoke.ps1 / #106.
    $sourcePluginJson = Join-Path $PackageRoot 'plugin.json'
    if (-not (Test-Path -LiteralPath $sourcePluginJson -PathType Leaf)) {
        throw "Missing package plugin.json at $sourcePluginJson"
    }
    Copy-Item -LiteralPath $sourcePluginJson -Destination (Join-Path $installPackage 'plugin.json') -Force

    # Ensure Agent Plugins manifest is present on pack source (from package root plugin.json).
    Copy-Item -LiteralPath $sourcePluginJson -Destination (Join-Path $stagePackageResolved 'plugin.json') -Force
    # Pack source must keep original apm.yml (git:parent), not path rewrite.
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'apm.yml') -Destination (Join-Path $stagePackageResolved 'apm.yml') -Force

    return [pscustomobject]@{
        StageRoot              = $StageRoot
        PackPackageRoot        = $stagePackageResolved
        InstallPackageRoot     = (Resolve-Path -LiteralPath $installPackage).Path
        AdaptivePackageRoot    = $stageAdaptiveResolved
        AdaptiveAgentSources   = @(Resolve-ApAdaptiveAgentSources $RepoRoot)
        PackageMeta            = $packageMeta
    }
}

function Invoke-ApConsumerInstallForLock {
    param(
        [Parameter(Mandatory = $true)][string]$InstallPackageRoot,
        [Parameter(Mandatory = $true)][string]$ConsumerRoot
    )
    New-Item -ItemType Directory -Path $ConsumerRoot -Force | Out-Null
    Push-Location $ConsumerRoot
    try {
        $installLog = & apm @('install', $InstallPackageRoot, '--target', 'copilot,codex,agent-skills') 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($installLog | ForEach-Object { [string]$_ }) -join "`n"
            throw "apm install (lock attestation) failed with exit code $LASTEXITCODE`n$tail"
        }
        $lockPath = Join-Path $ConsumerRoot 'apm.lock.yaml'
        if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
            throw 'apm install did not produce apm.lock.yaml for lock attestation.'
        }
        # Emit path only via return; never leak apm stdout into the caller's assignment.
        return , $lockPath
    }
    finally {
        Pop-Location
    }
}

function Get-ApRelativeUnixPath([string]$Root, [string]$FullPath) {
    return $FullPath.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-ApBundleFileInventory([string]$BundleRoot, [switch]$RawBytes) {
    $files = @(Get-ChildItem -LiteralPath $BundleRoot -Recurse -File | Sort-Object {
            Get-ApRelativeUnixPath $BundleRoot $_.FullName
        })
    $inventory = [ordered]@{}
    foreach ($file in $files) {
        $rel = Get-ApRelativeUnixPath $BundleRoot $file.FullName
        if ($RawBytes) {
            $inventory[$rel] = Get-ApRawSha256File $file.FullName
        }
        else {
            $inventory[$rel] = Get-ApSha256File $file.FullName
        }
    }
    return $inventory
}

function Test-ApPathEscape([string]$BundleRoot, [string]$RelativePath) {
    if ($RelativePath -match '(^|/|\\)\.\.(/|\\|$)') { return $true }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $true }
    $combined = [System.IO.Path]::GetFullPath((Join-Path $BundleRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
    $rootFull = [System.IO.Path]::GetFullPath($BundleRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return -not $combined.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ApReparsePointUnder([string]$Root) {
    $hits = @()
    Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            $hits += (Get-ApRelativeUnixPath $Root $_.FullName)
        }
    }
    return $hits
}

function ConvertTo-ApJson($Object) {
    return ($Object | ConvertTo-Json -Depth 100)
}
