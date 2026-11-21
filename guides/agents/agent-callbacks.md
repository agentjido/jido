# Agent Callbacks

An Agent module can define three optional callbacks. This reference states when each one runs, what it receives, and what it can return.

| Callback | Runs when | Must return |
| --- | --- | --- |
| `c:Jido.Agent.initialize/2` | A new instance is created | `{:ok, state}` or `{:error, reason}` |
| `c:Jido.Agent.checkpoint/2` | A snapshot captures the Agent | `{:ok, map}` or `{:error, reason}` |
| `c:Jido.Agent.restore/2` | A custom snapshot is restored | `{:ok, instance}` or `{:error, reason}` |

`use Jido.Agent` declares the behaviour, so mark each one with `@impl Jido.Agent`. A callback belongs to a module. A Map definition without `:module` has none.

## initialize/2

`initialize/2` transforms the candidate state for a new instance. Use it for values that depend on the instance, such as a key derived from its `id`.

`Jido.Agent.instantiate/2` calls it after merging explicit `:state` over `initial_state`, and before the schema adds defaults and validates. So the callback sees a partial candidate that can hold keys the schema does not allow, and it must return a Map that the schema will accept.

The second argument is a Map owned by Jido:

| Key | Value |
| --- | --- |
| `:id` | The new instance ID |
| `:parent_id` | The parent Agent ID, or `nil` |
| `:member` | The topology member name, or `nil` |
| `:slot` | The member slot, or `nil` |

```elixir
defmodule CallbackGuide.InvoiceAgent do
  use Jido.Agent, name: "invoice"

  state do
    schema Jido.Joi.object(%{
             number: Jido.Joi.string(),
             total_cents: Jido.Joi.integer(),
             currency: Jido.Joi.string() |> Jido.Joi.default("USD")
           })

    initial_state %{total_cents: 0, draft_note: "seed"}
  end

  @impl Jido.Agent
  def initialize(%{total_cents: total}, _context) when total < 0, do: {:error, :negative_total}

  def initialize(state, %{id: id}) do
    {:ok,
     state
     |> Map.delete(:draft_note)
     |> Map.put(:number, "INV-" <> String.upcase(id))}
  end
end

invoice = CallbackGuide.InvoiceAgent.instantiate!(id: "a1", state: %{total_cents: 900})

%{number: "INV-A1", total_cents: 900, currency: "USD"} = invoice.state
```

An `{:error, reason}` result stops creation. A reason that is not an exception becomes a `Jido.Error.ValidationError` with code `:initialize_failed`.

```elixir
{:error, %Jido.Error.ValidationError{code: :initialize_failed, details: %{reason: :negative_total}}} =
  CallbackGuide.InvoiceAgent.instantiate(id: "a2", state: %{total_cents: -1})
```

An exception reason returns as it is. A raise, throw, or exit in the callback returns a `Jido.Error.ExecutionError` with `details.code` of `:agent_callback_failed`. Any other return value is `:initialize_failed`.

`Jido.Agent.validate/1` does not run `initialize/2`, and neither does a default restore. Keep the callback free of side effects, because instance construction is plain data work and starts no process.

## checkpoint/2

`checkpoint/2` writes a custom portable payload for the Agent's state. Define it when the saved form must differ from the live state, for example to drop derived data.

It receives the instance and the `:context` option given to `Jido.Persistence.snapshot/2`. It must return a plain Map. Without this callback, Jido saves the state in its default format.

## restore/2

`restore/2` receives the saved payload and the `:context` option given to `Jido.Persistence.restore/2`, and returns an instance. It must keep the saved `id`. Define `checkpoint/2` and `restore/2` together, since a custom payload has no default reader.

```elixir
defmodule CallbackGuide.CartAgent do
  use Jido.Agent, name: "cart"

  state do
    schema Jido.Joi.object(%{
             items: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([]),
             item_count: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  @impl Jido.Agent
  def checkpoint(agent, context) do
    {:ok, %{id: agent.id, items: agent.state.items, saved_by: context.saved_by}}
  end

  @impl Jido.Agent
  def restore(%{id: id, items: items}, _context) do
    instantiate(id: id, state: %{items: items, item_count: length(items)})
  end
end

cart = CallbackGuide.CartAgent.instantiate!(id: "cart-1", state: %{items: ["sku-1", "sku-2"], item_count: 2})

{:ok, snapshot} = Jido.Persistence.snapshot(cart, context: %{saved_by: "nightly"})
:custom = snapshot.state_format
%{id: "cart-1", items: ["sku-1", "sku-2"], saved_by: "nightly"} = snapshot.agent.state

{:ok, restored} = Jido.Persistence.restore(snapshot)
%{item_count: 2} = restored.state
```

Jido keeps only the state from the result and validates it with the saved definition. A `checkpoint/2` result that is not `{:ok, map}` or `{:error, reason}`, or a `restore/2` that changes the `id`, fails with `:invalid_snapshot_state`.

A `restore/2` that calls `instantiate/1` also runs `initialize/2`, because `instantiate/1` always does. Write `initialize/2` to accept restored state in that case.

## Related

- [Agent State and Schemas](agent-state-and-schemas.md) covers the steps around `initialize/2`.
- Checkpoints and Upgrades covers saved data and version changes.
- Plugin Persistence covers Plugin-owned state in snapshots.
