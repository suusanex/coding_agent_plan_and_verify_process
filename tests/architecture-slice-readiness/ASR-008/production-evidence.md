# ASR-008 Production Evidence

Inspected production evidence addresses:

- `src/PlatformOperation.ps1::Invoke-PlatformOperation` owns the same-process call and returns the operation result to `Complete-OnUiThread` in the same entrypoint.
- `src/OperationState.ps1::Publish-OperationState` is the sole writer to `state/operation.json` and is called only after that UI handoff.
- `src/StartupReader.ps1::Read-OperationState` is read-only and consumes the same schema during the later startup path.
- `tests/verify-operation-flow.ps1` invokes the production entrypoint and verifies platform result -> UI completion -> durable write -> later read as one ordered oracle.

No independently deployed service, separate retry lifecycle, competing authority, or independently releasable sequence exists in the inspected source.
