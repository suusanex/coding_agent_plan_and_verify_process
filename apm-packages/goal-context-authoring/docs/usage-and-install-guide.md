# Goal Context Authoring usage and install guide

## Prerequisites

- APM CLI
- 初期検討を行った ChatGPT 会話、または同等の authoritative decision notes
- Goal Context を保存する対象 repository への書き込み権限
- package validator を実行する場合は PowerShell 7 以降

正式 target は `codex` と `agent-skills` です。ChatGPT 会話の外部監視、会話取得、Issue 作成はこの package の責務ではありません。

## Install with APM

対象 repository の root で実行します。

```powershell
apm install suusanex/coding_agent_plan_and_verify_process/apm-packages/goal-context-authoring --target codex,agent-skills
```

APM install 後、次の bundled references が存在することを確認します。

```text
.agents/skills/goal-context-authoring/
  SKILL.md
  references/
    generation-prompt.md
    goal-context-contract.md
    goal-context-template.md
    human-review-checklist.md
```

この package は custom agent、model mapping、repository-local config を追加しないため、補助 installer はありません。

### Local development validation

未公開の local package は、package root の `apm.yml`、target 解決、Skill と bundled references の配置まで smoke test します。script は system temporary directory に隔離した repository root を作り、`apm install <absolute-package-root> --target codex,agent-skills` を実行して、配置後ファイルの SHA-256 が source と一致することを確認します。CI は APM CLI `0.26.0` を固定します。

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1
./apm-packages/goal-context-authoring/scripts/test-apm-package-install.ps1
git diff --check
```

## Generate a draft

1. 初期検討と Issue 文面の確定後、同じ ChatGPT 会話で `references/generation-prompt.md` の prompt を送ります。
2. conversation の初期から現在までが model context に含まれることを確認します。
3. 生成された Markdown を `references/goal-context-template.md` と比較します。
4. repository 固有の保存規約がなければ `docs/goal-context-<topic-summary>.md` へ保存します。
5. frontmatter は human review 前のため `status: draft`、`sensitive_data_review: pending` のままにします。

ファイル名の topic summary は、永続的な問題または Desired outcome を短く表します。

Valid:

```text
goal-context-resumable-local-batch-export.md
goal-context-multi-project-ai-development-notification-and-purpose-review.md
```

Invalid:

```text
goal-context-issue-51.md
goal-context-pr-72.md
goal-context-fix-validator.md
```

Issue、PR、単一作業 slug は related artifact として本文に記録できても、ファイル名の中心にはしません。

## Handle long or corrected conversations

会話全体を一度に処理できない場合は `generation-prompt.md` の continuation protocol を使います。

- segment を順序付きで渡す
- 各 segment から temporary coverage ledger だけを抽出する
- final segment まで Goal Context 本文を作らない
- final segment で全 ledger を reconciliation する
- 各 segment で全 contract dimension を確認し、stable Claim ID、source pointer、provenance を残す
- final reconciliation で全 claim を Included / Superseded / Duplicate / Excluded as sensitive / Retained as Unknown のいずれかへ確定する
- 欠けた segment がある場合は生成を止める

later correction は、それ以前の statement を自動で削除する理由にはなりません。現在の決定を本文へ反映しつつ、重要な supersession を `Conversation corrections and priority changes` に残します。明確な supersession がない矛盾は `[Unknown]` として保持します。

## Validate the draft

package source repository から任意の Goal Context を確認できます。

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath C:\path\to\repository\docs\goal-context-<topic-summary>.md
```

この mode は次を検査します。

- content-centered filename shape
- required frontmatter と lifecycle value
- required headings と空 section
- `[Explicit]` / `[Inferred]` / `[Unknown]` provenance vocabulary
- unresolved template placeholder
- high-confidence secret pattern

PASS は draft の構造証拠です。Issue copy ではないこと、conversation の訂正を正しく反映したこと、推論が妥当であること、機密情報が完全に除外されたことまでは証明しません。

## Perform human review

reviewer は source conversation または authoritative decision notes と `references/human-review-checklist.md` を並べて確認します。次を重点項目とします。

- Desired outcome
- Rejected alternatives と理由
- Superficially compliant but wrong
- MVP / Non-goals / Future work 境界
- 利用者の訂正と優先順位変更
- explicit / inferred / unknown の分類
- secrets、credentials、authentication material、不要な個人情報の除外

有効な lifecycle は `draft` / `pending` と `human-reviewed` / `passed` の2組だけです。修正後、Human review record を実際の reviewer、日付、確認結果、review で行った変更で更新します。その後だけ frontmatter を次へ変更します。

```yaml
status: human-reviewed
sensitive_data_review: passed
```

strict mode を実行します。

```powershell
./apm-packages/goal-context-authoring/scripts/validate-goal-context-authoring.ps1 -GoalContextPath C:\path\to\repository\docs\goal-context-<topic-summary>.md -RequireHumanReview
```

## Save and hand off

reviewed document を repository へ保存し、後続 AI には Goal Context path を直接渡します。後続 AI は元会話ではなくこの文書を purpose-review input として使用できます。

handoff では次を報告します。

- saved path
- source scope と既知の gap
- human review status
- validator command と result
- open questions / assumptions

Goal Context の作成完了を、Issue 作成、実装、PR review、目的達成の完了と表現しません。

## Example and fixture

- `examples/source-conversation-fixture.md`: 訂正、priority change、採用判断、棄却案を含む入力 fixture
- `examples/goal-context-resumable-local-batch-export.md`: fixture から得られる human-reviewed example

example は会話順にメッセージを再掲せず、problem、outcome、decisions、boundaries、evidence、negative conditions へ再構成しています。package validator はこの example が contract を満たすことと、required heading または privacy condition を壊した negative mutation を検出できることを確認します。

## Limitations

- ChatGPT の利用環境によっては長い会話の初期部分が model context に入らない場合があります。
- provenance tag は source traceability を助けますが、AI の分類が正しいことを自動保証しません。
- secret scanner は少数の high-confidence pattern だけを検出します。
- human review は省略できません。
