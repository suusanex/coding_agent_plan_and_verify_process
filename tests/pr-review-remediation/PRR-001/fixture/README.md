# PR Review Fixture

This deterministic fixture changes `ValueProvider.Compute()` from `false` to
`true`. The patch intentionally contains no matching test update so that the
local reviewer has one concrete regression-coverage finding to report.

Validation for a remediation plan must include focused behavior coverage and a
repository build. The public API shape must remain unchanged.
