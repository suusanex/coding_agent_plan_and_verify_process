# Goal Context: 複数コーディングエージェントを統合運用する Control UI / Execution Broker

現在、Codex、GitHub Copilot、OpenCodeなど複数のコーディングエージェントのサブスクリプションを用途・利用枠・モデル特性に応じて使い分けている。しかし、各エージェントをそれぞれのAppやCLIから個別に操作すると、並行している作業の把握、完了通知、結果確認、再開なども実行環境ごとに分散する。利用するエージェントの種類が増えるほど、どの作業がどこで動いていて、どれが終わったかを人間が管理する負担が大きくなる。

一方、`coding_agent_plan_and_verify_process` ではCompletion Notification / Runtime / Local Spool / Inboxを通じ、複数のAI作業を並行させても完了や結果を一か所で認識しやすくする方向を進めている。この価値を、特定の一つのコーディングエージェントだけに限定せず、多数のエージェントを使い分ける実運用へ拡張したい。

## 全体として実現したいこと

人間が日常的に操作するControl UIを一つに寄せながら、実際のコーディング作業にはCodex、GitHub Copilot、OpenCodeその他の外部エージェントを選択して利用できる構成を作る。

Control UIで人間と対話する親エージェント自身がすべての実装を担当する必要はない。親エージェントは、対象作業と利用するworkerを決めて実行を依頼し、実作業は各エージェントのCLIや将来のprotocol adapterを通して独立して実行できるようにする。

これにより、利用者から見た主たる操作場所、並行作業の把握、完了通知、結果回収などはできるだけ統一しつつ、実際に利用するコーディングエージェントは、サブスクリプション残量、モデル特性、作業内容などに応じて柔軟に変更できる状態を目指す。

最終的に重要なのは、特定providerを統合すること自体ではなく、

* 多数のコーディングエージェントを同時並行で実用的に使い分けられること
* 人間が各CLIや各Appを常時監視する必要を減らすこと
* 作業の起動、状態把握、完了通知、結果回収などを共通の操作面から扱いやすくすること
* Control UIやworker providerを将来交換できるよう、特定の一つの組み合わせへ過度に固定しないこと

にある。

## 全体構成について確定している方針

Control UIとworkerの間には、provider-neutralなAgent Execution Brokerまたは同等のExecution Runtime層を設ける方向とする。

概念上は次の構成を目指す。

```text
Control UI / parent agent
        ↓
Agent Execution Broker
        ↓
provider-specific adapter
        ↓
Codex / GitHub Copilot / OpenCode / other workers
```

親エージェントが各CLIプロセスを直接長時間抱えて終了まで待つ構成を最終形にはしない。長時間実行、run identity、状態保持、終了判定などはControl UIの一つのturnやprocess lifetimeから切り離せる構造を目指す。

Brokerは特定Control UI専用の内部機構とはせず、将来的には別のControl UIからも利用可能なprovider-neutralな境界を持たせる方向とする。ただし、最初から複数Control UIへ対応する必要はない。

workerとの接続方式は一種類へ固定しない。provider固有のrich protocolが有利ならそれを使い、ACPが適切ならACPを使い、それらが未対応または導入コストに見合わない段階ではprogrammatic CLIを利用できる構造を想定する。

ACPは有力な将来手段ではあるが、v0完成の必須条件とはしない。ACP対応そのものを目的化せず、実運用でCLI adapterの制約が問題になったときに置き換え・拡張できるようにする。

Completion Notification / Runtime / Local Spool / InboxはAgent Brokerそのものへ統合して巨大なumbrella runtimeにするのではなく、実行系からterminal event等を受け取る共通のevent / notification planeとして再利用する方向とする。既存のCompletion Notification packageをgeneric agent orchestratorへ変えることは目的ではない。

既存のLocal Spool / Inboxで確立している、producerとconsumerの責務分離や、observed factとagent-reported resultを混同しない考え方は維持する。

## Control UIについて確定していること

最初のControl UIはCodex Appとする。

Operational v0の段階では他のControl UIとの比較評価は行わず、Codex Appを人間との主たる対話・指示面として利用する。

ただし全体アーキテクチャとしてCodex Appへ永久固定することを意味しない。Broker側は将来別clientから利用できる余地を残す。

## Operational v0の目的

最初の実装は、技術成立だけを確認して捨てるPoCにはしない。

不完全でも、現在の「複数のCLI/Appを人間が個別に起動・監視・管理する」運用より便利な状態になった時点で実運用へ投入し、そのv0を実際の開発に使いながら次の改善を進める。

ここでいう「不完全でもよい」とは、動作しなくてもよいという意味ではない。主要な作業経路は実際に利用可能でなければならない。一方、最終的には自動化される可能性が高い処理の一部が、v0では手動コマンド実行、ログ確認、コピー＆ペーストなどになっていても、それによって現状より実用上の負担が減るのであれば許容する。

v0自体の後続開発にもAIコーディングエージェントを使用するため、v0が早期に実用化されれば、その後のシステム自身の開発も加速できることを重要な狙いとする。

したがってv0の成功は、「CLI processを起動できてIDを返せた」ことではない。少なくとも実際の開発作業をworkerへ任せ、利用者がその終了を認識し、結果を回収して次の行動へ進めるところまで一連の実運用として成立する必要がある。

## Operational v0で成立させる利用体験

代表的な利用は次のようなものを想定する。

人間がCodex Appで親エージェントに、

```text
このworktreeでIssue #123をGitHub Copilot CLIに実装させて
```

などと依頼する。

親エージェントはBrokerへ作業を登録し、worker実行を開始する。workerの処理中、Codex App側の親turnがそのprocess終了まで占有され続ける必要はない。

利用者は別の作業へ移れる。

workerが終了したら、その事実が共通のnotification経路を通してLocal Inbox等から認識できる。

その後、利用者はCodex Appでrunの結果や保存されたoutputを確認し、レビュー、追加指示、手動resumeなど次の行動へ進める。

この一連の流れを本物の開発Issueで使える状態にする。

## Operational v0で必要と判断している能力

v0では少なくとも、Codex AppからBrokerを通してworkerを開始できる必要がある。

worker providerと対象working directory、実行するpromptを指定でき、親Control UIから切り離して非同期に実行できる必要がある。

各実行にはrun identityを持たせる。実行状態や結果をBroker processの一時的なmemoryだけに依存させず、Control UIやBrokerの一部が終了・再起動しても後から実行履歴や結果を確認できるよう、run情報とoutputを永続化する方向とする。

少なくともstdout / stderr等、workerが何を返したか確認できる情報を保存し、run終了後にCodex App側からその結果を読み取れるようにする。

worker processの終了を観測し、正常終了・異常終了など観測可能な事実を記録する。

workerの終了は共通のnotification経路へ接続し、Local Spool / Inbox等から利用者が完了を認識できるようにする。この完了通知はv0の主要価値の一つであり、後回しにしない。

ただし、processの正常終了を「Issueの実装が意味的に完全成功した」と自動的に同一視しない。process exit等のobserved factと、agent自身が報告するimplementation result等は区別する。

v0のBroker APIは最初から完全なsession abstractionを作る必要はない。`start_run`、run状態取得、run一覧、output取得、cancel等、実利用に必要な小さなsurfaceから始めてよい。

## Operational v0では自動化を必須としない事項

v0で最終形まで自動化する必要がないものとして、少なくとも以下がある。

worktreeの作成やcleanupは、必要であれば当初はCodex App側の親エージェントや既存のGit操作へ任せてよく、Broker自身が完全なworktree managerを持つことはv0の必須条件ではない。

provider固有sessionへの追加指示やresumeは、v0で完全な共通APIになっていなくてもよい。必要ならresume commandを表示して人間または親エージェントが手動で実行するなどの経路でも、現状より実用的なら許容する。

workerが人間への質問待ち状態になったことを完全に自動判定する機能もv0の必須条件ではない。run outputを確認して質問待ちだったことを判断し、手動で続きを実行する形でもよい。

PR URLやartifact等のresult自動検出、provider別usage / cost集計、providerの自動選択、worker間dependency orchestration、自動retry / recovery、ACP対応もv0必須ではない。

これらは実運用後に実際の摩擦が大きい順に改善候補とする。

## v0の開発方法についての方針

v0完成後に初めて実運用を始めるのではなく、最初のend-to-end経路が実用可能になった時点から本物の開発作業で利用する。

可能ならBroker自身またはこのrepositoryの次の開発Issueをworkerへ委譲し、v0自身を使ってv0以降を開発する。

その運用から得られた実際の不便を基準として、resume、WAITING_FOR_USER検出、ACP化、provider adapter改善、worktree管理などの次の優先順位を決定する。

したがって、あらかじめ固定された大規模なv1/v2ロードマップを完遂することより、早期にOperational v0を成立させ、実測された問題へ順次対応することを優先する。

## 現時点での前提・再検証が必要な事項

Codex AppからローカルのBrokerを操作する具体的なintegration surfaceとしてMCPを使う案が有力であり、これまでの検討では実現可能と考えている。ただし、v0の具体設計ではCodex Appからの接続方法、process lifetime、権限、起動方式等を改めて実装可能な形に落とし込む必要がある。

各worker CLIのprogrammatic invocation、session identity、終了時のobservability、resume能力等はproviderごとに異なるため、v0で正式対応するproviderについて具体設計時に実能力を確認する必要がある。

GitHub Copilot CLIについては、既存Issue #70でObserved Source Adapter / Agent-reported Source Adapter / bounded manual alternativeのいずれが成立するかを証拠付きで判断する方針がすでにある。現在の公式機能からObserved Source Adapterが成立する可能性は高いという作業仮説があるが、実機確認前に確定事項として扱わない。

Local Spoolの現在のschemaはCodex callback由来のidentityや`resume_uri`を前提としているため、複数providerを扱うにはschema evolutionが必要になる可能性がある。既存schemaを無理に流用して他providerをCodexとして偽装しないことは維持するが、具体的に後方互換extensionと新versionのどちらを選ぶかは未決定である。

## 意図的に後続設計へ残している事項

Operational v0で最初に正式対応するworker providerの範囲と順序は、まだ最終確定していない。

Brokerの具体的なprocess構成、常駐方式、detached runnerの実装方法、永続化formatと保存場所、MCP serverとのlifetime分離方法は後続のv0設計で決める。

Local Spool / Inboxとの具体的なevent schema、既存Issue #70との実装上の統合・分割方法も後続設計対象とする。

Codex、Copilot、OpenCode等のnative protocol / ACP / CLIのどの接続方式を各providerで最終採用するかは、v0では必要最小限だけ決め、その後の運用結果に応じて変更できるようにする。

将来Control UIをCodex App以外へ交換・追加する可能性は残すが、その比較・対応はOperational v0の目的には含めない。
