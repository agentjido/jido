# Testing Agents

This guide covers comprehensive testing strategies for Jido Agents using the `JidoTest.AgentCase` DSL, including agent lifecycle testing, state management, signal processing, and queue management.

## Quick Start

To use the AgentCase DSL in your tests:

```elixir
defmodule MyApp.Agents.UserAgentTest do
  use JidoTest.Case, async: true
  use JidoTest.AgentCase

  alias MyApp.Agents.UserAgent

  test "user registration workflow" do
    spawn_agent(UserAgent)
    |> assert_agent_state(status: :idle, users: [])
    |> send_signal_sync("user.register", %{name: "John", email: "john@example.com"})
    |> assert_agent_state(users: [%{name: "John", email: "john@example.com"}])
    |> assert_queue_empty()
  end
end
```

## Core Testing Principles

When testing Agents, focus on:

1. **State Management** - Verify state changes correctly
2. **Signal Processing** - Test signal routing and handling  
3. **Queue Management** - Ensure signals are queued and processed properly
4. **Agent Lifecycle** - Test startup, shutdown, and error states
5. **Concurrency** - Verify proper behavior under load

## AgentCase DSL Functions

### Agent Lifecycle

#### `spawn_agent/2`

Spawns an agent for testing with automatic cleanup:

```elixir
# Basic agent spawn
context = spawn_agent()

# Custom agent type
context = spawn_agent(MyCustomAgent)

# With options
context = spawn_agent(MyAgent, mode: :auto, registry: MyRegistry)
```

### Signal Processing

#### `send_signal_async/3`

Sends signals asynchronously without waiting for processing:

```elixir
spawn_agent()
|> send_signal_async("user.created", %{id: 123, name: "John"})
|> send_signal_async("email.send", %{to: "john@example.com"})
|> assert_queue_size(2)  # Signals may be queued
```

#### `send_signal_sync/3`

Sends signals synchronously and waits for the agent to return to idle state:

```elixir
spawn_agent()
|> send_signal_sync("user.process", %{id: 123})
|> assert_agent_state(processed_users: 1)
|> assert_queue_empty()  # Processing completed
```

### State Management

#### `get_agent_state/1`

Gets the current agent state:

```elixir
context = spawn_agent()
state = get_agent_state(context)

assert state.location == :home
assert state.battery_level == 100
```

#### `assert_agent_state/2`

Asserts that agent state matches expected values:

```elixir
# Using keyword list
spawn_agent()
|> assert_agent_state(location: :office, battery_level: 75)

# Using map
spawn_agent()
|> assert_agent_state(%{status: :active, user_count: 5})

# Partial state checking
spawn_agent()
|> assert_agent_state(status: :active)  # Only checks status field
```

#### `wait_for_agent_status/3`

Waits for an agent to reach a specific status:

```elixir
spawn_agent()
|> send_signal_async("start.processing")
|> wait_for_agent_status(:processing, timeout: 2000)
|> send_signal_sync("complete.processing")
|> wait_for_agent_status(:idle)
```

### Queue Management

#### `assert_queue_empty/1`

Asserts that the agent's signal queue is empty:

```elixir
spawn_agent()
|> send_signal_sync("process.all")
|> assert_queue_empty()
```

#### `assert_queue_size/2`

Asserts that the agent's signal queue has the expected size:

```elixir
spawn_agent()
|> send_signal_async("task.1")
|> send_signal_async("task.2") 
|> assert_queue_size(2)
```

## Testing Patterns

### Basic Agent Testing

```elixir
defmodule MyApp.Agents.CounterAgentTest do
  use JidoTest.Case, async: true
  use JidoTest.AgentCase

  alias MyApp.Agents.CounterAgent

  describe "counter operations" do
    test "increments counter" do
      spawn_agent(CounterAgent)
      |> assert_agent_state(count: 0)
      |> send_signal_sync("increment", %{amount: 5})
      |> assert_agent_state(count: 5)
    end

    test "handles multiple increments" do
      spawn_agent(CounterAgent)
      |> send_signal_async("increment", %{amount: 1})
      |> send_signal_async("increment", %{amount: 2})
      |> send_signal_async("increment", %{amount: 3})
      |> assert_queue_size(3)
      |> send_signal_sync("process_queue")
      |> assert_agent_state(count: 6)
      |> assert_queue_empty()
    end
  end
end
```

### Error Handling

```elixir
describe "error handling" do
  test "handles invalid signals gracefully" do
    spawn_agent()
    |> send_signal_async("invalid.signal", %{})
    |> assert_agent_state(status: :idle)  # Agent should remain stable
  end

  test "recovers from processing errors" do
    spawn_agent()
    |> send_signal_sync("cause.error", %{})
    |> assert_agent_state(error_count: 1, status: :idle)
    |> send_signal_sync("normal.operation", %{})
    |> assert_agent_state(status: :idle)
  end
end
```

### State Transitions

```elixir
describe "state transitions" do  
  test "transitions through expected states" do
    spawn_agent(WorkflowAgent)
    |> assert_agent_state(status: :idle)
    |> send_signal_async("start.workflow")
    |> wait_for_agent_status(:processing)
    |> send_signal_sync("complete.step", %{step: 1})
    |> assert_agent_state(current_step: 1)
    |> send_signal_sync("finish.workflow")
    |> wait_for_agent_status(:completed)
  end
end
```

### Concurrent Signal Processing

```elixir
describe "concurrency" do
  test "handles multiple signals concurrently" do
    agent = spawn_agent(BatchProcessor, mode: :auto)
    
    # Send multiple signals rapidly
    Enum.each(1..10, fn i ->
      send_signal_async(agent, "process.item", %{id: i})
    end)
    
    # Wait for processing to complete and verify results
    agent
    |> wait_for_agent_status(:idle, timeout: 5000)
    |> assert_agent_state(processed_count: 10)
    |> assert_queue_empty()
  end
end
```

### Custom Agent Setup

For agents requiring custom initial state:

```elixir
test "works with custom initial state" do
  # Create agent manually when spawn_agent doesn't support custom state
  agent = MyAgent.new("test_agent", %{initial_balance: 1000})
  
  {:ok, server_pid} = Jido.Agent.Server.start_link(
    agent: agent,
    id: agent.id,
    mode: :step,
    registry: Jido.Registry
  )
  
  context = %{agent: agent, server_pid: server_pid}
  
  # Cleanup
  ExUnit.Callbacks.on_exit(fn ->
    if Process.alive?(server_pid) do
      GenServer.stop(server_pid, :normal, 1000)
    end
  end)
  
  # Test with custom state
  context
  |> assert_agent_state(balance: 1000)
  |> send_signal_sync("deposit", %{amount: 500})
  |> assert_agent_state(balance: 1500)
end
```

## Best Practices

### 1. Use Pipeline Style

Chain operations using the pipeline operator for readability:

```elixir
# Good
spawn_agent()
|> assert_agent_state(count: 0)
|> send_signal_sync("increment")
|> assert_agent_state(count: 1)

# Avoid
context = spawn_agent()
assert_agent_state(context, count: 0)
send_signal_sync(context, "increment")
assert_agent_state(context, count: 1)
```

### 2. Test Both Sync and Async

Test both synchronous and asynchronous signal processing:

```elixir
describe "signal processing modes" do
  test "async signals are queued" do
    spawn_agent()
    |> send_signal_async("task.1")
    |> send_signal_async("task.2")
    |> assert_queue_size(2)
  end
  
  test "sync signals wait for completion" do
    spawn_agent()
    |> send_signal_sync("task.1")
    |> assert_queue_empty()  # Processing completed
  end
end
```

### 3. Verify Queue States

Always verify queue states when testing signal processing:

```elixir
test "queue management" do
  spawn_agent()
  |> assert_queue_empty()           # Start empty
  |> send_signal_async("task")      
  |> assert_queue_size(1)           # Signal queued
  |> send_signal_sync("process")    
  |> assert_queue_empty()           # Processing complete
end
```

### 4. Test Error Conditions  

Include tests for error scenarios:

```elixir
describe "error conditions" do
  test "handles dead processes gracefully" do
    context = spawn_agent()
    GenServer.stop(context.server_pid, :normal)
    Process.sleep(10)
    
    assert_raise RuntimeError, "Agent process is not alive", fn ->
      get_agent_state(context)
    end
  end
end
```

### 5. Group Tests by Function

Organize tests by the functions being tested:

```elixir
describe "assert_agent_state/2" do
  test "validates with maps"
  test "validates with keyword lists"  
  test "validates partial state"
  test "fails with meaningful errors"
end

describe "assert_queue_size/2" do
  test "verifies queue size"
  test "provides error messages"
end
```

## Advanced Testing

### Property-Based Testing

Use property-based testing for complex agent behaviors:

```elixir
use ExUnitProperties

property "counter always increases with positive increments" do
  check all increment <- positive_integer() do
    result = 
      spawn_agent(CounterAgent)
      |> send_signal_sync("increment", %{amount: increment})
      |> get_agent_state()
    
    assert result.count == increment
  end
end
```

### Load Testing

Test agent performance under load:

```elixir
@tag :load_test
test "handles high signal volume" do
  agent = spawn_agent(HighVolumeAgent, mode: :auto)
  
  # Send 1000 signals
  signals = Enum.map(1..1000, fn i -> {"process", %{id: i}} end)
  
  start_time = System.monotonic_time(:millisecond)
  
  Enum.each(signals, fn {type, data} ->
    send_signal_async(agent, type, data)
  end)
  
  # Verify processing completed and performance
  agent
  |> wait_for_agent_status(:idle, timeout: 30_000)
  |> assert_agent_state(processed_count: 1000)
  
  end_time = System.monotonic_time(:millisecond)
  assert end_time - start_time < 10_000  # Under 10 seconds
end
```

## Integration with Other Components

### Testing with Sensors

```elixir
test "agent responds to sensor signals" do
  {:ok, sensor_pid} = MySensor.start_link(target: agent_context.server_pid)
  
  # Trigger sensor
  send(sensor_pid, :trigger)
  
  # Verify agent received and processed signal
  agent_context
  |> wait_for_agent_status(:processing)
  |> assert_agent_state(sensor_data_received: true)
end
```

### Testing with Actions

```elixir
test "agent executes actions correctly" do
  spawn_agent(ActionAgent)
  |> send_signal_sync("execute.action", %{
    action: MyAction,
    params: %{value: 42}
  })
  |> assert_agent_state(last_action_result: %{status: :success, value: 42})
end
```

## Troubleshooting

### Common Issues

1. **Race Conditions**: Use `send_signal_sync` instead of `send_signal_async` when order matters
2. **Queue Not Empty**: Agents in `:step` mode may queue signals - use appropriate assertions
3. **Process Not Alive**: Ensure proper cleanup in test setup/teardown
4. **Timeout Errors**: Increase timeout for slow operations

### Debugging Tips

```elixir
# Log agent state for debugging
test "debug agent state" do
  context = spawn_agent()
  state = get_agent_state(context)
  IO.inspect(state, label: "Agent State")
  
  # Continue with test...
end
```

This comprehensive testing approach ensures your Jido agents work correctly in all scenarios and maintain reliability in production environments.