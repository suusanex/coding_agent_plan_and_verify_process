---
name: persistent-purpose-review
description: Use only when the user explicitly invokes persistent-purpose-review. Do not select automatically for ordinary implementation, verification, or review requests. Independently review purpose and design alignment at initial design and material changes within the explicitly authorized task, using linked submissions with a bounded budget. Requires the separately installed purpose-review-runner.
user-invocable: true
disable-model-invocation: true
# Copyright (c) 2026 suusanex (GitHub UserName)
# SPDX-License-Identifier: CC-BY-4.0
# License: https://creativecommons.org/licenses/by/4.0/
# Source: https://github.com/suusanex/coding_agent_plan_and_verify_process
---

# Persistent Purpose Review

このSkillは、ユーザーが明示的に起動した場合だけ使用する。通常の設計、実装、検証、レビューの依頼からモデルが自動選択してはならない。

目的と設計の整合を、独立reviewerに確認させる。対象は明示的に許可されたtask内の初期設計と、目的・設計を変える重要な変更である。findingが出たことだけ、または実装不足だけを理由にreviewを開始しない。実装の欠落を補修する工程やコード品質reviewを担当しない。

`purpose-review-runner`は別途OS user単位で導入されている必要がある。このSkillはRunner binaryを内包、download、installしない。

## Ownership and boundary

- ユーザーが許可したtaskとscopeを越えて判断・作業を広げない。ユーザーの許可を代理で作らない。
- reviewerは、元の目的、承認済み設計、提案設計とその差分、提示された証拠を照合する。実装の調査や実装欠落の修復をレビュー対象にしない。
- 必要な設計の不足と対に、目的内でも不要な処理・状態・境界・重複を評価する。削除案がなくても、削除・統合や追加機構の組合せの除去で必要な成果・保証を維持できるかを問い、具体的な不要性と負担を入力に結び付ける。説明不足だけで不要と断定せず、明示された成果・保証・責務境界を弱めたり、好みのarchitectureや細かな最適化を強制したりしない。承認済み判断の変更が必要なら、reviewerが取り消さず判断事項として返す。
- reviewerは設計上のfindingと必要な判断を返す。変更や設計の決定はユーザーまたは明示された設計責任者が行い、reviewerが承認を代行しない。
- 目的の引用文と根拠sourceはinputへ埋め込む。reviewerに会話・外部sourceを再取得させず、引用を捏造・補完させない。
- conformanceの記録は申告内容と証拠を評価するための入力である。記録されたownerが実行・確認したことをRunnerやreviewerが保証するものではない。
- Runnerがprovider、session、review round数（`reviewRounds`）と試行回数（`durableSubmissions`）、入力結合、result parseを所有する。provider CLI構文やsession handleをSkillから再実装しない。
- 対応review providerはCodexとGitHub Copilot。Grok Buildは対象外だが、Grok BuildはRunnerを呼び出すcallerになれる。

## Provider execution boundary

- Runnerはrepositoryとは別の作業directoryでCLIを起動し、review inputから作ったpromptだけをstdinへ渡す。continueは同じprovider sessionを再利用する。
- provider CLIのversion完全一致はruntime hard-fail条件とせず、feature disableやMCP disable等の探索抑制用optional guardrailは事前に利用可能性を判定できる範囲でbest-effort適用する。review本体が失敗した場合に制限を外して再試行することはしない。
- Codex CLIの通常read-only実行設定を使う。Codex環境にhost collaboration等の追加機能が残る場合があるため、role promptでrepository探索、外部調査、ツール呼び出し、委譲を明示的に禁じる。
- このrole boundaryは完全なcapability isolationを意味しない。SkillとRunnerは独自の認証・隔離基盤を追加せず、provider CLIの認証と通常read-only設定を利用する。
- Copilot CLIでは実機確認済みのより制限されたprovider設定を維持する。Copilotのzero-tool確認をCodexへ一般化せず、Codexの残存機能を使ってよいという許可にも読み替えない。

## Prepare one input per submission

目的、設計、差分、証拠、findingへの応答を一つのJSON inputにまとめる。初回および各continueで、その時点の完全なinputを渡す。古い入力をreviewerに探させない。

役割説明だけでは必要性を判断しにくい場合、既存の`proposal.body`へ代表的な一件の処理経路、読取り・生成・更新する情報、追加段階や状態を必要とする現在の制約を短く含める。分かっていない点は不明として示す。全componentの長い必要性説明、新しい必須台帳・schema・成果物は追加しない。

事前に作成したSolution Shape（構成・責務配置、機能配置、代表的な実行経路の軽量スケッチ）がある場合は、設計案そのものなら既存の`proposal.body`、他案や判断の補助資料なら`evidence`に任意で含める。Solution Shapeの作成や`solution-shape-authoring`の起動をreview開始の前提にせず、未添付であることをfindingや停止理由にしない。また、Solution Shapeを作成しても`approvedDesign`へ自動昇格させない。

```json
{
  "schemaVersion": 1,
  "taskKey": "stable-task-key",
  "changeId": "stable-change-id",
  "previousRunId": null,
  "userDecision": null,
  "purpose": {
    "version": "purpose-v1",
    "sources": ["docs/goal-context.md#purpose"],
    "body": "今回の目的と制約を、根拠sourceから忠実に引用して記載する。",
    "original": "ユーザーが述べた元の課題・目的を引用する。",
    "authority": "誰が、どの範囲を決定または許可したかをsource付きで記載する。"
  },
  "approvedDesign": null,
  "proposal": {
    "version": "proposal-v1",
    "body": "提案する設計全体を記載する。",
    "delta": "承認済みbaselineからの追加、削除、緩和、変更をすべて列挙する。baselineがない場合はその旨を明記する。"
  },
  "evidence": [
    { "id": "E1", "source": "docs/design.md#section", "body": "判断に必要な証拠本文を埋め込む。" }
  ],
  "responses": [],
  "conformance": [
    { "owner": "担当主体", "plan": "実施予定と確認内容", "evidence": ["E1"] }
  ]
}
```

`purpose.original`と`purpose.authority`には元の課題・authorityの該当箇所をsourceから原文で引用し、出典を`sources`に示す。`approvedDesign`は確認可能な承認済みbaselineがある場合だけ記入し、なければ`null`にする。`proposal.delta`では追加だけでなく、削除・緩和も含めて差分全体を明示する。`evidence.body`へreviewに必要な内容を含め、sourceへのアクセスを前提にしない。`responses`にはfindingへの応答と裏付けを記録する。`conformance`にはowner、実施plan、証拠参照を記録するが、記録されたownerが実行・確認したことをRunnerやreviewerが保証した扱いにしない。

`taskKey`と`changeId`は同じchangeの連続提出間で維持する。findingや未解決事項を隠す目的で識別子を変更し、新規taskや新規changeとして提出し直して上限を回避しない。`FINDINGS`からは新しい`changeId`へ逃げることはできず、必ず同じrunで`continue`する。Runnerはcallerが与えたIDでlineageを追跡し、異なるtaskKeyが同じ実質的作業かどうかは推測しないため、IDの一貫性はこのSkillに従う側が守る。

`userDecision`はnullが既定だが、実際のユーザー判断によりpurposeまたはapproved baselineを変更する場合、新しい`changeId`とともにその判断本文とauthorityを原文・出典付きで記録する。すでにユーザーが許可した判断を再利用する場合は、その既存の発言・文書を引用してauthorityを示し、同じ承認を再度求めない。以前の提案や`COMPLETE`だけでは承認済みbaselineへ昇格させない。実際のユーザー承認の根拠がなければ`approvedDesign`を直前baselineのまま保ち、承認されていない設計は`proposal`に置く。

`HUMAN_DECISION_REQUIRED`後は異なる`changeId`で新しいchangeを始めるため、`userDecision`が必要である。`ERROR` / `BLOCKED`後に異なる`changeId`の新しいchangeを始める場合、purposeと`approvedDesign`が前回inputから不変なら`userDecision`は不要であり、purposeまたは`approvedDesign`を変更する場合のみRunnerが新しい`changeId`と`userDecision`を要求する。同じchangeの`ERROR` / `BLOCKED` linked runは、既存authority内で不足原因を解消できるなら同じ`changeId`を維持する。Runnerはbody/authorityが空でないことを検証するが、ユーザー発言の真偽やauthorityを認証しない。判断を捏造して同じ変更を再開しない。

`priorReviewHistory`はRunnerが管理するoptional fieldで、利用者inputでは省略する。ERROR / BLOCKED後のlinked runやcontinueではRunnerが直前review履歴を含める。利用者が履歴を作成・改変して前回の指摘を入れ替えない。

## Verify the Runner

```powershell
purpose-review-runner version
```

stdoutのJSONを読み、`protocolVersion`が`4`、`runnerVersion`が`0.6.0`以上であることを確認する。command未導入、非0 exit、JSON不正、version欠落・非互換なら停止する。Grokや別commandで代替しない。

## Submit and continue

初回はJSON inputを作成し、taskとchangeに安定した識別子を付ける。

```powershell
purpose-review-runner start --repository <repository-root> --input <input.json>
```

結果に`runId`があれば保持する。`RUNNING`中は同じrunのstatusを確認する。

```powershell
purpose-review-runner status --run <run-id>
```

### Wait for the review result

`start` / `continue`は非同期reviewを起動するため、commandが`RUNNING`を返しただけで待機工程を終えない。直後から同じ`runId`の`status`を確認し、次の状態を`status`の値で処理する。`jobStatus`や`terminal`だけを先に評価してreview状態を省略しない。

| `status` | 処理 |
| --- | --- |
| `RUNNING` | 同じrunのstatus確認を継続する。 |
| `FINDINGS` | `terminal: false`でも待機を区切る。findingを設計責任者の入力として検討し、必要なら更新inputで同じrunを`continue`する。 |
| `COMPLETE` | `terminal: true`のreview完了として待機を終え、結果を報告する。承認や実装完了にはしない。 |
| `HUMAN_DECISION_REQUIRED` | 待機を終え、必要な判断とauthority不足を報告する。判断なしで続行・complete扱い・同じchangeの再開をしない。 |
| `BLOCKED` | 待機を終え、`message`と`informationRequests`を報告する。不足を補える場合だけlinked runの契約に従う。 |
| `ERROR` | 待機を終え、`error`を報告する。結果を`COMPLETE`として扱わず、runが不明な場合は再submitより先にstatusを再確認する。 |

Runner protocolでは`FINDINGS`は正常な非terminal状態である。`terminal: true`を`FINDINGS`の通知・受領条件にしてはならず、`FINDINGS`を`COMPLETE`まで無視したり、`terminal: false`を単に`RUNNING`と読み替えたりしない。`status`が上表以外、または状態と`terminal`の組合せが不整合なら停止してreportする。

Grok Buildのheadless実行（`-p --output-format streaming-json`または同等のheadless経路）では、同じprompt turnを維持したまま次のように`status`を反復確認する。`long-running-background-tasks`の`monitor`を登録してturnを終了し、その後のnotificationによる再起床を待機成立の前提にしない。15秒ごとにstdoutへ状態JSONを出力し、15分を上限とする。上限に到達しても`RUNNING`なら、reviewを成功扱い・再submitせず、run IDと`RUNNING`のままで中断した事実をerrorとして報告する。

```powershell
$runId = '<run-id>'
$deadline = [DateTimeOffset]::UtcNow.AddMinutes(15)
$terminalByStatus = @{
    'RUNNING' = $false
    'FINDINGS' = $false
    'COMPLETE' = $true
    'HUMAN_DECISION_REQUIRED' = $true
    'BLOCKED' = $true
    'ERROR' = $true
}

do {
    $raw = purpose-review-runner status --run $runId
    if ($LASTEXITCODE -ne 0) {
        throw "Purpose Review status failed with exit code $LASTEXITCODE.`n$raw"
    }
    $output = $raw | ConvertFrom-Json -ErrorAction Stop
    Write-Output $raw

    if ($output.runId -ne $runId -or -not $terminalByStatus.ContainsKey($output.status)) {
        throw "Purpose Review returned an inconsistent run or unsupported status for $runId."
    }
    if ($output.terminal -ne $terminalByStatus[$output.status]) {
        throw "Purpose Review returned inconsistent status and terminal values for $runId."
    }
    if ($output.status -ne 'RUNNING') {
        break
    }
    if ([DateTimeOffset]::UtcNow -ge $deadline) {
        throw "Purpose Review timed out while run $runId was still RUNNING."
    }
    Start-Sleep -Seconds 15
} while ($true)
```

このloopから抜けた後、`$output.status`へ上表の処理を適用する。`status` command自体の非0 exit、単一JSONのparse failure、`status` / `terminal`の契約不整合は、review結果不明または失敗として停止する。timeoutはworkerを停止させるものではない。後続処理を再開する場合は同じrun IDのstatusから始め、新しい`start` / `continue`を送らない。

対話実行などで既存のnotification / monitor機構を使う場合も、`FINDINGS`を非terminalの正常な待機区切りとして通知し、headlessで未確認の再起床を前提としない。Grok Buildをreview providerとして利用する変更ではない。

reviewerからfindingが返った場合、実装を自動修正しない。許可済みtaskの範囲で設計責任者が検討した応答、更新した提案・差分・証拠を新しいinputへ反映し、同じ`taskKey` / `changeId`と`continue`対象runのIDでcontinueする。このrunの全roundで`previousRunId`は初回start時の値を保つ（初回taskならnull）。

```powershell
purpose-review-runner continue --run <run-id> --input <updated-input.json>
```

同一changeに対する有効なreview成立回数（`reviewRounds`）は、linked run全体を通じて最大3回である。reviewが成立する前に終了したoperational failureは`durableSubmissions`にのみ計上され、3-roundのreview予算は消費しない。3回の成立したreviewで解決しない場合は停止して未解決事項を報告する。別runを作り直したり識別子を変えたりして上限を回避しない。terminal結果はcontinueしない。`COMPLETE`はレビューの完了だけを示し、提案や目的の承認を意味しない。後日、別の重要変更を始める場合は同じ`taskKey`、新しい`changeId`、直近の`COMPLETE` runを指す`previousRunId`を使い、完全な最新inputを新しいrunへ渡す。`approvedDesign`には実際に承認済みのbaselineだけを記入する。実際のユーザー承認の根拠がある場合はそれを`userDecision`に記録し、過去のproposalは自動昇格しない。同じ`changeId`の再提出・再開でterminal予算を回避しない。

`HUMAN_DECISION_REQUIRED`後、ユーザーが実際に新しい目的・scope判断を示した場合だけ、同じ`taskKey`、新しい`changeId`、直前terminal run IDを入れた`previousRunId`、引用した判断を記す`userDecision`で新しい`start`を行う。これは新しい変更に対する新しいbudgetであり、未解決の同じchangeを再開したり予算を迂回する方法ではない。ユーザーに同じ判断を繰り返し求めない。

terminal `ERROR`または`BLOCKED`ではそのrunをcontinueしない。原因や不足を解消した場合に限り、新しいlinked runを`start`する。同じchangeを継続する場合は`taskKey`と同じ`changeId`を保ち、`previousRunId`には直前terminal runのIDを設定して、既に消費したreview round数（`reviewRounds`）と過去履歴を引き継ぐ。この新runの各continueでは、その`previousRunId`を変えない。結果不明のrunがある場合は再submitせず、まずstatusを確認する。必要な情報が不足しているだけでユーザー承認を繰り返し要求せず、既存authorityの範囲で補える入力を用意する。authority自体の変更が必要なら作業を止め、判断が必要な点を報告する。

## Report

目的・設計に関するfinding、設計責任者の応答、未解決・未確認事項、run内`round`と累積`reviewRounds`（および必要に応じた`durableSubmissions`）、terminal状態を分けて報告する。`COMPLETE`をユーザー承認、設計適合の独立実証、実装完了、実行時conformance保証と表現しない。
