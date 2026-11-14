param()
$ErrorActionPreference = 'Stop'
$scriptPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\finalize-codex-agent-profiles.cs'))
$root = Join-Path ([IO.Path]::GetTempPath()) ('codex-finalizer-' + [guid]::NewGuid().ToString('N'))
function Invoke-Finalizer([string[]] $a) { $o = & dotnet run --file $scriptPath -- @a 2>&1 | Out-String; [pscustomobject]@{ ExitCode=$LASTEXITCODE; Output=$o } }
function Assert-True([bool]$ok,[string]$m) { if (-not $ok) { throw $m } }
try {
  $profileRoot=Join-Path $root 'home'; $codex=Join-Path $root 'codex'
  $pkg=Join-Path $profileRoot '.apm/apm_modules/owner/repo/adaptive-implementation-execution'
  $src=Join-Path $pkg '.apm/agents'; $dst=Join-Path $codex 'agents'
  New-Item -ItemType Directory -Force -Path $src,$dst | Out-Null
  Set-Content (Join-Path $pkg 'apm.yml') 'name: adaptive-implementation-execution'
  $p='decision-surface-implementation-owner'; $c='bounded-residual-implementation-owner'
  foreach($a in @($p,$c)) {
    $body=if($a -eq $c){'Canonical child.' + "`n" + '[example]' + "`n" + 'model = body-value'}else{'Canonical body.'}
    @('---',"name: $a",'description: Fixture','---','',$body) -join "`n" | Set-Content (Join-Path $src "$a.agent.md")
  }
  @{schemaVersion=1;package='adaptive-implementation-execution';profiles=@(@{agent=$c;model='gpt-6-luna';model_reasoning_effort='high';sandbox_mode='workspace-write'})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $pkg 'codex-profile-overlays.json')
  @'
name = "decision-surface-implementation-owner"
description = "Fixture"
developer_instructions = "Canonical body."
extra = "keep"
'@ | Set-Content (Join-Path $dst "$p.toml") -NoNewline
  @'
name = 'bounded-residual-implementation-owner'
description = "Fixture"
developer_instructions = """Canonical child.
[example]
model = body-value"""
' model ' = "unknown-key-preserved"
extra = "keep"
[custom]
model = "nested-value"
'@ | Set-Content (Join-Path $dst "$c.toml") -NoNewline
  $names=@('USERPROFILE','HOME','CODEX_HOME','APM_HOME'); $old=@{}
  foreach($n in $names){$old[$n]=[Environment]::GetEnvironmentVariable($n,'Process')}
  try {
    $env:USERPROFILE=$profileRoot; $env:HOME=$profileRoot; $env:CODEX_HOME=$codex; $env:APM_HOME=Join-Path $root 'ignored'
    $childPath=Join-Path $dst "$c.toml"
    $beforeDryRun=Get-Content -Raw $childPath
    $r=Invoke-Finalizer @('--global','--check'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'update\(s\) required') "check accepted missing profile fields: $($r.Output)"
    $r=Invoke-Finalizer @('--global','--dry-run'); Assert-True ($r.ExitCode -eq 0 -and $r.Output -match 'planned') 'dry-run did not plan missing profile fields'
    Assert-True ((Get-Content -Raw $childPath) -ceq $beforeDryRun) 'dry-run changed the target'
    Assert-True ((Invoke-Finalizer @('--global')).ExitCode -eq 0) 'apply failed'
    $text=Get-Content -Raw $childPath
    Assert-True ($text.Contains('Canonical child.') -and $text.Contains('[example]') -and $text.Contains('model = body-value')) 'profile insertion changed multiline body text'
    Assert-True ($text.Contains('extra = "keep"') -and $text.Contains(''' model '' = "unknown-key-preserved"') -and $text.Contains('[custom]')) 'profile update changed unrelated content or normalized an unknown quoted key'
    Assert-True ($text.Contains('model = "gpt-6-luna"') -and $text.Contains('model_reasoning_effort = "high"') -and $text.Contains('sandbox_mode = "workspace-write"')) 'missing profile fields were not inserted'
    $stableHash=(Get-FileHash $childPath -Algorithm SHA256).Hash
    $r=Invoke-Finalizer @('--global','--check'); Assert-True ($r.ExitCode -eq 0) "check failed after apply: $($r.Output)`n$(Get-Content -Raw $childPath)"
    Assert-True ((Invoke-Finalizer @('--global')).ExitCode -eq 0) 'idempotent apply failed'
    Assert-True ((Get-FileHash $childPath -Algorithm SHA256).Hash -eq $stableHash) 'idempotent apply changed the file'
    $conflictRoot=Join-Path $profileRoot '.apm/apm_modules/owner/repo/second-package'
    New-Item -ItemType Directory -Force -Path (Join-Path $conflictRoot '.apm/agents') | Out-Null
    Set-Content (Join-Path $conflictRoot 'apm.yml') 'name: second-package'
    foreach($a in @($p,$c)) { @('---',"name: $a",'description: Fixture','---','','Canonical body.') -join "`n" | Set-Content (Join-Path $conflictRoot ".apm/agents/$a.agent.md") }
    @{schemaVersion=1;package='second-package';profiles=@(@{agent=$c;model='other-model';model_reasoning_effort='high';sandbox_mode='workspace-write'})} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $conflictRoot 'codex-profile-overlays.json')
    $conflictHash=(Get-FileHash $childPath -Algorithm SHA256).Hash
    $r=Invoke-Finalizer @('--global'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'Conflicting Codex profile overlays') 'conflicting overlay accepted'
    Assert-True ((Get-FileHash $childPath -Algorithm SHA256).Hash -eq $conflictHash) 'overlay conflict changed a projection'
    Remove-Item $conflictRoot -Recurse -Force
    $invalidRoot=Join-Path $profileRoot '.apm/apm_modules/owner/repo/invalid-package'
    New-Item -ItemType Directory -Force $invalidRoot | Out-Null
    Set-Content (Join-Path $invalidRoot 'apm.yml') 'name: invalid-package'
    Set-Content (Join-Path $invalidRoot 'codex-profile-overlays.json') '{ invalid json'
    $r=Invoke-Finalizer @('--global'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'JsonException|StackTrace|at System\.') 'invalid overlay lacked exception diagnostics'
    Remove-Item $invalidRoot -Recurse -Force
    $bad=$text.Replace('model = "gpt-6-luna"', 'model = ''manual'''); Set-Content $childPath $bad -NoNewline
    $r=Invoke-Finalizer @('--global'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'use --force') 'mismatch was not rejected'
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -eq 0) "force failed: $($r.Output)"
    $text=Get-Content -Raw $childPath
    $quotedModel=$text.Replace('model = "gpt-6-luna"', "'model' = 'gpt-6-luna' # preserve comment")
    $multilineValue='"""manual"""'
    $multilineProfile=$quotedModel.Replace("'model' = 'gpt-6-luna'", "'model' = " + $multilineValue)
    Set-Content $childPath $multilineProfile -NoNewline
    $r=Invoke-Finalizer @('--global'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'use --force') 'multiline profile mismatch was not rejected'
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -eq 0) "multiline profile force failed: $($r.Output)"
    $text=Get-Content -Raw $childPath
    Assert-True ($text.Contains("'model' = `"gpt-6-luna`" # preserve comment")) 'force did not preserve quoted key and comment when replacing a multiline profile value'
    $duplicate=$text.Replace('[custom]', "model = 'duplicate'" + [Environment]::NewLine + '[custom]')
    Set-Content $childPath $duplicate -NoNewline
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -ne 0) "duplicate top-level profile key accepted: $($r.Output)"
    Assert-True ((Get-Content -Raw $childPath) -ceq $duplicate) 'duplicate key failure changed the target'
    Set-Content $childPath $text -NoNewline
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -eq 0) 'restoring duplicate fixture failed'
    $bodyEdit=$text.Replace('Canonical child.','Manually changed body.')
    Set-Content $childPath $bodyEdit -NoNewline
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'ownership mismatch') 'portable body mismatch accepted with --force'
    Assert-True ((Get-Content -Raw $childPath) -ceq $bodyEdit) 'portable body mismatch changed the target'
    $parentPath=Join-Path $dst "$p.toml"; $parentText=Get-Content -Raw $parentPath
    Set-Content $parentPath ($parentText + "`nmodel = 'pin'") -NoNewline
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'profile fields must be absent') 'parent pin accepted'
    Set-Content $parentPath ($parentText.Replace('Fixture','Changed')) -NoNewline
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'ownership mismatch') 'portable ownership mismatch accepted'
    Set-Content $parentPath 'name = "broken' -NoNewline
    $r=Invoke-Finalizer @('--global','--force'); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'Invalid Codex projection') 'malformed TOML accepted'
    $defaultAgents=Join-Path $profileRoot '.codex/agents'
    New-Item -ItemType Directory -Force $defaultAgents | Out-Null
    @'
name = "decision-surface-implementation-owner"
description = "Fixture"
developer_instructions = "Canonical body."
'@ | Set-Content (Join-Path $defaultAgents "$p.toml") -NoNewline
    @'
name = "bounded-residual-implementation-owner"
description = "Fixture"
developer_instructions = """Canonical child.
[example]
model = body-value"""
model = "gpt-6-luna"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
'@ | Set-Content (Join-Path $defaultAgents "$c.toml") -NoNewline
    $env:CODEX_HOME=$null
    $r=Invoke-Finalizer @('--global','--check'); Assert-True ($r.ExitCode -eq 0 -and $r.Output.Contains($defaultAgents)) 'default Codex home did not use the isolated profile'
    $env:CODEX_HOME=$codex
    $r=Invoke-Finalizer @(); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match '--global is required') 'missing global accepted'
    $r=Invoke-Finalizer @($root); Assert-True ($r.ExitCode -ne 0 -and $r.Output -match 'Unknown argument') 'local target accepted'
  } finally { foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$old[$n],'Process')} }
  Write-Output 'Codex profile finalizer validation: PASS'
} finally { if(Test-Path $root){Remove-Item $root -Recurse -Force} }
