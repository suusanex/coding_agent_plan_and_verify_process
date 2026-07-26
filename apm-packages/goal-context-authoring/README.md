# Goal Context Authoring

ChatGPT 等で完了した初期検討を、元会話へアクセスできない後続 AI が目的達成レビューに利用できる `goal-context-*.md` へ変換する APM package です。

Issue の長文化や会話の時系列要約ではなく、Original problem、Desired outcome、具体的な利用状況、MVP / Non-goals / Future work、採用判断、棄却案、制約、成功シナリオ、acceptance evidence、形式上は成立しても目的上失敗する条件を自己完結して残します。

## Package contents

| Content | Path |
| --- | --- |
| Authoring skill | `.apm/skills/goal-context-authoring/SKILL.md` |
| Copyable ChatGPT prompt | skill の `references/generation-prompt.md` |
| Normative document contract | skill の `references/goal-context-contract.md` |
| Goal Context template | skill の `references/goal-context-template.md` |
| Human review checklist | skill の `references/human-review-checklist.md` |
| Usage and install guide | `docs/usage-and-install-guide.md` |
| Source conversation fixture | `docs/examples/source-conversation-fixture.md` |
| Expected reviewed example | `docs/examples/goal-context-resumable-local-batch-export.md` |
| Reusable validator | `scripts/validate-goal-context-authoring.ps1` |
| Package-root install smoke test | `scripts/test-apm-package-install.ps1` |

Prompt、contract、template、checklist は bundled Skill の `references/` として配布します。standalone Markdown file を manifest dependency にしないため、APM の標準導入経路で一式が対象 repository の `.agents/skills/goal-context-authoring/` に配置されます。

## Install

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target codex,agent-skills
```

追加 installer は不要です。導入後に次を確認します。

- `.agents/skills/goal-context-authoring/SKILL.md`
- `.agents/skills/goal-context-authoring/references/generation-prompt.md`
- `.agents/skills/goal-context-authoring/references/goal-context-contract.md`
- `.agents/skills/goal-context-authoring/references/goal-context-template.md`
- `.agents/skills/goal-context-authoring/references/human-review-checklist.md`

## Use

1. 初期検討と Issue 文面を確定する。
2. `generation-prompt.md` を元の ChatGPT 会話へ渡す。
3. 出力を `goal-context-<topic-summary>.md` として draft 保存する。
4. validator を実行する。
5. 人間が checklist に従い、特に Desired outcome、棄却案、否定条件、MVP 境界、訂正・優先順位変更、provenance、機密情報を確認する。
6. 確認後だけ `status: human-reviewed` と `sensitive_data_review: passed` に変更し、strict validation を実行する。

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath ./docs/goal-context-<topic-summary>.md
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath ./docs/goal-context-<topic-summary>.md -RequireHumanReview
```

package source 自体の fixture と契約を検証する場合は引数なしで実行します。

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1
./apm-packages/goal-context-authoring/scripts/test-apm-package-install.ps1
```

install smoke test は system temporary directory で package root を `codex,agent-skills` target へ導入し、Skill と4 bundled references の SHA-256 一致を確認します。CI は APM CLI `0.26.0` を固定します。

構造 validator は semantic fidelity、長大な会話の完全な coverage、推論の正しさ、privacy safety を証明しません。人間による最終確認は必須です。

詳細は [usage and install guide](docs/usage-and-install-guide.md) を参照してください。
