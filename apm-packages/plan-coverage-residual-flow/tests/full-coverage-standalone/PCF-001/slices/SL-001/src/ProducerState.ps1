function Restore-ProducerSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId
    )

    [pscustomobject]@{
        SnapshotState = 'Active'
        CorrelationId = $CorrelationId
    }
}
