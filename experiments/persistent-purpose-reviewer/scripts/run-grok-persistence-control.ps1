[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-ExperimentRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-RepositoryRoot([string] $experimentRoot) {
    $topLevel = (& git -C $experimentRoot rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        throw "Git repository root could not be resolved."
    }

    return (Resolve-Path $topLevel).Path
}

function Get-Sha256([byte[]] $bytes) {
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}

function Get-TextSha256([string] $text) {
    $encoding = [Text.UTF8Encoding]::new($false)
    return Get-Sha256 ($encoding.GetBytes($text))
}

function Read-Utf8File([string] $path) {
    $encoding = [Text.UTF8Encoding]::new($false, $true)
    return $encoding.GetString([IO.File]::ReadAllBytes($path))
}

function ConvertTo-SanitizedText([string] $text) {
    if ($null -eq $text) {
        return ""
    }

    $sanitized = $text
    $patterns = @(
        @{ Pattern = "(?i)(authorization\s*:\s*(?:bearer|token|basic)\s+)[^\s]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"; Replacement = "[REDACTED_BEARER]" },
        @{ Pattern = "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|secret|credential|cookie)\s*([=:])\s*[^\s,;]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\b(?:ghp|gho|github_pat|sk)-[A-Za-z0-9_=-]+"; Replacement = "[REDACTED_TOKEN]" },
        @{ Pattern = "(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"; Replacement = "[SESSION_ID_REDACTED]" },
        @{ Pattern = "(?i)[A-Z]:\\Users\\[^\\\r\n ]+"; Replacement = "<HOME_PATH_REDACTED>" },
        @{ Pattern = "(?i)[A-Z]:\\[^ \r\n]+\\coding_agent_plan_and_verify_process"; Replacement = "<REPOSITORY_PATH_REDACTED>" }
    )

    foreach ($item in $patterns) {
        $sanitized = [regex]::Replace($sanitized, $item.Pattern, $item.Replacement)
    }

    return $sanitized
}

function Write-Text([string] $path, [string] $text) {
    Set-Content -LiteralPath $path -Value $text -Encoding utf8
}

function Write-Json([string] $path, $value) {
    $value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
}

function Get-GitSnapshot([string] $repositoryRoot) {
    $status = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>&1 |
        ForEach-Object { ConvertTo-SanitizedText ([string] $_) })
    if ($LASTEXITCODE -ne 0) {
        throw "git status failed."
    }

    $unstaged = @(& git -C $repositoryRoot diff --name-status 2>&1 |
        ForEach-Object { ConvertTo-SanitizedText ([string] $_) })
    if ($LASTEXITCODE -ne 0) {
        throw "git diff failed."
    }

    $staged = @(& git -C $repositoryRoot diff --cached --name-status 2>&1 |
        ForEach-Object { ConvertTo-SanitizedText ([string] $_) })
    if ($LASTEXITCODE -ne 0) {
        throw "git cached diff failed."
    }

    return [ordered] @{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        branch = (& git -C $repositoryRoot branch --show-current).Trim()
        head = (& git -C $repositoryRoot rev-parse HEAD).Trim()
        status = @($status)
        unstaged_name_status = @($unstaged)
        staged_name_status = @($staged)
    }
}

function Get-StatusDelta([string[]] $before, [string[]] $after) {
    $changes = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $after) {
        if ($before -notcontains $line) {
            $changes.Add("added-or-changed: $line")
        }
    }
    foreach ($line in $before) {
        if ($after -notcontains $line) {
            $changes.Add("removed-or-changed: $line")
        }
    }

    return @($changes)
}

function Get-StatusPath([string] $statusLine) {
    if ($statusLine.Length -le 3) {
        return $statusLine.Trim()
    }

    $path = $statusLine.Substring(3).Trim().Trim('"')
    if ($path.Contains(" -> ")) {
        $path = $path.Split(" -> ")[-1].Trim('"')
    }

    return $path
}

function Test-AllowedChange([string] $statusLine) {
    $path = (Get-StatusPath $statusLine).Replace("\", "/")
    return $path.StartsWith($script:AllowedEvidencePrefix, [StringComparison]::OrdinalIgnoreCase) -or
        $path.Equals($script:AllowedScriptPath, [StringComparison]::OrdinalIgnoreCase)
}

function Get-OutsideAllowedChanges([string[]] $changes) {
    return @(
        $changes | Where-Object {
            $line = [string] $_
            $separatorIndex = $line.IndexOf(": ")
            if ($separatorIndex -lt 0) {
                $true
            }
            else {
                $statusLine = $line.Substring($separatorIndex + 2)
                -not (Test-AllowedChange $statusLine)
            }
        }
    )
}

function Test-ProductionPath([string] $statusLine) {
    $path = (Get-StatusPath $statusLine).Replace("\", "/")
    return -not $path.StartsWith("experiments/persistent-purpose-reviewer/", [StringComparison]::OrdinalIgnoreCase)
}

function Get-OutsideProductionChanges([string[]] $changes) {
    return @(
        $changes | Where-Object {
            $line = [string] $_
            $separatorIndex = $line.IndexOf(": ")
            if ($separatorIndex -lt 0) {
                $true
            }
            else {
                $statusLine = $line.Substring($separatorIndex + 2)
                Test-ProductionPath $statusLine
            }
        }
    )
}

function Invoke-CapturedProcess(
    [string] $filePath,
    [string[]] $arguments,
    [string] $workingDirectory,
    [int] $timeoutSeconds = 900
) {
    $start = [DateTimeOffset]::UtcNow
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $filePath
    $process.StartInfo.WorkingDirectory = $workingDirectory
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    foreach ($argument in $arguments) {
        [void] $process.StartInfo.ArgumentList.Add($argument)
    }

    try {
        if (-not $process.Start()) {
            throw "CLI process could not be started."
        }

        $stdoutBuffer = [IO.MemoryStream]::new()
        $stderrBuffer = [IO.MemoryStream]::new()
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutBuffer)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrBuffer)
        $completed = $process.WaitForExit($timeoutSeconds * 1000)
        if (-not $completed) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit()
        }

        $stdoutTask.GetAwaiter().GetResult()
        $stderrTask.GetAwaiter().GetResult()
        $stdoutBytes = $stdoutBuffer.ToArray()
        $stderrBytes = $stderrBuffer.ToArray()
        $utf8 = [Text.UTF8Encoding]::new($false, $false)
        $combinedBytes = [byte[]]::new($stdoutBytes.Length + $stderrBytes.Length)
        [Array]::Copy($stdoutBytes, 0, $combinedBytes, 0, $stdoutBytes.Length)
        [Array]::Copy($stderrBytes, 0, $combinedBytes, $stdoutBytes.Length, $stderrBytes.Length)

        return [ordered] @{
            started_at_utc = $start.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            process_exited = $completed
            timed_out = -not $completed
            exit_code = if ($completed) { $process.ExitCode } else { $null }
            stdout = $utf8.GetString($stdoutBytes)
            stderr = $utf8.GetString($stderrBytes)
            raw_stdout_bytes_sha256 = Get-Sha256 $stdoutBytes
            raw_stderr_bytes_sha256 = Get-Sha256 $stderrBytes
            raw_combined_bytes_sha256 = Get-Sha256 $combinedBytes
            raw_stdout_bytes = $stdoutBytes.Length
            raw_stderr_bytes = $stderrBytes.Length
        }
    }
    finally {
        if ($null -ne $stdoutBuffer) {
            $stdoutBuffer.Dispose()
        }
        if ($null -ne $stderrBuffer) {
            $stderrBuffer.Dispose()
        }
        $process.Dispose()
    }
}

function Get-FileManifestEntry([string] $experimentRoot, [string] $relativePath) {
    $path = Join-Path $experimentRoot $relativePath
    $bytes = [IO.File]::ReadAllBytes($path)
    return [ordered] @{
        path = $relativePath.Replace("\", "/")
        bytes = $bytes.Length
        sha256 = Get-Sha256 $bytes
    }
}

function New-Payload([string[]] $relativePaths, [string] $experimentRoot) {
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in $relativePaths) {
        $parts.Add((Read-Utf8File (Join-Path $experimentRoot $relativePath)))
    }

    return ($parts -join "`r`n`r`n")
}

function New-CommandArguments(
    [string] $experimentRoot,
    [string] $model,
    [string] $sessionMode,
    [string] $sessionId,
    [string] $payload,
    [string] $systemPrompt
) {
    $arguments = @(
        "--cwd", $experimentRoot,
        "--model", $model,
        "--no-memory",
        "--no-subagents",
        "--permission-mode", "plan",
        "--sandbox", "read-only",
        "--disable-web-search",
        "--tools", "read,view,grep",
        "--disallowed-tools", "write,shell,task,edit_file,run_shell_command",
        "--system-prompt-override", $systemPrompt,
        "--output-format", "plain",
        "--verbatim"
    )

    if ($sessionMode -eq "new") {
        $arguments += @("--session-id", $sessionId)
    }
    elseif ($sessionMode -eq "resume") {
        $arguments += @("--resume", $sessionId)
    }
    else {
        throw "Unknown session mode: $sessionMode"
    }

    $arguments += @("--single", $payload)
    return $arguments
}

function Get-CommandShape([string] $sessionMode) {
    $sessionOption = if ($sessionMode -eq "new") {
        "--session-id <SESSION_ID_REDACTED>"
    }
    else {
        "--resume <SAME_SESSION_ID_REDACTED>"
    }

    return "grok --cwd <EXPERIMENT_ROOT> --model grok-4.6 --no-memory --no-subagents --permission-mode plan --sandbox read-only --disable-web-search --tools read,view,grep --disallowed-tools write,shell,task,edit_file,run_shell_command --system-prompt-override=<SAFE_REVIEWER_ROLE> --output-format plain --verbatim $sessionOption --single <PAYLOAD_FROM_MANIFEST>"
}

function Save-SanitizedOutput(
    [string] $runRoot,
    [string] $label,
    [object] $result
) {
    $sanitizedStdout = ConvertTo-SanitizedText $result.stdout
    $sanitizedStderr = ConvertTo-SanitizedText $result.stderr
    $output = [ordered] @{
        label = "sanitized-provider-output"
        provider = "grok"
        run_label = $label
        stdout = [ordered] @{
            label = "sanitized-stdout"
            content = $sanitizedStdout
            utf8_sha256 = Get-TextSha256 $sanitizedStdout
        }
        stderr = [ordered] @{
            label = "sanitized-stderr"
            content = $sanitizedStderr
            utf8_sha256 = Get-TextSha256 $sanitizedStderr
        }
        raw = [ordered] @{
            label = "raw-provider-output-bytes"
            content_saved = $false
            stdout_bytes = $result.raw_stdout_bytes
            stderr_bytes = $result.raw_stderr_bytes
            stdout_bytes_sha256 = $result.raw_stdout_bytes_sha256
            stderr_bytes_sha256 = $result.raw_stderr_bytes_sha256
            combined_bytes_sha256 = $result.raw_combined_bytes_sha256
        }
        process = [ordered] @{
            started_at_utc = $result.started_at_utc
            completed_at_utc = $result.completed_at_utc
            process_exited = $result.process_exited
            timed_out = $result.timed_out
            exit_code = $result.exit_code
        }
    }
    Write-Json (Join-Path $runRoot "sanitized-output.json") $output
    return $output
}

function Get-ReviewAssertions([string] $sanitizedStdout, [string] $sanitizedStderr) {
    $text = ($sanitizedStdout, $sanitizedStderr) -join "`r`n"
    $match = [regex]::Match(
        $text,
        "(?s)BEGIN_PERSISTENCE_REVIEW\s*(\{.*?\})\s*END_PERSISTENCE_REVIEW"
    )
    if (-not $match.Success) {
        return [ordered] @{
            block_found = $false
            parse_error = "Persistence review block was not found."
        }
    }

    try {
        $parsed = $match.Groups[1].Value | ConvertFrom-Json
        $evidence = @()
        if ($parsed.PSObject.Properties.Name -contains "evidence" -and $null -ne $parsed.evidence) {
            $evidence = @($parsed.evidence | ForEach-Object { [string] $_ })
        }

        return [ordered] @{
            block_found = $true
            finding_id = if ($parsed.PSObject.Properties.Name -contains "finding_id") { [string] $parsed.finding_id } else { $null }
            finding_status = if ($parsed.PSObject.Properties.Name -contains "finding_status") { [string] $parsed.finding_status } else { $null }
            prior_finding_status = if ($parsed.PSObject.Properties.Name -contains "prior_finding_status") { [string] $parsed.prior_finding_status } else { $null }
            decision_contract_assertion = if ($parsed.PSObject.Properties.Name -contains "decision_contract_assertion") { [string] $parsed.decision_contract_assertion } else { $null }
            evidence = @($evidence)
            information_sufficiency = if ($parsed.PSObject.Properties.Name -contains "information_sufficiency") { [string] $parsed.information_sufficiency } else { $null }
        }
    }
    catch {
        return [ordered] @{
            block_found = $true
            parse_error = ConvertTo-SanitizedText $_.Exception.ToString()
        }
    }
}

function Test-ExactViolation([object] $assertions) {
    if (-not $assertions.block_found -or $null -ne $assertions.parse_error) {
        return $false
    }

    $evidenceText = (@($assertions.evidence) -join " ")
    return $assertions.prior_finding_status -eq "active" -and
        $assertions.decision_contract_assertion -eq "fail" -and
        $assertions.information_sufficiency -eq "sufficient" -and
        $evidenceText -match "(?i)focus-mode" -and
        $evidenceText -match "(?i)quick-check" -and
        $evidenceText -match "(?i)(wire|contract|consumer|lantern-pulse|PPR-001)"
}

function Test-Resolved([object] $assertions) {
    if (-not $assertions.block_found -or $null -ne $assertions.parse_error) {
        return $false
    }

    return $assertions.prior_finding_status -eq "resolved" -and
        $assertions.decision_contract_assertion -eq "pass" -and
        $assertions.information_sufficiency -eq "sufficient"
}

function Test-RunSucceeded([object] $result) {
    return $result.process_exited -and -not $result.timed_out -and $result.exit_code -eq 0
}

$experimentRoot = Get-ExperimentRoot
$repositoryRoot = Get-RepositoryRoot $experimentRoot
$evidenceRoot = Join-Path $experimentRoot "evidence\grok\persistence-control"
$script:AllowedEvidencePrefix = "experiments/persistent-purpose-reviewer/evidence/grok/persistence-control/"
$script:AllowedScriptPath = "experiments/persistent-purpose-reviewer/scripts/run-grok-persistence-control.ps1"
$persistentRoot = Join-Path $evidenceRoot "persistent"
$freshRoot = Join-Path $evidenceRoot "fresh-control"
$cliPath = (Get-Command grok.exe -ErrorAction Stop).Source
$model = "grok-4.6"
$systemPrompt = "You are a read-only Persistent Purpose Reviewer. Use only the prompt and designated fixture text passed in this turn. Do not access files, shell, network, credentials, metadata, home content, or session history outside this conversation. Return only the requested review block."

New-Item -ItemType Directory -Force -Path $evidenceRoot, $persistentRoot, $freshRoot | Out-Null

$baselineGit = Get-GitSnapshot $repositoryRoot
$baselineStatus = @($baselineGit.status)
Write-Json (Join-Path $evidenceRoot "pre-git-snapshot.json") $baselineGit

$static = [ordered] @{
    provider = "grok"
    executable = "grok.exe"
    version = Invoke-CapturedProcess $cliPath @("--version") $experimentRoot 120
    help = Invoke-CapturedProcess $cliPath @("--help") $experimentRoot 120
    headless_help = Invoke-CapturedProcess $cliPath @("agent", "headless", "--help") $experimentRoot 120
    models = Invoke-CapturedProcess $cliPath @("models") $experimentRoot 120
}
$staticForEvidence = [ordered] @{}
foreach ($key in $static.Keys) {
    if ($key -eq "provider" -or $key -eq "executable") {
        $staticForEvidence[$key] = $static[$key]
        continue
    }

    $probe = $static[$key]
    $staticForEvidence[$key] = [ordered] @{
        started_at_utc = $probe.started_at_utc
        completed_at_utc = $probe.completed_at_utc
        process_exited = $probe.process_exited
        timed_out = $probe.timed_out
        exit_code = $probe.exit_code
        stdout = ConvertTo-SanitizedText $probe.stdout
        stderr = ConvertTo-SanitizedText $probe.stderr
        raw_stdout_bytes_sha256 = $probe.raw_stdout_bytes_sha256
        raw_stderr_bytes_sha256 = $probe.raw_stderr_bytes_sha256
        raw_combined_bytes_sha256 = $probe.raw_combined_bytes_sha256
    }
}
Write-Json (Join-Path $evidenceRoot "cli-static-help-version.json") $staticForEvidence

$fixtureRoot = Join-Path $experimentRoot "fixtures\persistence-control"
$promptRoot = Join-Path $experimentRoot "prompts\persistence-control"
$r1Paths = @(
    "prompts\persistence-control\round-1.md",
    "fixtures\persistence-control\round-1-context.md",
    "fixtures\persistence-control\round-1-candidate.md"
)
$r2Paths = @(
    "prompts\persistence-control\round-2.md",
    "fixtures\persistence-control\round-2-candidate.md"
)
$r3Paths = @(
    "prompts\persistence-control\round-3.md",
    "fixtures\persistence-control\round-3-candidate.md"
)
$persistentR1Payload = New-Payload $r1Paths $experimentRoot
$persistentR2Payload = New-Payload $r2Paths $experimentRoot
$persistentR3Payload = New-Payload $r3Paths $experimentRoot
$freshR2Payload = $persistentR2Payload

$persistentSessionId = [guid]::NewGuid().ToString()
do {
    $freshSessionId = [guid]::NewGuid().ToString()
} while ($freshSessionId -eq $persistentSessionId)
$persistentSessionHash = Get-TextSha256 $persistentSessionId
$freshSessionHash = Get-TextSha256 $freshSessionId

$runDefinitions = @(
    [ordered] @{
        label = "persistent-round-1"
        control = "persistent"
        round = 1
        outputRoot = Join-Path $persistentRoot "round-1"
        relativePaths = $r1Paths
        payload = $persistentR1Payload
        sessionMode = "new"
        sessionId = $persistentSessionId
        sessionHash = $persistentSessionHash
        fullContextSent = $true
    },
    [ordered] @{
        label = "persistent-round-2"
        control = "persistent"
        round = 2
        outputRoot = Join-Path $persistentRoot "round-2"
        relativePaths = $r2Paths
        payload = $persistentR2Payload
        sessionMode = "resume"
        sessionId = $persistentSessionId
        sessionHash = $persistentSessionHash
        fullContextSent = $false
    },
    [ordered] @{
        label = "persistent-round-3"
        control = "persistent"
        round = 3
        outputRoot = Join-Path $persistentRoot "round-3"
        relativePaths = $r3Paths
        payload = $persistentR3Payload
        sessionMode = "resume"
        sessionId = $persistentSessionId
        sessionHash = $persistentSessionHash
        fullContextSent = $false
    },
    [ordered] @{
        label = "fresh-control-round-2"
        control = "fresh-control"
        round = 2
        outputRoot = Join-Path $freshRoot "round-2"
        relativePaths = $r2Paths
        payload = $freshR2Payload
        sessionMode = "new"
        sessionId = $freshSessionId
        sessionHash = $freshSessionHash
        fullContextSent = $false
    }
)

$runRecords = [ordered] @{}
$assertionRecords = [ordered] @{}

foreach ($definition in $runDefinitions) {
    $runRoot = [string] $definition.outputRoot
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $preRunGit = Get-GitSnapshot $repositoryRoot
    Write-Json (Join-Path $runRoot "pre-git-snapshot.json") $preRunGit

    $manifestFiles = @(
        $definition.relativePaths | ForEach-Object {
            Get-FileManifestEntry $experimentRoot $_
        }
    )
    $payloadBytes = ([Text.UTF8Encoding]::new($false)).GetBytes([string] $definition.payload)
    $manifest = [ordered] @{
        schema_version = 1
        provider = "grok"
        control = $definition.control
        round = $definition.round
        session_hash = $definition.sessionHash
        session_id_saved = $false
        session_identity = if ($definition.control -eq "persistent") {
            if ($definition.round -eq 1) { "new specific session; R2/R3 resume the same supplied ID" } else { "resume the same specific supplied ID as persistent R1" }
        }
        else {
            "new session; intentionally different from persistent session"
        }
        input_files = @($manifestFiles)
        input_payload = [ordered] @{
            label = "prompt-plus-designated-fixture-text"
            composition = "UTF-8 decoded file text joined with CRLF CRLF; no additional user data"
            bytes = $payloadBytes.Length
            sha256 = Get-Sha256 $payloadBytes
        }
        full_context_sent = [bool] $definition.fullContextSent
        previous_response_sent = $false
        previous_response_full_text_sent = $false
        semantic_decision_mapping_finding_replayed = $false
        full_context_and_prior_output_not_sent_flags = [ordered] @{
            full_context_not_sent = -not [bool] $definition.fullContextSent
            prior_output_not_sent = $true
            semantic_decision_mapping_finding_not_sent = $true
        }
        external_meaning_data_boundary = "prompt and listed fixture text only"
    }
    if ($definition.label -eq "persistent-round-2" -or $definition.label -eq "fresh-control-round-2") {
        $manifest.input_payload.persistent_r2_fresh_r2_equality_sha256 = Get-TextSha256 $persistentR2Payload
        $manifest.input_payload.equality_reference = "persistent/round-2 and fresh-control/round-2 use the same payload string instance"
    }
    Write-Json (Join-Path $runRoot "input-payload-manifest.json") $manifest

    $result = $null
    $failure = $null
    try {
        $arguments = New-CommandArguments `
            -experimentRoot $experimentRoot `
            -model $model `
            -sessionMode $definition.sessionMode `
            -sessionId $definition.sessionId `
            -payload $definition.payload `
            -systemPrompt $systemPrompt
        $result = Invoke-CapturedProcess $cliPath $arguments $experimentRoot 1200
    }
    catch {
        $failure = ConvertTo-SanitizedText $_.Exception.ToString()
        $result = [ordered] @{
            started_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            process_exited = $false
            timed_out = $false
            exit_code = $null
            stdout = ""
            stderr = "[process exception recorded in failure.txt]"
            raw_stdout_bytes_sha256 = Get-Sha256 ([byte[]]::new(0))
            raw_stderr_bytes_sha256 = Get-Sha256 ([byte[]]::new(0))
            raw_combined_bytes_sha256 = Get-Sha256 ([byte[]]::new(0))
            raw_stdout_bytes = 0
            raw_stderr_bytes = 0
        }
    }

    $sanitizedOutput = Save-SanitizedOutput $runRoot $definition.label $result
    if ($null -ne $failure) {
        Write-Text (Join-Path $runRoot "failure.txt") @(
            "failure_class=process_exception"
            "exception_trace_sanitized=true"
            $failure
        )
    }

    $assertions = Get-ReviewAssertions $sanitizedOutput.stdout.content $sanitizedOutput.stderr.content
    Write-Json (Join-Path $runRoot "review-assertions.json") $assertions
    $assertionRecords[$definition.label] = $assertions

    $postRunGit = Get-GitSnapshot $repositoryRoot
    Write-Json (Join-Path $runRoot "post-git-snapshot.json") $postRunGit
    $runDelta = Get-StatusDelta $preRunGit.status $postRunGit.status
    $outsideRunDelta = Get-OutsideAllowedChanges $runDelta
    $outsideRunProductionDelta = Get-OutsideProductionChanges $runDelta
    Write-Json (Join-Path $runRoot "git-change-verification.json") ([ordered] @{
        pre_status_count = @($preRunGit.status).Count
        post_status_count = @($postRunGit.status).Count
        status_delta = @($runDelta)
        outside_our_write_boundary_delta = @($outsideRunDelta)
        outside_experiment_delta = @($outsideRunProductionDelta)
        production_tree_changed_during_run = $outsideRunProductionDelta.Count -gt 0
        allowed_write_boundary = @(
            "experiments/persistent-purpose-reviewer/evidence/grok/persistence-control/"
            "experiments/persistent-purpose-reviewer/scripts/run-grok-persistence-control.ps1"
        )
    })

    $runRecords[$definition.label] = [ordered] @{
        control = $definition.control
        round = $definition.round
        session_hash = $definition.sessionHash
        output_root = $runRoot.Substring($experimentRoot.Length + 1).Replace("\", "/")
        command_shape = Get-CommandShape $definition.sessionMode
        exit_code = $result.exit_code
        process_exited = $result.process_exited
        timed_out = $result.timed_out
        raw_combined_bytes_sha256 = $result.raw_combined_bytes_sha256
        payload_sha256 = $manifest.input_payload.sha256
        outside_our_write_boundary_delta_count = $outsideRunDelta.Count
        outside_experiment_delta_count = $outsideRunProductionDelta.Count
    }
}

$finalGit = Get-GitSnapshot $repositoryRoot
Write-Json (Join-Path $evidenceRoot "post-git-snapshot.json") $finalGit
$finalDelta = Get-StatusDelta $baselineStatus $finalGit.status
$outsideOurWriteBoundaryDelta = Get-OutsideAllowedChanges $finalDelta
$outsideProductionDelta = Get-OutsideProductionChanges $finalDelta
$persistentLabels = @("persistent-round-1", "persistent-round-2", "persistent-round-3")
$persistentSucceeded = @($persistentLabels | Where-Object { Test-RunSucceeded $runRecords[$_] }).Count -eq 3
$freshSucceeded = Test-RunSucceeded $runRecords["fresh-control-round-2"]
$persistentSameSession = ($runRecords["persistent-round-1"].session_hash -eq $runRecords["persistent-round-2"].session_hash) -and
    ($runRecords["persistent-round-2"].session_hash -eq $runRecords["persistent-round-3"].session_hash)
$freshDifferentSession = $runRecords["fresh-control-round-2"].session_hash -ne $runRecords["persistent-round-1"].session_hash
$persistentExact = Test-ExactViolation $assertionRecords["persistent-round-2"]
$freshExact = Test-ExactViolation $assertionRecords["fresh-control-round-2"]
$persistentResolved = Test-Resolved $assertionRecords["persistent-round-3"]
$r1Detected = $assertionRecords["persistent-round-1"].block_found -and
    $assertionRecords["persistent-round-1"].finding_id -eq "PPR-001" -and
    $assertionRecords["persistent-round-1"].finding_status -eq "active"
$freshWeaker = -not $freshExact
$payloadHasDecisionToken = $persistentR2Payload -match "(?i)quick-check"
$payloadHasRejectionRationale = $persistentR2Payload -match "(?i)(旧外部\s*consumer|wire\s*contract|quick-check|rejected\s+because)"

$semanticOutcome = if (-not ($persistentSucceeded -and $freshSucceeded)) {
    "Failure"
}
elseif ($persistentExact -and $freshWeaker -and $persistentResolved) {
    "Yes"
}
elseif ($persistentExact -and $persistentResolved -and $freshExact) {
    "Partial"
}
else {
    "No"
}

$architectureOutcome = if ($persistentSucceeded) { "Feasible" } else { "Blocked" }
$failureLabels = @($runRecords.Keys | Where-Object { -not (Test-RunSucceeded $runRecords[$_]) })
$summaryLines = @(
    "# Grok Persistent Purpose Reviewer 実験結果",
    "",
    "## 実行概要",
    "",
    "- provider: Grok Build CLI",
    "- CLI version evidence: cli-static-help-version.json",
    ("- model: " + $model),
    ("- branch: " + [string] $finalGit.branch),
    "- experiment cwd: experiments/persistent-purpose-reviewer",
    ("- persistent session hash: " + $persistentSessionHash + "（R1/R2/R3 は同一）"),
    ("- fresh session hash: " + $freshSessionHash + "（persistent と異なる）"),
    ("- Persistent R2 / Fresh R2 payload SHA-256: " + (Get-TextSha256 $persistentR2Payload) + "（完全一致）"),
    "",
    "## 判定",
    "",
    "- Semantic persistence qualification: **$semanticOutcome**",
    "- Architecture feasibility（同一 session resume の実行可能性）: **$architectureOutcome**",
    "- Round 1 の PPR-001 検出: **$r1Detected**",
    "- Persistent Round 2 の unhinted exact violation 検出: **$persistentExact**",
    "- Fresh Round 2 の exact violation 検出: **$freshExact**",
    "- Persistent Round 3 の解消: **$persistentResolved**",
    "- Fresh control は Persistent R2 と同一 payload bytes: **$($persistentR2Payload -ceq $freshR2Payload)**",
    "- Round 2 payload に quick-check を含む: **$payloadHasDecisionToken**",
    "- Round 2 payload に棄却理由を含む: **$payloadHasRejectionRationale**",
    "",
    "## 送信境界",
    "",
    "- R1 は Round 1 prompt/context/candidate のみを送信。",
    "- Persistent R2/R3 は各 prompt/candidate のみを送信し、full context、previous response、semantic decision/mapping/finding は再送していない。",
    "- Fresh R2 は新規 session で Persistent R2 と同じ prompt/candidate composition bytes のみを送信。",
    "- Fresh R2 の初期 bootstrap と Persistent R2 の --resume の差は fresh-control/round-2/input-payload-manifest.json と各 command shape に記録。",
    "- `session_id`、secret、環境値は evidence に保存していない。保存した session hash は UUID の SHA-256。",
    "",
    "## 制限と失敗",
    "",
    "- CLI の permission/sandbox/options は evidence の command shape に記録。",
    "- OS/network audit の不在は architecture failure として扱っていない。",
    ("- 実行失敗 run: " + $(if ($failureLabels.Count -eq 0) { "なし" } else { $failureLabels -join ", " }))
)
if (-not $persistentExact -and
    $assertionRecords["persistent-round-2"].prior_finding_status -eq "active" -and
    $assertionRecords["persistent-round-2"].decision_contract_assertion -eq "fail") {
    $summaryLines += "- Persistent R2 は active/fail/sufficient だったが、期待 wire token と wire-contract rationale の根拠が不足し、厳格な exact violation 条件を満たさない。"
}
if ($freshExact -and $payloadHasDecisionToken -eq $false -and $payloadHasRejectionRationale -eq $false) {
    $summaryLines += "- Fresh が正解を推測した場合は fixture を反復調整せず、payload leakage の証拠なしとして記録し、qualification は Partial/No に留める。"
}
if ($outsideProductionDelta.Count -eq 0) {
    $summaryLines += "- production tree changes: なし（baseline との差分で experiment root 外変更なし）。"
}
else {
    $summaryLines += "- production tree changes: あり。production-change-verification.json を確認する。"
}

Write-Json (Join-Path $evidenceRoot "run-metadata.json") ([ordered] @{
    schema_version = 1
    provider = "grok"
    cli_executable = "grok.exe"
    model = $model
    cwd = "experiments/persistent-purpose-reviewer"
    permission_mode = "plan"
    sandbox = "read-only"
    disable_web_search = $true
    no_memory = $true
    no_subagents = $true
    allowed_tools = @("read", "view", "grep")
    disallowed_tools = @("write", "shell", "task", "edit_file", "run_shell_command")
    system_wrapper = "safe reviewer role only; no fixture decision data"
    command_shapes = [ordered] @{
        persistent_round_1 = Get-CommandShape "new"
        persistent_round_2 = Get-CommandShape "resume"
        persistent_round_3 = Get-CommandShape "resume"
        fresh_control_round_2 = Get-CommandShape "new"
    }
    persistent_session_hash = $persistentSessionHash
    fresh_session_hash = $freshSessionHash
    persistent_same_session_hash = $persistentSameSession
    fresh_session_different_hash = $freshDifferentSession
    session_id_saved = $false
    secret_saved = $false
    environment_values_saved = $false
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
})

Write-Json (Join-Path $evidenceRoot "machine-metadata.json") ([ordered] @{
    schema_version = 1
    os = [Environment]::OSVersion.VersionString
    platform = "Windows"
    architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    process_architecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
    powershell = $PSVersionTable.PSVersion.ToString()
    culture = [Globalization.CultureInfo]::CurrentCulture.Name
    cwd = "experiments/persistent-purpose-reviewer"
    machine_name_saved = $false
    user_name_saved = $false
    environment_values_saved = $false
})

Write-Json (Join-Path $evidenceRoot "production-change-verification.json") ([ordered] @{
    baseline_status_count = @($baselineStatus).Count
    final_status_count = @($finalGit.status).Count
    status_delta = @($finalDelta)
    outside_our_write_boundary_delta = @($outsideOurWriteBoundaryDelta)
    outside_production_delta = @($outsideProductionDelta)
    production_tree_unchanged = $outsideProductionDelta.Count -eq 0
    allowed_write_boundary = @(
        "experiments/persistent-purpose-reviewer/evidence/grok/persistence-control/"
        "experiments/persistent-purpose-reviewer/scripts/run-grok-persistence-control.ps1"
    )
    note = "Pre-existing unrelated worktree status was not reverted or modified."
})

Write-Json (Join-Path $evidenceRoot "semantic-evaluation.json") ([ordered] @{
    semantic_persistence_qualification = $semanticOutcome
    architecture_feasibility = $architectureOutcome
    round_1_detected_ppr_001 = $r1Detected
    persistent_round_2_exact_unhinted_violation = $persistentExact
    fresh_round_2_exact_violation = $freshExact
    fresh_round_2_materially_weaker = $freshWeaker
    persistent_round_3_resolved = $persistentResolved
    prompt_candidate_leakage = [ordered] @{
        round_2_payload_contains_decision_token = $payloadHasDecisionToken
        round_2_payload_contains_rejection_rationale = $payloadHasRejectionRationale
        conclusion = if (-not $payloadHasDecisionToken -and -not $payloadHasRejectionRationale) { "no explicit fixture leakage detected" } else { "explicit leakage detected; qualification cannot be treated as clean" }
    }
    provider_run_failures = @($failureLabels)
    note = "OS/network audit absence is not classified as architecture failure."
})

Write-Text (Join-Path $evidenceRoot "summary.md") ($summaryLines -join "`r`n")

try {
    $finalOutside = @($outsideProductionDelta)
    if ($finalOutside.Count -gt 0) {
        throw "Production tree changed outside the allowed evidence/script boundary."
    }
}
catch {
    Write-Text (Join-Path $evidenceRoot "fatal-verification-failure.txt") (ConvertTo-SanitizedText $_.Exception.ToString())
    throw
}
