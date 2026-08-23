[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [string]$ApmExecutable = 'apm',
    [switch]$SkipNegativeMutations
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AgentPlugin.Common.ps1')

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$packageRoot = Join-Path $repoRoot "apm-packages/$Package"
$manifestPath = Join-Path $packageRoot 'apm.yml'
$canonicalRoot = Join-Path $packageRoot '.apm'
$contract = Get-AgentPluginContract $packageRoot
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) { $failures.Add($Message) | Out-Null }
function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { Add-Failure $Message } }

$manifestName = Get-AgentPluginManifestScalar $manifestPath 'name'
$targets = @(Get-AgentPluginManifestTargets $manifestPath)
$dependencies = @(Get-AgentPluginManifestDependencies $manifestPath)
Assert-True ([string]$contract.package -ceq $manifestName) 'Contract package differs from apm.yml'
Assert-True ((@($contract.installTargets) -join '|') -ceq ($targets -join '|')) 'Contract installTargets differ from apm.yml'
Assert-True ((@($contract.dependencies) | Sort-Object) -join '|' -ceq (($dependencies | Sort-Object) -join '|')) 'Contract dependencies differ from apm.yml'

$actualSkills = @(Get-ChildItem -LiteralPath (Join-Path $canonicalRoot 'skills') -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name)
$actualAgents = @(Get-ChildItem -LiteralPath (Join-Path $canonicalRoot 'agents') -Filter '*.agent.md' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.BaseName -replace '\.agent$','' })
$actualInstructions = @(Get-ChildItem -LiteralPath (Join-Path $canonicalRoot 'instructions') -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name)
Assert-True ((@($contract.ownedSkills) -join '|') -ceq ($actualSkills -join '|')) 'Contract ownedSkills differ from canonical source'
Assert-True ((@($contract.ownedAgents) -join '|') -ceq ($actualAgents -join '|')) 'Contract ownedAgents differ from canonical source'
Assert-True ((@($contract.ownedInstructions) -join '|') -ceq ($actualInstructions -join '|')) 'Contract ownedInstructions differ from canonical source'
foreach ($failure in Get-AgentPluginSourceGuardFailures $packageRoot) { Add-Failure $failure }

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$outputRoot = Join-Path $tempRoot ('agent-plugin-validation-' + [guid]::NewGuid().ToString('N'))
$safeToDelete = $false
try {
    $null = New-Item -ItemType Directory -Path $outputRoot -Force
    $resolvedOutput = (Resolve-Path -LiteralPath $outputRoot).Path
    if (-not $resolvedOutput.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe validation output: $resolvedOutput" }
    $safeToDelete = $true
    $build = Invoke-AgentPluginBuild -PackageRoot $packageRoot -OutputDirectory $outputRoot -ApmExecutable $ApmExecutable
    foreach ($failure in Get-AgentPluginBundleFailures $packageRoot $build.bundleRoot) { Add-Failure $failure }

    foreach ($dependency in @($contract.dependencies)) {
        if (Test-Path -LiteralPath (Join-Path $build.bundleRoot "skills/$dependency")) { Add-Failure "Dependency Skill was silently inlined: $dependency" }
    }

    if (-not $SkipNegativeMutations) {
        function Assert-MutationFails([string]$Name, [scriptblock]$Mutate) {
            $copy = Join-Path $outputRoot "mutation-$Name"
            Copy-AgentPluginDirectory $build.bundleRoot $copy
            & $Mutate $copy
            $mutationFailures = @(Get-AgentPluginBundleFailures $packageRoot $copy)
            if ($mutationFailures.Count -eq 0) { Add-Failure "Negative mutation was not detected: $Name" }
        }

        Assert-MutationFails 'manifest-name' {
            param($root)
            $path = Join-Path $root 'plugin.json'
            $json = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
            $json.name = 'mutated-name'
            [IO.File]::WriteAllText($path, ($json | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
        }
        $firstSkill = @(Get-ChildItem -LiteralPath (Join-Path $build.bundleRoot 'skills') -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($firstSkill) {
            $relative = Get-AgentPluginRelativePath $build.bundleRoot $firstSkill[0].FullName
            Assert-MutationFails 'skill-drift' { param($root) Add-Content -LiteralPath (Join-Path $root $relative) -Value 'mutation' }
        }
        $firstAgent = @(Get-ChildItem -LiteralPath (Join-Path $build.bundleRoot 'agents') -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($firstAgent) {
            $relative = Get-AgentPluginRelativePath $build.bundleRoot $firstAgent[0].FullName
            Assert-MutationFails 'agent-drift' { param($root) Add-Content -LiteralPath (Join-Path $root $relative) -Value 'mutation' }
        }
        $firstInstruction = @(Get-ChildItem -LiteralPath (Join-Path $build.bundleRoot 'instructions') -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($firstInstruction) {
            $relative = Get-AgentPluginRelativePath $build.bundleRoot $firstInstruction[0].FullName
            Assert-MutationFails 'instruction-drift' { param($root) Add-Content -LiteralPath (Join-Path $root $relative) -Value 'mutation' }
        }
        Assert-MutationFails 'lock-hash' {
            param($root)
            $path = Join-Path $root 'plugin.json'
            Add-Content -LiteralPath $path -Value ' '
        }

        $sourceCopy = Join-Path $outputRoot 'source-duplicate'
        Copy-AgentPluginDirectory $packageRoot $sourceCopy
        $dup = Join-Path $sourceCopy "skills/$($contract.ownedSkills[0])/SKILL.md"
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $dup) -Force
        [IO.File]::WriteAllText($dup, '# duplicate', [Text.UTF8Encoding]::new($false))
        if (@(Get-AgentPluginSourceGuardFailures $sourceCopy).Count -eq 0) { Add-Failure 'Negative duplicate semantic source was not detected' }
    }

    if ($failures.Count -gt 0) { throw ("Agent Plugin package validation failed for ${Package}:`n- " + ($failures -join "`n- ")) }
    Write-Output "Agent Plugin package validation: PASS ($Package fingerprint=$($build.canonicalFingerprint))"
}
finally {
    if ($safeToDelete -and (Test-Path -LiteralPath $outputRoot)) {
        $resolved = [IO.Path]::GetFullPath($outputRoot)
        if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to remove unsafe validation output: $resolved" }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
