# User Guide

## いちばん短い始め方

Codex には普通に依頼すればよい。

```text
この issue を進めて。
このバグを直して。
この機能を実装して。
この PR の残件を片付けて。
続きやって。
```

process 名、agent 名、model 名、full-coverage かどうかは利用者が選ばない。
Codex 側が repo rules と既存 artifact を読み、次に安全な工程を決める。

## Codex が内部で行うこと

1. 依頼内容と対象 repo の指示を読む。
2. 必要なら `plans/<slug>/codex-first-state.md` を作る。
3. いきなり実装せず、Plan / risk / scan / contract のどこから始めるか判断する。
4. READY になった範囲だけ、内部的に `standard-implementer` へ委譲して実装する。
5. 実装後に `standard-verifier` などで test / verification / close 可否を確認する。
6. 止まる必要がある場合だけ、必要最小限の質問を返す。

Codex は内部で Routing Plan と Agent Usage Ledger を残す。利用者が agent や model を選ぶ必要はないが、結果にはどの工程をどの agent / tier へ委譲したかの summary が含まれる。

## VS Code Codex 拡張でのローカル導入

`codex-first-start.ps1` は一時 launcher なので、VS Code 拡張のようにリポジトリごとに標準運用を残したい場合は、次のインストーラを先に実行する。

```powershell
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\install-codex-first-local.cs -- <target-repo-path>
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\install-codex-first-local.cs -- <target-repo-path> --dry-run
```

このインストーラは次を対象リポジトリへ追加します。

- `AGENTS.md` の Codex-first セクション（既存を上書きしない既定）
- `.codex/config.toml`（足りないキーだけ補完）
- `.codex/agents/*.toml`（同名既存ファイルは競合時に停止）
- `templates/codex-first-state.md`

必要なら `--force` を使って既存の `AGENTS.md` section / agent / template を上書きし、VScode 再読込して反映確認する。

## 止まったときの見方

よくある停止理由は次の通り。

- `NeedsHumanDecision`: 仕様や優先順位を人が決める必要がある。
- `ManualVerificationRequired`: 外部環境や目視など、人の確認が必要。
- `NeedsSecretInput`: secret や認証情報が必要。
- `NeedsExternalOperation`: 本番環境、課金、外部サービス操作が必要。
- `NeedsHigherModelReview`: 影響範囲や判断が難しく、上位 review が必要。

Codex が止まった場合も、利用者は工程名を選ばなくてよい。
提示された質問へ答えるか、外部確認の結果を渡せば再開できる。

## close してはいけない例

- 手動確認が必要なのに `ManualVerificationRequired` が残っている。
- 仕様判断が必要なのに `NeedsHumanDecision` が残っている。
- 上位 review が必要なのに `NeedsHigherModelReview` が残っている。
- fake / stub のテストだけ通っていて production wiring が未確認。
- READY implementation / verification の委譲証跡がなく、`DelegationCompliance` が PASS になっていない。

## 熟練 operator 向け

full-coverage 3層運用や既存 APM package の直接指定は advanced route で扱う。
通常の利用者向け入口では使わない。

詳細は `advanced-full-coverage-3layer.md` と `maintainer-guide.md` を参照する。
