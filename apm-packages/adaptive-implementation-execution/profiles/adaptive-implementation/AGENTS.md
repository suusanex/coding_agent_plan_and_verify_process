# Adaptive Implementation profile

通常 Plan Mode output、repository-tracked Plan、手書き Plan、または Issue 内の実装計画を入力として `adaptive-implementation-execution` skill を使用する。

## Activation

次のように依頼された場合、この profile を使用する。

```text
$adaptive-implementation-execution を使って、この Plan を実装してください。
通常 Plan Mode で作成した Plan を adaptive implementation で進めてください。
```

Plan Coverage artifacts は必須ではない。goal、scope、acceptance を判断できる通常 Plan だけで開始できる。

## Execution ownership

- 非自明な implementation は必ず `high-implementation-starter` から開始する。
- parent / router は production code と tests を直接編集しない。
- HIGH_MODEL と STANDARD_MODEL の write-heavy work を並列実行しない。
- `high-implementation-starter` の run が完了し、`READY_FOR_STANDARD_COMPLETION` handoff が検証された後だけ `standard-implementation-completer` を起動する。
- safe delegation point がなければ HIGH_MODEL が完了まで実装してよい。
- STANDARD_MODEL が新しい design decision を発見した場合は、`NEEDS_HIGH_MODEL_REENTRY` で停止し、元 intent と handoff を保持して HIGH_MODEL に戻す。

## Delegation gate

STANDARD_MODEL へ渡せるのは、主要な責務配置、production path / wiring、signature、test seam が確定し、新しい dependency / module / class / interface の選択が不要で、remaining work と allowed edit surface を明示できる場合だけとする。

課題全体が small-bounded、low risk、少数ファイルであることだけを delegation 理由にしない。

## Handoff

通常は inline handoff を使う。resume、別 thread、別 model、別作業者への移行が必要な場合だけ tracked handoff を `plans/<slug>-implementation-completion-handoff.md` に保存する。

## Verification and review

各 implementation agent は関連する build、focused test、lint、format、type check を可能な範囲で実行する。

この profile は final code review、総合 architecture review、human review、独立 verification の完了を宣言しない。必要な review / verification は別工程として扱う。

## Model mapping

`HIGH_MODEL` と `STANDARD_MODEL` は抽象 tier である。実モデル、reasoning effort、sandbox は `agents/*.toml` の top-level fields で設定し、instruction 本文へ実モデル名を埋め込まない。

