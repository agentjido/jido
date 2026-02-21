# Ash Framework Integration

**After:** You can trigger Jido agents from Ash actions and resources.

The [`ash_jido`](https://github.com/agentjido/ash_jido) package bridges Ash Framework resources with Jido agents. It generates `Jido.Action` modules from Ash actions at compile time.

## Installation

Add `ash_jido` to your dependencies:

```elixir
# mix.exs
def deps do
  [
    {:ash, "~> 3.12"},
    {:jido, "~> 1.1"},
    {:ash_jido, "~> 0.1"}
  ]
end
```

Or use Igniter:

```bash
mix igniter.install ash_jido
```

## Basic Usage

Add the `AshJido` extension to your Ash resource and declare which actions to expose:

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    domain: MyApp.Shop,
    extensions: [AshJido]

  attributes do
    uuid_primary_key :id
    attribute :status, :atom, default: :pending
    attribute :total, :decimal
    timestamps()
  end

  actions do
    create :place
    read :by_id, get_by: [:id]
    update :confirm
    update :ship
  end

  jido do
    action :place, name: "create_order"
    action :by_id, name: "get_order"
    action :confirm
    action :ship
  end
end
```

This generates Jido actions you can call directly:

```elixir
# Create an order via the generated action
{:ok, order} = MyApp.Order.Jido.Place.run(
  %{total: Decimal.new("99.99")},
  %{domain: MyApp.Shop}
)

# Update an order
{:ok, updated} = MyApp.Order.Jido.Confirm.run(
  %{id: order.id},
  %{domain: MyApp.Shop, actor: current_user}
)
```

## Using Generated Actions in Agents

Wire Ash-generated actions into your Jido agent's signal routing:

```elixir
defmodule MyApp.OrderAgent do
  use Jido.Agent,
    name: "order_processor",
    schema: [
      current_order_id: [type: {:or, [:string, nil]}, default: nil]
    ],
    signal_routes: [
      {"order.place", MyApp.Order.Jido.Place},
      {"order.confirm", MyApp.Order.Jido.Confirm},
      {"order.ship", MyApp.Order.Jido.Ship}
    ]
end
```

Send signals to trigger Ash actions:

```elixir
{:ok, _pid} = MyApp.Jido.start_agent(MyApp.OrderAgent, id: "order-agent-1")

signal = Jido.Signal.new!("order.place", %{total: "149.99"}, source: "/api")
{:ok, agent} = MyApp.Jido.call("order-agent-1", signal)
```

## Context Requirements

The Ash `domain` is **required** in the action context. Pass it via the agent's context or action params:

```elixir
context = %{
  domain: MyApp.Shop,      # Required
  actor: current_user,     # Optional: for authorization
  tenant: "org_123"        # Optional: for multi-tenancy
}

MyApp.Order.Jido.Place.run(%{total: "50.00"}, context)
```

## Triggering Agents from Ash Changes

Use Ash changes to emit Jido signals when resources change:

```elixir
defmodule MyApp.Changes.NotifyAgent do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      signal = Jido.Signal.new!(
        "order.created",
        %{order_id: record.id, total: record.total},
        source: "/ash"
      )

      case MyApp.Jido.whereis("fulfillment-agent") do
        nil -> :ok
        pid -> Jido.AgentServer.cast(pid, signal)
      end

      {:ok, record}
    end)
  end
end
```

Attach to your action:

```elixir
actions do
  create :place do
    change MyApp.Changes.NotifyAgent
  end
end
```

## Complete Example: Order Workflow

A complete example showing an Ash resource that triggers a Jido agent workflow.

### The Ash Resource

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    domain: MyApp.Shop,
    extensions: [AshJido]

  attributes do
    uuid_primary_key :id
    attribute :customer_email, :string, allow_nil?: false
    attribute :items, {:array, :map}, default: []
    attribute :status, :atom, default: :pending
    attribute :total, :decimal
    timestamps()
  end

  actions do
    create :place do
      accept [:customer_email, :items, :total]
      change MyApp.Changes.StartFulfillment
    end

    update :confirm do
      change set_attribute(:status, :confirmed)
    end

    update :ship do
      change set_attribute(:status, :shipped)
    end
  end

  jido do
    action :place
    action :confirm
    action :ship
  end
end
```

### The Change That Triggers an Agent

```elixir
defmodule MyApp.Changes.StartFulfillment do
  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, order ->
      # Start a fulfillment agent for this order
      {:ok, _pid} = MyApp.Jido.start_agent(
        MyApp.FulfillmentAgent,
        id: "fulfillment-#{order.id}",
        state: %{order_id: order.id, customer_email: order.customer_email}
      )

      # Signal it to begin processing
      signal = Jido.Signal.new!("fulfillment.start", %{order_id: order.id}, source: "/ash")
      MyApp.Jido.cast("fulfillment-#{order.id}", signal)

      {:ok, order}
    end)
  end
end
```

### The Fulfillment Agent

```elixir
defmodule MyApp.FulfillmentAgent do
  use Jido.Agent,
    name: "fulfillment",
    schema: [
      order_id: [type: :string, required: true],
      customer_email: [type: :string, required: true],
      step: [type: :atom, default: :pending]
    ],
    signal_routes: [
      {"fulfillment.start", MyApp.Actions.BeginFulfillment},
      {"fulfillment.complete", MyApp.Actions.CompleteFulfillment}
    ]
end
```

## DSL Reference

### Individual Actions

```elixir
jido do
  action :create
  action :read, name: "list_users", description: "List all users"
  action :update, tags: ["user-management"]
  action :special, output_map?: false  # preserve Ash structs
end
```

### Bulk Exposure

```elixir
jido do
  all_actions                          # expose all
  all_actions except: [:destroy]       # exclude some
  all_actions only: [:create, :read]   # include only these
end
```

### Default Naming

| Action Type | Pattern | Example |
|-------------|---------|---------|
| `:create` | `create_<resource>` | `create_user` |
| `:read` (`:read`) | `list_<resources>` | `list_users` |
| `:read` (`:by_id`) | `get_<resource>_by_id` | `get_user_by_id` |
| `:update` | `update_<resource>` | `update_user` |
| `:destroy` | `delete_<resource>` | `delete_user` |

## Next Steps

- [ash_jido GitHub](https://github.com/agentjido/ash_jido) — full source and HexDocs
- [Getting Started Guide](https://github.com/agentjido/ash_jido/blob/main/guides/getting-started.md) — comprehensive usage
- [Interactive Demo](https://github.com/agentjido/ash_jido/blob/main/guides/ash-jido-demo.livemd) — try in Livebook
- [Signals](signals.md) — signal routing in Jido
- [Actions](actions.md) — implementing custom Jido actions
