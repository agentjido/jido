# Compare-and-Swap, Hibernate, and Thaw

Persistence must protect an Agent from stale writers. Jido uses record revisions
and adapter compare-and-swap operations for this purpose.

## One Turn, one revision

An `AgentServer` has a `state_version`. Each successful Turn increases it once,
even when the next Agent state is identical to the current state. A failure
before commit keeps the current revision. A failure during post-commit work does
not undo it.

The server supplies its current revision as `:expected_revision` when it saves.
The write succeeds only when storage still has that revision. A missing record
is valid for the first revision-zero expectation.

Direct persistence calls can use the same rule:

```elixir
:ok = Jido.Persistence.save_agent(store, agent,
  revision: 4,
  expected_revision: 3,
  instance: MyApp.Jido
)
```

A conflict returns `{:error, :conflict}` and does not replace the stored record.
A revision cannot decrease. A save of the exact same record at the same revision
is idempotent.

Compare-and-swap prevents a confirmed stale write. It is not a writer lease. A
delete or expiry removes the old revision history, and a new record can start
again.

## Indeterminate writes

An adapter exception, timeout, or invalid result can make a write outcome
uncertain. The server stops the writer before it accepts more work. This keeps
one process from work on an unconfirmed storage history.

Application recovery must then read the durable record and decide if the Turn
committed. Give external operations stable identifiers so a retry does not
repeat an effect.

## Restore policies

An Agent start accepts one of three restore policies:

| Policy | Result |
| --- | --- |
| `false` | Start from the supplied Agent value. Do not read persistence. |
| `:if_found` | Restore a record when it exists. Otherwise, use the supplied value. |
| `:required` | Restore a record. Fail the start when no valid record exists. |

The default is `:if_found`. `:required` is useful when a start is specifically a
recovery operation.

## Hibernate a live actor

Hibernate waits until the actor is idle, persists its committed Agent, and stops
the server.

```elixir
:ok = MyApp.Jido.hibernate(server, timeout: 10_000)
```

The call returns after the actor stops. It fails when persistence is not
configured or when the checkpoint cannot be saved.

## Thaw the Agent

Thaw starts an actor with the same module and ID and sets `restore: :required`.

```elixir
{:ok, server} = MyApp.Jido.thaw(MyAgent, "agent-42")
```

Use the same partition option that identified the original actor. Thaw is a
normal actor start after the restore step. Thus, Plugin runtimes and other
process resources start again from their specifications.

## Recovery scope

A Jido instance also keeps an ephemeral runtime checkpoint for abnormal
`AgentServer` restarts. It can restore the actor while that Jido instance stays
alive. A normal actor stop removes that checkpoint. It is not durable storage
and does not replace a persistence adapter.

The next guide explains how to design external work that can recover after a
durable Agent commit.
