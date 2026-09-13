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
`Jido.Error.stable_codes/0` returns the closed 21-code registry. It includes
checkpoint and definition failures, Plugin-owned-field protection, callback
and task failures, operation limits, and instance namespace failures.

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
Ref resolution keeps `{:ok, pid}` and `{:error, :not_found}`. Topology
Controller repair and readiness keep `:ok`, status maps, and PID-or-`nil`
lookup results.

## Classify The Failure

| Failure point | Commit result | Required decision |
| --- | --- | --- |
| Admission or preparation | No commit | Correct input or admission policy |
| Routing | No commit | Correct routes or Signal type |
| Action or Flow | No commit | Decide whether external work is safe to repeat |
| Candidate validation | No commit | Correct the returned complete state |
| Confirmed storage conflict | No commit by this writer; activation stops | Restore the winning record in a new activation |
| Confirmed storage rejection | No commit; activation stops | Correct the documented preflight limit and restore in a new activation |
| Indeterminate storage write | Unknown durable result; activation stops | Reload authoritative state in a new activation |
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

Every required persistence write error removes the current activation's write
authority. This rule applies even when its normal error policy would continue.
The stopped activation does not reload or retry the Turn.

Persistence load returns `:not_found` for an absent record and `:deleted` for a
tombstone. A tombstone is an intentional durable fence. Do not treat it as a
missing record or create the same identity again through the normal lifecycle.

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

The `{:emit_signal, dispatch}` error policy sends a custom
`Jido.AgentServer.Signal.Error` with type `jido.agent.error`. Its data contains
the Agent and Turn IDs, status, stage, commit flag, and transport error map.
Its context carries the failed input's causation ID and available trace context.

See [Admission, Cancellation, And Timeouts](admission-cancellation-and-timeouts.md)
and [Extension Boundaries](extension-boundaries.md).
