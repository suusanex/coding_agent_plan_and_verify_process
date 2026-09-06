---
name: persistent-purpose-review
description: Use after implementation when the original implementation parent must run an independent purpose-aware review, fix findings itself, and ask the same reviewer session to re-review for up to three rounds. Requires the separately installed purpose-review-runner; do not use for baseline PR review planning without purpose context.
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Persistent Purpose Review

元のimplementation parentが、実装完了後のpurpose review、finding修正、同じreviewer sessionでの再reviewを同じtask内で完了する。

`purpose-review-runner`は別途OS user単位で導入されている必要がある。このSkillはRunner binaryを内包、download、installしない。

## Ownership

- production、tests、docsを変更できるのは、このSkillを開始した元のimplementation parentだけ。
- reviewerは目的達成の判断だけを担当し、repositoryを変更しない。
- reviewerはshellでGit差分や履歴を調査できる。変更禁止はshell経由にも適用する役割契約であり、技術的に変更不能であることを意味しない。
- Runnerがprovider、session handle、round、non-modifying reviewer契約、result parse、最大3roundを所有する。providerが副作用なくwrite/edit系toolを禁止できる場合は、その制約をRunnerが利用する。
- provider CLI構文、session ID、round counter、model、reasoning effortを親から指定または再実装しない。
- PR、GitHub Copilot review、別top-level task、Zed integrationは前提にしない。

## Select purpose context

Runnerを開始する前に、今回のpurpose sourceを意味的に選ぶ。

1. ユーザーが明示したsourceを最優先する。
2. task、承認済みplan、implementation handoffと、repository内のGoal Context、会話export、accepted decision documentから、今回の目的とscopeの根拠を選ぶ。
3. 元の問題・期待成果、承認されたscope・採用判断、実装方針の役割を区別する。新しいplanやhandoffであることだけで当初目的、優先順位、棄却理由を上書きしない。ユーザーが明示した目的・scopeの変更判断は反映する。
4. 複数文書が同じ目的を補完する場合はすべて選ぶ。複数であること自体をambiguityにしない。
5. 古い版と新しい版が競合するなど、現在のsourceを特定できない場合だけreviewを開始せずユーザーへ質問する。

context pathはrepository相対またはabsoluteでよい。Runner自身にsourceを探索・推測させない。

計画への適合だけを目的達成の根拠にしない。ユーザーが入力を限定していなければ、計画に残っていない背景・否定条件を補う現在のsourceも選ぶ。必要な目的情報が得られない場合は不足を明示し、推測で新しい要求を作らない。比較対象のbaseやPRが明示済みなら、その情報も選択したcontext内で識別できるようにする。PRやレビュー専用commitの作成は前提にしない。

## Verify the Runner

```powershell
purpose-review-runner version
```

stdoutの単一JSONを読み、`protocolVersion`が`2`であること、および`runnerVersion`が`0.2.3`以上であることを確認する。`runnerVersion`はmajor.minor.patchとして比較する。command未導入、非0 exit、JSON不正、`protocolVersion`非互換、`runnerVersion`欠落、`0.2.3`未満、または比較不能なら`Blocked`として停止する。別commandやprovider CLIで代替しない。`apm update`はRunner binaryを更新しないため、旧Runnerのまま続行しない。

## Start review

repository rootと選択済みcontextを明示する。`start`はprovider完了をforegroundで待たない。

```powershell
purpose-review-runner start --repository <repository-root> --context <path> [--context <path> ...]
```

返った`runId`を保持する。stdoutの公開protocol fields（`runId`、`jobStatus`、`status`、`findings`、`message`、`error`等）だけをworkflowで扱う。内部session handleやstate fileを読み書きしない。内部コマンド`work`は呼び出さない。

`jobStatus`または`status`が`RUNNING`なら、数秒間隔で同じ`runId`の`status`を繰り返す。1回のCLI invocationが失敗・結果不明でも、新規run作成や同じroundの再submitはせず、`status`だけをやり直す。

```powershell
purpose-review-runner status --run <run-id>
```

`status`はreviewを再実行しない。provider timeoutまで1 roundが約10分かかることがある。`RUNNING`が続くこと自体をrecovery理由にしない。

- `FINDINGS`: findingを実装目的へ照合し、元のparentが必要なproduction/tests/docsを修正してrepository規約のvalidationを実行する。その後、同じ`runId`を`continue`する。
- `COMPLETE`: purpose review完了として終了する。
- `HUMAN_DECISION_REQUIRED`: finding、選択が必要な理由、実施済みvalidationを報告して停止する。
- `BLOCKED`: blockerと再開条件を報告して停止する。
- `ERROR`または非0 exit: error codeと安全なmessageを報告して停止する。新session、retry、context replay、別providerへの切替を行わない。

findingは元の目的と明示的な採用判断に照合し、`requiredChange`の方式を無条件に実装しない。必要な振る舞いと制約を満たす修正を選び、追加だけでなく削除・縮小・既存経路への統合を検討する。誤り・過剰要求の根拠がある場合は、実装修正を行わず同じrunで再reviewを求めてもよい。必要な説明は既存の作業記録などに根拠と判断を簡潔に残し、過去のreviewer output全文を複製しない。未決定の目的・scopeを親の判断だけで変更する必要がある場合は、選択理由をユーザーへ報告して停止する。

## Continue after remediation

```powershell
purpose-review-runner continue --run <run-id>
```

`continue`もprovider完了を待たない。`continue`へcontext、previous output、provider設定、session IDを追加しない。同じreviewer sessionが保持する目的理解を利用する。返ったあとは再び`status --run <run-id>`でpollingする。再び`FINDINGS`なら親が修正・validationして同じcommandを使い、terminal statusまで繰り返す。

再reviewは指摘への追従確認ではなく、元の目的に対する現在の実装全体と修正差分の評価である。`message`にある比較基準・未検証事項・findingの訂正や撤回理由も扱い、撤回を実装修正済みと報告しない。前回の未コミット状態を復元できないなどの比較限界は、確認済みと置き換えず最終報告へ引き継ぐ。

Round 3でfindingが残る場合はRunnerが`HUMAN_DECISION_REQUIRED`を返す。automatic round 4、session reconstruction、transcript replay、別reviewer recoveryを行わない。

## Report

完了済み、未検証、HumanDecisionRequiredまたはBlocked、人手で必要な作業を分ける。reviewerがrepositoryを変更しないことは役割契約であり、OS-level isolationの証明とは表現しない。
