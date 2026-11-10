# Storage Model

This guide explains what Jido writes to storage, which layer owns each part, and what each write result means. Read it before you choose an adapter or write your own.

Jido persistence stores versioned checkpoints of one Agent. It is not an event journal. Each save replaces the previous record for that Agent.

## Three layers

| Layer | Owns | Does not own |
| --- | --- | --- |
| `Jido.Persistence` | Durable identity, record contents, revisions, tombstones, restore checks | Bytes on disk or in a service |
| `Jido.Persistence.Store` | The byte contract: read a value, write it only if a condition still holds, classify the result | Keys, record formats, revisions |
| An adapter such as `Jido.Persistence.ETS` | Storing binary keys and values atomically | What the bytes mean |

Adapters see opaque binaries. This is why one adapter works for Agent records and for Flow execution records. See [Continuation Storage](flow-continuations.md) for the second kind.

The examples below use this Agent and the in-memory ETS adapter:

```elixir
defmodule StorageModelGuide.ApplyPayment do
  use Jido.Action,
    name: "storage_model_guide_apply_payment",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl true
  def run(%{cents: cents}, %{agent_state: state}),
    do: {:ok, %{state | paid_cents: state.paid_cents + cents}}
end

defmodule StorageModelGuide.Invoice do
  use Jido.Agent, name: "storage_model_guide_invoice"

  state do
    schema Jido.Joi.object(%{
             paid_cents: Jido.Joi.integer() |> Jido.Joi.default(0),
             note: Jido.Joi.any() |> Jido.Joi.default(nil)
           })
  end

  routes do
    route "invoice.pay", StorageModelGuide.ApplyPayment
  end
end

store = {Jido.Persistence.ETS, table: :storage_model_guide}
invoice = StorageModelGuide.Invoice.instantiate!(id: "inv-1001")

:ok = Jido.Persistence.save_agent(store, invoice, namespace: "billing")
```

## Identity

One record belongs to one exact `{namespace, partition, id}` key. The partition defaults to `nil`.

```elixir
{:ok, %{id: "inv-1001"}} = Jido.Persistence.load_agent(store, StorageModelGuide.Invoice, "inv-1001", namespace: "billing")

{:error, :not_found} = Jido.Persistence.load_agent(store, StorageModelGuide.Invoice, "inv-1001", namespace: "archive")

{:error, :not_found} =
  Jido.Persistence.load_agent(store, StorageModelGuide.Invoice, "inv-1001", namespace: "billing", partition: "eu")

{:error, :stable_namespace_required} = Jido.Persistence.load_agent(store, StorageModelGuide.Invoice, "inv-1001")
```

Pass `:namespace` directly, or pass `:instance` with a running Jido instance that has a namespace. The instance name and the Agent module are not part of the key, so renaming an instance keeps its records. The module is still checked: a record saved by one Agent module does not load under another. See [Instances and Tenants](../operations/configuration-and-tenant-isolation.md) for how to choose namespaces.

## What a record holds

An encoded record is one Erlang term, written with `:erlang.term_to_binary/1` and read with the `:safe` option. An active record has these fields:

| Field | Meaning |
| --- | --- |
| `fmt` | Record format. Jido reads and writes format `1` only |
| `kind` | `:active` or `:tombstone` |
| `namespace`, `partition`, `agent_id` | The durable identity, checked on every read |
| `agent_module` | The module that saved the Agent |
| `vsn` | The saved Agent's version |
| `rev` | The record revision |
| `checkpoint` | The complete Agent snapshot |
| `server_turn` | Optional. The saved Flow Turn receipt, owned by `Jido.AgentServer` |

A tombstone has the same fields except `vsn`, `checkpoint`, and `server_turn`. Treat the bytes as private to Jido: read records through `Jido.Persistence`, not by decoding them in application code. A record with an extra or missing field fails validation with `{:error, {:invalid_persistence_record, :shape}}`.

## What a checkpoint holds

The checkpoint holds the whole Agent, including its definition. `Jido.Persistence.snapshot/2` returns the same form without writing to storage:

```elixir
{:ok, snapshot} = Jido.Persistence.snapshot(invoice)

[:agent, :format, :references, :state_format] = snapshot |> Map.keys() |> Enum.sort()
1 = snapshot.format
:default = snapshot.state_format
%{StorageModelGuide.ApplyPayment => <<_digest::binary-size(16)>>} = snapshot.references
```

- `agent` is the complete Agent: routes, schema, Plugins, topology, and state.
- `references` maps each executable module to the 16-byte digest of its compiled code.
- `state_format` is `:custom` when the Agent writes its own payload with the `checkpoint/2` callback of `Jido.Agent`.

Restore uses the saved definition and does not read the source definition, so a new default in source code does not change a saved Agent. A snapshot stores references to code, not the code itself. If a referenced module changed, restore fails until an explicit upgrade runs:

```elixir
stale = put_in(snapshot.references[StorageModelGuide.ApplyPayment], <<0::128>>)

{:error, %Jido.Error.ValidationError{code: :changed_reference}} = Jido.Persistence.restore(stale)
```

[Checkpoints and Upgrades](../durability/checkpoints-and-data-upgrades.md) covers `Jido.Persistence.upgrade/3` and `Jido.Persistence.upgrade_agent/5`.

Three things are not in a checkpoint:

- Caller execution context. A pending Flow keeps its portable context in the Turn receipt instead.
- Live processes, timers, and attachments.
- Child Agent state. Each child has its own record, so saving a parent is not an atomic save of the family.

## Portable values

Everything in a record must be portable data. Jido rejects processes, ports, references, functions, improper lists, and other local runtime values before any write, and reports the path to the value:

```elixir
waiting = StorageModelGuide.Invoice.instantiate!(id: "inv-1002", state: %{note: %{owner: self()}})

{:error, %Jido.Error.ValidationError{code: :non_portable_term, path: path}} =
  Jido.Persistence.save_agent(store, waiting, namespace: "billing")

[:snapshot, :agent, :state, :note, :owner] = path
```

See [Portable Values](../data/portable-values-and-references.md) for the full rule. A [Plugin](../plugins/plugin-persistence.md) can convert its own state value into a portable form with `dump/3` and `load/3`.

## Revisions

The `rev` field orders saves of one record. `Jido.AgentServer` manages it for you: it writes revision zero before a new persistent Agent reports ready, and each successful Turn writes the next revision. A direct call to `Jido.Persistence.save_agent/3` uses the options you pass.

`:revision` defaults to `0`. A stored revision cannot decrease, and changed state needs a greater revision. `:expected_revision` rejects a write based on a stale read, even when its proposed revision is greater.

```elixir
paid = %{invoice | state: %{invoice.state | paid_cents: 500}}

{:error, :conflict} = Jido.Persistence.save_agent(store, paid, namespace: "billing")

:ok = Jido.Persistence.save_agent(store, paid, namespace: "billing", revision: 1, expected_revision: 0)

{:error, :conflict} =
  Jido.Persistence.save_agent(store, paid, namespace: "billing", revision: 2, expected_revision: 0)

{:ok, %{state: %{paid_cents: 500}}, 1} =
  Jido.Persistence.load_agent_with_revision(store, StorageModelGuide.Invoice, "inv-1001", namespace: "billing")
```

Saving the identical record at the same revision succeeds, so a retry of a confirmed write does no harm. A revision check is not a writer lease. It rejects a stale write, but it does not stop two nodes from running the same Agent. See [Revisions and Conflicts](../durability/durable-revisions-and-conflicts.md).

## Tombstones

`Jido.Persistence.delete_agent/4` does not remove the key. It writes a compact tombstone that keeps the last revision, so a delayed writer cannot bring the record back.

```elixir
:ok = Jido.Persistence.delete_agent(store, StorageModelGuide.Invoice, "inv-1001", namespace: "billing")

{:error, :deleted} = Jido.Persistence.load_agent(store, StorageModelGuide.Invoice, "inv-1001", namespace: "billing")

{:error, :conflict} =
  Jido.Persistence.save_agent(store, paid, namespace: "billing", revision: 99)
```

[Deletion and Tombstones](../durability/deletion-and-tombstones.md) covers the rules around live Agents.

## Conditions and write results

A read returns the value and a condition for the next write. The condition is one of three forms:

| Condition | Meaning |
| --- | --- |
| `:not_found` | The key must be absent |
| The exact bytes | The stored value must still equal these bytes |
| `{:token, token}` | An opaque adapter token, such as a version or ETag, must still match |

`Jido.Persistence.Store.compare_and_swap/4` never splits a write into a separate read and put. It returns one of four results:

| Result | Did the write happen? | What to do |
| --- | --- | --- |
| `:ok` | Yes | Continue |
| `{:error, :conflict}` | No | Reload, then decide again |
| `{:error, {:rejected, reason}}` | No. The adapter finished a check before the write started | Fix the cause. For example, the value is too large |
| `{:error, {:indeterminate, reason}}` or `{:error, :indeterminate}` | Unknown | Do not retry blindly. Read first, then make a domain decision |

Any other adapter error, a raise, or an invalid reply counts as indeterminate. `Jido.AgentServer` stops an activation after an uncertain write, so a new activation reads the stored truth before more work starts. See [Recovery Limits](../durability/recovery-and-effect-limits.md).

## Other record families

Flow Turns write more than the Agent record. Acceptance and completion use Agent record revisions, and step progress uses separate keys in the same store. All of these use the byte contract above, so an adapter needs no extra support. [Continuation Storage](flow-continuations.md) lists them.

## Telemetry

`Jido.Persistence` emits `[:jido, :persistence, :operation, :start | :stop]`. Its metadata includes `operation`, `agent_id`, `agent_module`, `agent_namespace`, `adapter_module`, and `persistence_reason`. Its stop measurements include `revision_after` on a successful write or load.

`Jido.Persistence.Store` emits `[:jido, :persistence, :store, :start | :stop]` with `operation`, `adapter_module`, and `status`. It does not report keys, values, tokens, or adapter options.

## Related

- [Persistence Adapters](persistence-adapters.livemd): configure and swap a store.
- [Custom Adapters](custom-persistence-adapter.md): implement the byte contract.
- [Durability Model](../durability/durability-model.md): how the runtime uses this storage.
