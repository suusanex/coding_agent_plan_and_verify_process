# Grok Persistent Purpose Reviewer 実験結果

## 実行概要

- provider: Grok Build CLI
- CLI version evidence: cli-static-help-version.json
- model: grok-4.6
- branch: trial-subagent-review
- experiment cwd: experiments/persistent-purpose-reviewer
- persistent session hash: a5fff86e2afd3522532b7812e417134e5b94f59e716d3d60619dace248ab8468（R1/R2/R3 は同一）
- fresh session hash: 7534896590d7e1a9eb70b5002bf35bbd8668f9ace46d388e352f2d1558713699（persistent と異なる）
- Persistent R2 / Fresh R2 payload SHA-256: 7456fcac41dda767d74e3618eaafde38164fe683148e30992481dfe9084a6c86（完全一致）

## 判定

- Semantic persistence qualification: **No**
- Architecture feasibility（同一 session resume の実行可能性）: **Feasible**
- Round 1 の PPR-001 検出: **True**
- Persistent Round 2 の unhinted exact violation 検出: **False**
- Fresh Round 2 の exact violation 検出: **False**
- Persistent Round 3 の解消: **True**
- Fresh control は Persistent R2 と同一 payload bytes: **True**
- Round 2 payload に quick-check を含む: **False**
- Round 2 payload に棄却理由を含む: **False**

## 送信境界

- R1 は Round 1 prompt/context/candidate のみを送信。
- Persistent R2/R3 は各 prompt/candidate のみを送信し、full context、previous response、semantic decision/mapping/finding は再送していない。
- Fresh R2 は新規 session で Persistent R2 と同じ prompt/candidate composition bytes のみを送信。
- Fresh R2 の初期 bootstrap と Persistent R2 の --resume の差は fresh-control/round-2/input-payload-manifest.json と各 command shape に記録。
- session_id、secret、環境値は evidence に保存していない。保存した session hash は UUID の SHA-256。

## 制限と失敗

- CLI の permission/sandbox/options は evidence の command shape に記録。
- OS/network audit の不在は architecture failure として扱っていない。
- 実行失敗 run: なし
- production tree changes: なし（baseline との差分で experiment root 外変更なし）。
- Persistent R2 は active/fail/sufficient だったが、出力根拠に focus-mode と lantern-pulse はあり、期待 wire token quick-check／wire contract rationale がなく、厳格な exact violation 条件を満たさない。
