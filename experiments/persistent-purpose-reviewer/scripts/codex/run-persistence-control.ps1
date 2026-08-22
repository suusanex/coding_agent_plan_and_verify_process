[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-Sha256Bytes([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return (($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Sha256File([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-Utf8NoBom([string] $Path, [string] $Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-Json([string] $Path, [object] $Value) {
    Write-Utf8NoBom $Path ($Value | ConvertTo-Json -Depth 20)
}

function Get-GitStatusLines([string] $RepositoryRoot) {
    return @(& git -C $RepositoryRoot status --porcelain=v1 --untracked-files=all 2>&1 | ForEach-Object { [string] $_ })
}

function Get-RelativeStatusPath([string] $Line) {
    if ($Line.Length -lt 4) {
        return $Line
    }

    return $Line.Substring(3).Replace("\", "/")
}

function Get-OutsideAllowedStatus(
    [string[]] $Before,
    [string[]] $After,
    [string[]] $AllowedPrefixes
) {
    $beforeSet = @{}
    foreach ($line in $Before) {
        $beforeSet[(Get-RelativeStatusPath $line)] = $line
    }

    $afterSet = @{}
    foreach ($line in $After) {
        $afterSet[(Get-RelativeStatusPath $line)] = $line
    }

    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($path in ($beforeSet.Keys + $afterSet.Keys | Sort-Object -Unique)) {
        $statusChanged = $beforeSet.ContainsKey($path) -xor $afterSet.ContainsKey($path)
        if (-not $statusChanged -and $beforeSet.ContainsKey($path) -and $afterSet.ContainsKey($path)) {
            $statusChanged = $beforeSet[$path] -ne $afterSet[$path]
        }

        if ($statusChanged) {
            $normalized = $path.ToLowerInvariant()
            $allowed = $false
            foreach ($prefix in $AllowedPrefixes) {
                if ($normalized.StartsWith($prefix.ToLowerInvariant())) {
                    $allowed = $true
                    break
                }
            }

            if (-not $allowed) {
                $changed.Add($path)
            }
        }
    }

    return @($changed | Sort-Object -Unique)
}

function Sanitize-Text([string] $Text) {
    $sanitized = if ($null -eq $Text) { "" } else { $Text }
    $patterns = @(
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"; Replacement = "[REDACTED_BEARER]" },
        @{ Pattern = "(?i)(authorization\s*:\s*(?:bearer|token|basic)\s+)[^\s]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|cookie)\s*([=:])\s*[^\s,;]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\b(?:ghp|gho|github_pat|sk)-[A-Za-z0-9_=-]+"; Replacement = "[REDACTED_TOKEN]" },
        @{ Pattern = "(?i)\b[A-F0-9]{8}-[A-F0-9]{4}-[1-5][A-F0-9]{3}-[89AB][A-F0-9]{3}-[A-F0-9]{12}\b"; Replacement = "[SESSION_ID_REDACTED]" },
        @{ Pattern = "(?i)[A-Z]:\\Users\\[^\\\r\n ]+"; Replacement = "<USER_PATH>" },
        @{ Pattern = "(?i)[A-Z]:\\[^ \r\n]+\\coding_agent_plan_and_verify_process"; Replacement = "<REPOSITORY_PATH>" }
    )

    foreach ($item in $patterns) {
        $sanitized = [regex]::Replace($sanitized, $item.Pattern, $item.Replacement)
    }

    return $sanitized
}

function Invoke-Process(
    [string] $FilePath,
    [string[]] $Arguments,
    [string] $WorkingDirectory,
    [byte[]] $InputBytes,
    [int] $TimeoutSeconds = 900
) {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $FilePath
    $process.StartInfo.WorkingDirectory = $WorkingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) {
        [void] $process.StartInfo.ArgumentList.Add($argument)
    }

    $startedAt = [DateTimeOffset]::UtcNow
    try {
        if (-not $process.Start()) {
            throw "Codex process could not be started."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length)
        $process.StandardInput.Close()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            $process.Kill($true)
            $process.WaitForExit()
        }

        return [ordered] @{
            started_at_utc = $startedAt.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            exit_code = if ($completed) { $process.ExitCode } else { $null }
            timed_out = -not $completed
            stdout = $stdoutTask.GetAwaiter().GetResult()
            stderr = $stderrTask.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-JsonEvents([string] $Stdout) {
    $events = New-Object System.Collections.Generic.List[object]
    $parseErrors = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Stdout -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $events.Add(($line | ConvertFrom-Json))
        }
        catch {
            $parseErrors.Add((Sanitize-Text $_.Exception.ToString()))
        }
    }

    return [ordered] @{
        events = $events.ToArray()
        parse_errors = $parseErrors.ToArray()
    }
}

function Get-SessionIdentity([object[]] $Events) {
    $ids = @(
        $Events |
            Where-Object { $_.thread_id } |
            ForEach-Object { [string] $_.thread_id } |
            Select-Object -Unique
    )

    if ($ids.Count -eq 0) {
        return $null
    }

    if ($ids.Count -ne 1) {
        throw "Codex emitted multiple thread identities in one run."
    }

    return $ids[0]
}

function Get-EventSummary([object[]] $Events, [int] $ParseErrorCount) {
    $eventTypes = @(
        $Events |
            ForEach-Object { [string] $_.type } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $agentMessages = @(
        $Events |
            Where-Object { $_.type -eq "item.completed" -and $_.item.type -eq "agent_message" }
    )

    return [ordered] @{
        event_count = $Events.Count
        parse_error_count = $ParseErrorCount
        event_types = @($eventTypes)
        agent_message_event_count = $agentMessages.Count
        thread_id_present = (@($Events | Where-Object { $_.thread_id }).Count -gt 0)
    }
}

function Get-InputDescriptor([string] $Root, [string] $RelativePath) {
    $fullPath = Join-Path $Root $RelativePath
    $bytes = [IO.File]::ReadAllBytes($fullPath)
    return [ordered] @{
        path = $RelativePath
        bytes = $bytes.Length
        sha256 = Get-Sha256Bytes $bytes
        content_bytes = $bytes
    }
}

function New-Payload([string] $Root, [string[]] $RelativePaths) {
    $separator = [Text.Encoding]::UTF8.GetBytes("`r`n`r`n")
    $descriptors = @()
    $buffers = New-Object System.Collections.Generic.List[byte[]]
    for ($index = 0; $index -lt $RelativePaths.Count; $index++) {
        $descriptor = Get-InputDescriptor $Root $RelativePaths[$index]
        $descriptors += $descriptor
        $buffers.Add($descriptor.content_bytes)
        if ($index -lt ($RelativePaths.Count - 1)) {
            $buffers.Add($separator)
        }
    }

    $payloadLength = 0
    foreach ($buffer in $buffers) {
        $payloadLength += $buffer.Length
    }

    $payload = [byte[]]::new($payloadLength)
    $offset = 0
    foreach ($buffer in $buffers) {
        [Array]::Copy($buffer, 0, $payload, $offset, $buffer.Length)
        $offset += $buffer.Length
    }

    return [ordered] @{
        descriptors = @($descriptors | ForEach-Object {
            [ordered] @{
                path = $_.path
                bytes = $_.bytes
                sha256 = $_.sha256
            }
        })
        separator = "`r`n`r`n"
        separator_bytes = @(13, 10, 13, 10)
        bytes = $payload.Length
        sha256 = Get-Sha256Bytes $payload
        content_bytes = $payload
    }
}

function Get-CommandShape([string] $Kind, [string] $Model, [string] $ExperimentRoot) {
    if ($Kind -eq "persistent-r1") {
        return "node <codex-entrypoint> exec --json --color never --ignore-user-config --ignore-rules -s read-only -C <experiment-root> -m $Model -o <round-1-raw-response> -"
    }

    if ($Kind -eq "persistent-r2") {
        return "node <codex-entrypoint> exec resume <same-specific-session-id> --json --ignore-user-config --ignore-rules -o <round-2-raw-response> -"
    }

    if ($Kind -eq "persistent-r3") {
        return "node <codex-entrypoint> exec resume <same-specific-session-id> --json --ignore-user-config --ignore-rules -o <round-3-raw-response> -"
    }

    return "node <codex-entrypoint> exec --json --color never --ignore-user-config --ignore-rules -s read-only -C <experiment-root> -m $Model -o <fresh-round-2-raw-response> -"
}

function Save-Failure([string] $RoundRoot, [object] $Result, [string] $Failure) {
    $details = [ordered] @{
        failure = Sanitize-Text $Failure
        exit_code = $Result.exit_code
        timed_out = $Result.timed_out
        stderr = Sanitize-Text $Result.stderr
    }
    Write-Json (Join-Path $RoundRoot "failure.json") $details
}

function Invoke-Run(
    [string] $Kind,
    [string] $RoundRoot,
    [string] $ExperimentRoot,
    [string] $RepositoryRoot,
    [string] $EntryPoint,
    [string] $Model,
    [byte[]] $PayloadBytes,
    [string] $SessionId
) {
    $rawPath = Join-Path $RoundRoot "raw-response.md"
    $sanitizedPath = Join-Path $RoundRoot "sanitized-response.md"
    if (Test-Path $rawPath) {
        throw "Refusing to overwrite an existing raw response: $rawPath"
    }

    $args = if ($Kind -eq "persistent-r1") {
        @($EntryPoint, "exec", "--json", "--color", "never", "--ignore-user-config", "--ignore-rules", "-s", "read-only", "-C", $ExperimentRoot, "-m", $Model, "-o", $rawPath, "-")
    }
    elseif ($Kind -eq "persistent-r2" -or $Kind -eq "persistent-r3") {
        @($EntryPoint, "exec", "resume", $SessionId, "--json", "--ignore-user-config", "--ignore-rules", "-o", $rawPath, "-")
    }
    else {
        @($EntryPoint, "exec", "--json", "--color", "never", "--ignore-user-config", "--ignore-rules", "-s", "read-only", "-C", $ExperimentRoot, "-m", $Model, "-o", $rawPath, "-")
    }

    $result = Invoke-Process "node" $args $ExperimentRoot $PayloadBytes
    $parsed = Get-JsonEvents $result.stdout
    $sessionIdentity = Get-SessionIdentity $parsed.events
    $eventSummary = Get-EventSummary $parsed.events $parsed.parse_errors.Count
    $responsePresent = Test-Path $rawPath
    $rawHash = if ($responsePresent) { Get-Sha256File $rawPath } else { $null }
    $sanitizedHash = $null
    if ($responsePresent) {
        $rawText = [IO.File]::ReadAllText($rawPath, [Text.UTF8Encoding]::new($false))
        Write-Utf8NoBom $sanitizedPath (Sanitize-Text $rawText)
        $sanitizedHash = Get-Sha256File $sanitizedPath
    }

    $metadata = [ordered] @{
        schema_version = 1
        provider = "codex"
        kind = $Kind
        cli_version = "0.147.0"
        model = $Model
        sandbox = "read-only"
        cwd = "experiments/persistent-purpose-reviewer"
        process_exited = -not $result.timed_out
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        started_at_utc = $result.started_at_utc
        completed_at_utc = $result.completed_at_utc
        command_shape = Get-CommandShape $Kind $Model $ExperimentRoot
        session_id_sha256_12 = if ($sessionIdentity) { (Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($sessionIdentity))).Substring(0, 12) } else { $null }
        response_present = $responsePresent
        response_sha256_after_capture = $rawHash
        sanitized_response_sha256_after_save = $sanitizedHash
        response_paths = [ordered] @{
            raw = if ($responsePresent) { "raw-response.md" } else { $null }
            sanitized = if ($responsePresent) { "sanitized-response.md" } else { $null }
        }
        event_summary = $eventSummary
        stderr_present = -not [string]::IsNullOrWhiteSpace($result.stderr)
    }
    Write-Json (Join-Path $RoundRoot "machine-metadata.json") $metadata

    if ($parsed.parse_errors.Count -gt 0) {
        Write-Utf8NoBom (Join-Path $RoundRoot "event-parse-errors.txt") (($parsed.parse_errors -join "`r`n") + "`r`n")
    }

    if ($result.timed_out -or $result.exit_code -ne 0 -or -not $responsePresent -or -not $sessionIdentity) {
        $failure = "Codex run did not produce a verifiable completed response and session identity."
        Save-Failure $RoundRoot $result $failure
    }

    return [ordered] @{
        kind = $Kind
        session_id = $sessionIdentity
        session_hash = if ($sessionIdentity) { (Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($sessionIdentity))).Substring(0, 12) } else { $null }
        response_sha256 = $rawHash
        sanitized_response_sha256 = $sanitizedHash
        success = (-not $result.timed_out -and $result.exit_code -eq 0 -and $responsePresent -and $null -ne $sessionIdentity)
    }
}

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\")).Path
$experimentRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$evidenceRoot = Join-Path $experimentRoot "evidence\codex\persistence-control"
$persistentRoot = Join-Path $evidenceRoot "persistent"
$freshRoot = Join-Path $evidenceRoot "fresh-control"
$allowedPrefixes = @(
    "experiments/persistent-purpose-reviewer/evidence/codex/persistence-control/",
    "experiments/persistent-purpose-reviewer/scripts/codex/run-persistence-control.ps1"
)
$model = "gpt-5.6-luna"

if (Test-Path $evidenceRoot) {
    throw "Refusing to overwrite an existing persistence-control evidence directory."
}

$preStatus = Get-GitStatusLines $repositoryRoot
New-Item -ItemType Directory -Force -Path `
    (Join-Path $persistentRoot "round-1"), `
    (Join-Path $persistentRoot "round-2"), `
    (Join-Path $persistentRoot "round-3"), `
    (Join-Path $freshRoot "round-2"), `
    (Join-Path $evidenceRoot "setup") | Out-Null
Write-Utf8NoBom (Join-Path $evidenceRoot "pre-git-status.txt") (($preStatus -join "`r`n") + "`r`n")

$versionResult = Invoke-Process "node" @((Join-Path (Split-Path (Get-Command codex).Source -Parent) "node_modules\@openai\codex\bin\codex.js"), "--version") $experimentRoot ([byte[]]::new(0)) 120
$nodeVersionResult = Invoke-Process "node" @("--version") $experimentRoot ([byte[]]::new(0)) 120
$execHelpResult = Invoke-Process "node" @((Join-Path (Split-Path (Get-Command codex).Source -Parent) "node_modules\@openai\codex\bin\codex.js"), "exec", "--help") $experimentRoot ([byte[]]::new(0)) 120
$resumeHelpResult = Invoke-Process "node" @((Join-Path (Split-Path (Get-Command codex).Source -Parent) "node_modules\@openai\codex\bin\codex.js"), "exec", "resume", "--help") $experimentRoot ([byte[]]::new(0)) 120
Write-Utf8NoBom (Join-Path $evidenceRoot "setup\codex-version.txt") (Sanitize-Text $versionResult.stdout)
Write-Utf8NoBom (Join-Path $evidenceRoot "setup\exec-help.txt") (Sanitize-Text $execHelpResult.stdout)
Write-Utf8NoBom (Join-Path $evidenceRoot "setup\exec-resume-help.txt") (Sanitize-Text $resumeHelpResult.stdout)

$round1Payload = New-Payload $experimentRoot @(
    "prompts\persistence-control\round-1.md",
    "fixtures\persistence-control\round-1-context.md",
    "fixtures\persistence-control\round-1-candidate.md"
)
$round2Payload = New-Payload $experimentRoot @(
    "prompts\persistence-control\round-2.md",
    "fixtures\persistence-control\round-2-candidate.md"
)
$round3Payload = New-Payload $experimentRoot @(
    "prompts\persistence-control\round-3.md",
    "fixtures\persistence-control\round-3-candidate.md"
)

function New-Manifest(
    [string] $RunKind,
    [int] $Round,
    [object] $Payload,
    [bool] $FullContextSent,
    [bool] $PreviousOutputSent,
    [string] $R2EqualityHash
) {
    return [ordered] @{
        schema_version = 1
        provider = "codex"
        run = $RunKind
        round = $Round
        files = $Payload.descriptors
        payload = [ordered] @{
            composition = @($Payload.descriptors | ForEach-Object { $_.path })
            separator = $Payload.separator
            separator_bytes = $Payload.separator_bytes
            bytes = $Payload.bytes
            sha256 = $Payload.sha256
        }
        full_context_sent = $FullContextSent
        previous_output_sent = $PreviousOutputSent
        prior_reviewer_output_full_sent = $PreviousOutputSent
        semantic_decision_replayed = $false
        semantic_mapping_replayed = $false
        semantic_finding_replayed = $false
        external_meaning_data_sources = @("listed prompt bytes", "listed fixture bytes")
        persistent_r2_fresh_r2_equality_sha256 = $R2EqualityHash
    }
}

$equalityHash = $round2Payload.sha256
Write-Json (Join-Path $persistentRoot "round-1\input-payload-manifest.json") (New-Manifest "persistent" 1 $round1Payload $true $false $equalityHash)
Write-Json (Join-Path $persistentRoot "round-2\input-payload-manifest.json") (New-Manifest "persistent" 2 $round2Payload $false $false $equalityHash)
Write-Json (Join-Path $persistentRoot "round-3\input-payload-manifest.json") (New-Manifest "persistent" 3 $round3Payload $false $false $equalityHash)
Write-Json (Join-Path $freshRoot "round-2\input-payload-manifest.json") (New-Manifest "fresh-control" 2 $round2Payload $false $false $equalityHash)

foreach ($roundRoot in @(
    (Join-Path $persistentRoot "round-1"),
    (Join-Path $persistentRoot "round-2"),
    (Join-Path $persistentRoot "round-3"),
    (Join-Path $freshRoot "round-2")
)) {
    Write-Utf8NoBom (Join-Path $roundRoot "pre-git-status.txt") (($preStatus -join "`r`n") + "`r`n")
}

$entryPoint = Join-Path (Split-Path (Get-Command codex).Source -Parent) "node_modules\@openai\codex\bin\codex.js"
try {
    $persistentR1 = Invoke-Run "persistent-r1" (Join-Path $persistentRoot "round-1") $experimentRoot $repositoryRoot $entryPoint $model $round1Payload.content_bytes $null
}
catch {
    Write-Utf8NoBom (Join-Path $evidenceRoot "persistent-r1-runner-exception.txt") (Sanitize-Text $_.Exception.ToString())
    throw
}
$persistentSessionId = $persistentR1.session_id

if ($persistentSessionId) {
    $persistentR2 = Invoke-Run "persistent-r2" (Join-Path $persistentRoot "round-2") $experimentRoot $repositoryRoot $entryPoint $model $round2Payload.content_bytes $persistentSessionId
    $persistentR3 = Invoke-Run "persistent-r3" (Join-Path $persistentRoot "round-3") $experimentRoot $repositoryRoot $entryPoint $model $round3Payload.content_bytes $persistentSessionId
}
else {
    foreach ($round in @(2, 3)) {
        $blockedRoot = Join-Path $persistentRoot ("round-{0}" -f $round)
        Write-Json (Join-Path $blockedRoot "failure.json") @{
            failure = "Persistent Round 1 did not expose a session identity; resume was not attempted."
            exit_code = $null
            timed_out = $false
        }
    }
    $persistentR2 = @{ success = $false; session_hash = $null; response_sha256 = $null }
    $persistentR3 = @{ success = $false; session_hash = $null; response_sha256 = $null }
}

$freshR2 = Invoke-Run "fresh-r2" (Join-Path $freshRoot "round-2") $experimentRoot $repositoryRoot $entryPoint $model $round2Payload.content_bytes $null

$persistentHashes = @($persistentR1.session_hash, $persistentR2.session_hash, $persistentR3.session_hash) | Where-Object { $_ }
$freshHash = $freshR2.session_hash
$samePersistentSession = ($persistentHashes.Count -eq 3 -and (($persistentHashes | Select-Object -Unique).Count -eq 1))
$freshDifferent = ($null -ne $freshHash -and (-not ($persistentHashes -contains $freshHash)))
$r2EqualityVerified = ($round2Payload.sha256 -eq $equalityHash)

$postStatus = Get-GitStatusLines $repositoryRoot
Write-Utf8NoBom (Join-Path $evidenceRoot "post-git-status.txt") (($postStatus -join "`r`n") + "`r`n")
$outsideChanges = Get-OutsideAllowedStatus $preStatus $postStatus $allowedPrefixes
$productionChanges = @(
    $outsideChanges |
        Where-Object { -not $_.ToLowerInvariant().StartsWith("experiments/persistent-purpose-reviewer/") }
)
$otherExperimentChanges = @(
    $outsideChanges |
        Where-Object { $_.ToLowerInvariant().StartsWith("experiments/persistent-purpose-reviewer/") }
)
Write-Json (Join-Path $evidenceRoot "run-metadata.json") ([ordered] @{
    schema_version = 1
    provider = "codex"
    cli = "codex"
    cli_version = "0.147.0"
    model = $model
    sandbox = "read-only"
    cwd = "experiments/persistent-purpose-reviewer"
    persistent_session_hashes = $persistentHashes
    fresh_session_hash = $freshHash
    same_session_hash_persistent_r1_r3 = $samePersistentSession
    fresh_session_hash_different = $freshDifferent
    persistent_r2_fresh_r2_payload_sha256_equal = $r2EqualityVerified
    persistent_r2_payload_sha256 = $round2Payload.sha256
    fresh_r2_payload_sha256 = $round2Payload.sha256
    command_shapes = [ordered] @{
        persistent_round_1 = Get-CommandShape "persistent-r1" $model $experimentRoot
        persistent_round_2 = Get-CommandShape "persistent-r2" $model $experimentRoot
        persistent_round_3 = Get-CommandShape "persistent-r3" $model $experimentRoot
        fresh_control_round_2 = Get-CommandShape "fresh-r2" $model $experimentRoot
    }
    initial_process_exited_before_resume = ($persistentR1.success -and $persistentR2.success)
    production_unchanged = ($productionChanges.Count -eq 0)
    allowed_output_scope_unchanged = ($outsideChanges.Count -eq 0)
    outside_allowed_git_status_changes = $outsideChanges
    other_experiment_changes_observed = $otherExperimentChanges
    production_changes_observed = $productionChanges
    machine_metadata = [ordered] @{
        os = [Environment]::OSVersion.VersionString
        powershell = $PSVersionTable.PSVersion.ToString()
        process_architecture = [Environment]::Is64BitProcess
        node_version = ($nodeVersionResult.stdout.Trim())
        git_version = ((& git --version).Trim())
        timezone_offset = ([DateTimeOffset]::Now.Offset.ToString())
    }
    note = "Network and OS-level sandbox internals were not audited; that is recorded separately from architecture feasibility."
})

foreach ($roundRoot in @(
    (Join-Path $persistentRoot "round-1"),
    (Join-Path $persistentRoot "round-2"),
    (Join-Path $persistentRoot "round-3"),
    (Join-Path $freshRoot "round-2")
)) {
    Write-Utf8NoBom (Join-Path $roundRoot "post-git-status.txt") (($postStatus -join "`r`n") + "`r`n")
}

Write-Json (Join-Path $evidenceRoot "verification.json") ([ordered] @{
    schema_version = 1
    persistent_session_same_hash = $samePersistentSession
    fresh_session_different_hash = $freshDifferent
    r2_payload_equality_hash = $equalityHash
    production_unchanged = ($productionChanges.Count -eq 0)
    allowed_output_scope_unchanged = ($outsideChanges.Count -eq 0)
    other_experiment_changes_observed = $otherExperimentChanges
    production_changes_observed = $productionChanges
    git_diff_check = ((& git -C $repositoryRoot diff --check 2>&1 | Out-String).Trim())
})
