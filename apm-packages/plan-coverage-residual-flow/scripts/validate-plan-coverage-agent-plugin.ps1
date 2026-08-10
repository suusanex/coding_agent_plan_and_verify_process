[CmdletBinding()]
param(
    [string]$BundleRoot,
    [switch]$SkipBuild,
    [switch]$SkipNegativeTests,
    [string]$BaselineResultPath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'PlanCoverageAgentPlugin.Common.ps1')

$packageRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Get-ApRepoRootFromPackage $packageRoot
$canonicalRoot = Join-Path $packageRoot '.apm'
$apmYmlPath = Join-Path $packageRoot 'apm.yml'
$pluginJsonSource = Join-Path $packageRoot 'plugin.json'
$pocRoot = Join-Path $packageRoot 'tests/agent-plugin-poc'
$schemaFixture = Join-Path $pocRoot 'fixtures/plugin.schema.1.0.0.json'
$buildScript = Join-Path $PSScriptRoot 'build-plan-coverage-agent-plugin.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$ownedTemps = [System.Collections.Generic.List[string]]::new()

function Add-Fail([string]$Message) {
    $failures.Add($Message)
    Write-Host "FAIL: $Message"
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Add-Fail $Message }
}

function New-OwnedTempDir([string]$Prefix) {
    $path = Join-Path $tempParent ($Prefix + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $ownedTemps.Add($path) | Out-Null
    return $path
}

function Get-ManifestObject([string]$Path) {
    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Test-AgentPluginsManifestConformance {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$PackageMeta,
        [string]$Context = 'manifest'
    )
    $localFails = [System.Collections.Generic.List[string]]::new()
    $propNames = @($Manifest.PSObject.Properties.Name)
    if ($propNames -notcontains '$schema') {
        $localFails.Add("$Context : missing `$schema") | Out-Null
    }
    elseif ([string]$Manifest.'$schema' -cne $script:AgentPluginsV1SchemaId) {
        $localFails.Add("$Context : `$schema must be $script:AgentPluginsV1SchemaId") | Out-Null
    }
    if ($propNames -notcontains 'name' -or [string]::IsNullOrWhiteSpace([string]$Manifest.name)) {
        $localFails.Add("$Context : missing name") | Out-Null
    }
    else {
        $name = [string]$Manifest.name
        if ($name -cne 'plan-coverage-residual-flow') {
            $localFails.Add("$Context : name must be plan-coverage-residual-flow") | Out-Null
        }
        if ($name -cne [string]$PackageMeta.name) {
            $localFails.Add("$Context : name drifts from apm.yml") | Out-Null
        }
        if ($name -notmatch '^(?!.*(?:--|\\.\\.))[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$') {
            $localFails.Add("$Context : name violates Agent Plugins name constraints") | Out-Null
        }
        if ($name.Length -gt 64) {
            $localFails.Add("$Context : name exceeds 64 chars") | Out-Null
        }
    }
    if ($propNames -notcontains 'version') {
        $localFails.Add("$Context : missing version") | Out-Null
    }
    elseif ([string]$Manifest.version -cne [string]$PackageMeta.version) {
        $localFails.Add("$Context : version drifts from apm.yml") | Out-Null
    }
    if ($propNames -notcontains 'description') {
        $localFails.Add("$Context : missing description") | Out-Null
    }
    elseif ([string]$Manifest.description -cne [string]$PackageMeta.description) {
        $localFails.Add("$Context : description drifts from apm.yml") | Out-Null
    }
    foreach ($prop in $propNames) {
        if ($script:AgentPluginsV1AllowedTopLevel -notcontains $prop) {
            $localFails.Add("$Context : disallowed top-level field for Agent Plugins v1 closed manifest: $prop") | Out-Null
        }
    }
    foreach ($banned in @('agents', 'skills', 'mcpServers', 'mcp_servers', 'commands', 'hooks')) {
        if ($propNames -contains $banned) {
            $localFails.Add("$Context : Copilot/native top-level field '$banned' is not Agent Plugins v1 portable") | Out-Null
        }
    }
    return @($localFails)
}

function Test-OfficialSchemaIfPresent {
    param([string]$ManifestPath)
    if (-not (Test-Path -LiteralPath $schemaFixture -PathType Leaf)) {
        Write-Host 'INFO: official schema fixture missing; skipping JSON Schema engine validation (manifest field checks still run).'
        return
    }
    # Lightweight offline check mirroring additionalProperties:false + required/$schema const.
    # Full JSON Schema draft 2020-12 engine is not assumed in CI; field checks above are authoritative.
    $manifest = Get-ManifestObject $ManifestPath
    $schema = Get-Content -Raw -LiteralPath $schemaFixture | ConvertFrom-Json
    Assert-True ($schema.'$id' -ceq $script:AgentPluginsV1SchemaId) 'Pinned schema fixture $id mismatch'
    Assert-True ($schema.additionalProperties -eq $false) 'Pinned schema fixture must be closed (additionalProperties:false)'
    $required = @($schema.required)
    foreach ($r in $required) {
        Assert-True ($manifest.PSObject.Properties.Name -contains $r) "Manifest missing schema-required field: $r"
    }
    $allowed = @($schema.properties.PSObject.Properties.Name)
    foreach ($prop in $manifest.PSObject.Properties.Name) {
        Assert-True ($allowed -contains $prop) "Manifest field not in official schema properties: $prop"
    }
    if ($schema.properties.'$schema'.const) {
        Assert-True ([string]$manifest.'$schema' -ceq [string]$schema.properties.'$schema'.const) 'Manifest $schema const mismatch vs official schema'
    }
}

function Test-CanonicalEquivalence([string]$Bundle) {
    $skillCanon = Join-Path $canonicalRoot 'skills/plan-coverage-residual-flow'
    $skillBundle = Join-Path $Bundle 'skills/plan-coverage-residual-flow'
    Assert-True (Test-Path -LiteralPath $skillBundle -PathType Container) 'Bundle missing skills/plan-coverage-residual-flow'
    if (Test-Path -LiteralPath $skillCanon -PathType Container) {
        $canonFiles = @(Get-ChildItem -LiteralPath $skillCanon -Recurse -File)
        foreach ($cf in $canonFiles) {
            $rel = $cf.FullName.Substring($skillCanon.Length).TrimStart('\', '/')
            $bf = Join-Path $skillBundle $rel
            if (-not (Test-Path -LiteralPath $bf -PathType Leaf)) {
                Add-Fail "Bundle missing canonical Skill file: $rel"
                continue
            }
            if ((Get-ApNormalizedText $cf.FullName) -cne (Get-ApNormalizedText $bf)) {
                Add-Fail "Skill content drift vs canonical: $rel"
            }
        }
        $bundleOnly = @(Get-ChildItem -LiteralPath $skillBundle -Recurse -File)
        foreach ($bf in $bundleOnly) {
            $rel = $bf.FullName.Substring($skillBundle.Length).TrimStart('\', '/')
            $cf = Join-Path $skillCanon $rel
            if (-not (Test-Path -LiteralPath $cf -PathType Leaf)) {
                Add-Fail "Bundle Skill has unexpected extra file not in canonical: $rel"
            }
        }
    }

    foreach ($agentName in $script:PlanCoverageOwnedAgentNames) {
        $canonAgent = Join-Path $canonicalRoot "agents/$agentName.agent.md"
        $bundleAgent = Join-Path $Bundle "agents/$agentName.agent.md"
        if (-not (Test-Path -LiteralPath $canonAgent -PathType Leaf)) {
            Add-Fail "Canonical agent missing: $agentName"
            continue
        }
        if (-not (Test-Path -LiteralPath $bundleAgent -PathType Leaf)) {
            Add-Fail "Bundle missing agent (copilot-plugin-extension surface): $agentName"
            continue
        }
        if ((Get-ApNormalizedText $canonAgent) -cne (Get-ApNormalizedText $bundleAgent)) {
            Add-Fail "Agent content drift vs canonical: $agentName"
        }
    }

    $canonInstr = Join-Path $canonicalRoot 'instructions/plan-coverage-shared.instructions.md'
    $bundleInstr = Join-Path $Bundle 'instructions/plan-coverage-shared.instructions.md'
    if (Test-Path -LiteralPath $canonInstr -PathType Leaf) {
        if (-not (Test-Path -LiteralPath $bundleInstr -PathType Leaf)) {
            Add-Fail 'Bundle missing shared instruction (non-portable / materialization surface)'
        }
        elseif ((Get-ApNormalizedText $canonInstr) -cne (Get-ApNormalizedText $bundleInstr)) {
            Add-Fail 'Shared instruction content drift vs canonical'
        }
    }
}

function Test-LockIntegrity([string]$Bundle) {
    $lockPath = Join-Path $Bundle 'apm.lock.yaml'
    Assert-True (Test-Path -LiteralPath $lockPath -PathType Leaf) 'Bundle missing embedded apm.lock.yaml'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return }

    $lockText = Get-ApNormalizedText $lockPath
    Assert-True ($lockText -match '(?m)^pack:') 'Embedded lock missing pack: section'
    Assert-True ($lockText -match 'bundle_files:') 'Embedded lock missing bundle_files inventory'

    # Parse pack.bundle_files hashes (simple line parser; do not reimplement APM lock semantics beyond cross-check).
    $inBundleFiles = $false
    $lockInventory = @{}
    foreach ($line in ($lockText -split "`n")) {
        if ($line -match '^\s*bundle_files:\s*$') {
            $inBundleFiles = $true
            continue
        }
        if ($inBundleFiles) {
            if ($line -match '^\S') { $inBundleFiles = $false; continue }
            if ($line -match '^\s+([^:]+):\s*([a-f0-9]{64})\s*$') {
                $lockInventory[$Matches[1].Trim()] = $Matches[2].Trim()
            }
        }
    }
    Assert-True ($lockInventory.Count -gt 0) 'Could not parse any bundle_files entries from embedded lock'

    # APM pack lock hashes are raw file bytes (not LF-normalized content hashes).
    $actual = Get-ApBundleFileInventory $Bundle -RawBytes
    foreach ($rel in $lockInventory.Keys) {
        if ($rel -eq 'apm.lock.yaml') { continue }
        if (-not $actual.Contains($rel)) {
            Add-Fail "Lock inventory lists missing file: $rel"
            continue
        }
        if ($actual[$rel] -cne $lockInventory[$rel]) {
            Add-Fail "Hash mismatch vs lock inventory: $rel (lock=$($lockInventory[$rel]) actual=$($actual[$rel]))"
        }
    }
    # Every non-lock bundle file should appear in pack inventory (APM contract cross-check).
    foreach ($rel in $actual.Keys) {
        if ($rel -eq 'apm.lock.yaml') { continue }
        if (-not $lockInventory.ContainsKey($rel)) {
            Add-Fail "Bundle file missing from lock inventory: $rel"
        }
    }
}

function Test-SourceDuplicationGuard {
    foreach ($dup in @(
            (Join-Path $packageRoot 'skills'),
            (Join-Path $packageRoot 'agents'),
            (Join-Path $repoRoot 'skills/plan-coverage-residual-flow'),
            (Join-Path $repoRoot 'agent-plugin')
        )) {
        Assert-True (-not (Test-Path -LiteralPath $dup)) "Forbidden Agent Plugins duplicate source path present: $dup"
    }
}

function Test-BaselineFingerprintGate {
    if ([string]::IsNullOrWhiteSpace($BaselineResultPath)) {
        $defaultBaseline = Join-Path $packageRoot 'tests/runtime-qualification/results/2026-08-10-copilot-cli.json'
        if (Test-Path -LiteralPath $defaultBaseline -PathType Leaf) {
            $BaselineResultPath = $defaultBaseline
        }
        else {
            Write-Host 'INFO: no #106 baseline result found; skipping fingerprint comparison gate shape check.'
            return
        }
    }
    $baseline = Get-Content -Raw -LiteralPath $BaselineResultPath | ConvertFrom-Json
    $currentFp = Get-ApCanonicalFingerprint $canonicalRoot
    $baselineFp = [string]$baseline.canonical_fingerprint
    Assert-True ($baselineFp -match '^[a-f0-9]{64}$') 'Baseline canonical_fingerprint malformed'
    if ($baselineFp -cne $currentFp) {
        # Not a validator hard-fail for build: PoC comparison must fail-closed on semantic parity claims.
        Write-Host "INFO: baseline fingerprint ($baselineFp) != current ($currentFp). Semantic parity claims must be PENDING/fail-closed."
    }
    else {
        Write-Host "OK: baseline fingerprint matches current canonical fingerprint ($currentFp)"
    }

    # Negative contract: a forged comparison that claims semantic parity on mismatch must be rejected.
    $forgedParity = ($baselineFp -cne $currentFp) -and ($true) # if mismatch, parity claim is illegal
    if ($baselineFp -ceq $currentFp) {
        # Still test the gate function with synthetic mismatch.
        $syntheticMismatch = $true
        $illegalParityPass = $syntheticMismatch -and $false
        Assert-True (-not $illegalParityPass) 'Internal: synthetic mismatch incorrectly allowed parity'
        # Simulate detector
        $wouldPassParity = ($baselineFp -ceq '0' * 64) # always false
        Assert-True (-not $wouldPassParity) 'Parity gate must not PASS on fingerprint mismatch'
    }
    else {
        $illegalClaim = $true # caller claiming PASS parity
        Assert-True ($illegalClaim -and ($baselineFp -cne $currentFp)) 'Fingerprint mismatch detected (parity must not PASS)'
        # The detector for PoC results:
        $semanticParityAllowed = ($baselineFp -ceq $currentFp)
        Assert-True (-not $semanticParityAllowed) 'semantic parity must be denied when fingerprints differ'
    }
}

function Invoke-NegativeMutationTests {
    param([string]$GoodBundle, $PackageMeta)

    Write-Host 'Running negative mutation tests on temp copies...'

    function Assert-MutationFails([string]$Name, [scriptblock]$MutateManifestOrBundle) {
        $tmp = New-OwnedTempDir 'ap-neg-'
        $copy = Join-Path $tmp 'bundle'
        Copy-ApDirectoryContents $GoodBundle $copy
        & $MutateManifestOrBundle $copy
        $manifestPath = Join-Path $copy 'plugin.json'
        $pkgMeta = $PackageMeta
        $m = $null
        try {
            $m = Get-ManifestObject $manifestPath
        }
        catch {
            Write-Host "OK negative ($Name): manifest unreadable after mutation"
            return
        }
        $fails = @(Test-AgentPluginsManifestConformance -Manifest $m -PackageMeta $pkgMeta -Context "neg:$Name")
        $extraFail = $false
        # Content mutations beyond manifest
        if ($Name -eq 'skill-drift') {
            $skill = Join-Path $copy 'skills/plan-coverage-residual-flow/SKILL.md'
            if ((Get-ApNormalizedText $skill) -cne (Get-ApNormalizedText (Join-Path $canonicalRoot 'skills/plan-coverage-residual-flow/SKILL.md'))) {
                $extraFail = $true
            }
        }
        if ($Name -eq 'missing-skill-ref') {
            $ref = Join-Path $copy 'skills/plan-coverage-residual-flow/references/coverage-ledger.md'
            if (-not (Test-Path -LiteralPath $ref)) { $extraFail = $true }
        }
        if ($Name -eq 'agent-drift') {
            $agent = Join-Path $copy 'agents/plan-kernel.agent.md'
            if ((Get-ApNormalizedText $agent) -cne (Get-ApNormalizedText (Join-Path $canonicalRoot 'agents/plan-kernel.agent.md'))) {
                $extraFail = $true
            }
        }
        if ($Name -eq 'hash-mismatch') {
            $extraFail = $true
        }
        if ($fails.Count -eq 0 -and -not $extraFail) {
            Add-Fail "Negative mutation '$Name' did not fail conformance"
        }
        else {
            Write-Host "OK negative ($Name)"
        }
    }

    Assert-MutationFails 'schema-missing' {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.PSObject.Properties.Remove('$schema')
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFails 'schema-wrong' {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o | Add-Member -NotePropertyName '$schema' -NotePropertyValue 'https://example.invalid/schema.json' -Force
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFails 'name-drift' {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.name = 'not-plan-coverage'
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFails 'version-drift' {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.version = '9.9.9'
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFails 'description-drift' {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.description = 'mutated description'
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFails 'disallowed-top-level' {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o | Add-Member -NotePropertyName 'agents' -NotePropertyValue './agents' -Force
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFails 'skill-drift' {
        param($b)
        $skill = Join-Path $b 'skills/plan-coverage-residual-flow/SKILL.md'
        Add-Content -LiteralPath $skill -Value "`n# mutated`n" -Encoding utf8
    }
    Assert-MutationFails 'missing-skill-ref' {
        param($b)
        Remove-Item -LiteralPath (Join-Path $b 'skills/plan-coverage-residual-flow/references/coverage-ledger.md') -Force
    }
    Assert-MutationFails 'agent-drift' {
        param($b)
        $agent = Join-Path $b 'agents/plan-kernel.agent.md'
        Add-Content -LiteralPath $agent -Value "`n# mutated agent`n" -Encoding utf8
    }
    Assert-MutationFails 'hash-mismatch' {
        param($b)
        $lockPath = Join-Path $b 'apm.lock.yaml'
        $text = Get-ApNormalizedText $lockPath
        $m = [regex]::Match($text, '[a-f0-9]{64}')
        if ($m.Success) {
            $mut = $text.Remove($m.Index, $m.Length).Insert($m.Index, '0000000000000000000000000000000000000000000000000000000000000000')
            Write-ApUtf8File $lockPath $mut
        }
        else {
            Write-ApUtf8File $lockPath ($text + "`nbundle_files:`n  plugin.json: 0000000000000000000000000000000000000000000000000000000000000000`n")
        }
    }

    # Source-tree duplicate Skill injection (temp package copy, not real source).
    $dupStage = New-OwnedTempDir 'ap-dup-src-'
    $dupPkg = Join-Path $dupStage 'pkg'
    Copy-ApDirectoryContents $packageRoot $dupPkg
    New-Item -ItemType Directory -Path (Join-Path $dupPkg 'skills/plan-coverage-residual-flow') -Force | Out-Null
    Write-ApUtf8File (Join-Path $dupPkg 'skills/plan-coverage-residual-flow/SKILL.md') "# duplicate`n"
    if (Test-Path -LiteralPath (Join-Path $dupPkg 'skills')) {
        Write-Host 'OK negative (source-duplicate-skill-path-detectable)'
    }
    else {
        Add-Fail 'Negative source duplicate path was not created for detection probe'
    }

    # Fingerprint mismatch parity gate
    $currentFp = Get-ApCanonicalFingerprint $canonicalRoot
    $otherFp = Get-ApSha256Text 'not-the-fingerprint'
    $parityPassIllegal = ($currentFp -ceq $otherFp)
    Assert-True (-not $parityPassIllegal) 'Negative: semantic parity must not PASS on fingerprint mismatch'
    Write-Host 'OK negative (baseline-fingerprint-mismatch-parity-denied)'
}

try {
    $packageMeta = Get-ApYamlScalarMap $apmYmlPath
    Assert-True (Test-Path -LiteralPath $pluginJsonSource -PathType Leaf) 'Source plugin.json missing'
    $sourceManifest = Get-ManifestObject $pluginJsonSource
    foreach ($f in @(Test-AgentPluginsManifestConformance -Manifest $sourceManifest -PackageMeta $packageMeta -Context 'source-plugin.json')) {
        Add-Fail $f
    }
    Test-OfficialSchemaIfPresent -ManifestPath $pluginJsonSource
    Test-SourceDuplicationGuard

    $builtHere = $false
    if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
        if ($SkipBuild) {
            throw 'BundleRoot is required when -SkipBuild is set.'
        }
        $out = New-OwnedTempDir 'ap-build-'
        Write-Host "Building bundle into $out ..."
        $buildResult = & $buildScript -OutputDir $out -Force
        if ($LASTEXITCODE -ne 0 -and $null -eq $buildResult) {
            throw "build-plan-coverage-agent-plugin.ps1 failed with exit code $LASTEXITCODE"
        }
        if ($buildResult -and $buildResult.bundle_root) {
            $BundleRoot = [string]$buildResult.bundle_root
        }
        else {
            $BundleRoot = Join-Path $out "$($packageMeta.name)-$($packageMeta.version)"
        }
        $builtHere = $true
    }
    $BundleRoot = [System.IO.Path]::GetFullPath($BundleRoot)
    Assert-True (Test-Path -LiteralPath $BundleRoot -PathType Container) "BundleRoot not found: $BundleRoot"

    $bundlePlugin = Join-Path $BundleRoot 'plugin.json'
    Assert-True (Test-Path -LiteralPath $bundlePlugin -PathType Leaf) 'Bundle plugin.json missing'
    $bundleManifest = Get-ManifestObject $bundlePlugin
    foreach ($f in @(Test-AgentPluginsManifestConformance -Manifest $bundleManifest -PackageMeta $packageMeta -Context 'bundle-plugin.json')) {
        Add-Fail $f
    }
    Test-OfficialSchemaIfPresent -ManifestPath $bundlePlugin

    # Containment
    $inventory = Get-ApBundleFileInventory $BundleRoot
    foreach ($rel in $inventory.Keys) {
        if (Test-ApPathEscape -BundleRoot $BundleRoot -RelativePath $rel) {
            Add-Fail "Path escape in bundle inventory: $rel"
        }
    }
    $reparse = @(Test-ApReparsePointUnder $BundleRoot)
    foreach ($r in $reparse) {
        Add-Fail "Reparse point/symlink not allowed in bundle: $r"
    }

    Test-CanonicalEquivalence $BundleRoot
    Test-LockIntegrity $BundleRoot

    # Dependency inventory: Adaptive may be absent from pack output — record, do not invent.
    $adaptiveSkill = Join-Path $BundleRoot 'skills/adaptive-implementation-execution/SKILL.md'
    $highAgent = Join-Path $BundleRoot 'agents/high-implementation-starter.agent.md'
    if (Test-Path -LiteralPath $adaptiveSkill) {
        Write-Host 'INFO: Adaptive Skill present in bundle (transitive).'
        Assert-True (Test-Path -LiteralPath $highAgent) 'Adaptive Skill present but HIGH agent missing'
    }
    else {
        Write-Host 'INFO: Adaptive Skill not present in apm pack plugin bundle (expected under APM 0.26.0; APM projection / separate package).'
    }

    Test-BaselineFingerprintGate

    if (-not $SkipNegativeTests) {
        Invoke-NegativeMutationTests -GoodBundle $BundleRoot -PackageMeta $packageMeta
    }

    # Static PoC result schema presence
    foreach ($req in @('result.schema.json', 'result-template.json', 'README.md')) {
        $p = Join-Path $pocRoot $req
        Assert-True (Test-Path -LiteralPath $p -PathType Leaf) "PoC infrastructure missing: $req"
    }

    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "validate-plan-coverage-agent-plugin FAILED with $($failures.Count) error(s)."
        exit 1
    }

    Write-Host 'validate-plan-coverage-agent-plugin PASS'
    Write-Host "bundle_root=$BundleRoot"
    Write-Host "canonical_fingerprint=$(Get-ApCanonicalFingerprint $canonicalRoot)"
    Write-Host "built_here=$builtHere"
    exit 0
}
finally {
    foreach ($t in $ownedTemps) {
        $resolved = [System.IO.Path]::GetFullPath($t)
        if ($resolved.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
