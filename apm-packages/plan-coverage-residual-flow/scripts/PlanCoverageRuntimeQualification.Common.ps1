# Dot-source専用。Plan Coverage runtime qualificationの入力identityと終了判定を共有する。

function Get-QualificationInputRelativePaths([string]$RepositoryRoot) {
    $rootPaths = @(
        'apm-packages/plan-coverage-residual-flow/.apm',
        'apm-packages/adaptive-implementation-execution/.apm'
    )
    $filePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($relativeRoot in $rootPaths) {
        $fullRoot = Join-Path $RepositoryRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $fullRoot -PathType Container)) {
            throw "Qualification input directory not found: $relativeRoot"
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $fullRoot -Recurse -File)) {
            $relativePath = $file.FullName.Substring($RepositoryRoot.Length).TrimStart('\', '/').Replace('\', '/')
            $filePaths.Add($relativePath)
        }
    }
    foreach ($relativePath in @(
            'apm-packages/plan-coverage-residual-flow/apm.yml',
            'apm-packages/adaptive-implementation-execution/apm.yml',
            'apm-packages/adaptive-implementation-execution/codex-profile-overlays.json',
            'apm-packages/codex-profile-finalizer/apm.yml',
            'apm-packages/codex-profile-finalizer/scripts/finalize-codex-agent-profiles.cs'
        )) {
        $fullPath = Join-Path $RepositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Qualification input file not found: $relativePath"
        }
        $filePaths.Add($relativePath)
    }
    $paths = [string[]]$filePaths.ToArray()
    [Array]::Sort($paths, [StringComparer]::Ordinal)
    return $paths
}

function Get-PlanCoverageQualificationInputFingerprint([string]$RepositoryRoot) {
    $resolvedRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    $builder = [System.Text.StringBuilder]::new()
    foreach ($relativePath in @(Get-QualificationInputRelativePaths $resolvedRoot)) {
        $content = [System.IO.File]::ReadAllText((Join-Path $resolvedRoot $relativePath)).Replace("`r`n", "`n").Replace("`r", "`n")
        [void]$builder.Append($relativePath)
        [void]$builder.Append("`n")
        [void]$builder.Append($content)
        if (-not $content.EndsWith("`n")) {
            [void]$builder.Append("`n")
        }
        [void]$builder.Append("`n")
    }
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($builder.ToString())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ReevaluationOutputPaths([string]$ExistingResultPath) {
    $resolvedJsonPath = [System.IO.Path]::GetFullPath($ExistingResultPath)
    return [pscustomobject]@{
        JsonPath = $resolvedJsonPath
        MarkdownPath = [System.IO.Path]::ChangeExtension($resolvedJsonPath, '.md')
    }
}

function Test-QualificationCommandSucceeded([string]$OverallStatus) {
    return @('QUALIFIED', 'PENDING') -ccontains $OverallStatus
}
