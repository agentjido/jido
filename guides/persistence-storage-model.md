# Storage Model

A persisted Agent is one record under one key. The Agent Server rewrites that
record on every successful Turn, and an adapter stores it as opaque bytes.
This guide shows the key, the record, the snapshot inside it, the revision
and tombstone rules, and the terms a record can hold.

The examples use this Agent and the ETS adapter:

```elixir
defmodule StorageGuide.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/guides/storage")

    route "counter.add", as: :add, defaults: %{amount: 1} do
      action %{amount: amount},
        schema: Zoi.object(%{amount: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount}}
      end
    end
  end
end
```

## One Agent, One Record

```elixir
store = {Jido.Persistence.ETS, table: :storage_guide}
{:ok, _} = Jido.start(namespace: "storage-guide", persistence: store)

{:ok, pid} = Jido.start_agent(StorageGuide.Counter, id: "counter-1", persistence: :inherit)
:ok = Jido.AgentServer.await_ready(pid)

signal = StorageGuide.Counter.add_signal!(%{amount: 5})
{:ok, _agent, []} = Jido.AgentServer.call(pid, signal)

{:ok, agent} =
  Jido.Persistence.load_agent(store, StorageGuide.Counter, "counter-1",
    namespace: "storage-guide"
  )

agent.state
# => %{count: 5}
```

The Server wrote two versions of one record: revision 0 before it reported
ready, and revision 1 for the Turn. `:ets.tab2list(:storage_guide_records)`
returns one row.

`persistence: :inherit` selects the instance's adapter. An Agent started
without a `:persistence` option isn't persisted. `Jido.thaw/4` sets
`persistence: :inherit` for you.

## The Key

```text
"jido:agent:v1:" <> Base.url_encode64(:erlang.term_to_binary({namespace, partition, id}), padding: false)
```

Three values make the identity:

| Part | Source | Example |
| --- | --- | --- |
| `namespace` | `:namespace` on the instance, or the `namespace:` option | `"storage-guide"` |
| `partition` | `:partition` option, default `nil` | `nil` |
| `id` | The Agent ID | `"counter-1"` |

The Agent module isn't part of the key. Two modules with the same ID in one
namespace and partition share a record. Loading it with the other module
returns `{:error, {:invalid_persistence_record, :agent_module}}`.
A save without a namespace returns `{:error, :stable_namespace_required}`.
Use one namespace per tenant or environment. See
[Instances and Tenants](configuration-and-tenant-isolation.md).

## The Record

The value is `:erlang.term_to_binary/1` of a map. Jido decodes it with
`:erlang.binary_to_term(bytes, [:safe])`. Record format 4 holds:

| Field | Value |
| --- | --- |
| `fmt` | `4` |
| `kind` | `:active` or `:tombstone` |
| `namespace`, `partition`, `agent_id` | The identity from the key |
| `agent_module` | The module that wrote the record |
| `rev` | The revision, an integer `>= 0` |
| `vsn` | The Agent definition version (active records only) |
| `checkpoint` | The Agent snapshot (active records only) |
| `server_turn` | Optional Turn data written by the Server (active records only) |

`server_turn` uses one exact receipt shape. A durable Flow receipt stores its
Turn ID, Signals, portable context, Plugin input, definition fingerprint,
status, and expiry. A Handoff receipt also stores the successor instruction,
chain ID, chain order, and predecessor Turn ID. An accepted Handoff has no
admitted Signal or Plugin input. A released Handoff adds those fields and the
successor expiry. See [Durability Model](durability-model.md#durable-handoff)
for release and recovery rules.

Decoding the row from the example:

```elixir
[{_key, bytes}] = :ets.tab2list(:storage_guide_records)
record = :erlang.binary_to_term(bytes)

Map.take(record, [:fmt, :kind, :namespace, :agent_id, :partition, :rev])
# => %{fmt: 4, kind: :active, namespace: "storage-guide",
#      agent_id: "counter-1", partition: nil, rev: 1}
```

A record with missing or wrong fields fails to load with
`{:error, {:invalid_persistence_record, reason}}`, such as `:shape` or
`:agent_module`. Format 3 records, with `format`,
`revision` and `agent_vsn` fields, still load so older data survives a
cutover.

## Snapshots

`record.checkpoint` is a snapshot: the complete Agent as data, including its
definition. You can make one without storage:

```elixir
{:ok, snapshot} = Jido.Persistence.snapshot(agent)
Map.keys(snapshot)
# => [:format, :references, :agent, :state_format]

{:ok, restored} = Jido.Persistence.restore(snapshot)
restored.state
# => %{count: 5}
```

| Field | Value |
| --- | --- |
| `format` | `1` |
| `agent` | The `Jido.Agent` struct, with schemas and nested definitions as data |
| `references` | Each code module the Agent needs, mapped to its 16-byte MD5 fingerprint |
| `state_format` | `:default`, or `:custom` when the Agent defines `checkpoint/2` |

Restore never rebuilds the Agent from its source module. It checks that every
referenced module is loaded and that its fingerprint matches. A changed
module fails with `:changed_reference` and the message
`"Snapshot code changed; use an explicit upgrade Action"`. Any code
change to a referenced module changes its fingerprint. Run
`Jido.Persistence.upgrade/3` to move a record forward. See
[Checkpoints and Upgrades](checkpoints-and-data-upgrades.md).

In the `:default` format, each Plugin with persistence callbacks converts its
own state field with `dump/3` on save and `load/3` on restore. See
[Plugin Persistence](plugin-persistence-and-live-changes.md).

## Portable Terms

A snapshot holds only portable terms, so it can be decoded on another node
or after a restart. These are rejected anywhere in the value:

- pids, references and ports;
- functions;
- bitstrings that aren't whole binaries; and
- improper lists.

Maps, lists and tuples are checked recursively. A failure returns a
`Jido.Agent.Error` with `code: :non_portable_term`, the message
`"Snapshot contains a non-portable value"`, and the path to the first bad
value, such as `[:snapshot, :agent, :state, :owner]`. Paths stop at 20
segments.

Keep live handles out of Agent state. Store a registered name or an ID, and
look up the process when you need it.

## Revisions

| Event | Revision |
| --- | --- |
| A new Agent starts with persistence | `0`, written before the Server reports ready |
| Each successful Turn | Previous `+ 1`, even when the state didn't change |
| `Jido.hibernate/2` | Unchanged; the last committed record stays |
| `Jido.thaw/4` | Restores the stored revision |

Every Server write sets `expected_revision` to the revision it holds. If
another writer moved the record, the write returns `{:error, :conflict}` and
the activation ends. Direct calls to `Jido.Persistence.save_agent/3` follow
the same rules:

```elixir
stale = %{agent | state: %{count: 99}}

Jido.Persistence.save_agent(store, stale,
  namespace: "storage-guide",
  revision: 2,
  expected_revision: 0
)
# => {:error, :conflict}
```

A stored revision can't go down. At the same revision, only the identical
record can be saved again. For the conflict model, see
[Revisions and Conflicts](durable-revisions-and-conflicts.md).

## Tombstones

`Jido.Persistence.delete_agent/4` doesn't remove the key. It replaces the
record with a tombstone at the same revision:

```elixir
:ok = Jido.stop_agent(pid)
:ok = Jido.Persistence.delete_agent(store, StorageGuide.Counter, "counter-1", namespace: "storage-guide")

Jido.Persistence.load_agent(store, StorageGuide.Counter, "counter-1", namespace: "storage-guide")
# => {:error, :deleted}

Jido.Persistence.save_agent(store, agent, namespace: "storage-guide", revision: 5)
# => {:error, :conflict}
```

A tombstone holds `fmt`, `kind: :tombstone`, the identity, `agent_module` and
`rev`. It has no checkpoint and no state. It blocks every later save, so a
delayed writer can't bring a deleted Agent back. `Jido.thaw/4` on a
tombstone stops the new Server with `{:shutdown, :deleted}`. Deleting an ID
that was never saved writes a revision 0 tombstone.

Only an adapter's `delete/2` removes a key. Jido calls it for explicit
maintenance, never during a Turn.

## What Adapters See

An adapter receives a binary key and a binary value. It never decodes them.

| Stored | Never stored |
| --- | --- |
| The record bytes: identity, revision, module name, checkpoint | Pids, references, ports or functions |
| Plugin state after `dump/3` | Plugin runtime resources |
| Snapshot code fingerprints | Code or BEAM files |
| Tombstones | Effects, Directives or Turn queues |

Every adapter stores the same keys and the same record bytes. To move
Agents between adapters, copy the keys and values. See
[Persistence Adapters](persistence-adapters.livemd) for each backend and
[Custom Adapters](custom-persistence-adapter.md) to write one.

## Next

- [Durability Model](durability-model.md) – when a write happens and what a
  failed write means.
- [Make an Agent Durable](make-an-agent-durable.livemd) – a full durable Agent.
- [Checkpoints and Upgrades](checkpoints-and-data-upgrades.md) – custom
  checkpoints and data upgrades.
