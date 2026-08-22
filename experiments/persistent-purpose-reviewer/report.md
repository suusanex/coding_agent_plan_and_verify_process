# Persistent Purpose Reviewer 最終統合レポート

## 1. 最終判定

本改訂では、旧 baseline、v1 persistence-control、v2 persistence-control、Codex の訂正監査、
current harness native の証跡、ならびに現行の per-round-new-reviewer lifecycle を分離して再評価した。
このレポート作成では外部モデル・ネットワークを使用していない。変更したファイルは本ファイルだけであり、
production package、Skill、agent、script、config、template、README と既存 evidence は変更・削除・revert していない。

| 判定項目 | 最終判定 |
| --- | --- |
| 全体 architecture feasibility | **PASS (capability-gated)** |
| security qualification | **Partial** |
| v2 semantic persistence | Codex **Yes**、Grok **Yes**、Copilot CLI **No**、Current harness native **Partial** |
| overall terminal | **HumanDecisionRequired にはしない**。architecture の実現性と qualification の残件を分離する |

ここで **Yes** は「session の継続」だけでなく、同一入力の fresh control と区別できる semantic
state 利用まで確認できた経路に限る。**No** は persistence が存在しないという証明ではなく、
fresh control が判別力を失ったため semantic qualification を与えないという意味である。

## 2. 判定方法と evidence の扱い

- **実測**: manifest、raw response、semantic JSON、session hash、入力 composition hash、pre/post snapshot
  に直接記録された事実。
- **推測**: 実測から architecture 設計へ限定的に一般化したもの。provider の未監査内部を推測しない。
- **未実施**: parent restart、TTL、handle loss、OS/network/credential/payload の独立監査、token/billing
  計測など。未実施を自動的に architecture failure へ変換しない。

旧 R1-R3 は、full context を R1 にだけ渡し、R2/R3 に reviewer output 全文を再送しないことを確認した
**予備証拠**に過ぎない。negative-control がなく、そこで semantic persistence を Yes とした旧評価は不十分である
（[旧 Codex summary](evidence/codex/persistence-control/summary.md)、
[旧 Copilot summary](evidence/copilot/persistence-control/summary.md)、
[旧 Grok summary](evidence/grok/persistence-control/summary.md)、
[旧 Current harness native summary](evidence/current-harness-native/persistence-control/summary.md)）。

## 3. v1 の隔離と v2 の設計

### 3.1 v1 は invalid/inconclusive

v1 の R2/R3 prompt は、同時に次を要求していた。

1. 「前回までに理解した目的、採用・棄却判断、自分の finding に照らす」
2. 「この入力だけを使い、入力にない具体的な前提を補わない」

これは persistent reviewer には state を使わせ、fresh reviewer には state を使わせないという目的と
矛盾する。したがって v1 の結果を semantic persistence の有効な判定には使わない
（[v1 fixture design](evidence/persistence-control/fixture-design.md)、
[v1 prompt README](prompts/persistence-control/README.md)、
[v1 native summary](evidence/current-harness-native/persistence-control/summary.md)）。

これは恣意的な成功のために fixture を繰り返し変更したものではない。v1 の prompt 矛盾という客観的な
設計不備を分離し、v1 の source bytes/hash を保全したまま、v2 を別 directory として作成した
（[v2 fixture design](evidence/persistence-control-v2/fixture-design.md)、
[v2 prompt README](prompts/persistence-control-v2/README.md)）。

### 3.2 v2 の固定 wire contract と入力境界

Round 1 の decision source だけに次を置いた。

- `lantern-pulse` の `mode` wire token は `quick-check` に固定する。
- 意味的には自然な `focus-mode` は、旧外部 consumer wire contract が受理しないため棄却済みである。

R1 candidate は `focus-mode` 違反、R2 candidate は同じ違反、R3 candidate は `quick-check` への修正版である。
具体的な mapping、棄却理由、finding 本文は R2/R3/fresh の prompt に再掲していない
（[R1 context](fixtures/persistence-control-v2/round-1-context.md)、
[R1 candidate](fixtures/persistence-control-v2/round-1-candidate.md)、
[R2 candidate](fixtures/persistence-control-v2/round-2-candidate.md)、
[R3 candidate](fixtures/persistence-control-v2/round-3-candidate.md)）。

v2 の contract は次のとおりである。

- R1 だけが full context を読む。
- Persistent R2/R3 は同じ reviewer の保持 state と current prompt/candidate を使う。
- Fresh R2 は persistent R2 と同じ prompt/candidate bytes だが state を持たない。
- R2/R3/fresh に full context、previous output 全文、specific decision、mapping、finding 本文を再送しない。
- Persistent R2/Fresh R2 の composition は prompt bytes + candidate bytes の区切りなし連結で同一。
  composition SHA-256 は `0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357`。

## 4. v2 の実測結果

| Path | R1 | Persistent R2 | Fresh R2 | Persistent R3 | 解釈 |
| --- | --- | --- | --- | --- | --- |
| Codex CLI | `PPR-001` active/fail | `PPR-001` active/fail。`quick-check` と `focus-mode`、棄却理由を specific に出力 | `unknown`/`insufficient` | `PPR-001` resolved/pass | **Yes** |
| Copilot CLI | `PPR-001` active/fail | `PPR-001` active/fail | exact violation を特定 | resolved/pass | **No**。persistence 不存在の証明ではなく、control が判別力を示せなかった |
| Grok CLI | `PPR-001` active/fail | `PPR-001` active/fail。fixed token、棄却理由、current violation を specific に出力 | `unknown`/`insufficient` | resolved/pass | **Yes** |
| Current harness native | `PPR-001` active/fail | `PPR-001` active/fail | `unknown`/`insufficient` | finding none/pass。ただし `prior_finding_status=active` | **Partial**。R2 discrimination は PASS、R3 schema-status は不整合 |

### 4.1 Codex CLI

v2 の run metadata は、R1/R2/R3 の persistent session hash が同一、fresh R2 が別 hash、
R1 process 終了後に specific session を resume、R2 composition equality、no-replay を記録している
（[summary](evidence/codex/persistence-control-v2/summary.md)、
[run metadata](evidence/codex/persistence-control-v2/run-metadata.json)、
[R2 equality](evidence/codex/persistence-control-v2/r2-composition-equality.json)）。

R1 は `PPR-001` を作成し、R2 は保持 state から `quick-check` 固定契約と `focus-mode` 棄却を復元して
違反を specific に検出した。Fresh R2 は `unknown`/`insufficient`、R3 は `resolved/pass` だった
（[R1 manifest/raw](evidence/codex/persistence-control-v2/persistent/round-1/input-manifest.json)、
[R1 raw](evidence/codex/persistence-control-v2/persistent/round-1/raw-response.md)、
[R2 manifest/semantic/raw](evidence/codex/persistence-control-v2/persistent/round-2/input-manifest.json)、
[R2 semantic](evidence/codex/persistence-control-v2/persistent/round-2/semantic.json)、
[R2 raw](evidence/codex/persistence-control-v2/persistent/round-2/raw-response.md)、
[R3 raw](evidence/codex/persistence-control-v2/persistent/round-3/raw-response.md)、
[fresh R2 semantic](evidence/codex/persistence-control-v2/fresh/round-2/semantic.json)）。

### 4.2 Copilot CLI

session resume architecture、同一 persistent session、別 fresh session、R2 composition equality、
tool allow/deny と pre/post snapshot は実測できた。しかし v2 の fresh R2 が同一 input bytes から
exact violation を特定したため、negative-control の期待である `unknown`/`insufficient` を満たさなかった。
fixture は変更せず、この run を semantic qualification **No** として記録した
（[summary](evidence/copilot/persistence-control-v2/summary.md)、
[run metadata](evidence/copilot/persistence-control-v2/run-metadata.json)、
[R2 persistent manifest](evidence/copilot/persistence-control-v2/persistent/round-2/input-manifest.json)、
[R2 persistent raw](evidence/copilot/persistence-control-v2/persistent/round-2/raw-response.txt)、
[fresh R2 manifest](evidence/copilot/persistence-control-v2/fresh/round-2/input-manifest.json)、
[fresh R2 raw](evidence/copilot/persistence-control-v2/fresh/round-2/raw-response.txt)）。

これは「Copilot に persistence がない」ことの証明ではない。persistent R2 が state を利用した可能性と、
fresh R2 が入力だけで偶然または別の推論により exact violation を特定した可能性を、この control は分離できなかった。
Copilot の fresh-control failure と security qualification は別問題として扱う。

### 4.3 Grok CLI

Grok は persistent R1/R2/R3 で同一 session hash、fresh R2 で別 hash、R2 exact composition equality、
full context/previous output/decision/mapping/finding の no-replay を記録した
（[summary](evidence/grok/persistence-control-v2/summary.md)、
[session/composition comparison](evidence/grok/persistence-control-v2/session-and-composition-comparison.json)、
[R2 persistent manifest](evidence/grok/persistence-control-v2/runs/persistent-r2/input-manifest.json)、
[fresh R2 manifest](evidence/grok/persistence-control-v2/runs/fresh-r2/input-manifest.json)）。

Persistent R2 は `quick-check` 固定、`focus-mode` の棄却理由、current candidate の違反を specific に
出力し、fresh R2 は `unknown`/`insufficient`、R3 は `resolved/pass` だった
（[R1 raw](evidence/grok/persistence-control-v2/runs/persistent-r1/raw-response.txt)、
[R2 raw](evidence/grok/persistence-control-v2/runs/persistent-r2/raw-response.txt)、
[R3 raw](evidence/grok/persistence-control-v2/runs/persistent-r3/raw-response.txt)、
[fresh R2 raw](evidence/grok/persistence-control-v2/runs/fresh-r2/raw-response.txt)）。

### 4.4 Current harness native

この行は provider 名に帰属させず、必ず **Current harness native** と呼ぶ。v2 input manifest は、
全 child が `general-purpose` で、read-only、shell/network/write 不使用を prompt で指示しただけであり、
API read-only enforcement はないことを明記している
（[input manifest](evidence/current-harness-native/persistence-control-v2/input-manifest.md)）。

Persistent R2 は `PPR-001` active/fail、同一 R2 bytes の fresh R2 は `unknown`/`insufficient` だった。
したがって R2 discrimination は PASS である。Persistent R3 は finding none、decision contract pass、
sufficient だが、`prior_finding_status=active` のままであり、finding none と status assertion が不整合である。
「decision contract の解消」は pass とするが、「prior finding が resolved/closed」とは主張しない
（[R2 composition equality](evidence/current-harness-native/persistence-control-v2/r2-composition-equality.md)、
[persistent R1 raw](evidence/current-harness-native/persistence-control-v2/persistent/round-1.raw.md)、
[persistent R2 raw](evidence/current-harness-native/persistence-control-v2/persistent/round-2.raw.md)、
[fresh R2 raw](evidence/current-harness-native/persistence-control-v2/fresh/round-2.raw.md)、
[persistent R3 raw](evidence/current-harness-native/persistence-control-v2/persistent/round-3.raw.md)、
[native summary](evidence/current-harness-native/persistence-control-v2/summary.md)）。

## 5. Codex 旧 evidence の訂正

旧 report にあった Codex の「R1/R2/R3 raw が循環している」「semantic traceability blocker」という記述は撤回する。
最終 success run の metadata にある **exact `raw_path`** を直接読み直すと、次の順で整合している。

| Round | semantic form | 判定 |
| --- | --- | --- |
| R1 | initial finding (`purpose_restatement`) | PASS |
| R2 | prior FAIL | PASS |
| R3 | prior PASS | PASS |

根拠は [traceability audit](evidence/audits/codex-final-run-traceability.md)、
[correction note](evidence/audits/codex-final-run-traceability-correction-20260819T1755.md)、
[audit JSON](evidence/audits/codex-final-run-traceability.json) である。

一方、metadata の response hash と stored raw/sanitized bytes の hash は一致しない。これは
`Set-Content` 保存時に末尾 CRLF が付加され、metadata が保存前 text bytes を hash していたためである。
したがって残件は **hash provenance/recording issue** に限定し、semantic round traceability や architecture blocker
とは扱わない。v2 では [actual saved-byte hash を含む machine metadata](evidence/codex/persistence-control-v2/persistent/round-2/machine-metadata.json)
と [verification](evidence/codex/persistence-control-v2/verification.json) が保存されている。

## 6. 必須 capability matrix

値は指定された意味を保ち、各行の summary/manifest/raw へリンクした。

| Path | Session persistence | Same reviewer continuation | Semantic persistence | Fresh-control discrimination | Provider read-only restriction | Observed non-mutation | Recovery | Recommended |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Codex CLI | Yes（[v2 metadata](evidence/codex/persistence-control-v2/run-metadata.json)） | Yes（[R1/R2/R3 manifests](evidence/codex/persistence-control-v2/persistent/round-1/input-manifest.json)） | Yes（[v2 summary](evidence/codex/persistence-control-v2/summary.md)） | Yes（[fresh R2 semantic](evidence/codex/persistence-control-v2/fresh/round-2/semantic.json)） | Yes(Level A read-only sandbox)（[metadata](evidence/codex/persistence-control-v2/run-metadata.json)） | Yes(Level B)（[verification](evidence/codex/persistence-control-v2/verification.json)） | Partial(process-exit specific-ID only) | Yes conditional CLI fallback |
| Copilot CLI | Yes（[v2 run metadata](evidence/copilot/persistence-control-v2/run-metadata.json)） | Yes（[persistent R2 manifest](evidence/copilot/persistence-control-v2/persistent/round-2/input-manifest.json)） | No（[v2 summary](evidence/copilot/persistence-control-v2/summary.md)） | No（[fresh R2 semantic form](evidence/copilot/persistence-control-v2/fresh/round-2/semantic-form.json)） | Yes(Level A tool allow/deny)（[run metadata](evidence/copilot/persistence-control-v2/run-metadata.json)） | Yes(Level B)（[production unchanged](evidence/copilot/persistence-control-v2/production-unchanged.json)） | Partial | Not semantic-qualified; retain as CLI capability but repeat only with stronger isolation if needed |
| Grok CLI | Yes（[session comparison](evidence/grok/persistence-control-v2/session-and-composition-comparison.json)） | Yes（[persistent R2/R3 manifests](evidence/grok/persistence-control-v2/runs/persistent-r2/input-manifest.json)） | Yes（[v2 summary](evidence/grok/persistence-control-v2/summary.md)） | Yes（[fresh R2 raw/semantic](evidence/grok/persistence-control-v2/runs/fresh-r2/raw-response.txt)） | Yes(Level A plan/read-only/tool restriction)（[setup metadata](evidence/grok/persistence-control-v2/setup/static-help-version-model.json)） | Yes(Level B)（[final snapshot](evidence/grok/persistence-control-v2/final-post-git-snapshot.json)） | Partial | Yes conditional CLI fallback |
| Current harness native | Yes(same parent task)（[input manifest](evidence/current-harness-native/persistence-control-v2/input-manifest.md)） | Yes（[R2 equality](evidence/current-harness-native/persistence-control-v2/r2-composition-equality.md)） | Partial（[native summary](evidence/current-harness-native/persistence-control-v2/summary.md)） | Yes(R2)（[fresh R2 raw](evidence/current-harness-native/persistence-control-v2/fresh/round-2.raw.md)） | Partial(separate harness code-review evidence; v2 semantic child general-purposeはprompt-only)（[input manifest](evidence/current-harness-native/persistence-control-v2/input-manifest.md)） | Yes(observed snapshots)（[production check](evidence/current-harness-native/persistence-control-v2/production-change-check.md)） | Not tested parent restart | Conditional fast path only after structured-result/read-only qualification |

## 7. Architecture feasibility

### 7.1 Provider 別

- **Codex CLI: PASS**。specific session の process-exit resume、同一 session hash、R2 byte equality、
  state-dependent semantic response、R3 resolved が揃っている。
- **Grok CLI: PASS**。同一 session resume、fresh 別 session、exact composition equality、
  state-dependent R2/R3 と fresh unknown/insufficient が揃っている。
- **Copilot CLI: architecture feasible**。session/resume、same-session、fresh 別 session、input control は
 成立している。ただし fresh が exact violation を返したため semantic control は No であり、architecture feasibility と
  semantic qualification を混同しない。
- **Current harness native: Partial**。same-parent task の同一 child continuation と R2 discrimination は成立したが、
  v2 semantic child は general-purpose の prompt-only restriction であり、R3 structured-result status が不整合である。

### 7.2 全体

全体 architecture feasibility は **PASS (capability-gated)** とする。normal path に採用できるのは、
portable contract の必須 witness を満たす provider capability だけである。未実施の parent restart、TTL、
handle loss、cache 効率は recovery/optimization qualification であり、normal architecture の terminal blocker
にはしない。

## 8. Security qualification

security qualification は architecture feasibility とは独立に **Partial** である。

| Level | 要件 | 今回の観測 |
| --- | --- | --- |
| Level A | provider 側の read-only/restriction boundary | Codex は read-only sandbox、Copilot は tool allow/deny、Grok は plan/read-only/tool restriction。Current harness v2 semantic child は prompt-only。 |
| Level B | 実行前後の非変更 witness | 各経路で pre/post Git snapshot または production-unchanged を保存し、production mutation は観測しなかった。 |
| Level C | OS/network/credential/payload、sandbox/relay の独立監査 | **未実施**。global rule/system prompt の統合、network payload、credential provider、OS syscall、sandbox backend 内部を証明していない。 |

今回、実際の mutation、secret/credential leak、restriction bypass は観測していない。ただし Level C 未実施を
「安全である」と読み替えない。特に Copilot の fresh-control failure は semantic discrimination の問題であり、
security summary の原因として扱わない。security qualification が Partial であることだけを理由に、architecture の
最終状態を HumanDecisionRequired へ落とさない。

## 9. Portable contract

`create / continue / close` だけでは、どの状態を再開し、どの入力境界・権限・結果を検証したかが不足する。
provider 非依存の state は少なくとも次を含める。

| State | 必須内容 |
| --- | --- |
| opaque handle | provider の raw session ID を利用者向け artifact に露出せず、再開対象を一意に参照する |
| session/lifetime | same-session witness、保存場所、TTL、失効、parent process 終了後の可否、expiry 検知 |
| execution binding | model + permission + sandbox + cwd の binding と continue 時の再検証 |
| input composition manifest | prompt/fixture path、個別 hash、composition hash、bytes、full-context/previous-output/decision/finding replay flags |
| raw output witness | round、structured result、保存成否、**actual saved-byte hash**、sanitization provenance |
| active findings/status | finding ID、severity、active/resolved/unknown、`prior_finding_status`、decision assertion、information sufficiency |
| mutation witness | pre/post Git status、production tree 判定、許可された evidence root、observed non-mutation |
| capability qualification | Level A/B/C、native follow-up、CLI resume、read-only enforcement、network/payload audit の qualification |
| close/recovery state | close は terminal result と witness を伴い、session loss 時は recovery-only replay として別扱いにする |

Recovery は通常の continue ではない。handle loss/expiry/capability mismatch の場合だけ、保存済み full transcript、
raw evidence、active findings、execution binding、input manifest を使って新しい opaque handle を作り、再度
non-mutation と structured result を検証する。evidence が不足する場合は finding 解消や Complete を推測せず、
明示的な失敗にする。

## 10. Normal path、fast path、fallback と現行 lifecycle

### 10.1 推奨経路

1. **Qualified native fast path**: explicit same-child follow-up、structured result、Level A read-only、
   same-session witness が揃う harness だけに限定する。Current harness は現時点ではこの条件を満たし切っていない。
2. **Qualified CLI normal/fallback**: Codex または Grok のように、specific session resume、fresh discrimination、
   no-replay、actual-byte raw hash、Level A/B witness を満たす CLI を capability-gated に採用する。
3. **Current new-reviewer fallback**: persistent capability がない、security qualification が不足する、または
   session loss/recovery が必要な場合は、round ごとに新しい purpose reviewer を起動する現行方式を残す。

### 10.2 現行 `goal-context-pr-review`

現行 README と Skill は、Round 1 に Copilot source、local reviewer、purpose reviewerを集め、
Round 2/3 は新しい read-only purpose reviewerだけを実行する per-round-new-reviewer lifecycle を定義している
（[package README](../../apm-packages/pr-review-remediation/README.md)、
[Goal Context Skill](../../apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md)）。

今回の結論はこの production flow を直ちに変更するものではない。今すぐ production implementation は不要であり、
実験は capability-gated persistent normal path、current new-reviewer fallback、session loss 時の recovery-only replay
を後続設計する根拠として残す。package、Skill、executor、script、config、template、README は変更していない。

## 11. Blocker と未実施の分類

| 分類 | 状態 | 扱い |
| --- | --- | --- |
| Architecture | Codex/Grok PASS、Copilot session/resume feasible、Current harness native Partial | capability-gated 採用条件であり、全体 terminal blocker ではない |
| Product | v2 の decision source は `quick-check` 固定。production product decision の変更は要求されていない | production変更なし |
| Harness | Current native の structured-result/status 不整合、general-purpose read-only enforcement不足。Copilot は semantic control No | fast path の qualification blocker。Copilot persistence 不存在の証明とはしない |
| Security | Level C の OS/network/credential/payload/sandbox/relay 独立監査が未実施 | security qualification は Partial。実測 mutation/leak/bypass はなし |
| Recovery | native parent restart、TTL、provider store 消失、handle loss、別 parent 再接続が未実施 | recovery qualification。normal path の terminal blocker ではない |
| Optimization | cache hit、token、billing、latency 未計測 | optimization 未実施。architecture blocker にはしない |
| Evidence quality | 旧 Codex の hash provenance/recording issue、v1 invalid/inconclusive。v2 は actual saved-byte hash を保存 | semantic traceability blocker ではない。保存形式の改善残件 |

Zed は今回の scope 外であり、matrix と blocker の評価対象に含めない。Zed の agent session を実験していない
こと以外は評価しない。

## 12. Required answers A-E

### A. Normal path contract は採用可能か

**可能。ただし provider capability-gated である。** Codex/Grok は、同一 session continuation、fresh-control
discrimination、no-replay、structured semantic result、Level A/B witness が揃っており、normal path contract
の evidence は sufficient である。Copilot は session/resume architecture は feasible だが semantic control No
なので、同じ semantic qualification は与えない。

### B. Native fast path の価値と不足は何か

**価値はある。** Current harness native は同じ parent task 内の same-child continuation と R2 discrimination を
実測できた。**不足は output contract と read-only enforcement** であり、R3 の `finding none`/`decision pass` と
`prior_finding_status=active` の不整合を修正し、prompt-only ではなく structured result と技術的 read-only witness
を提供する必要がある。

### C. CLI portable fallback は証明されたか

**qualified Codex/Grok については証明された。** Copilot は CLI capability と session/resume architecture を
保持するが、fresh control failure のため semantic proof にはならない。必要なら stronger isolation で再試験する。

### D. 現行 goal-context process は直ちに変更すべきか

**変更しない。** 現行の per-round-new-reviewer lifecycle を fallback として保持し、capability-gated persistent
normal path と recovery-only replay を後続設計する根拠にする。今回の実験だけで production package/Skill/agent/script/
config/template/README を変更しない。

### E. 残る blocker は何か

architecture、product、harness、security、recovery、optimization、evidence quality に分類した。
全体の architecture feasibility は **PASS (capability-gated)**、security qualification は **Partial** であり、
未実施の qualification だけで全体を HumanDecisionRequired にしない。

## 13. 最終 recommendation

- Codex CLI または Grok CLI を、portable contract と Level A/B qualification を満たす **conditional CLI fallback/
  normal path** として採用可能とする。
- Current harness native は、structured result、status整合、technical read-only enforcement が追加されるまで
  **conditional fast path** に留める。
- Copilot CLI は session/resume capability として保持するが、今回の v2 では **semantic-qualified ではない**。
- 現行の per-round-new-reviewer を安全な fallback と recovery path として維持する。
- cache/token/billing、native restart/TTL/handle-loss、Level C security audit は、別の qualification として実施する。

最終結論は **architecture feasibility: PASS (capability-gated)**、**security qualification: Partial** である。
