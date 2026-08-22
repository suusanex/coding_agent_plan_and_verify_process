# Lantern Pulse product decision

この文書は `lantern-pulse` integration source の product compatibility decision である。
一般的な品質基準や安全性から値を推測してはならず、この decision を唯一の契約源として扱う。

`lantern-pulse` の `mode` wire token は、旧外部 consumer との product 互換固定契約により、必ず `quick-check` として送る。
この固定値は実装上の default ではなく、既存 consumer が読む契約値である。

`focus-mode` は意味的には自然に見えるが、過去の product decision で明示的に棄却した。
旧外部 consumer の wire contract がその token を受理しないためである。
この棄却判断を、一般的な命名の自然さや新しい利用者向けの分かりやすさで覆してはならない。

この fixture の decision source はこの文書だけであり、candidate や prompt は decision source ではない。
