# Plugin Persistence

A Plugin's owned field is saved with the rest of Agent state. Define `dump/3` and `load/3` when the stored form must differ from the live form. This guide shows the conversion, when it runs, and how it fails.

Without these callbacks, Jido stores the field's value as it is. The field must then hold portable data, as the rest of Agent state does. See [Storage Model](../storage/persistence-storage-model.md) for the record format.

## Convert the owned value

The two callbacks come as a pair, and they require `state_spec/1`. Each one handles only the Plugin's own value. Neither one receives an adapter, a record key, a revision, the complete Agent, or a process.

This Plugin keeps recent order ids as a list in memory and stores them as one compact string:

```elixir
defmodule PluginPersistenceGuide.RecentOrders do
  use Jido.Plugin

  alias Jido.Plugin.Context.Persistence, as: PersistenceContext

  @impl true
  def state_spec(_opts), do: {:recent_orders, Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])}

  @impl true
  def reduce(reduction, _opts) do
    case reduction.signal do
      %{type: "order.record", data: %{id: id}} -> {:ok, Enum.take([id | reduction.plugin_state], 100)}
      _other -> {:ok, reduction.plugin_state}
    end
  end

  @impl true
  def dump(ids, %PersistenceContext{direction: :dump}, _opts), do: {:ok, Enum.join(ids, ",")}

  @impl true
  def load(stored, %PersistenceContext{direction: :load}, _opts) when is_binary(stored) do
    {:ok, String.split(stored, ",", trim: true)}
  end

  def load(_stored, %PersistenceContext{}, _opts), do: {:error, :invalid_recent_orders}
end

defmodule PluginPersistenceGuide.Customer do
  use Jido.Agent, name: "customer", plugins: [PluginPersistenceGuide.RecentOrders]

  state do
    schema Jido.Joi.object(%{orders: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/shop/customer"

    route "order.record", as: :record do
      action %{id: _id},
        schema: Jido.Joi.object(%{id: Jido.Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | orders: context.agent_state.orders + 1}}
      end
    end
  end
end

customer = PluginPersistenceGuide.Customer.instantiate!(id: "c-1", state: %{recent_orders: ["o-2", "o-1"]})

{:ok, snapshot} = Jido.Persistence.snapshot(customer)
%{orders: 0, recent_orders: "o-2,o-1"} = snapshot.agent.state

{:ok, restored} = Jido.Persistence.restore(snapshot)
["o-2", "o-1"] = restored.state.recent_orders
```

`Jido.Persistence.snapshot/2` and `Jido.Persistence.restore/2` work without storage, which makes them a direct way to test the conversion.

## Conversion context

Each callback receives a `Jido.Plugin.Context.Persistence`:

| Field | Value |
|---|---|
| `:plugin` | The Plugin module. |
| `:plugin_vsn` | The current version from `use Jido.Plugin`. |
| `:record_format` | The persistence record format, a positive integer. |
| `:direction` | `:dump` or `:load`. |
| `:reason` | Why the conversion runs: `:snapshot`, `:manual`, `:restore`, `:stored_upgrade`, or, in an AgentServer, `:activate`, `:commit`, or `:hibernate`. |

`:plugin_vsn` is the version of the code that is running, not the version that stored the value. To tell old stored forms apart, put a marker in the stored value.

## When conversion runs

Every path that writes or reads a checkpoint uses these callbacks:

- `Jido.Persistence.save_agent/3` and `Jido.Persistence.load_agent/4`, directly.
- `Jido.Persistence.snapshot/2` and `Jido.Persistence.restore/2`.
- An AgentServer started with `persistence:`, which runs `dump/3` before each commit that it saves.
- `Jido.thaw/4` and a start with `persistence_mode: :restore`, which run `load/3` before the Plugin's runtime starts.

Here the Plugin runs live with a local store. The converted value reaches storage, and the thawed server sees the live form again:

```elixir
{:ok, _instance} = Jido.start(name: PluginPersistenceGuide.Jido, namespace: "plugin-persistence-guide")
store = {Jido.Persistence.ETS, table: :plugin_persistence_guide}

{:ok, server} =
  Jido.start_agent(PluginPersistenceGuide.Jido, PluginPersistenceGuide.Customer, id: "c-live", persistence: store)

:ok = Jido.AgentServer.await_ready(server)

{:ok, _agent, []} =
  Jido.AgentServer.call(server, PluginPersistenceGuide.Customer.record_signal!(%{id: "o-9"}))

:ok = Jido.AgentServer.quiesce(server)
:ok = Jido.AgentServer.hibernate(server)

{:ok, thawed} =
  Jido.thaw(PluginPersistenceGuide.Jido, PluginPersistenceGuide.Customer, "c-live", persistence: store)

:ok = Jido.AgentServer.await_ready(thawed)
%{orders: 1, recent_orders: ["o-9"]} = Jido.AgentServer.agent(thawed).state
:ok = Jido.stop_agent(PluginPersistenceGuide.Jido, thawed)
```

Thawing does not call `after_commit/3`. See [Hibernate and Thaw](../agent-servers/hibernate-thaw-and-activate.md).

## Failures

Jido checks both directions:

| Problem | Result |
|---|---|
| `dump/3` or `load/3` returns `{:error, reason}` | The call returns that error. |
| `dump/3` returns a value that is not portable, or `load/3` receives one | Error with `details.code` set to `:non_portable_term`. |
| `load/3` returns a value that fails the state schema | Error with message `"Persistence Plugin loaded invalid owned state"`. |
| A callback raises or returns another shape | `Jido.Error.ExecutionError` that names the Plugin. |
| The stored record lacks the Plugin's field | `{:error, {:invalid_persistence_record, :plugin_state}}`. |

```elixir
damaged = put_in(snapshot.agent.state.recent_orders, 42)
{:error, :invalid_recent_orders} = Jido.Persistence.restore(damaged)

missing = update_in(snapshot.agent.state, &Map.delete(&1, :recent_orders))
{:error, {:invalid_persistence_record, :plugin_state}} = Jido.Persistence.restore(missing)
```

A failed load keeps the Agent from starting. It does not fall back to the default value.

On a live server with `persistence:`, a failed `dump/3` fails the save of that commit. The caller receives an error with the message `"Required durable commit failed"`, and the Activation stops. Treat `dump/3` as total for every value that your schema allows.

## Change a Plugin that has stored data

A stored record holds the Agent's Plugin declarations and code references. After a Plugin module changes, loading an older record returns an error with code `:changed_reference` until an explicit upgrade runs. [Checkpoints and Upgrades](../durability/checkpoints-and-data-upgrades.md) covers that path. Replace Plugin options or state shape through a complete Agent definition upgrade.

## Next steps

- [Make an Agent Durable](../durability/make-an-agent-durable.livemd) configures persistence for an Agent.
- [Persistence Adapters](../storage/persistence-adapters.livemd) lists the supported stores.
