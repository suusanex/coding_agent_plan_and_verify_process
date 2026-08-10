# Incomplete seed. Producer durable publication must be implemented under Plan Coverage.
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

    throw 'Restore-ProducerSnapshot is not implemented.'
}
