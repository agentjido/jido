# Turns, Commit, and Effects

A Turn is one admitted Signal execution for one Agent. It has one stable Turn
ID and can commit at most one new Agent revision.

## Follow The Turn

| Stage | Work |
| --- | --- |
| Admission | Runtime Plugins accept or reject the Signal |
| Preparation | Plugins prepare the Signal and caller context |
| Routing | The effective Signal selects one executable |
| Execution | One Action or Flow returns candidate state and Directives |
| Finalization | Plugins update owned state and Jido validates all state |
| Commit | Persistence succeeds and the live Agent value changes |
| Dispatch | Directives run in declared order |
| Settlement | Jido records the terminal Outcome |

Direct commands use preparation, routing, execution, and finalization. They
return a candidate and Directives. Admission, live commit, dispatch, and
settlement belong to the Agent Server.

## Locate The Commit Boundary

Candidate validation must finish before commit. With persistence enabled, Jido
writes the checkpoint before it changes live state or reports success.

Each successful Turn increases `state_version` by one, even when the returned
state compares equal to the prior state. An error before commit leaves the
version unchanged.

## Separate State From External Effects

An Action can do synchronous I/O before commit when its result is needed for
the candidate. A Directive requests work after commit. Neither operation is
part of an external transaction.

For an external write:

- give the operation a stable application idempotency key;
- store pending intent when recovery must survive a crash;
- record acknowledgement with business state when possible;
- reconcile an uncertain response before retry.

## Understand Directive Failure

Directives run in list order. The first failure stops the rest of the batch.
The Agent commit remains. A caller waiting for the state transition can receive
the committed Agent before later runtime work fails.

Use the settled telemetry event or `Jido.Agent.Turn.Outcome` when you must know
the result of the complete Turn, including Directives.

## Keep Timeouts Separate

A caller timeout stops waiting. It does not cancel work that already entered
the Server. Runtime execution limits and explicit cancellation control the
active Turn. An external timeout can still have an uncertain result.

Next, read [Directives And Outcomes](directives-and-outcomes.md) and
[Recoverable Effects](recoverable-effects.md).
