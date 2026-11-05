# Deletion and Tombstones

This guide shows how to delete a durable Agent, what a tombstone blocks, and which data deletion leaves behind.

## Why deletion writes a record

Removing bytes would make a deleted Agent look like one that never existed. A delayed writer holding an old revision could then recreate it, and `Jido.activate_agent/4` could create a fresh Agent with the same ID.

So a normal delete replaces the active record with a compact tombstone, using compare-and-swap. The tombstone keeps the identity, the Agent module, and the last revision. It keeps no state or definition.

## Delete a stopped Agent

Use `Jido.delete_agent/4` with a stable Ref. It refuses while a local server for that Ref is live, so stop the Agent first.

```elixir
defmodule TombstonesGuide.Order do
  use Jido.Agent, name: "tombstones_order"

  state do
    schema Jido.Joi.object(%{status: Jido.Joi.string() |> Jido.Joi.default("open")})
  end
end

alias Jido.AgentServer, as: Server
alias TombstonesGuide.Order

{:ok, _} =
  Jido.start_link(
    name: TombstonesGuide.Jido,
    namespace: "guides/tombstones",
    persistence: {Jido.Persistence.ETS, table: :tombstones_guide}
  )

{:ok, ref} = Jido.agent_ref(TombstonesGuide.Jido, "order-1")
{:ok, server} = Jido.activate_agent(TombstonesGuide.Jido, ref, Order)
:ok = Server.await_ready(server)

{:error, :agent_running} = Jido.delete_agent(TombstonesGuide.Jido, ref, Order)

:ok = Jido.stop_agent_ref(TombstonesGuide.Jido, ref)
:ok = Jido.delete_agent(TombstonesGuide.Jido, ref, Order)

{:error, :deleted} = Jido.Persistence.load_agent(TombstonesGuide.Jido, Order, "order-1")
```

The `:persistence` option selects another adapter. The Ref supplies the namespace and partition.

Deleting again returns `:ok`. Deleting an ID that never had a record also returns `:ok` and writes a tombstone at revision zero, so you can reserve an ID against later creation.

```elixir
alias TombstonesGuide.Order

:ok = Jido.delete_agent(TombstonesGuide.Jido, ref, Order)

{:ok, unused} = Jido.agent_ref(TombstonesGuide.Jido, "order-never-created")
:ok = Jido.delete_agent(TombstonesGuide.Jido, unused, Order)
{:error, :deleted} = Jido.Persistence.load_agent(TombstonesGuide.Jido, Order, "order-never-created")
```

## See what a tombstone blocks

| Operation | Result on a tombstone |
| --- | --- |
| `Jido.Persistence.load_agent/4` and `Jido.Persistence.load_agent_with_revision/4` | `{:error, :deleted}` |
| `Jido.Persistence.save_agent/3`, at any revision | `{:error, :conflict}` |
| `Jido.Persistence.upgrade_agent/5` | `{:error, :deleted}` |
| `Jido.thaw/4` and `Jido.activate_agent/4` | Activation stops with `{:shutdown, :deleted}` |
| `Jido.start_agent_ref/4` with persistence | Activation stops with `{:shutdown, :conflict}` |

The last two rows return from the start call first. Wait with `Jido.AgentServer.await_ready/2` to see the reason. A fast failure can also make the start return `{:error, :worker_unavailable}`, or make the wait exit with `:noproc`. Read the record to get a stable answer.

```elixir
alias Jido.AgentServer, as: Server
alias TombstonesGuide.Order

late_order = Order.instantiate!(id: "order-1")

{:error, :conflict} =
  Jido.Persistence.save_agent(TombstonesGuide.Jido, late_order, revision: 99)

outcome =
  case Jido.activate_agent(TombstonesGuide.Jido, ref, Order) do
    {:ok, pid} ->
      try do
        Server.await_ready(pid)
      catch
        :exit, {reason, _call} -> {:stopped, reason}
      end

    {:error, reason} ->
      {:error, reason}
  end

true = outcome != :ok
nil = Jido.whereis_agent(TombstonesGuide.Jido, "order-1")
```

A tombstone is checked against the Agent module too. Deleting with a different module returns `{:error, {:invalid_persistence_record, :agent_module}}`.

## Use a new ID for a new lifetime

There is no undelete and no public way to reuse a deleted ID. Treat an ID as one Agent lifetime. If the same business object can return, add a generation to the ID, such as `"order-1/2"`, or keep the old ID retired and save the new ID in your own data.

## Delete directly with Persistence

`Jido.Persistence.delete_agent/4` writes the same tombstone, but it does not check for a live server. It takes `:instance`, `:namespace`, and `:partition`. Use it for a store you administer from a script, when no activation can be running.

If a server is running, the delete succeeds and the server finds out at its next commit. That commit conflicts, its caller gets an error, and the activation stops. Work that finished before that commit may already have run. Prefer `Jido.delete_agent/4`, which checks the local node for this reason. It cannot see a server on another node.

## Know what deletion leaves behind

Deletion changes one record. It leaves other data in place, so plan for each item.

- **Tombstones.** They stay forever, as nothing expires them. Each adapter's `delete/2` callback removes bytes for explicit maintenance, but Jido has no public function for this. Removing a tombstone also removes its protection, so a delayed writer or an activation could recreate the Agent.
- **Topology members.** Deleting a root does not delete its members' records. See [Durable Topology](durable-topology.md).
- **Flow graphs of a pending Turn.** Deletion is allowed while the record has a nonterminal durable Turn, and it does not remove that Turn's `jido:execution:` keys. Jido removes these keys when a Turn ends. To avoid orphaned keys, finish or cancel the Turn before you delete the Agent.
- **Your domain data.** The tombstone replaces saved state in the current record. Signals already delivered, audit records, external systems, and store backups are outside that record, so a tombstone alone is not an erasure guarantee.

```elixir
:ok = Jido.stop(TombstonesGuide.Jido)
```

## Next steps

- [Revisions and Conflicts](durable-revisions-and-conflicts.md) explains how the tombstone keeps the write barrier.
- [Durable Agent Activation](durable-agent-activation.livemd) shows which start functions refuse a tombstone.
