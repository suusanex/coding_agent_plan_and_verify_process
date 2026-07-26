[CmdletBinding()]
param(
    [string]$GoalContextPath,
    [switch]$RequireHumanReview
)

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()

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
    $path = Get-PackagePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing file: $RelativePath"
    }
}

function Assert-Contains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Get-PackagePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -notmatch $Pattern) {
        Add-Failure "$RelativePath does not contain $Description"
    }
}

function Assert-NotContains {
    param(
        [string]$RelativePath,
        [string]$Pattern,
        [string]$Description
    )

    $path = Get-PackagePath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because file is missing: $RelativePath"
        return
    }

    $content = Get-Content -Raw -LiteralPath $path
    if ($content -match $Pattern) {
        Add-Failure "$RelativePath contains forbidden $Description"
    }
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Key
    )

    $match = [regex]::Match($Frontmatter, "(?m)^$([regex]::Escape($Key)):\s*(?<value>.+?)\s*$")
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['value'].Value.Trim()
}

function Get-SectionBody {
    param(
        [string]$Content,
        [string]$Heading
    )

    $headingMarker = ($Heading -split '\s+', 2)[0]
    $level = $headingMarker.Length
    $nextHeading = '^#{1,' + $level + '}\s'
    $pattern = '(?ms)^' + [regex]::Escape($Heading) + '\s*\r?\n(?<body>.*?)(?=' + $nextHeading + '|\z)'
    $match = [regex]::Match($Content, $pattern)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups['body'].Value
}

function Get-GoalContextErrors {
    param(
        [string]$Content,
        [string]$FileName,
        [bool]$HumanReviewRequired
    )

    $errors = [System.Collections.Generic.List[string]]::new()

    if ($FileName -notmatch '^goal-context-[a-z0-9]+(?:-[a-z0-9]+)*\.md$') {
        $errors.Add("Filename must use lowercase kebab-case goal-context-<topic-summary>.md: $FileName")
    }
    if ($FileName -match '^goal-context-(?:issue|pr|pull-request|ticket|task|work-item)(?:-|$)' -or $FileName -match '^goal-context-\d') {
        $errors.Add("Filename is centered on an Issue, PR, ticket, task, or number instead of durable content: $FileName")
    }

    $frontmatterMatch = [regex]::Match($Content, '(?ms)\A---\s*\r?\n(?<frontmatter>.*?)\r?\n---\s*\r?\n')
    if (-not $frontmatterMatch.Success) {
        $errors.Add('Missing YAML frontmatter at the beginning of the Goal Context')
        $frontmatter = ''
    }
    else {
        $frontmatter = $frontmatterMatch.Groups['frontmatter'].Value
    }

    $requiredFrontmatter = @('document_type', 'status', 'topic', 'created_at', 'source_scope', 'sensitive_data_review')
    foreach ($key in $requiredFrontmatter) {
        $value = Get-FrontmatterValue -Frontmatter $frontmatter -Key $key
        if ([string]::IsNullOrWhiteSpace($value)) {
            $errors.Add("Missing or empty frontmatter field: $key")
        }
    }

    $documentType = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'document_type'
    if ($documentType -and $documentType -ne 'goal-context') {
        $errors.Add("document_type must be goal-context, found: $documentType")
    }

    $status = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'status'
    if ($status -and $status -notin @('draft', 'human-reviewed')) {
        $errors.Add("status must be draft or human-reviewed, found: $status")
    }

    $sensitiveReview = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'sensitive_data_review'
    if ($sensitiveReview -and $sensitiveReview -notin @('pending', 'passed')) {
        $errors.Add("sensitive_data_review must be pending or passed, found: $sensitiveReview")
    }

    $createdAt = Get-FrontmatterValue -Frontmatter $frontmatter -Key 'created_at'
    if ($createdAt -and $createdAt -notmatch '^\d{4}-\d{2}-\d{2}$') {
        $errors.Add("created_at must use YYYY-MM-DD, found: $createdAt")
    }

    $titleMatch = [regex]::Match($Content, '(?m)^# Goal Context:\s+\S.+$')
    if (-not $titleMatch.Success) {
        $errors.Add('Missing non-empty title: # Goal Context: <Topic>')
    }

    $requiredHeadings = @(
        '## Document control and source boundary',
        '## Original problem',
        '## Desired outcome',
        '## Concrete user situation and user scenarios',
        '## Scope and boundaries',
        '### MVP scope',
        '### Non-goals',
        '### Future work',
        '## Decisions and reasoning',
        '### Accepted decisions',
        '### Rejected alternatives',
        '## Constraints and invariants',
        '## Success scenarios',
        '## Acceptance evidence',
        '## Superficially compliant but wrong',
        '## Review questions',
        '## Open questions and assumptions',
        '## Conversation corrections and priority changes',
        '## Provenance and inference ledger',
        '## Human review record'
    )

    foreach ($heading in $requiredHeadings) {
        $body = Get-SectionBody -Content $Content -Heading $heading
        if ($null -eq $body) {
            $errors.Add("Missing required heading: $heading")
            continue
        }

        $meaningfulBody = [regex]::Replace($body, '(?s)<!--.*?-->', '').Trim()
        if ([string]::IsNullOrWhiteSpace($meaningfulBody)) {
            $errors.Add("Required section is empty: $heading")
        }
    }

    if ($Content -notmatch '\[Explicit\]') {
        $errors.Add('No [Explicit] provenance marker was found')
    }
    if ($Content -match '(?i)\[(?:Assumed|Fact|Guess)\]') {
        $errors.Add('Unsupported provenance marker found; use [Explicit], [Inferred], or [Unknown]')
    }

    $placeholderPatterns = @(
        '<!--',
        '<durable topic summary>',
        '<available conversation range',
        '(?m)^created_at:\s*YYYY-MM-DD\s*$'
    )
    foreach ($pattern in $placeholderPatterns) {
        if ($Content -match $pattern) {
            $errors.Add("Unresolved template placeholder matched: $pattern")
        }
    }

    $secretPatterns = @(
        'AKIA[0-9A-Z]{16}',
        'gh[pousr]_[A-Za-z0-9]{20,}',
        'sk-[A-Za-z0-9_-]{20,}',
        '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?im)^\s*(?:password|api[_-]?key|client[_-]?secret|accountkey)\s*[:=]\s*(?!<redacted:)[^#\r\n]+$'
    )
    foreach ($pattern in $secretPatterns) {
        if ($Content -match $pattern) {
            $errors.Add("Potential exposed secret or credential matched high-confidence pattern: $pattern")
        }
    }

    $humanReviewBody = Get-SectionBody -Content $Content -Heading '## Human review record'
    if ($status -eq 'human-reviewed') {
        if ($sensitiveReview -ne 'passed') {
            $errors.Add('status human-reviewed requires sensitive_data_review: passed')
        }
        if ($humanReviewBody -notmatch '(?im)^- Review status:\s*Complete\s*$') {
            $errors.Add('status human-reviewed requires Review status: Complete')
        }
        if ($humanReviewBody -notmatch '(?im)^- Reviewer:\s*(?!Pending\s*$)\S.+$') {
            $errors.Add('status human-reviewed requires a non-pending Reviewer')
        }
        if ($humanReviewBody -notmatch '(?im)^- Reviewed at:\s*\d{4}-\d{2}-\d{2}\s*$') {
            $errors.Add('status human-reviewed requires Reviewed at in YYYY-MM-DD format')
        }
        if ($humanReviewBody -match '(?im):\s*Pending\s*$') {
            $errors.Add('status human-reviewed cannot retain Pending fields in Human review record')
        }

        $requiredConfirmations = @(
            'Desired outcome confirmed',
            'Rejected alternatives confirmed',
            'Superficially compliant but wrong outcomes confirmed',
            'MVP / Non-goals / Future work boundary confirmed',
            'Corrections and priority changes confirmed',
            'Provenance and unknowns confirmed',
            'Sensitive-data review confirmed'
        )
        foreach ($confirmation in $requiredConfirmations) {
            $confirmationPattern = '(?im)^- ' + [regex]::Escape($confirmation) + ':\s*Yes\s*$'
            if ($humanReviewBody -notmatch $confirmationPattern) {
                $errors.Add("status human-reviewed requires '${confirmation}: Yes'")
            }
        }
    }

    if ($HumanReviewRequired) {
        if ($status -ne 'human-reviewed') {
            $errors.Add('Strict validation requires status: human-reviewed')
        }
        if ($sensitiveReview -ne 'passed') {
            $errors.Add('Strict validation requires sensitive_data_review: passed')
        }
    }

    return $errors.ToArray()
}

$requiredFiles = @(
    'apm.yml',
    'README.md',
    '.apm/skills/goal-context-authoring/SKILL.md',
    '.apm/skills/goal-context-authoring/references/generation-prompt.md',
    '.apm/skills/goal-context-authoring/references/goal-context-contract.md',
    '.apm/skills/goal-context-authoring/references/goal-context-template.md',
    '.apm/skills/goal-context-authoring/references/human-review-checklist.md',
    'docs/usage-and-install-guide.md',
    'docs/examples/source-conversation-fixture.md',
    'docs/examples/goal-context-resumable-local-batch-export.md'
)
foreach ($file in $requiredFiles) {
    Assert-FileExists $file
}

Assert-Contains 'apm.yml' '(?m)^name:\s*goal-context-authoring\s*$' 'package identity'
Assert-Contains 'apm.yml' '(?ms)^targets:\s*.*?- codex\s*.*?- agent-skills\s*' 'codex and agent-skills targets'
Assert-NotContains 'apm.yml' '\.md\s*$' 'standalone Markdown dependency'

$skillPath = '.apm/skills/goal-context-authoring/SKILL.md'
Assert-Contains $skillPath '(?m)^name:\s*goal-context-authoring\s*$' 'skill identity'
Assert-Contains $skillPath 'references/generation-prompt\.md' 'generation prompt reference'
Assert-Contains $skillPath 'references/goal-context-contract\.md' 'document contract reference'
Assert-Contains $skillPath 'references/goal-context-template\.md' 'template reference'
Assert-Contains $skillPath 'references/human-review-checklist\.md' 'human review checklist reference'
Assert-Contains $skillPath 'SOURCE_MATERIAL_REQUIRED' 'missing-source stop verdict'
Assert-Contains $skillPath 'RequireHumanReview' 'strict validation handoff'

$promptPath = '.apm/skills/goal-context-authoring/references/generation-prompt.md'
foreach ($pattern in @(
    'earliest available point',
    'corrections and priority changes',
    'Rejected alternatives',
    'Superficially compliant but wrong',
    '\[Explicit\]',
    '\[Inferred\]',
    '\[Unknown\]',
    'secrets, credentials',
    'Long-conversation continuation protocol',
    'not an Issue body'
)) {
    Assert-Contains $promptPath $pattern "prompt requirement '$pattern'"
}

$contractPath = '.apm/skills/goal-context-authoring/references/goal-context-contract.md'
Assert-Contains $contractPath 'goal-context-<topic-summary>\.md' 'content-centered naming rule'
Assert-Contains $contractPath 'status: human-reviewed' 'human-reviewed lifecycle rule'
Assert-Contains $contractPath 'AI self-review alone is not human review' 'human review boundary'
Assert-Contains $contractPath 'Issue body with more prose' 'Issue-copy prohibition'

$checklistPath = '.apm/skills/goal-context-authoring/references/human-review-checklist.md'
foreach ($pattern in @('Desired outcome', 'Rejected alternatives', 'Superficially compliant but wrong', 'MVP scope', 'Priority changes', 'Secrets, credentials')) {
    Assert-Contains $checklistPath $pattern "human review focus '$pattern'"
}

$examplePath = Get-PackagePath 'docs/examples/goal-context-resumable-local-batch-export.md'
if (Test-Path -LiteralPath $examplePath -PathType Leaf) {
    $exampleContent = Get-Content -Raw -LiteralPath $examplePath
    $exampleErrors = @(Get-GoalContextErrors -Content $exampleContent -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    foreach ($errorMessage in $exampleErrors) {
        Add-Failure "Reviewed example is invalid: $errorMessage"
    }

    $missingHeadingMutation = $exampleContent.Replace('### Rejected alternatives', '### Alternatives omitted')
    $missingHeadingErrors = @(Get-GoalContextErrors -Content $missingHeadingMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($missingHeadingErrors -match '^Missing required heading: ### Rejected alternatives$')) {
        Add-Failure 'Negative fixture mutation did not detect a missing Rejected alternatives heading'
    }

    $fakeSecret = 's' + 'k-' + ('x' * 24)
    $secretMutation = $exampleContent + "`napi_key = $fakeSecret`n"
    $secretErrors = @(Get-GoalContextErrors -Content $secretMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($secretErrors -match '^Potential exposed secret or credential')) {
        Add-Failure 'Negative fixture mutation did not detect a high-confidence credential pattern'
    }

    $badNameErrors = @(Get-GoalContextErrors -Content $exampleContent -FileName 'goal-context-issue-51.md' -HumanReviewRequired $true)
    if (-not ($badNameErrors -match '^Filename is centered on an Issue')) {
        Add-Failure 'Negative fixture mutation did not detect an Issue-centered filename'
    }
}

if (-not [string]::IsNullOrWhiteSpace($GoalContextPath)) {
    try {
        $resolvedGoalContextPath = (Resolve-Path -LiteralPath $GoalContextPath).Path
    }
    catch {
        Add-Failure "Goal Context path does not exist: $GoalContextPath"
        $resolvedGoalContextPath = $null
    }

    if ($resolvedGoalContextPath) {
        $goalContextContent = Get-Content -Raw -LiteralPath $resolvedGoalContextPath
        $goalContextErrors = @(Get-GoalContextErrors -Content $goalContextContent -FileName (Split-Path -Leaf $resolvedGoalContextPath) -HumanReviewRequired $RequireHumanReview.IsPresent)
        foreach ($errorMessage in $goalContextErrors) {
            Add-Failure "Goal Context validation failed: $errorMessage"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Goal Context Authoring validation failed:`n- " + ($failures -join "`n- "))
    exit 1
}

if ([string]::IsNullOrWhiteSpace($GoalContextPath)) {
    Write-Output 'Goal Context Authoring package validation: PASS'
}
else {
    $mode = if ($RequireHumanReview) { 'human-reviewed' } else { 'draft-structural' }
    Write-Output "Goal Context Authoring package and $mode artifact validation: PASS"
}
