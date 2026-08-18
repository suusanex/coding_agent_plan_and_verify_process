# native 実験 input manifest

## 実行記録

- 記録日時（指定された実験日時）: 2026-08-19T08:19:42.821+09:00
- 対応する UTC: 2026-08-18T23:19:42.821Z
- 証跡保存時刻（UTC）: 2026-08-18T23:20:09.2673090Z
- model: GPT-5.6 Luna
- child role label: `native-purpose-reviewer`
- handle: private session ID ではなく、人間可読な role label として扱った
- 外部モデル/ネットワーク: 証跡保存作業では未使用

## Round 入力

| round | prompt | fixture | context replay | prior output replay |
| --- | --- | --- | --- | --- |
| 1 | `experiments\persistent-purpose-reviewer\prompts\round-1.md` | `experiments\persistent-purpose-reviewer\fixtures\purpose-context.md`、`experiments\persistent-purpose-reviewer\fixtures\round-1-candidate.md` | full purpose context file を全文読取 | なし |
| 2 | `experiments\persistent-purpose-reviewer\prompts\round-2.md` | `experiments\persistent-purpose-reviewer\fixtures\round-2-remediation.md` | Goal Context 全文を再送しない | previous output 全文を再送しない |
| 3 | `experiments\persistent-purpose-reviewer\prompts\round-3.md` | `experiments\persistent-purpose-reviewer\fixtures\round-3-remediation.md` | Goal Context 全文を再送しない | previous output 全文を再送しない |

Round 1 は full purpose context file と candidate だけを読み、Round 2/3 は candidate と最小 follow-up のみを渡した。Round 2/3 follow-up の完全な文面は保存していないが、Goal Context/previous output 全文の replay がないことを上表で追跡できる。

## SHA256

ハッシュは実験 fixture/prompt の保存済みファイルを対象に、PowerShell `Get-FileHash -Algorithm SHA256` で取得した。

| 種別 | 相対パス | SHA256 |
| --- | --- | --- |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\purpose-context.md` | `d42b0ac73726be5136463ce254b03bf30b96a02397d4467355904d2308ae1f3d` |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\round-1-candidate.md` | `219bea6296687f05fda9887fd6b41fc106a22acab6b14090865374609b5a73fd` |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\round-2-remediation.md` | `8aa20aded2366d1c8afac15c19c9219ba40db60933fb0b2e4804e47f70772ff5` |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\round-3-remediation.md` | `07e2c126ef3fb953ae673f1757c0acf55e2c828c70dad5021099b0cd5ebeab0c` |
| prompt | `experiments\persistent-purpose-reviewer\prompts\round-1.md` | `608203890e3fe4c80394da44d26f31446f675d19e8191ffe3787f72c43b948de` |
| prompt | `experiments\persistent-purpose-reviewer\prompts\round-2.md` | `ec89fe57b3bc0aebea67a2dd83262751597e8a3fcb24117b4495099f527795a9` |
| prompt | `experiments\persistent-purpose-reviewer\prompts\round-3.md` | `afd1e6c8a788c2f2dc7a107b9cab886ccee4862de6d498472a8ed19093539926` |

## Lifecycle と read-only

- `functions.task` で GPT-5.6 Luna の general-purpose child `native-purpose-reviewer` を一度作成した。
- child が idle になった後、`functions.write_agent` で同一 handle に Round 2、Round 3 を送った。
- `read_agent` が同じ child conversation の Turn 0/1/2 を返したことを native same-child continuity の根拠とした。
- task API の read-only permission パラメータは存在しない。read-only は prompt instruction による要求であり、API enforcement ではない。child には通常のファイル書込み等のツールが原理的にあるため、shell/network/write 禁止は技術的保証ではない。
- 親 session 内での idle follow-up 成功は実施したが、parent process 終了後の復旧、永久 session ID の復旧、session ID/API durability は未実施。

## Git 証跡

### 実験開始時

実行日時（UTC）: 2026-08-18T23:20:09.2673090Z

`git status --short`:

```text
?? .wt/
?? experiments/
```

`git diff --check`: 出力なし（終了コード 0）。

### 証跡保存後・最終確認

実行日時（UTC）: 証跡保存後に再実行。

`git status --short` は既存の `?? .wt/` と `?? experiments/` の範囲であり、今回の変更は `experiments\persistent-purpose-reviewer\evidence\native\` のみ。production、skills、scripts、config の変更はない。

`git diff --check`: 最終実行で出力なし（終了コード 0）。

raw transcript は response 本体だけを保存し、ユーザパスおよび private handle は含めていない。
