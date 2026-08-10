# Shared helpers for Agent Plugins PoC build/validate (Issue #107).
# Dot-source only. Does not change Plan Coverage process semantics.
# plugin.json is NOT a checked-in package-root artifact; pack stage synthesizes it.

$script:PlanCoverageAgentPluginCommonVersion = 2

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

$script:AdaptiveRequiredLockMarkers = @(
    'adaptive-implementation-execution/SKILL.md',
    'high-implementation-starter.agent.md',
    'standard-implementation-completer.agent.md'
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
$script:DefaultPluginRepository = 'https://github.com/suusanex/coding_agent_plan_and_verify_process'

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

function New-ApPluginManifestObject {
    param([Parameter(Mandatory = $true)]$PackageMeta)
    return [ordered]@{
        '$schema'    = $script:AgentPluginsV1SchemaId
        name         = [string]$PackageMeta.name
        version      = [string]$PackageMeta.version
        description  = [string]$PackageMeta.description
        repository   = $script:DefaultPluginRepository
    }
}

function Write-ApPluginManifestJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$PackageMeta
    )
    $obj = New-ApPluginManifestObject -PackageMeta $PackageMeta
    $json = ($obj | ConvertTo-Json -Depth 8)
    # Stable LF, trailing newline
    Write-ApUtf8File $Path (($json.Replace("`r`n", "`n").TrimEnd() + "`n"))
}

function Resolve-ApAdaptiveAgentSources([string]$RepoRoot) {
    $packageAgents = Join-Path $RepoRoot 'apm-packages/adaptive-implementation-execution/.apm/agents'
    $names = @('high-implementation-starter.agent.md', 'standard-implementation-completer.agent.md')
    $resolved = @()
    foreach ($name in $names) {
        $pkgPath = Join-Path $packageAgents $name
        if (-not (Test-Path -LiteralPath $pkgPath -PathType Leaf)) {
            throw "Adaptive agent missing from package-owned canonical source (post-#111): $pkgPath"
        }
        $resolved += [pscustomobject]@{ Name = $name; Path = $pkgPath; Source = 'package-canonical' }
    }
    return $resolved
}

function Test-ApAdaptiveAttestedInLock([string]$LockPath) {
    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        throw "Lock path missing for Adaptive attestation: $LockPath"
    }
    $text = Get-ApNormalizedText $LockPath
    $missing = @()
    foreach ($marker in $script:AdaptiveRequiredLockMarkers) {
        if ($text -notmatch [regex]::Escape($marker)) {
            $missing += $marker
        }
    }
    # Prefer deployed_files section presence for Adaptive package entry.
    $hasAdaptivePackage = $text -match '(?m)^  name:\s*adaptive-implementation-execution\s*$' -or
        $text -match 'adaptive-implementation-execution'
    $hasDeployed = $text -match 'deployed_files:' -and $text -match 'deployed_file_hashes:'
    return [pscustomobject]@{
        Ok                = ($missing.Count -eq 0 -and $hasAdaptivePackage -and $hasDeployed)
        MissingMarkers    = $missing
        HasAdaptiveEntry  = [bool]$hasAdaptivePackage
        HasDeployedFiles  = [bool]$hasDeployed
        LockSha256        = (Get-ApSha256File $LockPath)
        LockPath          = $LockPath
    }
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

    # Source tree must not carry plugin.json; strip if a stale copy sneaks in.
    $stalePlugin = Join-Path $stagePackage 'plugin.json'
    if (Test-Path -LiteralPath $stalePlugin -PathType Leaf) {
        Remove-Item -LiteralPath $stalePlugin -Force
    }

    $adaptiveAgents = @(Resolve-ApAdaptiveAgentSources $RepoRoot)
    foreach ($agent in $adaptiveAgents) {
        $dest = Join-Path $stageAdaptive ".apm\agents\$($agent.Name)"
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item -LiteralPath $agent.Path -Destination $dest -Force
        }
    }

    $stageAdaptiveResolved = (Resolve-Path -LiteralPath $stageAdaptive).Path
    $stagePackageResolved = (Resolve-Path -LiteralPath $stagePackage).Path
    $adaptiveVersion = Get-ApPackageField -ManifestPath (Join-Path $RepoRoot 'apm-packages\adaptive-implementation-execution\apm.yml') -Field version
    $packageMeta = Get-ApYamlScalarMap (Join-Path $PackageRoot 'apm.yml')

    # Adaptive is self-contained post-#111; keep standalone manifest for path install.
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

dependencies:
  apm: []
"@
    Write-ApUtf8File (Join-Path $stageAdaptiveResolved 'apm.yml') ($adaptiveManifest.Replace("`r`n", "`n"))

    # Install-stage package: source layout (.apm), NO plugin.json, path dep on Adaptive.
    $installPackage = Join-Path $StageRoot 'install-package'
    Copy-ApDirectoryContents $stagePackageResolved $installPackage
    $installPlugin = Join-Path $installPackage 'plugin.json'
    if (Test-Path -LiteralPath $installPlugin -PathType Leaf) {
        Remove-Item -LiteralPath $installPlugin -Force
    }
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
    Write-ApUtf8File (Join-Path $installPackage 'apm.yml') ($installManifest.Replace("`r`n", "`n"))

    # Pack-stage package: original git:parent apm.yml + synthesized plugin.json only (no root source plugin.json).
    Copy-Item -LiteralPath (Join-Path $PackageRoot 'apm.yml') -Destination (Join-Path $stagePackageResolved 'apm.yml') -Force
    Write-ApPluginManifestJson -Path (Join-Path $stagePackageResolved 'plugin.json') -PackageMeta $packageMeta

    # Pack-lock seed package: package-owned only (no Adaptive path dep) so apm pack can embed lock.
    $packLockSeed = Join-Path $StageRoot 'pack-lock-seed'
    Copy-ApDirectoryContents $stagePackageResolved $packLockSeed
    $seedMeta = $packageMeta
    $seedManifest = @"
name: $($seedMeta.name)
version: $($seedMeta.version)
description: $($seedMeta.description)
type: hybrid
targets:
  - copilot
  - codex
  - agent-skills
includes: auto
"@
    Write-ApUtf8File (Join-Path $packLockSeed 'apm.yml') ($seedManifest.Replace("`r`n", "`n"))
    Write-ApPluginManifestJson -Path (Join-Path $packLockSeed 'plugin.json') -PackageMeta $seedMeta

    return [pscustomobject]@{
        StageRoot              = $StageRoot
        PackPackageRoot        = $stagePackageResolved
        InstallPackageRoot     = (Resolve-Path -LiteralPath $installPackage).Path
        PackLockSeedRoot       = (Resolve-Path -LiteralPath $packLockSeed).Path
        AdaptivePackageRoot    = $stageAdaptiveResolved
        AdaptiveAgentSources   = $adaptiveAgents
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
            throw "apm install (Adaptive lock attestation) failed with exit code $LASTEXITCODE`n$tail"
        }
        $lockPath = Join-Path $ConsumerRoot 'apm.lock.yaml'
        if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
            throw 'apm install did not produce apm.lock.yaml for Adaptive attestation.'
        }
        return , $lockPath
    }
    finally {
        Pop-Location
    }
}

function Invoke-ApPackLockSeed {
    param(
        [Parameter(Mandatory = $true)][string]$PackLockSeedRoot,
        [Parameter(Mandatory = $true)][string]$SeedConsumerRoot
    )
    New-Item -ItemType Directory -Path $SeedConsumerRoot -Force | Out-Null
    Push-Location $SeedConsumerRoot
    try {
        # With plugin.json present, APM treats this as a local plugin bundle and emits pack-embeddable lock.
        $log = & apm @('install', $PackLockSeedRoot) 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($log | ForEach-Object { [string]$_ }) -join "`n"
            throw "apm install (pack lock seed) failed with exit code $LASTEXITCODE`n$tail"
        }
        $lockPath = Join-Path $SeedConsumerRoot 'apm.lock.yaml'
        if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
            throw 'Pack lock seed install did not produce apm.lock.yaml.'
        }
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

function Get-ApGitCandidateCommit([string]$RepoRoot, [switch]$AllowDirty) {
    $sha = ((& git -C $RepoRoot rev-parse HEAD 2>$null | Out-String).Trim())
    if ([string]::IsNullOrWhiteSpace($sha)) {
        return 'UNOBSERVABLE'
    }
    if ($sha -notmatch '^[a-f0-9]{40}$') {
        # allow abbreviated only when not requiring clean evidence
        if (-not $AllowDirty -and $sha -notmatch '^[a-f0-9]{7,40}$') {
            throw "Unexpected git SHA: $sha"
        }
    }
    $dirty = @(& git -C $RepoRoot status --porcelain 2>$null)
    if ($dirty.Count -gt 0) {
        if (-not $AllowDirty) {
            throw 'Working tree is dirty. Qualifying PoC evidence requires a clean commit (no -dirty candidate_commit).'
        }
        return "$sha-dirty"
    }
    if ($sha -match '^[a-f0-9]{40}$') {
        return $sha
    }
    # expand to full sha
    $full = ((& git -C $RepoRoot rev-parse HEAD 2>$null | Out-String).Trim())
    return $full
}
