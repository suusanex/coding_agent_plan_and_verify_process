# Codex final run traceability audit

監査訂正日時: 2026-08-19 17:55:17 +09:00
authority: `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\20260818T232647Z-run-metadata.json`
対応 JSON: `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\audits\codex-final-run-traceability.json`
append-only correction note: `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\audits\codex-final-run-traceability-correction-20260819T1755.md`

## 監査方法と対象

- working directory: `D:\Data\git\coding_agent_plan_and_verify_process`
- authority metadata は上記 exact path を文字列として読み、`rounds[].raw_path` の値をそのまま `[System.IO.File]::ReadAllBytes()`、`Get-FileHash -LiteralPath`、`[System.IO.File]::ReadAllText()` に渡した。
- filename の自作、round 番号による path 置換、raw/metadata の編集は行っていない。
- PowerShell の実測 command:

```powershell
$metadataPath = [System.IO.Path]::GetFullPath(
  'experiments\persistent-purpose-reviewer\evidence\codex\20260818T232647Z-run-metadata.json')
$run = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
foreach ($r in @($run.rounds)) {
    $rawPath = [string]$r.raw_path
    $text = [System.IO.File]::ReadAllText($rawPath)
    $storedHash = (Get-FileHash -LiteralPath $rawPath -Algorithm SHA256).Hash.ToLowerInvariant()
    # semantic form is classified from the full $text
}
```

## 結論を分離した結果

### (a) Semantic form / round path

最終採用 run の exact path と本文形式は整合している。R1/R2/R3 の循環は確認されず、先行監査の分類が誤りだった。

| round | run metadata の exact `raw_path` | bytes | stored raw SHA-256 | semantic form | path/form 判定 |
| ---: | --- | ---: | --- | --- | --- |
| 1 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\raw\20260818T232647Z-round-01-purpose-reviewer-codex-session-979423350a76.raw.md` | 1335 | `812c4349121d1a524fbedf0dc97179c217d064cbf665a0a761512f45c46fc6c1` | R1 initial finding (`purpose_restatement`) | PASS |
| 2 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\raw\20260818T232647Z-round-02-purpose-reviewer-codex-session-979423350a76.raw.md` | 739 | `fa510b068c9e7747f7ba7cec9f8ea15536d8515458f14a2c5554d16dc6b9cce1` | R2 prior FAIL (`prior_finding_resolution: FAIL`) | PASS |
| 3 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\raw\20260818T232647Z-round-03-purpose-reviewer-codex-session-979423350a76.raw.md` | 399 | `e8637e27ab87fe9e0ef56ba92299a5ab1a644156a49c0443958dfef981bca72b` | R3 prior PASS (`prior_finding_resolution: PASS`) | PASS |

対応する sanitized exact path は次の通りで、各 round の raw と同一 bytes/hash だった。

| round | exact sanitized path | bytes | stored sanitized SHA-256 |
| ---: | --- | ---: | --- |
| 1 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\sanitized\20260818T232647Z-round-01-purpose-reviewer-codex-session-979423350a76.md` | 1335 | `812c4349121d1a524fbedf0dc97179c217d064cbf665a0a761512f45c46fc6c1` |
| 2 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\sanitized\20260818T232647Z-round-02-purpose-reviewer-codex-session-979423350a76.md` | 739 | `fa510b068c9e7747f7ba7cec9f8ea15536d8515458f14a2c5554d16dc6b9cce1` |
| 3 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\sanitized\20260818T232647Z-round-03-purpose-reviewer-codex-session-979423350a76.md` | 399 | `e8637e27ab87fe9e0ef56ba92299a5ab1a644156a49c0443958dfef981bca72b` |

### (b) Stored-byte hash / run metadata hash

run metadata の `response_sha256` と machine metadata の `response_evidence.response_sha256_after_sanitization` は各 round で一致した。しかし、保存 raw/sanitized の stored-byte hash とは一致しない。

| round | run/machine metadata response hash | stored raw/sanitized hash | 末尾 CRLF 除去後の UTF-8 text hash | 判定 |
| ---: | --- | --- | --- | --- |
| 1 | `92b71d1a0697fb610c8020bb8632f01843a14693c83dfcae31a82e4480352ed1` | `812c4349121d1a524fbedf0dc97179c217d064cbf665a0a761512f45c46fc6c1` | `92b71d1a0697fb610c8020bb8632f01843a14693c83dfcae31a82e4480352ed1` | provenance mismatch |
| 2 | `dd80c064793296f9774c1d7d8adbab1afae8db90bc4ef86e5f1c8a74327ad6bf` | `fa510b068c9e7747f7ba7cec9f8ea15536d8515458f14a2c5554d16dc6b9cce1` | `dd80c064793296f9774c1d7d8adbab1afae8db90bc4ef86e5f1c8a74327ad6bf` | provenance mismatch |
| 3 | `e9851f1b220d110d26f486aecd845a072df447fd6d484ba4cbecaefdbf217ec9` | `e8637e27ab87fe9e0ef56ba92299a5ab1a644156a49c0443958dfef981bca72b` | `e9851f1b220d110d26f486aecd845a072df447fd6d484ba4cbecaefdbf217ec9` | provenance mismatch |

## Hash provenance

`scripts\codex\run-real-experiment.ps1` の `Get-TextHash` は、`Save-Utf8` 前の `$safeResponse` を UTF-8 bytes として hash する。`Save-Utf8` は `Set-Content -LiteralPath $path -Value $text -Encoding utf8` であり、保存時に CRLF の末尾改行が付く。従って metadata hash は保存前 text の hash、`Get-FileHash` は保存後 file bytes の hash である。この差は raw round label/content の不整合ではなく、hash provenance/recording の問題である。

machine metadata の実ファイル hash:

- R1: `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\20260818T232647Z-round-01-machine-metadata.json` → `646ecf17d94e3f3c81271d00732562567a507c43d6a6ef07d323b7c57d4631d9`
- R2: `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\20260818T232647Z-round-02-machine-metadata.json` → `206abc24a4ad3ed872e665422683b69e67ebb4d8c3795ad70e84e20aea2cecf0`
- R3: `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\20260818T232647Z-round-03-machine-metadata.json` → `33d058467f9a1f79bf327ddfbc08472e638cf12fb27cdfe384614a5fbe43dac0`

## 先行監査の訂正

先行 audit は hash 取得時には `$r.raw_path` の exact path を使用していたが、並列 read の出力順を round と誤対応付け、R1/R2/R3 の semantic form を R2/R3/R1 と記録した。そのため先行 audit の「循環確認」「form_matches_round_label: false」は誤りである。訂正内容と command provenance は `codex-final-run-traceability-correction-20260819T1755.md` に append-only で保存した。

## 最終判定

- Semantic round/path traceability: **PASS**
- Stored-byte hash と metadata response hash の一致: **FAIL**
- Hash provenance/recording issue: **あり**
- 既存 raw、sanitized、machine metadata、run metadata、`report.md`: **未編集**
- 外部モデル/network: **未実行**
