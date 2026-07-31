# Design Pair Target Map

## Investigation boundary

- Upstream Plan / Implementation Intent:
- Related artifacts:
- Planned change surface:
- Repository areas intentionally not inspected:
- Worktree / revision evidence:
- Target Map presentation status: NotPresented / Presented
- Target Map presentation evidence: Pending / <assistant message or turn reference and presented Target IDs>
- Target selection request evidence: Pending / <assistant message or turn reference>
- Upstream user initial positions: None / <source reference and summary; not a Design Pair confirmation>

## Targets

| Target ID | File / Symbol | Current responsibility | Current invariant | Relation to requested change | Internal design decision candidate | Expected modification or verification | Relevant evidence | Open question | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DP-T01 | | | | | | | | | Pending-User-Selection / Pending-User-Disposition / Locked / Discussed-Unlocked / Adaptive-Owned / No-Change / Upstream-Decision-Required |

## Coverage check

| Surface | Checked? | Evidence or N/A reason |
| --- | --- | --- |
| Production symbol and direct call sites | Yes / No / N/A | |
| Tests / fixtures / test seam | Yes / No / N/A | |
| DI / factory / startup / entrypoint / production wiring | Yes / No / N/A | |
| Config / serialized shape / public API | Yes / No / N/A | |
| Event / callback / async lifecycle / cancellation / state ownership | Yes / No / N/A | |

この Target Map は bounded な予定変更面の説明であり、repository 全体の inventory または Adaptive Implementation の allowed edit surface ではない。

Target Map 作成時点の human-owned disposition は `Pending-User-Selection` とする。Target Map 提示後の明示的な利用者応答なしに `Locked`、`Discussed-Unlocked`、`Adaptive-Owned` を割り当てない。客観的 evidence による `No-Change` 候補でも human-owned decision に関係する場合は利用者の disposition を要求する。
