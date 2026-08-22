# Grok ローカルメタデータ確認

## 実測

- `grok inspect --json` は実験 cwd と project root を示し、global rule の path が存在することを示した。
- rule 本文、credential、認証 cache、ホーム配下の内容は開いていない。
- 実行時は `--system-prompt-override`、`--no-memory`、`--no-subagents`、`--disable-web-search` を指定した。
- `grok models` の結果は未認証表示とともに default model `grok-4.6`、利用可能 model `grok-4.5` を示した。credential 値は表示されなかった。

## 推測

- `--system-prompt-override` により reviewer 用の安全な system prompt を明示できた可能性はあるが、CLI 内部で global rule がどの層に統合されるかはこの確認だけでは断定できない。

## 未実施

- global rule の本文確認、credential の確認、ネットワーク payload の packet/API 監査は実施していない。
