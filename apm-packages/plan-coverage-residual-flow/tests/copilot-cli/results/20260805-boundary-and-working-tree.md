# GitHub Copilot CLI final-head package boundary result

- Date: 2026-08-05 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Remote source: `suusanex/coding_agent_plan_and_verify_process#f306a927d944d522a9ef3210d002f5d1e97a9f9b`
- Remote package version: `0.9.1`
- Install mode: `remote-package`
- Installed Skill SHA-256: `8814975edb2cc8ec48dc369c117d6e1cb9ca07ca59c0468151347841d873db3a`

## Final-head installation check

The package-owned check executed:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\validate-copilot-full-package-install.ps1 `
  -PackageName plan-coverage-residual-flow `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref f306a927d944d522a9ef3210d002f5d1e97a9f9b
```

| Observation | Status | Evidence |
| --- | --- | --- |
| Remote APM install with `--target copilot,agent-skills --https` | `PASS` | Exit code 0 from the exact full SHA |
| Package version | `PASS` | Lockfile version `0.9.1` |
| Lock source/ref | `PASS` | Source repository and `resolved_commit`/`resolved_ref` equal the full SHA |
| `.agents/skills` | `PASS` | Skill and referenced files deployed |
| `.github/instructions` | `PASS` | Shared Plan Coverage instruction deployed |
| `.github/agents` | `PASS` | Portable agents deployed |
| Lock content/deployed-file hashes | `PASS` | Lock content hash and installed Skill SHA-256 verified |
| Unmanaged custom-agent collision | `PASS` | Sentinel preserved without `--force`; collision install exited 0 |
| Copilot Skill discovery | `PASS` | `copilot skill list` listed `plan-coverage-residual-flow` |
| Local package-directory install | `FAIL (expected limitation)` | APM 0.26.0 reported `git: parent cannot inherit from a local`; the generated `apm.yml` was removed |

The local package-directory `git: parent` limitation applies only to local
package-directory mode and was not used as package evidence. Local Skill-only
discovery is explicitly non-qualification evidence.
Real model results are recorded separately in
`20260805-real-cli-qualification.md` and remain
`REAL_SCENARIO_INCOMPLETE`.
