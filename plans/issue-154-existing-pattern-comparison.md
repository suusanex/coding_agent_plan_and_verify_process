# Issue #154 実装計画

## 目的と範囲

[Issue #154](https://github.com/suusanex/coding_agent_plan_and_verify_process/issues/154)のGoal Context / Decision Contextを根拠とし、Adaptiveの通常実装に既存処理との比較・差分設計・実装後照合を組み込む。モデル切替、実装所有権、Design PairやPlan Coverageの利用条件は変更しない。

## 現行方式との比較

- `.apm/skills/adaptive-implementation-execution/SKILL.md`のStep 2がDecision-Surface ownerを起動し、Step 3が直接完了またはhandoffを受理する。Step 4–5はbounded ownerとre-entryを扱う。
- `.apm/agents/decision-surface-implementation-owner.agent.md`のSemantic ownershipはread → implement → focused verification → reassessを所有する。Production sequence / State ownership等のassessmentはあるが、実装前の参照処理との比較が明示されていない。
- `refs/handoff.md`のImplementation and verification evidenceとLocked decisionsへ比較内容を小さく追加できる。bounded ownerはその契約内で実装し、非局所判断が生じると既存re-entryへ戻る。
- Plan CoverageのImplementation Contract Kernelは類似pathの適合性評価を行うが、実装を所有しない別工程である。比較の観点のみ参考とし、そのartifact体系や語彙は移植しない。
- 今回はprompt / Markdown契約の変更であり、BCL / framework API / NuGet OSSで置き換える実行処理はない。既存の文書、handoff、PowerShell validator、plugin builderを再利用し、新しいruntimeや独自実行シーケンスは作らない。

## 実装手順

1. 初期設計をPersistent Purpose Reviewへ提出する。
2. Decision-Surface ownerへ実装前比較を追加する。新しい処理経路・状態管理を追加／変更する場合は近傍だけでなく同じデータの更新箇所、同じinterface実装、兄弟機能の関連箇所へ探索を広げる。通常の局所修正は関連する参照と差分を短く記録する。
3. 実際に読んだfile / symbol、呼び出し関係、順序・状態所有・関連する失敗等の扱い、要求差分、採用方式（API呼び出し／拡張点／構造追従／別方式）を既存の計画・実装記録へ記す。別方式は不適合根拠と例外範囲、不在時は探索範囲と未発見事実を記す。無制限探索・固定件数・架空参照・不要な共通化・新規承認待ちを要求しない。
4. 実装後はactual diffを参照処理と照合し、追加状態・順序制御・既存serviceを迂回する直接呼び出しの必要性を確認する。新事実は比較と判断へ反映する。直接完了でも省略しない。
5. 既存handoffのevidenceに比較を引き継ぎ、bounded ownerが参照・照合する。非局所判断を変える必要があれば既存re-entryを利用する。routerは両完了経路とtransferで記録を確認する。独立artifactや新たな状態schemaを増やさない。
6. 利用ガイドと具体的な分岐例、既存validatorの契約チェックを更新する。配布fingerprintは既存の生成手段で更新し、実model資格や実運用効果を成功扱いしない。
7. 検証後に日本語commit、Ready PR（Fixes #154と重点レビュー箇所を記載）、PR Review Remediationによるremoteレビュー評価・必要修正・pushを行う。

## 検証と完了条件

- 既存Adaptive validator（routing scenariosを含む）、公開package境界validator、変更packageのAgent Plugin検証、root projection禁止、diff whitespace、変更Markdownの相対リンクを確認する。
- API / 拡張点の再利用、共通化なしの構造追従、要求上の別方式、類似なし、局所修正、直接完了、担当交代、新事実でのre-entryを文書上の分岐例で照合する。静的検査や例の整合は実model挙動の証明ではない。
- マージ後の実運用評価は未実施として残す。発見・採用、不要な別経路／共通化、調査負担・確認回数をIssueへ追記できる観察欄を利用ガイドに用意する。期間・数値閾値は追加しない。副作用が多い場合は本変更をrevertできる範囲に保つ。

## 初期設計レビュー

- Runner 0.6.0 / protocol 4、run `97e3a149-7eee-4f81-9580-fe9c41e98ed5`。
- terminal `COMPLETE`、round 1、累積reviewRounds 1、durableSubmissions 1。findingなし、応答修正なし。
- 入力は`issue-154-purpose-review-input.json`。承認済みbaselineなし。COMPLETEは利用者承認、実装適合、実運用効果の確認を意味しない。

## 実装・検証結果

- 両owner、入口Skill、既存handoffのevidenceを更新。直接完了とtransfer両経路で比較を維持し、未実装部分の照合はCompletion checkへ引き継ぐ。独立実行工程、状態管理、service迂回、新しい共通基盤は追加していない。
- Usage guideの9分岐を契約と机上照合済み。API／拡張点／構造追従／別方式／不在、局所修正、直接完了、交代、新事実のre-entryを確認。実modelによる実証ではない。
- PASS: `validate-adaptive-implementation-execution.ps1`（既存routing scenariosを含む）、`validate-process-package-boundaries.cs -- validate`、`validate-no-root-projections.ps1`、`validate-readme-navigation.ps1`、`git diff --check`。
- PASS: `validate-agent-plugin-package.ps1 -Package adaptive-implementation-execution`、`validate-agent-plugin-qualification.ps1 -Package adaptive-implementation-execution`（negative mutationを含む）。qualificationの実model判定はNOT_RUN / HOLDを維持。
- 配布検証は常用APM 0.33.0のlocal-bundle非対応で一度失敗。CI指定の公式APM 0.26.0を一時領域へ展開し、公開SHA256と一致確認後、既存`-ApmExecutable`引数で指定すると成功した。常用APMとrepository配布方式は変更していない。
- PRレビュー・CIはPR作成後に確認する。マージ、実model挙動、実運用効果は未確認。

## PRレビュー補修

- PR #157のCopilot指摘（inline-comment:4531294328）を採用。既存routing fixtureへ比較例6件を加え、直接完了・transfer・bounded完了へ接続した。参照・要求差分・採用方式・照合欠落、inspection-onlyの虚偽照合をnegative mutationで拒否する。fixture用JSON表現でありruntime handoff形式は変更しない。
- CIのAdaptive／Design Pair配布smokeで、旧GPT-5.6期待値と現行canonicalのGPT-6定義との不一致を確認した。モデル自体は変えず、smoke2本の期待値8箇所だけ修正。
- 補修後のAdaptive validator、Design Pair validator、公開境界、diff検査はPASS。修正したsmoke2本もremote head `549243f`をAPM 0.26.0で導入してPASS。Windows上のAPM subprocessでcp932 decode例外の出力があったが、プロセスとsmokeはexit 0で完了。既存finalizerにはSDK RC由来のNuGet / AOT警告がある。最終headのLinux CIも確認する。
- 採否・全source coverage・Git結果の詳細はlocal `.review/pr-157/review-plan.md`に記録する。
