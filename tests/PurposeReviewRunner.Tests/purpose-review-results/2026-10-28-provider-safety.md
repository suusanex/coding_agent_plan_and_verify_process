# Issue #150 provider安全性の実機確認

実施日: 2026-10-28  
環境: Windows / PowerShell  
目的: 目的・設計レビュー用providerについて、初回と継続の両方でファイル調査・shell・MCP等がモデルに公開されない設定を確認する。試験入力はリポジトリ外の一時ディレクトリに置いた短いfixtureのみ。

## Copilot CLI 1.0.105

採用候補は GitHub Copilot CLI `1.0.105`、model `gpt-5.6-terra`、reasoning effort `low`。CLIの `--version` は `GitHub Copilot CLI 1.0.105.` を返すため、version検証は末尾の句点を許可し、より新しいpatch版を受け入れない。

設定は初回とresumeで同一にした。`COPILOT_PLUGIN_DIR_ONLY=true` を子プロセスだけに設定し、同じ環境で `copilot mcp list --json` を実行して全server名を列挙し、それぞれを `--disable-mcp-server=<name>` で無効化した。今回列挙された名前は `github-mcp-server`。加えて `--disable-builtin-mcps`、`--no-custom-instructions`、`--disallow-temp-dir` を指定した。

`--available-tools=` と `--available-tools ""` は空allowlistにならず、CLIの既定toolへ戻ったため使用しない。`report_intent` のみを指定すると、実機のtool inventoryは0件となった。

```powershell
$env:COPILOT_PLUGIN_DIR_ONLY = 'true'
$common = @(
  '-C', '<TEMP>/purpose-review-provider-proof-copilot-final',
  '--no-custom-instructions', '--no-remote-export', '--no-auto-update', '--no-ask-user',
  '--disable-builtin-mcps', '--disallow-temp-dir', '--no-color', '--silent',
  '--output-format', 'json', '--stream', 'off', '--model', 'gpt-5.6-terra',
  '--reasoning-effort', 'low', '--available-tools=report_intent',
  '--deny-tool=shell', '--deny-tool=write', '--deny-tool=task', '--deny-tool=edit',
  '--disable-mcp-server=github-mcp-server'
)
'<fixture prompt on stdin>' | copilot @common '--session-id=<fixture-session-id>'
'<continuation fixture prompt on stdin>' | copilot @common '--resume=<fixture-session-id>'
```

両方の実行でpayloadはstdinから渡し、cwdはリポジトリ外の `<TEMP>/purpose-review-provider-proof-copilot-final`。fixtureの `fixture.txt` を読む要求と、無害なPowerShell markerを実行する要求を含めた。

初回とresumeのCLI telemetryはそれぞれ `tool_count=0`、`tools=[]`。assistant messageの `toolRequests` は空で、tool実行イベントは無かった。両方の出力で `session.mcp_servers_loaded` に記録された `WorkIQ`、`browser-use`、`github-copilot-browser`、`github-mcp-server`、`githubiq` はすべて `disabled`。モデルはshellとviewが利用不可と回答した。CLI resultは両方 `exitCode=0`、変更ファイル数0。

テレメトリでは初回にpremium request 1件、resume後の累積に2件を計上した。ドル建ての請求額はCLI telemetryに無いため記載しない。初回のsession durationは約4.5秒、resumeは約17.7秒。これはこの短いtool拒否fixtureでの値であり、レビュー所要時間の評価ではない。

## 不採用だったCopilot設定

`--available-tools=` と別引数の空文字列の両方で、CLIは21件のtoolをモデルへ公開し、`powershell` tool requestを受けてfixture内の無害なmarkerを実行した。従って空値は安全設定として扱えない。

`COPILOT_PLUGIN_DIR_ONLY=true` を外すと、plugin由来の `microsoft-learn` MCPが初期化され、接続状態になった。plugin discovery制限を加えた実行ではplugin由来serverは現れず、built-inとその他のserverもすべてdisabledだった。`--no-remote` はこのCLI版では削除済みoptionとして拒否されたため、実装には含めない。

## Codex CLI 0.165.0

Codex CLI `0.165.0`、model `gpt-5.6-terra`、reasoning effort `low`で初回とresumeを試した。実行cwdは `<TEMP>` 配下。`--ignore-user-config`、`--ignore-rules`、初回の `--sandbox read-only`、`--skip-git-repo-check` を使い、`codex features list` で確認したfeature名を `--disable` で指定した。対象はshell、browser/web、apps/MCP、multi-agent、code mode、image、skills、plugins、hooks、memories。

初回とresumeでshell toolが無いことを確認できた。さらに `code_mode_host` などを無効化すると、`functions.exec` は “Code Mode is unavailable because code-mode host is disabled” で失敗した。一方、multi-agent featureとホストrouting環境変数を無効化しても、`collaboration.list_agents` は実際の `function_call` として残り、agent数1を返した。これはagent生成そのものの試行ではないが、同じnamespaceにはagent操作toolも存在する。よってCodexはsubagent機能を確実に無効化できた証拠が不足し、runnerでは `PROVIDER_RESTRICTION_UNSUPPORTED` としてfail closedにする。

Codex CLIのバージョン確認とshell拒否だけで、全host tool bridgeの無効化を証明したとはみなさない。外部実行時のsession/rollout識別子とユーザー固有pathはこの資料へ転記せず、試験cwdは `<TEMP>/purpose-review-provider-proof-codex-*`、rollout格納先は `<CODEX_HOME>/sessions/<date>/` として表記した。

## 自動テスト

対象: `dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj --no-restore --filter FullyQualifiedName~ProviderAdapterTests`  
結果: 6 passed、0 failed。Codex fail-closed、Copilot初回/resume引数、MCP列挙と無効化、未検証version/profileの拒否、検証済みversionへのsuffix追加拒否、Grok拒否を確認した。実機のzero-tool telemetryは上記のCLI fixtureで別途確認した。

## 評価runの利用量記録

Issue #150の評価で実際にmodelを呼び出したrunと、追加のvague-design runについて、Runnerのworker logおよび該当Copilot CLI process logをsession IDで照合した。これらの記録にpremium request数、token数、NanoAIUまたは金額のrun別usage fieldは残っていなかった。従って評価runごとの利用量・請求額は不明であり、推定しない。上記の安全性fixtureのtelemetry値はこの評価run群とは別の計測である。
