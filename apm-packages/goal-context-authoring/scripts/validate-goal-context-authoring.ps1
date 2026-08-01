[CmdletBinding()]
param(
    [string]$GoalContextPath,
    [switch]$RequireHumanReview
)

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$validatorRelativePath = '.apm/skills/goal-context-authoring/scripts/validate-goal-context.cs'
$validatorSourcePath = Join-Path $packageRoot $validatorRelativePath
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$scratchPath = Join-Path $tempRoot ('goal-context-authoring-validation-' + [guid]::NewGuid().ToString('N'))
$safeToDelete = $false

function Assert-File([string]$RelativePath) {
    $path = Join-Path $packageRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
}

function Assert-Contains([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $path = Join-Path $packageRoot $RelativePath
    Assert-File $RelativePath
    if ((Get-Content -Raw -LiteralPath $path) -notmatch $Pattern) { throw "$RelativePath does not contain $Description" }
}

function Invoke-NativeCapture([string]$FilePath, [string[]]$Arguments) {
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $FilePath
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $null = $start.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($start)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
}

function Invoke-Validator([string]$Path, [string]$Mode = 'basic') {
    $result = Invoke-NativeCapture $script:validatorExecutable @('--goal-context', $Path, '--mode', $Mode, '--format', 'json')
    try { $json = $result.Stdout | ConvertFrom-Json }
    catch { throw "Goal Context validator returned invalid JSON. stdout=$($result.Stdout) stderr=$($result.Stderr)" }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Json = $json }
}

try {
    New-Item -ItemType Directory -Path $scratchPath | Out-Null
    $resolvedScratch = (Resolve-Path -LiteralPath $scratchPath).Path
    $requiredPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedScratch.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use scratch path outside the system temporary directory: $resolvedScratch"
    }
    $safeToDelete = $true

    foreach ($file in @(
        'apm.yml',
        'README.md',
        '.apm/skills/goal-context-authoring/SKILL.md',
        '.apm/skills/goal-context-authoring/references/generation-prompt.md',
        '.apm/skills/goal-context-authoring/references/goal-context-contract.md',
        '.apm/skills/goal-context-authoring/references/goal-context-template.md',
        '.apm/skills/goal-context-authoring/references/human-review-checklist.md',
        $validatorRelativePath,
        'docs/usage-and-install-guide.md',
        'scripts/test-apm-package-install.ps1'
    )) { Assert-File $file }

    Assert-Contains 'apm.yml' '(?m)^name:\s*goal-context-authoring\s*$' 'package identity'
    Assert-Contains '.apm/skills/goal-context-authoring/SKILL.md' 'no required filename, extension, frontmatter, headings' 'free-form interoperability boundary'
    Assert-Contains '.apm/skills/goal-context-authoring/references/generation-prompt.md' 'The output is free-form' 'free-form generation instruction'
    Assert-Contains '.apm/skills/goal-context-authoring/references/goal-context-contract.md' 'No consumer may require' 'consumer non-requirement contract'
    Assert-Contains '.apm/skills/goal-context-authoring/references/goal-context-template.md' 'not a schema' 'optional template boundary'
    Assert-Contains '.apm/skills/goal-context-authoring/references/human-review-checklist.md' 'Human review is optional' 'optional human review boundary'

    $publishPath = Join-Path $resolvedScratch 'publish'
    $publish = Invoke-NativeCapture 'dotnet' @('publish', $validatorSourcePath, '--output', $publishPath, '--disable-build-servers')
    if ($publish.ExitCode -ne 0) { throw "Goal Context validator publish failed: $($publish.Stdout) $($publish.Stderr)" }
    $script:validatorExecutable = Join-Path $publishPath ($(if ($IsWindows) { 'validate-goal-context.exe' } else { 'validate-goal-context' }))
    if (-not (Test-Path -LiteralPath $script:validatorExecutable -PathType Leaf)) { throw "Published Goal Context validator is missing: $script:validatorExecutable" }

    $freeFormPath = Join-Path $resolvedScratch 'arbitrary-context.txt'
    Set-Content -LiteralPath $freeFormPath -Encoding utf8 -NoNewline -Value 'People should be able to complete the work without copying context into a second task. No headings or metadata are required.'
    foreach ($mode in @('basic', 'draft', 'strict')) {
        $validation = Invoke-Validator $freeFormPath $mode
        if ($validation.ExitCode -ne 0 -or $validation.Json.status -ne 'PASS' -or $validation.Json.validationContract -ne 'readable-free-form') {
            throw "Free-form Goal Context failed $mode validation: $($validation.Json.errors -join '; ')"
        }
    }

    $emptyPath = Join-Path $resolvedScratch 'empty.txt'
    Set-Content -LiteralPath $emptyPath -Encoding utf8 -NoNewline -Value '   '
    if ((Invoke-Validator $emptyPath).ExitCode -ne 2) { throw 'Empty Goal Context was not rejected.' }

    $nulPath = Join-Path $resolvedScratch 'nul.txt'
    [System.IO.File]::WriteAllText($nulPath, "readable`0binary")
    if ((Invoke-Validator $nulPath).ExitCode -ne 2) { throw 'NUL-bearing Goal Context was not rejected.' }

    $secretPath = Join-Path $resolvedScratch 'secret.txt'
    [System.IO.File]::WriteAllText($secretPath, 'api_key = s' + 'k-' + ('x' * 24))
    if ((Invoke-Validator $secretPath).ExitCode -ne 2) { throw 'High-confidence credential fixture was not rejected.' }

    if ($GoalContextPath) {
        $resolvedGoalContext = (Resolve-Path -LiteralPath $GoalContextPath).Path
        $mode = if ($RequireHumanReview) { 'strict' } else { 'basic' }
        $targetValidation = Invoke-Validator $resolvedGoalContext $mode
        if ($targetValidation.ExitCode -ne 0) { throw "Goal Context validation failed: $($targetValidation.Json.errors -join '; ')" }
    }
}
finally {
    if ($safeToDelete -and (Test-Path -LiteralPath $scratchPath)) {
        Remove-Item -LiteralPath $scratchPath -Recurse -Force
    }
}

if ($RequireHumanReview) {
    Write-Warning '-RequireHumanReview is a compatibility switch only; Goal Context has no required human-review lifecycle.'
}
Write-Output 'Goal Context Authoring package validation: PASS'
