# native same-child persistence 実験概要

## 結論

同一の native child に対する親 session 内の idle follow-up で、Round 1、Round 2、Round 3 の応答が同じ child conversation の Turn 0、1、2 として返された。Round 2 では `PUR-001` が持続し、Round 3 では解消済みと判定されたため、native same-child continuity の根拠として保存する。

## 実験条件

- model: GPT-5.6 Luna
- child role label: `native-purpose-reviewer`
- child 作成: `functions.task` で general-purpose child を一度だけ作成
- 初回方針: fresh 目的として、親の判断を使わず、指定された fixture のみを読むよう prompt で指示
- follow-up: child が idle になった後、`functions.write_agent` で同一 handle に Round 2、Round 3 を送信
- continuity 根拠: `read_agent` が同じ child conversation の Turn 0/1/2 を返したこと
- handle の扱い: private session ID として保存せず、人間可読な role label として記録

## read-only の限界

task API には read-only permission パラメータが存在しない。child には通常のファイル書込み等のツールが原理的にあり、prompt で shell、network、write を禁止しただけで技術的保証ではない。したがって本証跡は prompt 上の制約と観測された結果を記録するもので、API enforcement を主張しない。

## 入力の継続性

Round 1 は full purpose context file と Round 1 candidate だけを読ませた。Round 2/3 は Goal Context 全文および previous output 全文を再送せず、candidate と最小限の follow-up のみを渡した。Round 2/3 follow-up の完全な文面は保存していないが、full context replay がないことを `input-manifest.md` に追跡可能な形で記録した。

## 実験範囲と未実施事項

親 session 内で child が idle になった後の外部 agent task lifecycle と follow-up 成功を確認した。parent process 終了後の復旧、永久 session ID による復旧、session ID/API durability は実施していない。証跡保存作業では外部モデルおよびネットワークを使用していない。

## Git 検証

作業前後に `git status --short` と `git diff --check` を実行した。既存の未追跡状態は `?? .wt/` と `?? experiments/` で、今回の作成対象は `experiments\persistent-purpose-reviewer\evidence\native\` のみである。production、skills、scripts、config は変更していない。最終検証でも `git diff --check` は問題なしだった。
