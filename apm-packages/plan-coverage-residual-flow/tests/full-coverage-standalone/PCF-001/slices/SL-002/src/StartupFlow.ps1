. (Join-Path $PSScriptRoot 'ProducerState.ps1')
. (Join-Path $PSScriptRoot 'ConsumerGate.ps1')

function Invoke-StartupFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId
    )

    $producer = Restore-ProducerSnapshot -CorrelationId $CorrelationId
    $consumer = Get-ConsumerState -ProducerSnapshot $producer
    $accepted = Push-ConsumerItem -ConsumerState $consumer.State -CorrelationId $consumer.CorrelationId

    [pscustomobject]@{
        SnapshotState = $producer.SnapshotState
        ConsumerState = $consumer.State
        Postcondition = $accepted.Postcondition
        CorrelationId = $accepted.CorrelationId
    }
}
