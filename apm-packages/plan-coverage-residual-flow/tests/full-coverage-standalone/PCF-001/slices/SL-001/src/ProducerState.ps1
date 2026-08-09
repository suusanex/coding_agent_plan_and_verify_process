function Restore-ProducerSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [Parameter(Mandatory)]
        [int]$Generation,
        [Parameter(Mandatory)]
        [string]$StorePath
    )

    $snapshot = [pscustomobject]@{
        SnapshotState = 'Active'
        CorrelationId = $CorrelationId
        Generation = $Generation
        Published = $true
    }

    $storeDirectory = Split-Path -Parent $StorePath
    if (-not [string]::IsNullOrWhiteSpace($storeDirectory)) {
        New-Item -ItemType Directory -Path $storeDirectory -Force | Out-Null
    }

    $temporaryPath = "$StorePath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $snapshot | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM
        Move-Item -LiteralPath $temporaryPath -Destination $StorePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }

    return $snapshot
}
