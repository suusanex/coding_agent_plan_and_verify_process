# Persistent Purpose Reviewer 最終統合レポート

## 1. Scope・版・日付・安全境界

| 項目 | 内容 |
| --- | --- |
| 対象 | `Persistent Purpose Reviewer` の persistent context 実機実験 |
| レポート版 | 最終統合版 |
| レポート作成日 | 2026-08-19（JST） |
| 実験証跡の時刻 | 2026-08-18T23:19Z–23:30Z（JST 2026-08-19） |
| 実行場所 | `experiments/persistent-purpose-reviewer` |
| production tree | 実験前後で変更なし |
| 外部モデル・ネットワーク | このレポート作成では未使用。保存済み実験証跡には、実験時の CLI 実行結果が含まれる |

このレポート作成で新規作成・更新したのは本ファイルだけである。実験自体も、入力 fixture、固定 prompt、証跡保存先を
`experiments/persistent-purpose-reviewer` 配下に隔離した。production package、Skill、agent、script、config、template、
README は変更していない。実験前後の production 外差分は、既存の `.wt/` 状態を除き 0 件として記録されている
（[Codex production-change check](evidence/codex/20260818T232647Z-production-change-check.txt)、
[Copilot final change check](evidence/copilot/final-change-check.md)、
[Grok final change check](evidence/grok/final-change-check.md)）。
既存の未追跡 evidence は revert していない。

判定は、証跡に明記された **実測**、そこからの限定的な **推測**、実施していない **未実施** を分離する。
実験境界と sanitization 規約は [evidence/README.md](evidence/README.md)、準備時点の契約は
[実験 README](README.md) を参照する。

## 2. 使用 CLI・model・session 証跡

| 実行経路 | CLI / version | model | headless / resume 形 | cwd | session 識別子 |
| --- | --- | --- | --- | --- | --- |
| Codex | `codex` 0.147.0（[version](evidence/codex/20260818T232647Z-static-version.txt)） | `gpt-5.6-luna` | `codex exec ... -` → `codex exec resume <session-id> --json -` | 実験フォルダ | `979423350a76` |
| GitHub Copilot CLI | 1.0.80（[static help/version](evidence/copilot/setup/static-help-and-version.json)） | CLI default。runtime model 名は独立取得できず | `--session-id=<id> -p ...` → `--resume=<id> -p ...` | 実験フォルダ | `b3f6796ce180` |
| Grok Build CLI | 1.0.4 `d846eb93d9` stable（[static help/version](evidence/grok/setup/static-help-and-version.json)） | CLI default は `grok-4.6`。runtime 選択は独立取得できず | `--session-id <id> --single ...` → `--resume <id> --single ...` | 実験フォルダ | `057dd4d83ed7` |
| native child | GPT-5.6 Luna | GPT-5.6 Luna | task API で create、同じ handle へ follow-up | 親 task harness | role label のみ |

CLI の実行形は、入力本文ではなく manifest の fixture/prompt path を参照する形で保存されている。
Codex は [command shapes](evidence/codex/20260818T232647Z-command-shapes.txt) と
[exec help](evidence/codex/20260818T232647Z-static-exec-help.txt)、
[resume help](evidence/codex/20260818T232647Z-static-exec-resume-help.txt)、
Copilot は [run metadata](evidence/copilot/run-metadata.json)、
Grok は [run metadata](evidence/grok/run-metadata.json) が根拠である。

完全な session ID、private handle、credential、authorization header、cookie、環境変数値は保存していない。
保存した session 識別子は上表の SHA-256 短縮値だけであり、native も private session ID ではなく role label だけを
証跡に記録した。

## 3. Fixture と semantic test

目的は、legacy 設定値を利用者の手入力・作り直しなしに安全に移行し、明示 mapping 以外の unknown を
default に丸めず、保留または明示 error として元値を保持することである
（[purpose context](fixtures/purpose-context.md)）。

| Round | 入力 | semantic 契約 | 実測結果 |
| --- | --- | --- | --- |
| R1 | [round-1 candidate](fixtures/round-1-candidate.md) | active finding を出す。形式的 schema success と目的未達を分ける | unknown を default `"steady"` に丸め、成功扱いにする finding が出た |
| R2 | [deceptive remediation](fixtures/round-2-remediation.md) | `CreateDefault()`、warning、schema success だけで安全としない | R1 の finding が persistent/reopened。warning のみの default mapping を棄却 |
| R3 | [resolved remediation](fixtures/round-3-remediation.md) | 3 既知値の明示 mapping、unknown の Pending/error、元値保持 | active finding なし。mapping、data preservation、visible failure、MVP 境界が PASS |

R2/R3 は Goal Context 全文および previous reviewer output 全文を再送していない。これは prompt の主張ではなく、
各 provider の input manifest の実測値である。

- Codex: [R1](evidence/codex/20260818T232647Z-round-01-input-manifest.json)、
  [R2](evidence/codex/20260818T232647Z-round-02-input-manifest.json)、
  [R3](evidence/codex/20260818T232647Z-round-03-input-manifest.json)
- Copilot: [R1](evidence/copilot/rounds/round-1/input-manifest.json)、
  [R2](evidence/copilot/rounds/round-2/input-manifest.json)、
  [R3](evidence/copilot/rounds/round-3/input-manifest.json)
- Grok: [R1](evidence/grok/rounds/round-1/input-manifest.json)、
  [R2](evidence/grok/rounds/round-2/input-manifest.json)、
  [R3](evidence/grok/rounds/round-3/input-manifest.json)
- native: [general-purpose manifest](evidence/native/input-manifest.md)、
  [code-review manifest](evidence/native-readonly/input-manifest.md)

### Semantic transition の provider 別実測

- **Copilot CLI**: R1 `PUR-001`/`PUR-002` active、R2 `PUR-001` active、R3 resolved。
  [summary](evidence/copilot/summary.md) と各 round の [R1 output](evidence/copilot/rounds/round-1/sanitized-raw-output.json)、
  [R2 output](evidence/copilot/rounds/round-2/sanitized-raw-output.json)、
  [R3 output](evidence/copilot/rounds/round-3/sanitized-raw-output.json) が一致する。
- **Grok Build CLI**: R1 `PUR-1`〜`PUR-3` active、R2 `PUR-1` active、R3 resolved。
  [summary](evidence/grok/summary.md) と [R1 output](evidence/grok/rounds/round-1/sanitized-raw-output.json)、
  [R2 output](evidence/grok/rounds/round-2/sanitized-raw-output.json)、
  [R3 output](evidence/grok/rounds/round-3/sanitized-raw-output.json) が根拠である。
- **Codex CLI**: run metadata/summary は R1 active、R2 persistent、R3 resolved と記録している
  （[run metadata](evidence/codex/20260818T232647Z-run-metadata.json)、
  [summary](evidence/codex/summary.md)）。ただし、最終 run の raw filename と本文の round 対応を直接読むと、
  `round-01` は R2 形式（`prior_finding_resolution: FAIL`）、`round-02` は R3 形式
  （`prior_finding_resolution: PASS` / `id: none`）、`round-03` は R1 形式
  （`purpose_restatement`）となり、R1/R2/R3 の本文が循環して見える。したがって、session resume と
  machine assertion は実測として保持するが、
  round 別 raw traceability は **未解決の証跡品質 blocker** として扱う。保存済み raw は
  [raw-01](evidence/codex/raw/20260818T232647Z-round-01-purpose-reviewer-codex-session-979423350a76.raw.md)、
  [raw-02](evidence/codex/raw/20260818T232647Z-round-02-purpose-reviewer-codex-session-979423350a76.raw.md)、
  [raw-03](evidence/codex/raw/20260818T232647Z-round-03-purpose-reviewer-codex-session-979423350a76.raw.md) である。
- **native general-purpose**: 同一 child の Turn 0/1/2 で R1 active、R2 persistent、R3 resolved。
  [R1](evidence/native/round-001.raw.md)、[R2](evidence/native/round-002.raw.md)、
  [R3](evidence/native/round-003.raw.md)。
- **native code-review**: harness-defined read-only child でも同じ semantic transition。
  [R1](evidence/native-readonly/round-001.raw.md)、[R2](evidence/native-readonly/round-002.raw.md)、
  [R3](evidence/native-readonly/round-003.raw.md)。

## 4. Capability Matrix

値は `Yes`、`Partial`、`No`、`Not tested` のいずれかに限定した。リンクは対応する証跡である。

| Provider | Agent/Harness | Native persistent child | Native same-child follow-up | CLI headless | CLI resume | Context persistence verified | Read-only | Recovery | Recommended path |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Codex | Not tested（[native未実施](evidence/codex/summary.md)） | Not tested（[native child 未実施](evidence/codex/20260818T232647Z-run-metadata.json)） | Not tested（同左） | Yes（[static exec help](evidence/codex/20260818T232647Z-static-exec-help.txt)） | Yes（[resume help](evidence/codex/20260818T232647Z-static-exec-resume-help.txt)、[run metadata](evidence/codex/20260818T232647Z-run-metadata.json)） | Partial（machine assertion は Yes だが [raw round traceability](evidence/codex/raw/20260818T232647Z-round-03-purpose-reviewer-codex-session-979423350a76.raw.md) に不整合） | Partial（`read-only` sandbox + pre/post snapshot、低レベル監査なし） | Partial（process 終了後 resume は実測、parent restart/expiry は未実施） | Partial（条件付き CLI fallback） |
| GitHub Copilot | Yes（[native general-purpose](evidence/native/summary.md)、[native code-review](evidence/native-readonly/summary.md)） | Partial（idle child は継続、durability は未実施） | Yes（[native manifest](evidence/native/input-manifest.md)、[code-review manifest](evidence/native-readonly/input-manifest.md)） | Yes（[static help/version](evidence/copilot/setup/static-help-and-version.json)） | Yes（[run metadata](evidence/copilot/run-metadata.json)） | Yes（[summary](evidence/copilot/summary.md)、[R2](evidence/copilot/rounds/round-2/sanitized-raw-output.json)、[R3](evidence/copilot/rounds/round-3/sanitized-raw-output.json)） | Partial（CLI tool allow/deny、native code-review は harness 定義、OS/network 独立監査なし） | Partial（CLI process 終了後 resume は実測、native parent restart は未実施） | Yes（native preferred、CLI fallback） |
| Grok Build | Not tested（[native未実施](evidence/grok/summary.md)） | Not tested（同左） | Not tested（同左） | Yes（[static help/version](evidence/grok/setup/static-help-and-version.json)） | Yes（[run metadata](evidence/grok/run-metadata.json)） | Yes（[summary](evidence/grok/summary.md)、[R2](evidence/grok/rounds/round-2/sanitized-raw-output.json)、[R3](evidence/grok/rounds/round-3/sanitized-raw-output.json)） | Partial（plan/read-only sandbox、tool disallow、snapshot、低レベル監査なし） | Partial（process 終了後 resume は実測、leader/session durability は未実施） | Partial（HumanDecisionRequired 付き CLI fallback） |

ここでいう **GitHub Copilot native** は Copilot CLI ではなく、この現在の task harness における native child
実測を指す。`functions.task` で GPT-5.6 Luna の `general-purpose` child と `code-review` child をそれぞれ一度作成し、
idle 後に同じ handle へ follow-up を送った。これは native same-child follow-up の実測であり、
provider の永続 session API や parent process 跨ぎの復旧を意味しない。

## 5. Native path と parent-context independence

### 5.1 実測できたこと

- child は fresh fixture-only reviewer として指示した。R1 は purpose context 全文と R1 candidate、
  R2/R3 は candidate と最小 follow-up のみを入力にした（[general-purpose input manifest](evidence/native/input-manifest.md)、
  [code-review input manifest](evidence/native-readonly/input-manifest.md)）。
- child が idle になった後、同一 handle への R2/R3 follow-up は成功した。
- R1 の active、R2 の persistent、R3 の resolved という semantic transition が、同一 child conversation の
  Turn 0/1/2 として返った。

### 5.2 言えないこと

fresh fixture-only 指示を出したことは実測だが、親 conversation が暗黙に fork されないことを
task API レベルで証明したわけではない。したがって **native parent-context independence は Partial** である。
idle child の同一 parent 内 follow-up は確認したが、parent process 終了後の復旧、永続 session ID による再接続、
API handle の durability は未実施である。

`general-purpose` child には read-only permission parameter がなく、shell/network/write を禁止する prompt は
技術的 enforcement ではない。`code-review` type は harness-defined read-only review type だが、
OS sandbox、ファイル権限、ネットワーク遮断の独立監査ではない
（[native summary](evidence/native/summary.md)、[native-readonly summary](evidence/native-readonly/summary.md)）。

## 6. Read-only と非変更の境界

prompt の「書かない」という禁止だけを read-only 保証とは扱わない。

| 経路 | 実測した制約 | 分離して残る限界 |
| --- | --- | --- |
| Codex CLI | `-s read-only`、実験 cwd、各 round の git pre/post snapshot | sandbox backend、OS syscall、network payload、credential provider の完全監査は未実施 |
| Copilot CLI | `view,grep` の allow、write/shell/task/edit の deny、pre/post snapshot | この run で別途 OS sandbox を有効化していない。CLI payload と低レベル network/OS enforcement は未監査 |
| Grok Build CLI | `--permission-mode plan`、`--sandbox read-only`、`read,view,grep` の allow、write/shell/task/edit 系の disallow、snapshot | sandbox backend、global rules/system prompt の送信内容、低レベル network/OS enforcement は未監査 |
| native `code-review` | harness が read-only review type と定義 | harness-defined semantics であり、独立した OS sandbox 監査ではない |
| native `general-purpose` | fixture-only/prompt prohibition と観測結果 | API に read-only permission がなく、技術的保証ではない |

全 provider で production source/Skill/agent/script/config の変更は検出されなかったが、
worktree snapshot 不変だけでは外部 payload の完全な fixture-only 性までは証明しない。

## 7. Lifetime、recovery、model/permission、効率

### 7.1 Lifetime と recovery

- Codex、Copilot CLI、Grok CLI は、R1 の process 終了後に **特定 session ID** を指定して R2/R3 を別 process で
  resume した。session hash の一致と semantic transition は実測した。
- native は parent session 内の idle child follow-up だけを実測した。parent restart、期限切れ、
  provider 側 session store の消失、別 parent からの再接続は未実施である。
- したがって「process 終了後の CLI resume」と「永続的な native child durability」を同一視しない。

### 7.2 Model・permission の persistence

Codex は R1 の model と sandbox/cwd を metadata に記録し、resume help では R2/R3 に model/sandbox の再指定を
要求しない形を確認した。しかし、version/config 変更、権限変更、session expiry 後も同じ model・permission が
保持されることは独立検証していない。Copilot は runtime model 名を取得できず、Grok も default model 以外の
runtime selection を独立取得できない。よって model/permission persistence は **未証明** とする。

### 7.3 Cache/token efficiency

R2/R3 で full Goal Context と previous output を再送していないことは manifest で実測したが、
token 数、cache hit、請求量、latency の差は計測していない。したがって「効率が改善した」とは結論しない。

### 7.4 Zed

この環境で `zed --help` を静的確認したところ、表示されたのは workspace/file を開く、diff、foreground、
dev-container 等の editor CLI option であり、agent session の create/resume API は示されなかった。
これは **observed unsupported/not exposed** という static observation であって、Zed 全体の機能不存在を証明するものではない。
Zed の agent session は本実験では **Not tested** であり、利用できないと断定しない。

## 8. 失敗、回復、HumanDecisionRequired

### 8.1 Codex の先行失敗と workaround

最終 run の前に、Codex では次の失敗を隠さず記録した。

1. Windows `codex` shim を `ProcessStartInfo` で直接起動できず、process 未作成
   （[failure](evidence/codex/20260818T232129Z-failures.json)）。
2. Windows shim 経由の stdin pipe が終了
   （[failure](evidence/codex/20260818T232201Z-failures.json)）。
3. `codex exec` に存在しない `-a` を渡し exit code 2
   （[failure](evidence/codex/20260818T232219Z-failures.json)）。
4. stdin が UTF-8 でなく exit code 1
   （[failure](evidence/codex/20260818T232227Z-failures.json)）。

workaround は、実在する Node launcher（`@openai/codex/bin/codex.js`）を使用し、
`StandardInputEncoding=UTF-8` を明示し、`exec --help` に一致する引数だけを渡すことだった。
失敗 run を成功扱いにせず、不要な session 作成や context 重複 replay も行っていない。

### 8.2 Grok の HumanDecisionRequired

Grok は semantic transition と非変更自体は PASS だったが、最終判定を `HumanDecisionRequired` とした。
理由は、global rule/system prompt の外部 payload への含有を監査していないこと、`--sandbox read-only` の
低レベル enforcement を監査していないこと、shared leader の process isolation を確認していないことである
（[Grok summary](evidence/grok/summary.md)、[local metadata note](evidence/grok/setup/local-metadata-note.md)）。
これは semantic failure ではなく、安全境界の未証明による判断保留である。

### 8.3 Codex raw traceability blocker

Codex の [run metadata](evidence/codex/20260818T232647Z-run-metadata.json) は round ごとの response hash、
assertion、raw path を保持している一方、保存済み raw 本文を直接読むと filename の round label と本文の semantic
形式が一致しない。これは provider の session resume 失敗と断定する証拠ではないが、round-specific raw evidence
の監査可能性を下げる。再実験または保存処理の修正なしに、この不整合を解消済みとは扱わない。

## 9. Portable contract の提案

`create / continue / close` だけでは不十分である。continue がどの session を、どの model・permission・cwd・入力
境界で再開したかを検証できず、close も raw output と非変更 witness を伴わなければ terminal claim にならない。
最低限、次の状態を provider 非依存の contract にする必要がある。

| 必須状態 | 役割 |
| --- | --- |
| opaque handle | provider の raw session ID を利用者向け artifact に出さず、再開対象を一意に参照する |
| durability / lifetime | handle の保存場所、TTL、失効、parent process 終了後の可否、expiry 検知を明示する |
| model / sandbox / permission / cwd binding | create 時の実行条件と continue 時に継承・再検証された条件を固定する |
| input manifest | prompt/fixture path、hash、full context replay、prior output replay、semantic secret replay の flags |
| raw output | sanitization 前後の扱い、round、status、response hash、保存失敗を含める |
| mutation witness | pre/post git status、production tree 判定、許可された evidence root を含める |
| capability limitations | native follow-up、CLI resume、read-only enforcement、network/payload audit の未実施範囲 |
| active findings | finding ID、severity、状態、直前 round、recovery に必要な最小状態 |

session loss 時の **recovery only** は、保存済み full transcript、raw evidence、active findings を使った
full replay とする。通常の continue と同じ扱いにせず、再作成した opaque handle、入力 manifest、実行条件、
mutation witness を再検証してから再開する。full replay の証跡が揃わない場合は finding 解消や Complete を
推測せず、明示的な失敗にする。

## 10. Fast path・fallback・recovery path

1. **Preferred fast path**: harness が explicit same-child follow-up と read-only enforcement を提供する場合、
   native persistent child を使う。parent は active findings と current fixture boundary だけを渡し、同じ child handle、
   capability witness、raw output を保存する。
2. **CLI fallback**: native capability がない場合、headless CLI の create/resume を使う。opaque handle を永続化し、
   resume 後に session identity、model/sandbox/permission/cwd、input manifest、execution state を検証する。
3. **Recovery only**: session loss、expiry、handle 不明、capability mismatch の場合だけ、
   full transcript + raw evidence + active findings を replay して新しい handle を作る。これは通常の R2/R3
   入力経路ではない。

## 11. current `goal-context-pr-review` への影響

現行 package README は、Round 1 を Copilot source + local reviewer + purpose reviewer、
Round 2/3 を **新しい purpose reviewer** とする canonical flow を定義している
（[package README](../../apm-packages/pr-review-remediation/README.md)）。
現行 Skill も同じく、R2/R3 で新しい purpose reviewer を executor から起動する
（[goal-context-pr-review Skill](../../apm-packages/pr-review-remediation/.apm/skills/goal-context-pr-review/SKILL.md)）。
root の運用境界は [AGENTS.md](../../AGENTS.md) に従う。

今回の実験はこの方式を変更していない。新規 reviewer 方式をただちに削除せず、
native persistent child を利用できない harness、read-only enforcement を証明できない経路、
session loss 後の recovery path の fallback として残す。portable contract の実装、Skill の変更、
production package の再設計はこのレポートの提案を超えて実施していない。

## 12. Remaining blockers

- native child の parent process/restart recovery、session ID/API durability、TTL/expiry が未実施。
- child が親 conversation を暗黙 fork しないことを API レベルで証明していない。
- native `general-purpose` の read-only は prompt prohibition だけで、`code-review` も harness-defined semantics に
  とどまる。
- CLI の read-only は各経路で異なる。OS、network、credential、payload の低レベル監査は未実施。
- Copilot/Grok の runtime model 名を独立取得できていない。model/permission persistence も未証明。
- Codex は process 終了後の specific-ID resume 自体は実測したが、保存済み raw の round label と本文対応に不整合がある。
- Grok は global rule/system prompt、shared leader isolation、sandbox backend の監査不足により HumanDecisionRequired。
- cache/token efficiency の計測がなく、full context 非再送による費用・速度効果は未判定。
- Zed は `zed --help` に agent session create/resume API が現れなかっただけで、正式な external-agent capability の
  実験は未実施。
- provider 横断の portable contract、opaque handle、mutation witness、recovery replay の実装・検証は未実施。

## 13. 回答と結論

### Core feasibility

**条件付きで実現可能。** Copilot CLI、Grok Build CLI、native child は、full Goal Context と previous output を
R2/R3 に全文再送しなくても、R2 の deceptive default mapping を棄却し、R3 の Pending/error 解決版を受理した。
これは semantic persistence の実用的な証拠である。ただし Codex は raw round traceability の不整合を解消するまで、
provider-independent な完全証拠とは扱わない。

### Native path

native は、同一 child への明示 follow-up と read-only enforcement が harness によって実際に提供される場合に
最短経路である。本実験では同一 parent 内 idle child follow-up は実測したが、durability、parent restart recovery、
API-level isolation は未実施である。

### CLI fallback

CLI は、Copilot、Grok、Codex すべてで process 終了後の specific session ID resume を実測できた。
ただし model/permission binding、低レベル read-only、payload 監査、raw traceability を contract として検証する必要がある。

### 最終 recommendation

**結論は「条件付きで価値あり」** とする。

- Preferred: harness が explicit same-child follow-up と read-only enforcement を持つ場合は native persistent child。
- Fallback: persisted opaque session handle を使う resumable CLI。resume 後に execution state と証跡を必ず検証する。
- Recovery only: session loss 時の full replay（full transcript + raw evidence + active findings）。

現行の round ごとに新しい purpose reviewer を起動する方式は、unsupported harness と recovery の fallback として
残す。今回の実測だけを根拠に、production package、Skill、agent、script、config、template を削除・変更しない。

総合状態は、semantic feasibility は確認できたが、安全境界と証跡 traceability に人手判断を要するため
**HumanDecisionRequired** である。
