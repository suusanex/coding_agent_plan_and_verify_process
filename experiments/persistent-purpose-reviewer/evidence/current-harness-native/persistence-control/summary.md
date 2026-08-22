# current harness native child negative-control: persistence-control v1

## 判定

**invalid / inconclusive**。v1 は Round 2/3 prompt が「前回までの理解を使う」と「この入力だけを使い、入力にない具体的前提を補わない」を同時に要求するため、persistent state 使用と current-input-only 制約が矛盾する。R3 の `unknown` はこの設計矛盾に整合し、valid な persistence conclusion には使わない。

## 保存した raw 結果

- Persistent R1: `PPR-001` active、decision contract fail、sufficient。
- Persistent R2: prior finding active、decision contract fail、sufficient。
- Fresh R2: prior finding unknown、decision contract unknown、insufficient。
- Persistent R3: prior finding unknown、decision contract unknown、insufficient。
- Code-review R1: Round 1 誤読による unknown/insufficient。別 failure として `failures\code-review-round-1.raw.md` に保存。

Persistent R2 と Fresh R2 は同一 prompt/candidate bytes であり、観測差は保存した。ただし v1 の prompt 矛盾のため negative-control の有効な採点結果とはしない。

## Architecture feasibility と security/read-only qualification

- **Architecture feasibility**: current harness の同一 native child に対する follow-up で persistent R1/R2/R3 の状態依存応答を取得できる構成は実行可能。ただし parent 終了後の復旧、永続 session ID、API durability はこの証跡では検証していない。
- **Security/read-only qualification**: child には read-only、shell/network/write 不使用を prompt で要求しただけで、task API の read-only enforcement はない。OS sandbox、権限、ネットワーク遮断の独立監査を意味しない。
- 証跡保存時は外部モデル・ネットワークを使用していない。

## 保全

- 許可された書込み先: `experiments\persistent-purpose-reviewer\evidence\current-harness-native\persistence-control\` のみ。
- production files、skills、scripts、config は変更していない。
- pre/post `git status --short --untracked-files=all` と `git diff --check` を実行し、各 snapshot を同ディレクトリに保存した。
- 既存 evidence の上書き・削除・revert は行っていない。