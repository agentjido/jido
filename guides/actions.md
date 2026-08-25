# Actions

<!-- covers: jido.agents_and_actions.action_execution_surface -->

**After:** You can implement an Action module that transforms state and returns directives.

Jido keeps agent decision logic pure. Actions may be pure or effectful.
Directives are for effects you want the runtime to own.

## The Complete Picture

An action receives validated params and context, then returns state updates and
optional directives. Actions may perform side effects such as API calls, file
I/O, or database queries when they need the result to continue reasoning or
update state:

```elixir
defmodule MyApp.Actions.CreateOrder do
  use Jido.Action,
    name: "create_order",
    description: "Creates an order and emits a domain event",
    schema:
      Zoi.object(%{
        order_id: Zoi.string(),
        items: Zoi.list(Zoi.map()) |> Zoi.default([]),
        total: Zoi.integer()
      })

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

## Effect Boundary

Use this rule when deciding between action code and a directive:

- If the step needs a result back now to continue reasoning or update state, keep
  the work in the action.
- If the workflow has already decided on an outbound effect and wants the
  runtime or integration layer to own delivery, return a directive.

For example, an action can call an API and use the response to update state. If
the action only needs to announce that an order was created, return an
`%Jido.Agent.Directive.Emit{}` and let the runtime dispatch the signal.

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
    schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

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

Use map-shaped Zoi schemas for code that must work with both supported
`jido_action` versions. Object fields are required by default.

```elixir
use Jido.Action,
  name: "process_order",
  description: "Processes an order with validation",
  schema:
    Zoi.object(%{
      order_id: Zoi.string(),
      amount: Zoi.integer() |> Zoi.default(1),
      priority: Zoi.enum([:low, :medium, :high]) |> Zoi.default(:medium),
      metadata: Zoi.map() |> Zoi.default(%{}),
      tags: Zoi.list(Zoi.string()) |> Zoi.default([])
    })
```

Common schema operations:

- `Zoi.string()`, `Zoi.integer()`, `Zoi.atom()`, `Zoi.map()`, and `Zoi.any()` define field types.
- `Zoi.list(schema)` defines a list of values.
- `Zoi.enum(values)` restricts a field to a fixed set of values.
- `Zoi.default(schema, value)` supplies a value when the field is missing.
- `Zoi.optional(schema)` makes a field optional.
- The `description:` option documents a field.

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
- [`jido_action` Version Compatibility](jido-action-compatibility.md) — Version 2 default and version 3 opt-in
- [Directives Guide](directives.md) — Complete directive reference
- [Signals Guide](signals.md) — Signal routing and dispatch
