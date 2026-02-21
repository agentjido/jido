# Your First Sensor

**After:** You can feed external events into your agent as Signals.

## The Result

Here's a working sensor that emits a counter tick every second, connected to an agent that tracks the count:

```elixir
defmodule TickSensor do
  use Jido.Sensor,
    name: "tick_sensor",
    description: "Emits a tick signal at regular intervals",
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

Start the sensor pointing at your agent:

```elixir
{:ok, _sensor} = Jido.Sensor.Runtime.start_link(
  sensor: TickSensor,
  config: %{interval: 1000},
  context: %{agent_ref: agent_pid}
)
```

Every second, your agent receives `{:signal, %Jido.Signal{type: "sensor.tick", data: %{count: n}}}`.

## What is a Sensor?

A sensor transforms external world events into Signals that agents can process. External world → Sensor → Signal → Agent.

Sensors are pure modules that define two callbacks: `init/2` sets up initial state, and `handle_event/2` transforms events into signals. The `Jido.Sensor.Runtime` GenServer handles the actual execution.

## Creating a Sensor

### Step 1: Define the module

```elixir
defmodule TickSensor do
  use Jido.Sensor,
    name: "tick_sensor",
    description: "Emits a tick signal at regular intervals",
    schema: Zoi.object(%{
      interval: Zoi.integer() |> Zoi.default(1000)
    }, coerce: true)
```

The `schema` validates configuration at startup using Zoi.

### Step 2: Implement init/2

```elixir
@impl Jido.Sensor
def init(config, _context) do
  {:ok, %{interval: config.interval, count: 0}, [{:schedule, config.interval}]}
end
```

`init/2` receives validated config and a context map. Return `{:ok, state}` or `{:ok, state, directives}`.

The `{:schedule, interval_ms}` directive tells the runtime to send a `:tick` event after the interval.

### Step 3: Implement handle_event/2

```elixir
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
```

`handle_event/2` receives events and returns updated state plus directives.

### Available Directives

| Directive | Effect |
|-----------|--------|
| `{:schedule, ms}` | Send `:tick` after `ms` milliseconds |
| `{:schedule, ms, event}` | Send custom `event` after `ms` milliseconds |
| `{:emit, signal}` | Deliver signal to the agent immediately |

## Built-in: Heartbeat Sensor

Jido includes `Jido.Sensors.Heartbeat` for simple periodic signals:

```elixir
{:ok, _} = Jido.Sensor.Runtime.start_link(
  sensor: Jido.Sensors.Heartbeat,
  config: %{interval: 5000, message: "alive"},
  context: %{agent_ref: agent_pid}
)
```

The agent receives signals with type `"jido.sensor.heartbeat"` every 5 seconds.

## Connecting to an Agent

### Complete Example: Counter Agent

```elixir
defmodule HandleTickAction do
  use Jido.Action,
    name: "handle_tick",
    schema: [
      count: [type: :integer, required: true]
    ]

  def run(params, context) do
    current = Map.get(context.state, :tick_count, 0)
    {:ok, %{tick_count: current + 1, last_tick: params.count}}
  end
end

defmodule CounterAgent do
  use Jido.Agent,
    name: "counter",
    schema: [
      tick_count: [type: :integer, default: 0],
      last_tick: [type: :integer, default: 0]
    ]

  def signal_routes do
    [
      {"sensor.tick", HandleTickAction}
    ]
  end
end
```

Wire it together:

```elixir
# Start agent
{:ok, agent_pid} = Jido.AgentServer.start_link(agent: CounterAgent.new())

# Start sensor targeting the agent
{:ok, _sensor} = Jido.Sensor.Runtime.start_link(
  sensor: TickSensor,
  config: %{interval: 1000},
  context: %{agent_ref: agent_pid}
)

# After a few seconds, check state
Process.sleep(3000)
{:ok, state} = Jido.AgentServer.state(agent_pid)
state.agent.state.tick_count
# => 3
```

### Manual Event Injection

You can also inject events directly into a running sensor:

```elixir
Jido.Sensor.Runtime.event(sensor_pid, {:custom_data, payload})
```

## Next Steps

- [Signals Guide](signals.md) — Learn about Signal structure and routing
- [Runtime Guide](runtime.md) — Understand how agents process incoming signals
- [sensor_demo_test.exs](https://github.com/agentjido/jido/blob/main/test/examples/observability/sensor_demo_test.exs) — Full working example with quotes and webhooks
