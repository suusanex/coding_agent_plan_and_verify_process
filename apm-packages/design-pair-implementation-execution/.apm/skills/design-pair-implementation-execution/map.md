# Design Pair Target Map

## Investigation boundary

- Upstream Plan / Implementation Intent:
- Related artifacts:
- Planned change surface:
- Repository areas intentionally not inspected:
- Worktree / revision evidence:
- Target Map presentation status: NotPresented / Presented
- Target Map presentation evidence: Pending / <assistant turn, presented Target IDs, material sections and versions>
- Target selection request evidence: Pending / <assistant turn inviting direct questions, decisions and skips>
- Upstream user initial positions: None / <source reference and summary; not a Design Pair confirmation>

## Targets

| Target ID | Decision question / why now | Main trade-off / unknown | Decision materials | Disposition |
| --- | --- | --- | --- | --- |
| DP-T01 | <判断する問いと必要性> | <判断を左右する違い・不明点> | [DP-T01](#dp-t01) | Pending-User-Selection / Pending-User-Disposition / Locked / Discussed-Unlocked / Adaptive-Owned / No-Change / Upstream-Decision-Required |

1ファイル＝1IDとせず、独立して議論・判断・委任できる問いを単位にする。機械的な追随変更・検証対象は関連論点へ含める。このschemaをtracked handoff内へ展開し、説明の別ファイルを必須にしない。

## DP-T01

- Material version: DP-T01@1
- Evidence revision: <worktree / upstream revision and relevant dirty-file evidence>
- Presented at: Pending / <assistant turn and material version>

### 判断する問いと必要性

<何を決めるか、要求との関係、なぜ今判断が必要かを説明する。>

### 事実・制約と選択肢

<具体的な File / Symbol、Current responsibility / invariant、caller / wiring / lifecycle / state / test seam と根拠を示し、それが案の実現性や選択にどう影響するかを説明する。lineが不安定ならexact symbol / sectionを使う。未調査の仮説は事実と分離する。>

| Option | Facts / constraints supporting it | Trade-off and impact on the decision |
| --- | --- | --- |
| <実在する案> | <根拠への参照> | <満たす制約、代償、既存codeへの影響と因果関係> |

<比較可能な案がなければ理由。不明点を埋めるために初回から詳細設計を強制しない。>

### 暫定提案・未確認事項・検証

- Non-binding AI proposal: <根拠と採用条件 / No proposalと根拠付き理由>
- Open questions: <未確認事項、必要な追加調査の条件>
- Expected modification or verification: <関連する追随変更・検証対象>
- Validation expectations: <各判断で守るinvariant、確認方法>

### 対話差分

| User turn / exact question or decision | Answer / evidence delta | Assistant turn / material version |
| --- | --- | --- |

既知の根拠は上の節を参照し、質問に必要な回答だけを記録する。新案・情報不足・code / upstream変更時だけ追加調査し、影響する資料版・提示証拠と判断を更新する。旧版への確定を新版へ黙って適用しない。

## Coverage check

| Surface | Checked? | Evidence or N/A reason |
| --- | --- | --- |
| Production symbol and direct call sites | Yes / No / N/A | |
| Tests / fixtures / test seam | Yes / No / N/A | |
| DI / factory / startup / entrypoint / production wiring | Yes / No / N/A | |
| Config / serialized shape / public API | Yes / No / N/A | |
| Event / callback / async lifecycle / cancellation / state ownership | Yes / No / N/A | |

この Target Map は bounded な予定変更面の説明であり、repository 全体の inventory または Adaptive Implementation の allowed edit surface ではない。

会話では資料への導線と各問いの判断入口を要約し、直接質問・反論・確定・スキップを案内して停止する。具体的根拠を含む資料の全面再掲は不要だが、リンクまたはIDと論点名だけでは提示にならない。

Target Map 作成時点の human-owned disposition は `Pending-User-Selection` とする。Target Map 提示後の明示的な利用者応答なしに `Locked`、`Discussed-Unlocked`、`Adaptive-Owned` を割り当てない。客観的 evidence による `No-Change` 候補でも human-owned decision に関係する場合は利用者の disposition を要求する。

READY 判定時は Target ID を一意な集合として扱い、handoff summary の全IDがこの表に実在すること、summaryの5分類が重複なく全rowを覆うこと、各分類がDispositionと一致することを照合する。架空ID、重複ID、未分類row、summary / row不一致はartifact repairが必要である。
