# Worker Pools

**After:** You can run concurrent work safely without melting the BEAM.

```elixir
# Before: spawn a new agent per request (expensive initialization)
{:ok, pid} = Jido.start_agent(jido, SearchAgent)
result = AgentServer.call(pid, signal)
Jido.stop_agent(jido, agent_id)  # Teardown overhead

# After: checkout from pre-warmed pool (sub-millisecond)
{:ok, result} = Jido.Agent.WorkerPool.call(MyApp.Jido, :search, signal)
```

## When to Use Pools

Use worker pools when:

- Agent initialization is expensive (loading models, establishing connections)
- You need bounded concurrency for resource-limited operations
- You want consistent latency under load (no cold starts)

Use spawn-per-request when:

- Agents need per-request state isolation
- Initialization is cheap
- Request volume is unpredictable and bursty

## Configuration

Configure pools in your Jido instance:

```elixir
# lib/my_app/application.ex
children = [
  {Jido,
   name: MyApp.Jido,
   agent_pools: [
     {:fast_search, MyApp.Agents.SearchAgent, size: 8, max_overflow: 4},
     {:planner, MyApp.Agents.PlannerAgent, size: 4, strategy: :fifo}
   ]}
]
```

Or via config:

```elixir
# config/config.exs
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
| `:max_overflow` | 0 | Maximum temporary workers when pool exhausted |
| `:strategy` | `:lifo` | Checkout order: `:lifo` or `:fifo` |
| `:worker_opts` | `[]` | Options passed to `Jido.AgentServer.start_link/1` |

**Strategy choice:**

- `:lifo` (default) — Most recently used agent. Better cache locality, agents stay "warm"
- `:fifo` — Round-robin. Even load distribution across workers

## API Reference

### with_agent/4 (Recommended)

Transaction-style checkout/checkin. The safest way to use pooled agents:

```elixir
Jido.Agent.WorkerPool.with_agent(MyApp.Jido, :fast_search, fn pid ->
  signal = Signal.new!("search", %{query: "elixir pools"}, source: "/api")
  {:ok, agent} = Jido.AgentServer.call(pid, signal)
  agent.state.results
end)
```

Multiple operations on the same agent:

```elixir
Jido.Agent.WorkerPool.with_agent(MyApp.Jido, :planner, fn pid ->
  {:ok, _} = Jido.AgentServer.call(pid, setup_signal)
  {:ok, agent} = Jido.AgentServer.call(pid, execute_signal)
  agent.state.plan
end, timeout: 10_000)
```

### call/4

Send a single signal and wait for result:

```elixir
signal = Signal.new!("search", %{query: "poolboy"}, source: "/api")
{:ok, agent} = Jido.Agent.WorkerPool.call(MyApp.Jido, :fast_search, signal)
agent.state.results
```

Options:

| Option | Default | Description |
|--------|---------|-------------|
| `:timeout` | 5000 | Pool checkout timeout (ms) |
| `:call_timeout` | 5000 | Signal processing timeout (ms) |

### cast/4

Fire-and-forget signal (agent checked in immediately):

```elixir
signal = Signal.new!("index", %{doc: document}, source: "/worker")
:ok = Jido.Agent.WorkerPool.cast(MyApp.Jido, :indexer, signal)
```

**Warning:** The agent is returned to the pool before processing completes. Use `call/4` if you need the result.

### status/2

Inspect pool status for monitoring:

```elixir
status = Jido.Agent.WorkerPool.status(MyApp.Jido, :fast_search)
# => %{state: :ready, available: 5, overflow: 0, checked_out: 3}
```

| Field | Description |
|-------|-------------|
| `:state` | Pool state (`:ready`, `:full`, `:overflow`) |
| `:available` | Workers waiting for checkout |
| `:overflow` | Currently active overflow workers |
| `:checked_out` | Workers currently in use |

### checkout/3 and checkin/3 (Low-Level)

Manual checkout/checkin. **Not recommended**—use `with_agent/4` instead.

```elixir
pid = Jido.Agent.WorkerPool.checkout(MyApp.Jido, :fast_search)
try do
  Jido.AgentServer.call(pid, signal)
after
  Jido.Agent.WorkerPool.checkin(MyApp.Jido, :fast_search, pid)
end
```

If you forget to checkin, the worker is leaked until process death.

## State Semantics Warning

**Pooled agents are long-lived stateful workers.** State persists across checkouts:

```elixir
# First checkout: counter = 0 → 1
Jido.Agent.WorkerPool.with_agent(jido, :counter_pool, fn pid ->
  Jido.AgentServer.call(pid, increment_signal)
end)

# Second checkout (same worker): counter = 1 → 2
Jido.Agent.WorkerPool.with_agent(jido, :counter_pool, fn pid ->
  {:ok, agent} = Jido.AgentServer.call(pid, increment_signal)
  agent.state.counter  # => 2, not 1!
end)
```

Design patterns for per-request isolation:

1. **Stateless agents**: Store only cached/shared data in agent state; pass request data via signal
2. **Reset action**: Call a "reset" signal at the start of each transaction
3. **Request-scoped state**: Use `worker_opts` to configure how state resets

```elixir
# Pattern 1: Stateless design - pass everything via signal
defmodule SearchAction do
  use Jido.Action, name: "search", schema: [query: [type: :string, required: true]]

  def run(%{query: query}, context) do
    # Use cached connection from agent state
    conn = context.state.connection
    results = do_search(conn, query)
    {:ok, %{last_results: results}}  # Only store for debugging
  end
end
```

## Pool Sizing Guidelines

### Size Calculation

Start with:

```
size = expected_concurrent_requests × average_request_duration / 1000
```

Example: 100 req/sec with 50ms average → `100 × 0.05 = 5` workers minimum.

### Overflow Strategy

| Pattern | `max_overflow` | Use Case |
|---------|----------------|----------|
| Strict limit | 0 | Rate limiting, resource protection |
| Burst buffer | `size × 0.5` | Handle traffic spikes |
| Elastic | `size × 2` | Unknown load, prioritize availability |

### Environment-Based Sizing

```elixir
# config/runtime.exs
import Config

pool_size = 
  case config_env() do
    :prod -> String.to_integer(System.get_env("SEARCH_POOL_SIZE", "16"))
    :test -> 2
    :dev -> 4
  end

config :my_app, MyApp.Jido,
  agent_pools: [
    {:search, MyApp.SearchAgent, size: pool_size, max_overflow: div(pool_size, 2)}
  ]
```

## Timeout Configuration

Three timeout boundaries:

```elixir
# 1. Pool checkout timeout: waiting for available worker
Jido.Agent.WorkerPool.call(jido, :pool, signal, timeout: 5_000)

# 2. Call timeout: signal processing within agent
Jido.Agent.WorkerPool.call(jido, :pool, signal, call_timeout: 30_000)

# 3. Combined example
Jido.Agent.WorkerPool.call(jido, :pool, signal,
  timeout: 2_000,       # Fast fail if pool exhausted
  call_timeout: 60_000  # Long timeout for expensive operation
)
```

When checkout times out, you get a `{:noproc, _}` error from poolboy.

## Instrumentation

### Telemetry Integration

Attach handlers for pool metrics:

```elixir
defmodule MyApp.PoolMetrics do
  def setup do
    :telemetry.attach_many(
      "pool-metrics",
      [
        [:jido, :agent, :call, :start],
        [:jido, :agent, :call, :stop],
        [:jido, :agent, :call, :exception]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:jido, :agent, :call, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    :telemetry.execute(
      [:my_app, :pool, :call],
      %{duration_ms: duration_ms},
      %{pool: metadata.pool_name, success: metadata.success}
    )
  end
end
```

### Status Polling

Periodic health checks:

```elixir
defmodule MyApp.PoolMonitor do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    jido = Keyword.fetch!(opts, :jido)
    pools = Keyword.fetch!(opts, :pools)
    schedule_check()
    {:ok, %{jido: jido, pools: pools}}
  end

  def handle_info(:check, state) do
    for pool <- state.pools do
      status = Jido.Agent.WorkerPool.status(state.jido, pool)
      
      if status.available == 0 and status.overflow > 0 do
        Logger.warning("Pool #{pool} exhausted, using overflow workers",
          pool: pool,
          overflow: status.overflow
        )
      end
    end
    
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check, do: Process.send_after(self(), :check, 5_000)
end
```

## Example: Pool-Backed URL Fetcher

Complete example with a pool for HTTP requests:

```elixir
defmodule MyApp.FetchAction do
  use Jido.Action,
    name: "fetch",
    schema: [
      url: [type: :string, required: true],
      timeout: [type: :integer, default: 5000]
    ]

  def run(%{url: url, timeout: timeout}, context) do
    # Use persistent HTTP client from agent state
    client = context.state.http_client
    
    case Req.get(client, url: url, receive_timeout: timeout) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{last_fetch: %{url: url, body: body, fetched_at: DateTime.utc_now()}}}
      
      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}
      
      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end
end

defmodule MyApp.FetcherAgent do
  use Jido.Agent,
    name: "fetcher",
    schema: [
      http_client: [type: :any, required: true],
      last_fetch: [type: :map, default: nil]
    ]

  def signal_routes do
    [{"fetch", MyApp.FetchAction}]
  end
end

# Configuration
children = [
  {Jido,
   name: MyApp.Jido,
   agent_pools: [
     {:fetcher, MyApp.FetcherAgent,
      size: 10,
      max_overflow: 5,
      worker_opts: [
        initial_state: %{http_client: Req.new(retry: false)}
      ]}
   ]}
]

# Usage
defmodule MyApp.Crawler do
  alias Jido.Agent.WorkerPool
  alias Jido.Signal

  def fetch_urls(urls) do
    urls
    |> Task.async_stream(fn url ->
      signal = Signal.new!("fetch", %{url: url}, source: "/crawler")
      
      case WorkerPool.call(MyApp.Jido, :fetcher, signal, call_timeout: 10_000) do
        {:ok, agent} -> {:ok, url, agent.state.last_fetch}
        {:error, reason} -> {:error, url, reason}
      end
    end, max_concurrency: 20, timeout: 15_000)
    |> Enum.to_list()
  end
end
```

## Common Patterns

### Bounded Concurrency

Limit concurrent access to a scarce resource:

```elixir
# Pool size = number of database connections
agent_pools: [
  {:db_writer, MyApp.DbWriterAgent, size: 5, max_overflow: 0}
]

# Callers block when all 5 connections busy
WorkerPool.call(jido, :db_writer, write_signal, timeout: 30_000)
```

### Backpressure

Fail fast when pool exhausted instead of queueing:

```elixir
case WorkerPool.call(jido, :processor, signal, timeout: 100) do
  {:ok, result} -> 
    {:ok, result}
  
  {:error, {:timeout, _}} -> 
    {:error, :service_overloaded}
end
```

Or use non-blocking checkout:

```elixir
case Jido.Agent.WorkerPool.checkout(jido, :processor, block: false) do
  :full -> 
    {:error, :pool_exhausted}
  
  pid ->
    try do
      Jido.AgentServer.call(pid, signal)
    after
      Jido.Agent.WorkerPool.checkin(jido, :processor, pid)
    end
end
```

### Warm Pool Pattern

Pre-warm agents with expensive initialization:

```elixir
defmodule MyApp.MLAgent do
  use Jido.Agent,
    name: "ml_agent",
    schema: [
      model: [type: :any, required: true]
    ]

  # Model loaded once at pool startup, reused across requests
end

agent_pools: [
  {:ml, MyApp.MLAgent,
   size: 4,
   max_overflow: 0,  # Never cold-start; all workers pre-warmed
   worker_opts: [
     initial_state: %{model: MyApp.ML.load_model!()}
   ]}
]
```

## Pools vs Spawn-Per-Request

| Aspect | Worker Pool | Spawn-Per-Request |
|--------|-------------|-------------------|
| Latency | Consistent (no cold start) | Variable (init overhead) |
| State | Shared across requests | Isolated per request |
| Memory | Fixed (pool size) | Scales with load |
| Failure | Worker restarted, pool recovers | Isolated failure |
| Concurrency | Bounded by pool size | Unbounded (dangerous) |

**Choose pools for:**
- Database connections
- HTTP clients with keep-alive
- ML model inference
- Rate-limited external APIs

**Choose spawn-per-request for:**
- User-specific agents with personalized state
- One-shot workflows
- Testing (isolated state)

## Related

- [Configuration](configuration.md) — Instance setup and pool configuration
- [Persistence & Storage](storage.md) — Hibernate/thaw and InstanceManager lifecycle
- [Runtime](runtime.md) — AgentServer process model
- [Observability](observability-intro.md) — Monitoring and telemetry
