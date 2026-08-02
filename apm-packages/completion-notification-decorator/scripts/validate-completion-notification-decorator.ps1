$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = (Resolve-Path (Join-Path $packageRoot '..\..')).Path
$canonicalRoot = Join-Path $repositoryRoot 'scripts/codex-notification-runtime'
$assetRoot = Join-Path $packageRoot '.apm/skills/completion-notification-decorator/assets/codex-notification-runtime'
$files = @('README.md', 'codex-notification-runtime.cs', 'local-spool-provider.cs', 'install-codex-notification-runtime-local.cs', 'spool-item-v1.schema.json', 'completion-notification-envelope-v1.schema.json', 'completion-notification-event-v1.schema.json', 'decision-record.md', 'manual-verification.md', 'windows-app-notification-provider.cs')
foreach ($file in $files) {
    $canonical = Join-Path $canonicalRoot $file; $asset = Join-Path $assetRoot $file
    if (-not (Test-Path $canonical) -or -not (Test-Path $asset)) { throw "Missing canonical or checked asset: $file" }
    if ((Get-FileHash $canonical -Algorithm SHA256).Hash -ne (Get-FileHash $asset -Algorithm SHA256).Hash) { throw "Checked mirror mismatch: $file" }
}
$validationRoot = Join-Path ([IO.Path]::GetTempPath()) ('completion-notification-package-' + [guid]::NewGuid().ToString('N'))
try {
    $output = Join-Path $validationRoot 'provider'; $spool = Join-Path $validationRoot 'spool'; New-Item -ItemType Directory -Path $output, $spool | Out-Null
    dotnet publish (Join-Path $assetRoot 'local-spool-provider.cs') --output $output --disable-build-servers
    if ($LASTEXITCODE -ne 0) { throw 'Installed Local Spool provider publish failed.' }
    $payload = @{ schema_version = 1; source = 'codex.agent-turn-complete'; source_event_id = 'codex:package:fixture'; primary_process = 'completion-notification-decorator'; observed_status = 'COMPLETED'; occurred_at = '2026-08-01T00:00:00.0000000Z'; title = 'fixture'; repository = 'owner/repository'; resume_uri = 'codex://threads/package'; result_uri = $null; notification_status = 'PENDING' } | ConvertTo-Json -Compress
    $env:CODEX_NOTIFICATION_SPOOL_HOME = $spool; $payload | & (Join-Path $output 'local-spool-provider.exe'); if ($LASTEXITCODE -ne 0) { throw 'Installed Local Spool provider failed.' }
    $items = @(Get-ChildItem $spool -Filter '*.json'); if ($items.Count -ne 1) { throw 'Installed package provider did not publish exactly one item.' }
    $item = Get-Content $items[0] -Raw | ConvertFrom-Json; if (@($item.PSObject.Properties.Name).Count -ne 10 -or $item.PSObject.Properties.Name -contains 'notification_status') { throw 'Installed package provider did not preserve the 10-field contract.' }
    $invalidSpool = Join-Path $validationRoot 'invalid-spool'; New-Item -ItemType Directory -Path $invalidSpool | Out-Null
    $invalidPayload = $payload | ConvertFrom-Json; $invalidPayload.PSObject.Properties.Remove('notification_status'); $env:CODEX_NOTIFICATION_SPOOL_HOME = $invalidSpool
    ($invalidPayload | ConvertTo-Json -Compress) | & (Join-Path $output 'local-spool-provider.exe') 2>$null
    if ($LASTEXITCODE -ne 2 -or @(Get-ChildItem -LiteralPath $invalidSpool -Force -File).Count -ne 0) { throw 'Installed package provider did not reject an incomplete 11-field event without publishing output.' }
    $wrongTypeSpool = Join-Path $validationRoot 'wrong-type-spool'; New-Item -ItemType Directory -Path $wrongTypeSpool | Out-Null
    $wrongTypePayload = $payload | ConvertFrom-Json; $wrongTypePayload.schema_version = '1'; $env:CODEX_NOTIFICATION_SPOOL_HOME = $wrongTypeSpool
    ($wrongTypePayload | ConvertTo-Json -Compress) | & (Join-Path $output 'local-spool-provider.exe') 2>$null
    if ($LASTEXITCODE -ne 2 -or @(Get-ChildItem -LiteralPath $wrongTypeSpool -Force -File).Count -ne 0) { throw 'Installed package provider did not normalize wrong JSON types to invalid-stdin.' }
    Write-Output 'Completion Notification Decorator validation: PASS (checked Local Spool mirror and installed provider contract)'
}
finally { Remove-Item Env:CODEX_NOTIFICATION_SPOOL_HOME -ErrorAction SilentlyContinue; if (Test-Path $validationRoot) { Remove-Item -LiteralPath $validationRoot -Recurse -Force }; $global:LASTEXITCODE = 0 }
