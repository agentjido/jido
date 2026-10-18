# Turns, Commit, and Effects

A Turn is one admitted Signal execution for one Agent. It has one stable Turn
ID and can commit Agent state at most once. With persistence, a Flow also saves
acceptance and terminal status in record revisions.

## Follow The Turn

| Stage | Work |
| --- | --- |
| Admission | Runtime Plugins accept or reject the Signal |
| Routing | The Signal selects one executable |
| Execution | One Action or Flow returns candidate state and Directives |
| Finalization | Plugins update owned state and Jido validates all state |
| Commit | Persistence succeeds and the live Agent value changes |
| Notification | Optional Plugin `after_commit/3` hooks run in declaration order |
| Dispatch | Directives run in declared order |
| Settlement | Jido records the terminal Outcome |

Direct commands use routing, execution, and finalization. They return a
candidate and Directives. Admission, live commit, notification, dispatch, and settlement
belong to the Agent Server.

## Locate The Commit Boundary

Candidate validation must finish before commit. With persistence enabled, Jido
writes the checkpoint before it changes live state or reports success.

Each successful Action Turn increases `state_version` by one, even when Agent
state is unchanged. An Action error before commit leaves the version unchanged.
A persistent Flow saves acceptance and terminal status in separate revisions.
A failed Flow preserves Agent state but still saves its failure receipt.

## Separate State From External Effects

An Action can do synchronous I/O before commit when its result is needed for
the candidate. A Directive requests work after commit. Neither operation is
part of an external transaction.

Use `{:ok, state, directives}` to return deferred
requests from an Action. Flow collects these requests and returns one batch
only after complete success. Failed execution, candidate validation, and
Directive validation return no batch for dispatch. See
[Directives And Outcomes](directives-and-outcomes.md#return-explicit-effects).

For an external write:

- give the operation a stable application idempotency key;
- store pending intent when recovery must survive a crash;
- record acknowledgement with business state when possible;
- reconcile an uncertain response before retry.

## Understand Directive Failure

Directives run in list order. The first failure stops the rest of the batch.
The Agent commit remains. A caller waiting for the state transition can receive
the committed Agent before later runtime work fails.

Read `Jido.AgentServer.status/1` to distinguish the Turn result from the
post-commit result. `last_outcome` records the Turn's status, commit state,
revisions, IDs, Directive count, and duration. The error-policy callback
receives this summary after a failure. `last_effect_outcome` records the
separate post-commit status, stage, counts, and committed revision.
Neither summary contains full Signals, Agent state, or raw errors.

An optional Plugin commit notification runs before returned Directives. It
receives only the owned committed value and its exact revision. Failure uses
stage `:after_commit`, skips remaining notifications and Directives, and cannot
undo the commit. Startup and restore rebuild runtimes from `Init`; they do not
replay notifications. See [Plugin Contract and Lifecycle](plugin-contract-and-lifecycle.md).

## Keep Timeouts Separate

A caller timeout stops waiting. It does not cancel work that already entered
the Server. Runtime execution limits and explicit cancellation control the
active Turn. An external timeout can still have an uncertain result.

Next, read [Directives And Outcomes](directives-and-outcomes.md) and
[Recoverable Effects](recoverable-effects.md).
