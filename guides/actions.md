# Actions

**After:** You can implement an Action module that transforms state and returns directives.

## The Complete Picture

An action receives validated params and context, then returns state updates and optional directives. Actions may perform side effects (API calls, file I/O, database queries):

```elixir
defmodule MyApp.Actions.CreateOrder do
  use Jido.Action,
    name: "create_order",
    description: "Creates an order and emits a domain event",
    schema: [
      order_id: [type: :string, required: true],
      items: [type: {:list, :map}, default: []],
      total: [type: :integer, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(params, context) do
    orders = Map.get(context.state, :orders, [])

    order = %{
      id: params.order_id,
      items: params.items,
      total: params.total,
      status: :pending,
      created_at: DateTime.utc_now()
    }

    signal = Signal.new!(
      "order.created",
      %{order_id: order.id, total: order.total},
      source: "/order-agent"
    )

    {:ok, %{orders: [order | orders], last_order_id: order.id},
     %Directive.Emit{signal: signal}}
  end
end
```

## The run/2 Contract

Every action implements `run/2`:

```elixir
def run(params, context) do
  # params: validated map matching your schema
  # context: map with :state (current agent state)
  
  {:ok, state_updates}
end
```

**`params`** is a map with your validated, coerced schema fields. Missing optional fields get their defaults:

```elixir
def run(%{amount: amount}, context) do
  # amount is guaranteed to be an integer (from schema)
end
```

**`context`** is a map containing:

| Key | Value |
|-----|-------|
| `:state` | Current agent state as a map |
| `:agent` | The agent struct (when running via `emit_to_parent`) |

## Return Shapes

Actions return one of three shapes:

### State updates only

```elixir
def run(%{amount: amount}, context) do
  current = Map.get(context.state, :counter, 0)
  {:ok, %{counter: current + amount}}
end
```

The returned map is deep-merged into agent state.

### State updates with directives

```elixir
def run(params, context) do
  signal = Signal.new!("task.completed", %{id: params.id}, source: "/worker")
  
  {:ok, %{status: :done}, %Directive.Emit{signal: signal}}
end
```

Return a single directive or a list:

```elixir
{:ok, %{triggered: true}, [
  Directive.emit(%{type: "event.1"}),
  Directive.schedule(1000, :check)
]}
```

### Errors

```elixir
def run(%{file_path: path}, _context) do
  case File.read(path) do
    {:ok, content} -> {:ok, %{content: content}}
    {:error, reason} -> {:error, "Failed to read file: #{inspect(reason)}"}
  end
end
```

## Accessing State

Read current agent state from `context.state`:

```elixir
defmodule IncrementAction do
  use Jido.Action,
    name: "increment",
    schema: [amount: [type: :integer, default: 1]]

  def run(%{amount: amount}, context) do
    current = Map.get(context.state, :counter, 0)
    {:ok, %{counter: current + amount}}
  end
end
```

Pattern matching works too:

```elixir
def run(%{amount: amount}, %{state: %{counter: current}}) do
  {:ok, %{counter: current + amount}}
end
```

## Emitting Directives

Import the Directive module and return directive structs:

```elixir
alias Jido.Agent.Directive

# Emit a signal
{:ok, state, %Directive.Emit{signal: my_signal}}

# Schedule a delayed message
{:ok, state, %Directive.Schedule{delay_ms: 5000, message: :timeout}}

# Spawn a child agent
{:ok, state, Directive.spawn_agent(WorkerAgent, :worker_1)}

# Multiple directives
{:ok, state, [
  %Directive.Emit{signal: signal},
  %Directive.Schedule{delay_ms: 1000, message: :check}
]}
```

### Common directive helpers

```elixir
alias Jido.Agent.Directive

Directive.emit(signal)                           # Emit via default dispatch
Directive.emit_to_pid(signal, pid)              # Emit to specific process
Directive.emit_to_parent(agent, signal)         # Child → parent communication
Directive.spawn_agent(Module, :tag)              # Spawn child agent
Directive.stop_child(:tag, :normal)              # Stop tracked child
Directive.schedule(delay_ms, message)            # Delayed message
Directive.stop(:normal)                          # Stop self
```

## State Scope

**Agent state** (`context.state`) is the agent's root state map defined by its schema:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    schema: [
      counter: [type: :integer, default: 0],
      orders: [type: {:list, :map}, default: []]
    ]
end

# context.state = %{counter: 0, orders: []}
```

**State updates** from actions are deep-merged into agent state:

```elixir
# If agent state is %{counter: 5, name: "test"}
# And action returns {:ok, %{counter: 10}}
# Result: %{counter: 10, name: "test"}
```

**Plugin state** (if using plugins) lives under a namespaced key:

```elixir
# Agent with :chat plugin mounted
# agent.state = %{counter: 0, chat: %{history: []}}
```

Actions updating plugin state should target the plugin's key:

```elixir
{:ok, %{chat: %{history: updated_history}}}
```

### StateOps for complex updates

For operations beyond simple merge, return StateOp structs:

```elixir
alias Jido.Agent.StateOp

# Deep merge (default behavior)
{:ok, %{}, %StateOp.SetState{attrs: %{metadata: %{key: "value"}}}}

# Replace entire state
{:ok, %{}, %StateOp.ReplaceState{state: %{fresh: true}}}

# Delete top-level keys
{:ok, %{}, %StateOp.DeleteKeys{keys: [:temp, :cache]}}

# Set nested path
{:ok, %{}, %StateOp.SetPath{path: [:nested, :deep, :value], value: 42}}

# Delete nested path
{:ok, %{}, %StateOp.DeletePath{path: [:nested, :to_remove]}}
```

## Schema Definition

Schemas use NimbleOptions syntax:

```elixir
use Jido.Action,
  name: "process_order",
  description: "Processes an order with validation",
  schema: [
    order_id: [type: :string, required: true],
    amount: [type: :integer, default: 1],
    priority: [type: {:in, [:low, :medium, :high]}, default: :medium],
    metadata: [type: :map, default: %{}],
    tags: [type: {:list, :string}, default: []]
  ]
```

Common schema options:
- `type:` - `:string`, `:integer`, `:atom`, `:map`, `{:list, :type}`, `{:in, values}`
- `required: true` - Validation fails if missing
- `default: value` - Used when param not provided
- `doc: "description"` - Documents the parameter

## Invoking Actions

From `cmd/2`:

```elixir
# Module only (uses defaults)
{agent, directives} = MyAgent.cmd(agent, IncrementAction)

# Module with params
{agent, directives} = MyAgent.cmd(agent, {IncrementAction, %{amount: 5}})

# Multiple actions
{agent, directives} = MyAgent.cmd(agent, [
  {IncrementAction, %{amount: 10}},
  {DecrementAction, %{amount: 3}}
])
```

## Further Reading

- [jido_action HexDocs](https://hexdocs.pm/jido_action) — Full schema options, validation details, composition patterns
- [Directives Guide](directives.md) — Complete directive reference
- [Signals Guide](signals.md) — Signal routing and dispatch
