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
Codex は内部で `documentation_level: lite` または `documentation_level: standard` も記録するが、これも利用者が選ぶものではない。
`strict` は documentation level ではなく、full-coverage は advanced route である。

## Codex が内部で行うこと

1. 依頼内容と対象 repo の指示を読む。
2. 必要なら `plans/<slug>/codex-first-state.md` を作る。委譲証跡や close audit が必要な場合は `plans/<slug>/codex-first-audit.md` も作る。
3. いきなり実装せず、Plan / risk / scan / contract のどこから始めるか判断する。
4. Risk gate を通る場合は `plans/<slug>-change-risk-triage.md` を残す。
5. 実装前に handoff review で実装許可と coverage ledger を確認する。
6. 利用者が Design Pair を明示選択した場合だけ、予定変更面のTarget Mapを提示し、`AWAITING_USER_INPUT / target-selection`で必ず一度停止する。初期案へのtrade-off提示後に最終dispositionがなければ`disposition-confirmation`で再停止し、validなpost-map user evidenceを含むtracked handoffを作る。通常はこの工程を挟まない。
7. READY になった非自明な範囲を `high-implementation-starter` へ委譲して実装を開始する。
8. 構造判断が解消して complete な handoff ができた場合だけ、`standard-implementation-completer` へ残作業を直列委譲する。再び構造判断が必要なら HIGH_MODEL に戻す。
9. 実装後に `standard-verifier` などで test / verification / close 可否を確認する。
10. 止まる必要がある場合だけ、必要最小限の質問を返す。

Codex は内部で Routing Plan と audit を残す。利用者が agent や model を選ぶ必要はないが、結果にはどの工程をどの agent / tier へ委譲したかの summary が含まれる。
audit には、委譲実行の証跡、親が直接作業した場合の理由、実行設定と観測 model の区別も残る。利用者がこれを選ぶ必要はない。

## VS Code Codex 拡張でのローカル導入

`codex-first-start.ps1` は一時 launcher なので、VS Code 拡張のようにリポジトリごとに標準運用を残したい場合は、次のインストーラを先に実行する。

```powershell
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- <target-repo-path> --dry-run
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- <target-repo-path>
dotnet run --file .\apm-packages\codex-first-ai-development-process\scripts\apply-codex-first-local.cs -- <target-repo-path> --check
```

このインストーラは次を対象リポジトリへ追加します。

- `AGENTS.md` の Codex-first セクション（既存を上書きしない既定）
- `.codex/config.toml`（足りないキーだけ補完）
- `.agents/skills/adaptive-implementation-execution/`（complete handoff reference を含む）
- `.agents/skills/design-pair-implementation-execution/`（explicit selection 時だけ使う Target Map / tracked handoff reference を含む）
- `.github/agents/high-implementation-starter.agent.md` と `.github/agents/standard-implementation-completer.agent.md`
- `.codex/agents/*.toml`（同名既存ファイルは競合時に停止）
- `.agents/skills/codex-first-cost-router/SKILL.md`
- `templates/*.md`

標準ルートに必要な skill / agent / template はこのインストーラだけで入るため、別途 APM 実行を前提にしない。
Design Pair skill も配置されますが、自動選択、推奨、提案はされません。通常経路は Adaptive Implementation です。Design Pairを選んだ場合、最初の「実装してください」だけではAdaptiveへ進まず、Target Map提示後の利用者応答を待ちます。
`--dry-run` と `--check` はファイルやディレクトリを作成しない。`--check-only` は互換 alias である。
必要なら `--force` を使って既存の `AGENTS.md` section / skill / agent / template を上書きし、VS Code 再読込して反映確認する。

## 止まったときの見方

よくある停止理由は次の通り。

- `NeedsHumanDecision`: 仕様や優先順位を人が決める必要がある。
- `AWAITING_USER_INPUT / target-selection`: Design PairのTarget Mapを確認し、議論するTarget、初期案、未選択TargetをAdaptiveへ委ねるかを回答する必要がある。
- `AWAITING_USER_INPUT / disposition-confirmation`: AIのtrade-offを確認し、selected Targetの最終dispositionを明示する必要がある。
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
- implementation が HIGH_MODEL から始まっていない、STANDARD_MODEL が valid handoff なしで編集した、または必要な HIGH re-entry が未実施。
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

Lite / standard の検証には `docs/examples/lite-standard-validation.md` を使う。
この validation suite は、`documentation_level`、Lite artifact、Inline Ready Gate、canonical coverage ledger、direct FixNow、unified implementation contract、artifact count / sections read、negative scan を確認するための maintainer 向け artifact である。
