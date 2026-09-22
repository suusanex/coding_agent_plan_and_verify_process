# Migration

## 0.9.0 boundary

0.9.0は、独立した`review-planner`によるrecommendation作成を削除し、現在の親がcollectorのremote evidenceを直接評価する構成へ変更します。

| 0.8.0 behavior | 0.9.0 disposition |
| --- | --- |
| `review-planner`がremote evidenceをrecommendationへ整理 | 現在の親が全sourceを直接評価してdecisionと根拠を記録 |
| packageがplanner agentを導入 | packageはSkillとcollectorだけを導入 |
| `codex-profile-finalizer` dependencyとplanner profile | dependency、overlay、profile生成手順を削除 |
| planner recommendationと親のfinal decisionを別列で記録 | 親の`Apply \| Reject`または人間判断が必要な状態をdecisionとして記録 |

remote GitHub evidence authority、Ready PR identity、Copilot review要求・待機、全source ID coverage、duplicate / conflict mapping、Reject理由、head drift検出、未信頼remote content境界、fail-closedな取得失敗、同一parentによるremediation / validation / commit / pushは維持します。

## 0.8.0 boundary

0.8.0はbaseline PR Reviewを、review planで停止する契約から、現在の親がremediationとGit操作まで完了する契約へ変更しました。

| 0.7.0 behavior | 0.8.0 disposition |
| --- | --- |
| findingありでAdaptive用handoffを返して停止 | `REMEDIATION_REQUIRED`を内部状態として同じ親が処理を継続 |
| Adaptive Implementationが唯一の実装経路 | 利用者が明示指定した場合だけ利用できる任意経路 |
| plannerが`Apply \| Hold \| Reject`を決定 | plannerはrecommendationを提供し、親が全findingの最終判断を所有 |
| remediation後のcommit / pushは別作業 | validation成功後、否定指示がなければ同じ作業内でcommit / push |
| 修正不要 | 理由を報告し、empty commitを作らず`NO_CHANGES`で完了 |

## 0.7.0 boundary

0.7.0はbaseline PR Reviewをremote GitHub PR evidence専用へ変更しました。

| Former component | 0.7.0 disposition |
| --- | --- |
| Ready PR preparation | Retained |
| `collect-pr-review-context.cs` | Retained as remote evidence authority |
| GitHub Copilot Code Review request/wait | Retained and fail-closed |
| `local-reviewer` agent | Removed |
| local review template/raw artifact/execution metadata | Removed |
| `review-planner` | Retained with remote-only inputs |
| Goal Context/multi-round planner mode | Removed from baseline package |

Local reviewerを別runtimeで置き換えません。旧local findingsや旧実model fixtureをcurrent inputとして再利用せず、Git historyだけをhistorical recordとします。

目的reviewは互換性を持たない別package `persistent-purpose-review`とuser-level `purpose-review-runner`が担当します。
