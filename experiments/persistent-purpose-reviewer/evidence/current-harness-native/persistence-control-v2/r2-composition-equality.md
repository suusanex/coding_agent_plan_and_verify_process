# v2 Round 2 composition equality

Persistent R2 と Fresh R2 は同じ exact prompt/candidate bytes を使用した。

| item | bytes | SHA-256 |
| --- | ---: | --- |
| prompt `prompts\persistence-control-v2\round-2.md` | 1605 | `6760d25b1a22bbe2cbefe00e2a1ae3546ff0c34a01590af599344d0ad17917e6` |
| candidate `fixtures\persistence-control-v2\round-2-candidate.md` | 166 | `3a278bdee809a04d05e2a95c3ce213982b94f0f62a549679961fd3c9f601ac29` |
| persistent composition | 1771 | `0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357` |
| fresh composition | 1771 | `0c5be9a59873938331d8a0b96e2842174837b145d676d6023489d9a53079e357` |

注: composition は prompt bytes + candidate bytes の区切りなし連結。