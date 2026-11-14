---
name: solution-shape-authoring
description: Use when a user or agent wants to create or refine a lightweight Markdown Solution Shape from Goal Context and Decision Context, showing composition and responsibility placement, capability placement, and representative execution paths before detailed planning or implementation.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Solution Shape Authoring

Goal Context と Decision Context（または利用者の課題・期待成果・確定済み方針）から、詳細な実装 Plan へ進む前に「どの部分がどの機能を、どのように実現し、通常の処理で何が起きるか」を少量の情報で見渡すための軽量な Markdown スケッチ「Solution Shape」を作成する。

この Skill は単独で利用でき、コード実装や `$persistent-purpose-review` の実行を必須にしない。Solution Shape を作成しただけで `approvedDesign`（承認済み設計）へ昇格することもない。

## 中核の 3 要素

Markdown 上で、次の 3 つの意味が短い記述で読み取れるようにする。

1. **構成・責務配置**
   - 主要な構成要素、それぞれが担う役割、要素間の主な関係を示す。
   - **論理的な役割（責務）と実際の実現主体（プロセス、CLI、ホスト、外部 AI、保存先、外部サービス等）を明確に区別**し、論理部品の列挙によって各部品を独立サービスや別 LLM 呼び出しと誤解させない。
2. **機能配置**
   - 必要な機能ごとに、担当、実現方式・振る舞い、実際に課される重要な制約を示す。
   - 複数用途の共通化が設計対象の場合は、共通部分と用途固有部分の境界を示し、特定用途に固有の記憶・状態・連携・許可条件を別用途へ不必要に強制していないか確認できる粒度にする。
3. **代表的な実行経路**
   - 主要な正常系（必要に応じて代表的な分岐 1〜2 本）で、誰が何をどの順序で処理し、何を読み取り・生成・更新するかを示す。
   - 余計な往復、追加の推論、データの全件再生成・再処理、重複した照合・バックアップ・復旧・状態管理が混入していないか読み取れる粒度にする。

## 代案と記述粒度

- **代案の比較**: 構成・機能配置・実行経路に**重要な違いがあるときだけ**、差分だけを短く比較する。常時複数案や詳細な比較表を作らない。
- **書かないもの**: クラス・メソッド構成、網羅的な例外処理、詳細スキーマ、コード品質・保守性の審査、全判断の長い正当化説明、目的や実現方式の比較に直接寄与しない定型注意書きや「〜とは扱わない」といった防御的説明。
- **消さないもの**: 元資料で明示された必要な業務機能、安全性・保全の保証、確定済み制約は簡素化のために省略・弱体化しない。元資料にない決定を推測で確定せず、残る重要な未決事項だけを短く示す。
- **機密情報の除外**: 秘密情報、認証情報、不要な個人情報は含めない。

## 相互運用と Purpose Review への任意連携

- 特定のファイル名、見出し名、表の行数、ページ数、UCM / C4 / DFD 等の専用ツール・図法を下流の必須条件にしない。上記 3 要素の意味が読めれば、形式は自由とする。
- 明示的に `$persistent-purpose-review` を起動する上位エージェントまたは利用者が、作成済みの Solution Shape を任意に渡す場合は、既存入力契約（`schemaVersion: 1`）を使う。Solution Shape 自体が提案設計なら `proposal.body`、別の提案設計を理解する補助材料なら `evidence` に含める。
- Solution Shape を作っていない通常の `$persistent-purpose-review` も従来どおり成立し、欠如自体を不適合にしない。

## 参照資料

通常はこの `SKILL.md` だけで作成する。表現形式や粒度の判断に迷う場合のみ、`references/solution-shape-examples.md` の該当する例を参照する。

- 例 1: 複数の実現主体・共有部分を持つ共通 Bot 基盤の仮案の例
- 例 2: 少量の入力を 1 回処理して終わる小さなツールの例
