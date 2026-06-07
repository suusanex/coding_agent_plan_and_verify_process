# Stop Report

task_slug:
state_artifact:
current_gate:
next_gate:
recommended_model_tier:
allowed_to_edit:
edit_owner:
delegation_required:
expected_agent:
delegation_compliance:
stop_reason:

## Why Stopped


## Minimum Human Input Needed


## Not Allowed Until Resolved

- Implementation outside READY scope
- Parent-direct execution of a delegated gate without ParentDirectExecutionException and explicit human approval
- Close when DelegationCompliance is FAIL or Agent Usage Ledger is missing
- Close / completion claim
- Secret, external service, billing, or production operation

## Delegation Evidence Needed

- Expected agent:
- Missing observed run:
- Required artifact:

## Resume Command

```text
続きやって。
```
