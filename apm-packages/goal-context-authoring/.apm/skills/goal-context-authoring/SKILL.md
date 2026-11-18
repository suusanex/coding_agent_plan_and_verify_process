---
name: goal-context-authoring
description: Use when natural-language source material should be distilled into a portable Goal Context and Decision Context for later implementation or purpose review.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Goal Context Authoring

This skill helps create or refine a self-contained natural-language document that separates Goal Context from Decision Context. It is an optional authoring route. A context used elsewhere may have been written by a person, another agent, another repository, or an unknown process.

## Required references

Read the bundled references before authoring:

- `references/generation-prompt.md`: copyable synthesis prompt
- `references/goal-context-contract.md`: free-form interoperability contract
- `references/goal-context-template.md`: optional example, never a required schema
- `references/human-review-checklist.md`: optional quality review

## Interoperability boundary

Downstream consumers must not turn authoring conventions into a required filename, extension, frontmatter, headings, tables, tags, lifecycle state, approval record, or creation source. The authoring conventions in this package are suggestions only.

## Workflow

改修では `references/generation-prompt.md` の「改修時の目的継承と完了条件」を実施する。今回の変更が影響する既存目的を根拠と権限付きで継承し、未確認を維持条件なしへ変換しない。同じ実装PRでの継続文書更新要否と必要な更新をIssueの完了条件へ含める。これは作成者の意味的確認であり、下流の自由形式受理やhuman reviewの任意性を変更しない。

1. 利用できる原資料の問題提起と明示的な訂正から、誰のどの活動に何の支障があり、解決後に何が変わるのかを先に取り出す。機能や方式を目的に読み替えない。読めなかった資料を根拠にしない。
2. 目的案を原資料と照合する。対象や利用者の変化を取り違えていないか、機能がそろっても困りごとが残る例を未達と判定できるかを確認する。達成判定の異なる解釈が残る場合だけ、問題・望む状態・未解決の例を短く示し、全文生成の前にユーザーの応答を待つ。明確な目的の再承認は求めない。
3. 照合した目的（訂正があれば訂正後の意味）を保って Goal Context を書く。代表場面で利用者が得る結果と、判定に欠かせない条件を残す。Decision Context には明示的に確定した範囲・能力・方式だけを置く。提案や沈黙を決定にせず、経緯やロードマップを引き継ぎ目的で加えない。目的と決定が両立しなければ黙って一方を弱めず判断を求める。
4. 全文でも原問題を判定できることを確認し、秘密・認証情報・不要な個人情報を除く。完成文の人手レビューは任意。依頼されたら `references/human-review-checklist.md` を使い、実施していない確認を記録しない。

This skill intentionally does not provide a machine validator for semantic adequacy or a prompt regression test. Judge meaning from the source and the generated text itself.

## Boundaries

This skill must not:

- turn optional examples into a required context schema;
- reject an existing context because it differs from this package's preferred organization;
- assume the context originated in a particular prompt or conversation;
- convert an inference into a user decision;
- claim human review without explicit confirmation;
- claim that authoring completes implementation, Issue creation, or purpose review.

## Output verdicts

- `GOAL_CONTEXT_CREATED`: self-contained context was saved
- `SOURCE_MATERIAL_REQUIRED`: the requested authoring task cannot identify the needed purpose or decisions from available material
- `HUMAN_DECISION_REQUIRED`: 中心目的の解釈が分かれるか、未解消の矛盾があり、全文を書く前にユーザーの判断が必要
- `BLOCKED`: a tool, permission, or environment failure prevents completion
