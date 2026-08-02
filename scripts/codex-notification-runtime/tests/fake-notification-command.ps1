param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('provider', 'chain')]
    [string]$Mode,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArguments
)

if ($Mode -eq 'provider') {
    $payload = [Console]::In.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_NOTIFICATION_TEST_PROVIDER_CHILD_OUTPUT)) {
        $childScript = 'Start-Sleep -Milliseconds 2500; [System.IO.File]::WriteAllText($args[0], "child-survived")'
        Start-Process -FilePath (Get-Command pwsh).Source -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', $childScript, $env:CODEX_NOTIFICATION_TEST_PROVIDER_CHILD_OUTPUT) | Out-Null
    }
    $delay = [int]($env:CODEX_NOTIFICATION_TEST_PROVIDER_DELAY_MS ?? '0')
    if ($delay -gt 0) { Start-Sleep -Milliseconds $delay }
    [System.IO.File]::AppendAllText($env:CODEX_NOTIFICATION_TEST_PROVIDER_OUTPUT, $payload + [Environment]::NewLine)
    exit ([int]($env:CODEX_NOTIFICATION_TEST_PROVIDER_EXIT ?? '0'))
}

[System.IO.File]::AppendAllText($env:CODEX_NOTIFICATION_TEST_CHAIN_OUTPUT, $RemainingArguments[$RemainingArguments.Count - 1] + [Environment]::NewLine)
exit ([int]($env:CODEX_NOTIFICATION_TEST_CHAIN_EXIT ?? '0'))
