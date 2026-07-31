# Install Guide

## Dry-run first

canonical Adaptive implementation agentはAdaptive packageからAPM 0.26.0の`copilot`targetで導入できます。fallback全体を導入する場合も、manifestのcanonical target名は`copilot`です。

対象 repository へ入れる前に dry-run を実行してください。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path> --dry-run
```

dry-run は追加予定ファイル、既存 `.github` customization、衝突、manual merge が必要な項目を表示します。

## Apply

衝突がない場合は `--dry-run` を外して適用します。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path>
```

既存同名ファイルと内容が異なる場合、既定では停止します。managed file を上書きする必要がある場合だけ `--force` を使います。

```powershell
dotnet run --file .\apm-packages\copilot-fallback-ai-development-process\scripts\install-copilot-fallback-local.cs -- <target-repo-path> --force
```

`.github/copilot-instructions.md` は marker 管理された block だけを差し替えます。既存 instructions 全体を自動で破壊的に置き換えません。

## Verify in VS Code

- custom agents に `copilot-cost-router` が見える
- custom agents に canonical 名の `high-implementation-starter` と `standard-implementation-completer` が見える
- prompt files に `/cost-route`、`/resume-state`、`/verify-and-close` が見える
- 「この issue を進めて」で実装に直行しない
- `plans/<slug>/codex-first-state.md` が作られる
- 非自明な READY scope が `high-implementation-starter` から開始される
- `standard-implementation-completer` は complete な `READY_FOR_STANDARD_COMPLETION` handoff 後だけ起動する
- `NEEDS_HIGH_MODEL_REENTRY` の次の write owner が `high-implementation-starter` になる
- HIGH_MODEL と STANDARD_MODEL の write owner が同時に active にならない
- close blocker が残る場合に完了扱いしない

確認結果は state artifact の `current_status`、`selected_agent_name`、`recommended_model_tier`、`edit_owner`、Adaptive Implementation fields と Agent Usage Ledger に記録してください。実モデルを使わない installer 確認では、品質・token cost・re-entry 回数は `NOT RUN` とします。

同名Adaptive agentsはrepository rootのcanonical filesをsourceとし、fallback local installerもそこから直接コピーします。package内に同名mirrorはありません。別checkoutをsourceにする場合は`--repository-root <dir>`でcanonical filesを含むrepository rootを指定します。既存同名fileが異なる場合、local installerは`--force`なしで停止します。Adaptive APM installでも初回の未管理同名fileは保持されるため、内容とownerを確認せず上書きしません。

## Adaptive agent ownership and migration

- Adaptive packageをAPMで導入した`.github/agents/high-implementation-starter.agent.md`と`standard-implementation-completer.agent.md`はAPM lockfileのownershipに従い、`apm update` / `apm uninstall`で管理する。
- fallback local installerで配置した同名fileも実行時に指定したrepository rootのcanonical contentであり、同内容の再installはno-op、異なる内容は`--force`なしで停止する。
- 両packageを併用して同名fileが同内容なら衝突しない。異なる場合はAdaptive canonicalを採用するかrepository customizationを保持するかを人が決め、無条件上書きしない。
- fallback local installerは利用者変更を誤削除しないため自動removeを提供しない。Adaptive APM ownershipへ移行する場合は、canonical contentとの差分がないことを確認してからlocal installerで配置したfilesを人手で外し、Adaptive packageをAPM installする。

人手での作業が必要: 既存fallback導入先で同名Adaptive agentにcustomizationがある場合は差分を確認し、Adaptive canonicalへ移行するかcustomizationを維持するかを決めてください。

