# Admission, Cancellation, and Timeouts

Admission protects one live actor before executable work starts. Cancellation
stops eligible active work. Timeouts belong to specific waits.

## Bound Postponed Work

`max_postponed_signals` limits admission tokens for work that the state machine
has received and postponed. The default is 1,000. Use `:infinity` only when an
outer system supplies a firm bound.

This limit does not bound messages that have not reached the state-machine
callback. Rate-limit producers when mailbox growth matters.

Cast delivery is best effort under overload. Calls receive an error when Jido
can reject them before their deadline.

## Run Plugin Admission

Plugins with `admit/3` can use their optional runtime to accept or reject a
command. Admission uses the active `turn_timeout` pre-commit deadline. It runs
after pure preparation and before Turn evaluation. It can inspect its own pure
prepared input but cannot replace it.

A Plugin cannot make a synchronous reentrant call to the same Agent from its
admission task. Jido rejects this case to avoid a deadlock.

## Cancel Active Work

`Jido.AgentServer.cancel/2` cancels the eligible active Turn.
`cancel_turn/3` cancels only when the supplied Turn ID still matches.

Cancellation can stop admission or executable work before commit. It does not:

- undo completed Action I/O;
- reverse a completed commit;
- reverse a Directive that already reached an external system; or
- make an uncertain external result safe to retry.

`Jido.Exec` cancellation stays on its required owner process. It has at most
two 500 millisecond stop waits.
A successful cancellation ends the Turn. A failed or timed-out cancellation
is indeterminate and stops the Server.

## Distinguish Timeouts

| Timeout | Scope |
| --- | --- |
| `AgentServer.call/3` timeout | Caller wait and admission deadline |
| `turn_timeout` | Active Plugin admission and candidate evaluation before commit |
| Jido Action execution timeout | One executable chain |
| `directive_timeout` | One commit notification, Directive dispatch, or custom error policy |
| `idle_timeout` | Idle actor lifetime |
| topology startup timeout | One activation and readiness pass |
| persistence adapter timeout | Application adapter behavior |

Commit notifications use a 5,000 millisecond limit when `directive_timeout`
is `:infinity`. Each notification has its own limit.

A caller timeout does not cancel work that already started. Use explicit
cancellation when that is the required policy.

## Configure Error Policy

Server error policy can log, stop, stop after a count, emit an external Signal,
or call an application function with the error and Outcome. Policy runs after
Jido knows the failure stage. It cannot change the prior commit result.
An application policy function runs in an owned task. Status, stop, and later
Signals can run while it waits. Its stop result can arrive after a later Turn.
The task uses `directive_timeout`, or 5,000 milliseconds when that setting is
`:infinity`. A timed-out or failed policy task stops the Server.

See [Errors And Runtime Guarantees](errors-and-runtime-guarantees.md) and
[Agent Server Lifecycle](agent-server-lifecycle.md).
