# Migration Guide: Jido 1.x to 2.0

**After:** You can upgrade from Jido 1.x with minimal surprises.

This guide helps you migrate existing Jido applications to version 2.0. The migration can be done incrementally—start with the minimum changes to get running, then adopt new patterns as needed.

## Breaking Changes Summary

| Area | V1 | V2 | Migration Effort |
|------|----|----|------------------|
| Runtime | Global singleton | Instance-scoped supervisor | Small |
| Agent Lifecycle | `AgentServer.start/1` | `Jido.start_agent/3` | Small-Medium |
| Side Effects | Mixed in callbacks | Directive-based | Medium |
| Messaging | `Jido.Instruction` | CloudEvents Signals | Medium-Large |
| Orchestration | Runners (Simple/Chain) | Strategies + Plans | Medium |
| Actions | `Jido.Actions.*` | `Jido.Tools.*` | Small |
| Validation | NimbleOptions | Zoi schemas | Small-Medium |
| Errors | Ad hoc tuples | Splode structured errors | Small-Medium |

## Migration Path Overview

Choose your migration depth based on your timeline and needs:

1. **Minimal** (1-2 hours): Add supervision tree, update agent starts
2. **Intermediate** (1 day): Adopt Plugins, use Directives for side effects
3. **Full** (1-2 weeks): Pure `cmd/2`, Zoi schemas, Strategies, Plans

## Step 1: Add Jido to Your Supervision Tree

V2 uses instance-scoped supervisors instead of a global singleton. Define an instance module and add it to your supervision tree.

```elixir
# lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

```elixir
# config/config.exs
config :my_app, MyApp.Jido,
  max_tasks: 1000,
  agent_pools: []
```

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Add Jido as a supervised child
      MyApp.Jido,
      
      # Your other children...
      MyApp.Repo,
      MyAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

The instance module provides functions for managing agents that you'll use throughout your application.

## Step 2: Update Agent Starts

Replace direct `start_link` calls with your instance module's `start_agent/2`.

### Before (V1)

```elixir
# Starting an agent directly
{:ok, pid} = MyAgent.start_link(id: "agent-1")

# Or via AgentServer
{:ok, pid} = Jido.AgentServer.start_link(
  agent: MyAgent,
  agent_opts: [id: "agent-1"]
)
```

### After (V2)

```elixir
# Start via your instance module
{:ok, pid} = MyApp.Jido.start_agent(MyAgent, id: "agent-1")

# With additional options
{:ok, pid} = MyApp.Jido.start_agent(MyAgent,
  id: "agent-1",
  initial_state: %{counter: 0},
  strategy: Jido.Strategy.Direct
)
```

### Why This Matters

- **Discovery**: Agents are automatically registered and discoverable via `MyApp.Jido.whereis/1`
- **Lifecycle**: The supervisor handles restarts and cleanup
- **Hierarchy**: Enables parent-child agent relationships

## Step 3: Update Lifecycle Calls

Replace direct process calls with your instance module's functions.

### Before (V1)

```elixir
# Stopping an agent
AgentServer.stop(pid)
GenServer.stop(pid)

# Finding an agent
pid = Process.whereis(:"agent_agent-1")
```

### After (V2)

```elixir
# Stop via instance module
MyApp.Jido.stop_agent("agent-1")

# Find via discovery
pid = MyApp.Jido.whereis("agent-1")

# List all agents
agents = MyApp.Jido.list_agents()
```

## Step 4: Adopt Directives for Side Effects

V2 separates pure state transformations from side effects using Directives. This is the biggest conceptual change and can be adopted incrementally.

### Before (V1): Ad Hoc Side Effects

```elixir
defmodule MyAgent do
  use Jido.Agent

  def handle_result(agent, result) do
    # Side effect mixed with state logic
    Phoenix.PubSub.broadcast(MyApp.PubSub, "events", result)
    
    # External API call
    HTTPoison.post!("https://api.example.com/webhook", result)
    
    # Update state
    %{agent | state: Map.put(agent.state, :last_result, result)}
  end
end
```

### After (V2): Declarative Directives

```elixir
defmodule MyAgent do
  use Jido.Agent
  
  alias Jido.Agent.Directive
  alias Jido.Signal

  def cmd(agent, %Signal{type: "result.received"} = signal) do
    result = signal.data
    
    # Pure state update
    updated_agent = %{agent | 
      state: Map.put(agent.state, :last_result, result)
    }
    
    # Directives describe effects, don't execute them
    directives = [
      Directive.emit(
        Signal.new!("result.processed", result, source: "/agent"),
        {:pubsub, topic: "events"}
      ),
      Directive.emit(
        Signal.new!("webhook.send", result, source: "/agent"),
        {:http, url: "https://api.example.com/webhook"}
      )
    ]
    
    {updated_agent, directives}
  end
end
```

### Core Directives

| Directive | Purpose | Example |
|-----------|---------|---------|
| `Emit` | Dispatch a signal via adapters | `Directive.emit(signal, {:pubsub, topic: "events"})` |
| `Spawn` | Spawn a generic BEAM process | `Directive.spawn(Task, :async, [fn -> work() end])` |
| `SpawnAgent` | Spawn a child agent with hierarchy | `Directive.spawn_agent(ChildAgent, id: "child-1")` |
| `StopChild` | Stop a tracked child agent | `Directive.stop_child("child-1")` |
| `Schedule` | Schedule a delayed message | `Directive.schedule(signal, delay: 5_000)` |
| `Stop` | Stop the agent process | `Directive.stop(:normal)` |
| `Error` | Signal an error | `Directive.error(:validation_failed)` |

## Step 5: Use CloudEvents Signals

V2 uses CloudEvents-compliant signals instead of ad hoc messages.

### Before (V1): Ad Hoc Messages

```elixir
# Sending messages
send(pid, {:task_complete, %{id: 123, result: "done"}})
GenServer.cast(pid, {:process, data})

# Handling in agent
def handle_info({:task_complete, payload}, state) do
  # process...
  {:noreply, state}
end
```

### After (V2): Structured Signals

```elixir
alias Jido.Signal

# Creating signals
signal = Signal.new!(
  "task.completed",
  %{id: 123, result: "done"},
  source: "/workers/processor-1"
)

# Dispatching to a specific agent (synchronous)
{:ok, agent} = Jido.AgentServer.call(pid, signal)

# Or asynchronously
:ok = Jido.AgentServer.cast(pid, signal)

# Handling in agent (via cmd/2)
def cmd(agent, %Signal{type: "task.completed"} = signal) do
  result = signal.data.result
  {update_state(agent, result), []}
end
```

### Signal Anatomy

```elixir
%Jido.Signal{
  type: "order.placed",           # Event type (required)
  source: "/checkout/web",        # Origin (required)
  id: "550e8400-...",             # Unique ID (auto-generated)
  data: %{order_id: 123},         # Payload
  subject: "user/456",            # Optional subject
  time: ~U[2024-01-15 10:30:00Z]  # Timestamp
}
```

## Step 6: Migrate Actions to Tools

The `Jido.Actions.*` namespace has been renamed to `Jido.Tools.*`.

### Before (V1)

```elixir
defmodule MyApp.Actions.SendEmail do
  use Jido.Action,
    name: "send_email",
    description: "Sends an email",
    schema: [
      to: [type: :string, required: true],
      subject: [type: :string, required: true]
    ]

  @impl true
  def run(params, _context) do
    # send email...
    {:ok, %{sent: true}}
  end
end
```

### After (V2)

```elixir
defmodule MyApp.Tools.SendEmail do
  use Jido.Tool,
    name: "send_email",
    description: "Sends an email"

  @schema Zoi.struct(__MODULE__, %{
    to: Zoi.string(description: "Recipient email"),
    subject: Zoi.string(description: "Email subject")
  })

  @impl true
  def run(params, _context) do
    {:ok, %{sent: true}}
  end
end
```

## Step 7: Adopt Zoi Schemas

V2 uses Zoi for schema definitions instead of NimbleOptions.

### Before (V1): NimbleOptions

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [
      name: [type: :string, required: true],
      count: [type: :integer, default: 0],
      tags: [type: {:list, :string}, default: []]
    ]
end
```

### After (V2): Zoi Schemas

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent"

  @schema Zoi.struct(__MODULE__, %{
    name: Zoi.string(description: "Agent name"),
    count: Zoi.integer(default: 0),
    tags: Zoi.list(Zoi.string()) |> Zoi.default([])
  }, coerce: true)

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
end
```

### Zoi Benefits

- Single source of truth for types, defaults, and validation
- Automatic typespec generation
- Coercion support
- Better error messages

## Step 8: Migrate to Splode Errors

V2 uses Splode for structured error handling.

### Before (V1): Ad Hoc Tuples

```elixir
def process(data) do
  case validate(data) do
    :ok -> {:ok, result}
    :error -> {:error, :validation_failed}
    {:error, reason} -> {:error, {:processing_error, reason}}
  end
end
```

### After (V2): Splode Errors

```elixir
defmodule MyApp.Errors do
  use Splode, error_classes: [
    validation: MyApp.Errors.Validation,
    processing: MyApp.Errors.Processing
  ]
end

defmodule MyApp.Errors.Validation.InvalidInput do
  use Splode.Error, fields: [:field, :reason], class: :validation
  
  def message(%{field: field, reason: reason}) do
    "Invalid #{field}: #{reason}"
  end
end

# Usage
def process(data) do
  case validate(data) do
    :ok -> 
      {:ok, result}
    {:error, field, reason} -> 
      {:error, MyApp.Errors.Validation.InvalidInput.exception(
        field: field, 
        reason: reason
      )}
  end
end
```

## New Features in V2 (Optional)

These features are new in V2 and can be adopted as needed:

### Parent-Child Agent Hierarchy

```elixir
def cmd(agent, %Signal{type: "spawn.worker"} = signal) do
  {agent, [
    Directive.spawn_agent(WorkerAgent, 
      id: "worker-#{signal.data.id}",
      parent: agent
    )
  ]}
end

# Child can emit to parent
Directive.emit_to_parent(child_agent, signal)
```

### Plugin System

```elixir
defmodule MyAgent do
  use Jido.Agent,
    plugins: [
      MyApp.Plugins.WebSearch,
      MyApp.Plugins.DataAnalysis
    ]
end
```

### Strategy Pattern

```elixir
# Direct execution (default)
MyApp.Jido.start_agent(MyAgent, 
  strategy: Jido.Strategy.Direct
)

# FSM-based execution
MyApp.Jido.start_agent(MyAgent, 
  strategy: Jido.Strategy.FSM,
  strategy_opts: [initial_state: :idle]
)
```

### Telemetry

V2 emits telemetry events for observability:

```elixir
:telemetry.attach(
  "my-handler",
  [:jido, :agent, :cmd, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.info("cmd took #{measurements.duration}ns")
  end,
  nil
)
```

## Common Migration Patterns

### Pattern 1: Gradual Directive Adoption

You don't need to convert all side effects at once. Start with the most critical paths:

```elixir
def cmd(agent, signal) do
  # New code uses directives
  result = process(signal)
  
  # Legacy code still works (but should be migrated)
  LegacyNotifier.notify(result)
  
  {%{agent | state: result}, [
    Directive.emit(Signal.new!("processed", result, source: "/agent"), :default)
  ]}
end
```

### Pattern 2: Wrapper for Legacy Agents

If you have many agents, your instance module already provides the wrapper:

```elixir
# Define your instance module once
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end

# Then use it throughout your application
MyApp.Jido.start_agent(MyAgent, id: "agent-1")
MyApp.Jido.stop_agent("agent-1")
```

### Pattern 3: Signal Adapter for Legacy Messages

Bridge old message formats to signals:

```elixir
def handle_info({:legacy_event, payload}, state) do
  signal = Signal.new!("legacy.event", payload, source: "/legacy")
  handle_info(signal, state)
end
```

## Troubleshooting

### "Agent not found" errors

Ensure you're using the correct Jido instance name:

```elixir
# Wrong
Jido.start_agent(Jido, MyAgent, id: "test")

# Right
Jido.start_agent(MyApp.Jido, MyAgent, id: "test")
```

### Directives not executing

Directives are only executed when returned from `cmd/2`. Ensure you're returning them:

```elixir
# Wrong - directive is created but not returned
def cmd(agent, signal) do
  Directive.emit(signal, :default)
  {agent, []}
end

# Right
def cmd(agent, signal) do
  {agent, [Directive.emit(signal, :default)]}
end
```

### Schema validation errors

If migrating from NimbleOptions, ensure required fields are marked:

```elixir
# Zoi doesn't have `required: true`, fields are required by default
# Use Zoi.optional() for optional fields
@schema Zoi.struct(__MODULE__, %{
  name: Zoi.string(),                           # Required
  description: Zoi.string() |> Zoi.optional()   # Optional
})
```

## Getting Help

- [Jido Documentation](https://hexdocs.pm/jido)
- [GitHub Issues](https://github.com/agentjido/jido/issues)
- [Changelog](https://github.com/agentjido/jido/blob/main/CHANGELOG.md)
