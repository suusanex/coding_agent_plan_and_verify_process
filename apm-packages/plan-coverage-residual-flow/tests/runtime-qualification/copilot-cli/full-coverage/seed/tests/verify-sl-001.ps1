$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'src/ProducerState.ps1')

$storePath = [IO.Path]::Combine([IO.Path]::GetTempPath(), "full-001-sl1-$([Guid]::NewGuid().ToString('N')).json")
try {
    $snapshot = Restore-ProducerSnapshot -CorrelationId 'full-001' -Generation 3 -StorePath $storePath
    if ($snapshot.SnapshotState -cne 'Active') { throw 'Producer snapshot is not Active.' }
    if ($snapshot.CorrelationId -cne 'full-001') { throw 'correlation_id mismatch.' }
    if ([int]$snapshot.Generation -ne 3) { throw 'generation mismatch.' }
    if (-not [bool]$snapshot.Published) { throw 'Published flag missing.' }
    if (-not (Test-Path -LiteralPath $storePath -PathType Leaf)) { throw 'Durable store was not written.' }

    $disk = Get-Content -LiteralPath $storePath -Raw | ConvertFrom-Json
    if ($disk.SnapshotState -cne 'Active' -or $disk.CorrelationId -cne 'full-001' -or [int]$disk.Generation -ne 3) {
        throw 'Durable store content does not match the returned snapshot.'
    }

    [pscustomobject]@{
        verdict = 'SL_001_VERIFIED'
        store_written = $true
        snapshot_state = $snapshot.SnapshotState
        correlation_id = $snapshot.CorrelationId
        generation = [int]$snapshot.Generation
    } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $storePath -Force -ErrorAction SilentlyContinue
}
