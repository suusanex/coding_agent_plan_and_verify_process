[CmdletBinding()]
param(
    [string]$OutputDir,
    [switch]$Archive,
    [switch]$KeepStage,
    [switch]$Force,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'PlanCoverageAgentPlugin.Common.ps1')

$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Get-ApRepoRootFromPackage $packageRoot
$canonicalRoot = Join-Path $packageRoot '.apm'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'
$pluginJsonPath = Join-Path $packageRoot 'plugin.json'

if (-not (Test-Path -LiteralPath $pluginJsonPath -PathType Leaf)) {
    throw "plugin.json missing at package root: $pluginJsonPath"
}

$packageMeta = Get-ApYamlScalarMap $apmYmlPath
$pluginObj = Get-Content -Raw -LiteralPath $pluginJsonPath | ConvertFrom-Json
if ([string]$pluginObj.name -cne [string]$packageMeta.name) {
    throw "plugin.json name drifts from apm.yml (plugin=$($pluginObj.name) apm=$($packageMeta.name))"
}
if ([string]$pluginObj.version -cne [string]$packageMeta.version) {
    throw "plugin.json version drifts from apm.yml (plugin=$($pluginObj.version) apm=$($packageMeta.version))"
}
if ([string]$pluginObj.description -cne [string]$packageMeta.description) {
    throw 'plugin.json description drifts from apm.yml'
}
if ([string]$pluginObj.'$schema' -cne $script:AgentPluginsV1SchemaId) {
    throw "plugin.json `$schema must be $script:AgentPluginsV1SchemaId"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-coverage-agent-plugin-out-' + [Guid]::NewGuid().ToString('N'))
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stage = $null
$consumerRoot = $null
$bundleRoot = $null
$archivePath = $null

try {
    Write-Host 'Staging package + Adaptive dependency for lock attestation...'
    $stage = New-ApDependencyStage -PackageRoot $packageRoot -RepoRoot $repoRoot
    $consumerRoot = Join-Path $stage.StageRoot 'consumer'
    Write-Host 'Running staged apm install to attest dependency lock...'
    $consumerLock = [string](Invoke-ApConsumerInstallForLock -InstallPackageRoot $stage.InstallPackageRoot -ConsumerRoot $consumerRoot)
    if (-not (Test-Path -LiteralPath $consumerLock -PathType Leaf)) {
        throw "Lock attestation did not return a lock file path (got: $consumerLock)"
    }

    # Seed pack source with attested lock so apm pack embeds/enriches apm.lock.yaml.
    # Pack source keeps original git:parent apm.yml (local path deps are rejected by apm pack).
    Copy-Item -LiteralPath $consumerLock -Destination (Join-Path $stage.PackPackageRoot 'apm.lock.yaml') -Force

    $packArgs = @('pack', '--format', 'plugin', '-o', $OutputDir)
    if ($Force) { $packArgs += '--force' }
    if ($Archive) {
        $packArgs += @('--archive', '--archive-format', 'zip')
    }

    Write-Host "Running apm pack (target-neutral plugin format) in stage..."
    Push-Location $stage.PackPackageRoot
    try {
        $packLog = & apm @packArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tail = ($packLog | ForEach-Object { [string]$_ }) -join "`n"
            throw "apm pack failed with exit code $LASTEXITCODE`n$tail"
        }
        else {
            ($packLog | ForEach-Object { [string]$_ }) | ForEach-Object { Write-Host $_ }
        }
    }
    finally {
        Pop-Location
    }

    $expectedBundleName = "$($packageMeta.name)-$($packageMeta.version)"
    $bundleRoot = Join-Path $OutputDir $expectedBundleName
    if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) {
        $dirs = @(Get-ChildItem -LiteralPath $OutputDir -Directory -ErrorAction SilentlyContinue)
        if ($dirs.Count -eq 1) {
            $bundleRoot = $dirs[0].FullName
        }
        else {
            throw "Packed bundle directory not found under $OutputDir"
        }
    }

    if ($Archive) {
        $archivePath = Join-Path $OutputDir ($expectedBundleName + '.zip')
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            $zips = @(Get-ChildItem -LiteralPath $OutputDir -Filter '*.zip' -File -ErrorAction SilentlyContinue)
            if ($zips.Count -ge 1) { $archivePath = $zips[0].FullName } else { $archivePath = $null }
        }
    }

    $canonicalFingerprint = Get-ApCanonicalFingerprint $canonicalRoot
    $pluginManifestSha = Get-ApSha256File (Join-Path $bundleRoot 'plugin.json')
    $bundleLockPath = Join-Path $bundleRoot 'apm.lock.yaml'
    if (-not (Test-Path -LiteralPath $bundleLockPath -PathType Leaf)) {
        throw 'apm pack did not embed apm.lock.yaml in the plugin bundle.'
    }
    $bundleLockSha = Get-ApSha256File $bundleLockPath
    $inventory = Get-ApBundleFileInventory $bundleRoot
    $apmVersion = ((& apm --version 2>&1 | Out-String).Trim())
    $candidateCommit = ((& git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim())
    $dirty = ((& git -C $repoRoot status --porcelain 2>$null | Out-String).Trim())
    if (-not [string]::IsNullOrWhiteSpace($dirty)) {
        $candidateCommit = "$candidateCommit-dirty"
    }

    $result = [ordered]@{
        ok                     = $true
        package_name           = $packageMeta.name
        package_version        = $packageMeta.version
        bundle_root            = $bundleRoot
        archive_path           = $archivePath
        output_dir             = $OutputDir
        canonical_fingerprint  = $canonicalFingerprint
        plugin_manifest_sha256 = $pluginManifestSha
        bundle_lock_sha256     = $bundleLockSha
        apm_yml_sha256         = (Get-ApSha256File $apmYmlPath)
        source_plugin_json_sha256 = (Get-ApSha256File $pluginJsonPath)
        apm_version            = $apmVersion
        candidate_commit       = $candidateCommit
        file_count             = @($inventory.Keys).Count
        files                  = $inventory
        adaptive_agent_sources = @($stage.AdaptiveAgentSources | ForEach-Object { "$($_.Source):$($_.Name)" })
        notes                  = @(
            'Bundle generated via apm pack --format plugin (target-neutral).',
            'Lock attested via staged apm install with Adaptive path dependency, then embedded by pack.',
            'Adaptive transitive Skill/agents are not inlined into this pack output under APM 0.26.0; Adaptive remains a separate package boundary / APM projection concern.',
            'Source tree was not used as pack cwd; staging avoids dirtying package .github/plugin/.'
        )
    }

    $manifestPath = Join-Path $OutputDir 'build-manifest.json'
    Write-ApUtf8File $manifestPath (ConvertTo-ApJson $result)

    if ($Json) {
        Write-Output (ConvertTo-ApJson $result)
    }
    else {
        Write-Host "bundle_root=$bundleRoot"
        Write-Host "package_version=$($packageMeta.version)"
        Write-Host "canonical_fingerprint=$canonicalFingerprint"
        Write-Host "plugin_manifest_sha256=$pluginManifestSha"
        Write-Host "bundle_lock_sha256=$bundleLockSha"
        Write-Host "file_count=$(@($inventory.Keys).Count)"
        Write-Host "build_manifest=$manifestPath"
        if ($archivePath) { Write-Host "archive_path=$archivePath" }
    }

    # Return path for callers that capture output objects.
    return $result
}
finally {
    if (-not $KeepStage) {
        if ($stage -and $stage.StageRoot) {
            $resolved = [System.IO.Path]::GetFullPath($stage.StageRoot)
            if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        if ($stage) {
            Write-Host "Kept stage: $($stage.StageRoot)"
        }
    }
}
