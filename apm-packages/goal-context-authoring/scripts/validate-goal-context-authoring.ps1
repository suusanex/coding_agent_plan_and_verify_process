[CmdletBinding()]
param(
    [string]$GoalContextPath,
    [switch]$RequireHumanReview
)

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()
$validatorRelativePath = '.apm/skills/goal-context-authoring/scripts/validate-goal-context.cs'
$validatorSourcePath = Join-Path $packageRoot $validatorRelativePath
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$scratchPath = Join-Path $tempRoot ('goal-context-validator-' + [guid]::NewGuid().ToString('N'))
$resolvedScratchPath = $null
$safeToDelete = $false

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

function Get-PackagePath {
    param([string]$RelativePath)
    return Join-Path $packageRoot $RelativePath
}

function Assert-FileExists {
    param([string]$RelativePath)
    if (-not (Test-Path -LiteralPath (Get-PackagePath $RelativePath) -PathType Leaf)) {
        Add-Failure "Missing file: $RelativePath"
    }
}

function Assert-Contains {
    param([string]$RelativePath, [string]$Pattern, [string]$Description)
    $path = Get-PackagePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }
    if ((Get-Content -Raw -LiteralPath $path) -notmatch $Pattern) {
        Add-Failure "$RelativePath does not contain $Description"
    }
}

function Assert-NotContains {
    param([string]$RelativePath, [string]$Pattern, [string]$Description)
    $path = Get-PackagePath $RelativePath
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Content -Raw -LiteralPath $path) -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

function Invoke-NativeCapture {
    param([string]$FilePath, [string[]]$Arguments)
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

function Invoke-GoalContextValidator {
    param([string]$Path, [ValidateSet('strict', 'draft')][string]$Mode)
    $result = Invoke-NativeCapture -FilePath $script:validatorExecutable -Arguments @(
        '--goal-context', $Path,
        '--mode', $Mode,
        '--format', 'json'
    )
    try {
        $json = $result.Stdout | ConvertFrom-Json
    }
    catch {
        throw "Goal Context validator returned invalid JSON. stdout=$($result.Stdout) stderr=$($result.Stderr)"
    }
    return [pscustomobject]@{ ExitCode = $result.ExitCode; Result = $json; Stderr = $result.Stderr }
}

function Test-Mutation {
    param(
        [string]$Scenario,
        [string]$FileName,
        [string]$Content,
        [string]$Mode,
        [string]$ExpectedError
    )
    $directory = Join-Path $resolvedScratchPath ('cases/' + $Scenario)
    $null = New-Item -ItemType Directory -Path $directory -Force
    $path = Join-Path $directory $FileName
    Set-Content -LiteralPath $path -Value $Content -Encoding utf8 -NoNewline
    $validation = Invoke-GoalContextValidator -Path $path -Mode $Mode
    if ($validation.ExitCode -ne 2 -or -not ($validation.Result.errors -match $ExpectedError)) {
        Add-Failure "Negative fixture mutation was not rejected as expected: $Scenario"
    }
}

try {
    $null = New-Item -ItemType Directory -Path $scratchPath
    $resolvedScratchPath = (Resolve-Path -LiteralPath $scratchPath).Path
    $requiredPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedScratchPath.StartsWith($requiredPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to use scratch path outside the system temporary directory: $resolvedScratchPath"
    }
    $safeToDelete = $true

    $requiredFiles = @(
        'apm.yml',
        'README.md',
        '.apm/skills/goal-context-authoring/SKILL.md',
        '.apm/skills/goal-context-authoring/references/generation-prompt.md',
        '.apm/skills/goal-context-authoring/references/goal-context-contract.md',
        '.apm/skills/goal-context-authoring/references/goal-context-template.md',
        '.apm/skills/goal-context-authoring/references/human-review-checklist.md',
        $validatorRelativePath,
        'docs/usage-and-install-guide.md',
        'docs/examples/source-conversation-fixture.md',
        'docs/examples/goal-context-resumable-local-batch-export.md',
        'scripts/test-apm-package-install.ps1'
    )
    foreach ($file in $requiredFiles) { Assert-FileExists $file }

    Assert-Contains 'apm.yml' '(?m)^name:\s*goal-context-authoring\s*$' 'package identity'
    Assert-Contains 'apm.yml' '(?ms)^targets:\s*.*?- codex\s*.*?- agent-skills\s*' 'codex and agent-skills targets'
    Assert-NotContains 'apm.yml' '\.md\s*$' 'standalone Markdown dependency'

    $skillPath = '.apm/skills/goal-context-authoring/SKILL.md'
    Assert-Contains $skillPath '(?m)^name:\s*goal-context-authoring\s*$' 'skill identity'
    Assert-Contains $skillPath 'references/generation-prompt\.md' 'generation prompt reference'
    Assert-Contains $skillPath 'references/goal-context-contract\.md' 'document contract reference'
    Assert-Contains $skillPath 'references/goal-context-template\.md' 'template reference'
    Assert-Contains $skillPath 'references/human-review-checklist\.md' 'human review checklist reference'
    Assert-Contains $skillPath 'scripts/validate-goal-context\.cs' 'distributed canonical validator reference'
    Assert-Contains $skillPath 'SOURCE_MATERIAL_REQUIRED' 'missing-source stop verdict'
    Assert-Contains $skillPath 'RequireHumanReview' 'strict validation handoff'

    $promptPath = '.apm/skills/goal-context-authoring/references/generation-prompt.md'
    foreach ($pattern in @(
        'purpose-achievement review', 'not a second specification, an Issue body', 'Purpose hierarchy',
        'earliest relevant discussion', 'corrections and priority changes', 'rejected alternatives',
        'appear compliant while leaving the original problem unresolved', '\[Inferred\]', '\[Unknown\]',
        'secrets, credentials', 'ordered segments', 'Do not create Claim IDs or a detailed provenance ledger'
    )) { Assert-Contains $promptPath $pattern "prompt requirement '$pattern'" }

    $contractPath = '.apm/skills/goal-context-authoring/references/goal-context-contract.md'
    Assert-Contains $contractPath 'goal-context-<topic-summary>\.md' 'content-centered naming rule'
    Assert-Contains $contractPath 'status: human-reviewed' 'human-reviewed lifecycle rule'
    Assert-Contains $contractPath 'status: draft` / `sensitive_data_review: pending' 'draft/pending lifecycle pair'
    Assert-Contains $contractPath 'status: human-reviewed` / `sensitive_data_review: passed' 'human-reviewed/passed lifecycle pair'
    Assert-Contains $contractPath 'AI self-review alone is not human review' 'human review boundary'
    Assert-Contains $contractPath 'Issue body with more prose' 'Issue-copy prohibition'

    $smokePath = 'scripts/test-apm-package-install.ps1'
    Assert-Contains $smokePath 'apm install' 'package-root APM install command description'
    Assert-Contains $smokePath '--target' 'explicit install target selection'
    Assert-Contains $smokePath 'SHA256' 'installed file integrity verification'
    Assert-Contains $smokePath 'validate-goal-context\.cs' 'installed validator execution'

    $sourceFixturePath = 'docs/examples/source-conversation-fixture.md'
    $reviewedExamplePath = 'docs/examples/goal-context-resumable-local-batch-export.md'
    foreach ($claimId in @('LC-AC-001', 'LC-WRONG-001')) {
        Assert-Contains $sourceFixturePath ([regex]::Escape($claimId)) "source fixture claim '$claimId'"
        Assert-Contains $reviewedExamplePath ([regex]::Escape($claimId)) "reviewed example claim '$claimId'"
    }
    $sourceFixtureContent = Get-Content -Raw -LiteralPath (Get-PackagePath $sourceFixturePath)
    foreach ($claimId in @('LC-AC-001', 'LC-WRONG-001')) {
        if ([regex]::Matches($sourceFixtureContent, [regex]::Escape($claimId)).Count -ne 1) {
            Add-Failure "Source fixture claim must occur exactly once so later segments cannot mask its loss: $claimId"
        }
    }

    $checklistPath = '.apm/skills/goal-context-authoring/references/human-review-checklist.md'
    foreach ($pattern in @('Desired outcome', 'Rejected alternatives', 'Superficially compliant but wrong', 'MVP scope', 'Priority changes', 'Secrets, credentials')) {
        Assert-Contains $checklistPath $pattern "human review focus '$pattern'"
    }

    $publishPath = Join-Path $resolvedScratchPath 'publish'
    $publish = Invoke-NativeCapture -FilePath 'dotnet' -Arguments @('publish', $validatorSourcePath, '--output', $publishPath, '--disable-build-servers')
    if ($publish.ExitCode -ne 0) {
        throw "Canonical Goal Context validator publish failed: $($publish.Stdout) $($publish.Stderr)"
    }
    $script:validatorExecutable = Join-Path $publishPath ($(if ($IsWindows) { 'validate-goal-context.exe' } else { 'validate-goal-context' }))
    if (-not (Test-Path -LiteralPath $script:validatorExecutable -PathType Leaf)) {
        throw "Canonical Goal Context validator executable was not published: $script:validatorExecutable"
    }

    $examplePath = Get-PackagePath $reviewedExamplePath
    $exampleContent = Get-Content -Raw -LiteralPath $examplePath
    $exampleValidation = Invoke-GoalContextValidator -Path $examplePath -Mode 'strict'
    if ($exampleValidation.ExitCode -ne 0 -or $exampleValidation.Result.status -ne 'PASS') {
        Add-Failure "Reviewed example is invalid: $($exampleValidation.Result.errors -join '; ')"
    }
    foreach ($claimId in @('LC-AC-001', 'LC-WRONG-001')) {
        if ($exampleContent -notmatch [regex]::Escape($claimId)) {
            Add-Failure "Reviewed example does not preserve claim: $claimId"
        }
    }

    $fileName = Split-Path -Leaf $examplePath
    Test-Mutation 'missing-h3' $fileName ($exampleContent.Replace('### Rejected alternatives', '### Alternatives omitted')) 'strict' '^Missing required heading: ### Rejected alternatives$'
    $fakeSecret = 's' + 'k-' + ('x' * 24)
    Test-Mutation 'secret' $fileName ($exampleContent + "`napi_key = $fakeSecret`n") 'strict' '^Potential exposed secret or credential'
    Test-Mutation 'bad-name' 'goal-context-issue-51.md' $exampleContent 'strict' '^Filename is centered on an Issue'
    $headerOnly = [regex]::Replace($exampleContent, '(?ms)(### Rejected alternatives\s*\r?\n\s*\|.*?\|\s*\r?\n\s*\|.*?\|\s*\r?\n)(?:\s*\|.*?\|\s*\r?\n)+', '$1', 1)
    Test-Mutation 'header-only-table' $fileName $headerOnly 'strict' '^Table must contain at least one data row: ### Rejected alternatives$'
    Test-Mutation 'marker-only' $fileName ([regex]::Replace($exampleContent, '(?m)^- \[(?:Explicit|Inferred|Unknown)\].+$', '- [Explicit]', 1)) 'strict' '^List entry must contain substantive text after its provenance tag:'
    Test-Mutation 'untagged' $fileName ([regex]::Replace($exampleContent, '(?m)^- \[(?:Explicit|Inferred|Unknown)\]\s+', '- ', 1)) 'strict' '^List entry must start with exactly one'
    Test-Mutation 'unsupported-tag' $fileName ([regex]::Replace($exampleContent, '(?m)^- \[Explicit\]', '- [Certain]', 1)) 'strict' '^List entry must start with exactly one'
    Test-Mutation 'double-tag' $fileName ([regex]::Replace($exampleContent, '(?m)^- \[Explicit\]', '- [Explicit] [Unknown]', 1)) 'strict' '^List entry must contain exactly one provenance tag:'
    Test-Mutation 'draft-passed' $fileName ($exampleContent.Replace('status: human-reviewed', 'status: draft')) 'draft' '^Only lifecycle pairs draft/pending and human-reviewed/passed are allowed'
    Test-Mutation 'reviewed-pending' $fileName ($exampleContent.Replace('sensitive_data_review: passed', 'sensitive_data_review: pending')) 'draft' '^Only lifecycle pairs draft/pending and human-reviewed/passed are allowed'
    Test-Mutation 'reviewer-missing' $fileName ([regex]::Replace($exampleContent, '(?m)^- Reviewer:.*\r?\n', '', 1)) 'strict' '^status human-reviewed requires a non-pending Reviewer$'
    Test-Mutation 'reviewed-at-missing' $fileName ([regex]::Replace($exampleContent, '(?m)^- Reviewed at:.*\r?\n', '', 1)) 'strict' '^status human-reviewed requires Reviewed at'
    Test-Mutation 'confirmation-no' $fileName ($exampleContent.Replace('- Desired outcome confirmed: Yes', '- Desired outcome confirmed: No')) 'strict' "^status human-reviewed requires 'Desired outcome confirmed: Yes'"

    if (-not [string]::IsNullOrWhiteSpace($GoalContextPath)) {
        try { $resolvedGoalContextPath = (Resolve-Path -LiteralPath $GoalContextPath).Path }
        catch { Add-Failure "Goal Context path does not exist: $GoalContextPath"; $resolvedGoalContextPath = $null }
        if ($resolvedGoalContextPath) {
            $mode = if ($RequireHumanReview) { 'strict' } else { 'draft' }
            $targetValidation = Invoke-GoalContextValidator -Path $resolvedGoalContextPath -Mode $mode
            if ($targetValidation.ExitCode -ne 0) {
                foreach ($errorMessage in $targetValidation.Result.errors) { Add-Failure "Goal Context validation failed: $errorMessage" }
            }
        }
    }
}
finally {
    if ($safeToDelete -and $resolvedScratchPath -and (Test-Path -LiteralPath $resolvedScratchPath)) {
        Remove-Item -LiteralPath $resolvedScratchPath -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    throw ("Goal Context Authoring validation failed:`n- " + ($failures -join "`n- "))
}

if ([string]::IsNullOrWhiteSpace($GoalContextPath)) {
    Write-Output 'Goal Context Authoring package validation: PASS'
}
else {
    $mode = if ($RequireHumanReview) { 'human-reviewed' } else { 'draft-structural' }
    Write-Output "Goal Context Authoring package and $mode artifact validation: PASS"
}
