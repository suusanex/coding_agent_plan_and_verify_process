# User Guide

## いちばん短い始め方

Codex には普通に依頼すればよい。

```text
この issue を進めてください。
このバグを修正してください。
この機能を実装してください。
この PR の残件を片付けて。
続きやって。
```

process 名、agent 名、model 名、full-coverage かどうかは利用者が選ばない。
Codex 側が repo rules と既存 artifact を読み、次に安全な工程を決める。

## Codex が内部で行うこと

1. 依頼内容と対象 repo の指示を読む。
2. 必要なら `plans/<slug>/codex-first-state.md` を作る。委譲証跡や close audit が必要な場合は `plans/<slug>/codex-first-audit.md` も作る。
3. いきなり実装せず、Plan / risk / scan / contract のどこから始めるか判断する。
4. Risk gate を通る場合は `plans/<slug>-change-risk-triage.md` を残す。
5. 実装前に handoff review で実装許可と coverage ledger を確認する。
6. READY になった範囲だけ、内部的に `standard-implementer` へ委譲して実装する。
7. 実装後に `standard-verifier` などで test / verification / close 可否を確認する。
8. 止まる必要がある場合だけ、必要最小限の質問を返す。

Codex は内部で Routing Plan と audit を残す。利用者が agent や model を選ぶ必要はないが、結果にはどの工程をどの agent / tier へ委譲したかの summary が含まれる。
audit には、委譲実行の証跡、親が直接作業した場合の理由、実行設定と観測 model の区別も残る。利用者がこれを選ぶ必要はない。

## VS Code Codex 拡張でのローカル導入

`codex-first-start.ps1` は一時 launcher なので、VS Code 拡張のようにリポジトリごとに標準運用を残したい場合は、次のインストーラを先に実行する。

```powershell
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\install-codex-first-local.cs -- <target-repo-path> --dry-run
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\install-codex-first-local.cs -- <target-repo-path>
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\install-codex-first-local.cs -- <target-repo-path> --check-only
```

このインストーラは次を対象リポジトリへ追加します。

- `AGENTS.md` の Codex-first セクション（既存を上書きしない既定）
- `.codex/config.toml`（足りないキーだけ補完）
- `.codex/agents/*.toml`（同名既存ファイルは競合時に停止）
- `.agents/skills/codex-first-cost-router/SKILL.md`
- `templates/*.md`

標準ルートに必要な skill / agent / template はこのインストーラだけで入るため、別途 APM 実行を前提にしない。
`--dry-run` と `--check-only` はファイルやディレクトリを作成しない。
必要なら `--force` を使って既存の `AGENTS.md` section / skill / agent / template を上書きし、VS Code 再読込して反映確認する。

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
- READY implementation / verification の委譲証跡が audit に残っておらず、`DelegationCompliance` が PASS になっていない。
- 親が直接実装した作業を、agent へ委譲してコスト削減した成功として数えている。

## 熟練 operator 向け

full-coverage 3層運用や既存 APM package の直接指定は advanced route で扱う。
通常の利用者向け入口では使わない。

詳細は `advanced-full-coverage-3layer.md` と `maintainer-guide.md` を参照する。

## MVP評価用サンプル

`docs/examples/routing-mvp-sample.md` に、軽量な issue 入力と期待される Routing Plan の単発例を置いている。
Codex-first を導入した直後は、このサンプルで state artifact、audit artifact、READY 前停止、Edit Permission、Agent Usage Ledger の形を確認する。

より広い MVP 検証には `docs/examples/routing-mvp-validation.md` を使う。
この validation suite は、軽量修正、通常実装、full-coverage 候補、中断再開、Hook / Plugin 変更を並べて、Task Weight、Selected Process、Model Tier Recommendation、Agent / Subagent Plan、DelegationRequired、Stop / Ready Gate の分類を確認するための maintainer 向け artifact である。
