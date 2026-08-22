[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("copilot", "grok")]
    [string] $CliName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CliPath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F-]{36}$")]
    [string] $SessionId
)

$ErrorActionPreference = "Stop"

function Get-ExperimentRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-RepositoryRoot {
    $candidate = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
    $topLevel = (& git -C $candidate.Path rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        throw "Git repository root could not be resolved."
    }

    return (Resolve-Path $topLevel).Path
}

function Get-SafeSessionTag([string] $value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($value)
    $digest = [Security.Cryptography.SHA256]::HashData($bytes)
    return (($digest | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0, 12)
}

function ConvertTo-SanitizedText([string] $text) {
    if ($null -eq $text) {
        return ""
    }

    $sanitized = $text
    $patterns = @(
        @{ Pattern = "(?i)(authorization\s*:\s*(?:bearer|token|basic)\s+)[^\s]+"; Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"; Replacement = "[REDACTED_BEARER]" },
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

function Get-GitSnapshot([string] $repositoryRoot) {
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
        throw "git cached diff failed."
    }

    $head = (& git -C $repositoryRoot rev-parse HEAD 2>&1).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "git rev-parse failed."
    }

    return [ordered] @{
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        head = $head
        status = @($status | ForEach-Object { [string] $_ })
        unstaged_name_status = @($unstaged | ForEach-Object { [string] $_ })
        staged_name_status = @($staged | ForEach-Object { [string] $_ })
    }
}

function Write-GitSnapshot([string] $path, [object] $snapshot) {
    $snapshot | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
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
    $isPowerShellWrapper = [IO.Path]::GetExtension($filePath).Equals(".ps1", [StringComparison]::OrdinalIgnoreCase)
    if ($isPowerShellWrapper) {
        $process.StartInfo.FileName = (Get-Command pwsh -CommandType Application).Source
        [void] $process.StartInfo.ArgumentList.Add("-NoProfile")
        [void] $process.StartInfo.ArgumentList.Add("-File")
        [void] $process.StartInfo.ArgumentList.Add($filePath)
    }
    else {
        $process.StartInfo.FileName = $filePath
    }
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

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($timeoutSeconds * 1000)
        if (-not $completed) {
            $process.Kill()
            $process.WaitForExit()
        }

        return [ordered] @{
            started_at_utc = $start.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            exit_code = if ($completed) { $process.ExitCode } else { $null }
            timed_out = -not $completed
            stdout = ConvertTo-SanitizedText $stdoutTask.Result
            stderr = ConvertTo-SanitizedText $stderrTask.Result
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-InputManifest([string] $experimentRoot, [int] $round) {
    $promptPath = Join-Path $experimentRoot ("prompts\round-{0}.md" -f $round)
    $fixtureNames = switch ($round) {
        1 { @("purpose-context.md", "round-1-candidate.md") }
        2 { @("round-2-remediation.md") }
        3 { @("round-3-remediation.md") }
    }

    $files = @(
        [ordered] @{
            path = ("prompts\round-{0}.md" -f $round)
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $promptPath).Hash.ToLowerInvariant()
        }
    )
    foreach ($fixtureName in $fixtureNames) {
        $fixturePath = Join-Path $experimentRoot ("fixtures\{0}" -f $fixtureName)
        $files += [ordered] @{
            path = ("fixtures\{0}" -f $fixtureName)
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixturePath).Hash.ToLowerInvariant()
        }
    }

    return [ordered] @{
        round = $round
        role = "purpose-reviewer"
        files = $files
        goal_context_replayed = ($round -eq 1)
        prior_reviewer_output_replayed = $false
        semantic_secret_replayed = $false
        external_model_input_boundary = "prompt file plus listed fixture files only"
    }
}

function Get-PromptText([string] $experimentRoot, [int] $round) {
    $promptPath = Join-Path $experimentRoot ("prompts\round-{0}.md" -f $round)
    $parts = @((Get-Content -Raw -LiteralPath $promptPath))
    if ($round -eq 1) {
        $parts += (Get-Content -Raw -LiteralPath (Join-Path $experimentRoot "fixtures\purpose-context.md"))
        $parts += (Get-Content -Raw -LiteralPath (Join-Path $experimentRoot "fixtures\round-1-candidate.md"))
    }
    else {
        $parts += (Get-Content -Raw -LiteralPath (Join-Path $experimentRoot ("fixtures\round-{0}-remediation.md" -f $round)))
        $parts += "前回の finding の解消確認として、今回の candidate だけを判定してください。"
    }

    return ($parts -join "`r`n`r`n")
}

function Get-CommandShape([string] $cliName, [int] $round) {
    if ($cliName -eq "copilot") {
        if ($round -eq 1) {
            return "copilot --no-custom-instructions --no-remote --no-remote-export --disable-builtin-mcps --no-auto-update --silent --output-format text --stream off --session-id=<SESSION_ID_REDACTED> --available-tools=view,grep --allow-tool=view --allow-tool=grep --deny-tool=write --deny-tool=shell --deny-tool=task --deny-tool=edit -p <PROMPT_FROM_MANIFEST>"
        }

        return "copilot --no-custom-instructions --no-remote --no-remote-export --disable-builtin-mcps --no-auto-update --silent --output-format text --stream off --resume=<SESSION_ID_REDACTED> --available-tools=view,grep --allow-tool=view --allow-tool=grep --deny-tool=write --deny-tool=shell --deny-tool=task --deny-tool=edit -p <PROMPT_FROM_MANIFEST>"
    }

    if ($round -eq 1) {
        return "grok --cwd <EXPERIMENT_ROOT> --no-memory --no-subagents --permission-mode plan --sandbox read-only --disable-web-search --tools=read,view,grep --disallowed-tools=write,shell,task,edit_file,run_shell_command --system-prompt-override=<SAFE_REVIEWER_ROLE> --session-id=<SESSION_ID_REDACTED> --output-format plain --verbatim --single <PROMPT_FROM_MANIFEST>"
    }

    return "grok --cwd <EXPERIMENT_ROOT> --no-memory --no-subagents --permission-mode plan --sandbox read-only --disable-web-search --tools=read,view,grep --disallowed-tools=write,shell,task,edit_file,run_shell_command --system-prompt-override=<SAFE_REVIEWER_ROLE> --resume <SESSION_ID_REDACTED> --output-format plain --verbatim --single <PROMPT_FROM_MANIFEST>"
}

function Get-Arguments([string] $cliName, [int] $round, [string] $sessionId, [string] $prompt) {
    if ($cliName -eq "copilot") {
        $arguments = @(
            "--no-custom-instructions", "--no-remote", "--no-remote-export",
            "--disable-builtin-mcps", "--no-auto-update", "--silent",
            "--output-format", "text", "--stream", "off",
            "--available-tools=view,grep", "--allow-tool=view", "--allow-tool=grep",
            "--deny-tool=write", "--deny-tool=shell", "--deny-tool=task", "--deny-tool=edit"
        )
        if ($round -eq 1) {
            $arguments += @("--session-id", $sessionId)
        }
        else {
            $arguments += @("--resume=$sessionId")
        }
        $arguments += @("-p", $prompt)
        return $arguments
    }

    $arguments = @(
        "--cwd", (Get-ExperimentRoot), "--no-memory", "--no-subagents",
        "--permission-mode", "plan", "--sandbox", "read-only",
        "--disable-web-search", "--tools", "read,view,grep",
        "--disallowed-tools", "write,shell,task,edit_file,run_shell_command",
        "--system-prompt-override", "You are a read-only Persistent Purpose Reviewer. Use only the supplied prompt and fixture text. Do not access files, shell, network, credentials, metadata, or home content.",
        "--output-format", "plain", "--verbatim"
    )
    if ($round -eq 1) {
        $arguments += @("--session-id", $sessionId)
    }
    else {
        $arguments += @("--resume", $sessionId)
    }
    $arguments += @("--single", $prompt)
    return $arguments
}

function Write-Text([string] $path, [string] $text) {
    Set-Content -LiteralPath $path -Value $text -Encoding utf8
}

$repositoryRoot = Get-RepositoryRoot
$experimentRoot = Get-ExperimentRoot
$evidenceRoot = Join-Path $experimentRoot ("evidence\{0}" -f $CliName)
$setupRoot = Join-Path $evidenceRoot "setup"
$roundRoot = Join-Path $evidenceRoot "rounds"
$safeSessionTag = Get-SafeSessionTag $SessionId

New-Item -ItemType Directory -Force -Path $setupRoot, $roundRoot | Out-Null
$initialSnapshot = Get-GitSnapshot $repositoryRoot
Write-GitSnapshot (Join-Path $evidenceRoot "run-start-pre-git-snapshot.json") $initialSnapshot

$static = [ordered] @{
    version = Invoke-CapturedProcess $CliPath @("--version") $experimentRoot 120
    help = Invoke-CapturedProcess $CliPath @("--help") $experimentRoot 120
}
if ($CliName -eq "grok") {
    $static.headless_help = Invoke-CapturedProcess $CliPath @("agent", "headless", "--help") $experimentRoot 120
    $static.resume_help = Invoke-CapturedProcess $CliPath @("sessions", "list", "--help") $experimentRoot 120
}
else {
    $static.permissions_help = Invoke-CapturedProcess $CliPath @("help", "permissions") $experimentRoot 120
    $static.sandbox_help = Invoke-CapturedProcess $CliPath @("help", "sandbox") $experimentRoot 120
}
Write-Text (Join-Path $setupRoot "static-help-and-version.json") ($static | ConvertTo-Json -Depth 10)
Write-GitSnapshot (Join-Path $evidenceRoot "static-post-git-snapshot.json") (Get-GitSnapshot $repositoryRoot)

$runMetadata = [ordered] @{
    schema_version = 1
    cli = $CliName
    cli_path = $CliPath
    model = if ($CliName -eq "grok") { "grok-4.6 (CLI default reported by grok models; runtime selection not independently exposed)" } else { "CLI default (runtime model not independently exposed by noninteractive text output)" }
    cwd = $experimentRoot
    permission_and_sandbox = Get-CommandShape $CliName 1
    session_hash = $safeSessionTag
    session_identity = if ($CliName -eq "copilot") { "--session-id for Round1; --resume=<same specific ID> for Round2/3" } else { "--session-id for Round1; --resume <same specific ID> for Round2/3" }
    captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
}
Write-Text (Join-Path $evidenceRoot "run-metadata.json") ($runMetadata | ConvertTo-Json -Depth 8)

for ($round = 1; $round -le 3; $round++) {
    $roundEvidence = Join-Path $roundRoot ("round-{0}" -f $round)
    New-Item -ItemType Directory -Force -Path $roundEvidence | Out-Null
    $pre = Get-GitSnapshot $repositoryRoot
    Write-GitSnapshot (Join-Path $roundEvidence "pre-git-snapshot.json") $pre

    $manifest = Get-InputManifest $experimentRoot $round
    Write-Text (Join-Path $roundEvidence "input-manifest.json") ($manifest | ConvertTo-Json -Depth 8)

    $result = $null
    $failure = $null
    try {
        $prompt = Get-PromptText $experimentRoot $round
        $result = Invoke-CapturedProcess $CliPath (Get-Arguments $CliName $round $SessionId $prompt) $experimentRoot 1200
    }
    catch {
        $failure = ConvertTo-SanitizedText $_.Exception.ToString()
        $result = [ordered] @{
            started_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            exit_code = $null
            timed_out = $false
            stdout = ""
            stderr = "[process failure sanitized]"
        }
    }

    $output = [ordered] @{
        round = $round
        cli = $CliName
        session_hash = $safeSessionTag
        command_shape = Get-CommandShape $CliName $round
        result = $result
    }
    Write-Text (Join-Path $roundEvidence "sanitized-raw-output.json") ($output | ConvertTo-Json -Depth 10)

    if ($failure) {
        Write-Text (Join-Path $roundEvidence "failure.txt") @(
            "failure_class=process_exception"
            "decision=recorded_without_retry"
            $failure
        )
    }

    $post = Get-GitSnapshot $repositoryRoot
    Write-GitSnapshot (Join-Path $roundEvidence "post-git-snapshot.json") $post

    $allowedPrefixes = @(
        ("experiments/persistent-purpose-reviewer/evidence/{0}/" -f $CliName),
        "experiments/persistent-purpose-reviewer/scripts/run-real-review.ps1"
    )
    $preStatus = @($pre.status)
    $postStatus = @($post.status)
    $statusChanges = @(
        Compare-Object -ReferenceObject $preStatus -DifferenceObject $postStatus |
            ForEach-Object { [string] $_.InputObject }
    )
    $outside = @($statusChanges | Where-Object {
        $normalized = $_.Replace("\", "/")
        -not @($allowedPrefixes | Where-Object {
            $normalized.StartsWith($_, [StringComparison]::OrdinalIgnoreCase)
        }).Count
    })
    $changeSummary = @(
        "cli=$CliName"
        "round=$round"
        "production_tree_changes_detected=$([bool]($outside.Count -gt 0))"
        "outside_experiment_status_count=$($outside.Count)"
        "pre_status_count=$($preStatus.Count)"
        "post_status_count=$($postStatus.Count)"
        "exit_code=$($result.exit_code)"
        "timed_out=$($result.timed_out)"
        "stdout_nonempty=$(-not [string]::IsNullOrWhiteSpace($result.stdout))"
        "stderr_nonempty=$(-not [string]::IsNullOrWhiteSpace($result.stderr))"
        "session_identity_evidence=the same specific session hash was used; semantic persistence requires Round2/3 output assertions"
    )
    if ($outside.Count -gt 0) {
        $changeSummary += "outside_experiment_paths=" + ($outside -join " | ")
    }
    Write-Text (Join-Path $roundEvidence "worktree-change-summary.txt") $changeSummary
}

Write-Text (Join-Path $evidenceRoot "completed.txt") @(
    "completed_at_utc=$([DateTimeOffset]::UtcNow.ToString('O'))"
    "cli=$CliName"
    "session_hash=$safeSessionTag"
)
