# GitHub Copilot CLI final-head package boundary result

- Date: 2026-08-05 (Asia/Tokyo)
- Copilot CLI: `1.0.78`
- APM: `0.26.0`
- Remote source: `suusanex/coding_agent_plan_and_verify_process#f306a927d944d522a9ef3210d002f5d1e97a9f9b`
- Remote package version: `0.6.1`
- Install mode: `remote-package`
- Installed Skill SHA-256: `717c91f6b65e3eab4003ba4938f99ec4abb01982f212ecbd2dc254208e9c9c91`

## Final-head installation check

The package-owned check executed:

```powershell
.\apm-packages\plan-coverage-residual-flow\scripts\validate-copilot-full-package-install.ps1 `
  -PackageName token-aware-full-coverage-3layer `
  -Repository suusanex/coding_agent_plan_and_verify_process `
  -Ref f306a927d944d522a9ef3210d002f5d1e97a9f9b
```

| Observation | Status | Evidence |
| --- | --- | --- |
| Remote APM install with `--target copilot,agent-skills --https` | `PASS` | Exit code 0 from the exact full SHA |
| Package version | `PASS` | Lockfile version `0.6.1` |
| Lock source/ref | `PASS` | Source repository and `resolved_commit`/`resolved_ref` equal the full SHA |
| `.agents/skills` | `PASS` | Full Coverage Skill and references deployed |
| `.github/instructions` | `PASS` | Shared and Full Coverage instructions deployed |
| `.github/agents` | `PASS` | `slice-prep` and `slice-impl` plus canonical dependencies deployed |
| Lock content/deployed-file hashes | `PASS` | Lock content hash and installed Skill SHA-256 verified |
| Unmanaged custom-agent collision | `PASS` | Sentinel preserved without `--force`; collision install exited 0 |
| Copilot Skill discovery | `PASS` | `copilot skill list` listed `token-aware-full-coverage-3layer` |
| Local package-directory install | `FAIL (expected limitation)` | APM 0.26.0 reported `git: parent cannot inherit from a local`; the generated `apm.yml` was removed |

The local package-directory `git: parent` limitation applies only to local
package-directory mode and was not used as package evidence. Local Skill-only
discovery is explicitly non-qualification evidence.
Real model results are recorded separately in
`20260805-real-cli-qualification.md` and remain
`REAL_SCENARIO_INCOMPLETE`.
