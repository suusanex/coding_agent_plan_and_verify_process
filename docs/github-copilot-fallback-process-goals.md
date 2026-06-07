# GitHub Copilot Fallback AI Development Process Goal Document

作成日: 2026-06-07  
対象: `suusanex/coding_agent_plan_and_verify_process` の次作業  
想定成果物: GitHub Copilot Chat（VS Code）利用者が、Codex枠が尽きた場合でも、同じ思想の cost-aware / Plan-first / gate-driven process を repo-local に導入して使える状態にする。

---

## 1. 背景

現状、`main` ブランチには Codex 向けの `codex-first-ai-development-process` が入り、Codex CLI / Codex IDE / repo-local導入を前提とした cost-aware routing の土台は整っている。

一方、勤務先の運用では、まず Codex のサブスク枠を優先利用し、Codex枠が不足した場合や利用者環境の都合がある場合に GitHub Copilot を fallback として使う想定がある。

この fallback の主対象は **GitHub Copilot Chat in VS Code** である。  
したがって、Codex の `CODEX_HOME`、`.codex/config.toml`、Codex custom agent TOML、Codex-specific profile / launcher を前提にしても、GitHub Copilot Chat利用者にはそのまま届かない。

この文書は、GitHub Copilot Chat利用者が対象リポジトリへ導入して使える repo-local package を作るためのゴール定義である。  
後続の Plan / 実装は、この文書を source of truth として進める。

---

## 2. 最上位ゴール

GitHub Copilot Chat（VS Code）利用者が、対象リポジトリに repo-local 導入することで、通常の開発依頼を次のような cost-aware process に自然に通せる状態を作る。

```text
この issue を進めて。
このバグを直して。
この機能を実装して。
この PR の残件を片付けて。
続きやって。
```

利用者に次を要求しない。

- 既存の Plan網羅チェック・残件判定フロー名を覚えること
- agent 名を選ぶこと
- model tier を自分で判断すること
- full-coverage 3層運用を使うかどうかを判断すること
- READY / close / residual decision を自分で管理すること
- Codex CLI、`CODEX_HOME`、`.codex/config.toml` を理解すること

最終的な完成条件は、**GitHub Copilot Chat利用者が導入して使える repo-local成果物があり、その導入方法・使い方・制約がREADMEに明記されていること**。

---

## 3. 重要な設計方針

### 3.1 Copilot fallback は Codex package の移植ではなく、VS Code Copilot 向け再パッケージ化

Codex向け成果物は、そのままGitHub Copilot Chatには効かないものがある。

Codex向けに使えるもの:

- `AGENTS.md`
- `.codex/config.toml`
- `profiles/codex-first/agents/*.toml`
- `CODEX_HOME`
- Codex custom agent TOML
- `model_reasoning_effort`

GitHub Copilot Chat向けに使うべきもの:

- `.github/copilot-instructions.md`
- `.github/instructions/*.instructions.md`
- `.github/agents/*.agent.md`
- `.github/prompts/*.prompt.md`
- VS Code Copilot custom agents
- VS Code Copilot prompt files
- VS Code Copilot model指定
- VS Code Copilot handoff

したがって、Copilot fallback は `codex-first-ai-development-process` をそのまま流用するのではなく、**共通語彙・state artifact・gate設計・stop vocabularyを再利用し、VS Code Copilotのrepo-local customization形式へ変換した package** として作る。

### 3.2 中核は GitHub Copilot Chat 用 cost-router

Copilot fallbackでも、中核は `cost-router` である。

ただし、名称はCodexと混同しないように、次のようなCopilot専用名を使う。

```text
copilot-cost-router
copilot-fallback-cost-router
github-copilot-cost-router
```

このrouterは、ユーザーの普通の依頼を受け取り、次を行う。

1. repo-local instructions と既存artifactを読む
2. `plans/<slug>/codex-first-state.md` または互換state artifactを読む/作る
3. Intake / Plan / Risk / Scan / Contract / Implementation / Verification / Close の次gateを選ぶ
4. gateごとに Copilot向け model tier を選ぶ
5. 必要に応じて Copilot custom agent / prompt file / handoff を使う
6. READYでなければ実装しない
7. close不可ならcloseしない
8. 次に必要な人間入力だけを提示する

### 3.3 3層運用は標準ルートにしない

Codex側と同じく、GitHub Copilot fallbackでも full-coverage 3層運用は標準ルートにしない。

位置づけ:

- 熟練operator向け
- advanced route
- 大規模で明示的に並列化・分割統治したい場合のみ
- 初心者向け user guide では判断させない
- Copilot fallbackの標準導入では `copilot-cost-router` を中心にする

### 3.4 Copilotのmodel tierはCodexの実名モデルと分ける

Codex向け `HIGH_MODEL` / `STANDARD_MODEL` / `CHEAP_MODEL` の考え方は再利用する。  
ただし、Copilotの利用可能モデル名・課金単位・premium request消費はCodexと異なるため、実名モデル対応は別に持つ。

Copilot向けには次の抽象ラベルを使う。

```text
COPILOT_HIGH_MODEL
COPILOT_STANDARD_MODEL
COPILOT_CHEAP_MODEL
```

または、共通語彙を維持するために `HIGH_MODEL` / `STANDARD_MODEL` / `CHEAP_MODEL` を使う場合でも、**Copilot用mappingとして別文書に分ける**。

---

## 4. VS Code Copilot 仕様に基づく前提

### 4.1 Always-on instructions

VS Code Copilot Chat は、workspace root の `.github/copilot-instructions.md` を自動検出し、workspace内のchat requestへ適用できる。

また、VS Codeは `AGENTS.md` も always-on instructions として扱える。ただし、Copilot向けに最も明示的な入口は `.github/copilot-instructions.md` である。

このため、Copilot fallback package は最低限 `.github/copilot-instructions.md` を生成・配置できる必要がある。

### 4.2 File-based instructions

`.github/instructions/*.instructions.md` は、frontmatterの `applyTo` などで適用対象を制御できる。

ただし、複数instructionの結合順序は保証されないため、重要なルーティング原則を複数ファイルに分散しすぎてはならない。

Copilot fallbackでは、always-on instructionに最重要ルールを置き、`.instructions.md` は補助に留める。

### 4.3 Custom agents

VS Code Copilot custom agent は `.github/agents/*.agent.md` としてrepo-localに配置できる。  
agent fileはMarkdownで、YAML frontmatterに `name`、`description`、`tools`、`model`、`handoffs` などを持てる。

Copilot fallbackでは、次のcustom agentsを作る。

- `copilot-cost-router.agent.md`
- `copilot-high-planner.agent.md`
- `copilot-risk-triage.agent.md`
- `copilot-standard-implementer.agent.md`
- `copilot-standard-verifier.agent.md`
- `copilot-cheap-repo-scanner.agent.md`
- `copilot-close-reviewer.agent.md`

必要なら、ユーザーに見せない内部用agentは `user-invocable: false` を使う。

### 4.4 Handoff

Copilot custom agents は `handoffs` を使って、次agentへの誘導ボタンを出せる。  
これにより、詳しくない利用者へ「次に何を選ぶか」を考えさせず、Plan → Implementation → Verification → Close の順に進めやすくなる。

Copilot fallbackでは、handoffを次の用途に使う。

- Plan作成後に実装へ進める
- READYでない場合は修正・再Planへ戻す
- 実装後にverificationへ進める
- verification後にclose reviewへ進める
- human decisionが必要な場合は停止する

### 4.5 Prompt files

VS Code prompt files は `.github/prompts/*.prompt.md` に置ける。  
prompt files は slash command として手動実行でき、frontmatterで `agent`、`model`、`tools` を指定できる。

Copilot fallbackでは、always-on instructionだけで自然に効かない場合の明示入口として、次の prompt files を用意する。

- `cost-route.prompt.md`
- `resume-state.prompt.md`
- `verify-and-close.prompt.md`
- `fix-selected-residual.prompt.md`

---

## 5. 必須成果物

### 5.1 新規APM package

次のような新規packageを作る。

```text
apm-packages/copilot-fallback-ai-development-process/
  apm.yml
  docs/
    copilot-fallback-guide.md
    user-guide.md
    maintainer-guide.md
    model-tier-mapping.md
    install-guide.md
    limitations.md
  templates/
    github/
      copilot-instructions.md
      instructions/
        cost-aware-routing.instructions.md
        state-and-close-rules.instructions.md
      agents/
        copilot-cost-router.agent.md
        copilot-high-planner.agent.md
        copilot-risk-triage.agent.md
        copilot-standard-implementer.agent.md
        copilot-standard-verifier.agent.md
        copilot-cheap-repo-scanner.agent.md
        copilot-close-reviewer.agent.md
      prompts/
        cost-route.prompt.md
        resume-state.prompt.md
        verify-and-close.prompt.md
        fix-selected-residual.prompt.md
```

配置名は後続Planで変更してよい。  
ただし、次のゴールは変えない。

- repo-local導入できる
- GitHub Copilot Chat in VS Codeを主対象にする
- `.github/` 配下へ展開できる
- cost-routerを中核にする
- state artifactをCodexと共有または互換にする
- READMEに導入方法が書かれる

### 5.2 repo-local install後の成果物

対象リポジトリへ導入した後、最低限次の形になること。

```text
.github/
  copilot-instructions.md
  instructions/
    cost-aware-routing.instructions.md
    state-and-close-rules.instructions.md
  agents/
    copilot-cost-router.agent.md
    copilot-high-planner.agent.md
    copilot-risk-triage.agent.md
    copilot-standard-implementer.agent.md
    copilot-standard-verifier.agent.md
    copilot-cheap-repo-scanner.agent.md
    copilot-close-reviewer.agent.md
  prompts/
    cost-route.prompt.md
    resume-state.prompt.md
    verify-and-close.prompt.md
    fix-selected-residual.prompt.md
plans/
  <slug>/
    codex-first-state.md
```

`plans/<slug>/codex-first-state.md` という名前はCodex由来だが、互換性のためそのまま使ってよい。  
別名にする場合でも、Codex版と相互運用できる互換ルールを明記する。

### 5.3 README更新

root `README.md` に、GitHub Copilot fallback の導入と使い方を追記する。

READMEは少なくとも次を説明する。

- Codex-first package と Copilot fallback package の違い
- Codex枠が尽きたときのfallbackとして使う位置づけ
- GitHub Copilot Chat（VS Code）を主対象にすること
- 導入後に利用者がどう依頼すればよいか
- repo-local installで配置されるファイル
- model tier mappingは組織/チームで調整すること
- full-coverage 3層運用は標準ルートではなくadvanced routeであること
- close不可状態のまま完了扱いしないこと

---

## 6. Copilot用 custom agents のゴール

### 6.1 copilot-cost-router.agent.md

役割:

- 通常の開発依頼の入口
- ユーザーにprocess名、agent名、model tier、full-coverage判断を要求しない
- state artifactを読む/作る
- 次gateを選ぶ
- 必要なら他agentへのhandoffを出す
- close不可なら止める

必須:

- `model` を指定できるfrontmatterを持つ
- defaultは `COPILOT_STANDARD_MODEL` 相当
- 難しいgateでは `handoffs.model` または次agent側の `model` で高性能側へ寄せる
- ユーザーには最小の次入力だけ提示する

### 6.2 copilot-high-planner.agent.md

役割:

- 曖昧・広範囲の要求をbounded Planへ整理する
- Plan / Acceptance Criteria / Non-goals / Completion Criteria を作る
- 実装しない

必須:

- high model候補をfrontmatterで指定する
- implementation agentへのhandoffを持つ
- READYでない場合は実装へ渡さない

### 6.3 copilot-risk-triage.agent.md

役割:

- risk classification
- security / auth / DB / public API / async / production wiring / external SDK riskの分類
- standard routeでbounded化できるか判断する
- advanced routeが必要なら、人間/熟練operator判断へ送る

必須:

- full-coverage 3層運用を標準routeにしない
- high-risk時は high modelへ寄せる
- risk結果をstate artifactへ反映する

### 6.4 copilot-cheap-repo-scanner.agent.md

役割:

- read-heavy search
- file inventory
- API surface lookup
- test location discovery
- docs consistency scan

必須:

- low-cost model候補をfrontmatterで指定する
- editは禁止または最小限
- 実装判断・close判断をしない
- raw outputを大量に貼らず要約する

### 6.5 copilot-standard-implementer.agent.md

役割:

- READY後のbounded implementation
- scope外へ広げない
- repo rules / build rules / security rulesを守る

必須:

- standard model候補をfrontmatterで指定する
- `allowed_to_edit: true` または同等のREADY状態を確認する
- design uncertaintyが出たらplanner / risk / human decisionへ戻す
- endless repair loopを避ける

### 6.6 copilot-standard-verifier.agent.md

役割:

- implementation evidenceとacceptance criteriaを対応付ける
- production implementation / wiring / entrypoint を確認する
- fake / stub / mock-only success をproduction success扱いしない
- manual-only verificationを明示する

必須:

- standard model候補をfrontmatterで指定する
- close decisionは独断しない
- close reviewerへのhandoffを持つ

### 6.7 copilot-close-reviewer.agent.md

役割:

- close可否判断
- residual classification
- human decision / manual verification / higher model reviewの未解決確認

必須:

- risky closeでは high model候補を指定する
- `ManualVerificationRequired` / `NeedsHumanDecision` / `NeedsHigherModelReview` が残る場合はcloseしない
- `ReadyToClose` と `ReadyToCloseWithAcceptedResiduals` を区別する

---

## 7. Prompt files のゴール

### 7.1 cost-route.prompt.md

目的:

- 明示的にcost-routerを起動するslash command
- always-on instructionsだけでは不安な場合の入口

利用例:

```text
/cost-route この issue を進めて
```

必須:

- `agent: copilot-cost-router`
- 必要なら `model` を指定
- state artifactの作成/更新を指示
- 実装前READY確認を指示

### 7.2 resume-state.prompt.md

目的:

- `plans/<slug>/codex-first-state.md` から再開する

利用例:

```text
/resume-state
```

必須:

- state artifactを探す
- next gateだけ実行する
- 実装可否を確認する
- stateを更新する

### 7.3 verify-and-close.prompt.md

目的:

- 実装後のverificationとclose判定

必須:

- acceptance criteriaへのevidence mapping
- production wiring確認
- manual-only分類
- close不可stop reason確認
- residual decision

### 7.4 fix-selected-residual.prompt.md

目的:

- verification後に選択されたresidualだけをbounded修正する

必須:

- selected residual IDs または選択範囲を要求する
- scopeを広げない
- 修正後にverificationへ戻す

---

## 8. Instructions のゴール

### 8.1 .github/copilot-instructions.md

always-onの最重要ルールだけを書く。

含めるべきこと:

- 通常の開発依頼を Copilot fallback cost-aware process として扱う
- process名・agent名・model tier・full-coverage判断をユーザーに要求しない
- state artifactを読む/作る
- READYでなければ実装しない
- close不可ならcloseしない
- repo固有のbuild/test/security rulesを優先する
- secret / billing / production / external operationは自動実行しない
- full-coverage 3層運用はadvanced routeである

短く保つこと。  
詳細は `.github/instructions/*.instructions.md`、custom agents、prompt filesへ逃がす。

### 8.2 cost-aware-routing.instructions.md

適用対象:

```yaml
applyTo: "**"
```

含めるべきこと:

- gate定義
- model tier定義
- stop vocabulary
- state更新ルール
- handoff方針

### 8.3 state-and-close-rules.instructions.md

含めるべきこと:

- state artifact fields
- close不可条件
- residual分類
- fake / stub / mock-only successの扱い
- manual verificationの扱い

---

## 9. Model tier mapping

Copilot用の model mapping 文書を作る。

```text
docs/model-tier-mapping.md
```

含めるべきこと:

- Codex版とは別管理であること
- Copilotのモデル名はVS Code / GitHub Copilot側の可用性に依存すること
- custom agent / prompt file の `model` frontmatterで指定できること
- 未指定の場合はmodel pickerの現在値が使われること
- high / standard / cheap の候補は組織で更新すること
- premium request / 利用制限 / 品質要求を考慮すること

初期値は例として置いてよいが、固定しない。

---

## 10. 導入方式

### 10.1 repo-local install を標準にする

GitHub Copilot Chat利用者向けには、repo-local installを標準導入方式にする。

理由:

- VS Code Copilot Chatはworkspace内の `.github/copilot-instructions.md`、`.github/instructions`、`.github/agents`、`.github/prompts` を自然に読める
- ユーザーにCLIや `CODEX_HOME` を意識させない
- 対象リポジトリを開くだけで利用できる

### 10.2 bootstrap / dry-run

既存 `.github` や `AGENTS.md` があるリポジトリを壊さないため、導入時はdry-runを前提にする。

検出対象:

- `.github/copilot-instructions.md`
- `.github/instructions`
- `.github/agents`
- `.github/prompts`
- `AGENTS.md`
- 既存のbuild/test/security instructions
- 既存のCopilot customizations
- model名の衝突
- prompt名の衝突
- agent名の衝突

dry-run reportに含めるもの:

- 追加予定ファイル
- 変更予定ファイル
- 衝突する既存ファイル
- merge方針
- 人間判断が必要な項目
- 自動適用できない理由

### 10.3 install後の検証

最低限、次を確認する。

- VS Code Chatで custom agents が見える
- `/cost-route` などのprompt fileが見える
- `.github/copilot-instructions.md` が効いている
- 「この issue を進めて」で実装に直行しない
- `plans/<slug>/codex-first-state.md` が作られる
- `続きやって` または `/resume-state` で再開できる
- close不可条件が守られる

---

## 11. README に書くべきこと

root `README.md` には、次の章を追加する。

```text
## GitHub Copilot fallback AI Development Process
```

この章に含めること:

1. 位置づけ
   - Codex枠が尽きた場合のfallback
   - 主対象は GitHub Copilot Chat in VS Code
   - Codex-firstと同じ思想だが導入面は `.github/` 配下

2. 導入方法
   - repo-local install
   - 配置されるファイル
   - 既存 `.github` がある場合はdry-run推奨

3. 使い方
   - 普通に「この issue を進めて」
   - 明示入口として `/cost-route`
   - 再開は「続きやって」または `/resume-state`
   - 検証は `/verify-and-close`

4. モデルtier
   - Copilot用model mappingは別管理
   - high / standard / cheap の役割
   - 実名モデルは環境に合わせて変更

5. 安全ルール
   - READY前に実装しない
   - close不可をcloseしない
   - secret / production / billing / external operationを自動実行しない
   - repo固有ルールを優先する

6. Codex-firstとの関係
   - state artifact / stop vocabulary / gate設計は共有
   - Codex用 `.toml` や `CODEX_HOME` はCopilotには使わない
   - full-coverage 3層運用はadvanced route

---

## 12. 成功条件

### 12.1 導入成功

- 対象リポジトリへrepo-localに導入できる
- 導入後、VS Code Copilot Chatで custom instructions / custom agents / prompt files が見える
- 既存 `.github` や `AGENTS.md` を壊さない
- READMEに導入手順がある

### 12.2 利用成功

- ユーザーは「この issue を進めて」で開始できる
- ユーザーは `/cost-route` でも開始できる
- ユーザーは「続きやって」または `/resume-state` で再開できる
- ユーザーはagent名やmodel tierを知らなくてよい
- 実装前にREADY確認が入る
- 実装後にverification / close判定が入る

### 12.3 model routing 成功

- high judgment はCopilot high agentへ寄る
- normal implementation はstandard agentへ寄る
- read-heavy scan / docs consistency はcheap agentへ寄る
- model mapping はCopilot用に分離されている
- 実名モデルは組織側で差し替え可能

### 12.4 safety 成功

- `ManualVerificationRequired` が残る場合はcloseしない
- `NeedsHumanDecision` が残る場合はcloseしない
- `NeedsHigherModelReview` が残る場合はcloseしない
- fake / mock / stub-only success をproduction success扱いしない
- secret / production / billing / external operationを自動実行しない

---

## 13. 受け入れテスト観点

### 13.1 ordinary request

入力:

```text
この issue を進めて。
```

期待:

- Copilot fallback process として扱う
- process名を要求しない
- いきなり実装しない
- state artifact を作る
- next gate を示す

### 13.2 slash command

入力:

```text
/cost-route この issue を進めて
```

期待:

- `copilot-cost-router` agentで実行される
- next gate と model tier をstateに記録する

### 13.3 resume

入力:

```text
/resume-state
```

期待:

- 既存state artifactを読む
- next gateだけ実行する
- state artifactを更新する

### 13.4 simple local fix

入力:

```text
このtypoを直して。
```

期待:

- 不要なheavy planningへ入らない
- repo instructionsを読む
- trivial-fix相当として扱う
- 変更後に軽い確認を行う

### 13.5 high-risk request

入力:

```text
認証まわりの処理を直して。
```

期待:

- high planner / risk triage へ寄る
- いきなり実装しない
- security/auth risk を記録する
- human decisionが必要なら停止する

### 13.6 close blocker

前提:

```text
ManualVerificationRequired が残っている
```

期待:

- closeしない
- 必要な人間確認を提示する

### 13.7 existing GitHub customizations

前提:

```text
既存 .github/copilot-instructions.md がある
```

期待:

- dry-runで衝突を報告する
- 上書きしない
- merge案を出す
- 承認後だけ変更する

---

## 14. 非目的

この作業では次を目的にしない。

- Codex用 `.toml` profileをそのままCopilotで使うこと
- `CODEX_HOME` をCopilot導入の前提にすること
- Copilotの課金・premium request消費を完全自動管理すること
- full-coverage 3層運用を初心者向け標準ルートにすること
- すべてのリポジトリへ強制導入すること
- 既存 `.github` 設定を自動で破壊的に上書きすること
- GitHub organization-level custom instructions の管理画面設定まで自動化すること
- 人間レビューを完全になくすこと

---

## 15. 後続Planへの期待

後続のPlanでは、この文書をsource of truthとして、次を決める。

- 新規package名
- package構成
- template構成
- repo-local install手段
- dry-run / merge方針
- 既存Codex-first資産から流用する語彙・state・docs
- Copilot custom agentのfrontmatter設計
- Copilot prompt fileのslash command名
- Copilot model-tier mappingの初期例
- root READMEの更新範囲
- 受け入れテストの置き場所

実装上の制約で一部を満たせない場合は、削って進めず、未達項目と代替案を明記する。
