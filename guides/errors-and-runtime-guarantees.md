# Errors and Runtime Guarantees

Jido uses structured errors at public boundaries. Recovery depends on the
stage where the error occurred and on whether state committed.

## Error Families

`Jido.Error` defines validation, routing, execution, timeout, compensation, and
internal error types. Use `Jido.Error.to_map/1` when an application needs a
bounded transport value. The map always has the top-level keys `type`,
`message`, `details`, and `retryable?`.

Some Jido-owned conversions have a stable code in `error.details.code`. Use
`Jido.Error.code/1` to read it. Do not match a human-readable message.

Do not expose raw error details to an untrusted caller without review. Details
can contain application data.

## Callback Failures

Jido preserves the reason from a declared callback result of
`{:error, reason}`. This result belongs to the application callback contract.
Jido converts these other cases at the boundary that owns the callback:

| Callback result | Jido result |
| --- | --- |
| Invalid success or result shape | Owner error with an invalid-callback-result code |
| Raise, throw, or exit | `Jido.Error.ExecutionError` with a callback-failed code |
| Owned task exits before a result | `Jido.Error.ExecutionError` with a task-failed code |
| Owned operation reaches its limit | `Jido.Error.TimeoutError` with a timeout code |

This rule does not replace OTP caller timeouts or public lifecycle controls.
Persistence adapter controls, Agent Server cancellation values, PID lookup,
Registry names, and OTP start and stop values keep their documented forms.

## Classify The Failure

| Failure point | Commit result | Required decision |
| --- | --- | --- |
| Admission or preparation | No commit | Correct input or admission policy |
| Routing | No commit | Correct routes or Signal type |
| Action or Flow | No commit | Decide whether external work is safe to repeat |
| Candidate validation | No commit | Correct the returned complete state |
| Confirmed storage conflict | No commit | Resolve the competing writer |
| Indeterminate storage write | Unknown durable result | Reload authoritative state |
| Directive dispatch | Commit remains | Reconcile post-commit work |

Retry information is guidance. It does not prove that an external operation is
safe to repeat.

## State Guarantees

Jido validates one complete Agent candidate before commit. A failed pre-commit
Turn keeps the prior live Agent value. A successful Turn advances one state
version.

Jido does not provide a transaction across Agent state and external services.
It also does not provide cluster-exclusive Agent ownership, distributed
consensus, or automatic compensation.

## Process Guarantees

An Agent Server accepts Turns in serial order. Cast delivery is best effort
under overload. Calls and request APIs return tagged success or error results.
OTP process exit and node connection behavior still apply.

Remote child creation can have an indeterminate reply. Retrying the same
logical child request resolves the same child identity, but the application
must still handle node loss and authority.

## Observe Settlement

The Turn span can finish at commit. Directive work can fail later. Use
`Jido.Agent.Turn.Outcome`, the settled telemetry event, or the bounded debug
buffer when you need terminal settlement.

See [Admission, Cancellation, And Timeouts](admission-cancellation-and-timeouts.md)
and [Extension Boundaries](extension-boundaries.md).
