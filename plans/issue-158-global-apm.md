# Issue #158: APMのuser-global専用化

## 目的と範囲

[Issue #158](https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/158)のGoal / Decision Contextを正本とする。Adaptive、Design Pair、Plan Coverage、PR Review Remediation、Goal Context Authoring、Persistent Purpose Reviewと内部依存Finalizerをglobal前提へ統一する。Decoratorは撤去し、独立した通知Runtime、Inbox、PurposeReviewRunnerは保持する。各processの起動条件・役割・handoffは変えない。

## 設計と分担

- APMがglobal Skill / portable agentを配布する。独自installerやlocal互換経路は追加しない。
- Finalizerはglobal modulesとCodex homeを解決し、portable contract照合後に対象の3profile fieldsだけを補完する。agent本文、独自key、commentは保持し、衝突・不一致はforceでも修復しない。親はprofile継承を検査する。
- Plan Coverage共有guardrailはpackageの`docs/plan-coverage-shared-guardrails.md`を正本とし、14agentのmarker区間へ全文を内包する。検証で一致を確認し、global Copilot instructionsへは配布しない。
- 旧local配置の整理はownershipと独自編集を確認して利用者が行う。2つのrepositoryでlocal installなしにglobal資産を利用できることを切替完了条件とする。
- 親が設計、Skill / agent文面、文書、統合、レビュー判断とGit操作を担当する。C#実装・テストはGPT-6 Lunaが担当する。Adaptive Implementationは選択していない。

既存C#、BCL、TomlynとAPM配布機構を再利用する。新しい設定基盤や独自配布方式は導入しない。

## 目的・設計レビュー

Runner 0.6.0 / protocol 4を使用。run IDは`26d53aee-35d5-4a40-846f-a790f10cb084`、taskKeyは`issue-158-global-apm`、changeIdは`global-only-initial-design`。

初回のPUR-001（Finalizerの本文上書きとprofile-only制約の不整合）は、APMの配布責務とFinalizerの補完責務を分離して対応した。PUR-002（旧localからの移行経路不足）は、整理対象・保持対象・2repositoryでの完了条件を追加して対応した。同一runの2ラウンド目で`COMPLETE`、累積`reviewRounds: 2`、`durableSubmissions: 2`、残存findingなしとなった。

この結果は目的・設計レビューの完了であり、ユーザー承認、実装適合、テスト成功、実行時保証を意味しない。

APM v0.26.0の隔離実測で、global storeはOSユーザーホームの`.apm`、agent配布先は`.codex/agents` / `.copilot/agents`、Skill配布先は`.agents/skills`と確認した。APMは非標準`CODEX_HOME` / `COPILOT_HOME`へagentを出力しないため、正式運用を標準runtime homeに限定する。Finalizerは`CODEX_HOME`を解決し、投影がなければ失敗する。手動コピーで補完しない。

この利用条件を重要な設計具体化として、同一taskKey、changeId `global-layout-supported-operation`、previousRunIdに上記COMPLETE runを指定して追加レビューした。run `22aef28d-de4e-41b1-8d3e-d78b1bad268c`は1ラウンド目で`COMPLETE`、`reviewRounds: 1`、`durableSubmissions: 1`、findingなしとなった。作業パスの変更後も初回のrepository識別パスを指定し、同一lineageを維持した。

## 実装後の受入

隔離homeでのglobal install、依存closure、対応target、profile補完・check・再実行・update後の再補完・uninstall、2repositoryでの共通利用、無関係なfileの保持と衝突拒否を検証する。既存semantic validators、repository layout、文書導線、通知Runtimeの検証を行う。実測のAPM版とhome規則、実行結果を記録する。

変更をcommit / pushしReady PRを作成後、`pr-review-remediation`でremote review、inline / PR comments、checksを収集する。親が全sourceを評価し、必要なC#修正・テストはユーザー指定に従いLunaへ委譲する。

## 検証の現在地

GPT-6 LunaがFinalizer単体、global APM導入後のFinalizer実行、help表示を検証した。公式APM v0.26.0でglobal install検証を再確認した。Adaptive routing / static、Design Pair static、Plan Coverage static / full-coverage source E2E、Architecture Slice Readinessの8 fixtureと9 contract hashes、PR / Persistent Purpose static、repository layout、README導線、process boundary self-test / validateが成功した。

公式APM v0.26.0で全7 Agent Plugin packageのbuild / validationとqualification整合が成功し、Plan Coverage専用plugin validatorの13 negative mutationも検出した。Qualificationの実runtime状態はNOT_RUN / HOLDを維持し、静的内包をruntime動作確認として記録していない。独立した通知Runtimeの隔離単体検証も成功した。

APM v0.33.0では既存plugin buildのlocal-bundle install経路が拒否されることを確認した。検証対象のv0.26.0とは区別する。FinalizerのNativeAOT publishはこの環境のC++ build tools不足で失敗したが、必要な実行・コンパイル検証は`dotnet run`で成功している。NativeAOT配布の追加は本変更の対象外とする。

候補`9b2bd5cb746aa20949776f4fcec8766d764a6044`を公式APM v0.26.0で検証し、6対象packageのremote global lifecycleがすべて成功した。各独立target、mixed install / reinstall、Finalizer再実行と再補完、update、2つのGit repositoryからのglobal metadata / assets参照、uninstall、無関係sentinel保持を確認した。Plan Coverageのinstalled-root full-coverage E2Eと14agentへのguardrail到達も成功した。同候補のGitHub Actions全checkも成功した。

Ready PRは[#171](https://github.com/suusanex/coding_agent_plan_and_verify_process/pull/171)。GitHub Copilot reviewを要求し、remote evidenceを収集中である。実モデルによるprocess runtime qualificationは実行せず、既存NOT_RUN / HOLDの区別を維持した。

Finalizerの統合レビューで、TOML本文内のsection風テキスト、quoted key、multiline profile値を独自の行走査で誤認する可能性を確認した。既存Tomlynのsyntax treeと値spanを再利用し、対象profile値だけを置換するようLunaが修正した。未知field、comment、本文、改行を保持する回帰検証も成功した。独自TOML lexerの追加は行っていない。

remote lifecycleの初回実測で、APM v0.26.0は候補SHAに固定した依存のupdateを拒否することを確認した。この終了コード1を成功へ読み替えず、更新可能なbranch refによる正常updateを別途実測して成功を確認した。配布smokeはbranch headと候補SHAの一致を開始時とupdate後に確認し、独立target導入をSHA、正常lifecycleを同じ候補のbranchで検証する。検証中にbranchが変化した場合は失敗とする。

APMのfrozen reinstall後にprofile補完が失われる観測に合わせ、smokeの順序を「Finalizer単独再実行のhash不変」と「APM再install後のFinalizer再補完」に分けた。旧順序の失敗は失敗として記録し、再補完後のcheck成功で受入を検証する。

隔離homeでAPM v0.26.0の初回同名agent衝突も確認した。Codex TOML / Copilot agent markdownとも管理外の既存本文を保持し、installはskipメッセージ付きで終了コード0となった。このため正式手順ではskip出力を確認し、衝突を解消してからprocessを開始する。

追加の削除検証では、refなしで導入したPR Review Remediationを同じ完全source specで削除し、module / Skillの消滅を確認した。AdaptiveはFinalizerでprofile補完した後でも、APM uninstallが2 package、管理対象4 agent、3 integrated Skillを削除し、無関係sentinelを保持した。短縮名ではuninstallできないため、正式文書も完全source specへ補正した。Windows追加probeでAPM Python readerにcp932 decode例外の出力があったケースは、終了コード0・実配置・削除後のpath不在を別々に確認し、検証ログへ記録した。
