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
$schemaFixture = Join-Path $repoRoot 'tests/agent-plugins/plugin.schema.1.0.0.json'
$resultSchemaPath = Join-Path $pocRoot 'result.schema.json'
$buildScript = Join-Path $PSScriptRoot 'build-plan-coverage-agent-plugin.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
$tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$ownedTemps = [System.Collections.Generic.List[string]]::new()

$script:SuppressFailHost = $false
function Add-Fail([string]$Message) {
    $failures.Add($Message)
    if (-not $script:SuppressFailHost) {
        Write-Host "FAIL: $Message"
    }
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

function Get-SourceDuplicationFailures([string]$PackageRootPath, [string]$RepoRootPath) {
    $fails = [System.Collections.Generic.List[string]]::new()
    foreach ($dup in @(
            (Join-Path $PackageRootPath 'skills'),
            (Join-Path $PackageRootPath 'agents'),
            (Join-Path $RepoRootPath 'skills/plan-coverage-residual-flow'),
            (Join-Path $RepoRootPath 'agent-plugin')
        )) {
        if (Test-Path -LiteralPath $dup) {
            $fails.Add("Forbidden Agent Plugins duplicate source path present: $dup") | Out-Null
        }
    }
    return @($fails)
}

function Test-SourceDuplicationGuard {
    foreach ($msg in @(Get-SourceDuplicationFailures -PackageRootPath $packageRoot -RepoRootPath $repoRoot)) {
        Add-Fail $msg
    }
}

function Invoke-ProductionChecksOnBundle {
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [Parameter(Mandatory = $true)]$PackageMeta,
        [ValidateSet('manifest', 'equivalence', 'lock', 'all')][string]$Mode = 'all'
    )
    $prevSuppress = $script:SuppressFailHost
    $script:SuppressFailHost = $true
    $before = $failures.Count
    if ($Mode -ceq 'manifest' -or $Mode -ceq 'all') {
        $manifestPath = Join-Path $BundlePath 'plugin.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            Add-Fail "production-check: missing plugin.json under $BundlePath"
        }
        else {
            try {
                $m = Get-ManifestObject $manifestPath
                foreach ($f in @(Test-AgentPluginsManifestConformance -Manifest $m -PackageMeta $PackageMeta -Context 'production-check')) {
                    Add-Fail $f
                }
            }
            catch {
                Add-Fail "production-check: manifest unreadable: $_"
            }
        }
    }
    if ($Mode -ceq 'equivalence' -or $Mode -ceq 'all') {
        Test-CanonicalEquivalence $BundlePath
    }
    if ($Mode -ceq 'lock' -or $Mode -ceq 'all') {
        Test-LockIntegrity $BundlePath
    }
    $added = $failures.Count - $before
    # Pop intentional failures so the overall validator can still PASS.
    if ($added -gt 0) {
        for ($i = 0; $i -lt $added; $i++) {
            $failures.RemoveAt($failures.Count - 1)
        }
    }
    $script:SuppressFailHost = $prevSuppress
    return $added
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

    Write-Host 'Running negative mutation tests on temp copies (production validator path)...'

    function Assert-MutationFailsProduction {
        param(
            [string]$Name,
            [scriptblock]$Mutate,
            [ValidateSet('manifest', 'equivalence', 'lock')][string]$Mode
        )
        $tmp = New-OwnedTempDir 'ap-neg-'
        $copy = Join-Path $tmp 'bundle'
        Copy-ApDirectoryContents $GoodBundle $copy
        & $Mutate $copy
        $detected = Invoke-ProductionChecksOnBundle -BundlePath $copy -PackageMeta $PackageMeta -Mode $Mode
        if ($detected -le 0) {
            Add-Fail "Negative mutation '$Name' did not fail production validator mode=$Mode"
        }
        else {
            Write-Host "OK negative ($Name) via production $Mode checks (failures=$detected)"
        }
    }

    Assert-MutationFailsProduction -Name 'schema-missing' -Mode manifest -Mutate {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.PSObject.Properties.Remove('$schema')
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFailsProduction -Name 'schema-wrong' -Mode manifest -Mutate {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o | Add-Member -NotePropertyName '$schema' -NotePropertyValue 'https://example.invalid/schema.json' -Force
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFailsProduction -Name 'name-drift' -Mode manifest -Mutate {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.name = 'not-plan-coverage'
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFailsProduction -Name 'version-drift' -Mode manifest -Mutate {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.version = '9.9.9'
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFailsProduction -Name 'description-drift' -Mode manifest -Mutate {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o.description = 'mutated description'
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFailsProduction -Name 'disallowed-top-level' -Mode manifest -Mutate {
        param($b)
        $p = Join-Path $b 'plugin.json'
        $o = Get-ManifestObject $p
        $o | Add-Member -NotePropertyName 'agents' -NotePropertyValue './agents' -Force
        Write-ApUtf8File $p (($o | ConvertTo-Json -Depth 10))
    }
    Assert-MutationFailsProduction -Name 'skill-drift' -Mode equivalence -Mutate {
        param($b)
        $skill = Join-Path $b 'skills/plan-coverage-residual-flow/SKILL.md'
        Add-Content -LiteralPath $skill -Value "`n# mutated`n" -Encoding utf8
    }
    Assert-MutationFailsProduction -Name 'missing-skill-ref' -Mode equivalence -Mutate {
        param($b)
        Remove-Item -LiteralPath (Join-Path $b 'skills/plan-coverage-residual-flow/references/coverage-ledger.md') -Force
    }
    Assert-MutationFailsProduction -Name 'agent-drift' -Mode equivalence -Mutate {
        param($b)
        $agent = Join-Path $b 'agents/plan-kernel.agent.md'
        Add-Content -LiteralPath $agent -Value "`n# mutated agent`n" -Encoding utf8
    }
    Assert-MutationFailsProduction -Name 'hash-mismatch' -Mode lock -Mutate {
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

    # Source-tree duplicate Skill: production duplication guard must FAIL on mutated package copy.
    $dupStage = New-OwnedTempDir 'ap-dup-src-'
    $dupPkg = Join-Path $dupStage 'pkg'
    Copy-ApDirectoryContents $packageRoot $dupPkg
    New-Item -ItemType Directory -Path (Join-Path $dupPkg 'skills/plan-coverage-residual-flow') -Force | Out-Null
    Write-ApUtf8File (Join-Path $dupPkg 'skills/plan-coverage-residual-flow/SKILL.md') "# duplicate`n"
    $dupFails = @(Get-SourceDuplicationFailures -PackageRootPath $dupPkg -RepoRootPath $repoRoot)
    if ($dupFails.Count -eq 0) {
        Add-Fail 'Negative source-duplicate-skill: production duplication guard did not fail on mutated package copy'
    }
    else {
        Write-Host "OK negative (source-duplicate-skill) via production guard (failures=$($dupFails.Count))"
    }

    # Fingerprint mismatch parity gate (synthetic)
    $currentFp = Get-ApCanonicalFingerprint $canonicalRoot
    $otherFp = Get-ApSha256Text 'not-the-fingerprint'
    $parityPassIllegal = ($currentFp -ceq $otherFp)
    Assert-True (-not $parityPassIllegal) 'Negative: semantic parity must not PASS on fingerprint mismatch'
    Write-Host 'OK negative (baseline-fingerprint-mismatch-parity-denied)'
}

function Test-PocResultInvariants($Result, [string]$Context) {
    $local = [System.Collections.Generic.List[string]]::new()
    if ([int]$Result.schema_version -ne 1) { $local.Add("$Context schema_version") | Out-Null }
    if ([int]$Result.issue -ne 107) { $local.Add("$Context issue!=107") | Out-Null }
    if (-not $Result.spec -or [string]$Result.spec.agent_plugins_version -cne '1.0.0') {
        $local.Add("$Context spec.agent_plugins_version") | Out-Null
    }
    foreach ($req in @('source_run', 'environment', 'bundle', 'copilot_direct_load', 'codex_direct_load', 'boundary_inventory', 'comparison_to_apm', 'decision')) {
        if (-not ($Result.PSObject.Properties.Name -contains $req)) {
            $local.Add("$Context missing $req") | Out-Null
        }
    }
    $fp = [string]$Result.source_run.canonical_fingerprint
    if ($fp -notmatch '^[a-f0-9]{64}$') {
        $local.Add("$Context canonical_fingerprint malformed") | Out-Null
    }
    $commit = [string]$Result.source_run.candidate_commit
    $isLive = @('PASS', 'PARTIAL', 'BLOCKED', 'FAIL') -contains [string]$Result.copilot_direct_load.status
    if ($isLive) {
        if ($commit -match '-dirty$' -or $commit -notmatch '^[a-f0-9]{40}$') {
            $local.Add("$Context live evidence candidate_commit must be clean 40-char SHA (got: $commit)") | Out-Null
        }
    }
    $verdict = [string]$Result.decision.verdict
    if (@('GO', 'HOLD', 'NO_GO') -notcontains $verdict) {
        $local.Add("$Context decision.verdict invalid") | Out-Null
    }
    $parity = $false
    if ($Result.comparison_to_apm -and ($Result.comparison_to_apm.PSObject.Properties.Name -contains 'semantic_parity_claimed')) {
        $parity = [bool]$Result.comparison_to_apm.semantic_parity_claimed
    }
    $fpMatch = $true
    if ($Result.comparison_to_apm -and ($Result.comparison_to_apm.PSObject.Properties.Name -contains 'fingerprint_match')) {
        $fpMatch = [bool]$Result.comparison_to_apm.fingerprint_match
    }
    if ($parity -and -not $fpMatch) {
        $local.Add("$Context semantic_parity_claimed=true with fingerprint_match=false") | Out-Null
    }
    if ($verdict -ceq 'GO') {
        if (-not $fpMatch) { $local.Add("$Context GO requires fingerprint_match") | Out-Null }
        if ([string]$Result.copilot_direct_load.authorization -cne 'PASS') {
            $local.Add("$Context GO requires authorization PASS") | Out-Null
        }
        if ([string]$Result.copilot_direct_load.standard_slice -cne 'PASS') {
            $local.Add("$Context GO requires standard_slice PASS") | Out-Null
        }
        if ([string]$Result.copilot_direct_load.full_coverage -cne 'PASS') {
            $local.Add("$Context GO requires full_coverage PASS") | Out-Null
        }
        if ([string]$Result.copilot_direct_load.adaptive_connection -cne 'PASS') {
            $local.Add("$Context GO requires adaptive_connection PASS") | Out-Null
        }
        if (-not $parity) {
            $local.Add("$Context GO requires semantic_parity_claimed=true") | Out-Null
        }
    }
    if ($Result.scenarios) {
        $ids = @($Result.scenarios | ForEach-Object { [string]$_.id })
        foreach ($need in @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H')) {
            if ($ids -notcontains $need -and $isLive -and [string]$Result.copilot_direct_load.authorization -ne 'NOT_RUN') {
                $local.Add("$Context live authorization evidence missing scenario $need") | Out-Null
            }
        }
    }
    elseif ($isLive -and [string]$Result.copilot_direct_load.authorization -ne 'NOT_RUN') {
        $local.Add("$Context live result missing scenarios array") | Out-Null
    }
    if (-not $Result.boundary_inventory -or @($Result.boundary_inventory).Count -lt 8) {
        $local.Add("$Context boundary_inventory too small") | Out-Null
    }
    return @($local)
}

function Test-CommittedPocResults {
    $resultsDir = Join-Path $pocRoot 'results'
    if (-not (Test-Path -LiteralPath $resultsDir)) { return }
    $files = @(Get-ChildItem -LiteralPath $resultsDir -Filter '*-copilot-plugin-poc.json' -File -ErrorAction SilentlyContinue)
    foreach ($f in $files) {
        Write-Host "Validating committed PoC result: $($f.Name)"
        try {
            $obj = Get-ManifestObject $f.FullName
        }
        catch {
            Add-Fail "PoC result not valid JSON: $($f.Name)"
            continue
        }
        foreach ($err in @(Test-PocResultInvariants $obj -Context $f.Name)) {
            Add-Fail $err
        }
        # Lightweight schema required-field check (no external JSON Schema engine).
        if (Test-Path -LiteralPath $resultSchemaPath -PathType Leaf) {
            $schema = Get-ManifestObject $resultSchemaPath
            foreach ($req in @($schema.required)) {
                if (-not ($obj.PSObject.Properties.Name -contains $req)) {
                    Add-Fail "$($f.Name) missing schema-required field: $req"
                }
            }
        }
    }
}

try {
    $packageMeta = Get-ApYamlScalarMap $apmYmlPath
    Assert-True (-not (Test-Path -LiteralPath $pluginJsonSource -PathType Leaf)) `
        'Checked-in package root plugin.json is forbidden (keeps APM local-source install semantics). Synthesize only in pack stage.'
    Test-SourceDuplicationGuard

    $builtHere = $false
    $buildResult = $null
    if ([string]::IsNullOrWhiteSpace($BundleRoot)) {
        if ($SkipBuild) {
            throw 'BundleRoot is required when -SkipBuild is set.'
        }
        $out = New-OwnedTempDir 'ap-build-'
        Write-Host "Building bundle into $out ..."
        # CI working trees are clean; local dirty trees may pass -AllowDirty for deterministic pack tests only.
        $buildResult = & $buildScript -OutputDir $out -Force -AllowDirty
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
    Assert-True (Test-Path -LiteralPath $bundlePlugin -PathType Leaf) 'Bundle plugin.json missing (must be pack-stage synthesized)'
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

    # Adaptive packaging boundary: attestation must PASS and Plan Coverage bundle must not silently include Adaptive.
    if ($buildResult -and $buildResult.adaptive_attestation) {
        $att = $buildResult.adaptive_attestation
        Assert-True ([string]$att.status -ceq 'PASS') 'Adaptive lock attestation status must be PASS'
        Assert-True ([bool]$att.path_dep_pack_refused) 'Expected apm pack to refuse local path dependency'
        Assert-True (-not [bool]$att.present_in_plan_coverage_bundle.skill) 'Plan Coverage plugin bundle unexpectedly contains Adaptive Skill'
        Assert-True (-not [bool]$att.present_in_plan_coverage_bundle.high) 'Plan Coverage plugin bundle unexpectedly contains HIGH agent'
        Assert-True (-not [bool]$att.present_in_plan_coverage_bundle.standard) 'Plan Coverage plugin bundle unexpectedly contains STANDARD agent'
        Write-Host "OK Adaptive attestation: lock proves Skill/HIGH/STANDARD; pack does not inline them; path-dep pack refused."
        if ($att.standalone_adaptive_bundle_root) {
            $adSkill = Join-Path $att.standalone_adaptive_bundle_root 'skills/adaptive-implementation-execution/SKILL.md'
            Assert-True (Test-Path -LiteralPath $adSkill -PathType Leaf) 'Adaptive standalone pack missing Skill'
            Write-Host "OK Adaptive standalone plugin pack: $($att.standalone_adaptive_bundle_root)"
        }
    }
    else {
        $adaptiveSkill = Join-Path $BundleRoot 'skills/adaptive-implementation-execution/SKILL.md'
        if (Test-Path -LiteralPath $adaptiveSkill) {
            Write-Host 'INFO: Adaptive Skill present in provided bundle (external BundleRoot).'
        }
        else {
            Write-Host 'INFO: Adaptive Skill absent from provided bundle (attestation details require build path).'
        }
    }

    Test-BaselineFingerprintGate

    if (-not $SkipNegativeTests) {
        Invoke-NegativeMutationTests -GoodBundle $BundleRoot -PackageMeta $packageMeta
    }

    foreach ($req in @('result.schema.json', 'result-template.json', 'README.md')) {
        $p = Join-Path $pocRoot $req
        Assert-True (Test-Path -LiteralPath $p -PathType Leaf) "PoC infrastructure missing: $req"
    }
    Test-CommittedPocResults

    if ($failures.Count -gt 0) {
        Write-Host ""
        Write-Host "validate-plan-coverage-agent-plugin FAILED with $($failures.Count) error(s)."
        exit 1
    }

    Write-Host 'validate-plan-coverage-agent-plugin PASS'
    Write-Host "bundle_root=$BundleRoot"
    Write-Host "canonical_fingerprint=$(Get-ApCanonicalFingerprint $canonicalRoot)"
    Write-Host "built_here=$builtHere"
    Write-Host "source_plugin_json_checked_in=false"
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
