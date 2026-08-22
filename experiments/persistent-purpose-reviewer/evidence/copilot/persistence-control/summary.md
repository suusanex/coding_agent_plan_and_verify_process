# Persistent Purpose Reviewer persistence-control 実験結果

実施日時: 2026-08-19T09:03:08.9405190+00:00
CLI: GitHub Copilot CLI 1.0.80.
モデル: gpt-5.6-luna
実験 cwd: D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer
branch: trial-subagent-review

## 結果

- Semantic persistence 判定: **No**
- Round 1 の基準 finding (PPR-001) 検出: **True**
- Persistent Round 2 の exact unhinted violation 検出: **False**
- Fresh Round 2 の exact violation 推測: **False**
- Fresh Round 2 の unknown/insufficient: **True**
- Persistent Round 3 の解消: **False**
- Architecture feasibility (session resume/payload control): **feasible**

Fresh control が正解を推測した場合は fixture を再調整せず、negative-control の security qualification を与えない方針である。本実行では freshR2Exact=False を記録した。

## 入力境界

- Persistent R1 は Round 1 prompt、Round 1 context、Round 1 candidate のみを送信した。
- Persistent R2/R3 は各 round の prompt と candidate のみを送信した。
- Fresh R2 は Persistent R2 と同一の prompt+candidate payload bytes を送信した。
- Full Round 1 context、previous response、semantic decision/mapping/finding の再送フラグは全 R2/R3/Fresh R2 で false。
- CLI が自動付与する current-datetime/system wrapper は run ごとに変わり得るため、payload equality は supplied prompt+fixture bytes の hash で判定し、その wrapper 差を別記した。

## 制限と解釈

- --resume=<id> による persistent session は、実 ID を保存せず SHA-256 hash のみ保存した。
- Fresh control は別 session hash である。
- Copilot CLI 1.0.80 は grep を tool name として認識しなかったため、実際に公開した read tool は view のみである。この provider capability limitation は architecture feasibility と security qualification を分けて記録し、OS/network audit の不在を architecture failure とは扱わない。
- CLI JSON envelope（session ID、request ID、環境値を含み得るもの）は evidence に保存せず、assistant-message-content のみを raw/sanitized output として保存した。

## Git 保全

- production unchanged: **True**
- git diff --check: **True**
- pre/post status と allowed write scope: production-unchanged.json

詳細な input hash、bytes、command shape、permission、raw bytes SHA-256、pre/post Git status は各 run directory の input-payload-manifest.json と run-metadata.json に保存した。