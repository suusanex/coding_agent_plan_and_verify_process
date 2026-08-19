# v1 code-review child failure

- 分類: `misread-round-1-context`
- 結果: `unknown` / `insufficient`
- 影響: v1 の code-review 試行は failure として扱う。general-purpose v1 の結果を置換しない。
- raw: `failures\code-review-round-1.raw.md`
- 原因: Round 1 を誤読し、context/candidate の契約情報が不足していると誤って返した。
- 保存処理での外部モデル・ネットワーク: 不使用