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
    Write-Utf8NoBom $Path ($Value | ConvertTo-Json -Depth 30)
}

function ConvertTo-SafeText([string] $Text) {
    $safe = if ($null -eq $Text) { "" } else { $Text }
    $patterns = @(
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"; Replacement = "[REDACTED_BEARER]" },
        @{ Pattern = "(?i)(authorization\s*:\s*(?:bearer|token|basic)\s+)[^\s]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|credential|cookie)\s*([=:])\s*[^\s,;]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\b(?:ghp|gho|github_pat|sk)-[A-Za-z0-9_=-]+"; Replacement = "[REDACTED_TOKEN]" },
        @{ Pattern = "(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"; Replacement = "[SESSION_ID_REDACTED]" },
        @{ Pattern = "(?i)[A-Z]:\\Users\\[^\\\r\n ]+"; Replacement = "<USER_PATH>" },
        @{ Pattern = "(?i)[A-Z]:\\[^ \r\n]+\\coding_agent_plan_and_verify_process"; Replacement = "<REPOSITORY_PATH>" }
    )

    foreach ($item in $patterns) {
        $safe = [regex]::Replace($safe, $item.Pattern, $item.Replacement)
    }

    return $safe
}

function Get-RepositoryRoot([string] $StartPath) {
    $topLevel = (& git -C $StartPath rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        throw "Git repository root could not be resolved."
    }

    return (Resolve-Path $topLevel).Path
}

function Get-StatusLines([string] $RepositoryRoot) {
    return @(
        & git -C $RepositoryRoot status --porcelain=v1 --untracked-files=all 2>&1 |
            ForEach-Object { [string] $_ } |
            Sort-Object
    )
}

function Get-StatusPath([string] $Line) {
    if ($Line.Length -lt 4) {
        return $Line.Replace("\", "/")
    }

    return $Line.Substring(3).Replace("\", "/")
}

function Get-OutsideAllowedChanges(
    [string[]] $Before,
    [string[]] $After,
    [string[]] $AllowedPrefixes
) {
    $beforeMap = @{}
    foreach ($line in @($Before)) {
        $beforeMap[(Get-StatusPath $line)] = $line
    }

    $afterMap = @{}
    foreach ($line in @($After)) {
        $afterMap[(Get-StatusPath $line)] = $line
    }

    $changed = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)) {
        $isChanged = $beforeMap.ContainsKey($path) -xor $afterMap.ContainsKey($path)
        if (-not $isChanged -and $beforeMap.ContainsKey($path) -and $afterMap.ContainsKey($path)) {
            $isChanged = $beforeMap[$path] -ne $afterMap[$path]
        }

        if (-not $isChanged) {
            continue
        }

        $allowed = $false
        foreach ($prefix in $AllowedPrefixes) {
            if ($path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                $allowed = $true
                break
            }
        }

        if (-not $allowed) {
            [void] $changed.Add($path)
        }
    }

    return @($changed | Sort-Object -Unique)
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
    $process.StartInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $process.StartInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @($Arguments)) {
        [void] $process.StartInfo.ArgumentList.Add($argument)
    }

    $startedAt = [DateTimeOffset]::UtcNow
    try {
        if (-not $process.Start()) {
            throw "Codex process could not be started."
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($InputBytes.Length -gt 0) {
            $process.StandardInput.BaseStream.Write($InputBytes, 0, $InputBytes.Length)
        }
        $process.StandardInput.Close()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $process.WaitForExit()
        }

        return [ordered] @{
            started_at_utc = $startedAt.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            process_exited = $completed
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

function Get-EventParse([string] $Stdout) {
    $events = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Stdout -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        try {
            [void] $events.Add(($line | ConvertFrom-Json))
        }
        catch {
            [void] $errors.Add((ConvertTo-SafeText $_.Exception.ToString()))
        }
    }

    return [ordered] @{
        events = $events.ToArray()
        errors = $errors.ToArray()
    }
}

function Get-SessionId([object[]] $Events) {
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
        throw "Codex emitted multiple thread identities in one process."
    }

    return $ids[0]
}

function Get-EventSummary([object[]] $Events, [int] $ParseErrorCount) {
    $types = @(
        $Events |
            ForEach-Object { [string] $_.type } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    return [ordered] @{
        event_count = $Events.Count
        parse_error_count = $ParseErrorCount
        event_types = $types
        thread_started_event_count = @($Events | Where-Object { $_.type -eq "thread.started" }).Count
        agent_message_event_count = @(
            $Events |
                Where-Object { $_.type -eq "item.completed" -and $_.item.type -eq "agent_message" }
        ).Count
    }
}

function Get-Descriptor([string] $ExperimentRoot, [string] $RelativePath) {
    $path = Join-Path $ExperimentRoot $RelativePath
    $bytes = [IO.File]::ReadAllBytes($path)
    return [ordered] @{
        path = $RelativePath.Replace("\", "/")
        bytes = $bytes.Length
        sha256 = Get-Sha256Bytes $bytes
        content = $bytes
    }
}

function New-Payload([string] $ExperimentRoot, [string[]] $RelativePaths) {
    $stream = [IO.MemoryStream]::new()
    $descriptors = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($relativePath in $RelativePaths) {
            $descriptor = Get-Descriptor $ExperimentRoot $relativePath
            [void] $descriptors.Add($descriptor)
            $stream.Write($descriptor.content, 0, $descriptor.content.Length)
        }

        $bytes = $stream.ToArray()
        return [ordered] @{
            descriptors = @(
                $descriptors |
                    ForEach-Object {
                        [ordered] @{
                            path = $_.path
                            bytes = $_.bytes
                            sha256 = $_.sha256
                        }
                    }
            )
            composition_rule = "listed file bytes concatenated in order with no separator"
            bytes = $bytes.Length
            sha256 = Get-Sha256Bytes $bytes
            content = $bytes
        }
    }
    finally {
        $stream.Dispose()
    }
}

function New-Manifest(
    [string] $RunLabel,
    [int] $Round,
    [object] $Payload,
    [bool] $ContextSent
) {
    return [ordered] @{
        schema_version = 2
        provider = "codex"
        run_label = $RunLabel
        round = $Round
        files = $Payload.descriptors
        payload = [ordered] @{
            composition = @($Payload.descriptors.path)
            composition_rule = $Payload.composition_rule
            bytes = $Payload.bytes
            sha256 = $Payload.sha256
        }
        no_replay_flags = [ordered] @{
            round_1_context_sent = $ContextSent
            previous_response_sent = $false
            decision_replayed = $false
            mapping_replayed = $false
            finding_replayed = $false
            round_1_context_replayed_to_follow_up = $false
            round_1_context_omitted_from_follow_up = (-not $ContextSent)
        }
        external_input_boundary = "only the listed prompt/context/candidate bytes were written to stdin"
    }
}

function Get-CommandShape([string] $RunLabel) {
    switch ($RunLabel) {
        "persistent-r1" {
            return "codex exec --json --color never --ignore-user-config --ignore-rules -s read-only -C <experiment-folder> -m gpt-5.6-luna -o <round-output> -"
        }
        "persistent-r2" {
            return "codex exec resume <same-specific-session-id> --json --ignore-user-config --ignore-rules -o <round-output> -"
        }
        "persistent-r3" {
            return "codex exec resume <same-specific-session-id> --json --ignore-user-config --ignore-rules -o <round-output> -"
        }
        "fresh-r2" {
            return "codex exec --json --color never --ignore-user-config --ignore-rules -s read-only -C <experiment-folder> -m gpt-5.6-luna -o <round-output> -"
        }
        default {
            throw "Unknown run label: $RunLabel"
        }
    }
}

function Get-SemanticForm([string] $Text) {
    $match = [regex]::Match(
        $Text,
        "(?s)BEGIN_PERSISTENCE_REVIEW\s*(\{.*?\})\s*END_PERSISTENCE_REVIEW"
    )
    if (-not $match.Success) {
        return [ordered] @{
            parsed = $false
            error = "Required persistence review block was not found."
            block = $null
            value = $null
        }
    }

    try {
        $value = $match.Groups[1].Value | ConvertFrom-Json
        return [ordered] @{
            parsed = $true
            error = $null
            block = $match.Groups[1].Value
            value = $value
        }
    }
    catch {
        return [ordered] @{
            parsed = $false
            error = ConvertTo-SafeText $_.Exception.ToString()
            block = $match.Groups[1].Value
            value = $null
        }
    }
}

function Save-Run(
    [string] $RunLabel,
    [int] $Round,
    [string] $RoundRoot,
    [string] $ExperimentRoot,
    [string] $NodePath,
    [string] $CodexEntryPoint,
    [string] $Model,
    [byte[]] $PayloadBytes,
    [string] $SessionId,
    [string[]] $PreStatus
) {
    $script:debugStage = "start-$RunLabel"
    $capturePath = Join-Path $RoundRoot "response.capture"
    $savedResponsePath = Join-Path $RoundRoot "raw-response.md"
    $semanticPath = Join-Path $RoundRoot "semantic.json"
    $machinePath = Join-Path $RoundRoot "machine-metadata.json"
        $args = if ($RunLabel -eq "persistent-r1" -or $RunLabel -eq "fresh-r2") {
        @(
            $CodexEntryPoint, "exec", "--json", "--color", "never",
            "--ignore-user-config", "--ignore-rules", "-s", "read-only",
            "-C", $ExperimentRoot, "-m", $Model, "-o", $capturePath, "-"
        )
    }
    else {
        @(
            $CodexEntryPoint, "exec", "resume", $SessionId, "--json",
            "--ignore-user-config", "--ignore-rules", "-o", $capturePath, "-"
        )
    }

    [IO.File]::WriteAllBytes((Join-Path $RoundRoot "input-payload.bin"), $PayloadBytes)
    Write-Utf8NoBom (Join-Path $RoundRoot "pre-git-status.txt") (($PreStatus -join "`r`n") + "`r`n")
    $script:debugStage = "invoke-$RunLabel"
    $result = Invoke-Process $NodePath $args $ExperimentRoot $PayloadBytes
    $script:debugStage = "parse-events-$RunLabel"
    $parsedEvents = Get-EventParse $result.stdout
    $sessionIdentity = Get-SessionId $parsedEvents.events
    $sessionHash = if ($sessionIdentity) {
        Get-Sha256Bytes ([Text.Encoding]::UTF8.GetBytes($sessionIdentity))
    }
    else {
        $null
    }

    $script:debugStage = "read-response-$RunLabel"
    $actualResponsePresent = Test-Path -LiteralPath $capturePath
    [byte[]] $actualResponseBytes = [byte[]]::new(0)
    if ($actualResponsePresent) {
        $actualResponseBytes = [IO.File]::ReadAllBytes($capturePath)
    }
    $actualResponseHash = if ($actualResponsePresent) {
        Get-Sha256Bytes $actualResponseBytes
    }
    else {
        $null
    }
    $actualResponseText = if ($actualResponsePresent) {
        [Text.UTF8Encoding]::new($false).GetString($actualResponseBytes)
    }
    else {
        ""
    }
    $script:debugStage = "sanitize-response-$RunLabel"
    $safeResponseText = ConvertTo-SafeText $actualResponseText
    if ($actualResponsePresent) {
        $script:debugStage = "save-response-$RunLabel"
        Write-Utf8NoBom $savedResponsePath $safeResponseText
        Remove-Item -LiteralPath $capturePath -Force
    }

    $script:debugStage = "semantic-$RunLabel"
    $semantic = Get-SemanticForm $safeResponseText
    $semanticRecord = [ordered] @{
        schema_version = 2
        round_label = $RunLabel
        round = $Round
        round_label_verified = ($RunLabel -in @("persistent-r1", "persistent-r2", "persistent-r3", "fresh-r2"))
        verification_basis = "orchestrator run label, round directory, and input manifest"
        response_block_parsed = $semantic.parsed
        parse_error = $semantic.error
        semantic = $semantic.value
    }
    $script:debugStage = "save-semantic-$RunLabel"
    Write-Json $semanticPath $semanticRecord
    $semanticHash = Get-Sha256File $semanticPath

    if ($parsedEvents.errors.Count -gt 0) {
        Write-Utf8NoBom (Join-Path $RoundRoot "event-parse-errors.txt") (($parsedEvents.errors -join "`r`n") + "`r`n")
    }
    if (-not [string]::IsNullOrWhiteSpace($result.stderr)) {
        Write-Utf8NoBom (Join-Path $RoundRoot "stderr.txt") (ConvertTo-SafeText $result.stderr)
    }

    $metadata = [ordered] @{
        schema_version = 2
        provider = "codex"
        run_label = $RunLabel
        round = $Round
        cli = "codex"
        cli_version = "0.147.0"
        model = $Model
        sandbox_requested = "read-only"
        cwd = "experiments/persistent-purpose-reviewer"
        process_exited = $result.process_exited
        exit_code = $result.exit_code
        timed_out = $result.timed_out
        started_at_utc = $result.started_at_utc
        completed_at_utc = $result.completed_at_utc
        process_exited_before_next_round = $true
        command_shape = Get-CommandShape $RunLabel
        session_id_sha256 = $sessionHash
        session_identity_full_id_saved = $false
        event_summary = Get-EventSummary $parsedEvents.events $parsedEvents.errors.Count
        raw_response_saved = $actualResponsePresent
        raw_response_sanitized_before_save = $actualResponsePresent
        raw_response_actual_bytes = if ($actualResponsePresent) { $actualResponseBytes.Length } else { $null }
        raw_response_actual_sha256 = $actualResponseHash
        raw_response_saved_path = if ($actualResponsePresent) { "raw-response.md" } else { $null }
        raw_response_saved_bytes = if ($actualResponsePresent) { [IO.File]::ReadAllBytes($savedResponsePath).Length } else { $null }
        raw_response_saved_sha256 = if ($actualResponsePresent) { Get-Sha256File $savedResponsePath } else { $null }
        semantic_form_path = "semantic.json"
        semantic_form_sha256 = $semanticHash
        semantic_round_label_verified = $semanticRecord.round_label_verified
        secret_or_environment_raw_values_saved = $false
        stderr_present = -not [string]::IsNullOrWhiteSpace($result.stderr)
    }
    $script:debugStage = "save-machine-$RunLabel"
    Write-Json $machinePath $metadata

    $success = (
        $result.process_exited -and
        -not $result.timed_out -and
        $result.exit_code -eq 0 -and
        $actualResponsePresent -and
        $null -ne $sessionIdentity -and
        $semantic.parsed
    )
    if (-not $success) {
        Write-Json (Join-Path $RoundRoot "failure.json") ([ordered] @{
            failure = "Codex run did not produce a verifiable semantic response."
            exit_code = $result.exit_code
            process_exited = $result.process_exited
            timed_out = $result.timed_out
            response_present = $actualResponsePresent
            session_hash_present = $null -ne $sessionHash
            semantic_parsed = $semantic.parsed
            error = if ($semantic.error) { $semantic.error } else { $null }
        })
    }

    return [ordered] @{
        run_label = $RunLabel
        round = $Round
        success = $success
        exit_code = $result.exit_code
        process_exited = $result.process_exited
        timed_out = $result.timed_out
        session_id = $sessionIdentity
        session_hash = $sessionHash
        response_actual_sha256 = $actualResponseHash
        response_saved_sha256 = if ($actualResponsePresent) { Get-Sha256File $savedResponsePath } else { $null }
        semantic = $semantic.value
        semantic_parsed = $semantic.parsed
        semantic_round_label_verified = $semanticRecord.round_label_verified
    }
}

function Get-SemanticValue([object] $RunResult, [string] $Property) {
    if ($null -eq $RunResult.semantic) {
        return $null
    }

    $propertyValue = $RunResult.semantic.PSObject.Properties[$Property]
    if ($null -eq $propertyValue) {
        return $null
    }

    return [string] $propertyValue.Value
}

function Get-EvidenceLine([object] $RunResult) {
    $semantic = $RunResult.semantic
    if ($null -eq $semantic) {
        return "$($RunResult.run_label): semantic response unavailable"
    }

    $evidence = if ($semantic.evidence) {
        (@($semantic.evidence) -join " / ")
    }
    else {
        ""
    }
    return "$($RunResult.run_label): finding_id=$($semantic.finding_id); prior_finding_status=$($semantic.prior_finding_status); decision_contract_assertion=$($semantic.decision_contract_assertion); information_sufficiency=$($semantic.information_sufficiency); evidence=$evidence"
}

$repositoryRoot = Get-RepositoryRoot $PSScriptRoot
$experimentRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
$evidenceRoot = Join-Path $experimentRoot "evidence\codex\persistence-control-v2"
$experimentPrefix = "experiments/persistent-purpose-reviewer/"
$allowedPrefixes = @(
    "experiments/persistent-purpose-reviewer/evidence/codex/persistence-control-v2/",
    "experiments/persistent-purpose-reviewer/scripts/codex/run-persistence-control-v2.ps1"
)
$model = "gpt-5.6-luna"
$startedAt = [DateTimeOffset]::UtcNow

if (Test-Path -LiteralPath $evidenceRoot) {
    throw "Refusing to overwrite existing v2 evidence directory."
}

$preStatus = Get-StatusLines $repositoryRoot
New-Item -ItemType Directory -Force -Path `
    (Join-Path $evidenceRoot "persistent\round-1"), `
    (Join-Path $evidenceRoot "persistent\round-2"), `
    (Join-Path $evidenceRoot "persistent\round-3"), `
    (Join-Path $evidenceRoot "fresh\round-2"), `
    (Join-Path $evidenceRoot "setup") | Out-Null
Write-Utf8NoBom (Join-Path $evidenceRoot "pre-git-status.txt") (($preStatus -join "`r`n") + "`r`n")

$codexCommand = Get-Command codex
$nodeCommand = Get-Command node
$codexEntryPoint = Join-Path (Split-Path $codexCommand.Source -Parent) "node_modules\@openai\codex\bin\codex.js"
if (-not (Test-Path -LiteralPath $codexEntryPoint)) {
    throw "Codex Node entrypoint was not found."
}

$versionResult = Invoke-Process $nodeCommand.Source @($codexEntryPoint, "--version") $experimentRoot ([byte[]]::new(0)) 120
$execHelpResult = Invoke-Process $nodeCommand.Source @($codexEntryPoint, "exec", "--help") $experimentRoot ([byte[]]::new(0)) 120
$resumeHelpResult = Invoke-Process $nodeCommand.Source @($codexEntryPoint, "exec", "resume", "--help") $experimentRoot ([byte[]]::new(0)) 120
Write-Utf8NoBom (Join-Path $evidenceRoot "setup\codex-version.txt") (ConvertTo-SafeText $versionResult.stdout)
Write-Utf8NoBom (Join-Path $evidenceRoot "setup\exec-help.txt") (ConvertTo-SafeText $execHelpResult.stdout)
Write-Utf8NoBom (Join-Path $evidenceRoot "setup\exec-resume-help.txt") (ConvertTo-SafeText $resumeHelpResult.stdout)

$round1Payload = New-Payload $experimentRoot @(
    "prompts\persistence-control-v2\round-1.md",
    "fixtures\persistence-control-v2\round-1-context.md",
    "fixtures\persistence-control-v2\round-1-candidate.md"
)
$round2Payload = New-Payload $experimentRoot @(
    "prompts\persistence-control-v2\round-2.md",
    "fixtures\persistence-control-v2\round-2-candidate.md"
)
$round3Payload = New-Payload $experimentRoot @(
    "prompts\persistence-control-v2\round-3.md",
    "fixtures\persistence-control-v2\round-3-candidate.md"
)

Write-Json (Join-Path $evidenceRoot "persistent\round-1\input-manifest.json") (New-Manifest "persistent-r1" 1 $round1Payload $true)
Write-Json (Join-Path $evidenceRoot "persistent\round-2\input-manifest.json") (New-Manifest "persistent-r2" 2 $round2Payload $false)
Write-Json (Join-Path $evidenceRoot "persistent\round-3\input-manifest.json") (New-Manifest "persistent-r3" 3 $round3Payload $false)
Write-Json (Join-Path $evidenceRoot "fresh\round-2\input-manifest.json") (New-Manifest "fresh-r2" 2 $round2Payload $false)

$r2PersistentManifest = Get-Content -LiteralPath (Join-Path $evidenceRoot "persistent\round-2\input-manifest.json") -Raw | ConvertFrom-Json
$r2FreshManifest = Get-Content -LiteralPath (Join-Path $evidenceRoot "fresh\round-2\input-manifest.json") -Raw | ConvertFrom-Json
Write-Json (Join-Path $evidenceRoot "r2-composition-equality.json") ([ordered] @{
    schema_version = 2
    composition_rule = $round2Payload.composition_rule
    persistent_r2 = [ordered] @{
        files = $r2PersistentManifest.files
        bytes = $r2PersistentManifest.payload.bytes
        sha256 = $r2PersistentManifest.payload.sha256
    }
    fresh_r2 = [ordered] @{
        files = $r2FreshManifest.files
        bytes = $r2FreshManifest.payload.bytes
        sha256 = $r2FreshManifest.payload.sha256
    }
    exact_composition_bytes_equal = (
        $r2PersistentManifest.payload.bytes -eq $r2FreshManifest.payload.bytes -and
        $r2PersistentManifest.payload.sha256 -eq $r2FreshManifest.payload.sha256
    )
    persistent_r2_fresh_r2_composition_sha256 = $round2Payload.sha256
})

try {
    $persistentR1 = Save-Run `
        "persistent-r1" 1 (Join-Path $evidenceRoot "persistent\round-1") `
        $experimentRoot $nodeCommand.Source $codexEntryPoint $model `
        $round1Payload.content $null $preStatus
}
catch {
    Write-Utf8NoBom (Join-Path $evidenceRoot "failure-debug.txt") (
        "stage=$script:debugStage`r`n$((ConvertTo-SafeText $_.Exception.ToString()))`r`n"
    )
    throw
}
if (-not $persistentR1.success) {
    throw "Persistent Round 1 failed; resume rounds were not attempted."
}

$persistentSessionId = $persistentR1.session_id
$persistentR2 = Save-Run `
    "persistent-r2" 2 (Join-Path $evidenceRoot "persistent\round-2") `
    $experimentRoot $nodeCommand.Source $codexEntryPoint $model `
    $round2Payload.content $persistentSessionId $preStatus
$persistentR3 = Save-Run `
    "persistent-r3" 3 (Join-Path $evidenceRoot "persistent\round-3") `
    $experimentRoot $nodeCommand.Source $codexEntryPoint $model `
    $round3Payload.content $persistentSessionId $preStatus
$freshR2 = Save-Run `
    "fresh-r2" 2 (Join-Path $evidenceRoot "fresh\round-2") `
    $experimentRoot $nodeCommand.Source $codexEntryPoint $model `
    $round2Payload.content $null $preStatus

$postStatus = Get-StatusLines $repositoryRoot
Write-Utf8NoBom (Join-Path $evidenceRoot "post-git-status.txt") (($postStatus -join "`r`n") + "`r`n")
$outsideAllowedChanges = Get-OutsideAllowedChanges $preStatus $postStatus $allowedPrefixes
$productionChanges = Get-OutsideAllowedChanges $preStatus $postStatus @($experimentPrefix)

foreach ($roundRoot in @(
    (Join-Path $evidenceRoot "persistent\round-1"),
    (Join-Path $evidenceRoot "persistent\round-2"),
    (Join-Path $evidenceRoot "persistent\round-3"),
    (Join-Path $evidenceRoot "fresh\round-2")
)) {
    Write-Utf8NoBom (Join-Path $roundRoot "post-git-status.txt") (($postStatus -join "`r`n") + "`r`n")
}

$persistentSessionHashes = @(
    $persistentR1.session_hash,
    $persistentR2.session_hash,
    $persistentR3.session_hash
)
$samePersistentSession = (
    $persistentSessionHashes.Count -eq 3 -and
    (@($persistentSessionHashes | Select-Object -Unique).Count -eq 1)
)
$freshDifferentSession = (
    $null -ne $freshR2.session_hash -and
    -not ($persistentSessionHashes -contains $freshR2.session_hash)
)
$r2CompositionEqual = (
    $r2PersistentManifest.payload.bytes -eq $r2FreshManifest.payload.bytes -and
    $r2PersistentManifest.payload.sha256 -eq $r2FreshManifest.payload.sha256
)

$r2Semantic = $persistentR2.semantic
$r3Semantic = $persistentR3.semantic
$freshSemantic = $freshR2.semantic
$persistentR2DetectsPpr001 = (
    $persistentR2.semantic_parsed -and
    $r2Semantic.finding_id -eq "PPR-001" -and
    $r2Semantic.prior_finding_status -eq "active" -and
    $r2Semantic.decision_contract_assertion -eq "fail" -and
    $r2Semantic.information_sufficiency -eq "sufficient" -and
    @($r2Semantic.evidence).Count -gt 0
)
$persistentR3Resolved = (
    $persistentR3.semantic_parsed -and
    $r3Semantic.finding_id -eq "PPR-001" -and
    $r3Semantic.prior_finding_status -eq "resolved" -and
    $r3Semantic.decision_contract_assertion -eq "pass" -and
    $r3Semantic.information_sufficiency -eq "sufficient"
)
$freshMateriallyWeaker = (
    $freshR2.semantic_parsed -and
    (
        $freshSemantic.information_sufficiency -eq "insufficient" -or
        $freshSemantic.decision_contract_assertion -eq "unknown" -or
        $freshSemantic.prior_finding_status -eq "unknown"
    )
)
$runResults = @($persistentR1, $persistentR2, $persistentR3, $freshR2)
$allSuccessful = @($runResults | Where-Object { $_.success }).Count -eq 4
$architectureFeasible = (
    $allSuccessful -and
    $samePersistentSession -and
    $freshDifferentSession -and
    $r2CompositionEqual -and
    $persistentR1.process_exited
)
$semanticYes = (
    $architectureFeasible -and
    $persistentR2DetectsPpr001 -and
    $freshMateriallyWeaker -and
    $persistentR3Resolved -and
    $productionChanges.Count -eq 0
)
$classification = if ($semanticYes) {
    "Yes"
}
elseif ($persistentR2DetectsPpr001 -and $persistentR3Resolved -and -not $freshMateriallyWeaker) {
    "Partial/No (fresh control was not materially weaker; fixtures were unchanged)"
}
else {
    "Inconclusive/No"
}

$diffCheckOutput = ((& git -C $repositoryRoot diff --check 2>&1 | Out-String).Trim())
$diffCheckExit = $LASTEXITCODE
Write-Utf8NoBom (Join-Path $evidenceRoot "final-diff-check.txt") (
    "git_diff_check_exit=$diffCheckExit`r`n$diffCheckOutput`r`n"
)

$runMetadata = [ordered] @{
    schema_version = 2
    provider = "codex"
    cli = "codex"
    cli_version = "0.147.0"
    model = $model
    sandbox_requested = "read-only"
    cwd = "experiments/persistent-purpose-reviewer"
    started_at_utc = $startedAt.ToString("O")
    completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
    classification = $classification
    all_rounds_completed = @($runResults | Where-Object { $_.success }).Count
    persistent_session_hashes = $persistentSessionHashes
    fresh_session_hash = $freshR2.session_hash
    same_session_hash_persistent_r1_r3 = $samePersistentSession
    fresh_session_hash_different = $freshDifferentSession
    initial_process_exited_before_resume = $persistentR1.process_exited
    r2_composition_equality_verified = $r2CompositionEqual
    r2_composition_sha256 = $round2Payload.sha256
    input_context_replayed_to_follow_up = $false
    previous_response_replayed = $false
    decision_mapping_finding_replayed = $false
    raw_session_secret_environment_values_saved = $false
    status_changes_outside_codex_allowed_paths = @($outsideAllowedChanges)
    other_experiment_status_changes_observed = @($outsideAllowedChanges)
    production_status_changes_outside_experiment = @($productionChanges)
    production_unchanged_observed = ($productionChanges.Count -eq 0)
    architecture_feasibility = [ordered] @{
        status = if ($architectureFeasible) { "PASS" } else { "FAIL" }
        same_persistent_session_hash = $samePersistentSession
        different_fresh_session_hash = $freshDifferentSession
        exact_r2_input_composition = $r2CompositionEqual
        completed_process_before_resume = $persistentR1.process_exited
        read_only_requested = $true
        cwd_restricted_to_experiment = $true
    }
    security_qualification = [ordered] @{
        status = "CONDITIONAL"
        raw_session_ids_saved = $false
        raw_secret_values_saved = $false
        raw_environment_values_saved = $false
        read_only_requested = $true
        production_nonmutation_observed = ($productionChanges.Count -eq 0)
        network_payload_audit = "not performed"
        sandbox_implementation_internal_audit = "not performed"
        qualification = "CLI boundary and worktree non-mutation were observed; provider/network and sandbox internals were not independently audited."
    }
    command_shapes = [ordered] @{
        persistent_round_1 = Get-CommandShape "persistent-r1"
        persistent_round_2 = Get-CommandShape "persistent-r2"
        persistent_round_3 = Get-CommandShape "persistent-r3"
        fresh_round_2 = Get-CommandShape "fresh-r2"
    }
    machine_metadata = [ordered] @{
        os = [Environment]::OSVersion.VersionString
        powershell = $PSVersionTable.PSVersion.ToString()
        node = (Invoke-Process $nodeCommand.Source @("--version") $experimentRoot ([byte[]]::new(0)) 120).stdout.Trim()
        git = ((& git --version).Trim())
        process_architecture = [Environment]::Is64BitProcess
        timezone_offset = [DateTimeOffset]::Now.Offset.ToString()
    }
}
Write-Json (Join-Path $evidenceRoot "run-metadata.json") $runMetadata

$summary = @"
# Codex CLI Persistent Purpose Reviewer v2 実験結果

## 判定

- 分類: **$classification**
- provider/model: codex / $model
- CLI version: 0.147.0
- sandbox: read-only
- cwd: experiments/persistent-purpose-reviewer

## 実行境界

- Persistent R1 は新規 session で実行し、プロセス終了後に同一 session hash へ codex exec resume で R2/R3 を継続した。
- Fresh R2 は新規 session で、Persistent R2 と同一の prompt/candidate bytes を送った。
- R2/R3/Fresh R2 へ R1 context、previous response、decision、mapping、finding の再送は行っていない。
- 入力 manifest、個別 bytes/SHA-256、no-replay flags は各 round に保存した。
- R2 composition equality: $r2CompositionEqual、SHA-256: $($round2Payload.sha256)。

## 意味判定出力

$(Get-EvidenceLine $persistentR1)
$(Get-EvidenceLine $persistentR2)
$(Get-EvidenceLine $persistentR3)
$(Get-EvidenceLine $freshR2)

- Persistent R2 の PPR-001 specific detection: $persistentR2DetectsPpr001
- Persistent R3 の resolved 判定: $persistentR3Resolved
- Fresh R2 の相対的に弱い判定: $freshMateriallyWeaker

各 round の machine-metadata.json に、Codex output の実バイト SHA-256、保存時に sanitization 済みの response、semantic form、round label verification を保存した。session ID、secret、environment の raw value は保存していない。

## 非変更

- pre/post Git status を保存した。
- 実験フォルダ外の status 変化: $($productionChanges.Count) 件。
- 実験フォルダ内で Codex v2 の許可 prefix 外に観測された既存・並行 status 変化: $($outsideAllowedChanges.Count) 件。これらは revert していない。
- production 非変更観測: $(if ($productionChanges.Count -eq 0) { "PASS" } else { "FAIL" })。
- git diff --check の結果は final-diff-check.txt に保存した。

## アーキテクチャ実現性とセキュリティ適格性

- アーキテクチャ実現性: $(if ($architectureFeasible) { "PASS" } else { "FAIL" })。resume の同一 session、fresh の別 session、R2 の完全 byte 一致、process exit、read-only/cwd boundary を別々に検証した。
- セキュリティ適格性: CONDITIONAL。raw session/secret/environment 値を保存せず production 非変更を観測したが、provider/network payload と sandbox 実装内部の独立監査は実施していない。

v1 は prompt 内の persistent state 使用禁止と state 継続要求が矛盾していたため、本判定根拠に使用していない。v2 fixture/prompt/design は変更していない。
"@
Write-Utf8NoBom (Join-Path $evidenceRoot "summary.md") $summary

Write-Json (Join-Path $evidenceRoot "verification.json") ([ordered] @{
    schema_version = 2
    classification = $classification
    semantic_yes = $semanticYes
    persistent_r2_specific_ppr001 = $persistentR2DetectsPpr001
    fresh_r2_materially_weaker = $freshMateriallyWeaker
    persistent_r3_resolved = $persistentR3Resolved
    same_persistent_session = $samePersistentSession
    different_fresh_session = $freshDifferentSession
    exact_r2_composition_equal = $r2CompositionEqual
    production_unchanged = ($productionChanges.Count -eq 0)
    status_changes_outside_codex_allowed_paths = @($outsideAllowedChanges)
    git_diff_check_exit = $diffCheckExit
})

$finalDiffCheckOutput = ((& git -C $repositoryRoot diff --check 2>&1 | Out-String).Trim())
$finalDiffCheckExit = $LASTEXITCODE
Write-Utf8NoBom (Join-Path $evidenceRoot "final-diff-check.txt") (
    "git_diff_check_exit=$finalDiffCheckExit`r`n$finalDiffCheckOutput`r`n"
)
