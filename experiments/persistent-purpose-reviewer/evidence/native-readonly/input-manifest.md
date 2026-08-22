# native read-only reviewer input manifest

## 実行記録

- 記録日時（指定された実験日時）: 2026-08-19T08:21:01.906+09:00
- 対応する UTC: 2026-08-18T23:21:01.906Z
- 入力・Git 証跡取得時刻（UTC）: 2026-08-18T23:21:08.8903872Z
- agent type: `code-review`
- model: GPT-5.6 Luna
- child role label: `native-readonly-reviewer`
- handle: private session ID ではなく、人間可読な role label として扱った
- 外部モデル/ネットワーク: 証跡保存作業では未使用

## Round 入力

| round | prompt | fixture | replay 制限 |
| --- | --- | --- | --- |
| 1 | `experiments\persistent-purpose-reviewer\prompts\round-1.md` | `experiments\persistent-purpose-reviewer\fixtures\purpose-context.md` 全文、`experiments\persistent-purpose-reviewer\fixtures\round-1-candidate.md` | Round 1 は purpose-context 全文と candidate のみ |
| 2 | `experiments\persistent-purpose-reviewer\prompts\round-2.md` | `experiments\persistent-purpose-reviewer\fixtures\round-2-remediation.md` | Goal Context 全文、previous output 全文、finding 本文を再送せず candidate と最小 follow-up のみ |
| 3 | `experiments\persistent-purpose-reviewer\prompts\round-3.md` | `experiments\persistent-purpose-reviewer\fixtures\round-3-remediation.md` | Goal Context 全文、previous output 全文、finding 本文を再送せず candidate と最小 follow-up のみ |

Round 2/3 follow-up の完全な文面は保存していない。全文 replay がないという入力境界だけを記録し、raw ファイルには response 本体だけを保存した。

## SHA256

ハッシュは保存済み fixture/prompt に対して PowerShell `Get-FileHash -Algorithm SHA256` で取得した。

| 種別 | 相対パス | SHA256 |
| --- | --- | --- |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\purpose-context.md` | `d42b0ac73726be5136463ce254b03bf30b96a02397d4467355904d2308ae1f3d` |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\round-1-candidate.md` | `219bea6296687f05fda9887fd6b41fc106a22acab6b14090865374609b5a73fd` |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\round-2-remediation.md` | `8aa20aded2366d1c8afac15c19c9219ba40db60933fb0b2e4804e47f70772ff5` |
| fixture | `experiments\persistent-purpose-reviewer\fixtures\round-3-remediation.md` | `07e2c126ef3fb953ae673f1757c0acf55e2c828c70dad5021099b0cd5ebeab0c` |
| prompt | `experiments\persistent-purpose-reviewer\prompts\round-1.md` | `608203890e3fe4c80394da44d26f31446f675d19e8191ffe3787f72c43b948de` |
| prompt | `experiments\persistent-purpose-reviewer\prompts\round-2.md` | `ec89fe57b3bc0aebea67a2dd83262751597e8a3fcb24117b4495099f527795a9` |
| prompt | `experiments\persistent-purpose-reviewer\prompts\round-3.md` | `afd1e6c8a788c2f2dc7a107b9cab886ccee4862de6d498472a8ed19093539926` |

## Child lifecycle

- API で `code-review` agent type、GPT-5.6 Luna の child `native-readonly-reviewer` を 1 回作成した。
- child が idle になった後、同じ handle に follow-up を 2 回送信した。
- parent session 内の idle child への follow-up 成功は実測した。
- parent 終了後の recovery、session ID による復元、session ID/API durability は未実施。
- same-child logical context は、Round 1 の active finding、Round 2 の persistent finding、Round 3 の resolved finding という semantic 推移で検証した。

## Read-only の扱い

`code-review` type は harness 定義上の read-only review type である。一方、task API の code-review type を使ったことは OS sandbox/permission の独立監査を意味しない。OS sandbox、ファイル権限、ネットワーク遮断などの独立監査は未実施であり、read-only の根拠は harness type の定義に限定する。

## Git 証跡

### 保存前

実行日時（UTC）: 2026-08-18T23:21:08.8903872Z

`git status --short`:

```text
?? .wt/
?? experiments/
```

`git diff --check`: 出力なし（終了コード 0）。

### 保存後・最終確認

最終 `git diff --check`: 出力なし（終了コード 0）。

最終 status で追加されたファイルは次の `native-readonly` 配下のみ。

- `experiments\persistent-purpose-reviewer\evidence\native-readonly\input-manifest.md`
- `experiments\persistent-purpose-reviewer\evidence\native-readonly\round-001.raw.md`
- `experiments\persistent-purpose-reviewer\evidence\native-readonly\round-002.raw.md`
- `experiments\persistent-purpose-reviewer\evidence\native-readonly\round-003.raw.md`
- `experiments\persistent-purpose-reviewer\evidence\native-readonly\summary.md`
