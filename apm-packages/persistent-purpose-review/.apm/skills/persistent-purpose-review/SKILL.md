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
- Runnerがprovider、session handle、round、non-modifying reviewer契約、result parse、最大3roundを所有する。providerが副作用なくwrite/edit系toolを禁止できる場合は、その制約をRunnerが利用する。
- provider CLI構文、session ID、round counter、model、reasoning effortを親から指定または再実装しない。
- PR、GitHub Copilot review、別top-level task、Zed integrationは前提にしない。

## Select purpose context

Runnerを開始する前に、今回のpurpose sourceを意味的に選ぶ。

1. ユーザーが明示したsourceを最優先する。
2. task、承認済みplan、implementation handoffから現在のsourceが明確なら選ぶ。
3. repository内のGoal Context、会話export、accepted decision documentから現在のsourceが明確なら選ぶ。
4. 複数文書が同じ目的を補完する場合はすべて選ぶ。複数であること自体をambiguityにしない。
5. 古い版と新しい版が競合するなど、現在のsourceを特定できない場合だけreviewを開始せずユーザーへ質問する。

context pathはrepository相対またはabsoluteでよい。Runner自身にsourceを探索・推測させない。

## Verify the Runner

```powershell
purpose-review-runner version
```

stdoutの単一JSONを読み、`protocolVersion`が`1`であること、および`runnerVersion`が`0.1.1`以上であることを確認する。`runnerVersion`はmajor.minor.patchとして比較する。command未導入、非0 exit、JSON不正、`protocolVersion`非互換、`runnerVersion`欠落、`0.1.0`以下、または比較不能なら`Blocked`として停止する。別commandやprovider CLIで代替しない。`apm update`はRunner binaryを更新しないため、旧Runnerのまま続行しない。

## Start review

repository rootと選択済みcontextを明示する。

```powershell
purpose-review-runner start --repository <repository-root> --context <path> [--context <path> ...]
```

stdoutの公開protocol fields（`runId`、`status`、`findings`、`message`、`error`等）だけをworkflowで扱う。内部session handleやstate fileを読み書きしない。

- `FINDINGS`: findingを実装目的へ照合し、元のparentが必要なproduction/tests/docsを修正してrepository規約のvalidationを実行する。その後、同じ`runId`を`continue`する。
- `COMPLETE`: purpose review完了として終了する。
- `HUMAN_DECISION_REQUIRED`: finding、選択が必要な理由、実施済みvalidationを報告して停止する。
- `BLOCKED`: blockerと再開条件を報告して停止する。
- `ERROR`または非0 exit: error codeと安全なmessageを報告して停止する。新session、retry、context replay、別providerへの切替を行わない。

## Continue after remediation

```powershell
purpose-review-runner continue --run <run-id>
```

`continue`へcontext、previous output、provider設定、session IDを追加しない。同じreviewer sessionが保持する目的理解を利用する。再び`FINDINGS`なら親が修正・validationして同じcommandを使い、terminal statusまで繰り返す。

Round 3でfindingが残る場合はRunnerが`HUMAN_DECISION_REQUIRED`を返す。automatic round 4、session reconstruction、transcript replay、別reviewer recoveryを行わない。

## Report

完了済み、未検証、HumanDecisionRequiredまたはBlocked、人手で必要な作業を分ける。reviewerがrepositoryを変更しないことは役割契約であり、OS-level isolationの証明とは表現しない。
