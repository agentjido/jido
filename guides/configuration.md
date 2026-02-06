# Configuration & Deployment

**After:** You can configure Jido for different environments.

This guide covers Jido configuration options and production deployment patterns.

## Basic Setup

### Defining a Jido Instance

Every application using Jido starts by defining an instance module:

```elixir
# lib/my_app/jido.ex
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

This generates a supervision-ready module with functions for managing agents.

### Adding to Supervision Tree

Add your Jido instance to your application's supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyApp.Jido
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Configuration

Configure your instance in `config/config.exs`:

```elixir
config :my_app, MyApp.Jido,
  max_tasks: 1000,
  agent_pools: []
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:max_tasks` | integer | 1000 | Maximum concurrent tasks for `Task.Supervisor` |
| `:agent_pools` | list | `[]` | Pre-configured agent pool definitions |

### Runtime Configuration

Override configuration at startup by passing options directly:

```elixir
children = [
  {MyApp.Jido, max_tasks: 2000}
]
```

## Supervision Tree

Each Jido instance starts a supervision tree with three core components:

```
MyApp.Jido (Supervisor)
├── MyApp.Jido.TaskSupervisor (Task.Supervisor)
│   └── Handles async work with max_children limit
├── MyApp.Jido.Registry (Registry)
│   └── Agent lookup by ID
└── MyApp.Jido.AgentSupervisor (DynamicSupervisor)
    └── Supervises running agent processes
```

### Accessing Infrastructure Names

Your Jido instance provides functions to access component names:

```elixir
MyApp.Jido.registry_name()          # => MyApp.Jido.Registry
MyApp.Jido.agent_supervisor_name()  # => MyApp.Jido.AgentSupervisor
MyApp.Jido.task_supervisor_name()   # => MyApp.Jido.TaskSupervisor
```

### Generated API

The instance module provides these functions:

```elixir
# Agent lifecycle
MyApp.Jido.start_agent(MyAgent, id: "agent-1")
MyApp.Jido.start_agent(MyAgent, id: "agent-1", initial_state: %{count: 10})
MyApp.Jido.stop_agent("agent-1")

# Lookup
MyApp.Jido.whereis("agent-1")  # Returns pid or nil
MyApp.Jido.list_agents()       # Returns list of {id, pid}
MyApp.Jido.agent_count()       # Returns integer

# Configuration
MyApp.Jido.config()            # Returns merged configuration
```

## Agent Pools

For performance-critical use cases where agent initialization is expensive, configure pre-warmed agent pools.

### Pool Configuration

```elixir
config :my_app, MyApp.Jido,
  agent_pools: [
    {:fast_search, MyApp.Agents.SearchAgent, size: 8, max_overflow: 4},
    {:planner, MyApp.Agents.PlannerAgent, size: 4, strategy: :fifo}
  ]
```

### Pool Options

| Option | Default | Description |
|--------|---------|-------------|
| `:size` | 5 | Fixed number of pre-warmed agents |
| `:max_overflow` | 0 | Maximum temporary workers when pool is exhausted |
| `:strategy` | `:lifo` | Checkout order: `:lifo` or `:fifo` |
| `:worker_opts` | `[]` | Options passed to `Jido.AgentServer.start_link/1` |

### Using Pooled Agents

```elixir
# Simple call - handles checkout/checkin automatically
{:ok, result} = Jido.Agent.WorkerPool.call(MyApp.Jido, :fast_search, signal)

# Transaction-style for multiple operations
Jido.Agent.WorkerPool.with_agent(MyApp.Jido, :fast_search, fn pid ->
  Jido.AgentServer.call(pid, signal1)
  Jido.AgentServer.call(pid, signal2)
end)

# Check pool status
status = Jido.Agent.WorkerPool.status(MyApp.Jido, :fast_search)
# => %{state: :ready, available: 5, overflow: 0, checked_out: 3}
```

See [Worker Pools](worker-pools.md) for detailed pool configuration and usage patterns.

### Pool State Semantics

Pooled agents are **long-lived stateful workers**. State persists across checkouts unless the agent crashes. Design your agent to accept request-specific data via signals rather than storing it in agent state if you need per-request isolation.

## Production Considerations

### Timeouts

Configure timeouts based on your workload:

```elixir
# AgentServer call timeout (default: 5000ms)
Jido.AgentServer.call(pid, signal, 10_000)

# Pool checkout timeout
Jido.Agent.WorkerPool.call(MyApp.Jido, :pool, signal, timeout: 10_000)
```

### Graceful Shutdown

The Jido supervisor uses a 10-second shutdown timeout by default:

```elixir
# From child_spec/1
%{
  id: name,
  start: {__MODULE__, :start_link, [opts]},
  type: :supervisor,
  restart: :permanent,
  shutdown: 10_000
}
```

The `DynamicSupervisor` for agents is configured with:
- `max_restarts: 1000` - Maximum restarts within the time window
- `max_seconds: 5` - Time window for restart counting

### Memory Considerations

- **Task Supervisor**: Limit concurrent tasks with `:max_tasks` to prevent memory exhaustion
- **Agent Pools**: Pre-warmed agents consume memory at startup; size pools based on expected load
- **Registry**: Lightweight, but scales with number of active agents

### Scaling Guidelines

| Component | Consideration |
|-----------|---------------|
| `:max_tasks` | Set based on available CPU cores and task duration |
| Pool `:size` | Match expected concurrent requests |
| Pool `:max_overflow` | Handle burst traffic; temporary workers are spawned on demand |

### Monitoring and Alerting

Jido emits telemetry events that you can attach to for monitoring:

```elixir
# In your application startup
:telemetry.attach_many(
  "jido-metrics",
  [
    [:jido, :agent, :start],
    [:jido, :agent, :stop],
    [:jido, :signal, :dispatch]
  ],
  &MyApp.Metrics.handle_event/4,
  nil
)
```

Monitor these metrics in production:
- Agent count per instance
- Pool checkout latency and queue depth
- Task supervisor utilization

## Environment-Based Configuration

Use `config/runtime.exs` for environment-specific settings:

```elixir
# config/runtime.exs
import Config

config :my_app, MyApp.Jido,
  max_tasks: String.to_integer(System.get_env("JIDO_MAX_TASKS", "1000"))

# Configure pools based on environment
if config_env() == :prod do
  config :my_app, MyApp.Jido,
    agent_pools: [
      {:search, MyApp.SearchAgent, 
       size: String.to_integer(System.get_env("SEARCH_POOL_SIZE", "10")),
       max_overflow: String.to_integer(System.get_env("SEARCH_POOL_OVERFLOW", "5"))}
    ]
end
```

### Per-Agent Configuration

Configure individual agents at startup:

```elixir
MyApp.Jido.start_agent(MyApp.Agent,
  id: "agent-1",
  initial_state: %{count: 0},
  strategy_opts: %{batch_size: 20},
  plugin_configs: %{
    cache: %{max_size: 5000},
    logging: %{level: :debug}
  }
)
```

## Multiple Jido Instances

For multi-tenant applications or isolation, define multiple instances:

```elixir
defmodule MyApp.TenantA.Jido do
  use Jido, otp_app: :my_app
end

defmodule MyApp.TenantB.Jido do
  use Jido, otp_app: :my_app
end
```

Configure each separately:

```elixir
config :my_app, MyApp.TenantA.Jido,
  max_tasks: 500

config :my_app, MyApp.TenantB.Jido,
  max_tasks: 1000
```

## Testing Configuration

For tests, use `JidoTest.Case` which provides an isolated Jido instance:

```elixir
defmodule MyAgentTest do
  use JidoTest.Case, async: true

  test "agent works", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, MyAgent)
    # Test with isolated instance
  end
end
```

See [Testing](testing.md) for more patterns.

## Related

- [Persistence & Storage](storage.md) — Hibernate/thaw and InstanceManager lifecycle
- [Worker Pools](worker-pools.md) — Pre-warmed agent pools for throughput
- [Runtime](runtime.md) — AgentServer and process-based execution
- [Testing](testing.md) — Testing patterns and best practices
- [Strategies](strategies.md) — Execution strategies configuration
