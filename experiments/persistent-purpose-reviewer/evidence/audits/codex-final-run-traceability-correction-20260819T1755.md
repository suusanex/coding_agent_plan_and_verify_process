# Codex final run traceability correction note

訂正日時: 2026-08-19 17:55:17 +09:00

この note は、`codex-final-run-traceability.md` / `.json` の先行版を訂正する append-only 証跡である。既存の raw、sanitized、machine metadata、run metadata、`report.md` は編集していない。

## 先行監査の誤り

先行監査の raw hash 取得部分は、作業 directory `D:\Data\git\coding_agent_plan_and_verify_process` から次のように `run-metadata.rounds[].raw_path` の文字列を `$r.raw_path` に渡していた。

```powershell
$root = Resolve-Path experiments\persistent-purpose-reviewer
$run = Get-Content $root\evidence\codex\20260818T232647Z-run-metadata.json -Raw | ConvertFrom-Json
foreach ($r in $run.rounds) {
    $raw = Get-Item $r.raw_path
    Get-FileHash -Algorithm SHA256 $raw.FullName
}
```

この hash 取得自体は exact path を使用しており、filename の自作・置換はしていなかった。誤りは、並列 read の出力順を round 呼び出し順と誤って対応付け、semantic form を R2/R3/R1 と記録したことである。exact path を metadata から再読し直すと、保存本文は R1/R2/R3 と一致する。

## exact path の訂正結果

| metadata round | metadata の exact raw path | semantic form | stored-byte SHA-256 |
| ---: | --- | --- | --- |
| 1 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\raw\20260818T232647Z-round-01-purpose-reviewer-codex-session-979423350a76.raw.md` | R1 initial finding (`purpose_restatement`) | `812c4349121d1a524fbedf0dc97179c217d064cbf665a0a761512f45c46fc6c1` |
| 2 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\raw\20260818T232647Z-round-02-purpose-reviewer-codex-session-979423350a76.raw.md` | R2 prior FAIL | `fa510b068c9e7747f7ba7cec9f8ea15536d8515458f14a2c5554d16dc6b9cce1` |
| 3 | `D:\Data\git\coding_agent_plan_and_verify_process\experiments\persistent-purpose-reviewer\evidence\codex\raw\20260818T232647Z-round-03-purpose-reviewer-codex-session-979423350a76.raw.md` | R3 prior PASS | `e8637e27ab87fe9e0ef56ba92299a5ab1a644156a49c0443958dfef981bca72b` |

同じ round の sanitized file も raw file と同一 bytes/hash である。

## response hash の provenance

`scripts\codex\run-real-experiment.ps1` は `Get-TextHash($safeResponse)` で保存前の UTF-8 text bytes（末尾改行なし）を hash し、その後 `Save-Utf8` の `Set-Content -Encoding utf8` でファイルを保存する。保存ファイルには CRLF の末尾改行が追加されるため、stored-byte hash は metadata の response hash と一致しない。

| round | run/machine metadata response_sha256 | stored-byte hash | 保存末尾改行を除いた text hash |
| ---: | --- | --- | --- |
| 1 | `92b71d1a0697fb610c8020bb8632f01843a14693c83dfcae31a82e4480352ed1` | `812c4349121d1a524fbedf0dc97179c217d064cbf665a0a761512f45c46fc6c1` | `92b71d1a0697fb610c8020bb8632f01843a14693c83dfcae31a82e4480352ed1` |
| 2 | `dd80c064793296f9774c1d7d8adbab1afae8db90bc4ef86e5f1c8a74327ad6bf` | `fa510b068c9e7747f7ba7cec9f8ea15536d8515458f14a2c5554d16dc6b9cce1` | `dd80c064793296f9774c1d7d8adbab1afae8db90bc4ef86e5f1c8a74327ad6bf` |
| 3 | `e9851f1b220d110d26f486aecd845a072df447fd6d484ba4cbecaefdbf217ec9` | `e8637e27ab87fe9e0ef56ba92299a5ab1a644156a49c0443958dfef981bca72b` | `e9851f1b220d110d26f486aecd845a072df447fd6d484ba4cbecaefdbf217ec9` |

## Corrected conclusion

1. **Semantic form / round path**: final adopted run is consistent: R1 initial finding, R2 prior FAIL, R3 prior PASS. The earlier R1/R2/R3 cycle claim was an audit attribution error.
2. **Stored-byte hash / metadata hash**: all three stored raw/sanitized files differ from the recorded response hash solely by the save-byte representation; metadata hash matches the text bytes after removing the appended CRLF. This is a hash provenance/recording issue, not a raw round-label/content mismatch.
3. Final run is semantically traceable, but byte-level evidence is not self-describing until the writer records the stored-byte hash or preserves the exact pre-save bytes.
