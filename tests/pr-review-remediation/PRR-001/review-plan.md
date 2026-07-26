# PR Review Remediation Plan

## Phase 1 Verdict

- Verdict: READY_FOR_ADAPTIVE_IMPLEMENTATION
- Production code changed: No
- Process status: Review planning complete

## PR Identity

- Repository: example/repo
- PR: #123
- Base branch / OID: main / base-001
- Head branch / OID: feature/review-fixture / head-001
- Context directory: `.review/pr-123/`

## Input Artifacts

- `AGENTS.md`
- `README.md`
- `.review/pr-123/review-context.json`
- `.review/pr-123/pr-diff.patch`
- `.review/pr-123/local-review-findings.md`

## Review Input Status

- Local Codex review: Collected (`LR-001`)
- Copilot wait status: completed
- Copilot observed review state: reviewAndInline
- Copilot review: Collected (`GitHub Review #100`)
- PR comments: Collected (`GitHub PR Comment #501`)
- Inline comments: Collected (`GitHub Inline Comment #1001`)
- Checks: Collected (`fixture-check`: COMPLETED / SUCCESS)
- Missing input decision: なし。Copilot review と inline comment の取得完了を確認した。

## Finding Decision Ledger

| Source ID | Source | Location | Summary | Decision | Reason | Duplicate of | Conflicts with | Scope / Acceptance mapping |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| LR-001 | Local Codex | `src/Fixture.cs:5` | `Compute()` の戻り値を `true` に変えた変更に対応する回帰テストがない。 | Apply | 変更後の振る舞いを固定するfocused regression testが必要。 | N/A | N/A | Scope 1、Acceptance 1–3 |
| GH-REVIEW-100 | GitHub Copilot review | PR review | changed behavior のregression testを追加する。 | Apply | `LR-001` と同じ問題を独立したreview sourceが確認している。 | LR-001 | N/A | Scope 1、Acceptance 1–3 |
| GH-INLINE-1001 | GitHub Copilot inline comment | `src/Fixture.cs:5` | focused regression coverageを追加する。 | Apply | `LR-001` および `GH-REVIEW-100` と同一の回帰テスト不足を指す。 | LR-001 | N/A | Scope 1、Acceptance 1–3 |
| GH-PR-COMMENT-501 | GitHub PR comment | PR conversation | public contractを維持する。 | Apply | 回帰テスト追加時にもpublic API shapeを変更しない制約として採用する。 | N/A | N/A | Constraints 2、Acceptance 2 |
| CHECK-fixture-check | GitHub check | `fixture-check` | COMPLETED / SUCCESS。 | Hold | 現時点で失敗や修正要求はない。実装後のvalidation基準として保持する。 | N/A | N/A | Validation 3 |

## Duplicate / Conflict Mapping

- Canonical remediation item: `CR-001`
  - Source IDs: `LR-001`, `GH-REVIEW-100`, `GH-INLINE-1001`
  - 統合判断: `Apply`
  - 内容: `ValueProvider.Compute()` が `true` を返すことを検証するfocused regression testを追加する。
- `GH-PR-COMMENT-501` は `CR-001` の実装制約を補強する独立コメントであり、重複ではない。
- `CHECK-fixture-check` は修正指摘ではないためremediation itemに統合しない。
- 競合: なし。

## Ordered Remediation Plan

| Step | Finding IDs | Change | Expected files / symbols | Acceptance | Validation |
| --- | --- | --- | --- | --- | --- |
| 1 | LR-001, GH-REVIEW-100, GH-INLINE-1001 | 既存のtest conventionに従い、`ValueProvider.Compute()` が `true` を返すfocused regression testを追加する。 | 既存のtest project内の該当test file、`ValueProvider.Compute()` | 変更後の戻り値を明示的に検証するtestが存在し、成功する。 | focused regression test |
| 2 | GH-PR-COMMENT-501 | production APIを変更せず、test追加だけで回帰coverageを補う。 | `ValueProvider` public API | `ValueProvider.Compute()` のpublic API shapeを維持する。 | build |
| 3 | CHECK-fixture-check | 実装後のvalidationを実行し、既存成功checkを損なわないことを確認する。 | repository validation | focused testとrepository buildが成功する。 | focused regression test、repository build、適用可能なら `fixture-check` |

## Scope

- `ValueProvider.Compute()` が `true` を返すことを検証するfocused regression testの追加。
- 追加したtestの実行。
- repository buildの実行。

## Non-goals

- `src/Fixture.cs` のproduction behavior変更。
- `ValueProvider` のpublic API shape変更。
- 無関係なrefactor、仕様追加、PR外差分の変更。
- Adaptive Implementationのrouter、agents、verdict、handoff、validation contractの変更または複製。

## Acceptance

1. `ValueProvider.Compute()` の期待値 `true` を検証するfocused regression testが追加される。
2. public API shapeが維持される。
3. focused regression testが成功する。
4. repository buildが成功する。
5. 適用可能な環境では `fixture-check` が成功する。

## Constraints

1. 確認済みremote patch (`.review/pr-123/pr-diff.patch`) に関係する変更だけを対象とする。
2. `GH-PR-COMMENT-501` に従いpublic contractを維持する。
3. test framework、test project、実行コマンドは実装時にrepositoryの既存conventionから選択する。
4. production code、review artifact、GitHub state、commit、branchはこのPhase 1で変更しない。

## Validation

1. 追加した `ValueProvider.Compute()` のfocused regression testを実行する。
2. repository buildを実行する。
3. CIを実行可能な環境では `fixture-check` の成功を確認する。

## Implementation Intent

```yaml
implementation_intent:
  goal: ValueProvider.Compute() の false から true への振る舞い変更をfocused regression testで固定し、将来の意図しない契約後退を検出可能にする。
  scope:
    - 既存のtest conventionに従い、ValueProvider.Compute() が true を返すことを検証するfocused regression testを追加する。
    - 追加したfocused regression testとrepository buildを実行する。
  non_goals:
    - src/Fixture.cs のproduction behavior変更
    - ValueProvider のpublic API shape変更
    - 無関係なrefactor、仕様追加、PR外差分
    - Adaptive Implementationのrouter、agents、verdict、handoff、validation contractの変更または複製
  acceptance:
    - ValueProvider.Compute() の期待値 true を明示的に検証するfocused regression testが存在し、成功する。
    - ValueProvider のpublic API shapeが維持される。
    - repository buildが成功する。
    - 適用可能な環境では fixture-check が成功する。
  constraints:
    - confirmed remote patchに関係するtest coverageだけを追加する。
    - GitHub PR Comment #501 に従いpublic contractを維持する。
    - test projectと実行コマンドはrepositoryの既存conventionを使用する。
  validation:
    - focused regression test
    - repository build
    - 適用可能な環境でfixture-check
  plan_reference: example/repo PR #123, main/base-001 to feature/review-fixture/head-001, review-plan.md
```

## Uncollected / Unverified

- 未取得のCopilot review、inline comment、PR comment、checkはない。
- Phase 1ではbuildおよびtestを実行していない。これらはAdaptive Implementationで実施するvalidationである。
- 実際のtest project、test file、test command、build commandは提供artifactに含まれないため、実装時に既存repository conventionから確定する。

## Human-required Work

- 人手での作業が必要: 次のpromptを別親ターンで開始し、Adaptive Implementationを実行する。

## Separate Parent Turn Handoff

```text
$adaptive-implementation-execution を使って review-plan.md を実装してください。
review-plan.md の implementation_intent を source of truth とし、既存 Adaptive Implementation の router、agents、verdict、handoff、validation contract を変更または複製しないでください。
```

Phase 1の停止はレビュー反映プロセス全体の完了ではありません。Adaptive Implementationはこの親ターンから自動起動しません。