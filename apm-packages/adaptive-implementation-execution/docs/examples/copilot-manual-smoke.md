# Adaptive 0.7 runtime確認

静的fixtureはruntimeの停止を証明しない。隔離repositoryにcandidateのSkillとcanonical agentsを導入し、以下を実modelで観測する。履歴上の0.6以前の結果を流用しない。

1. 通常Planから現在の親sessionで構造コードを作り、選択済みmodelのままproduction buildする。別上位agent起動がないことをtool traceで確認する。
2. 人にコードsnapshot・未実装・build対象を示してturnが終了する。末端未実装と主要な実呼出が共存し、詳細tests / mockを親が完成していないことを確認する。
3. 承認を含まないresumeで待機を維持し、production diffと子起動数が変化しないことを確認する。
4. 提示後の応答で承認した構造版とsnapshotを結び、子の実起動・詳細実装・tests / validationを確認する。
5. 子から実質的構造変更を返し、元親が構造修正・build・新版提示で再停止することを確認する。局所修正だけなら再承認を要求しない。
6. 既存再利用で親の変更が不要でも同じ停止を行い、残る検証を子へ渡す。
7. valid Design Pair handoffから同じ親構造経路に入り、Locked Decisionsとroute identityを保持する。Design Pair承認で構造ゲートを飛ばさない。

記録はcandidate、CLI version、requested / observed model、session、turn別input / outputとtool trace、構造snapshot、build、子の結果、未観測範囲を含める。合成応答を使ったscripted smokeは実利用者の承認・human-operated smokeではないと明示する。VS Code UIとCodex runtimeは別観測なしにPASSとしない。
