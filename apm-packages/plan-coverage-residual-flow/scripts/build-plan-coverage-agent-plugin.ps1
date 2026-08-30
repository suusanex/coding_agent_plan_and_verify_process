[CmdletBinding()]
param(
    [string]$OutputDir,
    [switch]$Archive,
    [switch]$KeepStage,
    [switch]$Force,
    [switch]$Json,
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'PlanCoverageAgentPlugin.Common.ps1')

$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Get-ApRepoRootFromPackage $packageRoot
$canonicalRoot = Join-Path $packageRoot '.apm'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'

# Source package must remain an APM source package (no checked-in plugin.json).
$sourcePluginJson = Join-Path $packageRoot 'plugin.json'
if (Test-Path -LiteralPath $sourcePluginJson -PathType Leaf) {
    throw "Checked-in package root plugin.json is forbidden (APM local-source vs plugin-bundle ambiguity). Found: $sourcePluginJson"
}

$packageMeta = Get-ApYamlScalarMap $apmYmlPath

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path ([System.IO.Path]::GetTempPath()) ('plan-coverage-agent-plugin-out-' + [Guid]::NewGuid().ToString('N'))
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$stage = $null

try {
    Write-Host 'Staging Plan Coverage + Adaptive (source layout, no root plugin.json)...'
    $stage = New-ApDependencyStage -PackageRoot $packageRoot -RepoRoot $repoRoot

    # --- Adaptive attestation lock (source install, path dep, no plugin.json) ---
    $attestationConsumer = Join-Path $stage.StageRoot 'attestation-consumer'
    Write-Host 'Running staged source apm install to attest Adaptive deployed_files/hashes...'
    $attestationLock = [string](Invoke-ApConsumerInstallForLock -InstallPackageRoot $stage.InstallPackageRoot -ConsumerRoot $attestationConsumer)
    $adaptiveAttestation = Test-ApAdaptiveAttestedInLock $attestationLock
    if (-not $adaptiveAttestation.Ok) {
        throw ("Adaptive lock attestation failed. missing=[{0}] hasAdaptive={1} hasDeployed={2}" -f `
            ($adaptiveAttestation.MissingMarkers -join ', '), `
            $adaptiveAttestation.HasAdaptiveEntry, `
            $adaptiveAttestation.HasDeployedFiles)
    }
    Write-Host "Adaptive attestation PASS (lock sha256=$($adaptiveAttestation.LockSha256))"
    $attestationLockCopy = Join-Path $OutputDir 'adaptive-attestation.lock.yaml'
    Copy-Item -LiteralPath $attestationLock -Destination $attestationLockCopy -Force

    # Prove local path deps cannot be packed (packaging boundary).
    $pathDepPackAttempt = [ordered]@{
        attempted = $true
        refused   = $false
        detail    = $null
    }
    $pathDepProbe = Join-Path $stage.StageRoot 'path-dep-pack-probe'
    Copy-ApDirectoryContents $stage.InstallPackageRoot $pathDepProbe
    Push-Location $pathDepProbe
    try {
        $probeLog = & apm @('pack', '--format', 'plugin', '-o', (Join-Path $stage.StageRoot 'path-dep-pack-out'), '--force') 2>&1
        $probeText = ($probeLog | ForEach-Object { [string]$_ }) -join "`n"
        if ($LASTEXITCODE -ne 0 -and $probeText -match 'local path dependency|Local dependencies are for development only') {
            $pathDepPackAttempt.refused = $true
            $pathDepPackAttempt.detail = 'apm pack refused local path dependency (expected).'
        }
        else {
            $pathDepPackAttempt.detail = "unexpected pack result exit=$LASTEXITCODE text=$probeText"
        }
    }
    finally {
        Pop-Location
    }
    if (-not $pathDepPackAttempt.refused) {
        throw "Expected apm pack to refuse local path dependencies; got: $($pathDepPackAttempt.detail)"
    }
    Write-Host 'Confirmed: apm pack refuses local path dependency (cannot pack Adaptive via path dep).'

    # --- Pack-embeddable lock seed (package-owned only; not Adaptive attestation lock) ---
    $seedConsumer = Join-Path $stage.StageRoot 'pack-lock-seed-consumer'
    Write-Host 'Seeding pack-embeddable lock from package-owned content only...'
    $seedLock = [string](Invoke-ApPackLockSeed -PackLockSeedRoot $stage.PackLockSeedRoot -SeedConsumerRoot $seedConsumer)
    Copy-Item -LiteralPath $seedLock -Destination (Join-Path $stage.PackPackageRoot 'apm.lock.yaml') -Force

    # Ensure pack source has synthesized plugin.json + original git:parent apm.yml
    Write-ApPluginManifestJson -Path (Join-Path $stage.PackPackageRoot 'plugin.json') -PackageMeta $packageMeta
    Copy-Item -LiteralPath $apmYmlPath -Destination (Join-Path $stage.PackPackageRoot 'apm.yml') -Force

    $packArgs = @('pack', '--format', 'plugin', '-o', $OutputDir)
    if ($Force) { $packArgs += '--force' }
    if ($Archive) {
        $packArgs += @('--archive', '--archive-format', 'zip')
    }

    Write-Host 'Running apm pack --format plugin (target-neutral) on pack stage...'
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
        $dirs = @(Get-ChildItem -LiteralPath $OutputDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'path-dep' })
        if ($dirs.Count -eq 1) {
            $bundleRoot = $dirs[0].FullName
        }
        else {
            throw "Packed bundle directory not found under $OutputDir"
        }
    }

    $archivePath = $null
    if ($Archive) {
        $archivePath = Join-Path $OutputDir ($expectedBundleName + '.zip')
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            $zips = @(Get-ChildItem -LiteralPath $OutputDir -Filter '*.zip' -File -ErrorAction SilentlyContinue)
            if ($zips.Count -ge 1) { $archivePath = $zips[0].FullName }
        }
    }

    # After pack with Adaptive-attested lock authority proven separately: bundle must not silently claim Adaptive.
    $adaptiveInBundle = (Test-Path -LiteralPath (Join-Path $bundleRoot 'skills/adaptive-implementation-execution/SKILL.md') -PathType Leaf)
    $decisionSurfaceOwnerInBundle = (Test-Path -LiteralPath (Join-Path $bundleRoot 'agents/decision-surface-implementation-owner.agent.md') -PathType Leaf)
    $boundedResidualOwnerInBundle = (Test-Path -LiteralPath (Join-Path $bundleRoot 'agents/bounded-residual-implementation-owner.agent.md') -PathType Leaf)

    # Optional: Adaptive package packs standalone (separate plugin artifact).
    $adaptiveBundleRoot = $null
    $adaptivePackOut = Join-Path $OutputDir 'adaptive-standalone-pack'
    New-Item -ItemType Directory -Path $adaptivePackOut -Force | Out-Null
    Push-Location $stage.AdaptivePackageRoot
    try {
        $adLog = & apm @('pack', '--format', 'plugin', '-o', $adaptivePackOut, '--force') 2>&1
        if ($LASTEXITCODE -eq 0) {
            $adaptiveBundleRoot = Join-Path $adaptivePackOut "adaptive-implementation-execution-$(Get-ApPackageField -ManifestPath (Join-Path $stage.AdaptivePackageRoot 'apm.yml') -Field version)"
            if (-not (Test-Path -LiteralPath $adaptiveBundleRoot)) {
                $d = @(Get-ChildItem $adaptivePackOut -Directory | Select-Object -First 1)
                if ($d) { $adaptiveBundleRoot = $d[0].FullName }
            }
        }
        else {
            Write-Host "WARNING: Adaptive standalone pack failed: $(($adLog | ForEach-Object { [string]$_ }) -join ' ')"
        }
    }
    finally {
        Pop-Location
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
    $candidateCommit = Get-ApGitCandidateCommit -RepoRoot $repoRoot -AllowDirty:$AllowDirty

    $result = [ordered]@{
        ok                        = $true
        package_name              = $packageMeta.name
        package_version           = $packageMeta.version
        bundle_root               = $bundleRoot
        archive_path              = $archivePath
        output_dir                = $OutputDir
        canonical_fingerprint     = $canonicalFingerprint
        plugin_manifest_sha256    = $pluginManifestSha
        bundle_lock_sha256        = $bundleLockSha
        apm_yml_sha256            = (Get-ApSha256File $apmYmlPath)
        apm_version               = $apmVersion
        candidate_commit          = $candidateCommit
        file_count                = @($inventory.Keys).Count
        files                     = $inventory
        source_plugin_json_checked_in = $false
        plugin_json_synthesis     = 'pack-stage-from-apm.yml'
        adaptive_attestation      = [ordered]@{
            status                    = 'PASS'
            lock_sha256               = $adaptiveAttestation.LockSha256
            lock_artifact             = $attestationLockCopy
            markers_required          = @($script:AdaptiveRequiredLockMarkers)
            markers_missing           = @($adaptiveAttestation.MissingMarkers)
            has_deployed_files_section = $adaptiveAttestation.HasDeployedFiles
            path_dep_pack_refused     = $pathDepPackAttempt.refused
            path_dep_pack_detail      = $pathDepPackAttempt.detail
            present_in_plan_coverage_bundle = [ordered]@{
                skill                  = $adaptiveInBundle
                decision_surface_owner = $decisionSurfaceOwnerInBundle
                bounded_residual_owner = $boundedResidualOwnerInBundle
            }
            standalone_adaptive_bundle_root = $adaptiveBundleRoot
            conclusion                = $(if (-not $adaptiveInBundle -and -not $decisionSurfaceOwnerInBundle -and -not $boundedResidualOwnerInBundle -and $pathDepPackAttempt.refused) {
                    'Adaptive Skill and semantic owner agents are attested in source-install lock deployed_files/hashes, but apm pack of Plan Coverage (git:parent / no local path dep) does not inline them into the plugin bundle; local path deps are refused by pack. Adaptive packs successfully as its own plugin bundle. APM dependency materialization or a separate Adaptive plugin remains required.'
                } else {
                    'Unexpected Adaptive pack composition — review build logs.'
                })
        }
        notes = @(
            'plugin.json is synthesized only in the temporary pack stage from apm.yml (not checked into package root).',
            'Adaptive attestation uses a real source-package apm install lock (no plugin.json), distinct from the pack-embeddable lock seed.',
            'Bundle generated via apm pack --format plugin (target-neutral).'
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
        Write-Host "adaptive_attested=true adaptive_in_bundle=$adaptiveInBundle"
        Write-Host "file_count=$(@($inventory.Keys).Count)"
        Write-Host "build_manifest=$manifestPath"
        if ($archivePath) { Write-Host "archive_path=$archivePath" }
        if ($adaptiveBundleRoot) { Write-Host "adaptive_standalone_bundle=$adaptiveBundleRoot" }
    }

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
