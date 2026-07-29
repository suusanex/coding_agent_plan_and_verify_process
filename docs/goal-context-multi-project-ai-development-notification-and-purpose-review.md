---
document_type: goal-context
repository: suusanex/coding_agent_plan_and_verify_process
status: conversation-final
created_at: 2026-07-25
source_repositories:
  - https://github.com/suusanex/coding_agent_plan_and_verify_process
  - https://github.com/suusanex/codex_copilot_pr_review_agent
scope: multi-project AI development, goal-context portability, PR review, completion notification, and actionable links
---

# 複数プロジェクトAI開発の通知・目的レビュー連携

## 1. この文書の目的

この文書は、個別Issueへ分割する前の**全体構想、必要になった経緯、設計判断、MVP境界、棄却した案、未確定事項**を引き継ぐためのGoal Contextである。

後続の設計担当、実装担当、レビュー担当が元のChatGPT会話を参照できなくても、少なくとも次を判断できる状態を目指す。

- 何を作るのかだけでなく、なぜ必要なのか
- 全体目的を達成するために、どの成果物を新しく作るのか
- どの既存プロセスを変更せず再利用するのか
- どの既存リポジトリを取り込み、どの部分を拡張するのか
- 共通の通知デコレータと、具体的な開発プロセスをどう区別するのか
- 何を自動化し、何を手動のまま残すのか
- 形式上動いていても、本来の目的を達成していない実装は何か
- MVPと将来拡張をどこで分けるのか

この文書はIssue一覧、実装Plan、タスク分解ではない。後続のIssue分割、Plan作成、実装、レビューにおける判断基準を提供する。

## 2. 記述上の区分

本文では、情報の確度を次のように区別する。

- **明示事項**: 利用者が会話中に直接示した要求、制約、訂正、決定
- **採用判断**: 会話中の提案に対して、利用者が明示的または文脈上明確に受け入れた設計方針
- **作業仮説**: 実現方法として有力だが、実装前の検証や選定が必要な案
- **未確定**: 会話では結論を出しておらず、後続設計で決める事項

## 3. Executive intent

### 3.1 全体目的

**明示事項**

複数のソフトウェアプロジェクトで、次のようなAI支援開発サイクルを並行して回している。

1. ChatGPTで、実現したいこと、背景、制約、MVP境界を検討する
2. 検討結果からGitHub Issueを作成する
3. Codexで実装する
4. CodexからPull Requestを作成する
5. GitHub Copilotレビューを行う
6. 初期検討の目的コンテキストを理解する、実装担当とは独立したAIで目的達成レビューを行う
7. レビュー結果をCodexへ渡して修正する
8. 必要に応じて検証、再レビュー、追加修正を行う

複数プロジェクトを併走すると、Codex、GitHub、ChatGPTなど複数のアプリやWebサイトを順番に見回り、各処理が終わったか確認し、終わったものを次の操作へ回す必要がある。

この**見回りと戻り先探索の負担**を減らし、各手動工程を開始するべきタイミングに、正しい作業場所へすぐ戻れるようにすることが本来の目的である。

### 3.2 求める利用体験

**明示事項**

最低限、次を実現する。

1. 各AI作業の完了または停止を検出して通知する
2. 通知から、その作業が行われた対象スレッド、レビュー、PR、実行結果などを直接開ける

単なる「終わりました」という通知では不十分である。通知を押した後に、再びアプリ、リポジトリ、PR、スレッドを探す必要があるなら、本来の問題は十分に解消されない。

**明示事項・望ましい拡張**

通知履歴がタイムライン状に蓄積され、見逃した完了イベントを後から確認できると望ましい。ただしMVP必須条件は、まず**完了通知と対象を直接開けるリンク**である。永続タイムラインは重要な拡張候補だが、MVP必須へ勝手に読み替えない。

## 4. 問題の本質

### 4.1 見回りコスト

**明示事項**

個々のCodex実行やPRレビューに時間がかかること自体よりも、次の認知負荷が問題になっている。

- どのプロジェクトの何が実行中か覚えておく
- Codexアプリ、GitHub、ChatGPTを順番に確認する
- 完了または停止した処理を見つける
- 該当リポジトリ、PR、レビュー、スレッドを探して開く
- 複数プロジェクトの途中状態を頭の中で維持する

必要なのは、開発工程の全面自動化ではなく、**非同期に進むAI作業を人間が見失わないための観測・通知・復帰導線**である。

### 4.2 目的達成レビューの本質

**明示事項**

従来ChatGPTでレビューしていた理由は、ChatGPTという製品またはモデル名そのものではない。

本質は、Issue本文だけでは失われる次の情報を、最初の相談スレッドが保持していたことにある。

- 最初に困っていた具体的状況
- 実現したい利用体験
- Issue文面へ至るまでの検討
- 採用案と、その判断理由
- 棄却した案と、その理由
- MVPから外したもの
- 「形式上は条件を満たすが、それでは意味が薄い」という否定条件
- 利用者が途中で訂正した優先順位や境界

したがって必要なのは「ChatGPTでレビューすること」ではなく、**初期検討で形成された目的コンテキストを利用できる、実装担当とは独立したレビュアー**である。

## 5. 設計方針の全体像

### 5.1 単一の固定プロセスを新設する構想ではない

**明示事項・採用判断**

本構想は、相談、Issue作成、Plan、実装、PRレビュー、修正のすべてを一度に自動進行する巨大なSkillまたは固定シーケンスを作るものではない。

目的を達成するため、次の3種類の新規成果物と、1種類の移行作業を組み合わせる。

#### 新規成果物A: 完了通知デコレータ

任意の既存Codexプロセスと同じ親ターンに追加し、そのプロセスが完了または停止した時点で通知と復帰リンクを生成する横断機能。

主な構成要素は次である。

- Decorator Skill
- Codexの`notify` callback
- 通知イベントを生成・配送するスクリプトまたはランタイム
- Codex親スレッド、PR、レビューなどを直接開くリンク

#### 新規成果物B: 目的コンテキスト生成手段

ChatGPTで行った初期検討を、後続AIへ引き継げる`goal-context-*.md`へ変換する手段。

主な構成要素は次である。

- ChatGPTへ渡す標準生成プロンプト
- Goal Contextの文書契約またはテンプレート
- 人間による確認項目
- リポジトリへの保存・命名規約

#### 新規成果物C: 目的コンテキスト対応PRレビュー工程とレビュー・修正サイクル定義

既存の`codex_copilot_pr_review_agent`を基礎として、GitHub CopilotレビューとローカルCodexコードレビューに加え、Goal Contextを使う目的達成レビューを行う具体的なPRレビュー工程を作る。

この工程はレビュー結果を整理し、既存のAdaptive Implementationへ渡せる修正計画またはImplementation Intentを生成して停止する。

レビュー反映は、利用者が次のCodex親ターンとして完了通知デコレータ付きAdaptive Implementationを開始する。したがって、論理的な「PRレビュー・修正サイクル」は、新しいPRレビュー工程と既存Adaptive Implementationの二つから成る。

#### 移行作業D: 既存PRレビュープロセスの取り込み

`suusanex/codex_copilot_pr_review_agent`を`suusanex/coding_agent_plan_and_verify_process`へ取り込む。

取り込み時には、既存のレビュー部品を再利用しつつ、`spark-implementer`を削除し、修正実装の正規経路をAdaptive Implementationへ一本化する。

### 5.2 新たに作らないもの

**明示事項**

初回の「Codexで実装」部分には、すでに複数のプロセスが存在するため、新しい実装プロセスを作らない。

再利用対象の例は次である。

- `adaptive-implementation-execution`
- Plan網羅チェック・残件判定フロー
- Design Pair
- Codex-first系の既存入口
- その他、将来追加される独立したCodex開発プロセス

重要なのは、これらを共通の完了通知デコレータと併用できるようにすることである。

### 5.3 各要素の階層

```text
Goal Context生成手段
  └─ ChatGPTの初期検討を goal-context-*.md へ変換する

完了通知デコレータ
  └─ 任意のCodexプロセスへ横断的に追加する

既存実装プロセス
  ├─ Adaptive Implementation
  ├─ Plan網羅チェック・残件判定
  ├─ Design Pair
  └─ その他

目的コンテキスト対応PRレビュー工程
  ├─ PR確認・準備
  ├─ GitHub Copilotレビュー待機・収集
  ├─ ローカルCodexコードレビュー
  ├─ Goal Contextを使う目的達成レビュー
  └─ レビュー結果の整理・修正計画

レビュー反映工程
  └─ 既存Adaptive Implementationが修正計画を実装・検証する
```

次の区別を崩さない。

- **完了通知デコレータ**は、すべての対応プロセスへ追加可能な横断機能
- **Goal Context生成手段**は、初期検討を可搬なレビュー入力へ変換する前処理
- **Adaptive Implementation等**は、既存の実装・検証プロセス
- **目的コンテキスト対応PRレビュー工程**は、PR作成後のレビューと修正計画を作る具体的プロセス
- **レビュー反映工程**は、生成された修正計画を既存Adaptive Implementationで実装・検証する別の手動開始プロセス
- **`local-reviewer`、`purpose-reviewer`、`review-planner`等**は、PRレビュー工程内部の実行部品

### 5.4 全体サイクル

```text
【相談・Issue作成前】

ChatGPTで目的・背景・境界を検討
  ↓
Issue作成
  ↓
Goal Context生成手段
  └─ goal-context-*.mdを生成・確認・repositoryへ保存


【初回実装】

完了通知デコレータ
  ＋
任意の既存実装プロセス
  ↓
完了または停止
  ↓
通知から該当Codex親スレッド等を開く


【PRレビュー】

完了通知デコレータ
  ＋
目的コンテキスト対応PRレビュープロセス
  ↓
GitHub Copilotレビュー、コードレビュー、目的達成レビューを収集
  ↓
修正計画またはImplementation Intentを生成
  ↓
完了または停止通知


【レビュー反映】

利用者が通知から対象へ戻る
  ↓
完了通知デコレータ
  ＋
既存のAdaptive Implementationを開始
  ↓
修正・検証
  ↓
完了または停止通知
```

PRレビューとレビュー反映は論理的には一つのレビュー・修正サイクルであるが、Codex上では二つの独立した親ターンとして実行する。現在の運用にある手動開始境界を保ち、その境界で通知とリンクを利用する。

## 6. Goal Contextの可搬化

### 6.1 ChatGPT会話そのものをシステムの中核へ置かない

**採用判断**

通常のChatGPTチャットは、外部から完了状態や会話内容を安定して取得・監視する公開インターフェースが弱く、システムの中心に置くと他の工程より壊れやすい。

そこで、元のChatGPT会話を後から監視・再利用するのではなく、Issue確定時点で、その会話自身に**目的達成レビュー用のGoal Context Markdown**を生成させる。

このMarkdownをリポジトリへ保存し、後続のCodex、Workspace Agent、その他のAIハーネスが読む。

### 6.2 Goal Contextに引き継ぐ内容

**明示事項・採用判断**

Goal ContextはIssue本文の複製ではなく、少なくとも次を自己完結して保持する。

- Original problem
- Desired outcome
- 利用者が困っていた具体的な状況
- User scenarios
- Scope
- Non-goals
- 採用した判断と理由
- 棄却した代替案と理由
- 制約と不変条件
- 成功シナリオ
- Acceptance evidence
- 形式上は条件を満たしても失敗となる実装例
- レビュー時に確認すべき質問
- Open questionsとassumptions
- 会話で明示された内容と、要約モデルの推論の区別

後続AIが元のChatGPT会話を閲覧できなくても、目的達成レビューを行えることを目標とする。

### 6.3 Goal Context生成プロンプトの責務

**採用判断**

標準生成プロンプトは、ChatGPTに単なる会話要約を依頼するものではない。次を要求する。

1. 会話の初期から現在までを対象にする
2. Issue本文を再掲するだけにしない
3. 重要な訂正と優先順位の変化を反映する
4. 採用案だけでなく、棄却案と棄却理由を保持する
5. MVP、Non-goals、将来課題を分離する
6. 形式上成立しても目的上失敗する例を記載する
7. 明示事項と推論を区別する
8. 不明点を推測で確定しない
9. 秘密情報、認証情報、不要な個人情報を除外する
10. 作成後に会話全体と再照合し、欠落や混同を自己検査する

生成手段には、少なくとも次を含める。

- 再利用可能なChatGPT向けプロンプトファイル
- 期待する章構成
- 生成後に人間が重点確認するチェックリスト
- リポジトリへ保存する手順

### 6.4 完全な自動抽出ではない

**明示された制限を踏まえた採用判断**

AIに会話を要約させても、重要な訂正、棄却理由、暗黙の優先順位などが漏れる可能性はある。したがって、生成物は人間が一度確認することを推奨する。

特に次を重点確認する。

- Desired outcome
- Rejected alternatives
- Superficially compliant but wrong
- MVPと将来課題の境界
- 利用者が強く訂正した事項

### 6.5 命名上の注意

**明示事項・確定決定**

コンテキストを引き継ぐための文書は、他の既存プロセスが作る名称と重なってはならない。また、特定のIssueに紐付く名称にしてはならない。

ファイル名は次の規則とする。

```text
goal-context-<内容を要約した文字列>.md
```

例:

```text
goal-context-multi-project-ai-development-notification-and-purpose-review.md
```

Issue番号、PR番号、単一作業のslugをファイル名の中心に置かない。

## 7. 既存プロセスとリポジトリの扱い

### 7.1 既存実装プロセスは変更せず再利用する

**明示事項・確定決定**

Codexによる初回実装部分は、`coding_agent_plan_and_verify_process`に存在する既存プロセスを任意に選択する。

完了通知を実現するために、Adaptive Implementation、Plan網羅チェック・残件判定、Design Pairなどの内部ロジック、agent契約、handoff契約を変更または複製しない。

完了通知デコレータを、選択した既存プロセスと同じCodex親ターンへ追加して実行する。

### 7.2 `codex_copilot_pr_review_agent`を取り込む

**明示事項・採用判断**

`suusanex/codex_copilot_pr_review_agent`は独立リポジトリとして維持せず、`suusanex/coding_agent_plan_and_verify_process`へ取り込む。

取り込むべき本質は次である。

- 対象ブランチとPRの確認・準備
- PR本文、レビュー、コメント、CI状態の収集
- GitHub Copilotレビューの完了待機と取得
- ローカルCodexコードレビュー
- 複数レビュー結果の整理
- 修正方針・検証方針を含むレビュー計画の作成
- 必要な結果レポート

同じリポジトリへ置くことで、Adaptive Implementation、Plan Coverage、Design Pairなどの既存プロセスと、配布契約、agent契約、artifact契約を共有しやすくする。

元リポジトリをarchiveするか、移行案内用に残すかは未確定である。

### 7.3 `spark-implementer`は削除する

**明示事項・確定決定**

現在の`codex_copilot_pr_review_agent`にある`spark-implementer`は、互換用にも残さず削除する。

理由は次の通り。

- PRレビューフローを単独リポジトリ内で完結させるために存在した部品である
- PRレビューそのものの本質ではない
- Adaptive Implementationに対する独自性がない
- 残すと実装ルート、モデル選択、handoff、検証契約が二重化する
- 互換性を維持する要求がない

レビュー結果は、Adaptive Implementationが受け取れる修正計画、Implementation Intent、または同等のcanonical artifactへ変換する。

### 7.4 基礎版とGoal Context対応版

**採用判断**

取り込み後のPRレビュー機能は、少なくとも概念上、次の二つを区別する。

#### 基礎版PRレビュー

- PR確認・準備
- GitHub Copilotレビュー待機・収集
- ローカルCodexコードレビュー
- レビュー結果の整理
- 修正計画の生成

#### Goal Context対応PRレビュー

基礎版の処理に加えて、次を行う。

- `goal-context-*.md`の選択・検証
- 実装担当とは独立した`purpose-reviewer`による目的達成レビュー
- `review-planner`でGitHub Copilot、ローカルコードレビュー、目的達成レビューを統合
- Goal ContextのMVP、Non-goals、棄却案、否定条件を修正計画へ反映

基礎版とGoal Context対応版を別パッケージにするか、同一パッケージ内の二つのSkillにするかは後続設計で決める。ただし、共有するagent、スクリプト、artifactを複製してはならない。

## 8. 完了通知デコレータ

### 8.1 デコレータであり、オーケストレーターではない

**明示事項・確定決定**

完了通知デコレータは、既存プロセスを選択、起動、分岐、再実装する上位オーケストレーターではない。

既存プロセスと同じCodex親ターンに適用され、親ターンが作業を終えて停止した時点に、通知とリンクを追加する横断機能である。

```text
同一のCodex親ターン
├─ completion notification decorator
└─ 選択された既存プロセス
    └─ 既存custom agents / scripts

親ターン終了
  ↓
Codex notify callback
  ↓
通知イベント
  ↓
通知から対象へ戻る
```

### 8.2 Skill同士の関係

**採用判断**

デコレータSkillが、既存Skillを通常の関数のように呼び出し、型付き戻り値を受け取る構造にはしない。

標準の利用形は、同一プロンプトでデコレータと主プロセスを明示する形とする。

```text
$completion-notification-decorator
$adaptive-implementation-execution

このPlanを実装してください。
```

または、

```text
$completion-notification-decorator
$plan-coverage-residual-flow

この要求を対象にPlan網羅チェック・残件判定を実行してください。
```

一つの通知対象ターンには、通知上の所有者となる`primary_process`を一つ定める。主プロセスが内部で複数agentや補助処理を使うことは妨げない。

### 8.3 デコレータ専用custom agentは作らない

**採用判断**

次のような汎用custom agentは作らない。

- generic process runner
- notification wrapper agent
- whole-cycle orchestrator agent

理由は次の通り。

- 作業本体が別subagent threadへ移り、復帰リンクが曖昧になる
- 既存Skillが持つparent/routerと責務が二重化する
- モデル、sandbox、承認設定の継承関係が増える
- 既存プロセスを変更せず使う目的から離れる

custom agentは各具体的プロセスが所有する。

### 8.4 完了検出はCodex `notify` callbackで行う

**採用判断**

Skillの自然言語指示だけで「最後に通知スクリプトを必ず呼ぶ」ことへ依存しない。

Codex親ターンの完了後に呼ばれる`notify` callbackを、正式な完了検出境界とする。

通知処理は概念的に次を行う。

```text
既存プロセスが完了または停止
  ↓
Codex親ターンが終了
  ↓
agent-turn-complete
  ↓
notifyプログラムが起動
  ↓
デコレータ対象ターンか判定
  ↓
通知イベント生成
  ↓
通知配送
```

`Stop` Hookなど、後続処理によって継続し得るタイミングを最終通知境界として使用しない。

### 8.5 デコレータSkillの責務

デコレータSkillは作業本体を実行しない。責務は次に限定する。

1. 現在の親ターンを通知対象として明示する
2. 通知タイトル、主プロセス、任意の結果URLなど、通知に必要なmetadataを整える
3. 主プロセスの最終verdictを変更せず、機械可読なnotification envelopeを最終回答へ追加する
4. 通知ランタイムがterminal envelopeを取得できない場合は通知を抑止し、中間callbackを完了と誤認しない

概念例:

```yaml
completion_notification:
  schema_version: 1
  primary_process: adaptive-implementation-execution
  observed_status: COMPLETED_BY_HIGH_MODEL
  title: implementation completed
  result_uri: null
```

`observed_status`は主プロセスが返した状態を転記する。デコレータ自身が実装、レビュー、Planの成否を再判定しない。

### 8.6 復帰リンク

通知イベントは、少なくとも次の二種類のリンクを扱える形とする。

```yaml
resume_uri: codex://threads/<thread-id>
result_uri: https://github.com/owner/repository/pull/123
```

- `resume_uri`
  - 現在のCodex親スレッドへ戻るリンク
  - 原則必須
- `result_uri`
  - PR、GitHubレビュー、Actions結果、成果物などを開く任意リンク

通知UIは、`result_uri`が利用可能な場合も`resume_uri`を置き換えず、「結果を開く」と「このタスクを開く」の両操作を提示する。`result_uri`が存在しない場合は`resume_uri`だけを提示する。イベントデータでも両方を保持する。

Codex deep linkの利用可否、対象PC、アプリ版による挙動は、MVP実装前に実機確認する。

### 8.7 Fail-open

通知機能の失敗で、既存開発プロセスの結果を失敗扱いにしない。

```text
process_status: COMPLETED
notification_status: FAILED
```

通知は観測と復帰導線であり、実装、Plan、レビューの正本ではない。

### 8.8 既存プロセスとの具体的シーケンス

#### Adaptive Implementation

```text
利用者
  ├─ completion notification decoratorを選択
  └─ adaptive-implementation-executionを選択
       ↓
Codex親ターン
  └─ Adaptive Implementationを従来どおり実行
       ├─ high-implementation-starter
       ├─ 必要ならstandard-implementation-completer
       ├─ 必要ならHIGH_MODEL re-entry
       └─ terminal verdict
       ↓
親ターン終了
  ↓
notify callback
  ↓
Codex親スレッド等へのリンク付き通知
```

デコレータは、HIGHとSTANDARDの切り替え、acceptance判定、re-entry、検証証拠を判断しない。

#### Plan網羅チェック・残件判定

```text
利用者
  ├─ completion notification decoratorを選択
  └─ plan-coverage-residual-flowを選択
       ↓
Codex親ターン
  └─ 既存フローを従来どおり実行
       ├─ requirement elaboration
       ├─ behavior cases
       ├─ coverage / residual evaluation
       └─ terminal verdict
       ↓
親ターン終了
  ↓
notify callback
  ↓
Codex親スレッドへのリンク付き通知
```

この通知を受けた後にAdaptive Implementationへ進む場合、利用者が次の手動ターンを開始する。次工程の自動起動は本件の要求ではない。

## 9. 目的コンテキスト対応PRレビュー・修正サイクル

### 9.1 二つのCodexプロセスからなる

**明示事項・採用判断**

このサイクルは完了通知デコレータと異なり、PR作成後のレビューと修正に関する具体的な開発工程である。

ただし、一つの巨大なSkillまたは一つのCodex親ターンとして実装しない。次の二つの独立したプロセスから構成する。

1. Goal Context対応PRレビュー工程
   - レビューを収集・実行し、修正計画またはImplementation Intentを生成して停止する
2. Adaptive Implementationによるレビュー反映工程
   - 利用者が別のCodex親ターンとして手動開始し、修正計画を実装・検証する

論理的な全体像は次である。

```text
PR確認・準備
  ↓
GitHub Copilotレビュー待機・収集
  ↓
ローカルCodexコードレビュー
  ＋
Goal Contextを使う目的達成レビュー
  ↓
review-plannerによる統合
  ↓
修正計画 / Implementation Intent
  ↓
Adaptive Implementationによる修正・検証
```

レビュー計画生成後は必ずいったん親ターンを停止し、通知する。

利用者は通知から対象へ戻り、別の親ターンとしてAdaptive Implementationを開始する。この境界は元の運用に存在する手動操作であり、自動化対象へ勝手に追加しない。

この決定により、PRレビュー工程がAdaptive Skillを関数のように内部呼び出す曖昧な設計を避け、既存Adaptive Implementationを変更せず再利用できる。

### 9.2 内部部品の所属

次の部品は、完了通知デコレータではなく、Goal Context対応PRレビュー工程に所属する。

- PR収集スクリプト
- GitHub Copilotレビュー待機・安定判定
- `local-reviewer`または同等のコードレビューagent
- `purpose-reviewer`
- `review-planner`
- review plan / Implementation Intent template
- 必要な結果レポート

### 9.3 ローカルコードレビュー

既存の`local-reviewer`は、PRのbase/head差分を中心に、次を扱う。

- バグ
- 仕様逸脱
- テスト不足
- 運用上のリスク
- 保守性上の問題

Goal Context対応版でも、この責務を目的レビューへ吸収しない。

名称を`code-reviewer`へ変更するか、`local-reviewer`を維持するかは移行設計で決める。名称は共通デコレータの設計に影響しない。

### 9.4 `purpose-reviewer`

`purpose-reviewer`は、実装担当とは独立した読み取り専用agentとする。

入力は少なくとも次を含む。

- 対象PR
- PRのbase/head差分
- Issueまたは要求
- 対応する`goal-context-*.md`
- 対象リポジトリの規約
- 必要に応じて検証結果

主な確認事項は次である。

- Original problemが解消されているか
- Desired outcomeが利用シナリオ上達成されているか
- Issueの字面だけを形式的に満たしていないか
- 棄却済みの代替案を説明なく再導入していないか
- MVPと将来課題を混同していないか
- Non-goalsを実装へ持ち込んでいないか
- Goal Contextにない要求を勝手に追加していないか
- 不明点を推測で確定していないか

### 9.5 `review-planner`

`review-planner`は、次を統合する。

- GitHub Copilotレビュー
- ローカルCodexコードレビュー
- Goal Contextによる目的達成レビュー
- PRコメント
- CIまたはチェック状態

出力には少なくとも次を含める。

- 指摘ごとの採用・不採用判断と理由
- 重複指摘の整理
- 指摘間の競合
- 修正順序
- 修正scope
- Non-goals
- acceptance
- validation expectation
- 未取得レビューまたは未検証事項
- Adaptive Implementationへ渡せる修正計画またはImplementation Intent

### 9.6 Adaptive Implementationへの引き渡し

**明示事項・採用判断**

修正実装は`spark-implementer`ではなく、既存のAdaptive Implementationを使用する。

レビュー計画は、少なくとも次を判断できる形へ正規化する。

```yaml
implementation_intent:
  goal:
  scope:
  non_goals:
  acceptance:
  constraints:
  validation:
  plan_reference:
```

Adaptive Implementationの内部ルーティング、agent、verdict、handoff契約を、PRレビュープロセス側へ複製しない。

### 9.7 通知付きシーケンス

複数roundを明示した場合、次のreview構成を固定する。

- PRごとにReview ThreadとImplementation Threadの二つのCodex親タスクを登録し、異なるtask IDを要求する。同じroleの次工程は同じtaskを再開した新しい明示ターンとして実行する。
- 「別の親ターン」はreviewとimplementationの操作境界を指し、同じroleでも毎回新しいtaskを作ることを意味しない。reviewからAdaptive、Adaptiveから次reviewを自動起動しない。
- round 1はGitHub Copilotレビュー、`local-reviewer`、`purpose-reviewer`を実行し、`review-planner`で統合する。
- round 2以降は最新PR identityと正本diffをcollectorで取得するが、GitHub Copilotレビューを開始・待機せず、`local-reviewer`も再実行しない。
- round 2以降に繰り返すreviewerは`purpose-reviewer`だけとする。`review-planner`はfinding遷移、verdict、Adaptive向けplanのprojectionを担当する。
- collectorに残る過去reviewや、想定外のconnector／人間review/comment/checkは理由付き`noAction`の監査証跡として保持し、remediation findingへ直接変換しない。
- purpose-only roundでは前roundまでの全active findingを現在diffに照らして`persistent | resolved`へ分類する。
- round artifactを正本とし、親Review Threadの会話履歴は補助コンテキストとして利用できる。各roundの`purpose-reviewer`などread-only子agentには現在roundの正本artifactを渡し、子agent taskの継続利用は要求しない。
- 初回実装を行ったImplementation ThreadとReview Threadをcycle開始時に固定する。どちらかを再開できない場合はcycle内で代替taskへ移管せず、`BLOCKED`として停止して人の手動操作へ移行する。

通常運用のtask構成は次のとおりとする。

```text
Implementation Thread I
  初回実装
  ← round 1 planを使う明示的な修正ターン
  ← round 2 planを使う明示的な修正ターン

Review Thread R
  round 1 full review
  ← 修正後headに対するround 2 purpose-only review
  ← 再修正後headに対するround 3 purpose-only review

R != I
```

#### PRレビューターン

```text
利用者
  ├─ completion notification decoratorを選択
  └─ Goal Context対応PRレビューSkillを選択
       ↓
PR準備・レビュー収集
  ↓
local-reviewer + purpose-reviewer
  ↓
review-planner
  ↓
修正計画 / Implementation Intentを生成
  ↓
親ターン終了
  ↓
通知
  ├─ resume_uri: Codex親スレッド
  └─ result_uri: 対象PRまたはレビュー結果
```

#### レビュー反映ターン

```text
利用者がhandoffから同じImplementation Threadへ戻る
  ↓
completion notification decorator
  ＋
adaptive-implementation-execution
  ↓
修正計画を実装・検証
  ↓
親ターン終了
  ↓
PRと現在のImplementation Threadへのリンク付き通知
```

Adaptive完了後は、変更後head OIDとAdaptive result referenceに加え、同じReview Threadを再開するURIをhandoff本文へ記録する。Completion Notification Decoratorは現在のtaskと結果へのリンクを表示するだけであり、counterpart taskを選択または起動しない。

## 10. 全体の運用シーケンス

### 10.1 軽量な開発

```text
ChatGPTで相談・設計
  ↓
Issue作成
  ↓
Goal Context生成・確認・保存
  ↓
[手動開始]
通知デコレータ + Adaptive Implementation
  ↓
実装完了・停止通知
  ↓
[手動開始]
通知デコレータ + Goal Context対応PRレビュー
  ↓
レビュー計画完了・停止通知
  ↓
[手動開始]
通知デコレータ + Adaptive Implementation
  ↓
レビュー反映完了・停止通知
```

### 10.2 Plan網羅チェックを使う開発

```text
ChatGPTで相談・設計
  ↓
Issue作成
  ↓
Goal Context生成・確認・保存
  ↓
[手動開始]
通知デコレータ + Plan網羅チェック・残件判定
  ↓
完了・判断待ち通知
  ↓
[手動開始]
通知デコレータ + Adaptive Implementation
  ↓
実装完了・停止通知
  ↓
[手動開始]
通知デコレータ + Goal Context対応PRレビュー
  ↓
レビュー計画完了・停止通知
  ↓
[手動開始]
通知デコレータ + Adaptive Implementation
  ↓
レビュー反映完了・停止通知
```

### 10.3 Design Pair等を使う開発

```text
ChatGPTで相談・設計
  ↓
Issue作成
  ↓
Goal Context生成・確認・保存
  ↓
[手動開始]
通知デコレータ + Design Pair
  ↓
完了・判断待ち通知
  ↓
[手動開始]
通知デコレータ + Adaptive Implementation
  ↓
以後は同じPRレビュー・修正サイクル
```

いずれの場合も、完了通知デコレータは各具体的プロセスの内部処理を所有しない。

## 11. 通知とリンクのMVP

### 11.1 必須要件

**明示事項**

MVPでは、少なくとも次を満たす。

1. 対象Codex親ターンの完了または停止を検出できる
2. 検出後に利用者へ通知できる
3. 通知から対象Codex親スレッドを直接開ける
4. 利用可能な場合は、対象PR、レビュー、実行結果も直接開ける
5. 複数プロジェクト、複数実行が併走しても通知を識別できる
6. 完了、失敗、BLOCKED、人間判断待ちなどを混同しない

次のような通知は要件を満たさない。

- Codexアプリのトップだけを開く
- GitHubのリポジトリトップだけを開く
- PR番号やスレッド名を表示するだけでリンクがない
- 通知から一覧を開き、さらに検索を要求する

### 11.2 最小イベントデータ

**作業仮説**

```json
{
  "schema_version": 1,
  "source": "codex",
  "primary_process": "adaptive-implementation-execution",
  "observed_status": "COMPLETED_BY_HIGH_MODEL",
  "occurred_at": "2026-07-25T14:32:00+09:00",
  "title": "repository-name: implementation completed",
  "repository": "owner/name",
  "resume_uri": "codex://threads/...",
  "result_uri": "https://github.com/.../pull/123",
  "source_event_id": "..."
}
```

service-localなthread ID、turn ID、review ID等は、重複抑止とリンク生成に必要になり得る。ただし、これを理由にグローバルなタスク依存グラフをMVPへ持ち込まない。

### 11.3 タイムライン

**望ましい拡張**

見逃したイベントを確認できる時系列履歴は有用である。

ただし初期MVPでは、通知と直接リンクを優先する。タイムラインを実装する場合も、まずは受信イベントの履歴とし、プロジェクト管理ボードまたは依存関係グラフへ膨張させない。

## 12. 手動のまま残す境界

### 12.1 ChatGPTでの相談とIssue作成

初期相談、設計の確定、Issue作成は手動のまま残す。

Goal Context生成プロンプトは、この手動相談から再利用可能な成果物を作る補助手段であり、相談またはIssue作成そのものを自動化しない。

### 12.2 Planモードから実装モードへの移行

**明示事項・確定決定**

Planモードから実装へ自動的に切り替えることは、今回の設計で考慮しない。

- 既存の各プロセスもこの切り替えを実現していない
- 現在も利用者が手動で行っている
- 今回の要求は、その手動操作を自動化することではない
- ここを課題として扱うと、通知とリンクという本来の目的から外れる

### 12.3 次工程の開始

通知は、次工程を勝手に開始するためのものではない。

次はMVP対象外である。

- 完了イベントから次工程を自動選択する
- 人間の確認なしに次のCodexターンを起動する
- 任意の工程間で汎用的な次タスク入力を生成する
- プロジェクト横断の依存関係を判断して自走する

PRレビュープロセスが修正計画を生成することは、その具体的プロセス内の責務である。ここで除外するのは、任意の工程をつなぐ汎用オーケストレーションである。

## 13. MVPの範囲

### 13.1 MVPに含めるもの

- 完了通知デコレータSkill
- Codex `notify` callbackと通知ランタイム
- Codex親スレッドへの直接リンク
- 利用可能な場合のPR、レビュー、実行結果リンク
- 複数リポジトリ、複数実行を識別できる通知
- Goal Context生成用のChatGPTプロンプト
- Goal Contextの文書契約、確認手順、命名規則
- `codex_copilot_pr_review_agent`のモノレポ取り込み
- `spark-implementer`の削除
- Adaptive Implementationへ渡せる修正計画契約
- `purpose-reviewer`の追加
- GitHub Copilot、ローカルコードレビュー、目的達成レビューを統合するレビュー計画
- 通知デコレータを少なくとも二つ以上の既存プロセスで利用できることの検証

### 13.2 MVPで必須ではないもの

- 永続タイムラインUI
- 高度なフィルタリングやダッシュボード
- モバイルとPCをまたぐ完全なdeep link解決
- 全工程の自動連続実行
- 通常ChatGPTチャットの外部監視
- 組織全体の権限、監査、マルチユーザー展開
- すべての既存Skillに対する自動適用

## 14. 明示的なNon-goals

次は、本構想の目的ではない。

- Issue作成自体の自動化
- Planモードから実装モードへの自動切り替え
- 人間の判断を省いた自動マージ
- 開発プロジェクト全体を管理する汎用PMツール
- グローバルなタスク依存グラフまたはwork item graph
- 各サービス間の全タスクを自動相関する仕組み
- 任意の次タスクへ渡す入力を自動生成する汎用機構
- ChatGPTの通常会話DOMを前提にした監視を中核へ据えること
- 既存Adaptive Implementation、Plan Coverage、Design Pair等をデコレータ内へ複製すること
- 全サイクルを一つの巨大Skillまたはcustom agentへ固定すること
- デコレータ専用のgeneric workflow runner agentを作ること
- `spark-implementer`との互換性維持
- 通知機能を理由に、既存プロセスの成果物、verdict、handoff契約を曖昧にすること

## 15. スコープ外だが将来検討可能な課題

Non-goalsと異なり、次は将来価値があり得るが、今回のMVPへ混ぜない。

- 通知履歴の永続タイムライン
- プロジェクト別、状態別、未確認別のフィルタ
- Issue、Codex run、PR、レビューの明示的な関連付け
- 完了イベントから次操作候補を提示するHuman Action Queue
- レビュー結果から次工程用入力を自動整形する汎用機構
- 次工程の自動起動
- Workspace Agentまたは他社AIハーネス用アダプター
- GitHub Webhookベースの常駐サービス
- Slack、ntfy、Windows通知、メール等の複数配信先
- リモートPCまたはモバイルからローカルCodexスレッドへ戻る導線
- 組織、チーム向けの権限、監査、共有タイムライン
- デコレータの自動適用ポリシー

## 16. 採用した主要判断と理由

### 16.1 Goal ContextをMarkdownへ固定する

- 通常ChatGPTチャットを外部監視する難しさを回避できる
- Codex、Workspace Agent、他のAIハーネスへ持ち運べる
- リポジトリの変更履歴と一緒に保存できる
- 後日の再レビューでも再利用できる
- 「ChatGPTであること」ではなく「目的を知っていること」を保証しやすい

### 16.2 通知を共通デコレータとして分離する

- Adaptive、Plan Coverage、Design Pair、PRレビュー等へ同じ機能を追加できる
- 既存プロセスの内部契約を変更せず使える
- 通知先を差し替えやすい
- 新しい固定開発シーケンスを作らずに済む

### 16.3 完了検出をCodex `notify`へ置く

- モデルが最後のツール呼び出しを省略するリスクを避けられる
- 親ターンが実際に停止した後を境界にできる
- thread ID等、復帰リンク生成に必要な情報を得やすい

### 16.4 PRレビューリポジトリをプロセスモノレポへ統合する

- 実装、レビュー、検証の重複部品を減らせる
- Adaptive、Plan Coverage、Design Pairとの組み合わせが容易になる
- APM packageとして再利用しやすい
- agentとartifact contractを共通化できる

### 16.5 修正実装をAdaptiveへ一本化する

- 実装ルートの重複をなくす
- HIGH / STANDARDの既存ルーティングを再利用する
- 固定モデル実装agentへの独自経路を廃止する
- 初回実装とレビュー反映で共通の検証・停止契約を使える

### 16.6 コードレビューと目的達成レビューを分ける

- バグ・品質観点と、Original problem・Desired outcome観点を薄めない
- 目的コンテキストを使わない基礎版PRレビューも維持しやすい
- 将来、セキュリティレビュー等を独立して追加しやすい

## 17. 検討したが採用しなかった案

### 17.1 全サイクルを一つの上位Skillへ固定する

**棄却理由**

- 既存プロセスを差し替える自由度が下がる
- 手動境界まで自動化対象として混入しやすい
- デコレータと具体的プロセスの責務が混ざる
- Plan Coverage、Adaptive、PRレビューの内部契約を複製しやすい

### 17.2 デコレータSkillが下位Skillを関数のように呼ぶ

**棄却理由**

- Skill間の型付き関数呼び出しを前提にできない
- 下位Skillの実行と戻り値検証をデコレータが所有することになる
- デコレータがオーケストレーターへ変質する

標準形は、利用者がデコレータと主プロセスを同一ターンで明示する形とする。

### 17.3 generic wrapper custom agentで既存プロセスを包む

**棄却理由**

- 親スレッドとsubagent threadのどちらへ戻るか曖昧になる
- 既存routerと責務が重複する
- モデル、sandbox、承認設定の階層が増える

### 17.4 各既存プロセスを個別に通知対応へ改造する

**棄却理由**

- 同じ通知処理が重複する
- 新しいプロセスを追加するたびに変更が必要になる
- 通知仕様変更の影響範囲が広がる
- 既存プロセスを変更せず使う方針に反する

### 17.5 ChatGPTの元スレッドへ必ず戻ってレビューする

**棄却理由**

- 目的コンテキスト保持には優れるが、通常ChatGPTチャットの外部完了監視が弱い
- システム全体でChatGPTだけ特殊扱いになる
- 他のAIハーネスへレビューを移せない

元スレッドを人間が参照することは禁止しないが、統合フローの必須依存にはしない。

### 17.6 ChatGPTチャットを分岐してレビュー専用に保存する

**棄却理由**

- ChatGPT内のコンテキスト保持には有効だが、監視問題は残る
- CodexまたはWorkspace Agentへ可搬にならない
- リポジトリ側の正式なレビュー入力にならない

### 17.7 Workspace Agentだけでレビューする

**棄却理由**

- 実行状態監視と会話リンクは有用だが、通常ChatGPTで行った初期検討を直接引き継げない
- Workspace Agent固有の設計に固定される
- Goal Contextを用意すれば、Workspace Agentは将来の実行先の一つにできる

### 17.8 ブラウザ拡張で通常ChatGPTを監視する

**棄却理由**

- DOM変更に弱い
- Chat、Work、デスクトップアプリで実装が分かれる
- 回答完了とツール処理完了の判定が不安定になり得る
- Goal Contextをファイルへ移せば中核要件ではなくなる

### 17.9 グローバルなタスク相関と次工程生成をMVPへ入れる

**棄却理由**

- 元の要求は通知と戻り先リンクである
- 完全な関連付けは別の大きな問題になる
- 利用者が求めていない自動化を混入させる
- MVPの価値検証を遅らせる

### 17.10 `spark-implementer`を互換用に残す

**棄却理由**

- 互換要件はない
- Adaptiveと責務が重複する
- 旧ルートが残ると正規の修正実装経路が曖昧になる

## 18. 制約と不変条件

### 18.1 Goal Contextの不変条件

- Issue本文の長文化だけにしない
- Original problemとDesired outcomeを明示する
- 採用判断と棄却判断を理由付きで残す
- MVP、Non-goals、将来課題を分ける
- 明示事項と推論を区別する
- 秘密情報、認証情報、不要な個人情報を含めない
- ファイル名は`goal-context-`で始め、特定Issueへ結び付けない

### 18.2 目的達成レビューの不変条件

- Issue本文の字面だけで合否を決めない
- Goal ContextのOriginal problemとDesired outcomeを優先する
- 棄却済み代替案を説明なく再導入しない
- MVPと将来課題を混同しない
- Goal Contextにない要求を勝手に追加しない
- 不明点はOpen questionまたはhuman decisionとして返す

### 18.3 PRレビューの不変条件

- コードレビューは対象PRのbase/head差分を中心にする
- 未pushまたはPR外の変更を、PRで修正済みとみなさない
- GitHub Copilotレビューが取得できない場合、コメントなしと推測しない
- 修正計画に含めない変更を便乗して行わない
- 検証結果、未検証事項、停止理由を明示する

### 18.4 通知デコレータの不変条件

- 既存プロセスの内部ロジックを所有しない
- 主プロセスのverdictを改変しない
- 通知は対象を識別できるタイトルを持つ
- 可能な限り対象を直接開くURIを持つ
- 完了、失敗、BLOCKED、人間判断待ちを混同しない
- 通知失敗を工程自体の失敗と取り違えない
- 同じイベントの重複通知を抑止できる設計にする
- 通知機能がなくても既存プロセスの成果物と状態判定は壊れない

### 18.5 リポジトリ・配布の不変条件

- 既存packageのsourceをデコレータまたは他のpackageへ複製しない
- APM依存、agent contract、artifact contractで再利用する
- `spark-implementer`を正規ルートへ残さない
- repository固有のビルド・テスト手順は対象repositoryの指示を優先する

## 19. 成功シナリオ

### 19.1 複数プロジェクトの実装完了

1. 利用者が複数リポジトリで異なる既存Codexプロセスを開始する
2. 各ターンに完了通知デコレータを追加する
3. 一つの親ターンが完了またはBLOCKEDになる
4. リポジトリ名と主プロセスが分かる通知が届く
5. 通知を押すと、そのCodex親スレッドまたは関連PRが直接開く
6. 他のアプリやプロジェクトを順番に見回る必要がない

### 19.2 Goal Context生成

1. ChatGPTで設計とIssue文面を固める
2. 標準プロンプトでGoal Contextを生成する
3. 人間が目的、棄却案、MVP境界を確認する
4. `goal-context-<summary>.md`としてrepositoryへ保存する
5. 後続AIが元チャットなしで目的達成レビューを行える

### 19.3 Goal Context対応PRレビュー

1. PRと確認済みGoal Contextが存在する
2. GitHub Copilotレビューを待機・収集する
3. `local-reviewer`がコード上の問題を評価する
4. `purpose-reviewer`がOriginal problemとDesired outcomeを評価する
5. `review-planner`が各レビューを統合する
6. 修正計画がAdaptive Implementationへ渡せる形で生成される
7. 完了通知からCodex親スレッドまたはPRを直接開ける

### 19.4 レビュー反映

1. 利用者がPRレビュー完了通知から対象へ戻る
2. 修正計画を入力として、通知デコレータ付きAdaptive Implementationを開始する
3. Adaptiveが既存契約に従って修正・検証する
4. `spark-implementer`は使用しない
5. 修正完了または停止時に通知される

## 20. 形式上は実装済みでも失敗となる例

### 20.1 通知だけでリンクがない

「Codexが完了しました」と表示されるが、対象リポジトリ、スレッド、PRを利用者が再び探す必要がある。

### 20.2 リンクが粗い

通知を押してCodexまたはGitHubのトップ画面が開くだけで、該当スレッド、PR、レビューへ直接移動できない。

### 20.3 デコレータが固定オーケストレーターになる

Adaptive、Plan Coverage、PRレビューを選択・起動する巨大な上位Skillを作り、既存プロセスを単独利用または差し替えしにくくする。

### 20.4 各既存Skillを個別改造する

通知機能を追加するために、Adaptive、Plan Coverage、Design Pair等へ同じ通知コードや指示を埋め込む。

### 20.5 目的レビューがIssueの再読に退化する

`purpose-reviewer`がGoal Contextを読まず、IssueのAcceptance Criteriaだけをなぞる。

### 20.6 Goal ContextがIssueのコピーでしかない

検討理由、棄却案、否定条件、優先順位がなく、元の相談スレッドでレビューしていた価値を再現できない。

### 20.7 `spark-implementer`が残る

旧ルートとAdaptiveルートが併存し、修正実装の正規経路が曖昧になる。

### 20.8 自動化範囲を広げすぎる

Planから実装への自動切り替え、タスク相関、次工程自動起動に時間を使い、通知と直接リンクが未完成のままになる。

### 20.9 タイムラインを作ったが通知が弱い

立派なWebダッシュボードはあるが、工程完了時に通知されず、結局利用者がダッシュボードを見回る必要がある。

### 20.10 完了判定が曖昧

Codexの親ターン終了を、Issueまたはプロジェクト目的の完全達成と表示する。イベント名は、観測できた事実と主プロセスのverdictを正確に表す必要がある。

## 21. レビュー時に必ず確認する質問

### 21.1 全体目的

- 複数アプリを見回る回数は実際に減るか
- 通知を押した後、追加検索なしに対象へ戻れるか
- 自動化していない手動工程を、設計上の欠陥として誤って扱っていないか
- 実装がプロジェクト管理システムまたは巨大オーケストレーターへ膨張していないか

### 21.2 全体構成

- 作るものが、通知デコレータ、Goal Context生成手段、Goal Context対応PRレビューの三つに分かれているか
- 既存実装プロセスを新しく作り直していないか
- PRレビューリポジトリの取り込み作業と、新規の横断デコレータを混同していないか
- 共通部品と具体的プロセス内部のagentが同じ階層に並んでいないか

### 21.3 Goal Context

- 元の問題、Desired outcome、判断理由が自己完結しているか
- Issue本文の長文化に留まっていないか
- 棄却案と棄却理由が残っているか
- 利用者が訂正した事項が反映されているか
- 推論を事実として書いていないか
- 秘密情報または不要な個人情報を含んでいないか
- ファイル名が命名規則に従っているか

### 21.4 完了通知デコレータ

- 既存プロセスと同一親ターンへ追加できるか
- 既存プロセスを呼び出すオーケストレーターになっていないか
- デコレータ専用custom agentを作っていないか
- `notify` callbackで実際の親ターン終了を観測しているか
- 主プロセスのverdictをデコレータが再判定していないか
- 通知失敗が既存プロセスを壊さないか

### 21.5 PRレビュー・修正サイクル

- `codex_copilot_pr_review_agent`の本質的部品だけを取り込んでいるか
- `spark-implementer`を削除したか
- `local-reviewer`と`purpose-reviewer`の責務が明確か
- `review-planner`が各レビューの重複、競合、採否を扱えるか
- 修正計画がAdaptive Implementationへ渡せるか
- Adaptiveの内部契約を複製していないか
- PR単位でReview ThreadとImplementation Threadを一つずつ固定し、同じroleの次工程が同じtaskを再開しているか
- cycle開始時から初回実装のImplementation ThreadとReview Threadが固定され、後続roundでID変更を拒否しているか

### 21.6 通知・リンク

- 各通知がどのrepository、process、thread、PRか識別できるか
- `resume_uri`は該当Codex親スレッドを開くか
- `result_uri`は該当PRまたはレビューを開くか
- Windows通知が結果と現在taskの両操作を同時に提示するか
- 失敗、timeout、BLOCKEDが成功として通知されないか
- 重複通知を抑止できるか

## 22. リスクと制限

### 22.1 Goal Contextの情報漏れ

AI生成では、会話中の細かな訂正または暗黙の優先順位が欠落する可能性がある。人間による確認を省かない。

### 22.2 長大な相談スレッド

元会話が非常に長い場合、生成モデルが初期の文脈を十分に参照できない可能性がある。Issue確定直後にGoal Contextを生成し、必要なら重要判断を再確認する。

### 22.3 Codex deep link

ローカルCodexスレッドを開くURIは、利用環境、アプリ版、対象PCに依存し得る。MVP実装前に実機検証し、使えない環境ではPR等の代替リンクを検討する。

### 22.4 Notification envelopeの欠落

モデルがenvelopeを正しく出力しない可能性がある。notifyランタイムは、envelopeがない場合や不正な場合は診断状態を記録して通知を抑止する。markerだけの中間callbackを一般的な親ターン完了と解釈しない。

### 22.5 完了の意味

観測できるのが親ターン終了である場合、それをIssueまたは目的の完全達成と表示してはならない。主プロセスのverdictが取得できる場合は併記し、取得できない場合は「Codex turn completed」等、観測事実に合わせる。

### 22.6 GitHub Copilotレビュー待機

レビュー本文とinline commentsの到着タイミングが異なる可能性がある。既存の安定サンプル判定とtimeout表現を維持し、未取得をコメントなしと推測しない。

### 22.7 通知先の選択

Windows通知、ntfy、Slack、ローカルWeb UI等のどれを採用するかで、deep link、履歴、複数端末対応が変わる。通知先をデコレータSkillまたは具体的プロセスへ密結合しない。

## 23. Open questions

以下は会話では確定していない。

1. 完了通知デコレータの正式なSkill名とAPM package名
2. Goal Context生成プロンプトおよびテンプレートの正式な配置場所
3. Goal Context対応PRレビューSkillの正式名称
4. 基礎版とGoal Context対応版を、別packageにするか同一package内の別Skillにするか
5. `local-reviewer`の名称を維持するか、`code-reviewer`へ変更するか
6. `review-planner`からAdaptive Implementationへ渡すcanonical artifactの最終schema
7. 通知ランタイムの実装言語と配置場所
8. 既存のCodex `notify`設定と競合しない導入・合成方法
9. Windows通知、ntfy、Slack、Web UI等の初期配信先
10. MVPで永続イベント履歴を持つか
11. Codexスレッドのdeep linkが対象環境で安定して動くか
12. 複数worktreeまたは別PCで同じrepositoryを使う場合のリンク表現
13. GitHub Webhookを将来利用するか、既存CLI pollingを継続するか
14. `codex_copilot_pr_review_agent`の元リポジトリをarchiveするか、移行案内用に残すか

これらを、実装者の好みだけで暗黙に固定しない。MVP価値に直接影響するものから検証する。

## 24. Context confidence and possible omissions

### 24.1 高い確度で確定している事項

- 痛点は、複数プロジェクトのAI作業を見回り、対象へ戻る手間である
- MVP必須は、完了または停止の通知と対象を直接開くリンクである
- ChatGPTレビューの価値は、初期検討の目的コンテキストにある
- 目的コンテキストはGoal Context Markdownへ可搬化する
- Goal Context文書のファイル名は`goal-context-`で始め、特定Issueへ紐付けない
- 新しい初回実装プロセスは作らない
- 完了通知は任意の既存プロセスへ追加できるデコレータとする
- デコレータは既存プロセスを起動するオーケストレーターではない
- デコレータ専用custom agentは作らない
- 親ターンの完了検出はCodex `notify` callbackを中心とする
- `codex_copilot_pr_review_agent`は`coding_agent_plan_and_verify_process`へ取り込む
- Goal Context対応の目的達成レビューをPRレビュー工程へ追加する
- PRレビュー工程は修正計画を生成して停止し、レビュー反映は別の手動開始ターンでAdaptive Implementationを使用する
- 修正実装にはAdaptive Implementationを使用する
- `spark-implementer`は互換用にも残さず削除する
- Planモードから実装への自動切り替えは考慮しない
- 次工程の自動起動とグローバルなタスク相関はMVPへ入れない

### 24.2 設計判断として有力だが、実装で検証が必要な事項

- notification envelopeを最終回答へ追加する方式
- valid terminal envelopeがあるcallbackだけを通知し、marker-only中間callbackを抑止する方式
- `resume_uri`としてCodex deep linkを使う方式
- 基礎版とGoal Context対応版のSkill構成
- Goal Context対応PRレビューにおけるagentの並列実行
- 共通通知ランタイムの配布方法

### 24.3 会話からは決められない事項

- 各package、Skill、agentの正式名称
- 最終的なディレクトリ配置
- 通知プロバイダー
- 永続履歴の初期実装有無
- イベントschemaの細部
- 旧リポジトリの移行手順

## 25. 最終的な設計原則

本構想を一文で表すと、次のようになる。

> ChatGPTで形成した目的をGoal Contextとして可搬化し、既存のCodex開発プロセスを変更せず共通の完了通知デコレータと併用し、PRレビューには目的達成レビューを追加することで、複数プロジェクトのAI開発サイクルを通知と直接リンク付きで回せるようにする。

優先順位は次の通りである。

1. **見回りを減らす**
2. **通知から対象へ直接戻れるようにする**
3. **Issueの字面ではなく、本来の目的でレビューできるようにする**
4. **既存実装プロセスを変更または複製せず再利用する**
5. **共通デコレータと具体的プロセスの責務を混同しない**
6. **手動のままでよい工程を不要に自動化しない**
7. **高度な相関、自動進行、ダッシュボードはMVP完成後に検討する**

この優先順位を崩し、通知とリンクが不完全なまま、巨大オーケストレーター、タスク管理、次工程自動化へ広げる実装は、本来の目的から外れる。
