# Issue #148 検証記録

## 採用した構成

Review Leadは各roundで1回だけ起動またはresumeし、Investigatorは明示設定時だけfreshで先行実行する。schemaVersion 1とschemaVersion 2のInvestigator未指定はLead-onlyとする。小規模判定のための追加LLM呼出しや自動閾値は導入しない。

既存のprovider adapter、process runner、job / state storeを再利用する。変更概要はGit CLI、構造化reportのparseはBCLのSystem.Text.Jsonを利用する。新規OSSは不要で、独自部分はIssue固有の必須field・位置情報・参照整合性の検証とrole間の実行制御に限定する。一般的なJSON Schemaエンジンを追加してもevidence参照整合性や目的に関する意味判断は代替できず、現在の小さい固定contractでは依存追加に見合わない。

## 自動検証と実測の区別

stubによる検証は、呼出回数、同一session、role設定の固定、JSON検証、失敗時の退避を確認する。promptの文字列検査は行動契約の存在を確認するものであり、LLMが実際にその順番で調査した証明ではない。

実providerの比較では同じpurposeと同じfixtureに対しLead-only / 分業を実行し、Leadの呼出回数、provider公開のtoken等、総消費、wall-clock、既知の欠陥の発見・誤検出、再reviewを記録する。tokenが取得できなければ欠測とし、呼出回数だけで利用枠削減を断定しない。少数のfixture結果を実案件全般へ一般化しない。

## 実測対象

`experiments/persistent-purpose-reviewer/fixtures/lead-investigator/`の注文判定を用いる。正の注文数量と停止中アカウントの拒否という独立した2条件を確認する。送料判定は正常な対照とする。調査用fixtureの意図的欠陥を本番コードの不具合と混同しない。

実測で品質・消費の利点を確認するまではInvestigatorを既定で有効にしない。

## 自動検証（2026-10-28）

- Runnerのテスト：75件合格、2件skip。skipはWindows Job Object / WMIを使う既存の明示実行用テスト。通常のCI経路ではOS状態変更を避ける。
- Skillの契約検証とpackage-root APM install smoke：合格。
- framework-dependent Release publish：合格。インストール済みのuser-level Runnerは更新していない。
- Agent Plugin生成検証：インストール済みAPM 0.33が既存スクリプトのimperative local-bundle routeを拒否したため失敗。本変更のSkillインストール試験とは分けて扱う。生成経路の互換更新は未実施。

## 実providerの観測

比較用に隔離したfixtureとconfig / stateを使い、Review LeadはCodex `gpt-6-astra` / medium、実InvestigatorはGrok `grok-4.6` / highを指定した。Grok側の記録上のモデル名は`grok-4.6-build`。基準は新RunnerのLead-onlyであり、旧0.4.0のbinaryとの比較ではない。

初回のGrok比較では、最終assistant contentが正しいJSONでも、plain stdoutに途中の日本語commentaryが混ざってparseが失敗した。Runnerはそのreportを不受理とし、Leadが2つの欠陥を直接検出した。この実測を受けて固定境界行によるJSON transportを追加した。自由文から波括弧を推測して結果を救済する方式にはしていない。

CLIがcommentaryと開始境界を改行なしで連結するケースも実応答fixtureで回帰検証し、修正後の`f57c2662`ではGrok reportを正常受理した。Leadは原典を照合して2欠陥を検出した。Lead-onlyと正常分業のLead total tokensは67,889 / 63,546、総provider tokensは67,889 / 136,188、wall-clockは34.33 / 150.38秒。この規模では総消費・時間が増えるため分業は既定化しない。cache差と試行数の少なさもあり、Lead利用枠の削減は未実証である。

候補ゼロの見落とし試験は、実LLMのInvestigatorが偶然見落とすのを待つのではなく、FakeProviderに「送料のみ確認、注文可否は未確認、候補なし」というreportを返させ、実Codex Leadへ渡す。UTF-8修正後の試験では、Leadが未確認範囲を補って注文判定を原典で確認し、2つの欠陥を検出した。これは見落としを拾う経路の一例であり、すべての見落としを防ぐ保証ではない。

初期のfixture実行には、実行ファイル名の誤指定、FakeProvider固有のcontext marker検査、標準出力のCP932による文字化けもあった。これらは正常な分業の比較には含めず、試行の結果を削除せず保持する。

測定値と結果JSONは[実測evidence](../experiments/persistent-purpose-reviewer/evidence/issue-148/)に保存する。providerのtokenは各providerが報告する集計値であり、サービスの利用枠百分率や課金額へ換算しない。入力tokenにはcacheされた入力が含まれるため、cached inputも併記する。

## 修正後の同一session再review

一時repositoryのCanOrderだけを`requested > 0 && !isSuspended && stock >= requested`へ修正し、既存のLead-onlyと正常分業runをそれぞれcontinueした。両方とも同じLead sessionのRound 2でCOMPLETE、分業側はfresh Investigatorのreportも正常受理した。COMPLETEはこの検証用fixtureの静的review結果であり、Runner本体の独立purpose reviewや公開完了を意味しない。Round 3の上限・継続性はstubによる3roundテストで確認し、COMPLETE後の追加roundは実行していない。

| Round 2 | Lead invocation | Lead tokens（当round差分） | Investigator tokens | 総tokens | 秒 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Lead-only | 1 | 58,216 | 0 | 58,216 | 24.75 |
| 分業 | 1 | 60,776 | 82,426 | 143,202 | 279.03 |

この小規模再reviewでは分業のLead消費も減らなかった。通常設定をLead-onlyのままとする判断を維持する。広い実案件での効果測定、各provider組合せの網羅実測、Release発行とuser-level導入は未実施。今回の実装・予定した機能検証は完了しており、追加のLLM実測を必須とはしない。
