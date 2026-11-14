# Grok Build headless短時間分割polling検証

## 目的

PR #168 のP1/P2レビューに対し、Grok Build headlessが15分のpolling loopを1回の前景terminal commandへ入れず、同じprompt turn内で短い`status` callと短いwait callを交互に進められることを確認する。特に最初の`RUNNING`が30秒以上続いた後でも、`FINDINGS / terminal: false`を取得し、同じrunを`continue`して`COMPLETE`へ進めることを検証する。

## 実行環境

- 実行日: 2026-11-14
- Grok Build: 1.0.77 (`50ca579fa996`, stable)
- Codex Agent Facade checkout: `836ffaceaea41519cae6adad8822b1809d52c2c7`
- Facade route: `CodexAgentFacadeCli.cs`から`agent: grok-build`、`--output-format streaming-json`、`-p`
- Purpose Review Runner: 0.6.0 / protocol v4
- Runner provider: CIで使用する`PurposeReviewRunner.FakeProvider`を隔離state/configで利用
- delay: `PURPOSE_REVIEW_FAKE_PROVIDER_DELAY_MS=45000`
- Facade run: `20261114T130742Z-0629866d`
- Grok session: `94203d0e-04c9-4a70-ba72-4f70f7e4f5f0`
- Purpose Review run: `9545860a-eb3a-4838-a8a5-d69270bd9cf6`

テストproviderはreview判定そのものをGrokへ任せる実験ではなく、`RUNNING`を再現可能に45秒継続させるtiming fixtureである。caller側のGrok、Facade、Runner CLI、Protocol v4 state machineは実物を使用した。

## 実行手順

1. 更新後の`persistent-purpose-review`を`--target agent-skills --global`でGrokのuser scopeへ導入した。
2. 隔離configへ`PurposeReviewRunner.FakeProvider`の実行ファイルを指定し、config/state pathは環境変数でこの試験だけへ向けた。
3. `PURPOSE_REVIEW_FAKE_PROVIDER_DELAY_MS=45000`でFacade CLIからGrok headlessを1 prompt turn起動した。
4. promptはstatus確認を1回の前景terminal callに限定し、`RUNNING`時だけ15秒以下の別callでwaitした。
5. `do {}`、`while ($true)`、Grok `monitor`、long-running background taskを禁止した。
6. `FINDINGS / terminal:false`を受けたら同じrunへ`continue`し、分割pollingをterminal状態まで継続した。

## 隔離delay fixtureの観測

| call | UTC開始 | 実時間 | 結果 |
| --- | --- | ---: | --- |
| start | 2026-11-14T13:10:19.4587318Z | 395 ms | `RUNNING / terminal:false / round 1` |
| status 1 | 2026-11-14T13:10:39.5608553Z | 115 ms | `RUNNING / terminal:false` |
| wait 1 | 2026-11-14T13:10:47.7770086Z | 15007 ms | 前景で完了 |
| status 2 | 2026-11-14T13:11:26.2682692Z | 144 ms | `FINDINGS / terminal:false / findings 1` |
| continue | 2026-11-14T13:12:11.7853811Z | 484 ms | `RUNNING / terminal:false / round 2` |
| status 3 | 2026-11-14T13:12:22.7421912Z | 136 ms | `RUNNING / terminal:false` |
| wait 2 | 2026-11-14T13:12:29.1923947Z | 15012 ms | 前景で完了 |
| status 4 | 2026-11-14T13:12:51.8110541Z | 133 ms | `RUNNING / terminal:false` |
| wait 3 | 2026-11-14T13:12:56.7186115Z | 15005 ms | 前景で完了 |
| status 5 | 2026-11-14T13:13:20.1378142Z | 114 ms | `COMPLETE / terminal:true` |

最初の`RUNNING`から`FINDINGS`を返したstatus call開始まで66.409秒であり、レビュー開始から30秒以上`RUNNING`を経たケースを満たした。statusとwaitは別々のterminal callで、全callのexit codeは0、`timed_out`はfalseだった。raw Facade eventsに`monitor`またはbackground task callはなく、Facadeはexit code 0で終了した。

## 結果

- PASS: Grok Build headlessは30秒超の`RUNNING`期間を同一prompt turnで維持した。
- PASS: `FINDINGS / terminal:false`を検出し、その結果を処理した。
- PASS: 同じrun IDでround 2へ`continue`し、`reviewRounds: 2` / `durableSubmissions: 2`で`COMPLETE`になった。
- PASS: status commandと15秒waitは独立した前景callで、前景timeout/background化を起こさなかった。
- PASS: `monitor`、long-running background task、turn終了後の再起床は使用しなかった。
- PASS: Facadeの5分無出力回収は発火せず、Facade CLIは0で完了した。
- NOT_RUN: 実際に15分全部を連続して待つwall-clock試験。deadline pre-checkとremaining time capはpackage validatorで確認した。

## 実providerの追加確認

同じ分割polling SkillをGrokのuser scopeへ再installし、隔離config/envを外した実providerでも新規taskKey `issue-167-grok-short-poll-real-provider-smoke`を実行した。

- configured provider: Codex / model `gpt-6-astra` / reasoning effort `medium`
- Facade run: `20261114T134236Z-ac54aaa1`
- Grok session: `44a4b24c-4536-4252-8330-02dfec2f5cb5`
- Purpose Review run: `b4326f23-487b-4119-82ac-e6e9f4e55c2d`
- round 1: `start 13:43:24Z -> RUNNING`
- same-turn polling: `status 13:43:35Z -> RUNNING`、独立15秒wait、`status 13:44:02Z -> FINDINGS / terminal:false / findings 1`
- 同じrunへ`continue 13:44:43Z -> RUNNING round 2`
- `status 13:45:08Z -> COMPLETE / terminal:true / findings 0`
- `reviewRounds: 2`、`durableSubmissions: 2`
- status、wait、continueはすべて独立した前景callで終了し、monitor/background callは0件
- Facade exit code 0

実provider確認では最初の`RUNNING`から`FINDINGS`まで約38秒で、45秒fixtureより短かったが、同じ短いstatus/wait分離とsame-turn継続を実provider経路でも確認した。

## 非保証

この結果はPurpose Reviewのcaller経路とRunner protocolに関する限定的なruntime evidenceであり、reviewer providerの品質、実装適合、ユーザー承認、production release readinessを保証しない。
