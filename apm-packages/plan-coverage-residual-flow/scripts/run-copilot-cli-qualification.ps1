[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('plan-coverage-residual-flow', 'token-aware-full-coverage-3layer')]
    [string]$PackageName,

    [string]$Repository,

    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$Ref,

    [string]$LocalSkillPath,

    [string]$OutputRoot = (Join-Path (Get-Location) 'tests\copilot-cli\runs'),

    [switch]$RunModel,

    [string]$Prompt,

    [string]$ModelScenarioId = 'explicit-lite',

    [switch]$KeepWorkspace
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Repository) -xor [string]::IsNullOrWhiteSpace($Ref)) {
    throw 'Repository and Ref must be supplied together.'
}

if ($RunModel -and [string]::IsNullOrWhiteSpace($Prompt)) {
    throw 'Prompt is required when -RunModel is specified.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$packageRelative = "apm-packages\$PackageName"
$packageRoot = Join-Path $repoRoot $packageRelative
$scenarioPath = Join-Path $packageRoot 'tests\copilot-cli\qualification-scenarios.json'
$localSkillCandidate = $null
if (-not [string]::IsNullOrWhiteSpace($LocalSkillPath)) {
    $localSkillCandidate = if ([System.IO.Path]::IsPathRooted($LocalSkillPath)) {
        $LocalSkillPath
    }
    else {
        Join-Path $repoRoot $LocalSkillPath
    }
}

if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) {
    throw "Package directory does not exist: $packageRelative"
}
if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
    throw "Qualification fixture does not exist: $scenarioPath"
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $resolvedOutputRoot -Force | Out-Null
$runName = "$PackageName-$(Get-Date -Format yyyyMMdd-HHmmss)-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
$runRoot = Join-Path $resolvedOutputRoot $runName
$workspace = Join-Path $runRoot 'workspace'
$logRoot = Join-Path $runRoot 'copilot-logs'
New-Item -ItemType Directory -Path $workspace, $logRoot -Force | Out-Null

function Write-Utf8File([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllLines($Path, $Lines, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured([string]$FilePath, [string[]]$Arguments, [string]$OutputPath) {
    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    Write-Utf8File $OutputPath @($output | ForEach-Object { [string]$_ })
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

function Get-CommandVersion([string]$FilePath, [string[]]$Arguments) {
    $result = Invoke-Captured $FilePath $Arguments (Join-Path $runRoot ("$([System.IO.Path]::GetFileNameWithoutExtension($FilePath))-version.txt"))
    if ($result.ExitCode -ne 0) {
        throw "$FilePath version command failed with exit code $($result.ExitCode)."
    }
    return (($result.Output -join "`n").Trim())
}

function Get-GitState() {
    $head = (& git -C $repoRoot rev-parse HEAD 2>$null).Trim()
    $status = @(& git -C $repoRoot status --short 2>$null)
    if ($status.Count -gt 0) {
        return "$head-dirty"
    }
    return $head
}

function Get-InstalledPackageVersion([string]$LockPath, [string]$Name) {
    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
        return 'UNOBSERVABLE'
    }

    $lines = Get-Content -LiteralPath $LockPath
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s+name:\s+$([regex]::Escape($Name))\s*$") {
            for ($lookAhead = $index + 1; $lookAhead -lt [Math]::Min($index + 12, $lines.Count); $lookAhead++) {
                if ($lines[$lookAhead] -match '^\s+version:\s*(\S+)\s*$') {
                    return $Matches[1]
                }
            }
        }
    }
    return 'UNOBSERVABLE'
}

$scenarioData = Get-Content -Raw -LiteralPath $scenarioPath | ConvertFrom-Json
$copilotVersion = Get-CommandVersion 'copilot' @('--version')
$apmVersion = Get-CommandVersion 'apm' @('--version')
$sourceRevision = Get-GitState
$installMode = 'remote-package'
$installResult = $null
$localSkillResolved = $null

try {
    Push-Location $workspace
    try {
        if (-not [string]::IsNullOrWhiteSpace($Repository)) {
            $packageSpec = "$Repository/apm-packages/$PackageName#$Ref"
            $installResult = Invoke-Captured 'apm' @('install', $packageSpec, '--target', 'copilot,agent-skills', '--https', '--no-audit') (Join-Path $runRoot 'apm-install.txt')
        }
        else {
            if ([string]::IsNullOrWhiteSpace($LocalSkillPath)) {
                throw 'Supply Repository and Ref for a full package install, or LocalSkillPath for a local Skill-only probe.'
            }
            $localSkillResolved = (Resolve-Path $localSkillCandidate).Path
            $installMode = 'local-skill-only'
            $installResult = Invoke-Captured 'apm' @('install', $localSkillResolved, '--target', 'agent-skills', '--no-audit') (Join-Path $runRoot 'apm-install.txt')
        }

        if ($installResult.ExitCode -ne 0) {
            throw "APM install failed with exit code $($installResult.ExitCode)."
        }

        $skillRelative = ".agents\skills\$PackageName\SKILL.md"
        $skillPath = Join-Path $workspace $skillRelative
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            throw "APM install did not deploy $skillRelative."
        }

        $skillList = Invoke-Captured 'copilot' @('skill', 'list') (Join-Path $runRoot 'copilot-skill-list.txt')
        if ($skillList.ExitCode -ne 0) {
            throw "Copilot skill list failed with exit code $($skillList.ExitCode)."
        }

        $skillHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $skillPath).Hash.ToLowerInvariant()
        $lockPath = Join-Path $workspace 'apm.lock.yaml'
        if (Test-Path -LiteralPath $lockPath -PathType Leaf) {
            Copy-Item -LiteralPath $lockPath -Destination (Join-Path $runRoot 'apm.lock.yaml') -Force
        }

        $modelStatus = 'NOT RUN'
        $modelExit = 'N/A'
        if ($RunModel) {
            $modelResult = Invoke-Captured 'copilot' @(
                '--no-auto-update',
                '-p',
                $Prompt,
                '--allow-all-tools',
                '--allow-all-paths',
                '--no-ask-user',
                '--output-format',
                'json',
                '--silent',
                '--log-level',
                'debug',
                '--log-dir',
                $logRoot
            ) (Join-Path $runRoot 'copilot-model-output.jsonl')
            $modelExit = [string]$modelResult.ExitCode
            $modelStatus = if ($modelResult.ExitCode -eq 0) { 'UNOBSERVABLE' } else { 'FAIL' }
        }

        $lockPackageVersion = Get-InstalledPackageVersion (Join-Path $workspace 'apm.lock.yaml') $PackageName
        $skillListText = ($skillList.Output -join "`n")
        $skillDiscovered = $skillListText -match [regex]::Escape($PackageName)
        $agentPath = Join-Path $workspace '.github\agents'
        $instructionPath = if ($PackageName -eq 'token-aware-full-coverage-3layer') {
            Join-Path $workspace '.github\instructions\token-aware-full-coverage-3layer.instructions.md'
        }
        else {
            Join-Path $workspace '.github\instructions\plan-coverage-shared.instructions.md'
        }
        $agentStatus = if (Test-Path -LiteralPath $agentPath -PathType Container) { 'observed' } else { 'not deployed by local Skill-only mode' }
        $instructionStatus = if (Test-Path -LiteralPath $instructionPath -PathType Leaf) { 'observed' } else { 'not deployed by local Skill-only mode' }
        $overallStatus = if ($skillDiscovered) { 'PASS' } else { 'UNOBSERVABLE' }

        $recordLines = [System.Collections.Generic.List[string]]::new()
        [void]$recordLines.Add("# GitHub Copilot CLI qualification result")
        [void]$recordLines.Add('')
        [void]$recordLines.Add("- Date: $(Get-Date -Format o)")
        [void]$recordLines.Add("- Operator: automated repository-local harness")
        [void]$recordLines.Add("- Copilot CLI version: $copilotVersion")
        [void]$recordLines.Add("- APM version: $apmVersion")
        [void]$recordLines.Add("- Package: $PackageName")
        [void]$recordLines.Add("- Package version in lock: $lockPackageVersion")
        [void]$recordLines.Add("- Package source and full commit: $(if ($Repository) { "$Repository#$Ref" } else { $localSkillResolved })")
        [void]$recordLines.Add("- Source repository revision: $sourceRevision")
        [void]$recordLines.Add("- Install mode: $installMode")
        [void]$recordLines.Add("- Working repository: $workspace")
        [void]$recordLines.Add("- Installed Skill path: $skillRelative")
        [void]$recordLines.Add("- Installed Skill SHA-256: $skillHash")
        [void]$recordLines.Add("- Installed agent path: $agentStatus")
        [void]$recordLines.Add("- Installed instruction path: $instructionStatus")
        [void]$recordLines.Add("- Model capability observation: requested and observed model values require separate evidence; this harness does not infer per-agent model locking.")
        [void]$recordLines.Add('')
        [void]$recordLines.Add('| Scenario | Status | Observable evidence | Validation |')
        [void]$recordLines.Add('| --- | --- | --- | --- |')

        foreach ($scenario in @($scenarioData.real_cli_scenarios)) {
            $status = switch ([string]$scenario.id) {
                'install-and-skill-discovery' { $overallStatus; break }
                'design-pair-e2e' { 'BLOCKED'; break }
                default { 'NOT RUN'; break }
            }
            $evidence = switch ($status) {
                'PASS' { "APM install output and copilot skill list contain ``$PackageName``." ; break }
                'BLOCKED' { 'Issue #69 canonical Copilot support is not merged.'; break }
                default { 'Not executed by this harness invocation.'; break }
            }
            $validation = if ($status -eq 'PASS') { "exit 0; SHA-256 $skillHash" } else { 'manual or later real-model run required' }
            [void]$recordLines.Add("| $($scenario.id) | $status | $evidence | $validation |")
        }

        if ($RunModel) {
            [void]$recordLines.Add("| $ModelScenarioId model prompt | $modelStatus | Copilot CLI exit code $modelExit; route/agent selection remains separately observable evidence. | inspect copilot-model-output.jsonl and debug log |")
        }
        [void]$recordLines.Add('')
        [void]$recordLines.Add('## Notes and limitations')
        [void]$recordLines.Add('')
        [void]$recordLines.Add("- `local-skill-only` proves CLI Skill discovery for the working-tree Skill but does not prove the full `git: parent` dependency graph.")
        [void]$recordLines.Add("- Static validators and Skill discovery do not prove real model routing, production mutation, or durable process completion.")
        [void]$recordLines.Add("- Design Pair E2E remains blocked by Issue #69.")

        Write-Utf8File (Join-Path $runRoot 'result.md') $recordLines
        Write-Host "GitHub Copilot CLI qualification: $overallStatus"
        Write-Host "Result: $(Join-Path $runRoot 'result.md')"
    }
    finally {
        Pop-Location
    }
}
finally {
    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspace)) {
        Remove-Item -LiteralPath $workspace -Recurse -Force
    }
}
