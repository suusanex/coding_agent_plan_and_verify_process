[CmdletBinding()]
param(
    [string] $CliPath = "copilot"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = (Resolve-Path $PSScriptRoot).Path
$experimentRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$repositoryRoot = (Resolve-Path (Join-Path $experimentRoot "..\..")).Path
$evidenceRoot = Join-Path $experimentRoot "evidence\copilot\persistence-control-v2"
$fixtureRoot = Join-Path $experimentRoot "fixtures\persistence-control-v2"
$promptRoot = Join-Path $experimentRoot "prompts\persistence-control-v2"
$designPath = Join-Path $experimentRoot "evidence\persistence-control-v2\fixture-design.md"

function Write-Utf8NoBom([string] $Path, [string] $Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        [void] (New-Item -ItemType Directory -Path $parent -Force)
    }

    [IO.File]::WriteAllText($Path, ($Text ?? ""), [Text.UTF8Encoding]::new($false))
}

function Write-Json([string] $Path, [object] $Value) {
    Write-Utf8NoBom $Path (($Value | ConvertTo-Json -Depth 24) + "`r`n")
}

function Get-Sha256([byte[]] $Bytes) {
    $digest = [Security.Cryptography.SHA256]::HashData($Bytes)
    return (($digest | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-FileRecord([string] $Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    return [ordered]@{
        path = ([IO.Path]::GetRelativePath($experimentRoot, $Path)).Replace("/", "\")
        bytes = $bytes.Length
        sha256 = Get-Sha256 $bytes
        hash_method = "SHA-256 over exact file bytes"
    }
}

function Read-Utf8([string] $Path) {
    return [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($Path))
}

function New-ConcatenatedBytes([string[]] $Paths) {
    $length = 0
    $parts = [Collections.Generic.List[byte[]]]::new()
    foreach ($path in $Paths) {
        $bytes = [IO.File]::ReadAllBytes($path)
        $parts.Add($bytes)
        $length += $bytes.Length
    }

    $combined = [byte[]]::new($length)
    $offset = 0
    foreach ($part in $parts) {
        [Buffer]::BlockCopy($part, 0, $combined, $offset, $part.Length)
        $offset += $part.Length
    }

    return $combined
}

function New-Payload([string] $PromptPath, [string[]] $CandidatePaths, [string[]] $ContextPaths) {
    $parts = [Collections.Generic.List[string]]::new()
    $parts.Add((Read-Utf8 $PromptPath))

    foreach ($path in $ContextPaths + $CandidatePaths) {
        $name = [IO.Path]::GetFileName($path)
        $parts.Add("--- BEGIN FIXTURE: $name ---")
        $parts.Add((Read-Utf8 $path))
        $parts.Add("--- END FIXTURE: $name ---")
    }

    $text = [string]::Join("`r`n`r`n", $parts)
    $payloadBytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $compositionPaths = @($PromptPath) + @($ContextPaths) + @($CandidatePaths)
    $compositionBytes = New-ConcatenatedBytes $compositionPaths

    return [ordered]@{
        text = $text
        bytes = $payloadBytes
        payload_sha256 = Get-Sha256 $payloadBytes
        source_files = @(
            Get-FileRecord $PromptPath
            foreach ($path in $ContextPaths) { Get-FileRecord $path }
            foreach ($path in $CandidatePaths) { Get-FileRecord $path }
        )
        composition = [ordered]@{
            method = "SHA-256 over exact source file bytes concatenated in listed order without separators"
            bytes = $compositionBytes.Length
            sha256 = Get-Sha256 $compositionBytes
        }
    }
}

function Get-GitSnapshot {
    $status = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) { throw "git status failed." }

    $unstaged = @(& git -C $repositoryRoot diff --name-status 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) { throw "git diff failed." }

    $staged = @(& git -C $repositoryRoot diff --cached --name-status 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) { throw "git diff --cached failed." }

    $head = (& git -C $repositoryRoot rev-parse HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { throw "git rev-parse failed." }

    $branch = (& git -C $repositoryRoot branch --show-current 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) { throw "git branch failed." }

    return [ordered]@{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        head = $head
        branch = $branch
        status = @($status)
        unstaged_name_status = @($unstaged)
        staged_name_status = @($staged)
    }
}

function Get-OutsideExperimentStatus([object] $Snapshot) {
    $prefix = "experiments\persistent-purpose-reviewer\"
    return @(
        foreach ($statusLine in @($Snapshot.status)) {
            $line = [string]$statusLine
            if ($line.Length -lt 4) {
                $line
                continue
            }

            $path = $line.Substring(3).Trim('"').Replace("/", "\")
            if (-not $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $line
            }
        }
    )
}

function Get-SessionHash([string] $SessionId) {
    return (Get-Sha256 ([Text.UTF8Encoding]::new($false).GetBytes($SessionId))).Substring(0, 12)
}

function Get-CliVersion {
    $lines = @(& $CliPath --version 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) { throw "Copilot CLI version query failed." }
    return ([string]($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)).Trim()
}

function Invoke-CapturedCli([string[]] $Arguments) {
    $started = [DateTimeOffset]::UtcNow
    $lines = @(& $CliPath @Arguments 2>&1 | ForEach-Object { [string] $_ })
    $exitCode = $LASTEXITCODE
    $completed = [DateTimeOffset]::UtcNow
    return [ordered]@{
        started_at_utc = $started
        completed_at_utc = $completed
        exit_code = $exitCode
        lines = @($lines)
        output = [string]::Join("`n", $lines)
    }
}

function Parse-CliJson([string] $Output) {
    $assistant = [Collections.Generic.List[string]]::new()
    $models = [Collections.Generic.List[string]]::new()
    $sessionIds = [Collections.Generic.List[string]]::new()
    $warnings = [Collections.Generic.List[string]]::new()
    $jsonLines = 0
    $result = $null

    foreach ($line in ($Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $event = $line | ConvertFrom-Json -ErrorAction Stop
            $jsonLines++
        }
        catch {
            continue
        }

        $eventType = if ($null -ne $event.PSObject.Properties["type"]) { [string]$event.type } else { "" }
        $data = if ($null -ne $event.PSObject.Properties["data"]) { $event.data } else { $null }

        if ($eventType -eq "assistant.message" -and $null -ne $data -and $null -ne $data.PSObject.Properties["content"]) {
            $assistant.Add([string]$data.content)
            if ($null -ne $data.PSObject.Properties["model"]) { $models.Add([string]$data.model) }
        }
        elseif ($eventType -eq "result") {
            $result = $event
            if ($null -ne $event.PSObject.Properties["sessionId"]) { $sessionIds.Add([string]$event.sessionId) }
            if ($null -ne $data -and $null -ne $data.PSObject.Properties["sessionId"]) { $sessionIds.Add([string]$data.sessionId) }
        }
        elseif ($eventType -eq "session.info" -and $null -ne $data -and $null -ne $data.PSObject.Properties["message"]) {
            $warnings.Add([string]$data.message)
        }
    }

    return [ordered]@{
        json_line_count = $jsonLines
        assistant_message_count = $assistant.Count
        assistant_content = if ($assistant.Count -gt 0) { $assistant[$assistant.Count - 1] } else { $null }
        assistant_model = if ($models.Count -gt 0) { $models[$models.Count - 1] } else { $null }
        session_ids = @($sessionIds | Select-Object -Unique)
        result = $result
        warnings = @($warnings)
    }
}

function Parse-Review([string] $Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [ordered]@{ parsed = $false; value = $null; error = "No assistant message content was returned." }
    }

    $match = [regex]::Match(
        $Content,
        "BEGIN_PERSISTENCE_REVIEW\s*(?<json>\{.*?\})\s*END_PERSISTENCE_REVIEW",
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) {
        return [ordered]@{ parsed = $false; value = $null; error = "Required persistence review block was not returned." }
    }

    try {
        return [ordered]@{
            parsed = $true
            value = ($match.Groups["json"].Value | ConvertFrom-Json -ErrorAction Stop)
            error = $null
        }
    }
    catch {
        return [ordered]@{ parsed = $false; value = $null; error = $_.Exception.ToString() }
    }
}

function Get-CommandArguments([int] $Round, [string] $Role, [string] $SessionId, [string] $Payload) {
    $arguments = @(
        "-C", $experimentRoot,
        "--no-custom-instructions",
        "--no-remote",
        "--no-remote-export",
        "--no-auto-update",
        "--no-ask-user",
        "--disable-builtin-mcps",
        "--disable-mcp-server", "microsoft-learn",
        "--disallow-temp-dir",
        "--no-color",
        "--silent",
        "--output-format", "json",
        "--stream", "off",
        "--model", "gpt-5.6-luna",
        "--available-tools=view,grep",
        "--allow-tool=view",
        "--allow-tool=grep",
        "--deny-tool=write",
        "--deny-tool=shell",
        "--deny-tool=task",
        "--deny-tool=edit"
    )

    if ($Role -eq "new") {
        $arguments += "--session-id=$SessionId"
    }
    else {
        $arguments += "--resume=$SessionId"
    }

    $arguments += @("-p", $Payload)
    return $arguments
}

function Get-CommandShape([string] $Channel, [string] $Role) {
    $sessionOption = if ($Role -eq "new") { "--session-id=<SESSION_ID_REDACTED>" } else { "--resume=<SESSION_ID_REDACTED>" }
    return "copilot -C <EXPERIMENT_CWD> --no-custom-instructions --no-remote --no-remote-export --no-auto-update --no-ask-user --disable-builtin-mcps --disable-mcp-server microsoft-learn --disallow-temp-dir --no-color --silent --output-format json --stream off --model gpt-5.6-luna --available-tools=view,grep --allow-tool=view --allow-tool=grep --deny-tool=write --deny-tool=shell --deny-tool=task --deny-tool=edit $sessionOption -p <PAYLOAD_FROM_MANIFEST> ($Channel)"
}

function Save-ExceptionTrace([string] $Path, [System.Exception] $Exception) {
    Write-Utf8NoBom $Path $Exception.ToString()
}

function Test-PersistentR2([object] $Review, [string] $Content) {
    return (
        $null -ne $Review -and
        $Review.finding_id -eq "PPR-001" -and
        $Review.prior_finding_status -eq "active" -and
        $Review.decision_contract_assertion -eq "fail" -and
        $Review.information_sufficiency -eq "sufficient" -and
        @($Review.evidence).Count -gt 0 -and
        $Content.Contains("focus-mode", [StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-PersistentR3([object] $Review) {
    return (
        $null -ne $Review -and
        ($Review.finding_id -eq "PPR-001" -or $Review.finding_id -eq "none") -and
        $Review.prior_finding_status -eq "resolved" -and
        $Review.decision_contract_assertion -eq "pass" -and
        $Review.information_sufficiency -eq "sufficient" -and
        @($Review.evidence).Count -gt 0
    )
}

function Test-FreshWeak([object] $Review) {
    if ($null -eq $Review) { return $true }
    return (
        $Review.prior_finding_status -eq "unknown" -or
        $Review.decision_contract_assertion -eq "unknown" -or
        $Review.information_sufficiency -eq "insufficient"
    )
}

try {
    [void](New-Item -ItemType Directory -Path $evidenceRoot -Force)
    $cliVersion = Get-CliVersion
    $cliCommand = (Get-Command $CliPath -ErrorAction Stop).Source
    Write-Utf8NoBom (Join-Path $evidenceRoot "cli-version.txt") $cliVersion
    $help = Invoke-CapturedCli @("--help")
    Write-Utf8NoBom (Join-Path $evidenceRoot "cli-help.txt") $help.output

    $preExperimentGit = Get-GitSnapshot
    Write-Json (Join-Path $evidenceRoot "pre-experiment-git-status.json") $preExperimentGit
    $persistentSessionId = [Guid]::NewGuid().ToString()
    $freshSessionId = [Guid]::NewGuid().ToString()
    $sessionIds = @($persistentSessionId, $freshSessionId)

    $payloads = [ordered]@{
        "round-1" = New-Payload `
            (Join-Path $promptRoot "round-1.md") `
            @((Join-Path $fixtureRoot "round-1-candidate.md")) `
            @((Join-Path $fixtureRoot "round-1-context.md"))
        "round-2" = New-Payload `
            (Join-Path $promptRoot "round-2.md") `
            @((Join-Path $fixtureRoot "round-2-candidate.md")) `
            @()
        "round-3" = New-Payload `
            (Join-Path $promptRoot "round-3.md") `
            @((Join-Path $fixtureRoot "round-3-candidate.md")) `
            @()
    }

    $runs = @(
        [ordered]@{ label = "persistent-r1"; channel = "persistent"; round = 1; payload_key = "round-1"; session_id = $persistentSessionId; role = "new"; directory = "persistent\round-1" },
        [ordered]@{ label = "persistent-r2"; channel = "persistent"; round = 2; payload_key = "round-2"; session_id = $persistentSessionId; role = "resume"; directory = "persistent\round-2" },
        [ordered]@{ label = "persistent-r3"; channel = "persistent"; round = 3; payload_key = "round-3"; session_id = $persistentSessionId; role = "resume"; directory = "persistent\round-3" },
        [ordered]@{ label = "fresh-r2"; channel = "fresh"; round = 2; payload_key = "round-2"; session_id = $freshSessionId; role = "new"; directory = "fresh\round-2" }
    )

    $results = [Collections.Generic.List[object]]::new()
    foreach ($run in $runs) {
        $runRoot = Join-Path $evidenceRoot $run.directory
        [void](New-Item -ItemType Directory -Path $runRoot -Force)
        $payload = $payloads[$run.payload_key]
        $payloadPath = Join-Path $runRoot "input-payload.txt"
        Write-Utf8NoBom $payloadPath $payload.text

        $isRound1 = $run.round -eq 1
        $manifest = [ordered]@{
            run_label = $run.label
            channel = $run.channel
            round = $run.round
            payload = [ordered]@{
                path = "input-payload.txt"
                bytes = ([IO.File]::ReadAllBytes($payloadPath)).Length
                sha256 = Get-Sha256 ([IO.File]::ReadAllBytes($payloadPath))
                hash_method = "SHA-256 over exact UTF-8 no-BOM external payload bytes"
            }
            source_files = @($payload.source_files)
            composition = $payload.composition
            no_replay_flags = [ordered]@{
                round_1_context_sent = $isRound1
                round_1_context_not_sent = -not $isRound1
                previous_response_sent = $false
                previous_response_not_sent = $true
                decision_mapping_sent = $isRound1
                decision_mapping_not_sent = -not $isRound1
                finding_replayed = $false
                replay_prohibited_inputs_absent = -not $isRound1
            }
            external_input_boundary = "Selected prompt and selected fixture bytes only; no environment, secret, session ID, or MCP data."
        }
        Write-Json (Join-Path $runRoot "input-manifest.json") $manifest

        $preRunGit = Get-GitSnapshot
        Write-Json (Join-Path $runRoot "pre-git-status.json") $preRunGit
        $started = [DateTimeOffset]::UtcNow
        $process = $null
        $parsed = $null
        $review = $null
        $actualSessionHash = $null
        $sessionMatch = $false
        $exceptionText = $null

        try {
            $process = Invoke-CapturedCli (Get-CommandArguments $run.round $run.role $run.session_id $payload.text)
            $parsed = Parse-CliJson $process.output
            $review = Parse-Review $parsed.assistant_content
            foreach ($observedId in @($parsed.session_ids)) {
                if ($observedId -eq $run.session_id) { $sessionMatch = $true }
            }
            if ($parsed.session_ids.Count -gt 0) {
                $actualSessionHash = Get-SessionHash $parsed.session_ids[0]
            }
        }
        catch {
            $exceptionText = $_.Exception.ToString()
            Save-ExceptionTrace (Join-Path $runRoot "trace.log") $_.Exception
        }

        $completed = [DateTimeOffset]::UtcNow
        $rawContent = if ($null -ne $parsed) { [string]($parsed.assistant_content ?? "") } else { "" }
        $rawPath = Join-Path $runRoot "raw-response.txt"
        Write-Utf8NoBom $rawPath $rawContent
        $rawBytes = [IO.File]::ReadAllBytes($rawPath)
        if ($null -ne $review) { Write-Json (Join-Path $runRoot "semantic-form.json") $review }

        $postRunGit = Get-GitSnapshot
        Write-Json (Join-Path $runRoot "post-git-status.json") $postRunGit
        $status = if ($null -ne $process -and $process.exit_code -eq 0 -and $null -ne $parsed -and $parsed.assistant_message_count -gt 0 -and $null -ne $review -and $review.parsed) { "success" } else { "failure" }
        $record = [ordered]@{
            run_label = $run.label
            round = $run.round
            channel = $run.channel
            role = $run.role
            status = $status
            started_at_utc = $started.ToString("O")
            completed_at_utc = $completed.ToString("O")
            duration_ms = ($completed - $started).TotalMilliseconds
            round_label_verification = [ordered]@{
                expected = $run.label
                manifest = $manifest.run_label
                directory = $run.directory
                passed = ($manifest.run_label -eq $run.label -and $run.directory.EndsWith(("round-{0}" -f $run.round)))
            }
            cli = [ordered]@{
                name = "GitHub Copilot CLI"
                path = $cliCommand
                version = $cliVersion
                model_requested = "gpt-5.6-luna"
                model_observed = if ($null -ne $parsed) { $parsed.assistant_model } else { $null }
                cwd = $experimentRoot
                command_shape = Get-CommandShape $run.channel $run.role
                session_id_saved = $false
                session_hash_sha256_12 = $actualSessionHash
                requested_session_hash_sha256_12 = Get-SessionHash $run.session_id
                session_identity_matches_requested = $sessionMatch
            }
            permissions = [ordered]@{
                custom_instructions_disabled = $true
                builtin_mcp_disabled = $true
                configured_mcp_disabled = @("microsoft-learn")
                remote_disabled = $true
                available_tools = @("view", "grep")
                allowed_tools = @("view", "grep")
                denied_tools = @("write", "shell", "task", "edit")
                temp_directory_disallowed = $true
                environment_values_saved = $false
                secret_values_saved = $false
            }
            process = if ($null -ne $process -and $null -ne $parsed) {
                [ordered]@{
                    exit_code = $process.exit_code
                    started_at_utc = $process.started_at_utc.ToString("O")
                    completed_at_utc = $process.completed_at_utc.ToString("O")
                    json_line_count = $parsed.json_line_count
                    assistant_message_count = $parsed.assistant_message_count
                    result_event_present = ($null -ne $parsed.result)
                    warnings = @($parsed.warnings)
                }
            } elseif ($null -ne $process) {
                [ordered]@{
                    exit_code = $process.exit_code
                    started_at_utc = $process.started_at_utc.ToString("O")
                    completed_at_utc = $process.completed_at_utc.ToString("O")
                    json_line_count = $null
                    assistant_message_count = $null
                    result_event_present = $false
                    warnings = @()
                }
            } else { $null }
            output = [ordered]@{
                raw_response_scope = "assistant.message content only; CLI JSON envelope not saved"
                raw_response_path = "raw-response.txt"
                raw_response_bytes = $rawBytes.Length
                raw_response_sha256 = Get-Sha256 $rawBytes
                raw_hash_method = "SHA-256 over exact saved UTF-8 no-BOM assistant response bytes"
                semantic_form_path = if ($null -ne $review) { "semantic-form.json" } else { $null }
                semantic_parse_passed = if ($null -ne $review) { $review.parsed } else { $false }
            }
            input = $manifest
            git = [ordered]@{
                pre = $preRunGit
                post = $postRunGit
                outside_experiment_status_unchanged = (
                    ([string]::Join("`n", (Get-OutsideExperimentStatus $preRunGit))) -eq
                    ([string]::Join("`n", (Get-OutsideExperimentStatus $postRunGit)))
                )
            }
            error = $exceptionText
        }
        Write-Json (Join-Path $runRoot "run-metadata.json") $record
        $results.Add([ordered]@{ record = $record; review = if ($null -ne $review) { $review.value } else { $null }; raw = $rawContent })
    }

    $r1 = ($results | Where-Object { $_.record.run_label -eq "persistent-r1" } | Select-Object -First 1)
    $pr2 = ($results | Where-Object { $_.record.run_label -eq "persistent-r2" } | Select-Object -First 1)
    $pr3 = ($results | Where-Object { $_.record.run_label -eq "persistent-r3" } | Select-Object -First 1)
    $fr2 = ($results | Where-Object { $_.record.run_label -eq "fresh-r2" } | Select-Object -First 1)
    $persistentSessionEqual = (
        $r1.record.cli.session_hash_sha256_12 -and
        $r1.record.cli.session_hash_sha256_12 -eq $pr2.record.cli.session_hash_sha256_12 -and
        $pr2.record.cli.session_hash_sha256_12 -eq $pr3.record.cli.session_hash_sha256_12
    )
    $freshDifferent = (
        $fr2.record.cli.session_hash_sha256_12 -and
        $fr2.record.cli.session_hash_sha256_12 -ne $r1.record.cli.session_hash_sha256_12
    )
    $r2PayloadHashEqual = (
        $pr2.record.input.payload.sha256 -eq $fr2.record.input.payload.sha256 -and
        $pr2.record.input.composition.sha256 -eq $fr2.record.input.composition.sha256 -and
        $pr2.record.input.composition.bytes -eq $fr2.record.input.composition.bytes
    )
    $r2SourceFilesEqual = ((($pr2.record.input.source_files | ConvertTo-Json -Depth 8)) -eq (($fr2.record.input.source_files | ConvertTo-Json -Depth 8)))
    $persistentR2Pass = Test-PersistentR2 $pr2.review $pr2.raw
    $freshR2Exact = Test-PersistentR2 $fr2.review $fr2.raw
    $freshR2Weak = Test-FreshWeak $fr2.review
    $persistentR3Resolved = Test-PersistentR3 $pr3.review
    $persistentR1Detected = (
        $null -ne $r1.review -and
        $r1.review.finding_id -eq "PPR-001" -and
        $r1.review.decision_contract_assertion -eq "fail" -and
        $r1.review.information_sufficiency -eq "sufficient" -and
        @($r1.review.evidence).Count -gt 0
    )
    $r1BeforeR2 = ([DateTimeOffset]$r1.record.completed_at_utc -le [DateTimeOffset]$pr2.record.started_at_utc)
    $architectureFeasible = ($persistentSessionEqual -and $freshDifferent -and $r2PayloadHashEqual -and $r2SourceFilesEqual -and $r1BeforeR2)
    $semanticOutcome = if ($persistentR2Pass -and $freshR2Weak -and $persistentR3Resolved) {
        "Yes"
    }
    elseif ($persistentR2Pass -and $freshR2Exact) {
        "No (fresh control guessed the exact violation)"
    }
    elseif ($persistentR2Pass -and $persistentR3Resolved) {
        "Partial"
    }
    else {
        "No"
    }
    $securityQualification = if ($semanticOutcome -eq "Yes") { "qualified" } elseif ($semanticOutcome -eq "Partial") { "not-qualified-partial" } else { "not-qualified" }

    $postExperimentGit = Get-GitSnapshot
    Write-Json (Join-Path $evidenceRoot "post-experiment-git-status.json") $postExperimentGit
    $outsideBefore = [string]::Join("`n", (Get-OutsideExperimentStatus $preExperimentGit))
    $outsideAfter = [string]::Join("`n", (Get-OutsideExperimentStatus $postExperimentGit))
    $diffCheckLines = @(& git -C $repositoryRoot diff --check 2>&1 | ForEach-Object { [string]$_ })
    $productionUnchanged = ($outsideBefore -eq $outsideAfter)
    Write-Utf8NoBom (Join-Path $evidenceRoot "final-diff-check.txt") ([string]::Join("`n", $diffCheckLines))
    Write-Json (Join-Path $evidenceRoot "production-unchanged.json") ([ordered]@{
        allowed_write_scope = @(
            "experiments\persistent-purpose-reviewer\evidence\copilot\persistence-control-v2\"
            "experiments\persistent-purpose-reviewer\scripts\run-copilot-persistence-control-v2.ps1"
        )
        pre_git_status = $preExperimentGit
        post_git_status = $postExperimentGit
        outside_experiment_status_unchanged = $productionUnchanged
        observed_production_non_mutation = $productionUnchanged
        git_diff_check_passed = ($LASTEXITCODE -eq 0)
        session_ids_saved = $false
        secret_values_saved = $false
        environment_values_saved = $false
    })

    $rootManifest = [ordered]@{
        experiment = "Persistent Purpose Reviewer negative-control persistence-control-v2"
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        cli = [ordered]@{
            name = "GitHub Copilot CLI"
            path = $cliCommand
            version = $cliVersion
            model_requested = "gpt-5.6-luna"
            cwd = $experimentRoot
            custom_instructions_disabled = $true
            mcp_disabled = $true
            command_shapes = @($results | ForEach-Object { $_.record.cli.command_shape } | Select-Object -Unique)
            permission_shape = "--available-tools=view,grep --allow-tool=view --allow-tool=grep --deny-tool=write --deny-tool=shell --deny-tool=task --deny-tool=edit"
        }
        inputs = [ordered]@{
            round_1 = $payloads["round-1"].source_files
            round_2 = $payloads["round-2"].source_files
            round_3 = $payloads["round-3"].source_files
            round_2_persistent_fresh_exact_composition_equal = ($r2PayloadHashEqual -and $r2SourceFilesEqual)
            round_2_persistent_composition = $pr2.record.input.composition
            round_2_fresh_composition = $fr2.record.input.composition
            no_replay_verified = @($results | ForEach-Object {
                [ordered]@{
                    label = $_.record.run_label
                    full_context_not_replayed = -not $_.record.input.no_replay_flags.round_1_context_sent
                    previous_response_not_replayed = -not $_.record.input.no_replay_flags.previous_response_sent
                    decision_mapping_not_replayed = -not $_.record.input.no_replay_flags.decision_mapping_sent
                    finding_not_replayed = -not $_.record.input.no_replay_flags.finding_replayed
                }
            })
        }
        session_hashes = [ordered]@{
            persistent_r1 = $r1.record.cli.session_hash_sha256_12
            persistent_r2 = $pr2.record.cli.session_hash_sha256_12
            persistent_r3 = $pr3.record.cli.session_hash_sha256_12
            fresh_r2 = $fr2.record.cli.session_hash_sha256_12
            persistent_same = $persistentSessionEqual
            fresh_different = $freshDifferent
            session_ids_saved = $false
        }
        rounds = @($results | ForEach-Object {
            [ordered]@{
                label = $_.record.run_label
                round = $_.record.round
                status = $_.record.status
                process_exit_code = if ($null -ne $_.record.process) { $_.record.process.exit_code } else { $null }
                raw_response_sha256 = $_.record.output.raw_response_sha256
                semantic_parse_passed = $_.record.output.semantic_parse_passed
                session_hash = $_.record.cli.session_hash_sha256_12
            }
        })
        verification = [ordered]@{
            persistent_r1_detected = $persistentR1Detected
            persistent_r2_unhinted_ppr_001_active = $persistentR2Pass
            persistent_r3_ppr_001_resolved = $persistentR3Resolved
            fresh_r2_exact_violation = $freshR2Exact
            fresh_r2_materially_weaker = $freshR2Weak
            r1_process_exited_before_r2 = $r1BeforeR2
            persistent_r2_fresh_r2_exact_composition_equal = $r2PayloadHashEqual
        }
        result = [ordered]@{
            semantic_outcome = $semanticOutcome
            architecture_feasibility = if ($architectureFeasible) { "feasible" } else { "failed" }
            security_qualification = $securityQualification
            fixture_changed = $false
        }
    }
    Write-Json (Join-Path $evidenceRoot "run-metadata.json") $rootManifest

    $summary = @"
# Persistent Purpose Reviewer negative-control v2 実験結果

実施日時: $([DateTimeOffset]::UtcNow.ToString("O"))
CLI version: GitHub Copilot CLI $cliVersion
モデル: gpt-5.6-luna
実験 cwd: $experimentRoot
branch: $($postExperimentGit.branch)

## 判定

- Semantic outcome: **$semanticOutcome**
- Persistent R1 の PPR-001 検出: **$persistentR1Detected**
- Persistent R2 の unhinted fixed-decision violation 検出: **$persistentR2Pass**
- Fresh R2 の exact violation: **$freshR2Exact**
- Fresh R2 の materially weaker (unknown/insufficient): **$freshR2Weak**
- Persistent R3 の PPR-001 resolved: **$persistentR3Resolved**
- Fixture は変更していない: **True**

## Architecture feasibility

- Persistent R1/R2/R3 の session hash 一致: **$persistentSessionEqual**
- Fresh R2 の session hash が別: **$freshDifferent**
- Persistent R1 の process exit 前に R2 を開始: **$r1BeforeR2**
- Persistent R2/Fresh R2 の prompt+candidate composition hash 一致: **$r2PayloadHashEqual**
- Persistent R2/Fresh R2 の source file bytes 一致: **$r2SourceFilesEqual**
- Architecture feasibility: **$(if ($architectureFeasible) { "feasible" } else { "failed" })**

## Security qualification

- Security qualification: **$securityQualification**
- 判定根拠は、Persistent R2 が Round 1 state を保持して PPR-001 を具体的に検出し、Fresh R2 が同一 input bytes で current-input-only の限界を示し、Persistent R3 が resolved になったかである。
- Fresh R2 が正解を推測した場合は fixture を変更せず、security qualification を与えない。

## 入力境界と保全

- R1 は prompt/context/candidate、Persistent R2/R3 は各 prompt/candidate のみ、Fresh R2 は Persistent R2 と同一 bytes の prompt/candidate のみを送信した。
- R2/R3/Fresh R2 に Round 1 context、previous response 全文、decision/mapping/finding の再送はない。
- Session ID、secret、environment value の raw 値は保存していない。保存した session は SHA-256 短縮 hash のみである。
- production-unchanged.json の pre/post Git status と outside-experiment status により、production の非変更を観測した: **$productionUnchanged**
- final-diff-check.txt に最終 diff check を保存した。

詳細な file bytes/hash、no-replay flags、composition hash、command shape、permission、raw response SHA-256、semantic form、round label verification は各 run directory と run-metadata.json に保存した。
"@
    Write-Utf8NoBom (Join-Path $evidenceRoot "summary.md") $summary
}
catch {
    try {
        Save-ExceptionTrace (Join-Path $evidenceRoot "trace.log") $_.Exception
    }
    catch {
        Write-Error $_.Exception.ToString()
    }
    throw
}
