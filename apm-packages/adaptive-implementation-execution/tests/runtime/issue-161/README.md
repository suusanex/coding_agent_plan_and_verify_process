# Issue #161 runtime観測（2026-11-12）

Copilot CLI 1.0.109でcanonical Skill/agentsを隔離repositoryへコピーして実行したscripted smoke。APM導入経路の認定、実利用者による承認、長期的な品質保証ではない。

- session: `91f9ae22-692b-4d1c-a1b0-292563f16518`
- 親: CLI選択済み`gpt-5.6-sol`。起動時にmodelを指定せず、上位別agentなし。
- 子: `gpt-6-luna`。tool traceでsubagent start/configured/completedを観測。general-purpose taskにcanonical子契約を渡すadapter。
- fixture: 既存ItemStore/ReportSinkにReportServiceとReportFormatterを追加。ordinal順のname:quantity出力、null/負quantity拒否、cache/retryなし。
- turn1入力: `/adaptive-implementation-execution plans/report.md を実装してください。`
- turn2入力: `進捗状況を教えてください。これは構造への承認ではありません。`
- turn3入力: `提示された構造版1を承認します。計画の残作業を進めてください。（隔離runtime試験の合成応答）`

## 観測

1. 親はstore→formatter→sinkの実呼出とXML契約を作り、formatter末端をNotImplementedExceptionで残した。構造はstructure-v1.txtに保存。
2. production publish成功後AWAITING_STRUCTURE_REVIEWでCLIが終了した。Native AOT linker不足があったためfixtureではPublishAot=falseを明示。意味上の正しさをbuildで証明した扱いにしていない。
3. 非承認resumeで待機を維持。Report.cs SHA256は前後とも`32F9376667496813DC458F022DEA31D250BA961DC851891A780D15F73917C877`。子起動なし。
4. 合成承認後、版1と現在hashを照合しhandoffをREADYへ更新して子を起動。子が本体と隔離検証を作成し7/7 PASSを返した。親の受入build・検証も成功。

turn*.jsonlはsession/応答/子起動/結果の抜粋。全tool traceは実行環境の`C:\WindowsTemp\adaptive161-runtime\turn*.jsonl`に保持する。実際の人間による構造レビューを代替する証拠ではない。

## 限界

子の隔離fixture検証はinternal型を読むためreflectionを選んだ。納品対象のfinalizer・process実装にはreflectionを追加していない。このfixtureは詳細実装品質やrepository規約遵守を認定するものではなく、構造分担と停止・委譲の観測である。

再引受けは注入payloadの処理、既存再利用は本文path明示の経路を観測した。自然発生した子の構造変更検出、Codex runtime / VS Code UI / 実利用者運用は未検証。

## 追加観測

- turn4: fixtureがstore戻り型をIEnumerableへ変える外的変化と子返却payloadを注入。元親はserviceの一回materializeを構造版2としてbuildし、AWAITING_STRUCTURE_REVIEWで停止。自然発生した子の検出は未検証であり、注入payload後の再引受け経路だけを確認した。
- reuse-failed: slash名だけのCLI入力ではSkill本文が読まれず、親が通常実行と詳細検証を完了した。失敗例として保持する。この結果を新しい構造ゲートのPASSへ含めない。CLI usageはSkill本文pathも明示する形へ修正した。
- reuse-explicit: Skill本文pathを明示した新sessionでは、production diffなしでbuildし、tracked構造版1を提示してAWAITING_STRUCTURE_REVIEWで停止した。詳細検証や子起動へ進まないことを観測。
- designpair: 既存Issue159のall-Adaptive READY fixtureを明示入力。親model維持、別上位起動なしで構造作成とproduction buildを実施し、design-pair / explicit-user-selectionを保持してAWAITING_STRUCTURE_REVIEWでCLIが終了した。Design Pair対話自体を今回再実施した証拠ではない。
