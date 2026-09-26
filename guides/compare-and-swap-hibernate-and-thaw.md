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
  namespace: "my-app/agents",
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

Restore reads one snapshot. A deletion can complete after that read and before
activation returns. The next required write then fails with `:conflict` and
stops that activation before post-commit effects. A restore read is not a lease
on the record.

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

Every durable Agent uses a key derived from the exact
`{namespace, partition, id}` Ref tuple and persistence record format 3. The
local instance atom and Agent module are not part of the key. The record still
stores and validates the Agent module. Changing the module cannot create a
second record for the same Ref.

Configure a stable `:namespace` on each Jido instance that starts persistent
Agents. Direct persistence calls can supply `:namespace` or use the namespace
of their live `:instance`. A missing namespace returns
`{:error, :stable_namespace_required}`. An explicit namespace must be a nonempty
string. Partition must be `nil` or a nonempty string, as required by Agent Ref.
An instance without a namespace can still run Agents with persistence disabled.

Use `activate_agent/3` to restore by Ref. After the live Server hibernates or
stops, use `delete_agent/3` to write a logical tombstone. `delete_agent/3`
refuses to delete while the local Server is live.

### Move records from an earlier V3 beta

Current operations read and write only Ref keys and format 3. They do not look
for instance-based keys. Formats 1 and 2 at a Ref key return an invalid-format
error. `WriteAuthority`, `establish_write_authority/4`, and the instance-based
`agent_key/3,4` helpers have been removed. The `:write_authority` option is
rejected. Existing format-3 Ref records need no conversion.

Use an offline application migration for older records:

1. Stop all old writers, including background jobs. Back up the complete store.
   Keep those writers stopped after cutover.
2. Inventory the old keys with the storage provider's tools. Core adapters do
   not provide key listing. Assign one stable namespace to each logical set of
   Agents. Map old partitions to `nil` or nonempty strings. Find instance,
   module, or partition keys that map to the same Ref. Resolve those conflicts
   before writing. Include tombstones in this inventory.
3. Use the old application code to restore active records. Convert domain and
   Plugin-owned state as needed. Validate each Agent with the new code. In a
   separate empty target store, call `Persistence.save_agent/3` with the new
   namespace, the mapped partition, the saved revision, and `expected_revision: 0`.
   This also runs current checkpoint and Plugin conversion. Do not relabel an
   old checkpoint without this conversion.
4. Copy each tombstone to its target Ref key through an administrative adapter
   operation with a `:not_found` CAS condition. Its exact format-3 map contains
   `format: 3`, `kind: :tombstone`, `namespace`, `partition`, `agent_module`,
   `agent_id`, and the saved `revision`. Encode it with `:erlang.term_to_binary/1`.
   Do not drop tombstones or reset their revisions.
5. Read every target record with the new persistence API. Check Agent identity,
   state, definition revision, and storage revision. Tombstones must return
   `:deleted`. Compare the source and target inventories before starting new
   writers. Keep the backup separate.

The adapter cannot atomically move a record between keys. Do not run old and
new writers together. An indeterminate migration write needs a read and record
comparison before retry. Rehearse rollback with the backup; after new work has
started, rollback also requires reconciliation of external effects.

## Recovery scope

A Jido instance also keeps an ephemeral runtime checkpoint for abnormal
`AgentServer` restarts. It can restore the actor while that Jido instance stays
alive. A normal actor stop removes that checkpoint. It is not durable storage
and does not replace a persistence adapter.

The next guide explains how to design external work that can recover after a
durable Agent commit.
