. (Join-Path $PSScriptRoot 'ProducerState.ps1')
. (Join-Path $PSScriptRoot 'ConsumerGate.ps1')

function Invoke-StartupFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [Parameter(Mandatory)]
        [int]$Generation,
        [Parameter(Mandatory)]
        [string]$StorePath
    )

    $producer = Restore-ProducerSnapshot -CorrelationId $CorrelationId -Generation $Generation -StorePath $StorePath
    $consumer = Get-ConsumerState -StorePath $StorePath -ExpectedCorrelationId $CorrelationId -ExpectedGeneration $Generation
    $accepted = Push-ConsumerItem -ConsumerState $consumer.State -CorrelationId $consumer.CorrelationId -Generation $consumer.Generation

    [pscustomobject]@{
        SnapshotState = $producer.SnapshotState
        ConsumerState = $consumer.State
        Postcondition = $accepted.Postcondition
        CorrelationId = $accepted.CorrelationId
        Generation = $accepted.Generation
    }
}
