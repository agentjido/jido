# Sensors

**After:** You can feed signals into Jido from the outside world.

> 🎓 **New to sensors?** Start with [Your First Sensor](your-first-sensor.md) for a hands-on tutorial before diving into this comprehensive reference.

Sensors bridge external events into the Jido signal-based world. HTTP webhooks, PubSub messages, file system changes, timers—sensors transform them all into Signals that agents can process.

```
External World → Sensor → Signal → Agent
```

## When to Use Sensors

Use sensors when you want to:
- Poll an external API at regular intervals
- React to Phoenix.PubSub messages
- Convert webhooks into agent signals
- Implement heartbeat/liveness checks
- Bridge any event source into your agent

## The Sensor Behaviour

A sensor is a pure module implementing the `Jido.Sensor` behaviour. The `Jido.Sensor.Runtime` GenServer handles actual execution—similar to how `AgentServer` wraps agent modules.

```elixir
defmodule MetricSensor do
  use Jido.Sensor,
    name: "metric_sensor",
    description: "Monitors a specific metric",
    schema: Zoi.object(%{
      metric: Zoi.string(),
      threshold: Zoi.integer() |> Zoi.default(100)
    }, coerce: true)

  @impl Jido.Sensor
  def init(config, _context) do
    {:ok, %{metric: config.metric, threshold: config.threshold, last_value: nil}}
  end

  @impl Jido.Sensor
  def handle_event({:metric_update, value}, state) do
    signal = Jido.Signal.new!(%{
      source: "/sensor/metric",
      type: "metric.updated",
      data: %{value: value, previous: state.last_value, exceeded: value > state.threshold}
    })

    {:ok, %{state | last_value: value}, [{:emit, signal}]}
  end
end
```

## Callbacks

### init/2 (required)

Initialize sensor state from validated config and runtime context.

```elixir
@impl Jido.Sensor
def init(config, context) do
  # config: Validated against the sensor's schema
  # context: Runtime info (e.g., :agent_ref for signal delivery)
  
  {:ok, %{interval: config.interval, count: 0}, [{:schedule, config.interval}]}
end
```

**Return values:**
- `{:ok, state}` — Initial state
- `{:ok, state, directives}` — Initial state plus startup directives
- `{:error, reason}` — Initialization failed

### handle_event/2 (required)

Process incoming events and emit signals.

```elixir
@impl Jido.Sensor
def handle_event(:tick, state) do
  signal = Jido.Signal.new!(%{
    source: "/sensor/tick",
    type: "sensor.tick",
    data: %{count: state.count}
  })

  {:ok, %{state | count: state.count + 1}, [{:emit, signal}, {:schedule, state.interval}]}
end
```

**Return values:**
- `{:ok, state, directives}` — Updated state and directives to execute
- `{:error, reason}` — Event handling failed

### terminate/2 (optional)

Clean up resources on shutdown. Default implementation returns `:ok`.

```elixir
@impl Jido.Sensor
def terminate(_reason, state) do
  # Clean up connections, timers, etc.
  :ok
end
```

## Sensor Directives

Callbacks return directives that the Runtime executes:

| Directive | Description |
|-----------|-------------|
| `{:schedule, ms}` | Schedule a `:tick` event after `ms` milliseconds |
| `{:schedule, ms, payload}` | Schedule a custom event after `ms` milliseconds |
| `{:emit, signal}` | Deliver signal to the agent immediately |
| `{:connect, adapter}` | Connect to an external source |
| `{:connect, adapter, opts}` | Connect with options |
| `{:disconnect, adapter}` | Disconnect from a source |
| `{:subscribe, topic}` | Subscribe to a topic/pattern |
| `{:unsubscribe, topic}` | Unsubscribe from a topic |

## Starting Sensors

Use `Jido.Sensor.Runtime` to run a sensor:

```elixir
{:ok, sensor_pid} = Jido.Sensor.Runtime.start_link(
  sensor: MetricSensor,
  config: %{metric: "cpu_usage", threshold: 80},
  context: %{agent_ref: agent_pid}
)
```

### Options

| Option | Description |
|--------|-------------|
| `:sensor` | Sensor module (required) |
| `:config` | Configuration map, validated against sensor's schema |
| `:context` | Runtime context, including `:agent_ref` for signal delivery |
| `:id` | Instance ID (auto-generated if not provided) |

### In Supervision Trees

```elixir
children = [
  {Jido.Sensor.Runtime,
   sensor: TickSensor,
   config: %{interval: 1000},
   context: %{agent_ref: {:via, Registry, {MyApp.Registry, "my-agent"}}},
   id: :tick_sensor}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

## Built-in Sensors

### Jido.Sensors.Heartbeat

Emits periodic heartbeat signals for liveness checks:

```elixir
{:ok, _} = Jido.Sensor.Runtime.start_link(
  sensor: Jido.Sensors.Heartbeat,
  config: %{interval: 5000, message: "alive"},
  context: %{agent_ref: agent_pid}
)
```

Emits signals with type `"jido.sensor.heartbeat"` containing:
- `message` — The configured message
- `timestamp` — UTC timestamp of the heartbeat

## Example: Custom Interval Sensor

A sensor that polls an external API every 30 seconds:

```elixir
defmodule ApiPollSensor do
  use Jido.Sensor,
    name: "api_poll",
    description: "Polls an API endpoint at regular intervals",
    schema: Zoi.object(%{
      url: Zoi.string(),
      interval: Zoi.integer() |> Zoi.default(30_000)
    }, coerce: true)

  @impl Jido.Sensor
  def init(config, _context) do
    state = %{url: config.url, interval: config.interval}
    {:ok, state, [{:schedule, 0}]}  # Poll immediately on start
  end

  @impl Jido.Sensor
  def handle_event(:tick, state) do
    case fetch_data(state.url) do
      {:ok, data} ->
        signal = Jido.Signal.new!(%{
          source: "/sensor/api_poll",
          type: "api.data_received",
          data: data
        })
        {:ok, state, [{:emit, signal}, {:schedule, state.interval}]}

      {:error, reason} ->
        signal = Jido.Signal.new!(%{
          source: "/sensor/api_poll",
          type: "api.error",
          data: %{error: reason}
        })
        {:ok, state, [{:emit, signal}, {:schedule, state.interval}]}
    end
  end

  defp fetch_data(url) do
    # Your HTTP client logic here
    {:ok, %{status: "ok", timestamp: DateTime.utc_now()}}
  end
end
```

## Example: PubSub-Based Sensor

A sensor that subscribes to Phoenix.PubSub and forwards messages as signals:

```elixir
defmodule PubSubSensor do
  use Jido.Sensor,
    name: "pubsub_sensor",
    description: "Subscribes to Phoenix.PubSub topics",
    schema: Zoi.object(%{
      pubsub: Zoi.atom(),
      topic: Zoi.string()
    }, coerce: true)

  @impl Jido.Sensor
  def init(config, _context) do
    Phoenix.PubSub.subscribe(config.pubsub, config.topic)
    {:ok, %{pubsub: config.pubsub, topic: config.topic}}
  end

  @impl Jido.Sensor
  def handle_event({:pubsub_message, payload}, state) do
    signal = Jido.Signal.new!(%{
      source: "/sensor/pubsub/#{state.topic}",
      type: "pubsub.message",
      data: payload
    })

    {:ok, state, [{:emit, signal}]}
  end

  @impl Jido.Sensor
  def terminate(_reason, state) do
    Phoenix.PubSub.unsubscribe(state.pubsub, state.topic)
    :ok
  end
end
```

To make this work, you need a custom Runtime or use `handle_info` in the Runtime to forward PubSub messages. The simplest approach is injecting events externally:

```elixir
# In your application code, forward PubSub messages to the sensor
Phoenix.PubSub.subscribe(MyApp.PubSub, "events")

receive do
  message ->
    Jido.Sensor.Runtime.event(sensor_pid, {:pubsub_message, message})
end
```

## Example: Connecting Sensor to Agent

Complete working example with an agent that reacts to sensor signals:

```elixir
# The action that handles sensor signals
defmodule HandleTickAction do
  use Jido.Action,
    name: "handle_tick",
    schema: [count: [type: :integer, required: true]]

  def run(params, context) do
    current = Map.get(context.state, :tick_count, 0)
    {:ok, %{tick_count: current + 1, last_sensor_count: params.count}}
  end
end

# The agent with signal routing
defmodule TickCounterAgent do
  use Jido.Agent,
    name: "tick_counter",
    schema: [
      tick_count: [type: :integer, default: 0],
      last_sensor_count: [type: :integer, default: 0]
    ]

  @signal_routes [{"sensor.tick", HandleTickAction}]
  def signal_routes(_ctx), do: @signal_routes
end

# The sensor
defmodule TickSensor do
  use Jido.Sensor,
    name: "tick_sensor",
    schema: Zoi.object(%{
      interval: Zoi.integer() |> Zoi.default(1000)
    }, coerce: true)

  @impl Jido.Sensor
  def init(config, _context) do
    {:ok, %{interval: config.interval, count: 0}, [{:schedule, config.interval}]}
  end

  @impl Jido.Sensor
  def handle_event(:tick, state) do
    count = state.count + 1
    signal = Jido.Signal.new!(%{
      source: "/sensor/tick",
      type: "sensor.tick",
      data: %{count: count}
    })

    {:ok, %{state | count: count}, [{:emit, signal}, {:schedule, state.interval}]}
  end
end
```

Wire it together:

```elixir
# Start the agent
{:ok, agent_pid} = Jido.AgentServer.start_link(agent: TickCounterAgent.new())

# Start the sensor, targeting the agent
{:ok, _sensor} = Jido.Sensor.Runtime.start_link(
  sensor: TickSensor,
  config: %{interval: 1000},
  context: %{agent_ref: agent_pid}
)

# After a few seconds, check agent state
Process.sleep(3500)
{:ok, state} = Jido.AgentServer.state(agent_pid)
state.agent.state.tick_count
# => 3
```

## Signal Delivery

When a sensor emits a signal via `{:emit, signal}`:

1. If `context.agent_ref` is a pid, sends `{:signal, signal}` directly
2. If `context.agent_ref` is another reference (e.g., via Registry), uses `Jido.Signal.Dispatch`
3. If no `agent_ref`, the signal is logged but not delivered

## Manual Event Injection

Inject events into a running sensor from external code:

```elixir
# Inject a custom event
Jido.Sensor.Runtime.event(sensor_pid, {:external_data, payload})

# The sensor's handle_event/2 receives this
@impl Jido.Sensor
def handle_event({:external_data, payload}, state) do
  # Process the externally injected event
  {:ok, state, [{:emit, signal}]}
end
```

This is useful for bridging external event sources (GenStage, Broadway, custom GenServers) into sensors.

## Backpressure and Deduplication

Sensors don't have built-in backpressure. Implement these strategies in your sensor logic:

### Rate Limiting

```elixir
def handle_event(:tick, state) do
  if can_emit?(state) do
    {:ok, %{state | last_emit: System.monotonic_time()}, [{:emit, signal}, {:schedule, interval}]}
  else
    {:ok, state, [{:schedule, interval}]}
  end
end

defp can_emit?(state) do
  now = System.monotonic_time(:millisecond)
  now - state.last_emit > state.min_interval
end
```

### Deduplication

```elixir
def handle_event(:tick, state) do
  data_hash = :erlang.phash2(new_data)
  
  if data_hash != state.last_hash do
    {:ok, %{state | last_hash: data_hash}, [{:emit, signal}, {:schedule, interval}]}
  else
    {:ok, state, [{:schedule, interval}]}
  end
end
```

### Batching

```elixir
def handle_event({:data, item}, state) do
  buffer = [item | state.buffer]
  
  if length(buffer) >= state.batch_size do
    signal = Jido.Signal.new!(%{
      source: "/sensor/batch",
      type: "batch.ready",
      data: %{items: Enum.reverse(buffer)}
    })
    {:ok, %{state | buffer: []}, [{:emit, signal}]}
  else
    {:ok, %{state | buffer: buffer}, []}
  end
end
```

## See Also

- [Your First Sensor](your-first-sensor.md) — Introductory tutorial
- [Signals & Routing](signals.md) — How agents process signals
- [Runtime](runtime.md) — Agent runtime and signal processing
- `Jido.Sensor` — Behaviour module documentation
- `Jido.Sensor.Runtime` — Runtime GenServer documentation
