# Incomplete seed. Consumer startup/replay must be implemented under Plan Coverage.
function Get-ConsumerState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StorePath,
        [Parameter(Mandatory)]
        [string]$ExpectedCorrelationId,
        [Parameter(Mandatory)]
        [int]$ExpectedGeneration
    )

    throw 'Get-ConsumerState is not implemented.'
}

function Push-ConsumerItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConsumerState,
        [Parameter(Mandatory)]
        [string]$CorrelationId,
        [Parameter(Mandatory)]
        [int]$Generation
    )

    throw 'Push-ConsumerItem is not implemented.'
}
