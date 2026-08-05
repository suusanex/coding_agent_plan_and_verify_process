# Issue #85 Active-reference inventory

この記録は、Issue #85 の削除判断と current source-of-truth の参照整理を示す。旧集約 package の導入・routing・validation を current surface に残さず、監査目的の historical record だけを保持する。

## 削除した package

- Codex-first aggregate process package
- Copilot fallback aggregate process package

skills、agents、profiles、templates、installers、launchers、instructions、docs、manifestsを含む package 全体を削除した。

## Active surface の判断

| Surface | 判断 | 対応 |
| --- | --- | --- |
| Root README navigation | Current | 旧2 packageの行を削除し、canonical packageへの目的別リンクだけを保持 |
| Installation and Maintenance | Current install guidance | 従来のmanaged-section導入手順を削除し、Adaptive専用installerとAPM provisioning helperを案内 |
| README navigation validator | Current validator | 削除済みREADMEとinstaller assertionを削除 |
| Adaptive / Design Pair validators | Current validators | 旧package payload、state、launcher、installer assertionsを削除し、canonical package経路だけを検証 |
| Architecture / Adaptive / Design Pair workflows | Current CI | 削除済みpackageのpath filterを削除 |
| Full Autonomous / Adaptive / Design Pair docs | Current package docs | 旧packageへの導線をcanonical packageの導線へ変更 |
| `apm.yml` / `apm.lock.yaml` | Current manifests | 旧packageのentryは存在しないことを確認 |

## Historical references

次の文書は過去の要求・実装・監査記録であり、current installation guidanceではない。内容は削除せず、historical-onlyの注記を付けて保持する。

- `docs/codex-first-cost-aware-process-goals.md`
- `docs/github-copilot-fallback-process-goals.md`
- `docs/codex-delegation-mustification-goals.md`
- `docs/codex-first-routing-branching.md`
- `docs/goal-context-multi-project-ai-development-notification-and-purpose-review.md`
- `plans/**`

## Validation rule

Current source、workflow、validator、package README、installation documentationで旧aggregate package pathを参照しない。historical record内の参照は、過去状態の再現性のために保持する。
