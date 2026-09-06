> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Commit and effects

[Design overview](README.md) | Previous: [Jido instance](jido-instance.md) | Next: [Instance persistence](instance-persistence.md)

- Status: Revised after REC-01 review; pending document approval.
- Defines: state commit, transient Directive dispatch, and explicit durable work.

## State and effect contract

- Direct `Jido.Agent.cmd/3` returns a validated candidate and Directives. It
  commits no live state and dispatches no Directive.
- An Action or Flow can perform synchronous external work during evaluation.
  A later failure does not undo that work. Applications own duplicate handling.
- The Server validates the complete candidate and Directive batch before commit.
- With persistence enabled, the checkpoint write succeeds before live state
  changes or the caller receives success.
- Each committed Turn advances the Agent state revision once.
- Directives run after commit. Dispatch cannot change Agent state. A result
  that changes state enters through a new Signal and Turn.
- A dispatch failure does not undo the commit.

## Ordinary Directives

The Server resolves each Directive owner, validates the batch, and dispatches
it in list order after commit. Live dispatch remains part of the current Turn's
runtime work. A Directive failure follows the configured runtime error policy.

Ordinary Directives are not automatically saved or replayed after a crash.
Their runtime fields can include process references when their contracts allow
this. A portable Directive alone does not make its execution recoverable.

The earlier universal `Jido.Agent.Outbox.Entry`, completion cursor, and
`:outbox_blocked` policy are removed from the core design. A pending application
job is not a reason to block every later Agent Turn.

## Explicit durable work

A Plugin or application can define a capability that requires delivery after
restart. It stores portable intent in Agent or Plugin-owned state, in the same
candidate and checkpoint as the business change.

```text
business change + pending work
  -> one candidate and checkpoint write
  -> committed Agent state
  -> supervised worker reads pending work
  -> receiver confirms the operation
  -> completion Signal
  -> new Turn commits completion
```

The [REC-01 example](../../examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex)
uses existing `Jido.Plugin.update_state/3` to record intent. A post-commit
Directive only wakes the worker. The worker also reads committed Plugin state
on startup and at each poll, so a lost wake-up does not lose work.

Completion is another Agent state change. It uses the normal commit boundary
and advances the state revision. REC-01 needs no separate storage cursor or
completion-only persistence API. New Turns preserve older pending entries.

A capability defines:

- A stable work ID, portable input, and duplicate/conflict policy.
- What receiver acknowledgement means: accepted, durably accepted, or completed.
- Retry delay, attempt timeout, ordering, cancellation, and failure handling.
- How to start again from committed state and keep completed work complete.
- Retention for completed IDs and any trace or causation needed across restart.

Sending an OTP message or receiving `:ok` from a cast is not proof that the
receiver committed its work. Delivery after restart can repeat an external
operation if its acknowledgement was not committed. The receiver must handle
that repeat. At-least-once completion depends on later activation, an available
worker and receiver, and the capability's retry policy.

## Runtime resources and children

Connections, Tasks, PIDs, timers, and execution objects stay in runtime memory.
Store desired resources and stable identities when they must be reconstructed.
A resource Plugin compares desired state with current runtime state and repairs
the difference. Replaying a historical spawn request is not sufficient proof
of current child ownership, especially across Erlang nodes.

The remote-child placement contract does not provide durable distributed
ownership, automatic failover, or a lease. Those remain separate research cases.

## Persistence and lifecycle

The checkpoint includes Agent and Plugin-owned state. Thus an explicit pending
work set is stored atomically with the business state. Persisting a separate
queue entry after the checkpoint would leave a failure window.

The proposed instance-level Record and lifecycle API in
[Instance persistence](instance-persistence.md) remain separate work. They do
not require a Directive outbox. A proposed Commit binds a checkpoint to its
state version and Turn identity; it has no outbox or cursor fields.

Restore loads committed state and starts Plugin runtimes. Recovery work can
continue while the Agent accepts Signals, unless an explicit capability needs
a stricter gate. Hibernation stops runtime work; pending intent remains in the
checkpoint. Later activation resumes according to the capability's policy.

## Evidence and limits

[REC-01 results](../examples/rec-01-results.md) cover process and Plugin loss,
failed writes, duplicate delivery, and new Turns while delivery is blocked.
These tests use one BEAM and the File adapter. They do not prove power-loss
storage durability, a durable mailbox, recovery of a partly evaluated Turn,
exactly-once effects, or distributed write authority.
