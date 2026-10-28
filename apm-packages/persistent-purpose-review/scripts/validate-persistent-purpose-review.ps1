[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$skillPath = Join-Path $packageRoot '.apm/skills/persistent-purpose-review/SKILL.md'
$paths = @(
    (Join-Path $packageRoot 'apm.yml'),
    (Join-Path $packageRoot 'README.md'),
    $skillPath,
    (Join-Path $packageRoot 'scripts/test-apm-package-install.ps1'),
    (Join-Path $packageRoot 'tests/agent-plugin/contract.json'),
    (Join-Path $packageRoot 'tests/agent-plugin/qualification.json'),
    (Join-Path $packageRoot '../../tests/PurposeReviewRunner.Tests/purpose-review-results/2026-10-28-provider-safety.md')
)
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing package file: $path" }
}

$manifest = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'apm.yml')
$skill = Get-Content -Raw -LiteralPath $skillPath
$readme = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'README.md')
$safetyEvidence = Get-Content -Raw -LiteralPath (Join-Path $packageRoot '../../tests/PurposeReviewRunner.Tests/purpose-review-results/2026-10-28-provider-safety.md')
$contract = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'tests/agent-plugin/contract.json') | ConvertFrom-Json
$qualification = Get-Content -Raw -LiteralPath (Join-Path $packageRoot 'tests/agent-plugin/qualification.json') | ConvertFrom-Json
$frontmatter = [regex]::Match($skill, '(?s)\A---\r?\n(.*?)\r?\n---').Groups[1].Value
if ([string]::IsNullOrWhiteSpace($frontmatter)) { throw 'Skill frontmatter is missing.' }

if ($frontmatter -notmatch '(?m)^user-invocable:\s*true\s*$' -or $frontmatter -notmatch '(?m)^disable-model-invocation:\s*true\s*$') {
    throw 'Skill must remain user-invocable and disable model invocation.'
}
if ($frontmatter -notmatch '(?im)^description:.*explicitly invokes' -or $frontmatter -notmatch '(?im)^description:.*Do not select automatically') {
    throw 'Skill description does not preserve the explicit-only invocation contract.'
}
if ($skill -notmatch 'ユーザーが明示的に起動した場合だけ使用' -or $skill -notmatch 'モデルが自動選択してはならない') {
    throw 'Skill body does not preserve the explicit-only invocation contract.'
}

if ($manifest -notmatch '(?m)^name:\s*persistent-purpose-review\s*$' -or $manifest -notmatch '(?m)^version:\s*0\.6\.0\s*$') {
    throw 'APM package identity/version is invalid.'
}
if ($manifest -notmatch '(?ms)^targets:\s*$.*^\s+- copilot\s*$.*^\s+- codex\s*$.*^\s+- agent-skills\s*$') {
    throw 'APM package targets are invalid.'
}
if ($skill -notmatch 'protocolVersion.*`4`' -or $skill -notmatch '0\.5\.0' -or $skill -notmatch 'schemaVersion.*1') {
    throw 'Skill does not require Runner 0.5.0 / protocol v4 / input schema 1.'
}
if ($skill -notmatch 'start --repository.*--input' -or $skill -notmatch 'continue --run.*--input' -or $skill -notmatch 'status --run') {
    throw 'Skill CLI usage does not match the public protocol v4 commands.'
}
foreach ($field in @('taskKey', 'changeId', 'previousRunId', 'purpose', 'approvedDesign', 'proposal', 'evidence', 'responses', 'conformance', 'userDecision')) {
    if ($skill -notmatch ('"' + [regex]::Escape($field) + '"')) { throw "ReviewInput example is missing field: $field" }
}
if ($skill -notmatch '削除・緩和' -or $skill -notmatch 'null' -or $skill -notmatch '記録されたownerが実行・確認したことをRunnerやreviewerが保証') {
    throw 'Input guidance omits full proposal delta, nullable baseline, or conformance owner boundary.'
}
if ($skill -notmatch '最大3回' -or $skill -notmatch 'terminal' -or $skill -notmatch '識別子を変えたりして上限を回避しない' -or $skill -notmatch '既に消費した提出数を引き継ぐ') {
    throw 'Skill does not preserve linked submission budget and terminal rules.'
}
if ($skill -notmatch '初期設計' -or $skill -notmatch '重要な変更' -or $skill -notmatch 'findingが出たことだけ' -or $skill -notmatch '実装不足だけ') {
    throw 'Skill review triggers or scope boundary are incomplete.'
}
if ($skill -notmatch '目的の引用文と根拠sourceはinputへ埋め込む' -or $skill -notmatch '承認を代行しない') {
    throw 'Skill does not preserve source-embedded authority and review/approval separation.'
}
if ($skill -notmatch 'repositoryとは別の作業directory' -or $skill -notmatch 'review inputから作ったpromptだけをstdinへ渡す' -or
    $skill -notmatch 'repository探索、外部調査、ツール呼び出し、委譲を明示的に禁じる' -or
    $skill -notmatch '完全なcapability isolationを意味しない' -or $skill -notmatch '独自の認証・隔離基盤を追加せず') {
    throw 'Skill must state the external-cwd, input-only, role-prompt, and residual-capability boundary.'
}
if ($skill -notmatch 'Copilot CLIでは実機確認済みのより制限されたprovider設定を維持する') {
    throw 'Skill must preserve the verified stricter Copilot provider configuration.'
}
if ($skill -match '(?im)^\s*(?:Grok|grok)\s*:' -or $skill -match 'grok --|--context|work --run|--session-id|--resume|--model|reasoning-effort') {
    throw 'Skill contains removed provider invocation or duplicates runner-owned invocation details.'
}
if ($readme -notmatch '--target agent-skills --global' -or $readme -notmatch 'disable-model-invocation: true' -or $readme -notmatch '\$persistent-purpose-review') {
    throw 'Package README does not preserve the install and explicit-only contract.'
}
if ($readme -notmatch '0\.5\.0' -or $readme -notmatch 'protocol v4' -or $readme -notmatch 'NOT_RUN' -or $readme -notmatch 'HOLD') {
    throw 'Package README does not state the version and qualification boundary.'
}
if ($readme -notmatch 'repository外の作業directory' -or $readme -notmatch '完全なcapability isolationとして扱いません' -or
    $readme -notmatch 'より強い制限設定を維持します') {
    throw 'Package README does not state the relaxed Codex role boundary and preserved Copilot restriction.'
}
if ($safetyEvidence -notmatch '当時のRunnerはCodexをfail closedにした' -or
    $safetyEvidence -notmatch '2026-10-29 Issue #150方針更新後のCodex実行境界' -or
    $safetyEvidence -notmatch '同じCodex session' -or
    $safetyEvidence -notmatch 'function_call.*function_call_output.*0件' -or
    $safetyEvidence -notmatch 'functions.*collaboration.*追加tool' -or
    $safetyEvidence -notmatch 'Copilot.*zero-tool実測') {
    throw 'Provider evidence must distinguish the historical Codex rejection, later bounded run, residual host tools, and preserved Copilot proof.'
}
if ($readme -match '(?im)^\s*(?:Grok|grok)\s*:' -or $readme -match 'grok --|0\.4\.0|protocol v3|--context') {
    throw 'Package README contains a removed provider invocation or protocol behavior.'
}
if ($contract.runtimeBoundary -notmatch '0\.5\.0以上 / protocol v4') {
    throw 'Agent Plugin contract does not identify the external Runner v4 boundary.'
}
if ($qualification.assessments[0].status -cne 'NOT_RUN' -or $qualification.assessments[0].evidenceMode -cne 'NONE' -or
    $qualification.assessments[1].status -cne 'HOLD' -or $qualification.assessments[1].evidenceMode -cne 'PARTIAL' -or
    $qualification.assessments[0].evidenceRefs.Count -ne 0 -or
    $qualification.assessments[1].evidenceRefs -notcontains 'tests/PurposeReviewRunner.Tests/purpose-review-results/2026-10-28-purpose-design-evaluation.md') {
    throw 'Qualification must remain APM NOT_RUN and direct deployment HOLD with the bounded live-evaluation evidence.'
}
if ($qualification.assessments[0].reason -notmatch '実モデル評価は未実施' -or
    $qualification.assessments[1].reason -notmatch '限定的な実モデル評価を実施したが') {
    throw 'Qualification reason must distinguish unrun APM qualification from bounded live evaluation.'
}

Write-Output 'Persistent Purpose Review package validation: PASS'
