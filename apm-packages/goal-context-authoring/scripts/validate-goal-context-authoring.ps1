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

function Test-SubstantiveText {
    param([string]$Text)

    return -not [string]::IsNullOrWhiteSpace($Text) -and $Text -match '[\p{L}\p{N}]'
}

function Get-MarkdownTableCells {
    param([string]$Line)

    $trimmed = $Line.Trim()
    if (-not ($trimmed.StartsWith('|') -and $trimmed.EndsWith('|'))) {
        return @()
    }

    $inner = $trimmed.Substring(1, $trimmed.Length - 2)
    return @([regex]::Split($inner, '(?<!\\)\|') | ForEach-Object { $_.Trim() })
}

function Add-ProvenanceListSectionErrors {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Content,
        [string]$Heading
    )

    $body = Get-SectionBody -Content $Content -Heading $Heading
    if ($null -eq $body) {
        return
    }

    $entries = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($body, '\r?\n')) {
        $entryMatch = [regex]::Match($line, '^\s*(?:-\s+|\d+\.\s+)(?<entry>.*?)\s*$')
        if ($entryMatch.Success) {
            $entries.Add($entryMatch.Groups['entry'].Value)
        }
    }

    if ($entries.Count -eq 0) {
        $Errors.Add("Section must contain at least one list entry: $Heading")
        return
    }

    foreach ($entry in $entries) {
        $provenanceMatch = [regex]::Match($entry, '^\[(?:Explicit|Inferred|Unknown)\](?<remainder>.*)$')
        if (-not $provenanceMatch.Success) {
            $Errors.Add("List entry must start with exactly one [Explicit], [Inferred], or [Unknown] tag: $Heading")
            continue
        }

        $remainder = $provenanceMatch.Groups['remainder'].Value
        $entryText = $remainder.Trim()
        if (-not (Test-SubstantiveText $entryText)) {
            $Errors.Add("List entry must contain substantive text after its provenance tag: $Heading")
            continue
        }
        if ($remainder -notmatch '^\s+') {
            $Errors.Add("List entry must separate its provenance tag from substantive text: $Heading")
            continue
        }
        if ($entryText -match '^\[[^\]]+\]') {
            $Errors.Add("List entry must contain exactly one provenance tag: $Heading")
            continue
        }
    }
}

function Add-ProvenanceTableSectionErrors {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Content,
        [string]$Heading,
        [string[]]$ExpectedHeaders,
        [int]$ProvenanceColumn
    )

    $body = Get-SectionBody -Content $Content -Heading $Heading
    if ($null -eq $body) {
        return
    }

    $tableLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [regex]::Split($body, '\r?\n')) {
        if ($line -match '^\s*\|.*\|\s*$') {
            $tableLines.Add($line)
        }
    }

    if ($tableLines.Count -lt 2) {
        $Errors.Add("Section must contain a Markdown table with a header and separator: $Heading")
        return
    }

    $headerCells = @(Get-MarkdownTableCells $tableLines[0])
    $separatorCells = @(Get-MarkdownTableCells $tableLines[1])
    if ($headerCells.Count -ne $ExpectedHeaders.Count) {
        $Errors.Add("Table header must contain $($ExpectedHeaders.Count) columns: $Heading")
    }
    else {
        for ($index = 0; $index -lt $ExpectedHeaders.Count; $index++) {
            if ($headerCells[$index] -ne $ExpectedHeaders[$index]) {
                $Errors.Add("Table header column $($index + 1) must be '$($ExpectedHeaders[$index])': $Heading")
            }
        }
    }

    if ($separatorCells.Count -ne $ExpectedHeaders.Count -or @($separatorCells | Where-Object { $_ -notmatch '^:?-{3,}:?$' }).Count -gt 0) {
        $Errors.Add("Table separator must contain $($ExpectedHeaders.Count) valid Markdown separator cells: $Heading")
    }

    if ($tableLines.Count -lt 3) {
        $Errors.Add("Table must contain at least one data row: $Heading")
        return
    }

    foreach ($line in $tableLines.GetRange(2, $tableLines.Count - 2)) {
        $cells = @(Get-MarkdownTableCells $line)
        if ($cells.Count -ne $ExpectedHeaders.Count) {
            $Errors.Add("Table data row must contain $($ExpectedHeaders.Count) columns: $Heading")
            continue
        }

        if ($cells[$ProvenanceColumn] -notmatch '^\[(?:Explicit|Inferred|Unknown)\]$') {
            $Errors.Add("Table provenance cell must be exactly [Explicit], [Inferred], or [Unknown]: $Heading")
        }

        for ($index = 0; $index -lt $cells.Count; $index++) {
            if ($index -eq $ProvenanceColumn) {
                continue
            }
            if (-not (Test-SubstantiveText $cells[$index])) {
                $Errors.Add("Table data cell must contain substantive text in column $($index + 1): $Heading")
            }
        }
    }
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
    if ($status -in @('draft', 'human-reviewed') -and $sensitiveReview -in @('pending', 'passed')) {
        $validLifecyclePair =
            ($status -eq 'draft' -and $sensitiveReview -eq 'pending') -or
            ($status -eq 'human-reviewed' -and $sensitiveReview -eq 'passed')
        if (-not $validLifecyclePair) {
            $errors.Add("Only lifecycle pairs draft/pending and human-reviewed/passed are allowed; found: $status/$sensitiveReview")
        }
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

    $provenanceListHeadings = @(
        '## Document control and source boundary',
        '## Original problem',
        '## Desired outcome',
        '## Concrete user situation and user scenarios',
        '### MVP scope',
        '### Non-goals',
        '### Future work',
        '## Constraints and invariants',
        '## Success scenarios',
        '## Superficially compliant but wrong',
        '## Review questions',
        '## Open questions and assumptions'
    )
    foreach ($heading in $provenanceListHeadings) {
        Add-ProvenanceListSectionErrors -Errors $errors -Content $Content -Heading $heading
    }

    $provenanceTableSections = @(
        @{ Heading = '### Accepted decisions'; Headers = @('Provenance', 'Decision', 'Reason', 'Consequence'); ProvenanceColumn = 0 },
        @{ Heading = '### Rejected alternatives'; Headers = @('Provenance', 'Alternative', 'Rejection reason', 'Revisit condition'); ProvenanceColumn = 0 },
        @{ Heading = '## Acceptance evidence'; Headers = @('Provenance', 'Outcome to demonstrate', 'Required evidence', 'Evidence type'); ProvenanceColumn = 0 },
        @{ Heading = '## Conversation corrections and priority changes'; Headers = @('Provenance', 'Earlier statement', 'Current statement or priority', 'Evidence of supersession'); ProvenanceColumn = 0 },
        @{ Heading = '## Provenance and inference ledger'; Headers = @('Claim or section', 'Classification', 'Source evidence or reasoning', 'Confidence / required follow-up'); ProvenanceColumn = 1 }
    )
    foreach ($tableSection in $provenanceTableSections) {
        Add-ProvenanceTableSectionErrors -Errors $errors -Content $Content -Heading $tableSection.Heading -ExpectedHeaders $tableSection.Headers -ProvenanceColumn $tableSection.ProvenanceColumn
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
    'docs/examples/goal-context-resumable-local-batch-export.md',
    'scripts/test-apm-package-install.ps1'
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
    'Claim ID',
    'Contract dimension',
    'None observed in this segment',
    'Superseded by <Claim ID>',
    'Excluded as sensitive',
    'Retained as Unknown',
    'not an Issue body'
)) {
    Assert-Contains $promptPath $pattern "prompt requirement '$pattern'"
}

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

$sourceFixturePath = 'docs/examples/source-conversation-fixture.md'
$reviewedExamplePath = 'docs/examples/goal-context-resumable-local-batch-export.md'
foreach ($claimId in @('LC-AC-001', 'LC-WRONG-001')) {
    Assert-Contains $sourceFixturePath ([regex]::Escape($claimId)) "source fixture claim '$claimId'"
    Assert-Contains $reviewedExamplePath ([regex]::Escape($claimId)) "reviewed example claim '$claimId'"
}
$sourceFixtureFullPath = Get-PackagePath $sourceFixturePath
if (Test-Path -LiteralPath $sourceFixtureFullPath -PathType Leaf) {
    $sourceFixtureContent = Get-Content -Raw -LiteralPath $sourceFixtureFullPath
    foreach ($claimId in @('LC-AC-001', 'LC-WRONG-001')) {
        if ([regex]::Matches($sourceFixtureContent, [regex]::Escape($claimId)).Count -ne 1) {
            Add-Failure "Source fixture claim must occur exactly once so later segments cannot mask its loss: $claimId"
        }
    }
}

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

    $acceptanceEvidenceBody = Get-SectionBody -Content $exampleContent -Heading '## Acceptance evidence'
    if ($acceptanceEvidenceBody -notmatch 'LC-AC-001') {
        Add-Failure 'Reviewed example does not preserve LC-AC-001 in Acceptance evidence'
    }
    $wrongOutcomeBody = Get-SectionBody -Content $exampleContent -Heading '## Superficially compliant but wrong'
    if ($wrongOutcomeBody -notmatch 'LC-WRONG-001') {
        Add-Failure 'Reviewed example does not preserve LC-WRONG-001 in Superficially compliant but wrong'
    }
    $provenanceLedgerBody = Get-SectionBody -Content $exampleContent -Heading '## Provenance and inference ledger'
    foreach ($claimId in @('LC-AC-001', 'LC-WRONG-001')) {
        if ($provenanceLedgerBody -notmatch [regex]::Escape($claimId)) {
            Add-Failure "Reviewed example provenance ledger does not preserve claim: $claimId"
        }
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

    $headerOnlyTableMutation = [regex]::Replace(
        $exampleContent,
        '(?ms)(### Rejected alternatives\s*\r?\n\s*\|.*?\|\s*\r?\n\s*\|.*?\|\s*\r?\n)(?:\s*\|.*?\|\s*\r?\n)+',
        '$1',
        1
    )
    $headerOnlyTableErrors = @(Get-GoalContextErrors -Content $headerOnlyTableMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($headerOnlyTableErrors -match '^Table must contain at least one data row: ### Rejected alternatives$')) {
        Add-Failure 'Negative fixture mutation did not detect a header-only Rejected alternatives table'
    }

    $markerOnlyMutation = [regex]::Replace($exampleContent, '(?m)^- \[(?:Explicit|Inferred|Unknown)\].+$', '- [Explicit]', 1)
    $markerOnlyErrors = @(Get-GoalContextErrors -Content $markerOnlyMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($markerOnlyErrors -match '^List entry must contain substantive text after its provenance tag:')) {
        Add-Failure 'Negative fixture mutation did not detect a marker-only list entry'
    }

    $untaggedMutation = [regex]::Replace($exampleContent, '(?m)^- \[(?:Explicit|Inferred|Unknown)\]\s+', '- ', 1)
    $untaggedErrors = @(Get-GoalContextErrors -Content $untaggedMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($untaggedErrors -match '^List entry must start with exactly one')) {
        Add-Failure 'Negative fixture mutation did not detect an untagged material list entry'
    }

    $unsupportedTagMutation = [regex]::Replace($exampleContent, '(?m)^- \[Explicit\]', '- [Certain]', 1)
    $unsupportedTagErrors = @(Get-GoalContextErrors -Content $unsupportedTagMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($unsupportedTagErrors -match '^List entry must start with exactly one')) {
        Add-Failure 'Negative fixture mutation did not detect an unsupported provenance tag'
    }

    $doubleTagMutation = [regex]::Replace($exampleContent, '(?m)^- \[Explicit\]', '- [Explicit] [Unknown]', 1)
    $doubleTagErrors = @(Get-GoalContextErrors -Content $doubleTagMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $true)
    if (-not ($doubleTagErrors -match '^List entry must contain exactly one provenance tag:')) {
        Add-Failure 'Negative fixture mutation did not detect multiple provenance tags'
    }

    $draftPassedMutation = $exampleContent.Replace('status: human-reviewed', 'status: draft')
    $draftPassedErrors = @(Get-GoalContextErrors -Content $draftPassedMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $false)
    if (-not ($draftPassedErrors -match '^Only lifecycle pairs draft/pending and human-reviewed/passed are allowed')) {
        Add-Failure 'Negative fixture mutation did not detect draft/passed lifecycle state'
    }

    $humanReviewedPendingMutation = $exampleContent.Replace('sensitive_data_review: passed', 'sensitive_data_review: pending')
    $humanReviewedPendingErrors = @(Get-GoalContextErrors -Content $humanReviewedPendingMutation -FileName (Split-Path -Leaf $examplePath) -HumanReviewRequired $false)
    if (-not ($humanReviewedPendingErrors -match '^Only lifecycle pairs draft/pending and human-reviewed/passed are allowed')) {
        Add-Failure 'Negative fixture mutation did not detect human-reviewed/pending lifecycle state'
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
    throw ("Goal Context Authoring validation failed:`n- " + ($failures -join "`n- "))
}

if ([string]::IsNullOrWhiteSpace($GoalContextPath)) {
    Write-Output 'Goal Context Authoring package validation: PASS'
}
else {
    $mode = if ($RequireHumanReview) { 'human-reviewed' } else { 'draft-structural' }
    Write-Output "Goal Context Authoring package and $mode artifact validation: PASS"
}
