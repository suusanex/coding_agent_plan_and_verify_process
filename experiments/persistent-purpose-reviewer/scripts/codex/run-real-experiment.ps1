[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Get-TextHash([string] $text) {
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        return ([Convert]::ToHexString($sha256.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-ShortHash([string] $text) {
    return (Get-TextHash $text).Substring(0, 12)
}

function ConvertTo-SafeText([string] $text) {
    if ($null -eq $text) {
        return ""
    }

    $safe = $text
    $safe = [regex]::Replace($safe, "(?i)(authorization\s*:\s*(?:bearer|token|basic)\s+)[^\s]+", '$1[REDACTED]')
    $safe = [regex]::Replace($safe, "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+", "[REDACTED]")
    $safe = [regex]::Replace($safe, "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|credential|cookie)\s*([=:])\s*[^\s,;]+", '$1[REDACTED]')
    $safe = [regex]::Replace($safe, "(?i)\b(?:ghp|gho|github_pat|sk)-[A-Za-z0-9_=-]+", "[REDACTED]")
    $safe = [regex]::Replace($safe, "(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b", "[SESSION_ID_REDACTED]")
    $safe = [regex]::Replace($safe, "(?i)[A-Z]:\\Users\\[^\\\r\n ]+", "[HOME_PATH_REDACTED]")
    return $safe
}

function Get-ExperimentRoot {
    $scriptRoot = (Resolve-Path $PSScriptRoot).Path
    return (Resolve-Path (Join-Path $scriptRoot "..\..\")).Path
}

function Get-RepositoryRoot([string] $experimentRoot) {
    $topLevel = (& git -C $experimentRoot rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        throw "Git repository root could not be resolved."
    }

    return (Resolve-Path $topLevel).Path
}

function Get-StatusLines([string] $repositoryRoot) {
    return @(
        & git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>&1 |
            ForEach-Object { [string] $_ } |
            Sort-Object
    )
}

function Get-StatusOutsideProduction([string[]] $statusLines) {
    $experimentBoundary = "experiments/persistent-purpose-reviewer/"
    return @(
        $statusLines |
            Where-Object {
                $normalized = $_.Replace("\", "/")
                -not $normalized.Contains($experimentBoundary, [StringComparison]::OrdinalIgnoreCase)
            }
    )
}

function Invoke-ProcessCapture(
    [string[]] $arguments,
    [string] $prompt,
    [string] $outputPath,
    [int] $timeoutSeconds = 900
) {
    $start = [DateTimeOffset]::UtcNow
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $script:CodexExecutable
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $process.StartInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $process.StartInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)
    foreach ($argument in (@($script:CodexPrefixArguments) + @($arguments))) {
        [void] $process.StartInfo.ArgumentList.Add($argument)
    }

    try {
        if (-not $process.Start()) {
            throw "Codex process could not be started."
        }

        $inputError = $null
        if ($null -ne $prompt) {
            try {
                $process.StandardInput.Write($prompt)
            }
            catch {
                $inputError = $_.Exception.ToString()
            }
        }
        try {
            $process.StandardInput.Close()
        }
        catch {
            if ($null -eq $inputError) {
                $inputError = $_.Exception.ToString()
            }
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($timeoutSeconds * 1000)
        if ($timedOut) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit()
        }

        return [ordered] @{
            started_at_utc = $start.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            process_exited = -not $timedOut
            timed_out = $timedOut
            exit_code = if ($timedOut) { $null } else { $process.ExitCode }
            stdout = $stdoutTask.GetAwaiter().GetResult()
            stderr = (($inputError, $stderrTask.GetAwaiter().GetResult()) |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n"
            output_path = $outputPath
        }
    }
    catch {
        return [ordered] @{
            started_at_utc = $start.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            process_exited = $false
            timed_out = $false
            exit_code = $null
            stdout = ""
            stderr = $_.Exception.ToString()
            output_path = $outputPath
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-SessionId([string] $machineOutput) {
    $parsedGuid = [guid]::Empty
    foreach ($line in ($machineOutput -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json
            if ($event.PSObject.Properties.Name -contains "thread_id" -and
                [guid]::TryParse([string] $event.thread_id, [ref] $parsedGuid)) {
                return [string] $event.thread_id
            }
        }
        catch {
        }
    }

    $match = [regex]::Match(
        $machineOutput,
        "(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"
    )
    if ($match.Success) {
        return $match.Value
    }

    return $null
}

function Get-EventTypes([string] $machineOutput) {
    $types = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($machineOutput -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json
            if ($event.PSObject.Properties.Name -contains "type") {
                $type = [string] $event.type
                if (-not [string]::IsNullOrWhiteSpace($type) -and -not $types.Contains($type)) {
                    $types.Add($type)
                }
            }
        }
        catch {
        }
    }

    return @($types)
}

function Get-ResponseText([string] $outputPath, [string] $machineOutput) {
    if (-not [string]::IsNullOrWhiteSpace($outputPath) -and (Test-Path -LiteralPath $outputPath)) {
        $text = Get-Content -LiteralPath $outputPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            return $text
        }
    }

    $messages = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($machineOutput -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            $event = $line | ConvertFrom-Json
            if ($event.PSObject.Properties.Name -contains "item" -and $null -ne $event.item) {
                if ($event.item.PSObject.Properties.Name -contains "type" -and
                    [string] $event.item.type -eq "agent_message") {
                    if ($event.item.PSObject.Properties.Name -contains "text") {
                        $messages.Add([string] $event.item.text)
                    }
                }
            }
        }
        catch {
        }
    }

    if ($messages.Count -gt 0) {
        return $messages[$messages.Count - 1]
    }

    return ""
}

function Get-FileManifest([string] $basePath, [string[]] $paths) {
    return @(
        $paths | ForEach-Object {
            $resolved = (Resolve-Path (Join-Path $basePath $_)).Path
            [ordered] @{
                file = $_
                sha256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
                bytes = (Get-Item -LiteralPath $resolved).Length
            }
        }
    )
}

function Save-Utf8([string] $path, [string] $text) {
    Set-Content -LiteralPath $path -Value $text -Encoding utf8
}

function Save-Json([string] $path, $value) {
    $value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
}

function New-InputManifest(
    [int] $round,
    [string] $basePath,
    [string] $promptPath,
    [string[]] $fixturePaths,
    [bool] $goalContextFullSent,
    [bool] $priorOutputReplayed,
    [string] $minimalFollowUp
) {
    $allPaths = @($promptPath) + @($fixturePaths)
    return [ordered] @{
        schema_version = 1
        round = $round
        role = "persistent-purpose-reviewer"
        prompt_file = $promptPath
        input_files = Get-FileManifest $basePath $allPaths
        goal_context_full_sent = $goalContextFullSent
        goal_context_replayed = $false
        prior_reviewer_output_replayed = $priorOutputReplayed
        prior_reviewer_output_full_sent = $false
        semantic_secret_replayed = $false
        minimal_follow_up = $minimalFollowUp
        external_model_input_boundary = "fixed prompt plus listed fixture files only"
    }
}

function Get-Assertion([string] $response, [string] $name) {
    $match = [regex]::Match($response, "(?im)^" + [regex]::Escape($name) + ":\s*(PASS|FAIL|UNKNOWN)\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return "MISSING"
}

function Get-FindingIds([string] $response) {
    return @(
        [regex]::Matches($response, "(?i)\bPUR-\d+\b") |
            ForEach-Object { $_.Value.ToUpperInvariant() } |
            Select-Object -Unique
    )
}

function Save-ResponseEvidence(
    [int] $round,
    [string] $timestamp,
    [string] $sessionHash,
    [string] $response,
    [string] $evidenceRoot
) {
    $rawRoot = Join-Path $evidenceRoot "raw"
    $sanitizedRoot = Join-Path $evidenceRoot "sanitized"
    New-Item -ItemType Directory -Force -Path $rawRoot, $sanitizedRoot | Out-Null

    $safeResponse = ConvertTo-SafeText $response
    $baseName = "$timestamp-round-{0:D2}-purpose-reviewer-codex-session-$sessionHash" -f $round
    $rawPath = Join-Path $rawRoot "$baseName.raw.md"
    $sanitizedPath = Join-Path $sanitizedRoot "$baseName.md"
    Save-Utf8 $rawPath $safeResponse
    Save-Utf8 $sanitizedPath $safeResponse

    return [ordered] @{
        raw_path = $rawPath
        sanitized_path = $sanitizedPath
        sanitization_applied_before_save = $true
        response_sha256_after_sanitization = Get-TextHash $safeResponse
    }
}

function Get-SafeError([string] $stderr) {
    $safe = ConvertTo-SafeText $stderr
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "[no stderr]"
    }

    return $safe.Trim()
}

$experimentRoot = Get-ExperimentRoot
$repositoryRoot = Get-RepositoryRoot $experimentRoot
$evidenceRoot = Join-Path $experimentRoot "evidence\codex"
New-Item -ItemType Directory -Force -Path $evidenceRoot | Out-Null

$codexShim = (Get-Command codex.cmd -ErrorAction Stop).Source
$codexNpmRoot = Split-Path $codexShim -Parent
$script:CodexExecutable = if (Test-Path (Join-Path $codexNpmRoot "node.exe")) {
    (Join-Path $codexNpmRoot "node.exe")
}
else {
    (Get-Command node.exe -ErrorAction Stop).Source
}
$script:CodexPrefixArguments = @(
    (Join-Path $codexNpmRoot "node_modules\@openai\codex\bin\codex.js")
)

$runTimestamp = [DateTimeOffset]::UtcNow.ToString("yyyyMMddTHHmmssZ")
$runStart = [DateTimeOffset]::UtcNow
$baselineStatus = Get-StatusLines $repositoryRoot
Save-Utf8 (Join-Path $evidenceRoot "$runTimestamp-pre-experiment-git-status.txt") ($baselineStatus -join "`r`n")

$staticProbes = @(
    [ordered] @{ name = "version"; args = @("--version") },
    [ordered] @{ name = "exec-help"; args = @("exec", "--help") },
    [ordered] @{ name = "exec-resume-help"; args = @("exec", "resume", "--help") }
)
foreach ($probe in $staticProbes) {
    $result = Invoke-ProcessCapture -arguments $probe.args -prompt $null -outputPath $null -timeoutSeconds 120
    $safeText = ConvertTo-SafeText ($result.stdout + $result.stderr)
    Save-Utf8 (Join-Path $evidenceRoot "$runTimestamp-static-$($probe.name).txt") $safeText
}

$roundDefinitions = @(
    [ordered] @{
        number = 1
        prompt = "prompts\round-1.md"
        fixtures = @("fixtures\purpose-context.md", "fixtures\round-1-candidate.md")
        context = $true
        priorOutput = $false
        followUp = ""
    },
    [ordered] @{
        number = 2
        prompt = "prompts\round-2.md"
        fixtures = @("fixtures\round-2-remediation.md")
        context = $false
        priorOutput = $false
        followUp = "前回の finding の解消確認だけを行う。"
    },
    [ordered] @{
        number = 3
        prompt = "prompts\round-3.md"
        fixtures = @("fixtures\round-3-remediation.md")
        context = $false
        priorOutput = $false
        followUp = "前回の finding の解消確認だけを行う。"
    }
)

$sessionId = $null
$sessionHash = $null
$roundRecords = [System.Collections.Generic.List[object]]::new()
$failureRecords = [System.Collections.Generic.List[object]]::new()
$allRoundsCompleted = $true

foreach ($definition in $roundDefinitions) {
    $round = [int] $definition.number
    $roundStart = [DateTimeOffset]::UtcNow
    $preStatus = Get-StatusLines $repositoryRoot
    $promptRelative = $definition.prompt.Replace("\", "/")
    $fixtureRelative = @($definition.fixtures | ForEach-Object { $_.Replace("\", "/") })
    $promptPath = Join-Path $experimentRoot $definition.prompt
    $fixturePaths = @($definition.fixtures | ForEach-Object { Join-Path $experimentRoot $_ })
    $manifest = New-InputManifest `
        -round $round `
        -basePath $experimentRoot `
        -promptPath $promptRelative `
        -fixturePaths $fixtureRelative `
        -goalContextFullSent $definition.context `
        -priorOutputReplayed $definition.priorOutput `
        -minimalFollowUp $definition.followUp
    Save-Json (Join-Path $evidenceRoot ("$runTimestamp-round-{0:D2}-input-manifest.json" -f $round)) $manifest

    $promptParts = [System.Collections.Generic.List[string]]::new()
    $promptParts.Add((Get-Content -LiteralPath $promptPath -Raw))
    foreach ($fixturePath in $fixturePaths) {
        $promptParts.Add((Get-Content -LiteralPath $fixturePath -Raw))
    }
    if (-not [string]::IsNullOrWhiteSpace($definition.followUp)) {
        $promptParts.Add($definition.followUp)
    }
    $promptText = ($promptParts -join "`r`n`r`n")

    $workingOutput = Join-Path $evidenceRoot ("$runTimestamp-round-{0:D2}-working-output.txt" -f $round)
    if (Test-Path -LiteralPath $workingOutput) {
        Remove-Item -LiteralPath $workingOutput -Force
    }

    if ($round -eq 1) {
        $arguments = @(
            "exec", "--json", "--color", "never",
            "-s", "read-only",
            "-C", $experimentRoot,
            "-m", "gpt-5.6-luna",
            "-"
        )
        $commandShape = @(
            "codex exec --json --color never -s read-only",
            "-C experiments/persistent-purpose-reviewer -m gpt-5.6-luna",
            "-"
        )
    }
    else {
        if ([string]::IsNullOrWhiteSpace($sessionId)) {
            $allRoundsCompleted = $false
            $failureRecords.Add([ordered] @{
                round = $round
                classification = "missing-session-identity"
                exit_code = $null
                sanitized_stderr = "[Round 1 did not yield a machine-readable session identity]"
                recovery_attempt = "none; no safe resume target existed"
                conclusion = "Blocked before sending this round; no new session was created."
            })
            break
        }

        $arguments = @(
            "exec", "resume", $sessionId,
            "--json",
            "-"
        )
        $commandShape = @(
            "codex exec resume <session-id> --json",
            "-",
            "resume target is the same session; sandbox/cwd inherited from Round 1"
        )
    }

    $result = Invoke-ProcessCapture `
        -arguments $arguments `
        -prompt $promptText `
        -outputPath $workingOutput `
        -timeoutSeconds 900
    $response = Get-ResponseText -outputPath $workingOutput -machineOutput $result.stdout
    $machineSessionId = Get-SessionId $result.stdout
    if ($round -eq 1 -and -not [string]::IsNullOrWhiteSpace($machineSessionId)) {
        $sessionId = $machineSessionId
        $sessionHash = Get-ShortHash $sessionId
    }
    elseif ($round -gt 1 -and -not [string]::IsNullOrWhiteSpace($machineSessionId) -and
        $machineSessionId -ne $sessionId) {
        $failureRecords.Add([ordered] @{
            round = $round
            classification = "session-identity-mismatch"
            exit_code = $result.exit_code
            sanitized_stderr = "A different machine-reported session identity was observed."
            recovery_attempt = "none; stopped to avoid cross-session evidence"
            conclusion = "Blocked because the resumed session identity did not match Round 1."
        })
        $allRoundsCompleted = $false
    }

    $safeResponse = ConvertTo-SafeText $response
    if (-not [string]::IsNullOrWhiteSpace($sessionHash)) {
        $responseEvidence = Save-ResponseEvidence `
            -round $round `
            -timestamp $runTimestamp `
            -sessionHash $sessionHash `
            -response $response `
            -evidenceRoot $evidenceRoot
    }
    else {
        $responseEvidence = [ordered] @{
            raw_path = $null
            sanitized_path = $null
            sanitization_applied_before_save = $false
            response_sha256_after_sanitization = $null
        }
    }

    $postStatus = Get-StatusLines $repositoryRoot
    $preOutside = Get-StatusOutsideProduction $preStatus
    $postOutside = Get-StatusOutsideProduction $postStatus
    $outsideChanged = ((@($preOutside) -join "`n") -cne (@($postOutside) -join "`n"))
    $responsePresent = -not [string]::IsNullOrWhiteSpace($safeResponse)
    $sameSession = $round -eq 1 -or
        [string]::IsNullOrWhiteSpace($machineSessionId) -or
        $machineSessionId -eq $sessionId
    $success = ($result.exit_code -eq 0) -and (-not $result.timed_out) -and $responsePresent -and
        (-not $outsideChanged) -and $sameSession

    Save-Utf8 (Join-Path $evidenceRoot ("$runTimestamp-round-{0:D2}-pre-git-status.txt" -f $round)) ($preStatus -join "`r`n")
    Save-Utf8 (Join-Path $evidenceRoot ("$runTimestamp-round-{0:D2}-post-git-status.txt" -f $round)) ($postStatus -join "`r`n")

    $machineMetadata = [ordered] @{
        schema_version = 1
        round = $round
        cli = "codex"
        version = "0.147.0"
        model = "gpt-5.6-luna"
        sandbox_requested = "read-only"
        cwd = "experiments/persistent-purpose-reviewer"
        process_exited_before_next_round = $true
        started_at_utc = $result.started_at_utc
        completed_at_utc = $result.completed_at_utc
        process_exited = $result.process_exited
        timed_out = $result.timed_out
        exit_code = $result.exit_code
        event_types = Get-EventTypes $result.stdout
        session_id_sha256_12 = if ($sessionHash) { $sessionHash } else { $null }
        session_identity_source = if ($round -eq 1 -and $machineSessionId) {
            "codex --json machine event thread_id"
        }
        elseif ($round -gt 1 -and $machineSessionId) {
            "codex --json machine event thread_id matched Round 1"
        }
        elseif ($round -gt 1) {
            "resume command targeted the Round 1 session; no new thread_id event"
        }
        else {
            "not found"
        }
        response_present = $responsePresent
        production_change_outside_experiment = $outsideChanged
        production_status_pre = @($preOutside)
        production_status_post = @($postOutside)
        command_shape = $commandShape
        response_evidence = $responseEvidence
    }
    Save-Json (Join-Path $evidenceRoot ("$runTimestamp-round-{0:D2}-machine-metadata.json" -f $round)) $machineMetadata

    if (-not $success) {
        $allRoundsCompleted = $false
        $failureRecords.Add([ordered] @{
            round = $round
            classification = if ($result.timed_out) { "timeout" } elseif ($result.exit_code -ne 0) { "non-zero" } elseif (-not $responsePresent) { "empty-output" } elseif ($outsideChanged) { "worktree-change" } else { "session-identity" }
            exit_code = $result.exit_code
            sanitized_stderr = Get-SafeError $result.stderr
            recovery_attempt = "none; one-shot run stopped without replaying context or duplicating a session"
            conclusion = "Round did not produce a verified successful evidence record."
        })
    }

    if (Test-Path -LiteralPath $workingOutput) {
        Remove-Item -LiteralPath $workingOutput -Force
    }

    $roundRecords.Add([ordered] @{
        round = $round
        success = $success
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        response_sha256 = if ($responseEvidence.response_sha256_after_sanitization) { $responseEvidence.response_sha256_after_sanitization } else { $null }
        session_id_sha256_12 = $sessionHash
        production_change_outside_experiment = $outsideChanged
        assertions = [ordered] @{
            purpose_assertion = Get-Assertion $safeResponse "purpose_assertion"
            rejected_approach_assertion = Get-Assertion $safeResponse "rejected_approach_assertion"
            formal_but_goal_failure_assertion = Get-Assertion $safeResponse "formal_but_goal_failure_assertion"
            mapping_assertion = Get-Assertion $safeResponse "mapping_assertion"
            unknown_handling_assertion = Get-Assertion $safeResponse "unknown_handling_assertion"
            data_preservation_assertion = Get-Assertion $safeResponse "data_preservation_assertion"
            visible_failure_assertion = Get-Assertion $safeResponse "visible_failure_assertion"
            mvp_boundary_assertion = Get-Assertion $safeResponse "mvp_boundary_assertion"
            priority_assertion = Get-Assertion $safeResponse "priority_assertion"
            prior_finding_resolution = Get-Assertion $safeResponse "prior_finding_resolution"
            production_change_assertion = Get-Assertion $safeResponse "production_change_assertion"
        }
        finding_ids = Get-FindingIds $safeResponse
        raw_path = $responseEvidence.raw_path
        sanitized_path = $responseEvidence.sanitized_path
    })

    if (-not $success) {
        break
    }
}

$finalStatus = Get-StatusLines $repositoryRoot
$finalOutside = Get-StatusOutsideProduction $finalStatus
$baselineOutside = Get-StatusOutsideProduction $baselineStatus
$productionChanged = ((@($baselineOutside) -join "`n") -cne (@($finalOutside) -join "`n"))
$runEnd = [DateTimeOffset]::UtcNow

Save-Utf8 (Join-Path $evidenceRoot "$runTimestamp-post-experiment-git-status.txt") ($finalStatus -join "`r`n")
Save-Utf8 (Join-Path $evidenceRoot "$runTimestamp-production-change-check.txt") @(
    "production_changed_outside_allowed_evidence=$productionChanged"
    "baseline_outside_experiment_count=$($baselineOutside.Count)"
    "final_outside_experiment_count=$($finalOutside.Count)"
    "production_scope=paths outside experiments/persistent-purpose-reviewer"
    "production_change_assertion=$(if ($productionChanged) { 'FAIL' } else { 'PASS' })"
) -join "`r`n"

if ($failureRecords.Count -gt 0) {
    Save-Json (Join-Path $evidenceRoot "$runTimestamp-failures.json") @($failureRecords)
}

$runMetadata = [ordered] @{
    schema_version = 1
    cli = "codex"
    version = "0.147.0"
    model = "gpt-5.6-luna"
    experiment_root = "experiments/persistent-purpose-reviewer"
    allowed_write_root = "experiments/persistent-purpose-reviewer/evidence/codex"
    sandbox_requested = "read-only"
    rounds_requested = 3
    rounds_completed = @($roundRecords).Count
    all_rounds_verified = $allRoundsCompleted -and ($roundRecords.Count -eq 3)
    session_id_sha256_12 = $sessionHash
    session_identity_full_id_saved = $false
    initial_process_exited_before_resume = ($roundRecords.Count -gt 1)
    started_at_utc = $runStart.ToString("O")
    completed_at_utc = $runEnd.ToString("O")
    production_changed_outside_experiment = $productionChanged
    input_boundary = "fixture files and fixed prompts only; repository documents and git metadata were not included in constructed prompts"
    network_payload_audit = "not performed"
    native_child_experiment = "not performed"
    rounds = @($roundRecords)
    failures = @($failureRecords)
}
Save-Json (Join-Path $evidenceRoot "$runTimestamp-run-metadata.json") $runMetadata

Write-Output ($runMetadata | ConvertTo-Json -Depth 10)
