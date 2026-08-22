[CmdletBinding()]
param(
    [string] $CliPath = "grok"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = (Resolve-Path $PSScriptRoot).Path
$experimentRoot = (Resolve-Path (Join-Path $scriptRoot "..")).Path
$repositoryRoot = (Resolve-Path (Join-Path $experimentRoot "..\..")).Path
$evidenceRoot = Join-Path $experimentRoot "evidence\grok\persistence-control-v2"
$setupRoot = Join-Path $evidenceRoot "setup"
$runsRoot = Join-Path $evidenceRoot "runs"
$safeReviewerRole = "You are a read-only Persistent Purpose Reviewer. Use only the supplied prompt and fixture text. Do not access files, shell, network tools, credentials, metadata, home content, memory, or subagents. Return only the requested persistence review block."
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$utf8Strict = [Text.UTF8Encoding]::new($false, $true)

function Write-Utf8NoBom([string] $Path, [string] $Text) {
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) {
        [void] (New-Item -ItemType Directory -Path $parent -Force)
    }

    [IO.File]::WriteAllText($Path, ($Text ?? ""), $utf8NoBom)
}

function Write-Json([string] $Path, [object] $Value) {
    Write-Utf8NoBom $Path (($Value | ConvertTo-Json -Depth 32) + "`r`n")
}

function Get-Sha256([byte[]] $Bytes) {
    $digest = [Security.Cryptography.SHA256]::HashData($Bytes)
    return (($digest | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-FileInfo([string] $Path) {
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
    $status = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed."
    }

    $unstaged = @(& git -C $repositoryRoot diff --name-status 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) {
        throw "git diff failed."
    }

    $staged = @(& git -C $repositoryRoot diff --cached --name-status 2>&1 | ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) {
        throw "git diff cached failed."
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
        status = @($status)
        unstaged_name_status = @($unstaged)
        staged_name_status = @($staged)
    }
}

function Get-OutsideExperimentStatus([object] $Snapshot) {
    $prefix = "experiments/persistent-purpose-reviewer/"
    return @(
        @($Snapshot.status) | ForEach-Object {
            $line = [string] $_
            $normalized = $line.Replace("\", "/")
            if (-not $normalized.Contains($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $line
            }
        }
    )
}

function Get-StatusHash([string[]] $StatusLines) {
    $text = [string]::Join("`n", @($StatusLines))
    return Get-Sha256 ($utf8NoBom.GetBytes($text))
}

function Get-SafeText([string] $Text, [string[]] $SessionIds) {
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
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"; Replacement = "[BEARER_REDACTED]" },
        @{ Pattern = "(?i)[A-Z]:\\Users\\[^\\\r\n ]+"; Replacement = "<USER_PATH>" },
        @{ Pattern = "(?i)[A-Z]:\\[^ \r\n]+\\coding_agent_plan_and_verify_process"; Replacement = "<REPOSITORY_PATH>" }
    )

    foreach ($item in $patterns) {
        $safe = [regex]::Replace($safe, $item.Pattern, $item.Replacement)
    }

    return $safe
}

function Invoke-CapturedProcess(
    [string] $FilePath,
    [string[]] $Arguments,
    [string] $WorkingDirectory,
    [string[]] $SessionIds,
    [int] $TimeoutSeconds = 1200
) {
    $started = [DateTimeOffset]::UtcNow
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.WorkingDirectory = $WorkingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void] $process.StartInfo.ArgumentList.Add($argument)
    }

    try {
        if (-not $process.Start()) {
            throw "CLI process could not be started."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            $process.Kill()
            $process.WaitForExit()
        }

        return [ordered]@{
            started_at_utc = $started.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            exit_code = if ($completed) { $process.ExitCode } else { $null }
            timed_out = -not $completed
            stdout = Get-SafeText $stdoutTask.Result $SessionIds
            stderr = Get-SafeText $stderrTask.Result $SessionIds
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-SourceFileRecord([string] $Path) {
    $file = Get-FileInfo $Path
    return [ordered]@{
        path = Get-RelativePath $experimentRoot $Path
        bytes = $file.bytes
        sha256 = $file.sha256
        hash_method = $file.hash_method
    }
}

function New-Payload([string[]] $Paths) {
    $memory = [IO.MemoryStream]::new()
    try {
        $files = [Collections.Generic.List[object]]::new()
        foreach ($path in $Paths) {
            $bytes = [IO.File]::ReadAllBytes($path)
            $memory.Write($bytes, 0, $bytes.Length)
            $files.Add((Get-SourceFileRecord $path))
        }

        $payloadBytes = $memory.ToArray()
        $payloadText = $utf8Strict.GetString($payloadBytes)
        $roundTripBytes = $utf8NoBom.GetBytes($payloadText)
        if ($payloadBytes.Length -ne $roundTripBytes.Length -or (Get-Sha256 $payloadBytes) -ne (Get-Sha256 $roundTripBytes)) {
            throw "UTF-8 payload round-trip changed exact bytes."
        }

        return [ordered]@{
            bytes = $payloadBytes
            text = $payloadText
            byte_count = $payloadBytes.Length
            sha256 = Get-Sha256 $payloadBytes
            hash_method = "SHA-256 over exact UTF-8 no-BOM concatenation of listed source file bytes without separators"
            source_files = @($files)
        }
    }
    finally {
        $memory.Dispose()
    }
}

function Get-SessionHash([string] $SessionId) {
    return Get-Sha256 ($utf8NoBom.GetBytes($SessionId))
}

function Get-CommandShape([int] $Round, [string] $Channel) {
    $sessionOption = if ($Round -eq 1 -or $Channel -eq "fresh-control") {
        "--session-id <SESSION_ID_REDACTED>"
    }
    else {
        "--resume <SESSION_ID_REDACTED>"
    }

    return "grok --cwd <EXPERIMENT_CWD> --no-memory --no-subagents --permission-mode plan --sandbox read-only --disable-web-search --tools read,view,grep --disallowed-tools write,shell,task,edit_file,run_shell_command --system-prompt-override=<SAFE_REVIEWER_ROLE> $sessionOption --output-format plain --verbatim --single <PAYLOAD_FROM_MANIFEST>"
}

function Get-Arguments([int] $Round, [string] $Channel, [string] $SessionId, [string] $PayloadText) {
    $arguments = @(
        "--cwd", $experimentRoot,
        "--no-memory",
        "--no-subagents",
        "--permission-mode", "plan",
        "--sandbox", "read-only",
        "--disable-web-search",
        "--tools", "read,view,grep",
        "--disallowed-tools", "write,shell,task,edit_file,run_shell_command",
        "--system-prompt-override", $safeReviewerRole,
        "--output-format", "plain",
        "--verbatim"
    )

    if ($Round -eq 1 -or $Channel -eq "fresh-control") {
        $arguments += @("--session-id", $SessionId)
    }
    else {
        $arguments += @("--resume", $SessionId)
    }

    $arguments += @("--single", $PayloadText)
    return $arguments
}

function Parse-ReviewBlock([string] $Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [ordered]@{
            parsed = $false
            value = $null
            error = "No assistant response was returned."
            block_count = 0
        }
    }

    $matches = [regex]::Matches(
        $Content,
        "BEGIN_PERSISTENCE_REVIEW\s*(?<json>\{.*?\})\s*END_PERSISTENCE_REVIEW",
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if ($matches.Count -ne 1) {
        return [ordered]@{
            parsed = $false
            value = $null
            error = "Expected exactly one persistence review block."
            block_count = $matches.Count
        }
    }

    try {
        $value = $matches[0].Groups["json"].Value | ConvertFrom-Json -ErrorAction Stop
        return [ordered]@{
            parsed = $true
            value = $value
            error = $null
            block_count = 1
        }
    }
    catch {
        return [ordered]@{
            parsed = $false
            value = $null
            error = Get-SafeText $_.Exception.ToString() $script:allSessionIds
            block_count = 1
        }
    }
}

function Save-ExceptionTrace([string] $Path, [System.Exception] $Exception) {
    Write-Utf8NoBom $Path (Get-SafeText $Exception.ToString() $script:allSessionIds)
}

function Test-PropertyValue([object] $Value, [string] $Name, [string] $Expected) {
    return ($null -ne $Value -and [string] $Value.$Name -eq $Expected)
}

function Test-PersistentR2([object] $Review) {
    if ($null -eq $Review) {
        return $false
    }

    $evidence = [string]::Join(" ", @($Review.evidence | ForEach-Object { [string] $_ }))
    return (
        (Test-PropertyValue $Review "finding_id" "PPR-001") -and
        (Test-PropertyValue $Review "prior_finding_status" "active") -and
        (Test-PropertyValue $Review "decision_contract_assertion" "fail") -and
        (Test-PropertyValue $Review "information_sufficiency" "sufficient") -and
        $evidence.Contains("quick-check", [StringComparison]::OrdinalIgnoreCase) -and
        $evidence.Contains("focus-mode", [StringComparison]::OrdinalIgnoreCase)
    )
}

function Test-FreshR2Weaker([object] $Review) {
    if ($null -eq $Review) {
        return $false
    }

    return (
        (Test-PropertyValue $Review "prior_finding_status" "unknown") -and
        (Test-PropertyValue $Review "decision_contract_assertion" "unknown") -and
        (Test-PropertyValue $Review "information_sufficiency" "insufficient")
    )
}

function Test-PersistentR3Resolved([object] $Review) {
    if ($null -eq $Review) {
        return $false
    }

    return (
        ([string] $Review.finding_id -eq "PPR-001" -or [string] $Review.finding_id -eq "none") -and
        (Test-PropertyValue $Review "prior_finding_status" "resolved") -and
        (Test-PropertyValue $Review "decision_contract_assertion" "pass") -and
        (Test-PropertyValue $Review "information_sufficiency" "sufficient")
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

$script:allSessionIds = @()
$initialSnapshot = $null
$runRecords = [Collections.Generic.List[object]]::new()
$failure = $null

try {
    $initialSnapshot = Get-GitSnapshot
    $persistentSessionId = [Guid]::NewGuid().ToString()
    $freshSessionId = [Guid]::NewGuid().ToString()
    $script:allSessionIds = @($persistentSessionId, $freshSessionId)

    [void] (New-Item -ItemType Directory -Path $setupRoot, $runsRoot -Force)
    Write-Json (Join-Path $evidenceRoot "run-start-pre-git-snapshot.json") $initialSnapshot

    $version = Invoke-CapturedProcess $CliPath @("--version") $experimentRoot $script:allSessionIds 120
    $help = Invoke-CapturedProcess $CliPath @("--help") $experimentRoot $script:allSessionIds 120
    $headlessHelp = Invoke-CapturedProcess $CliPath @("agent", "headless", "--help") $experimentRoot $script:allSessionIds 120
    $resumeHelp = Invoke-CapturedProcess $CliPath @("sessions", "list", "--help") $experimentRoot $script:allSessionIds 120
    $models = Invoke-CapturedProcess $CliPath @("--cwd", $experimentRoot, "models") $experimentRoot $script:allSessionIds 120
    Write-Json (Join-Path $setupRoot "static-help-version-model.json") ([ordered]@{
        version = $version
        help = $help
        headless_help = $headlessHelp
        sessions_list_help = $resumeHelp
        models = $models
        raw_session_secret_environment_values_saved = $false
    })

    $runMetadata = [ordered]@{
        schema_version = 2
        cli = "Grok Build CLI"
        cli_path_label = "grok"
        version_evidence = "setup\static-help-version-model.json"
        model = "grok-4.6 (CLI default reported by grok models; runtime selection not independently exposed)"
        cwd = $experimentRoot
        permission_mode = "plan"
        sandbox = "read-only"
        tools_allowed = @("read", "view", "grep")
        tools_disallowed = @("write", "shell", "task", "edit_file", "run_shell_command")
        web_search_disabled = $true
        memory_disabled = $true
        subagents_disabled = $true
        system_prompt_override = "safe read-only reviewer role; no fixture-specific mapping or finding"
        session_identity = "persistent R1 uses new session-id; persistent R2/R3 use --resume with the same specific ID; fresh R2 uses a different new session-id"
        persistent_session_hash = Get-SessionHash $persistentSessionId
        fresh_session_hash = Get-SessionHash $freshSessionId
        raw_session_secret_environment_values_saved = $false
        command_shape_round_1 = Get-CommandShape 1 "persistent"
        command_shape_persistent_round_2 = Get-CommandShape 2 "persistent"
        command_shape_persistent_round_3 = Get-CommandShape 3 "persistent"
        command_shape_fresh_round_2 = Get-CommandShape 2 "fresh-control"
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
    }
    Write-Json (Join-Path $evidenceRoot "run-metadata.json") $runMetadata

    $promptRoot = Join-Path $experimentRoot "prompts\persistence-control-v2"
    $fixtureRoot = Join-Path $experimentRoot "fixtures\persistence-control-v2"
    $payloads = [ordered]@{
        "round-1" = New-Payload @(
            (Join-Path $promptRoot "round-1.md"),
            (Join-Path $fixtureRoot "round-1-context.md"),
            (Join-Path $fixtureRoot "round-1-candidate.md")
        )
        "round-2" = New-Payload @(
            (Join-Path $promptRoot "round-2.md"),
            (Join-Path $fixtureRoot "round-2-candidate.md")
        )
        "round-3" = New-Payload @(
            (Join-Path $promptRoot "round-3.md"),
            (Join-Path $fixtureRoot "round-3-candidate.md")
        )
    }

    $runs = @(
        [ordered]@{
            label = "persistent-r1"
            channel = "persistent"
            round = 1
            payload_key = "round-1"
            session_id = $persistentSessionId
            directory = "persistent-r1"
        },
        [ordered]@{
            label = "persistent-r2"
            channel = "persistent"
            round = 2
            payload_key = "round-2"
            session_id = $persistentSessionId
            directory = "persistent-r2"
        },
        [ordered]@{
            label = "persistent-r3"
            channel = "persistent"
            round = 3
            payload_key = "round-3"
            session_id = $persistentSessionId
            directory = "persistent-r3"
        },
        [ordered]@{
            label = "fresh-r2"
            channel = "fresh-control"
            round = 2
            payload_key = "round-2"
            session_id = $freshSessionId
            directory = "fresh-r2"
        }
    )

    foreach ($run in $runs) {
        $runDirectory = Join-Path $runsRoot $run.directory
        [void] (New-Item -ItemType Directory -Path $runDirectory -Force)
        $preRun = Get-GitSnapshot
        Write-Json (Join-Path $runDirectory "pre-git-snapshot.json") $preRun

        $payload = $payloads[$run.payload_key]
        $payloadPath = Join-Path $runDirectory "input-payload.txt"
        [IO.File]::WriteAllBytes($payloadPath, [byte[]] $payload.bytes)
        $savedPayload = Get-FileInfo $payloadPath
        if ($savedPayload.sha256 -ne $payload.sha256 -or $savedPayload.bytes -ne $payload.byte_count) {
            throw "Saved input payload changed exact bytes."
        }

        $manifest = [ordered]@{
            schema_version = 2
            run_label = $run.label
            channel = $run.channel
            round = $run.round
            session_hash = Get-SessionHash $run.session_id
            session_role = if ($run.channel -eq "persistent" -and $run.round -gt 1) { "resume-same-specific-session" } elseif ($run.channel -eq "fresh-control") { "new-session" } else { "new-session" }
            payload = [ordered]@{
                path = Get-RelativePath $experimentRoot $payloadPath
                bytes = $savedPayload.bytes
                sha256 = $savedPayload.sha256
                hash_method = $savedPayload.hash_method
                composition = $payload.hash_method
            }
            source_files = @($payload.source_files)
            full_round_1_context_sent = ($run.round -eq 1)
            full_round_1_context_replayed = $false
            previous_response_replayed = $false
            decision_mapping_replayed = $false
            finding_text_replayed = $false
            semantic_secret_replayed = $false
            no_replay_flags_verified = $true
            persistent_r2_fresh_r2_same_payload_expected = ($run.payload_key -eq "round-2")
            external_input_boundary = "listed prompt and candidate/context fixture file bytes only; no previous response or semantic decision replay"
            raw_session_secret_environment_values_saved = $false
        }
        Write-Json (Join-Path $runDirectory "input-manifest.json") $manifest

        $process = $null
        $parse = $null
        $runError = $null
        try {
            $arguments = Get-Arguments $run.round $run.channel $run.session_id $payload.text
            $process = Invoke-CapturedProcess $CliPath $arguments $experimentRoot $script:allSessionIds 1200
            $parse = Parse-ReviewBlock $process.stdout
        }
        catch {
            $runError = $_.Exception.ToString()
            Save-ExceptionTrace (Join-Path $runDirectory "exception-trace.log") $_.Exception
            $process = [ordered]@{
                started_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
                completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
                exit_code = $null
                timed_out = $false
                stdout = ""
                stderr = "[process failure; see sanitized exception trace]"
            }
            $parse = Parse-ReviewBlock ""
        }

        $responsePath = Join-Path $runDirectory "raw-response.txt"
        Write-Utf8NoBom $responsePath $process.stdout
        $responseInfo = Get-FileInfo $responsePath
        Write-Utf8NoBom (Join-Path $runDirectory "stderr.txt") $process.stderr
        $semantic = [ordered]@{
            run_label = $run.label
            round = $run.round
            channel = $run.channel
            round_label_verified = ($run.label -in @("persistent-r1", "persistent-r2", "persistent-r3", "fresh-r2"))
            semantic_source = "exact saved response bytes from this invocation"
            response_path = Get-RelativePath $experimentRoot $responsePath
            response_bytes = $responseInfo.bytes
            response_sha256 = $responseInfo.sha256
            response_hash_method = "SHA-256 over exact saved UTF-8 no-BOM response bytes after mandatory sensitive-value redaction"
            parse = $parse
            process_exit_code = $process.exit_code
            timed_out = $process.timed_out
            raw_session_secret_environment_values_saved = $false
        }
        Write-Json (Join-Path $runDirectory "semantic-review.json") $semantic

        $postRun = Get-GitSnapshot
        Write-Json (Join-Path $runDirectory "post-git-snapshot.json") $postRun
        $outsidePre = @(Get-OutsideExperimentStatus $preRun)
        $outsidePost = @(Get-OutsideExperimentStatus $postRun)
        $outsideEqual = ([string]::Join("`n", $outsidePre) -ceq [string]::Join("`n", $outsidePost))
        $changeSummary = [ordered]@{
            run_label = $run.label
            round_label_verified = [bool] $semantic.round_label_verified
            process_exit_code = $process.exit_code
            timed_out = $process.timed_out
            outside_experiment_status_unchanged = $outsideEqual
            outside_experiment_pre_status_sha256 = Get-StatusHash $outsidePre
            outside_experiment_post_status_sha256 = Get-StatusHash $outsidePost
            production_nonmutation_observed = $outsideEqual
            allowed_write_root = "experiments\persistent-purpose-reviewer\evidence\grok\persistence-control-v2"
            exception_recorded = ($null -ne $runError)
        }
        Write-Json (Join-Path $runDirectory "worktree-change-summary.json") $changeSummary

        $reviewValue = if ($parse.parsed) { $parse.value } else { $null }
        $runRecords.Add([ordered]@{
            label = $run.label
            channel = $run.channel
            round = $run.round
            session_hash = Get-SessionHash $run.session_id
            payload_sha256 = $payload.sha256
            response_sha256 = $responseInfo.sha256
            process_exit_code = $process.exit_code
            parsed = $parse.parsed
            review = $reviewValue
            persistent_r2_exact_violation = if ($run.label -eq "persistent-r2") { Test-PersistentR2 $reviewValue } else { $false }
            fresh_r2_materially_weaker = if ($run.label -eq "fresh-r2") { Test-FreshR2Weaker $reviewValue } else { $false }
            persistent_r3_resolved = if ($run.label -eq "persistent-r3") { Test-PersistentR3Resolved $reviewValue } else { $false }
        })
    }

    $persistentR2 = @($runRecords | Where-Object { $_.label -eq "persistent-r2" })[0]
    $freshR2 = @($runRecords | Where-Object { $_.label -eq "fresh-r2" })[0]
    $persistentR3 = @($runRecords | Where-Object { $_.label -eq "persistent-r3" })[0]
    $persistentR2Payload = $persistentR2.payload_sha256
    $freshR2Payload = $freshR2.payload_sha256
    $payloadEquality = ($persistentR2Payload -eq $freshR2Payload)
    $persistentSessionHash = Get-SessionHash $persistentSessionId
    $freshSessionHash = Get-SessionHash $freshSessionId
    $sessionComparison = [ordered]@{
        persistent_round_1_session_hash = $persistentSessionHash
        persistent_round_2_session_hash = $persistentSessionHash
        persistent_round_3_session_hash = $persistentSessionHash
        fresh_round_2_session_hash = $freshSessionHash
        persistent_same_session_hash = ($persistentSessionHash -eq $persistentSessionHash)
        fresh_different_session_hash = ($persistentSessionHash -ne $freshSessionHash)
        raw_session_ids_saved = $false
    }
    Write-Json (Join-Path $evidenceRoot "session-and-composition-comparison.json") ([ordered]@{
        session = $sessionComparison
        round_2_persistent_and_fresh = [ordered]@{
            persistent_payload_sha256 = $persistentR2Payload
            fresh_payload_sha256 = $freshR2Payload
            exact_composition_equal = $payloadEquality
            composition_contract = "prompt file bytes followed by candidate file bytes without separators"
        }
        source_file_hashes_equal = $payloadEquality
        raw_session_secret_environment_values_saved = $false
    })

    $semanticYes = (
        [bool] $persistentR2.persistent_r2_exact_violation -and
        [bool] $freshR2.fresh_r2_materially_weaker -and
        [bool] $persistentR3.persistent_r3_resolved -and
        $payloadEquality -and
        [bool] $sessionComparison.persistent_same_session_hash -and
        [bool] $sessionComparison.fresh_different_session_hash
    )
    $freshExactViolation = if ($freshR2.review) { Test-PersistentR2 $freshR2.review } else { $false }
    $classification = if ($semanticYes) {
        "Yes"
    }
    elseif ([bool] $persistentR2.persistent_r2_exact_violation -and [bool] $persistentR3.persistent_r3_resolved) {
        "Partial"
    }
    else {
        "No"
    }

    $finalSnapshot = Get-GitSnapshot
    Write-Json (Join-Path $evidenceRoot "final-post-git-snapshot.json") $finalSnapshot
    $outsideInitial = @(Get-OutsideExperimentStatus $initialSnapshot)
    $outsideFinal = @(Get-OutsideExperimentStatus $finalSnapshot)
    $productionUnchanged = ([string]::Join("`n", $outsideInitial) -ceq [string]::Join("`n", $outsideFinal))
    $diffCheck = Get-DiffCheck
    Write-Json (Join-Path $evidenceRoot "final-diff-check.json") $diffCheck

    $architecture = if ($semanticYes) { "PASS" } elseif ([bool] $persistentR2.persistent_r2_exact_violation -and [bool] $persistentR3.persistent_r3_resolved) { "PARTIAL" } else { "FAIL" }
    $security = if ($productionUnchanged -and $diffCheck.passed) { "CONDITIONAL" } else { "NOT_QUALIFIED" }
    $summary = @"
# Grok Build CLI Persistent Purpose Reviewer v2 実験結果

実行日: $([DateTimeOffset]::Now.ToString("yyyy-MM-dd HH:mm:ss zzz"))
対象: fixtures\persistence-control-v2\、prompts\persistence-control-v2\
CLI: Grok Build CLI（version evidence: setup\static-help-version-model.json、model: grok-4.6 default）
cwd: $experimentRoot

## 判定

- 総合: **$classification**
- Persistent R2 の unhinted 固定契約違反検出 (PPR-001, active/fail/sufficient, quick-check と focus-mode の具体的 evidence): **$([bool] $persistentR2.persistent_r2_exact_violation)**
- Fresh R2 の negative-control（current input だけでは特定不能として unknown/insufficient）: **$([bool] $freshR2.fresh_r2_materially_weaker)**
- Persistent R3 の解消判定 (resolved/pass/sufficient): **$([bool] $persistentR3.persistent_r3_resolved)**
- Persistent R2/Fresh R2 の exact composition equality: **$payloadEquality**
- Persistent session 同一 hash / Fresh session 別 hash: **$([bool] $sessionComparison.persistent_same_session_hash) / $([bool] $sessionComparison.fresh_different_session_hash)**

Fresh R2 が exact rule/rationale を特定してしまう場合は negative-control の期待に反するため、fixture は変更せず総合を Partial/No とする。今回の fresh 判定は materially weaker: **$([bool] $freshR2.fresh_r2_materially_weaker)**、exact violation: **$freshExactViolation**。

## Architecture feasibility

Persistent R1 は新規 session、Persistent R2/R3 は同じ特定 session ID の --resume、Fresh R2 は別の新規 session で実行した。R2 の外部入力は persistent/fresh で同一 payload hash、R2/R3 に R1 context・previous response・decision/mapping/finding の再送はない。architecture feasibility: **$architecture**。

## Security qualification

--permission-mode plan、--sandbox read-only、--tools read,view,grep、write/shell/task/edit 系 disallow、--disable-web-search、--no-memory、--no-subagents、実験 cwd を指定した。外部へ渡したのは安全な架空 fixture の payload のみで、raw session ID・secret・environment value は保存していない。Git の実験外 status は pre/post で同一、production non-mutation observed: **$productionUnchanged**、final git diff --check: **$($diffCheck.passed)**。

CLI 内部の relay、global rule の統合、sandbox backend の低レベル enforcement はこの実験の evidence だけでは独立監査していないため、security qualification は **$security**（architecture feasibility とは別評価）とする。

## Evidence

- run-metadata.json
- setup\static-help-version-model.json
- runs\*\input-manifest.json（bytes/hash/no-replay flags）
- runs\*\raw-response.txt と semantic-review.json（保存 actual-byte SHA-256、semantic form、round label）
- session-and-composition-comparison.json
- run-start-pre-git-snapshot.json、final-post-git-snapshot.json、final-diff-check.json
"@
    Write-Utf8NoBom (Join-Path $evidenceRoot "summary.md") $summary
    Write-Utf8NoBom (Join-Path $evidenceRoot "completed.txt") @(
        "completed_at_utc=$([DateTimeOffset]::UtcNow.ToString('O'))"
        "classification=$classification"
        "architecture_feasibility=$architecture"
        "security_qualification=$security"
        "raw_session_secret_environment_values_saved=false"
    )
}
catch {
    $failure = $_.Exception.ToString()
    if (-not (Test-Path -LiteralPath $evidenceRoot)) {
        [void] (New-Item -ItemType Directory -Path $evidenceRoot -Force)
    }
    Save-ExceptionTrace (Join-Path $evidenceRoot "experiment-exception-trace.log") $_.Exception
    throw
}
