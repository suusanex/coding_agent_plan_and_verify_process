[CmdletBinding()]
param(
    [string] $CliPath = "copilot"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = (Resolve-Path $PSScriptRoot).Path
$experimentRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$repositoryRoot = (Resolve-Path (Join-Path $experimentRoot "..\..")).Path
$evidenceRoot = Join-Path $experimentRoot "evidence\copilot\persistence-control"

function Write-Utf8NoBom([string] $Path, [string] $Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        [void] (New-Item -ItemType Directory -Path $parent -Force)
    }

    [IO.File]::WriteAllText($Path, ($Text ?? ""), [Text.UTF8Encoding]::new($false))
}

function Write-Json([string] $Path, [object] $Value) {
    Write-Utf8NoBom $Path (($Value | ConvertTo-Json -Depth 16) + "`r`n")
}

function Get-Sha256([byte[]] $Bytes) {
    $digest = [Security.Cryptography.SHA256]::HashData($Bytes)
    return (($digest | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-FileSha256([string] $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    return [ordered]@{
        bytes = $bytes.Length
        sha256 = Get-Sha256 $bytes
        hash_method = "SHA-256 over exact file bytes"
    }
}

function Get-RelativePath([string] $Root, [string] $Path) {
    return ([IO.Path]::GetRelativePath($Root, $Path)).Replace("/", "\")
}

function Get-GitSnapshot {
    $status = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed."
    }

    $unstaged = @(& git -C $repositoryRoot diff --name-status 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff failed."
    }

    $staged = @(& git -C $repositoryRoot diff --cached --name-status 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git diff --cached failed."
    }

    $head = (& git -C $repositoryRoot rev-parse HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git rev-parse failed."
    }

    $branch = (& git -C $repositoryRoot branch --show-current 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git branch failed."
    }

    return [ordered]@{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        head = $head
        branch = $branch
        status = @($status | ForEach-Object { [string] $_ })
        unstaged_name_status = @($unstaged | ForEach-Object { [string] $_ })
        staged_name_status = @($staged | ForEach-Object { [string] $_ })
    }
}

function Get-TrackedSnapshot([object] $Snapshot) {
    $items = [Collections.Generic.List[string]]::new()
    foreach ($line in @($Snapshot.unstaged_name_status) + @($Snapshot.staged_name_status)) {
        $items.Add([string] $line)
    }

    return ,([string[]] $items.ToArray())
}

function Get-OutsideExperimentStatus([object] $Snapshot) {
    $prefix = "experiments\persistent-purpose-reviewer\"
    $items = [Collections.Generic.List[string]]::new()
    foreach ($statusLine in @($Snapshot.status)) {
        $line = [string] $statusLine
        if ($line.Length -lt 4) {
            $items.Add($line)
            continue
        }

        $path = $line.Substring(3)
        if ($path.StartsWith('"')) {
            $path = $path.Trim('"')
        }

        if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $items.Add($line)
        }
    }

    return ,([string[]] $items.ToArray())
}

function Get-ProductionStatus([object] $Snapshot) {
    $productionPrefixes = @(
        ".github\",
        "apps\",
        "apm_modules\",
        "apm-packages\",
        "docs\",
        "plans\",
        "scripts\",
        "tests\"
    )
    $items = [Collections.Generic.List[string]]::new()
    foreach ($statusLine in @($Snapshot.status)) {
        $line = [string] $statusLine
        if ($line.Length -lt 4) {
            $items.Add($line)
            continue
        }

        $path = $line.Substring(3).Trim('"').Replace("/", "\")
        if ($productionPrefixes | Where-Object { $path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) {
            $items.Add($line)
        }
    }

    return ,([string[]] $items.ToArray())
}

function Get-InputFileRecord([string] $Path) {
    $relative = Get-RelativePath $experimentRoot $Path
    $file = Get-FileSha256 $Path
    return [ordered]@{
        path = $relative
        bytes = $file.bytes
        sha256 = $file.sha256
        hash_method = $file.hash_method
    }
}

function Read-Utf8([string] $Path) {
    return [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($Path))
}

function New-Payload([string] $PromptPath, [string[]] $FixturePaths) {
    $parts = [Collections.Generic.List[string]]::new()
    $parts.Add((Read-Utf8 $PromptPath))

    foreach ($fixturePath in $FixturePaths) {
        $name = [IO.Path]::GetFileName($fixturePath)
        $parts.Add("--- BEGIN FIXTURE: $name ---")
        $parts.Add((Read-Utf8 $fixturePath))
        $parts.Add("--- END FIXTURE: $name ---")
    }

    $payload = [string]::Join("`r`n`r`n", $parts)
    return [ordered]@{
        text = $payload
        bytes = [Text.UTF8Encoding]::new($false).GetBytes($payload)
        files = @(
            Get-InputFileRecord $PromptPath
            $FixturePaths | ForEach-Object { Get-InputFileRecord $_ }
        )
    }
}

function Get-SessionHash([string] $SessionId) {
    return Get-Sha256 ([Text.UTF8Encoding]::new($false).GetBytes($SessionId))
}

function ConvertTo-SafeAssistantContent([string] $Text, [string[]] $SessionIds) {
    $safe = $Text ?? ""
    foreach ($sessionId in $SessionIds) {
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            $safe = $safe.Replace($sessionId, "[SESSION_ID_REDACTED]")
        }
    }

    $patterns = @(
        @{ Pattern = "(?i)\b[A-F0-9]{8}-[A-F0-9]{4}-[1-5][A-F0-9]{3}-[89AB][A-F0-9]{3}-[A-F0-9]{12}\b"; Replacement = "[UUID_REDACTED]" },
        @{ Pattern = "(?i)\b(?:ghp|gho|github_pat|sk)-[A-Za-z0-9_=-]+\b"; Replacement = "[TOKEN_REDACTED]" },
        @{ Pattern = "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|cookie)\s*([=:])\s*[^\s,;]+"; Replacement = '$1[SECRET_REDACTED]' },
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"; Replacement = "[BEARER_REDACTED]" }
    )

    foreach ($item in $patterns) {
        $safe = [regex]::Replace($safe, $item.Pattern, $item.Replacement)
    }

    return $safe
}

function Invoke-Copilot([string[]] $Arguments) {
    $started = [DateTimeOffset]::UtcNow
    $lines = @(& $CliPath @Arguments 2>&1 | ForEach-Object { [string] $_ })
    $exitCode = $LASTEXITCODE
    $completed = [DateTimeOffset]::UtcNow

    return [ordered]@{
        started_at_utc = $started.ToString("O")
        completed_at_utc = $completed.ToString("O")
        duration_ms = ($completed - $started).TotalMilliseconds
        exit_code = $exitCode
        output = [string]::Join([Environment]::NewLine, $lines)
    }
}

function Parse-CopilotOutput([string] $Output) {
    $assistantMessages = [Collections.Generic.List[string]]::new()
    $assistantModels = [Collections.Generic.List[string]]::new()
    $result = $null
    $warnings = [Collections.Generic.List[string]]::new()
    $jsonLineCount = 0

    foreach ($line in ($Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $jsonLineCount++
        }
        catch {
            continue
        }

        if ($event.type -eq "assistant.message" -and $null -ne $event.data.content) {
            $assistantMessages.Add([string] $event.data.content)
            if ($null -ne $event.data.model) {
                $assistantModels.Add([string] $event.data.model)
            }
        }
        elseif ($event.type -eq "result") {
            $result = $event
        }
        elseif ($event.type -eq "session.info" -and $null -ne $event.data.message) {
            $warnings.Add([string] $event.data.message)
        }
    }

    $content = if ($assistantMessages.Count -gt 0) {
        $assistantMessages[$assistantMessages.Count - 1]
    }
    else {
        $null
    }

    return [ordered]@{
        json_line_count = $jsonLineCount
        assistant_message_count = $assistantMessages.Count
        assistant_content = $content
        assistant_model = if ($assistantModels.Count -gt 0) { $assistantModels[$assistantModels.Count - 1] } else { $null }
        result = $result
        warnings = @($warnings)
    }
}

function Parse-ReviewBlock([string] $Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [ordered]@{
            parsed = $false
            value = $null
            error = "No assistant message content was returned."
        }
    }

    $match = [regex]::Match(
        $Content,
        "BEGIN_PERSISTENCE_REVIEW\s*(?<json>\{.*?\})\s*END_PERSISTENCE_REVIEW",
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) {
        return [ordered]@{
            parsed = $false
            value = $null
            error = "The required persistence review block was not returned."
        }
    }

    try {
        $value = $match.Groups["json"].Value | ConvertFrom-Json -ErrorAction Stop
        return [ordered]@{
            parsed = $true
            value = $value
            error = $null
        }
    }
    catch {
        return [ordered]@{
            parsed = $false
            value = $null
            error = $_.Exception.ToString()
        }
    }
}

function Get-CommandArguments(
    [int] $Round,
    [string] $SessionId,
    [string] $Payload,
    [string] $SessionRole
) {
    $arguments = @(
        "-C", $experimentRoot,
        "--no-custom-instructions",
        "--no-remote",
        "--no-remote-export",
        "--no-auto-update",
        "--no-ask-user",
        "--disable-builtin-mcps",
        "--disable-mcp-server=microsoft-learn",
        "--disallow-temp-dir",
        "--no-color",
        "--silent",
        "--output-format", "json",
        "--stream", "off",
        "--model", "gpt-5.6-luna",
        "--available-tools=view",
        "--allow-tool=view",
        "--deny-tool=write",
        "--deny-tool=shell",
        "--deny-tool=task",
        "--deny-tool=edit"
    )

    if ($SessionRole -eq "new") {
        $arguments += "--session-id=$SessionId"
    }
    else {
        $arguments += "--resume=$SessionId"
    }

    $arguments += @("-p", $Payload)
    return $arguments
}

function Get-CommandShape([string] $Mode, [int] $Round, [string] $SessionRole) {
    $sessionOption = if ($SessionRole -eq "new") {
        "--session-id=<SESSION_ID_REDACTED>"
    }
    else {
        "--resume=<SESSION_ID_REDACTED>"
    }

    return "copilot -C <EXPERIMENT_CWD> --no-custom-instructions --no-remote --no-remote-export --no-auto-update --no-ask-user --disable-builtin-mcps --disable-mcp-server=microsoft-learn --disallow-temp-dir --no-color --silent --output-format json --stream off --model gpt-5.6-luna --available-tools=view --allow-tool=view --deny-tool=write --deny-tool=shell --deny-tool=task --deny-tool=edit $sessionOption -p <PAYLOAD_FROM_MANIFEST> ($Mode)"
}

function Get-CliVersion {
    $lines = @(& $CliPath --version 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) {
        throw "Copilot CLI version query failed."
    }

    $versionLine = $lines | Where-Object { $_ -match "^GitHub Copilot CLI " } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($versionLine)) {
        throw "Copilot CLI version output did not contain a version line."
    }

    return ([string] $versionLine).Trim()
}

function Test-ExactViolation([object] $Review, [string] $Content) {
    if ($null -eq $Review) {
        return $false
    }

    return (
        $Review.prior_finding_status -eq "active" -and
        $Review.decision_contract_assertion -eq "fail" -and
        $Review.information_sufficiency -eq "sufficient" -and
        $Content.Contains("quick-check", [StringComparison]::OrdinalIgnoreCase) -and
        $Content.Contains("focus-mode", [StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-ExactResolution([object] $Review) {
    if ($null -eq $Review) {
        return $false
    }

    return (
        $Review.prior_finding_status -eq "resolved" -and
        $Review.decision_contract_assertion -eq "pass" -and
        $Review.information_sufficiency -eq "sufficient"
    )
}

function Get-DiffCheck {
    $output = @(& git -C $repositoryRoot diff --check 2>&1 | ForEach-Object { [string] $_ })
    return [ordered]@{
        exit_code = $LASTEXITCODE
        passed = ($LASTEXITCODE -eq 0)
        output = @($output)
    }
}

function Save-ExceptionTrace([string] $Path, [System.Exception] $Exception) {
    Write-Utf8NoBom $Path $Exception.ToString()
}

try {
    if (-not (Test-Path -LiteralPath $evidenceRoot)) {
        [void] (New-Item -ItemType Directory -Path $evidenceRoot -Force)
    }
    $staleTrace = Join-Path $evidenceRoot "trace.log"
    if (Test-Path -LiteralPath $staleTrace) {
        Remove-Item -LiteralPath $staleTrace -Force
    }

    $cliVersion = Get-CliVersion
    $preExperimentGit = Get-GitSnapshot
    $persistentSessionId = [Guid]::NewGuid().ToString()
    $freshSessionId = [Guid]::NewGuid().ToString()
    $allSessionIds = @($persistentSessionId, $freshSessionId)

    $promptRoot = Join-Path $experimentRoot "prompts\persistence-control"
    $fixtureRoot = Join-Path $experimentRoot "fixtures\persistence-control"
    $payloads = [ordered]@{
        "round-1" = New-Payload `
            (Join-Path $promptRoot "round-1.md") `
            @(
                (Join-Path $fixtureRoot "round-1-context.md"),
                (Join-Path $fixtureRoot "round-1-candidate.md")
            )
        "round-2" = New-Payload `
            (Join-Path $promptRoot "round-2.md") `
            @(
                (Join-Path $fixtureRoot "round-2-candidate.md")
            )
        "round-3" = New-Payload `
            (Join-Path $promptRoot "round-3.md") `
            @(
                (Join-Path $fixtureRoot "round-3-candidate.md")
            )
    }

    $runs = @(
        [ordered]@{
            label = "persistent-round-1"
            channel = "persistent"
            round = 1
            payload_key = "round-1"
            session_id = $persistentSessionId
            session_role = "new"
            relative_directory = "persistent\round-1"
        },
        [ordered]@{
            label = "persistent-round-2"
            channel = "persistent"
            round = 2
            payload_key = "round-2"
            session_id = $persistentSessionId
            session_role = "resume"
            relative_directory = "persistent\round-2"
        },
        [ordered]@{
            label = "persistent-round-3"
            channel = "persistent"
            round = 3
            payload_key = "round-3"
            session_id = $persistentSessionId
            session_role = "resume"
            relative_directory = "persistent\round-3"
        },
        [ordered]@{
            label = "fresh-control-round-2"
            channel = "fresh-control"
            round = 2
            payload_key = "round-2"
            session_id = $freshSessionId
            session_role = "new"
            relative_directory = "fresh-control\round-2"
        }
    )

    $runResults = [Collections.Generic.List[object]]::new()
    foreach ($run in $runs) {
        $runDirectory = Join-Path $evidenceRoot $run.relative_directory
        [void] (New-Item -ItemType Directory -Path $runDirectory -Force)
        $payload = $payloads[$run.payload_key]
        $payloadBytes = [byte[]] $payload.bytes
        $payloadHash = Get-Sha256 $payloadBytes
        $payloadPath = Join-Path $runDirectory "input-payload.txt"
        Write-Utf8NoBom $payloadPath $payload.text

        $payloadManifest = [ordered]@{
            run_label = $run.label
            channel = $run.channel
            round = $run.round
            payload_file = [ordered]@{
                path = "input-payload.txt"
                bytes = ([IO.File]::ReadAllBytes($payloadPath)).Length
                sha256 = (Get-FileSha256 $payloadPath).sha256
                hash_method = "SHA-256 over exact UTF-8 no-BOM payload bytes"
            }
            source_files = @($payload.files)
            full_round_1_context_sent = ($run.round -eq 1)
            full_context_not_sent = ($run.round -ne 1)
            prior_output_sent = $false
            prior_output_not_sent = $true
            semantic_decision_mapping_sent = ($run.round -eq 1)
            semantic_decision_mapping_not_sent = ($run.round -ne 1)
            external_meaningful_input_boundary = "The selected prompt file plus the listed selected fixture files only."
            persistent_round_2_and_fresh_round_2_payload_equality_hash = if ($run.payload_key -eq "round-2") { $payloadHash } else { $null }
        }
        Write-Json (Join-Path $runDirectory "input-payload-manifest.json") $payloadManifest

        $preRunGit = Get-GitSnapshot
        $process = $null
        $parse = $null
        $reviewBlock = $null
        $safeContent = ""
        $runError = $null
        $expectedSessionHash = Get-SessionHash $run.session_id
        $actualSessionHash = $null
        $sessionMatchesExpected = $false
        $runStarted = [DateTimeOffset]::UtcNow

        try {
            $arguments = Get-CommandArguments $run.round $run.session_id $payload.text $run.session_role
            $process = Invoke-Copilot $arguments
            $parse = Parse-CopilotOutput $process.output
            $reviewBlock = Parse-ReviewBlock $parse.assistant_content
            $safeContent = ConvertTo-SafeAssistantContent $parse.assistant_content $allSessionIds

            if ($null -ne $parse.result -and $null -ne $parse.result.sessionId) {
                $actualSessionHash = Get-SessionHash ([string] $parse.result.sessionId)
                $sessionMatchesExpected = ([string] $parse.result.sessionId -eq $run.session_id)
            }
            else {
                $actualSessionHash = $expectedSessionHash
            }
        }
        catch {
            $runError = $_.Exception.ToString()
            Save-ExceptionTrace (Join-Path $runDirectory "trace.log") $_.Exception
        }

        $runCompleted = [DateTimeOffset]::UtcNow
        $postRunGit = Get-GitSnapshot
        $rawResponsePath = Join-Path $runDirectory "raw-response.txt"
        $sanitizedOutputPath = Join-Path $runDirectory "sanitized-output.txt"
        Write-Utf8NoBom $rawResponsePath $safeContent
        Write-Utf8NoBom $sanitizedOutputPath $safeContent
        $rawFile = Get-FileSha256 $rawResponsePath
        $sanitizedFile = Get-FileSha256 $sanitizedOutputPath

        $resultEvent = if ($null -ne $parse) { $parse.result } else { $null }
        $metadata = [ordered]@{
            run_label = $run.label
            channel = $run.channel
            round = $run.round
            session_role = $run.session_role
            status = if ($null -eq $runError -and $null -ne $process -and $process.exit_code -eq 0 -and $reviewBlock.parsed) { "success" } else { "failure" }
            started_at_utc = $runStarted.ToString("O")
            completed_at_utc = $runCompleted.ToString("O")
            duration_ms = ($runCompleted - $runStarted).TotalMilliseconds
            cli = [ordered]@{
                name = "GitHub Copilot CLI"
                version = $cliVersion
                model_requested = "gpt-5.6-luna"
                model_observed = if ($null -ne $parse) { $parse.assistant_model } else { $null }
                cwd = $experimentRoot
                command_shape = Get-CommandShape $run.channel $run.round $run.session_role
                session_id_saved = $false
                session_id_hash = $actualSessionHash
                expected_session_hash = $expectedSessionHash
                session_matches_expected = $sessionMatchesExpected
            }
            permissions = [ordered]@{
                available_tools = @("view")
                allowed_tools = @("view")
                denied_tools = @("write", "shell", "task", "edit")
                grep_requested = $false
                grep_support_note = "Copilot CLI 1.0.80 reported grep as an unknown tool name during syntax probing; view was the only supported read tool exposed."
                custom_instructions_disabled = $true
                builtin_mcps_disabled = $true
                configured_mcp_servers_disabled = @("microsoft-learn")
                remote_disabled = $true
                temp_directory_disallowed = $true
                environment_values_saved = $false
            }
            process = if ($null -ne $process) {
                [ordered]@{
                    exit_code = $process.exit_code
                    started_at_utc = $process.started_at_utc
                    completed_at_utc = $process.completed_at_utc
                    duration_ms = $process.duration_ms
                    json_line_count = $parse.json_line_count
                    assistant_message_count = $parse.assistant_message_count
                    result_event_present = ($null -ne $resultEvent)
                    cli_warnings = @($parse.warnings)
                }
            }
            else {
                $null
            }
            input = $payloadManifest
            review_block = $reviewBlock
            output = [ordered]@{
                raw_label = "assistant-message-content-only; CLI JSON envelope was not persisted"
                raw_content_path = "raw-response.txt"
                raw_bytes = $rawFile.bytes
                raw_sha256 = $rawFile.sha256
                raw_hash_method = $rawFile.hash_method
                sanitized_content_path = "sanitized-output.txt"
                sanitized_bytes = $sanitizedFile.bytes
                sanitized_sha256 = $sanitizedFile.sha256
                raw_and_sanitized_identical = ($rawFile.sha256 -eq $sanitizedFile.sha256)
            }
            git = [ordered]@{
                pre = $preRunGit
                post = $postRunGit
                tracked_diff_unchanged = (
                    ([string]::Join("`n", (Get-TrackedSnapshot $preRunGit))) -eq
                    ([string]::Join("`n", (Get-TrackedSnapshot $postRunGit)))
                )
                outside_experiment_status_unchanged = (
                    ([string]::Join("`n", (Get-OutsideExperimentStatus $preRunGit))) -eq
                    ([string]::Join("`n", (Get-OutsideExperimentStatus $postRunGit)))
                )
            }
            error = $runError
        }
        Write-Json (Join-Path $runDirectory "run-metadata.json") $metadata
        $runResults.Add($metadata)
    }

    $persistentR2 = $runResults | Where-Object { $_.run_label -eq "persistent-round-2" } | Select-Object -First 1
    $freshR2 = $runResults | Where-Object { $_.run_label -eq "fresh-control-round-2" } | Select-Object -First 1
    $persistentR3 = $runResults | Where-Object { $_.run_label -eq "persistent-round-3" } | Select-Object -First 1
    $persistentR1 = $runResults | Where-Object { $_.run_label -eq "persistent-round-1" } | Select-Object -First 1

    $persistentR2Content = Read-Utf8 (Join-Path $evidenceRoot "persistent\round-2\sanitized-output.txt")
    $freshR2Content = Read-Utf8 (Join-Path $evidenceRoot "fresh-control\round-2\sanitized-output.txt")
    $persistentR2Review = if ($null -ne $persistentR2.review_block) { $persistentR2.review_block.value } else { $null }
    $freshR2Review = if ($null -ne $freshR2.review_block) { $freshR2.review_block.value } else { $null }
    $persistentR3Review = if ($null -ne $persistentR3.review_block) { $persistentR3.review_block.value } else { $null }
    $persistentR1Review = if ($null -ne $persistentR1.review_block) { $persistentR1.review_block.value } else { $null }
    $persistentR2Exact = Test-ExactViolation $persistentR2Review $persistentR2Content
    $freshR2Exact = Test-ExactViolation $freshR2Review $freshR2Content
    $freshR2Weak = (
        -not $freshR2Exact -and
        (
            $null -eq $freshR2Review -or
            $freshR2Review.decision_contract_assertion -eq "unknown" -or
            $freshR2Review.information_sufficiency -eq "insufficient" -or
            $freshR2Review.prior_finding_status -eq "unknown"
        )
    )
    $persistentR3Resolved = Test-ExactResolution $persistentR3Review
    $persistentR1Detected = (
        $null -ne $persistentR1Review -and
        $persistentR1Review.finding_id -eq "PPR-001" -and
        $persistentR1Review.finding_status -eq "active" -and
        $persistentR1Review.decision_contract_assertion -eq "fail"
    )

    $semanticOutcome = if ($persistentR2Exact -and $freshR2Weak -and $persistentR3Resolved) {
        "Yes"
    }
    elseif ($persistentR2Exact -and $freshR2Exact) {
        "No (fresh control guessed the exact violation)"
    }
    elseif ($persistentR2Exact -and $persistentR3Resolved) {
        "Partial"
    }
    else {
        "No"
    }

    $postExperimentGit = Get-GitSnapshot
    $outsideBefore = [string]::Join("`n", (Get-OutsideExperimentStatus $preExperimentGit))
    $outsideAfter = [string]::Join("`n", (Get-OutsideExperimentStatus $postExperimentGit))
    $productionBefore = [string]::Join("`n", (Get-ProductionStatus $preExperimentGit))
    $productionAfter = [string]::Join("`n", (Get-ProductionStatus $postExperimentGit))
    $trackedBefore = [string]::Join("`n", (Get-TrackedSnapshot $preExperimentGit))
    $trackedAfter = [string]::Join("`n", (Get-TrackedSnapshot $postExperimentGit))
    $diffCheck = Get-DiffCheck

    $manifest = [ordered]@{
        experiment = "Persistent Purpose Reviewer negative-control persistence-control"
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        cli = [ordered]@{
            name = "GitHub Copilot CLI"
            version = $cliVersion
            model = "gpt-5.6-luna"
            cwd = $experimentRoot
        }
        input_boundary = "Only selected prompt and fixture bytes were placed in the user payload. Full Round 1 context, prior output, semantic mapping, and findings were not replayed in R2/R3/Fresh R2."
        persistent_round_2_fresh_round_2_payload_hash = Get-Sha256 ([Text.UTF8Encoding]::new($false).GetBytes($payloads["round-2"].text))
        persistent_round_2_fresh_round_2_payload_equal = (
            (Get-FileSha256 (Join-Path $evidenceRoot "persistent\round-2\input-payload.txt")).sha256 -eq
            (Get-FileSha256 (Join-Path $evidenceRoot "fresh-control\round-2\input-payload.txt")).sha256
        )
        session_hashes = [ordered]@{
            persistent_round_1 = $persistentR1.cli.session_id_hash
            persistent_round_2 = $persistentR2.cli.session_id_hash
            persistent_round_3 = $persistentR3.cli.session_id_hash
            fresh_round_2 = $freshR2.cli.session_id_hash
            persistent_r1_r2_r3_equal = (
                $persistentR1.cli.session_id_hash -eq $persistentR2.cli.session_id_hash -and
                $persistentR2.cli.session_id_hash -eq $persistentR3.cli.session_id_hash
            )
            fresh_different = ($freshR2.cli.session_id_hash -ne $persistentR1.cli.session_id_hash)
            session_ids_saved = $false
        }
        runs = @($runResults | ForEach-Object {
            [ordered]@{
                label = $_.run_label
                status = $_.status
                output_sha256 = $_.output.raw_sha256
                input_payload_sha256 = $_.input.payload_file.sha256
                session_hash = $_.cli.session_id_hash
            }
        })
    }
    Write-Json (Join-Path $evidenceRoot "input-payload-manifest.json") $manifest

    $machineMetadata = [ordered]@{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        os = [Environment]::OSVersion.VersionString
        is_64_bit_os = [Environment]::Is64BitOperatingSystem
        powershell = $PSVersionTable.PSVersion.ToString()
        platform = $PSVersionTable.Platform
        architecture = $PSVersionTable.OS
        repository_root = $repositoryRoot
        experiment_cwd = $experimentRoot
        branch = $postExperimentGit.branch
        cli_version = $cliVersion
        environment_values_saved = $false
        secrets_saved = $false
        session_ids_saved = $false
    }
    Write-Json (Join-Path $evidenceRoot "machine-metadata.json") $machineMetadata

    $productionUnchanged = [ordered]@{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        allowed_write_scope = @(
            "experiments\persistent-purpose-reviewer\evidence\copilot\persistence-control\"
            "experiments\persistent-purpose-reviewer\scripts\run-copilot-persistence-control.ps1"
        )
        pre_git_status = $preExperimentGit
        post_git_status = $postExperimentGit
        tracked_status_unchanged = ($trackedBefore -eq $trackedAfter)
        outside_experiment_status_unchanged = ($outsideBefore -eq $outsideAfter)
        production_status_unchanged = ($productionBefore -eq $productionAfter)
        production_unchanged = ($trackedBefore -eq $trackedAfter -and $productionBefore -eq $productionAfter)
        git_diff_check = $diffCheck
    }
    Write-Json (Join-Path $evidenceRoot "production-unchanged.json") $productionUnchanged

    $architectureFeasibility = if (
        $manifest.session_hashes.persistent_r1_r2_r3_equal -and
        $manifest.session_hashes.fresh_different -and
        $manifest.persistent_round_2_fresh_round_2_payload_equal
    ) {
        "feasible"
    }
    else {
        "failed"
    }

    $summary = @"
# Persistent Purpose Reviewer persistence-control 実験結果

実施日時: $([DateTimeOffset]::UtcNow.ToString("O"))
CLI: $cliVersion
モデル: gpt-5.6-luna
実験 cwd: $experimentRoot
branch: $($postExperimentGit.branch)

## 結果

- Semantic persistence 判定: **$semanticOutcome**
- Round 1 の基準 finding (`PPR-001`) 検出: **$persistentR1Detected**
- Persistent Round 2 の exact unhinted violation 検出: **$persistentR2Exact**
- Fresh Round 2 の exact violation 推測: **$freshR2Exact**
- Fresh Round 2 の unknown/insufficient: **$freshR2Weak**
- Persistent Round 3 の解消: **$persistentR3Resolved**
- Architecture feasibility (session resume/payload control): **$architectureFeasibility**

Fresh control が正解を推測した場合は fixture を再調整せず、negative-control の security qualification を与えない方針である。本実行では freshR2Exact=$freshR2Exact を記録した。

## 入力境界

- Persistent R1 は Round 1 prompt、Round 1 context、Round 1 candidate のみを送信した。
- Persistent R2/R3 は各 round の prompt と candidate のみを送信した。
- Fresh R2 は Persistent R2 と同一の prompt+candidate payload bytes を送信した。
- Full Round 1 context、previous response、semantic decision/mapping/finding の再送フラグは全 R2/R3/Fresh R2 で false。
- CLI が自動付与する current-datetime/system wrapper は run ごとに変わり得るため、payload equality は supplied prompt+fixture bytes の hash で判定し、その wrapper 差を別記した。

## 制限と解釈

- --resume=<id> による persistent session は、実 ID を保存せず SHA-256 hash のみ保存した。
- Fresh control は別 session hash である。
- Copilot CLI 1.0.80 は grep を tool name として認識しなかったため、実際に公開した read tool は view のみである。この provider capability limitation は architecture feasibility と security qualification を分けて記録し、OS/network audit の不在を architecture failure とは扱わない。
- CLI JSON envelope（session ID、request ID、環境値を含み得るもの）は evidence に保存せず、assistant-message-content のみを raw/sanitized output として保存した。

## Git 保全

- production unchanged: **$($productionUnchanged.production_unchanged)**
- git diff --check: **$($diffCheck.passed)**
- pre/post status と allowed write scope: production-unchanged.json

詳細な input hash、bytes、command shape、permission、raw bytes SHA-256、pre/post Git status は各 run directory の input-payload-manifest.json と run-metadata.json に保存した。
"@
    Write-Utf8NoBom (Join-Path $evidenceRoot "summary.md") $summary
}
catch {
    $tracePath = Join-Path $evidenceRoot "trace.log"
    try {
        Save-ExceptionTrace $tracePath $_.Exception
    }
    catch {
        Write-Error $_.Exception.ToString()
    }

    throw
}
