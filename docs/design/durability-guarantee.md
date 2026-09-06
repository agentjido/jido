> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Durability guarantee

[Design overview](README.md) | Previous: [Instance persistence](instance-persistence.md) | Next: [Runtime topology](runtime-topology.md)

- Status: Revised after REC-01 review; pending document approval.
- Scope: persistent Agent state and explicitly selected recovery capabilities.

## Decision

Core restores committed Agent and Plugin state. Recoverable external work is
an explicit Plugin or application capability. It is not the default behavior
of every Directive.

OTP owns process supervision and restart. Jido owns the candidate, commit, and
restore boundaries. The persistence provider owns storage durability. A delivery
capability owns saved intent, retry, acknowledgement, and duplicate handling.

## Guarantees

With persistence configured, a successful state-changing call confirms that
the checkpoint write succeeded before live state changed. The strength of that
storage guarantee depends on the adapter and its deployment conditions.

An explicit delivery capability stores pending work in the same checkpoint as
the business change. Its supervised worker reads committed state after startup
and retries pending work. Completion enters as another Signal and commits as
another Agent revision. A later business commit must preserve pending work.

A successful command confirms the state commit. It does not confirm external
delivery. A caller must inspect the capability's completion state when that
result matters. Turn settlement only covers that Turn's runtime Directive
batch; it is not completion of all background business work.

There is no universal core Directive outbox, completion cursor, or
`:outbox_blocked` stop rule. Ordering and admission restrictions are explicit
capability policies. The REC-01 worker keeps the Agent available during a
blocked delivery.

## Failure boundaries

| Failure point | Explicit delivery capability behavior |
| --- | --- |
| Before the intent write succeeds | No new committed intent exists for a worker to read. |
| After commit, before wake-up or delivery | A later worker reads the saved pending entry. |
| Receiver is unavailable | Keep the entry pending and apply retry policy. |
| After the effect, before confirmation commits | Retry the same work ID; the receiver handles the duplicate. |
| Completion write fails without changing storage | Keep pending intent and retry. |
| After confirmation commits | Restore the completed record and do not deliver it again. |
| A later business Turn commits | Preserve earlier pending work. |
| An Agent or Plugin runtime exits | Supervision or explicit activation starts a worker from committed state. |

A write with an unknown result needs a storage authority policy. REC-01 does
not prove safe continued writes after an indeterminate result. The stricter
lost-write-authority rules in the proposed instance persistence design remain
separate core work. The example's failed-write tests inject known failures
before the storage mutation.

## Constraints

- Work IDs and input must survive serialization. Do not persist Tasks, PIDs,
  clients, callbacks, or an in-progress Flow.
- The receiver's acknowledgement boundary must be defined. A cast returning
  `:ok` does not establish receipt or committed business work.
- A crash can cause repeat execution. Use idempotent operations or a receiver
  that records stable IDs and rejects conflicting reuse.
- Durable intent does not start a stopped Agent by itself. Later activation
  and available dependencies are conditions of eventual completion.
- Completed-ID retention, retry limits, ordering, cancellation, and operational
  handling of permanent failures belong to the capability.

## Non-guarantees

This contract does not provide a durable mailbox, recovery of a partly
completed Turn, rollback of external work, exactly-once effects, automatic
activation after node loss, or distributed ownership and failover.

A nonpersistent Agent makes no crash recovery promise. A persistent Agent's
storage must remain available after the failure being tested. The File adapter
permits one BEAM to own a directory; the process-restart proof does not establish
shared writes across nodes or survival of a machine power failure.

## Verification

The [REC-01 tests](../../test/jido/agent/effect_recovery_test.exs) use the real
Server, Plugin composition, checkpoint, restore, and completion Signal paths.
A controlled sink holds real attempts at the failure boundaries. The same
sink records duplicate writes outside the failed Agent.

The [results](../examples/rec-01-results.md) list the measured scope. The
broader instance Record, lifecycle, and authority proposals are not reported
as implemented by this example.
