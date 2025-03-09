# Building Stateful Agents in Jido

## Overview

Jido's stateful agents combine the power of Elixir's GenServer with Jido's agent capabilities, providing a robust foundation for building long-running, stateful processes. By implementing `start_link/1`, your agent automatically integrates with OTP supervision trees while maintaining all the workflow orchestration features of Jido.

## Core Design Principles

1. **OTP Integration**: Seamless integration with Elixir's supervision trees
2. **Signal-Based Communication**: Asynchronous message passing using signals
3. **State Management**: Server-managed state with validation
4. **Lifecycle Management**: OTP-compliant process lifecycle

## Implementation Guide

### Basic Agent Structure

```elixir
defmodule MyApp.StatefulAgent do
  use Jido.Agent,
    name: "stateful_agent",
    description: "OTP-integrated workflow processor",
    actions: [
      MyApp.Actions.ProcessData,
      MyApp.Actions.GenerateResponse
    ]

  # Server startup configuration
  def start_link(opts) do
    Jido.Agent.Server.start_link(
      id: opts[:id],              # Unique identifier
      agent: __MODULE__,          # This module
      mode: :auto,                # Execution mode
      log_level: :debug,          # Logging verbosity
      routes: [                   # Signal routing
        {"process.data", %Instruction{
          action: MyApp.Actions.ProcessData,
          opts: [timeout: 5000]
        }}
      ],
      sensors: [                  # Background processes
        {MyApp.Sensors.Monitor, []}
      ],
      skills: [                   # Additional capabilities
        MyApp.Skills.DataProcessor
      ]
    )
  end

  # Signal handling
  def handle_signal(%Signal{type: "process.data"} = signal) do
    {:ok, signal}
  end

  # Result processing
  def transform_result(%Signal{type: "process.data"}, result) do
    {:ok, result}
  end
end
```

### Understanding Server Configuration

The `start_link/1` function configures several key aspects:

```elixir
def start_link(opts) do
  Jido.Agent.Server.start_link(
    # Required configuration
    id: opts[:id],          # Unique process identifier
    agent: __MODULE__,      # The agent module itself

    # Execution configuration
    mode: :auto,            # :auto or :manual execution
    log_level: :debug,      # Logging verbosity
    max_queue_size: 1000,   # Maximum pending signals

    # Communication setup
    routes: [              # Signal routing rules
      {"pattern.match", instruction}
    ],
    dispatch: {:logger, []}, # Output configuration

    # Process management
    registry: MyApp.Registry,  # Process registry
    sensors: [...],           # Background processes
    skills: [...]            # Additional capabilities
  )
end
```

For more details on configuration options, see [Agent Directives](directives.md).

### Signal Processing Flow

1. **Signal Reception**: Signals arrive via cast/call
2. **Pattern Matching**: Signal matched against routes
3. **Instruction Generation**: Matched routes create instructions
4. **Execution**: Instructions processed by runner
5. **Result Handling**: Results processed through callbacks

For more details on signal routing and processing, see [Signal Routing](../signals/routing.md) and [Signal Dispatching](../signals/dispatching.md).

### Interacting with Stateful Agents

```elixir
# Start the agent under supervision
children = [
  {MyApp.StatefulAgent, [id: "agent_1"]}
]
Supervisor.start_link(children, strategy: :one_for_one)

# Send signals to the agent
signal = %{
  type: "process.data",
  data: %{value: 42}
} |> Signal.new!()

# Synchronous call
{:ok, result} = MyApp.StatefulAgent.call("agent_1", signal)

# Asynchronous cast
{:ok, signal_id} = MyApp.StatefulAgent.cast("agent_1", signal)
```

### Lifecycle Callbacks

Implement OTP callbacks for lifecycle management:

```elixir
defmodule MyApp.StatefulAgent do
  use Jido.Agent, name: "lifecycle_agent"

  # Initialization
  def mount(state, _opts) do
    {:ok, state}
  end

  # Clean shutdown
  def shutdown(state, reason) do
    {:ok, state}
  end

  # Code upgrades
  def code_change(state, old_vsn, extra) do
    {:ok, state}
  end
end
```

For more details on agent callbacks and lifecycle management, see [Agent Callbacks](callbacks.md).

### Signal Handling

Customize signal processing through callbacks:

```elixir
defmodule MyApp.StatefulAgent do
  use Jido.Agent, name: "signal_processor"

  # Transform incoming signals
  def handle_signal(%Signal{type: "custom.event"} = signal) do
    transformed_data = transform_data(signal.data)
    {:ok, %Signal{signal | data: transformed_data}}
  end

  # Process execution results
  def transform_result(%Signal{type: "custom.event"}, result) do
    {:ok, process_output(result)}
  end
end
```

## Advanced Patterns

### Dynamic Route Configuration

```elixir
def start_link(opts) do
  routes = [
    # Basic pattern matching
    {"event.basic", basic_instruction()},

    # With parameters
    {"event.params.*", parameterized_instruction()},

    # Complex matching
    {fn signal ->
      String.starts_with?(signal.type, "custom.")
    end, dynamic_instruction()}
  ]

  Jido.Agent.Server.start_link(
    id: opts[:id],
    agent: __MODULE__,
    routes: routes
  )
end
```

### State Management

```elixir
defmodule MyApp.StatefulAgent do
  use Jido.Agent,
    name: "state_manager",
    schema: [
      status: [type: :atom, values: [:idle, :processing]],
      data: [type: :map, default: %{}]
    ]

  def handle_signal(%Signal{type: "update.state"} = signal) do
    # State updates handled by server
    {:ok, signal}
  end
end

# Update state
{:ok, _} = MyApp.StatefulAgent.set("agent_1", %{
  status: :processing,
  data: %{started_at: DateTime.utc_now()}
})
```

### Integration with Skills

Skills extend agent capabilities:

```elixir
defmodule MyApp.Skills.DataProcessor do
  use Jido.Skill,
    name: "data_processor",
    signals: %{
      input: ["data.process.*"],
      output: ["data.processed.*"]
    }

  def handle_signal(%Signal{} = signal) do
    {:ok, signal}
  end

  def transform_result(_signal, result) do
    {:ok, result}
  end
end

defmodule MyApp.StatefulAgent do
  use Jido.Agent, name: "skilled_agent"

  def start_link(opts) do
    Jido.Agent.Server.start_link(
      id: opts[:id],
      agent: __MODULE__,
      skills: [MyApp.Skills.DataProcessor]
    )
  end
end
```

### Background Processing with Sensors

Sensors provide background processing:

```elixir
defmodule MyApp.Sensors.Monitor do
  use Jido.Sensor,
    name: "system_monitor"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    schedule_check()
    {:ok, opts}
  end

  def handle_info(:check, state) do
    # Perform monitoring
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, 5000)
  end
end
```

For more details on implementing sensors, see [Agent Sensors](sensors.md).

defmodule MyApp.StatefulAgent do
use Jido.Agent, name: "monitored_agent"

def start_link(opts) do
Jido.Agent.Server.start_link(
id: opts[:id],
agent: **MODULE**,
sensors: [{MyApp.Sensors.Monitor, []}]
)
end
end

````

## Best Practices

1. **Process Registration**

   - Use meaningful, unique IDs
   - Consider namespacing for large systems
   - Implement consistent naming conventions

2. **Signal Design**

   - Use hierarchical signal types
   - Include necessary context in data
   - Consider signal versioning

3. **Error Handling**

   - Implement proper supervision
   - Use descriptive error returns
   - Consider retry strategies

4. **State Management**
   - Keep state minimal
   - Validate state transitions
   - Consider persistence needs

## Anti-Patterns to Avoid

1. **Direct State Mutation**

   - Don't bypass signal system
   - Avoid direct GenServer calls
   - Use proper state update mechanisms

2. **Complex Signal Processing**

   - Keep signal handling simple
   - Move complex logic to actions
   - Use skills for extensions

3. **Blocking Operations**
   - Avoid long-running handlers
   - Use async processing
   - Consider task supervision

## Testing Strategies

```elixir
defmodule MyApp.StatefulAgentTest do
  use ExUnit.Case

  setup do
    start_supervised!({MyApp.StatefulAgent, [id: "test_agent"]})
    :ok
  end

  test "processes signals correctly" do
    signal = Signal.new!(%{
      type: "test.event",
      data: %{value: 42}
    })

    assert {:ok, result} = MyApp.StatefulAgent.call("test_agent", signal)
    assert result.processed == true
  end
end
````

For comprehensive testing strategies and patterns, see [Signal Testing](../signals/testing.md).

## See Also

- [Signal Overview](../signals/overview.livemd)
- [Agent Overview](overview.md)
- [Agent Routing](routing.md)
- [Agent Output Configuration](output.md)
- [Child Processes](child-processes.md)
- [Runtime Configuration](runtime.md)

This implementation pattern provides a robust foundation for building distributed, stateful workflows while leveraging Elixir's OTP capabilities.
