[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

$prohibitedRootPatterns = @(
    @{ Path = '.github/agents'; Description = 'package runtime agent projection' },
    @{ Path = '.codex/agents'; Description = 'package runtime Codex projection' },
    @{ Path = '.agents/skills'; Description = 'package runtime skill projection' }
)

foreach ($entry in $prohibitedRootPatterns) {
    $rootPath = Join-Path $repoRoot $entry.Path
    if (Test-Path -LiteralPath $rootPath -PathType Container) {
        $children = Get-ChildItem -LiteralPath $rootPath -Recurse -File
        if ($children.Count -gt 0) {
            $failures.Add("Prohibited $($entry.Description) directory exists at root: $($entry.Path) ($($children.Count) file(s))")
        }
    }
}

$instructionsDir = Join-Path $repoRoot '.github/instructions'
if (Test-Path -LiteralPath $instructionsDir -PathType Container) {
    $packageOwnedInstructions = @(Get-ChildItem -LiteralPath $instructionsDir -File -Recurse | Where-Object {
        $name = $_.Name
        $knownPackageInstructions = @('plan-coverage-shared.instructions.md')
        $name -in $knownPackageInstructions
    })
    foreach ($file in $packageOwnedInstructions) {
        $failures.Add("Prohibited package-owned instruction at root: $($file.FullName.Substring($repoRoot.Length + 1))")
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Root projection prevention check failed:`n- " + ($failures -join "`n- "))
    exit 1
}

Write-Output 'Root projection prevention check: PASS'
