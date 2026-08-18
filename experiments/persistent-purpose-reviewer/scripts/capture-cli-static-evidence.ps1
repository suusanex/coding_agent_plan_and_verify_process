[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CliName,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $CliPath,

    [string[]] $VersionArguments = @("--version"),

    [string[]] $HelpArguments = @("--help"),

    [ValidateRange(1, 120)]
    [int] $TimeoutSeconds = 30,

    [switch] $FailOnWorktreeChange
)

$ErrorActionPreference = "Stop"

function Get-RepositoryRoot {
    $candidate = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
    $topLevel = (& git -C $candidate.Path rev-parse --show-toplevel 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
        throw "Git repository root could not be resolved."
    }

    return (Resolve-Path $topLevel).Path
}

function Get-SafeName([string] $value) {
    return ([regex]::Replace($value, "[^A-Za-z0-9._-]", "_"))
}

function ConvertTo-SanitizedText([string] $text) {
    if ($null -eq $text) {
        return ""
    }

    $sanitized = $text
    $patterns = @(
        @{ Pattern = "(?i)(authorization\s*:\s*(?:bearer|token|basic)\s+)[^\s]+";
           Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+";
           Replacement = "Bearer [REDACTED]" },
        @{ Pattern = "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|secret|credential|cookie)\s*([=:])\s*[^\s,;]+";
           Replacement = '$1[REDACTED]' },
        @{ Pattern = "(?i)\b(?:ghp|gho|github_pat|sk)-[A-Za-z0-9_=-]+";
           Replacement = "[REDACTED]" }
    )

    foreach ($item in $patterns) {
        $sanitized = [regex]::Replace($sanitized, $item.Pattern, $item.Replacement)
    }

    return $sanitized
}

function Get-WorktreeStatus([string] $repositoryRoot, [string] $evidenceRoot) {
    $lines = @(& git -C $repositoryRoot status --porcelain=v1 --untracked-files=all 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git worktree status failed."
    }

    $evidenceMarker = "experiments/persistent-purpose-reviewer/evidence/setup/"
    return @(
        $lines |
            ForEach-Object { [string] $_ } |
            Where-Object {
                $normalized = $_.Replace("\", "/")
                -not $normalized.Contains($evidenceMarker, [StringComparison]::OrdinalIgnoreCase)
            } |
            Sort-Object
    )
}

function Invoke-StaticProbe(
    [string] $filePath,
    [string[]] $arguments,
    [int] $timeoutSeconds
) {
    $start = [DateTimeOffset]::UtcNow
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $filePath
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
        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            return [ordered] @{
                started_at_utc = $start.ToString("O")
                completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
                exit_code = $null
                timed_out = $true
                stdout = ConvertTo-SanitizedText $stdoutTask.Result
                stderr = ConvertTo-SanitizedText $stderrTask.Result
            }
        }

        return [ordered] @{
            started_at_utc = $start.ToString("O")
            completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
            exit_code = $process.ExitCode
            timed_out = $false
            stdout = ConvertTo-SanitizedText $stdoutTask.Result
            stderr = ConvertTo-SanitizedText $stderrTask.Result
        }
    }
    finally {
        $process.Dispose()
    }
}

$repositoryRoot = $null
$setupRoot = $null
$tracePath = $null

try {
    $repositoryRoot = Get-RepositoryRoot
    $experimentRoot = Join-Path $repositoryRoot "experiments\persistent-purpose-reviewer"
    $setupRoot = Join-Path $experimentRoot "evidence\setup"
    New-Item -ItemType Directory -Force -Path $setupRoot | Out-Null
    $tracePath = Join-Path $setupRoot "helper-trace.log"

    $allowedVersionArguments = @("--version", "-v", "version")
    $allowedHelpArguments = @("--help", "-h", "help")
    if (@($VersionArguments | Where-Object { $_ -notin $allowedVersionArguments }).Count -gt 0) {
        throw "Only static version arguments are permitted."
    }
    if (@($HelpArguments | Where-Object { $_ -notin $allowedHelpArguments }).Count -gt 0) {
        throw "Only static help arguments are permitted."
    }

    $safeCliName = Get-SafeName $CliName
    $timestamp = [DateTimeOffset]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $evidenceRoot = Join-Path $experimentRoot "evidence\setup"
    $preStatus = @(Get-WorktreeStatus $repositoryRoot $evidenceRoot)

    $probes = [ordered] @{}
    foreach ($probe in @(
        @{ Name = "version"; Arguments = $VersionArguments },
        @{ Name = "help"; Arguments = $HelpArguments }
    )) {
        try {
            $probes[$probe.Name] = Invoke-StaticProbe $CliPath $probe.Arguments $TimeoutSeconds
        }
        catch {
            $probes[$probe.Name] = [ordered] @{
                started_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
                completed_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
                exit_code = $null
                timed_out = $false
                stdout = ""
                stderr = "[probe failure sanitized; see helper trace]"
            }
            Add-Content -LiteralPath $tracePath -Value ("{0} {1}: {2}" -f [DateTimeOffset]::UtcNow.ToString("O"), $probe.Name, (ConvertTo-SanitizedText $_.Exception.ToString()))
        }
    }

    $postStatus = @(Get-WorktreeStatus $repositoryRoot $evidenceRoot)
    $preKey = @($preStatus) -join "`n"
    $postKey = @($postStatus) -join "`n"
    $changed = $preKey -cne $postKey

    $metadata = [ordered] @{
        schema_version = 1
        cli_name = $CliName
        cli_path = $CliPath
        captured_at_utc = [DateTimeOffset]::UtcNow.ToString("O")
        probes = [ordered] @{
            version_arguments = @($VersionArguments)
            help_arguments = @($HelpArguments)
        }
        probe_results = [ordered] @{
            version_exit_code = $probes.version.exit_code
            version_timed_out = $probes.version.timed_out
            help_exit_code = $probes.help.exit_code
            help_timed_out = $probes.help.timed_out
        }
        worktree_changed_outside_evidence = $changed
        worktree_status_files = @(
            "$timestamp-$safeCliName-pre-git-status.txt",
            "$timestamp-$safeCliName-post-git-status.txt",
            "$timestamp-$safeCliName-worktree-change-summary.txt"
        )
    }

    $prePath = Join-Path $setupRoot "$timestamp-$safeCliName-pre-git-status.txt"
    $postPath = Join-Path $setupRoot "$timestamp-$safeCliName-post-git-status.txt"
    $summaryPath = Join-Path $setupRoot "$timestamp-$safeCliName-worktree-change-summary.txt"
    $metadataPath = Join-Path $setupRoot "$timestamp-$safeCliName-static-metadata.json"
    $versionPath = Join-Path $setupRoot "$timestamp-$safeCliName-version.txt"
    $helpPath = Join-Path $setupRoot "$timestamp-$safeCliName-help.txt"

    Set-Content -LiteralPath $prePath -Value $preStatus -Encoding utf8
    Set-Content -LiteralPath $postPath -Value $postStatus -Encoding utf8
    Set-Content -LiteralPath $versionPath -Value (ConvertTo-SanitizedText $probes.version.stdout) -Encoding utf8
    Add-Content -LiteralPath $versionPath -Value (ConvertTo-SanitizedText $probes.version.stderr) -Encoding utf8
    Set-Content -LiteralPath $helpPath -Value (ConvertTo-SanitizedText $probes.help.stdout) -Encoding utf8
    Add-Content -LiteralPath $helpPath -Value (ConvertTo-SanitizedText $probes.help.stderr) -Encoding utf8
    Set-Content -LiteralPath $summaryPath -Value @(
        "worktree_changed_outside_evidence=$changed"
        "pre_status_count=$($preStatus.Count)"
        "post_status_count=$($postStatus.Count)"
        "cli_name=$CliName"
        "captured_at_utc=$([DateTimeOffset]::UtcNow.ToString('O'))"
    ) -Encoding utf8
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding utf8

    Write-Output ("Static evidence saved: {0}" -f $setupRoot)
    Write-Output ("Worktree changed outside evidence: {0}" -f $changed)

    if ($FailOnWorktreeChange -and $changed) {
        exit 2
    }
}
catch {
    if ($null -ne $tracePath) {
        Add-Content -LiteralPath $tracePath -Value ("{0} fatal: {1}" -f [DateTimeOffset]::UtcNow.ToString("O"), (ConvertTo-SanitizedText $_.Exception.ToString()))
    }
    throw
}
