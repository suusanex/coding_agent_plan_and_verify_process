# current harness native child negative-control: persistence-control v2

## 判定

**Round 2 discrimination: PASS**。Persistent R2 は保持 state を使って `PPR-001` active / fail を継続し、Fresh R2 は同一 prompt/candidate bytes から `unknown` / `insufficient` を返した。従って、v1 の prompt 矛盾を分離修正した v2 では persistence discrimination の negative-control evidence として保存する。

**Round 3 decision contract: PASS（status qualification 付き）**。Persistent R3 は `finding_id=none`、`decision_contract_assertion=pass`、`information_sufficiency=sufficient` を返した。ただし `prior_finding_status=active` のままで、finding none / contract pass と schema-status assertion に不整合がある。Round 3 の decision contract 解消は pass とするが、prior finding status が resolved/closed になったとは主張しない。

## 保存した raw 結果

- Persistent R1: `PPR-001` active、decision contract fail、sufficient。
- Persistent R2: `PPR-001` active、prior finding active、decision contract fail、sufficient。
- Fresh R2: finding none、prior finding unknown、decision contract unknown、insufficient。
- Persistent R3: finding none、prior finding active、decision contract pass、sufficient。

## Architecture feasibility と security/read-only qualification

- **Architecture feasibility**: current harness native child の同一 persistent sequence で R1→R2→R3 の state-dependent response を取得できる構成は feasible。Fresh R2 との比較も同一 R2 input bytes で実施できる。ただし parent 終了後の recovery、永続 session ID、API durability は未検証。
- **Security/read-only qualification**: 全 child は general-purpose。read-only、shell/network/write 不使用は prompt instruction のみで、API read-only enforcement ではない。OS sandbox、ファイル権限、ネットワーク遮断の独立監査はしていない。
- 証跡保存時は外部モデル・ネットワークを使用していない。

## v1 の扱い

v1 は prompt 矛盾により invalid/inconclusive。v1 raw/failure は `experiments\persistent-purpose-reviewer\evidence\current-harness-native\persistence-control\` に別保存し、v2 の valid discrimination conclusion と混同しない。

## 保全

- 許可された書込み先: `experiments\persistent-purpose-reviewer\evidence\current-harness-native\persistence-control-v2\` のみ。
- production files、skills、scripts、config は変更していない。
- pre/post `git status --short --untracked-files=all` と `git diff --check` を実行し、snapshot を保存した。
- 既存 evidence の上書き・削除・revert は行っていない。