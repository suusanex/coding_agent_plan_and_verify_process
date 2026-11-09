# Issue #155 必要性・不要性レビューの限定実モデル評価

実施日: 2026-11-10（JST）。[事前に定めたケース・閾値](../purpose-review-scenarios.md#issue-155-必要性の限定対比評価)で7件を各1回実行した。過剰処理3件の検出、対照2件への誤指摘なし、設計不足と根拠不足の区別を確認した。これは限定した合成入力の結果であり、一般的な検出精度や旧promptに対する改善率の測定ではない。

## 対象と再現条件

- Runner 0.6.0 / protocol v4 / input schema 1のローカルDebug build。基点commit `30c69499e4b1db986828fc7c18ae067179517541`へ本PRのPromptBuilder変更を適用。配布済みbinaryは更新していない。
- Copilot CLI 1.0.108、model `gpt-6-astra`、reasoning `medium`。既存のuser configとRunnerのprovider adapterを利用。
- PromptBuilder.cs SHA256: `913A77219F79D67CDB2586022E11F4030D6CD6C59EB8AAD253E454EA72A10636`。
- Skill 0.7.0へ本PRの変更を適用したsource SHA256: `0E97ACB3879F32E3F571126DD869E7BE920A34874FC282689D8F68E27E24B24E`。モデルへの指示はRunnerから送信し、Skill配布経由の利用者動作は測定していない。
- 既存CLIの`start --repository <使い捨てrepository> --input <JSON>`で提出、`status --run`で収集した。repositoryは機密情報のない空のfixture。provider実行cwdはRunnerが管理する外部領域。
- 入力は[01–07のJSON](../fixtures/necessity)。期待判定、削除案、評価表は送信していない。利用ケースと既存API等の制約は判断材料として入力に含む。
- 全出力は[結果JSON・計測値](2026-11-10-necessity)へ保存。各出力のinputHashと[measurements.json](2026-11-10-necessity/measurements.json)のpromptSha256で提出を識別する。

## 全提出の評価

各caseはrun内round 1 / 累積reviewRounds 1 / durableSubmissions 1。再提出・operational failureなし。`FINDINGS`は非terminalであり、この評価では修正案のcontinueは行っていない。`COMPLETE`と`BLOCKED`はterminalである。

| 入力 / run ID | 状態・finding | 親による意味的評価 | 所要秒 |
| --- | --- | --- | --- |
| 01 / `1da86058-2c88-48bd-9517-c6fb1e705c83` | FINDINGS / PUR-001 HIGH | 履歴全件の往復と、それに由来する照合を組合せとして不要と特定。履歴不変と今回メモ生成を維持する要求。期待どおり | 19.39 |
| 02 / `970c4b0f-8b21-4c45-8223-125335b310a2` | FINDINGS / PUR-001 HIGH | 非対象9999件の再生成・照合・全件保存を特定。一件分の処理と非対象保持の両立を要求。期待どおり | 22.53 |
| 03 / `6f169cc1-24fc-4364-8e6e-0b3ca9e005c7` | FINDINGS / PUR-001 HIGH | 引継ぎ管理の強化を要求せず、中間ファイルとID・状態・一致検査を一体で除去・統合できると特定。期待どおり | 19.66 |
| 04 / `710c514b-74ab-42cc-b558-412652625d84` | COMPLETE / 0件 | 操作ID永続保存・同一ID再開・外部契約を必要な保証に結び付け、削除を要求しない。期待どおり | 15.21 |
| 05 / `08cb157d-11e5-4aa9-8868-4b0f9deb8b71` | COMPLETE / 0件 | 20項目の安価な全体保存を受け入れ、差分管理を要求しない。期待どおり | 12.09 |
| 06 / `d13728b5-d586-4f4e-afe9-879b55c86717` | FINDINGS / PUR-001 HIGH | CSVの内容、非改変、本人限定配布の責務・経路が未定義であると指摘。不足審査も維持 | 17.92 |
| 07 / `92071936-8af4-40ca-ac0b-08ec84ef1505` | BLOCKED / finding 0件、INFO-001 | RET-7の適用条項を要求。保存の必要性不明を過剰と断定しない。評価ケースとして期待どおりで、実案件のblockerではない | 14.84 |

01–03のfindingはいずれもpurpose/proposalのfieldとversionを引用し、具体的負担と維持する成果を示している。好みの技術・architectureを強制する指摘はなかった。必要性検出3/3、必要な機構への誤指摘0/2、不足・証拠不足の対照2/2で、事前閾値を満たした。

## 費用・負荷と未確認範囲

所要はRunner jobのstartedAtUtcからfinishedAtUtcの差。7件は並行して進んだため、合計を作業の実時間とは扱わない。入力は1,279–2,022 bytes。追加の必須field・台帳はなく、既存proposal.body内で処理経路を説明できた。レビュー中のユーザーへの追加判断要求・入力更新は0回だった。

providerごとのtoken量・請求額、人間による入力準備の実時間は計測していない。synthetic fixture作成時間を通常利用者の入力負荷に換算しない。旧promptとのA/B比較、反復でのばらつき、Codex provider、承認済みbaseline変更、意味的なcontinue評価、実案件での継続利用負荷は未確認。明確な制約を持つ小標本なので、曖昧な大規模設計での精度は推定しない。APM `NOT_RUN / NONE`とdirect deployment `HOLD / PARTIAL`を維持する。

## この実装自体のpurpose reviewと契約検証

初期設計は導入済みRunnerのrun `ecfd3b6f-f1a9-4048-a255-5ad04c3c3d97`でレビューし、round 1 / reviewRounds 1 / durableSubmissions 1、terminal `COMPLETE`、finding 0件。応答・未解決findingはない。提案承認、実装適合、実行時conformanceの保証とは扱わない。

- `dotnet test tests/PurposeReviewRunner.Tests/PurposeReviewRunner.Tests.csproj`: 81成功、2スキップ（Windows実環境のopt-in qualification）、0失敗。
- package固有validation: PASS。
- CI指定APM 0.26.0でpackage install smokeとAgent Plugin package validation（buildを含む）: PASS。plugin canonical fingerprintは`d193450dbbdb07463cc609061f96788cb8840e7a81837025b1076c0c0f742779`。
- PRの初回CIではqualification記録のfingerprint更新漏れを検出。canonical/distribution fingerprintを現行sourceに合わせ、qualification record validator（negative mutationを含む）とpackage validatorの成功を確認した。qualification状態は変更していない。
- 最初に使ったAPM 0.33.0では既存builderのlocal bundle install経路が拒否された。CIと同じ既存0.26.0をコマンド環境内だけで選択して検証した。グローバル設定・builderの変更はしていない。
- skill-creatorのgeneric quick validatorは既存の`user-invocable` / `disable-model-invocation`を許可しないため失敗。これらは本Skillの必須境界であり削除せず、両fieldを検証するrepository固有validatorと配布検証の成功を採用した。

契約検証はRunnerの入出力・予算・provider境界等の回帰を確認するものであり、上記実モデル結果の代替ではない。
