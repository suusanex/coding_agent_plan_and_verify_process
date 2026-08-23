# Migration from local reviewer baseline

## 0.7.0 boundary

0.7.0はbaseline PR Reviewをremote GitHub PR evidence専用へ変更します。

| Former component | 0.7.0 disposition |
| --- | --- |
| Ready PR preparation | Retained |
| `collect-pr-review-context.cs` | Retained as remote evidence authority |
| GitHub Copilot Code Review request/wait | Retained and fail-closed |
| `local-reviewer` agent | Removed |
| local review template/raw artifact/execution metadata | Removed |
| `review-planner` | Retained with remote-only inputs |
| Goal Context/multi-round planner mode | Removed from baseline package |
| implementation agent | Remains in separately installed Adaptive Implementation |

Local reviewerを別runtimeで置き換えません。旧local findingsや旧実model fixtureをcurrent inputとして再利用せず、Git historyだけをhistorical recordとします。

目的reviewは互換性を持たない別package `persistent-purpose-review`とuser-level `purpose-review-runner`が担当します。
