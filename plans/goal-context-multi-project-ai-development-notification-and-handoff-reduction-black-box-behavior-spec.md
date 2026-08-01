# Black-box Behavior Spec

## Scope

`docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md`に記載されたMVPを、実装方式に依存しない外部観測可能なケースへ展開する。対象は、通常のCodex作業に対する常時リンク付き通知と、初回実装を行った同じ親スレッド内で開始・反復する独立review/remediation flowである。

## Source requirement inventory

| Source ID | Requirement summary | Kind | Source | Notes |
| --- | --- | --- | --- | --- |
| `SRC-NOTIFY-001` | 通常どおりCodexへ作業を依頼するだけで、作業終了時にリンク付き通知を行う。 | Functional | Goal Context「Desired user-visible outcome」「Purpose-critical decisions」 | Decorator Skillや専用文言を日常promptへ追加しない。 |
| `SRC-NOTIFY-002` | 完了または停止を通知し、対象Codex threadを直接開ける。 | Functional | Goal Context「Desired user-visible outcome」「After」 | 「終わりました」だけの通知は拒否される。 |
| `SRC-NOTIFY-003` | PRや判定結果がある場合は、同じ通知からそれらも直接開ける。 | Functional | Goal Context「Desired user-visible outcome」「Purpose-critical decisions」 | threadへの導線を置き換えない。 |
| `SRC-NOTIFY-004` | 利用者へ提示する通知は親作業の完了・停止を中心に整理する。 | Negative / Unknown-sensitive | Goal Context「Unknowns affecting purpose judgment」 | subagent callback発火範囲は実環境確認が必要。 |
| `SRC-NOTIFY-005` | 通知runtimeはAPMで一度導入し、ユーザー単位のCodex `notify` callbackとして常時有効にする。 | Distribution | Goal Context「Purpose boundaries」「Purpose-critical decisions」 | Plugin移行は非目標。 |
| `SRC-NOTIFY-006` | 通知runtimeの失敗で主processの完了結果を壊さず、既存notifyを保持する。 | Compatibility | `scripts/codex-notification-runtime/decision-record.md` | 既存runtimeのfail-open / chain契約を維持する。 |
| `SRC-REVIEW-001` | 初回実装後は、元の実装親threadから短い一操作で独立reviewと必要な修正を開始する。 | Functional | Goal Context「Desired user-visible outcome」「After」 | 別top-level Review Threadを作成・探索しない。 |
| `SRC-REVIEW-002` | round 1はGitHub Copilot code review、独立Codex code review、Goal Context purpose reviewを収集する。 | Functional | Goal Context「After」「Purpose-critical decisions」 | 独立reviewerの生出力を保持する。 |
| `SRC-REVIEW-003` | purpose reviewerは実装担当と別のread-only reviewer subagentとしてPR差分とGoal Contextを直接評価する。 | Boundary / Negative | Goal Context「Priorities and trade-offs」「Rejected or misleading outcomes」 | 親agentの自己評価で代替しない。 |
| `SRC-REVIEW-004` | actionable findingがあれば、初回実装を担当した親agentが同じcontextで修正する。 | Functional | Goal Context「After」「Purpose boundaries」 | 初版では別write agentを使わない。 |
| `SRC-REVIEW-005` | 修正後はpurpose reviewだけを再実行し、code reviewを繰り返さない。 | Functional / Negative | Goal Context「After」「Purpose boundaries」 | GitHub CopilotとCodex code reviewはround 1のみ。 |
| `SRC-REVIEW-006` | 修正とpurpose reviewは最大3roundまで反復する。 | State transition | Goal Context「After」「Purpose-critical decisions」 | 収束しなければ人間判断で停止する。 |
| `SRC-REVIEW-007` | 自動確定できない目的判断または最大round未収束は、人間判断が必要な状態として停止・通知する。 | Recovery / Stop | Goal Context「Purpose-critical decisions」 | 推測で完了または追加修正を続けない。 |
| `SRC-REVIEW-008` | 利用者はthread ID、review-plan path、hash、JSON、Goal Context state値やresult referenceを運ばない。 | Negative | Goal Context「Before」「Rejected or misleading outcomes」 | 内部artifact整合だけを成功としない。 |
| `SRC-REVIEW-009` | terminal状態では同じ親threadと関連PRへ戻れる通知を行う。 | Functional | Goal Context「After」 | 正常完了と人間判断停止の両方。 |
| `SRC-SCOPE-001` | 複雑な分岐、長期中断、複数top-level実装thread、特殊な手動review運用はMVP外。 | Exclusion | Goal Context「Purpose boundaries」 | 人間が手動制御してよい。 |
| `SRC-SCOPE-002` | notification timeline、Adaptive Implementation executor対応、Plugin移行はMVP外。 | Deferred / Exclusion | Goal Context「Purpose boundaries」「Material corrections」 | 後続課題として再検討可能。 |
| `SRC-SCOPE-003` | Goal Contextはreview入力であり、多段承認workflowや利用者向け厳格state machineにしない。 | Negative | Goal Context「Purpose boundaries」「Rejected or misleading outcomes」 | 初期検討の目的を伝えることが役割。 |

## Behavior axes

| Axis ID | Axis | Relevant values | Why behavior changes | Notes |
| --- | --- | --- | --- | --- |
| `AX-N01` | 親作業terminal状態 | 完了 / 人間判断要求 / blocked・停止 | 通知内容と次操作が変わる。 | いずれも無通知にしない。 |
| `AX-N02` | enriched result | 具体的PR・resultあり / なし / unsafe・invalid | 追加導線の有無が変わる。 | thread導線は常に維持する。 |
| `AX-N03` | callback source | 親作業 / reviewer subagent | user-visible通知の要否が変わる。 | 実機で識別可能性を確認する。 |
| `AX-N04` | callback delivery history | 初回 / duplicate replay | user-visible通知件数が変わる。 | 既存runtime互換性。 |
| `AX-N05` | provider / chained notify状態 | 成功 / 失敗 | 主turnへの影響有無が変わる。 | fail-openを維持する。 |
| `AX-R01` | review round | 1 / 2 / 3 | 起動するreviewer集合と停止判定が変わる。 | round 1だけfull review。 |
| `AX-R02` | finding状態 | なし / 自動修正可能 / 人間判断必要 / 実行不能 | 完了、修正、human stop、blockedが変わる。 | 親agentがwrite owner。 |
| `AX-R03` | review input状態 | Ready PRとGoal Contextあり / 必須入力欠落・不正 / 外部review取得不能 | review開始または停止が変わる。 | Issue本文だけでpurpose review済みにしない。 |
| `AX-R04` | actor | 親agent / code reviewer / purpose reviewer / GitHub Copilot | write権限と責務が変わる。 | reviewerはread-only。 |
| `AX-R05` | purpose review後のhead | finding解消 / finding残存 | closeまたは次roundが変わる。 | 新しい実装結果を直接reviewする。 |

## Case matrix

| Case ID | Source IDs | Input conditions / preconditions | Expected observable behavior | Negative expectation | Status |
| --- | --- | --- | --- | --- | --- |
| `NTF-001` | `SRC-NOTIFY-001`, `SRC-NOTIFY-002`, `SRC-NOTIFY-005` | 通知Decoratorや専用markerを含まない通常の親Codex作業が完了する。 | 利用者へ完了通知が一度表示され、選択すると発火元のCodex threadを直接開ける。 | Decorator指定、専用envelope、thread探索を要求しない。 | Defined |
| `NTF-002` | `SRC-NOTIFY-001`, `SRC-NOTIFY-002`, `SRC-REVIEW-007` | 親作業がblockedまたは人間判断要求で停止する。 | attentionが必要なterminal通知が表示され、発火元threadを直接開ける。 | 成功扱いにせず、無通知にもならない。 | Defined |
| `NTF-003` | `SRC-NOTIFY-002`, `SRC-NOTIFY-003` | 親作業に具体的なPRまたはresult URIがある。 | 通知からresultと発火元threadの両方を直接開ける。 | result導線でthread導線を置き換えない。 | Defined |
| `NTF-004` | `SRC-NOTIFY-002`, `SRC-NOTIFY-003` | result URIがない、または安全・具体性条件を満たさない。 | thread direct linkを持つ通知は表示され、result導線だけが省かれる。 | 抽象的top pageやunsafe URIを開かせず、通知全体を失わない。 | Defined |
| `NTF-005` | `SRC-NOTIFY-004` | 親作業が一つ以上のreviewer subagentを実行してからterminalになる。 | 利用者へ提示される通知は親作業の完了・停止を中心に整理され、subagentごとの不要な通知群を生じない。 | subagent数に比例する通知spamを許さない。 | Defined |
| `NTF-006` | `SRC-NOTIFY-006` | 同一terminal callbackがreplayされる。 | 利用者に同じ完了通知を重複表示しない。 | replayを別作業の完了として扱わない。 | Defined |
| `NTF-007` | `SRC-NOTIFY-006` | notification providerまたは既存chained notifyが失敗する。 | 親Codex turnの完了・停止結果は維持され、診断可能な失敗として扱われる。 | notification side effectの失敗を主作業の失敗へ昇格しない。 | Defined |
| `NTF-008` | `SRC-NOTIFY-005`, `SRC-NOTIFY-006` | 利用者がAPMでruntimeを導入・更新し、既存notify設定がある。 | 一度の導入後に通常作業へ常時適用され、既存notifyも自己再帰なく継続する。 | 作業ごとのSkill選択や既存notifyの黙示破棄を要求しない。 | Defined |
| `REV-001` | `SRC-REVIEW-001`, `SRC-REVIEW-008` | 初回実装を終えた親threadにReady PRとGoal Contextがある。 | 利用者の短い一操作から、同じ親thread内でreview/remediation flowが開始する。 | 別top-level review task作成やID/path/hash/JSON転記を要求しない。 | Defined |
| `REV-002` | `SRC-REVIEW-002`, `SRC-REVIEW-003` | round 1を開始する。 | GitHub Copilot review、独立read-only code reviewer、独立read-only purpose reviewerの結果が収集され、各reviewerの生出力を追跡できる。 | 親agentの自己review一つで三系統を代替しない。 | Defined |
| `REV-003` | `SRC-REVIEW-003`, `SRC-REVIEW-004` | reviewer subagentがcodeとGoal Contextを評価する。 | reviewerはread-onlyで結果を親agentへ返し、production fileの変更は親agentだけが行う。 | reviewerにwriteを許可せず、別write agentとの調整を持ち込まない。 | Defined |
| `REV-004` | `SRC-REVIEW-002`, `SRC-REVIEW-004`, `SRC-REVIEW-006` | round 1に自動修正可能なactionable findingがある。 | 親agentが同じ実装contextで修正・検証し、新しいheadまたはdiffをpurpose reviewerへ渡す。 | review結果を利用者にコピーさせず、修正前のheadを再reviewしない。 | Defined |
| `REV-005` | `SRC-REVIEW-005`, `SRC-REVIEW-006` | round 1修正後またはround 2修正後に再reviewする。 | 新しい独立read-only purpose reviewerだけを実行し、GitHub Copilot waitとCodex code reviewは再実行しない。 | 各roundでfull code reviewを反復しない。 | Defined |
| `REV-006` | `SRC-REVIEW-005`, `SRC-REVIEW-006`, `SRC-REVIEW-009` | purpose reviewerが3round以内にactionable purpose findingなしと判定する。 | flowは完了し、同じ親threadと関連PR/resultへのdirect linkを持つterminal通知を行う。 | 内部artifact整合だけで完了せず、独立purpose reviewer結果を欠かさない。 | Defined |
| `REV-007` | `SRC-REVIEW-006`, `SRC-REVIEW-007`, `SRC-REVIEW-009` | round 3後もactionable purpose findingが残る。 | 自動修正を停止し、人間判断が必要なterminal状態と、親thread・PRへの復帰導線を通知する。 | round 4を自動開始せず、黙示的にfindingを受容しない。 | Defined |
| `REV-008` | `SRC-REVIEW-007`, `SRC-SCOPE-003` | reviewer findingがproduct semantics、優先順位、risk acceptanceの決定を要求する。 | 親agentは推測で修正せず、人間判断が必要な理由を保持して停止・通知する。 | Goal Contextを根拠にないproduct decisionを発明しない。 | Defined |
| `REV-009` | `SRC-REVIEW-001`, `SRC-REVIEW-002`, `SRC-REVIEW-007` | Ready PR、Goal Context、review対象headなどの必須入力が欠落・不正・曖昧である。 | flowは実行可能な範囲を越えて進まず、具体的な不足と戻り先を示してblocked停止・通知する。 | Issue本文だけでpurpose review済みと扱わず、空のreview結果で修正へ進まない。 | Defined |
| `REV-010` | `SRC-REVIEW-002`, `SRC-REVIEW-007` | GitHub Copilot review取得または必須read-only reviewerの実行が完了できない。 | 欠落sourceを明示し、独立reviewが成立していないterminal stopとして通知する。 | 親agentの推測または残り一系統だけでround 1完了を宣言しない。 | Defined |
| `REV-011` | `SRC-REVIEW-004`, `SRC-REVIEW-005`, `SRC-REVIEW-006` | 修正後のpurpose reviewerが一部findingを解消し、別findingを残す。 | 解消・残存を区別して親agentへ返し、round上限内なら残存findingだけを次の修正対象にする。 | 解消済みfindingを無条件に再実装せず、残存findingを黙示的に消さない。 | Defined |
| `REV-012` | `SRC-REVIEW-008`, `SRC-SCOPE-003` | normal-pathのreview/remediationを利用者が実行する。 | 利用者に見える操作は開始とterminal判断に限定され、内部artifactはagent間の追跡に使われる。 | 利用者へ固定thread identity、cycle state、hash、result referenceの管理を課さない。 | Defined |
| `REV-013` | `SRC-REVIEW-009` | review/remediationが完了、human decision、またはblockedでterminalになる。 | 通知から同じ親threadを開け、関連PRがある場合はPRも直接開ける。 | 「終了」だけを表示して戻り先探索を残さない。 | Defined |
| `SCP-001` | `SRC-SCOPE-001` | 複数top-level実装threadや長期中断を伴う特殊運用である。 | MVPの自動orchestration対象外として明示され、人間が手動制御できる。 | 汎用workflow engineとして自動復旧を約束しない。 | ExcludedWithReason |
| `SCP-002` | `SRC-SCOPE-002` | 利用者がnotification timelineまたはAdaptive executor差し替えを求める。 | 今回のMVPでは実装せず、後続課題として分離される。 | 今回のclose条件へ混入しない。 | DeferredWithSource |
| `SCP-003` | `SRC-SCOPE-002` | APMで必要な配布が可能である。 | 現行APM配布を継続する。 | Plugin移行自体を目的達成として扱わない。 | ExcludedWithReason |

## Derived invariants

| Invariant ID | Description | Covered Case IDs | Notes |
| --- | --- | --- | --- |
| `INV-001` | user-visible terminal通知は常に発火元親threadへのdirect linkを保持する。 | `NTF-001`〜`NTF-005`, `REV-006`〜`REV-010`, `REV-013` | result linkは追加導線。 |
| `INV-002` | 通知を有効にする日常操作へDecorator、marker、envelopeを要求しない。 | `NTF-001`, `NTF-008` | 導入時の一度の設定は許容。 |
| `INV-003` | notification side effectは主作業のverdictを変更しない。 | `NTF-006`, `NTF-007` | provider / chain failureを含む。 |
| `INV-004` | parent notificationを中心とし、subagent数に比例するuser-visible通知を生じない。 | `NTF-005` | 実機観測が必要。 |
| `INV-005` | reviewを行うactorと修正write ownerを分離する。 | `REV-002`〜`REV-005`, `REV-008`, `REV-010` | reviewerはread-only、親agentがwrite owner。 |
| `INV-006` | code review二系統はround 1だけ、purpose reviewは各roundで独立に実行する。 | `REV-002`, `REV-004`〜`REV-007`, `REV-011` | 最大3round。 |
| `INV-007` | 未解決finding、必須review欠落、human decisionを黙示的にclose-compatibleへ変換しない。 | `REV-007`〜`REV-011` | explicit stop reasonが必要。 |
| `INV-008` | normal-pathでは利用者がtop-level thread間のmessengerにならない。 | `REV-001`, `REV-004`, `REV-012`, `REV-013` | 同一親thread内で収集・修正・再reviewする。 |

## Excluded combinations / non-goals

| Exclusion ID | Condition / behavior | Source or reason | Reopen condition |
| --- | --- | --- | --- |
| `EX-001` | notification履歴を永続timelineとして閲覧する。 | `SRC-SCOPE-002`: MVP必須ではない。 | direct-link通知のMVPが成立し、別要求として優先された場合。 |
| `EX-002` | 第2round以降もGitHub Copilot / Codex code reviewを再実行する。 | `SRC-REVIEW-005`: 有益性より待機・負担増が大きい。 | 新しいevidenceで目的判断が変更された場合。 |
| `EX-003` | 複数top-level thread間の通信・復旧を汎用state machineで自動化する。 | `SRC-SCOPE-001`: 通常ケースの境界削減を優先する。 | 複雑運用が別MVPとして定義された場合。 |
| `EX-004` | 修正実装をAdaptive Implementation executorへ委譲する。 | `SRC-SCOPE-002`: 次の課題。 | 同一親threadのUXを維持するexecutor contractが別途定義された場合。 |
| `EX-005` | 配布をCodex Pluginへ移行する。 | `SRC-SCOPE-002`: APM継続。 | APMで配布不能となる具体的制約が確認された場合。 |
| `EX-006` | Goal Contextへdraft、human-reviewed、hash等の利用者向け多段承認を必須化する。 | `SRC-SCOPE-003`: review入力以上の負担を課さない。 | security / compliance要求が別sourceとして追加された場合。 |

## Unresolved requirement-elaboration items

| Item ID | Source IDs | Missing decision / ambiguity | Blocking? | Required decision |
| --- | --- | --- | --- | --- |
| `URE-001` | `SRC-NOTIFY-004` | Codex `notify` callbackがsubagent完了にも発火するか、公開payloadだけで親／subagentを識別できるかは未確認。 | No（Plan readinessには非blocking、close readinessにはmanual evidenceが必要） | product semanticsは明確でありhuman decision不要。実機観測によりfilter可能性または既定挙動を記録する。 |

## Handoff Packet

- Profile used: black-box-behavior-spec-kernel
- Behavior spec artifact: `plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-black-box-behavior-spec.md`
- Source artifacts: `docs/goal-context-multi-project-ai-development-notification-and-handoff-reduction.md`、`scripts/codex-notification-runtime/decision-record.md`、`plans/goal-context-multi-project-ai-development-notification-and-handoff-reduction-plan.md`
- Case IDs: `NTF-001`〜`NTF-008`、`REV-001`〜`REV-013`、`SCP-001`〜`SCP-003`
- Files inspected: 上記source artifactsのみ。
- Files intentionally not inspected: production code詳細、test fixture本文、runtime contract、CI log、他package。
- Decisions made: notificationとreview/remediationを別behavior群として展開し、parent-centric notification、same-parent write ownership、round 1 full review、round 2以降purpose-only、最大3roundをinvariant化した。
- Excluded combinations: `EX-001`〜`EX-006`。
- NeedsHumanDecision: なし。
- Do not redo unless new evidence appears: fixed two-top-level-task運用、Decorator必須、各round full code review、Plugin移行をnormal-pathへ戻さない。
- Remaining work: `URE-001`は実機verificationへ渡す。Case-to-Plan mappingは`plan-kernel.agent.md`が所有する。
- Recommended next step: `plan-kernel.agent.md`を再実行し、全Defined / Excluded / Deferred Case IDをFR / ACまたはsource-backed dispositionへmappingして`ReadyForRiskTriage`を判定する。
