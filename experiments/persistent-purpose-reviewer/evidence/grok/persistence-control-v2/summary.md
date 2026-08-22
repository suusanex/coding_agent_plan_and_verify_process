# Grok Build CLI Persistent Purpose Reviewer v2 実験結果

実行日: 2026-08-19 18:17:59 +09:00
対象: fixtures\persistence-control-v2\、prompts\persistence-control-v2\
CLI: Grok Build CLI（version evidence: setup\static-help-version-model.json、model: grok-4.6 default）
cwd: D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer

## 判定

- 総合: **Yes**
- Persistent R2 の unhinted 固定契約違反検出 (PPR-001, active/fail/sufficient, quick-check と focus-mode の具体的 evidence): **True**
- Fresh R2 の negative-control（current input だけでは特定不能として unknown/insufficient）: **True**
- Persistent R3 の解消判定 (resolved/pass/sufficient): **True**
- Persistent R2/Fresh R2 の exact composition equality: **True**
- Persistent session 同一 hash / Fresh session 別 hash: **True / True**

Fresh R2 が exact rule/rationale を特定してしまう場合は negative-control の期待に反するため、fixture は変更せず総合を Partial/No とする。今回の fresh 判定は materially weaker: **True**、exact violation: **False**。

## Architecture feasibility

Persistent R1 は新規 session、Persistent R2/R3 は同じ特定 session ID の --resume、Fresh R2 は別の新規 session で実行した。R2 の外部入力は persistent/fresh で同一 payload hash、R2/R3 に R1 context・previous response・decision/mapping/finding の再送はない。architecture feasibility: **PASS**。

## Security qualification

--permission-mode plan、--sandbox read-only、--tools read,view,grep、write/shell/task/edit 系 disallow、--disable-web-search、--no-memory、--no-subagents、実験 cwd を指定した。外部へ渡したのは安全な架空 fixture の payload のみで、raw session ID・secret・environment value は保存していない。Git の実験外 status は pre/post で同一、production non-mutation observed: **True**、final git diff --check: **True**。

CLI 内部の relay、global rule の統合、sandbox backend の低レベル enforcement はこの実験の evidence だけでは独立監査していないため、security qualification は **CONDITIONAL**（architecture feasibility とは別評価）とする。

## Evidence

- run-metadata.json
- setup\static-help-version-model.json
- runs\*\input-manifest.json（bytes/hash/no-replay flags）
- runs\*\raw-response.txt と semantic-review.json（保存 actual-byte SHA-256、semantic form、round label）
- session-and-composition-comparison.json
- run-start-pre-git-snapshot.json、final-post-git-snapshot.json、final-diff-check.json