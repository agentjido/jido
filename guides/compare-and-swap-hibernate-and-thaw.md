# Compare-and-Swap, Hibernate, and Thaw

Persistence must protect an Agent from stale writers. Jido uses record revisions
and adapter compare-and-swap operations for this purpose.

## One Turn, one revision

An `AgentServer` has a `state_version`. Each successful Turn increases it once,
even when the next Agent state is identical to the current state. A failure
before commit keeps the current revision. A failure during post-commit work does
not undo it.

The server supplies its current revision as `:expected_revision` when it saves.
The write succeeds only when storage still has that revision. Before a new
persistent start succeeds, the server writes the supplied Agent as a create-
only revision-zero record.

Direct persistence calls can use the same rule:

```elixir
:ok = Jido.Persistence.save_agent(store, agent,
  revision: 4,
  expected_revision: 3,
  instance: MyApp.Jido
)
```

A conflict returns `{:error, :conflict}` and does not replace the stored record.
For a live Turn, any persistence write error also stops that Server activation
before it can evaluate more work. A revision cannot decrease. A save of the
exact same record at the same revision is idempotent.

Compare-and-swap prevents a confirmed stale write. It is not a writer lease.
Normal delete preserves revision history in a tombstone. Normal create and save
cannot replace that tombstone. Physical purge or storage expiry removes the
fence. Same-identity reactivation is not a normal Core operation.

## Write failures

Every required persistence write error stops the Server activation before it
accepts more work. Error policy cannot keep the stale writer active. Start a
new activation and restore the authoritative record before a retry.

A confirmed conflict means that the exact expected bytes did not match. A
confirmed `{:rejected, reason}` result means that a documented preflight limit
stopped the write before it started. Every other CAS error is indeterminate.
This includes an exception, throw, exit, timeout, invalid result, or an
unclassified adapter error. Storage can then contain either the previous
record or the candidate record.

Application recovery must then read the durable record and decide if the Turn
committed. Give external operations stable identifiers so a retry does not
repeat an effect.

## Restore policies

An Agent start accepts one of three restore policies:

| Policy | Result |
| --- | --- |
| `false` | Do not read persistence. Create the supplied Agent at revision zero. Fail if an active record or tombstone exists. |
| `:if_found` | Restore an active record. If it is missing, create the supplied Agent at revision zero. |
| `:required` | Restore a record. Fail the start when no valid record exists. |

The default is `:if_found`. A tombstone returns `:deleted` and fails all three
normal creation or restore paths. `:required` is useful when a start is
specifically a recovery operation.

Plugin runtimes can start provisionally before the initial storage write. Jido
stops that runtime tree if the write fails. The start call does not return
success until the write is confirmed. Instance lookup and listing also hide
the provisional Server. The Registry entry reserves the identity as
`:starting` and changes to `:ready` only after the confirmed write.

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

## Keep durable identity stable

A namespaced Jido instance stores a new Agent under a key derived from the
complete `{namespace, partition, id}` Ref. It uses persistence record format 3.
The local instance atom and Agent module are not part of that key. The record
still stores and validates the Agent module.

Use `activate_agent/3` to restore by Ref. After the live Server hibernates or
stops, use `delete_agent/3` to write a logical tombstone. `delete_agent/3`
refuses to delete while the local Server is live.

When a namespaced operation finds only a legacy instance-keyed record, Jido
continues to use that key. When it finds both the legacy key and the stable Ref
key, it returns a persistence identity collision. It does not select one or
rewrite either key.

Adding a namespace is an application migration gate. Stop old writers and
check for collisions before you enable the new runtime. The adapter contract
cannot atomically move data between two keys. An older release cannot read
format 3, so downgrade after the first stable Ref write is not supported.
Legacy keys also contain the Agent module. Inventory the old keyspace for two
module keys that would collapse to one Ref because Core adapters do not provide
a key-list operation.

## Recovery scope

A Jido instance also keeps an ephemeral runtime checkpoint for abnormal
`AgentServer` restarts. It can restore the actor while that Jido instance stays
alive. A normal actor stop removes that checkpoint. It is not durable storage
and does not replace a persistence adapter.

The next guide explains how to design external work that can recover after a
durable Agent commit.
