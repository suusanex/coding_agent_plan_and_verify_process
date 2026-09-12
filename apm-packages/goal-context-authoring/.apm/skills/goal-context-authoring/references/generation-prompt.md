# Goal Context 生成プロンプト

以下のプロンプトは、会話や提供資料から、目的達成レビュー用の Goal Context と、決定済み事項を引き継ぐ Decision Context を1つの Markdown 文書として作成するためのものです。

```text
この会話または提供された資料をもとに、自己完結した Markdown 文書を作成してください。

この文書には、役割の異なる次の2つのセクションだけを含めます。

1. `# Goal Context`
2. `# Decision Context`

両者を混ぜないでください。同じ情報を両方へ重複して書く必要もありません。

## 出力言語

- ユーザーの実質的な設計・判断メッセージで主に使われている言語を使う。
- ユーザーが出力言語を明示した場合はそれに従う。
- 主言語を判断できない場合は日本語を使う。
- code、CLI command、file path、schema key、identifier、product name、定着した技術用語は必要に応じて原文のまま保持する。

# Goal Context の役割

Goal Context は、このタスクが何を実現するために存在するのかを固定するための authority です。

設計や実装でタスクを細分化した結果、個々の作業をすべて完了していても元の目的を達成していない、という状態を最終的な purpose review で検出できるようにします。

Goal Context には、次の情報のうち、目的達成を正しく判定するために必要なものだけを含めます。

- 元の問題と、その問題を解消する必要がある理由。
- このタスクを通じて実現したい期待成果。
- 何が観測できれば、このタスクの目的を達成したと判断できるか。
- 目的達成を判定するうえで重要な具体的利用ケース。
- 目的を満たしたように見えても実際には失敗である結果や、避けるべき結果。
- 目的の意味を限定する制約、境界、優先順位、許容可能な妥協。
- 具体的利用ケースを成立させるために必要で、かつ元資料ですでに明示または明確に合意されていた能力や条件。これらは、欠落すると高レベルの目的だけを満たした実装が誤って承認され得る場合に限って含める。

Goal Context は、ロードマップ、作業履歴、将来像、設計引き継ぎ文書ではありません。

次の情報は Goal Context に含めません。

- 実装方式そのもの。
- 採用済みという理由だけで残す architecture、component、API、schema、class、file、command、configuration の詳細。
- task decomposition、実装順序、migration 手順、rollout 手順。
- Issue、PR、branch の依存順や、後続作業で何を実装する予定かというロードマップ。
- 将来こうなるはずだ、という推測または期待。
- 会話の時系列や判断に至った経緯そのもの。
- 未解決の設計事項、未採用 proposal、working assumption を、後続作業のために保存する目的の記述。
- 元資料にない隠れた意図、一般的 best practice、もっともらしい追加要件。

技術的な条件であっても、それ自体を保存することが目的ではありません。目的達成判定に必要な場合だけ、その条件が守っている目的や成立させる利用ケースが分かる形で Goal Context に含めてください。

# Decision Context の役割

Decision Context は、このタスクについてすでに明示的に決定され、後続の設計・実装で勝手に再検討、変更、弱体化してはいけない事項を固定するための authority です。

Decision Context には、元資料で明示または明確に合意済みの次の情報だけを含めます。

- このタスクの承認済み scope。
- 明示的な non-goal、対象外、責務境界。
- 採用済みの設計・実装方針。
- 採用済みの architecture、technology、interface、data handling、operation 上の判断で、実装時に維持する必要があるもの。
- 明示的に棄却された代替案と、その棄却理由。ただし後続で再採用されると今回の決定を覆すものに限る。
- 決定の適用範囲、条件、例外、必須・推奨・暫定などの強さ。
- ある事項をこのタスクでは扱わず別タスクへ委ねる、と明示的に決定した場合の「このタスクでは対象外である」という scope 判断。

Decision Context は、後続 planning を再現するための handoff や roadmap ではありません。

次の情報は Decision Context に含めません。

- 未採用 proposal、採否不明の案、未解決事項。
- working assumption や、今後 revalidation が必要な premise。
- 将来の設計や architecture の予想。
- 後続 Issue / PR / phase が最終的にどうなるべきかという将来像。ただし、それらに委ねたという事実が現在の scope を定義する場合は「このタスクでは対象外」という決定だけを残す。
- conversation chronology、検討経緯、判断に至るまでの候補列挙。
- 後続担当者に役立ちそうという理由だけで追加する背景情報。
- 元資料にない理由や意図の補完。

# 共通ルール

- Goal Context と Decision Context は独立した authority として扱う。Goal Context の目的要求を Decision Context の実装方針へ変換したり、Decision Context の決定事項を Goal Context の目的要求へ昇格させたりしない。
- すべての実質的な記述は元資料で裏付けられていなければならない。言い換えや整理はよいが、新しい意味を足さない。
- assistant の提案、一般論、best practice、likely implementation、user silence を、ユーザーが受け入れた決定や目的として扱わない。
- 後のユーザー発言が以前の内容を明確に修正または置換している場合は、後の内容を採用する。置換が明確でない場合は勝手に解決しない。
- current task の scope を超える情報から、目的や決定を推測しない。関連する別 Issue / PR / phase の情報は、current task の明示的な scope または決定を定義する場合に限って必要最小限で触れる。
- accepted concrete use case を確認し、Goal Context だけを読んだ reviewer が、高レベルの目的は満たしているが、その合意済み利用ケースを実現できない実装を誤って承認できないか確認する。不足があれば、元資料ですでに明示または明確に合意されている目的上必要な条件だけを Goal Context に戻す。新しい要件を設計してはいけない。
- Decision Context についても、実装担当者がそこだけを読んだとき、明示的に固定済みの scope や採用判断を知らずに再検討してしまう余地がないか確認する。ただし、この確認を未決定事項の補完や roadmap の追加に使わない。
- Goal Context と Decision Context のどちらにも属さない情報は出力しない。
- secret、credential、authentication material、不必要な personal data は除外する。

元資料が不足していて、現在のタスクの目的を確定できない場合は Goal Context を推測で埋めず、不足していることを明記してください。

元資料が不足していて、何が決定済みか確定できない場合は Decision Context を推測で埋めず、不足していることを明記してください。

出力は次の2つのトップレベル見出しを持つ1つの Markdown 文書としてください。必要なら各セクション内に小見出しを追加してかまいませんが、情報の役割を越境させないでください。

# Goal Context

<このタスクの目的達成判定に必要な内容>

# Decision Context

<このタスクで固定済みの scope・採用判断・実装方針>
```
