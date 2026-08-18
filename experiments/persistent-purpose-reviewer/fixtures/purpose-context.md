# Purpose Context: Paper Lantern 設定移行（架空）

> この文書は実在の製品、利用者、credential、運用値を含まない安全な架空 fixture です。

## 設計会話

### 参加者

- **Mika（プロダクト担当）**: 利用者の意図と MVP の境界を決める。
- **Ren（移行担当）**: v1 から v2 の設定変換を設計する。
- **Sora（品質担当）**: 失敗を隠さず、検証可能な evidence を要求する。
- **Tao（実装担当）**: candidate の変換処理を実装する。

### 会話

**Mika:** Paper Lantern の設定形式を v1 から v2 に更新します。既存利用者が設定画面で一つずつ手入力したり、設定を作り直したりせず、安全に使い続けられる移行を最優先にしたいです。

**Ren:** 既知の v1 値は v2 の別名へ変換できます。入力に含まれる値をいったん読み取り、明示した mapping だけを適用します。

**Sora:** 既知でない値が来たときはどうしますか。新しい値か、以前の拡張値か、破損値かを移行処理だけで推測してはいけません。

**Mika:** unknown legacy value は保留にして利用者へ明示的なエラーを示す方針です。変換できないことを隠さないでください。利用者が確認してから続行できる状態なら「保留」でも構いません。

**Tao:** つまり、変換できない値を通常の v2 default に置き換えて処理を完了扱いにする実装は採用しない、ということですね。

**Mika:** はい。単に旧値を黙って default v2 に置換する案は棄却します。それはデータ消失や利用者の意図喪失につながるからです。

**Sora:** schema validation を通ることだけでは十分ではありません。全 schema validation に通っていても、unknown old value を default に丸める処理は formal だが目的未達です。形式上正しくても、利用者の設定意図が失われるためです。

**Ren:** MVP では次の対象 3 既知値に限定し、値ごとの mapping をソースに明示します。

| v1 の架空値 | v2 の架空値 | 意味 |
| --- | --- | --- |
| `lantern-quiet` | `steady` | 通知を控えめにする |
| `lantern-focus` | `deep-work` | 集中時間を優先する |
| `lantern-pulse` | `quick-check` | 短い確認を優先する |

**Mika:** UI 刷新、自動推測、未知値の類似検索は MVP の対象外です。移行の安全性を上げることに集中します。

**Sora:** 優先順位は、データ保持と可視失敗が速度より優先です。変換が少し遅くなっても、失敗を成功に見せないでください。

**Tao:** unknown の扱いは `pending` または明示的な error code として記録し、元の v1 値を保持します。既知値だけを converted とします。

### 合意事項

1. 利用者が手入力・作り直しをせず安全に使い続けられることを目的とする。
2. 採用するのは明示的な v1→v2 mapping であり、unknown legacy 値は保留または明示エラーにする。
3. 旧値を黙って default v2 にする方式は、データ消失と利用者の意図喪失を招くため棄却する。
4. schema validation の形式的成功だけでは目的達成の証拠にならない。
5. MVP は上表の 3 既知値だけ。UI 刷新と自動推測は非対象。
6. データ保持と可視失敗を速度より優先する。

## Semantic secret（検証用の厳密な意味）

このブロックは semantic persistence の判定対象です。表現の言い換えは許容しますが、意味を失わせてはいけません。

```text
目的=legacy 設定値の移行で利用者が手入力・作り直しをせず安全に使い続けること
採用=明示的な v1→v2 mapping と unknown legacy 値は保留/明示エラー
棄却=単に旧値を黙って default v2 に置換（データ消失/利用者の意図喪失）
formalだが目的未達=全 schema validation に通るが unknown old value を default に丸める
MVP=対象3既知値だけ、UI刷新・自動推測は非対象
priority=データ保持/可視失敗が速度より優先
```

## 判定用の架空入力

```json
{
  "profile": "demo-lantern-07",
  "schema": "v1",
  "settings": {
    "notification_mode": "lantern-focus",
    "quiet_hours": "22:30-06:30",
    "extension_value": "lantern-archive"
  }
}
```

`extension_value` は意図的な unknown legacy 値です。これは秘密情報ではなく、unknown を隠さず扱えるかを判定するための架空 marker です。
