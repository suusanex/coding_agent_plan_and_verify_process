# Issue #150 目的・設計レビューの限定実機評価

実施日: 2026-10-28  
対象: Runner 0.5.0 / protocol v4 / input schema 1、Copilot CLI 1.0.105、`gpt-5.6-terra`、reasoning effort `low`
安全設定: [provider安全性の実機確認](2026-10-28-provider-safety.md)を参照。全レビューは外部一時fixture repositoryを対象とし、実プロジェクトのファイルをモデルへ渡していない。

## 観察したケース

| ケース | 入力・実行 | 結果 | 観察 |
|---|---|---|---|
| 通知返却の初期proposal | 同一task/changeで計3提出。初めの2提出は `PROVIDER_VERSION_UNSUPPORTED` で終了し、モデル呼び出し前に失敗。3提出目 `38dc59d6-80ad-4910-9df2-fd718dce036d` は終端 `HUMAN_DECISION_REQUIRED`。 | 3提出上限を消費 | 最終実行は「指定通知先へ直接返す」目的とdashboard/search/filterを追加する案の不一致を2件指摘。前2回のversion拒否を含め、同じchangeの修正継続はできなかった。version parser修正後の評価ではないため、初期失敗はRunner修正前の運用負荷として記録する。 |
| CSV export 初期案 | run `7af681cc-fdab-4378-89c5-5cd8932f7ba1`、input 1,594 bytes / 約1,514文字。 | `FINDINGS`、HIGH 2件 | 保存済みreportを書き換える点とpublic token URLがprivate reportを露出する点を検出。 |
| CSV export 修正案 | 同runのround 2、input 2,725 bytes。 | `COMPLETE`、findings 0 | read-only snapshotと認証済みprivate routeに修正した内容を、両findingへの応答・根拠付きで受理。Runnerは2件の解決をmessageに記録した。 |
| CSV exportの重要な別変更 | 新change `private-csv-export-async-v2`、前runを参照、input 2,200文字。 | run `49a14804-3887-4237-ad6d-211ef63c50dd`: `COMPLETE` | 即時downloadを非同期job/statusと完了後downloadへ変えたが、CSV、read-only snapshot、private accessを保つ案を目的に整合すると判断。 |
| 広い要約と具体的な原文 | bodyは「reportをexportできる」、原文はCSV/offline/no mutation/no public link。input 1,476文字。 | run `9ec54290-fe7a-45a5-ad74-25c569921cc1`: `COMPLETE` | 原文に含まれる具体条件を参照して適合案を受理。要約が広い場合に原文の要件を落とさなかった。 |
| 要件を限定していない依頼 | 原文は「reportをexportしたい」のみ。proposalはCSVと任意date filterを追加。input 1,211文字。 | run `4e01bc22-f26f-41a8-bd1a-d58ef3e5dbfe`: `HUMAN_DECISION_REQUIRED` | CSV形式、filterの必要性・意味、提供方法を未決事項として人の判断に戻した。要求されていない要件を前提にせず、追加設計の選択を提示した。 |
| 根拠資料が不足 | purposeはRET-7 retention policy準拠を要求。入力にpolicy本文・期間・削除条件はなく、proposalは7日保持。input 1,484文字。 | run `0dc95444-e673-4024-bb97-ac46290de1f2`: `BLOCKED` | RET-7本文または承認済み保持要件の提示を `INFO-001` で要求。7日が準拠するかを推測しなかった。 |
| 具体的な目的に対する目的の言い換えだけの設計 | purposeはCSV・offline review・非変更・認証済みprivate routeを明示。proposalは「目的を満たすexportを実装する」とだけ記述。初回input 1,551文字。 | run `0e9c501e-5204-4091-8074-d2c2b6a8b345`: round 1 `FINDINGS`、HIGH 1件。修正案round 2で `COMPLETE`。 | 必要なCSV内容、read-only責務、認証済みprivate配布を設計決定として定義していない点を検出。proposal-v2で3点を具体化し、findingを解消。修正input 2,024文字。 |

## 所要と入力準備の観察

Runnerが受け付けてから終端状態を確認するまでの所要は、9件の実モデル呼び出しを含む実モデル評価で概ね約9–12秒だった（status確認は約3秒間隔のため概算）。初期JSONの生成・一時ファイル書き込みは、計測したcontrast fixtureで約30–34ms、CSV別変更・修正案では約10ms。これはPowerShellによるJSON生成・保存だけの時間で、人による要件収集・入力作成時間を表さない。

入力は約1,211–2,725文字。CSV初回案から修正案へはfinding応答、根拠、修正deltaを加え、1,594 bytesから2,725 bytesになった。通知fixtureではmodelを呼ばないversion拒否が同一changeの提出3枠中2枠を消費した。修正後のversion parserでは別taskの実行を確認したが、この運用負荷を相殺したとは評価しない。

Runnerの各review呼び出しについて、CLIのpremium request数、token数、usage checkpoint、ドル請求額はstate/logへ保持されていない。provider process logとworker logを調べたがレビューごとのusage fieldは見つからず、個別の利用量をここへ記載できない。provider安全性fixtureのpremium request累積値は1から2へ増加したが、別の拒否fixtureであり今回のreview呼び出し数・利用量ではない。ドル請求額も不明。これらのfixtureから旧実装とのコスト・時間削減を推定しない。人の入力準備、レビューの見逃し率、指摘の過剰さ、反復利用での負担は未測定。

## 判定境界

本資料は限定的な実モデル挙動の記録であり、PASSや正式qualificationの根拠ではない。レビューはpurpose/design alignmentのみで、実装適合、テスト実行、証拠の独立検証、ユーザー承認は保証しない。APM配布での評価は未実施。direct deploymentは限定証拠を記録したが、広い利用負荷・検出性能を評価していないためHOLDを維持する。
