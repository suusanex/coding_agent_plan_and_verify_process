# Agent Plugins互換artifactの生成・検証で共有するhelper。
# process semanticsは読み取るだけで、package sourceへ生成物を書き戻さない。

$script:AgentPluginContractVersion = 1
$script:AgentPluginsSchemaId = 'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json'
$script:AgentPluginsSchemaFixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../tests/agent-plugins/plugin.schema.1.0.0.json'))
$script:AgentPluginContractSchemaFixture = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../tests/agent-plugins/contract.schema.json'))
$script:AgentPluginsAllowedTopLevel = @(
    '$schema', 'name', 'version', 'description', 'author', 'homepage',
    'repository', 'license', 'keywords', 'extensions'
)

function Get-AgentPluginNormalizedText([string]$Path) {
    return [IO.File]::ReadAllText($Path).Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-AgentPluginSha256Bytes([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-AgentPluginSha256Text([string]$Text) {
    return Get-AgentPluginSha256Bytes ([Text.UTF8Encoding]::new($false).GetBytes($Text))
}

function Get-AgentPluginRawFileHash([string]$Path) {
    return Get-AgentPluginSha256Bytes ([IO.File]::ReadAllBytes($Path))
}

function Get-AgentPluginCanonicalFingerprint([string]$CanonicalRoot) {
    $builder = [Text.StringBuilder]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $CanonicalRoot -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($CanonicalRoot.Length).TrimStart('\', '/').Replace('\', '/')
        $content = Get-AgentPluginNormalizedText $file.FullName
        [void]$builder.Append($relative).Append("`n").Append($content)
        if (-not $content.EndsWith("`n")) { [void]$builder.Append("`n") }
        [void]$builder.Append("`n")
    }
    return Get-AgentPluginSha256Text $builder.ToString()
}

function Get-AgentPluginDistributionFingerprint([string]$PackageRoot) {
    $resolvedPackage = (Resolve-Path -LiteralPath $PackageRoot).Path
    $paths = [Collections.Generic.List[string]]::new()
    $paths.Add('apm.yml') | Out-Null
    $paths.Add('tests/agent-plugin/contract.json') | Out-Null
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $resolvedPackage '.apm') -Recurse -File | Sort-Object FullName)) {
        $paths.Add((Get-AgentPluginRelativePath $resolvedPackage $file.FullName)) | Out-Null
    }

    $builder = [Text.StringBuilder]::new()
    foreach ($relative in @($paths | Sort-Object)) {
        $path = Join-Path $resolvedPackage $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing distribution input: $relative" }
        $content = Get-AgentPluginNormalizedText $path
        [void]$builder.Append($relative.Replace('\', '/')).Append("`n").Append($content)
        if (-not $content.EndsWith("`n")) { [void]$builder.Append("`n") }
        [void]$builder.Append("`n")
    }
    return Get-AgentPluginSha256Text $builder.ToString()
}

function Get-AgentPluginRelativePath([string]$Root, [string]$Path) {
    return $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-AgentPluginFileInventory([string]$Root, [switch]$RawBytes) {
    $inventory = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)) {
        $relative = Get-AgentPluginRelativePath $Root $file.FullName
        $inventory[$relative] = if ($RawBytes) { Get-AgentPluginRawFileHash $file.FullName } else { Get-AgentPluginSha256Text (Get-AgentPluginNormalizedText $file.FullName) }
    }
    return $inventory
}

function Copy-AgentPluginDirectory([string]$Source, [string]$Destination) {
    $null = New-Item -ItemType Directory -Path $Destination -Force
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $Destination $item.Name) -Recurse -Force
    }
}

function Get-AgentPluginManifestScalar([string]$ManifestPath, [string]$Name) {
    $text = Get-Content -Raw -LiteralPath $ManifestPath
    if ($text -notmatch "(?m)^$([regex]::Escape($Name)):\s*(.+?)\s*$") { throw "Missing manifest field: $Name" }
    return $Matches[1].Trim().Trim('"', "'")
}

function Get-AgentPluginManifestTargets([string]$ManifestPath) {
    $lines = Get-Content -LiteralPath $ManifestPath
    $targets = [Collections.Generic.List[string]]::new()
    $inside = $false
    foreach ($line in $lines) {
        if ($line -match '^targets:\s*$') { $inside = $true; continue }
        if ($inside -and $line -match '^\s+-\s+(.+?)\s*$') { $targets.Add($Matches[1].Trim()) | Out-Null; continue }
        if ($inside -and $line -match '^\S') { break }
    }
    return @($targets)
}

function Get-AgentPluginManifestDependencies([string]$ManifestPath) {
    $dependencies = [Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        if ($line -match '^\s+path:\s*apm-packages/([^/\s]+)\s*$') { $dependencies.Add($Matches[1]) | Out-Null }
    }
    return @($dependencies)
}

function Write-AgentPluginManifest([string]$Path, [string]$ManifestPath) {
    $manifest = [ordered]@{
        '$schema' = $script:AgentPluginsSchemaId
        name = Get-AgentPluginManifestScalar $ManifestPath 'name'
        version = Get-AgentPluginManifestScalar $ManifestPath 'version'
        description = Get-AgentPluginManifestScalar $ManifestPath 'description'
    }
    $json = $manifest | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Get-AgentPluginJsonSchemaFailures([string]$JsonPath, [string]$Context) {
    $failures = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $script:AgentPluginsSchemaFixture -PathType Leaf)) {
        $failures.Add("$Context schema fixture is missing: $script:AgentPluginsSchemaFixture") | Out-Null
        return $failures
    }
    try {
        $schema = Get-Content -Raw -LiteralPath $script:AgentPluginsSchemaFixture | ConvertFrom-Json
        if ([string]$schema.'$id' -cne $script:AgentPluginsSchemaId) { $failures.Add("$Context schema fixture `$id mismatch") | Out-Null }
        if ($schema.additionalProperties -ne $false) { $failures.Add("$Context schema fixture must be closed") | Out-Null }
        $valid = Test-Json -LiteralPath $JsonPath -SchemaFile $script:AgentPluginsSchemaFixture -ErrorAction Stop
        if (-not $valid) { $failures.Add("$Context does not conform to Agent Plugins v1 JSON Schema") | Out-Null }
    }
    catch {
        Write-Host "TRACE: $($_.Exception.ToString())"
        $failures.Add("$Context JSON Schema validation failed: $($_.Exception.Message)") | Out-Null
    }
    return $failures
}

function Get-AgentPluginContract([string]$PackageRoot) {
    $path = Join-Path $PackageRoot 'tests/agent-plugin/contract.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Agent Plugin contract: $path" }
    if (-not (Test-Path -LiteralPath $script:AgentPluginContractSchemaFixture -PathType Leaf)) { throw "Missing Agent Plugin contract schema: $script:AgentPluginContractSchemaFixture" }
    try {
        $valid = Test-Json -LiteralPath $path -SchemaFile $script:AgentPluginContractSchemaFixture -ErrorAction Stop
        if (-not $valid) { throw 'Agent Plugin contract does not conform to its JSON Schema.' }
    }
    catch {
        Write-Host "TRACE: $($_.Exception.ToString())"
        throw "Agent Plugin contract JSON Schema validation failed: $($_.Exception.Message)"
    }
    $contract = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    if ([int]$contract.schemaVersion -ne $script:AgentPluginContractVersion) { throw "Unsupported Agent Plugin contract version: $($contract.schemaVersion)" }
    $required = @('package','installTargets','ownedSkills','ownedAgents','ownedInstructions','dependencies','runtimeBoundary')
    foreach ($name in $required) {
        if ($contract.PSObject.Properties.Name -notcontains $name) { throw "Agent Plugin contract missing field: $name" }
    }
    $allowed = @('schemaVersion') + $required
    foreach ($name in $contract.PSObject.Properties.Name) {
        if ($allowed -notcontains $name) { throw "Agent Plugin contract contains unsupported field: $name" }
    }
    if ([string]::IsNullOrWhiteSpace([string]$contract.package) -or [string]::IsNullOrWhiteSpace([string]$contract.runtimeBoundary)) { throw 'Agent Plugin contract contains an empty scalar.' }
    if (@($contract.ownedSkills).Count -eq 0) { throw 'Agent Plugin contract must own at least one Skill.' }
    return $contract
}

function Test-AgentPluginPathEscape([string]$Root, [string]$RelativePath) {
    if ($RelativePath -match '(^|/|\\)\.\.(/|\\|$)' -or [IO.Path]::IsPathRooted($RelativePath)) { return $true }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)))
    return -not $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Get-AgentPluginReparsePoints([string]$Root) {
    return @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint } | ForEach-Object { Get-AgentPluginRelativePath $Root $_.FullName })
}

function Get-AgentPluginSourceGuardFailures([string]$PackageRoot) {
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($relative in @('plugin.json', 'skills', 'agents', 'instructions', '.agents', '.codex', '.github/agents', '.github/instructions')) {
        if (Test-Path -LiteralPath (Join-Path $PackageRoot $relative)) { $failures.Add("Generated or duplicate runtime surface exists at package root: $relative") | Out-Null }
    }
    return $failures
}

function Invoke-AgentPluginBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageRoot,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [string]$ApmExecutable = 'apm'
    )

    $resolvedPackage = (Resolve-Path -LiteralPath $PackageRoot).Path
    $canonicalRoot = Join-Path $resolvedPackage '.apm'
    $manifestPath = Join-Path $resolvedPackage 'apm.yml'
    if (-not (Test-Path -LiteralPath $canonicalRoot -PathType Container)) { throw "Missing canonical root: $canonicalRoot" }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing apm.yml: $manifestPath" }
    $guardFailures = Get-AgentPluginSourceGuardFailures $resolvedPackage
    if ($guardFailures.Count -gt 0) { throw ($guardFailures -join "`n") }

    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $stageRoot = Join-Path $tempRoot ('agent-plugin-pack-' + [guid]::NewGuid().ToString('N'))
    $safeToDelete = $false
    try {
        Copy-AgentPluginDirectory $resolvedPackage $stageRoot
        $resolvedStage = (Resolve-Path -LiteralPath $stageRoot).Path
        if (-not $resolvedStage.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe pack stage: $resolvedStage" }
        $safeToDelete = $true
        $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
        $preliminaryOutput = Join-Path $resolvedStage '.pack-preliminary'
        $lockConsumer = Join-Path $resolvedStage '.pack-lock-consumer'
        $null = New-Item -ItemType Directory -Path $preliminaryOutput -Force
        $null = New-Item -ItemType Directory -Path $lockConsumer -Force
        Write-AgentPluginManifest -Path (Join-Path $resolvedStage 'plugin.json') -ManifestPath $manifestPath

        # APM自身でpackage-owned lockを生成する。最初のpackをlocal bundleとして
        # installし、そのlockを二回目のpackへ渡すことで独自lock実装を避ける。
        Push-Location -LiteralPath $resolvedStage
        try {
            $log = & $ApmExecutable @('pack', '--format', 'plugin', '--output', $preliminaryOutput, '--force') 2>&1
            if ($LASTEXITCODE -ne 0) { throw "apm pack failed with exit code $LASTEXITCODE`n$(($log | ForEach-Object { [string]$_ }) -join "`n")" }
        }
        finally { Pop-Location }

        $name = Get-AgentPluginManifestScalar $manifestPath 'name'
        $version = Get-AgentPluginManifestScalar $manifestPath 'version'
        $preliminaryBundle = Join-Path $preliminaryOutput "$name-$version"
        Push-Location -LiteralPath $lockConsumer
        try {
            $installLog = & $ApmExecutable @('install', $preliminaryBundle) 2>&1
            if ($LASTEXITCODE -ne 0) { throw "apm install for pack lock failed with exit code $LASTEXITCODE`n$(($installLog | ForEach-Object { [string]$_ }) -join "`n")" }
        }
        finally { Pop-Location }
        $seedLock = Join-Path $lockConsumer 'apm.lock.yaml'
        if (-not (Test-Path -LiteralPath $seedLock -PathType Leaf)) { throw 'APM did not create the pack seed lock.' }
        Copy-Item -LiteralPath $seedLock -Destination (Join-Path $resolvedStage 'apm.lock.yaml') -Force

        Push-Location -LiteralPath $resolvedStage
        try {
            $finalLog = & $ApmExecutable @('pack', '--format', 'plugin', '--output', $OutputDirectory, '--force') 2>&1
            if ($LASTEXITCODE -ne 0) { throw "final apm pack failed with exit code $LASTEXITCODE`n$(($finalLog | ForEach-Object { [string]$_ }) -join "`n")" }
        }
        finally { Pop-Location }

        $bundleRoot = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) "$name-$version"
        if (-not (Test-Path -LiteralPath $bundleRoot -PathType Container)) { throw "Packed bundle not found: $bundleRoot" }
        return [pscustomobject]@{
            package = $name
            version = $version
            bundleRoot = $bundleRoot
            canonicalFingerprint = Get-AgentPluginCanonicalFingerprint $canonicalRoot
            apmVersion = ((& $ApmExecutable --version 2>&1 | Out-String).Trim())
            bundleFiles = Get-AgentPluginFileInventory $bundleRoot
        }
    }
    finally {
        if ($safeToDelete -and (Test-Path -LiteralPath $stageRoot)) {
            $resolved = [IO.Path]::GetFullPath($stageRoot)
            if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove unsafe stage: $resolved" }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

function Get-AgentPluginLockInventory([string]$LockPath) {
    $inventory = @{}
    $inside = $false
    foreach ($line in ((Get-AgentPluginNormalizedText $LockPath) -split "`n")) {
        if ($line -match '^\s*bundle_files:\s*$') { $inside = $true; continue }
        if ($inside -and $line -match '^\S') { break }
        if ($inside -and $line -match '^\s+([^:]+):\s*([a-f0-9]{64})\s*$') { $inventory[$Matches[1].Trim()] = $Matches[2] }
    }
    return $inventory
}

function Get-AgentPluginBundleFailures([string]$PackageRoot, [string]$BundleRoot) {
    $failures = [Collections.Generic.List[string]]::new()
    $manifestPath = Join-Path $PackageRoot 'apm.yml'
    $pluginPath = Join-Path $BundleRoot 'plugin.json'
    $lockPath = Join-Path $BundleRoot 'apm.lock.yaml'
    if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) { $failures.Add('Bundle missing plugin.json') | Out-Null; return $failures }
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { $failures.Add('Bundle missing apm.lock.yaml') | Out-Null; return $failures }

    try { $plugin = Get-Content -Raw -LiteralPath $pluginPath | ConvertFrom-Json }
    catch {
        Write-Host "TRACE: $($_.Exception.ToString())"
        $failures.Add("Invalid plugin.json: $($_.Exception.Message)") | Out-Null
        return $failures
    }
    foreach ($failure in Get-AgentPluginJsonSchemaFailures $pluginPath 'plugin.json') { $failures.Add($failure) | Out-Null }
    foreach ($required in @('name', 'version', 'description')) {
        if ($plugin.PSObject.Properties.Name -notcontains $required -or [string]::IsNullOrWhiteSpace([string]$plugin.$required)) { $failures.Add("plugin.json missing $required") | Out-Null }
    }
    foreach ($property in $plugin.PSObject.Properties.Name) {
        if ($script:AgentPluginsAllowedTopLevel -notcontains $property) { $failures.Add("plugin.json contains unsupported field: $property") | Out-Null }
    }
    if ([string]$plugin.name -cne (Get-AgentPluginManifestScalar $manifestPath 'name')) { $failures.Add('plugin name differs from apm.yml') | Out-Null }
    if ([string]$plugin.version -cne (Get-AgentPluginManifestScalar $manifestPath 'version')) { $failures.Add('plugin version differs from apm.yml') | Out-Null }
    if ([string]$plugin.description -cne (Get-AgentPluginManifestScalar $manifestPath 'description')) { $failures.Add('plugin description differs from apm.yml') | Out-Null }

    $actual = Get-AgentPluginFileInventory $BundleRoot -RawBytes
    foreach ($relative in $actual.Keys) {
        if (Test-AgentPluginPathEscape $BundleRoot $relative) { $failures.Add("Bundle path escapes containment: $relative") | Out-Null }
    }
    foreach ($point in Get-AgentPluginReparsePoints $BundleRoot) { $failures.Add("Bundle contains reparse point: $point") | Out-Null }

    $canonicalRoot = Join-Path $PackageRoot '.apm'
    foreach ($surface in @('skills', 'agents', 'instructions')) {
        $sourceRoot = Join-Path $canonicalRoot $surface
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { continue }
        $sourceInventory = Get-AgentPluginFileInventory $sourceRoot
        $bundleSurface = Join-Path $BundleRoot $surface
        if (-not (Test-Path -LiteralPath $bundleSurface -PathType Container)) { $failures.Add("Bundle missing canonical surface: $surface") | Out-Null; continue }
        $bundleInventory = Get-AgentPluginFileInventory $bundleSurface
        foreach ($relative in $sourceInventory.Keys) {
            if (-not $bundleInventory.Contains($relative)) { $failures.Add("Bundle missing canonical $surface file: $relative") | Out-Null }
            elseif ($sourceInventory[$relative] -cne $bundleInventory[$relative]) { $failures.Add("Canonical drift in $surface/$relative") | Out-Null }
        }
        foreach ($relative in $bundleInventory.Keys) {
            if (-not $sourceInventory.Contains($relative)) { $failures.Add("Unexpected bundle $surface file: $relative") | Out-Null }
        }
    }

    $lock = Get-AgentPluginLockInventory $lockPath
    if ($lock.Count -eq 0) { $failures.Add('Embedded lock has no bundle_files inventory') | Out-Null }
    foreach ($relative in $actual.Keys) {
        if ($relative -eq 'apm.lock.yaml') { continue }
        if (-not $lock.ContainsKey($relative)) { $failures.Add("Bundle file missing from lock: $relative") | Out-Null }
        elseif ($actual[$relative] -cne $lock[$relative]) { $failures.Add("Lock hash mismatch: $relative") | Out-Null }
    }
    foreach ($relative in $lock.Keys) {
        if (-not $actual.Contains($relative)) { $failures.Add("Lock lists missing bundle file: $relative") | Out-Null }
    }
    return $failures
}
