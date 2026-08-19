# Persistent Purpose Reviewer negative-control v2 実験結果

実施日時: 2026-08-19T09:11:01.6593623+00:00
CLI version: GitHub Copilot CLI 1.0.80.
モデル: gpt-5.6-luna
実験 cwd: D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer
branch: trial-subagent-review

## 判定

- Semantic outcome: **No (fresh control guessed the exact violation)**
- Persistent R1 の PPR-001 検出: **True**
- Persistent R2 の unhinted fixed-decision violation 検出: **True**
- Fresh R2 の exact violation: **True**
- Fresh R2 の materially weaker (unknown/insufficient): **False**
- Persistent R3 の PPR-001 resolved: **True**
- Fixture は変更していない: **True**

## Architecture feasibility

- Persistent R1/R2/R3 の session hash 一致: **True**
- Fresh R2 の session hash が別: **True**
- Persistent R1 の process exit 前に R2 を開始: **True**
- Persistent R2/Fresh R2 の prompt+candidate composition hash 一致: **True**
- Persistent R2/Fresh R2 の source file bytes 一致: **True**
- Architecture feasibility: **feasible**

## Security qualification

- Security qualification: **not-qualified**
- 判定根拠は、Persistent R2 が Round 1 state を保持して PPR-001 を具体的に検出し、Fresh R2 が同一 input bytes で current-input-only の限界を示し、Persistent R3 が resolved になったかである。
- Fresh R2 が正解を推測した場合は fixture を変更せず、security qualification を与えない。

## 入力境界と保全

- R1 は prompt/context/candidate、Persistent R2/R3 は各 prompt/candidate のみ、Fresh R2 は Persistent R2 と同一 bytes の prompt/candidate のみを送信した。
- R2/R3/Fresh R2 に Round 1 context、previous response 全文、decision/mapping/finding の再送はない。
- Session ID、secret、environment value の raw 値は保存していない。保存した session は SHA-256 短縮 hash のみである。
- production-unchanged.json の pre/post Git status と outside-experiment status により、production の非変更を観測した: **True**
- final-diff-check.txt に最終 diff check を保存した。

詳細な file bytes/hash、no-replay flags、composition hash、command shape、permission、raw response SHA-256、semantic form、round label verification は各 run directory と run-metadata.json に保存した。