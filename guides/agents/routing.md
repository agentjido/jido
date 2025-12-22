# Agent Routing

## Overview

Agent routing in Jido provides a flexible mechanism for directing signals to agents and handling their responses. While agents have predefined command signal types for core operations, they primarily interact through a generic `call/cast` interface that supports custom signal routing.

## Core Concepts

- **Signal Types**: Predefined and custom message formats
- **Call/Cast Interface**: Synchronous and asynchronous messaging
- **Router Configuration**: Pattern-based signal routing
- **Signal Dispatch**: Configurable output handling

## Default Signal Types

Jido provides default command signal types for core agent operations:

```elixir
# Server-defined command signals
@cmd_state "jido.agent.cmd.state"         # Get agent state
@cmd_queue_size "jido.agent.cmd.queuesize" # Check queue size
@cmd_set "jido.agent.cmd.set"             # Update agent state
@cmd_validate "jido.agent.cmd.validate"    # Validate agent state
@cmd_plan "jido.agent.cmd.plan"           # Plan new actions
@cmd_run "jido.agent.cmd.run"             # Execute pending actions
@cmd_cmd "jido.agent.cmd.cmd"             # Combined plan+run
```

## Call/Cast Interface

The primary method for interacting with agents is through the `call/cast` interface:

```elixir
# Synchronous call (waits for response)
def call(agent, signal, timeout \\ 5000) do
  with {:ok, pid} <- Jido.resolve_pid(agent) do
    case GenServer.call(pid, {:signal, signal}, timeout) do
      {:ok, response} -> {:ok, response}
      other -> other
    end
  end
end

# Asynchronous cast (fire and forget)
def cast(agent, signal) do
  with {:ok, pid} <- Jido.resolve_pid(agent) do
    GenServer.cast(pid, {:signal, signal})
    {:ok, signal.id}
  end
end
```

### Using Call/Cast

```elixir
# Create a signal
signal = %Signal{
  type: "custom.event",
  data: %{value: 42}
}

# Synchronous request (waits for response)
{:ok, result} = MyAgent.call(agent, signal)

# Asynchronous request (returns immediately)
{:ok, signal_id} = MyAgent.cast(agent, signal)
```

## Router Configuration

Agents use the `Jido.Signal.Router` module to handle signal routing. Routers can be configured with pattern-based routes:

```elixir
# Configure agent with routes by overriding start_link
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent"

  def start_link(opts \\ []) do
    # Define routes for the agent
    routes = [
      {"custom.event", HandleCustomEvent},
      {"metrics.*", CollectMetrics},
      {"audit.**", AuditLog}
    ]

    # Pass routes to Agent.Server.start_link
    opts = Keyword.merge(opts, [routes: routes])
    Agent.Server.start_link(opts)
  end
end

# Add routes at runtime
{:ok, agent} = Server.Router.add(agent, [
  {"user.created", HandleUserCreated},
  {"payment.processed", HandlePayment}
])
```

See the [Signal Routing](signals/routing.md) guide for detailed pattern matching syntax.

## Signal Dispatch and Response Correlation

Agents handle signal dispatch configuration and response correlation through a robust mechanism that ensures message traceability.

### Dispatch Configuration

Dispatch options must be configured by overriding the agent's `start_link` function:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent"

  def start_link(opts \\ []) do
    # Configure dispatch options
    dispatch_opts = [
      {:pubsub, [topic: "events"]},
      {:logger, [level: :info]}
    ]

    opts = Keyword.merge(opts, [dispatch: dispatch_opts])
    Agent.Server.start_link(opts)
  end
end
```

### Response Correlation

When an agent processes a signal and broadcasts responses, it automatically correlates responses with the originating request by:

1. Setting the response's `source` field to the original signal's `id`
2. Maintaining the correlation through broadcast chains
3. Enabling response tracking and request-response mapping

```elixir
# Original request signal
request = %Signal{
  id: "req_123",
  type: "get.user.data",
  data: %{user_id: "456"}
}

# Response signal (automatically correlated)
response = %Signal{
  id: "resp_789",
  type: "user.data.retrieved",
  source: "req_123",  # References original request ID
  data: %{user: user_data}
}
```

This correlation mechanism enables:

- Request-response tracking
- Response aggregation
- Event chain reconstruction
- Debugging and monitoring

See the [Signal Output](agents/output.md) guide for detailed information about signal response handling and output patterns.

## Best Practices

### 1. Signal Design

- Use consistent naming patterns for signal types
- Include relevant context in signal data
- Consider response format requirements

```elixir
# Good signal design
signal = %Signal{
  type: "order.payment.processed",
  source: "/payments",
  data: %{
    order_id: "123",
    amount: 99.99,
    currency: "USD"
  }
}
```

### 2. Route Organization

- Group related routes together
- Use specific routes before wildcards
- Document routing patterns

```elixir
# Organized routes with priority
routes = [
  # High priority exact matches
  {"payment.processed", HandlePayment},

  # Domain-specific patterns
  {"order.*.updated", HandleOrderUpdate},

  # Catch-all audit logging
  {"audit.**", AuditLog}
]
```

### 3. Error Handling

- Implement comprehensive error handling
- Use timeouts appropriately
- Log routing failures

```elixir
def handle_payment(signal) do
  case MyAgent.call(agent, signal, timeout: 10_000) do
    {:ok, result} ->
      handle_success(result)

    {:error, :timeout} ->
      handle_timeout(signal)

    {:error, reason} ->
      log_error(signal, reason)
  end
end
```

## Common Patterns

### 1. Request-Response

```elixir
alias Jido.Signal.DispatchHelpers

# Client sends request
{:ok, request} = Signal.new(%{
  type: "get.user.profile",
  data: %{user_id: "123"},
  source: "/client"
})
{:ok, request} = DispatchHelpers.put_dispatch(request, {:pid, [target: self()]})

{:ok, response} = MyAgent.call(agent, request)
```

### 2. Event Broadcasting

```elixir
alias Jido.Signal.DispatchHelpers

# Broadcast event to multiple subscribers
{:ok, event} = Signal.new(%{
  type: "user.registered",
  data: %{user_id: "123"},
  source: "/users"
})
{:ok, event} = DispatchHelpers.put_dispatch(event, [
  {:pubsub, [topic: "users"]},
  {:bus, [stream: "audit"]}
])

MyAgent.cast(agent, event)
```

### 3. Chain Processing

```elixir
# Chain multiple agents
process_order = fn order ->
  with {:ok, validated} <- ValidatorAgent.call(order),
       {:ok, processed} <- ProcessorAgent.call(validated),
       {:ok, _stored} <- StorageAgent.call(processed) do
    {:ok, :completed}
  end
end
```

## Testing

```elixir
defmodule AgentRoutingTest do
  use ExUnit.Case

  test "routes signals correctly" do
    signal = %Signal{type: "test.event", data: %{value: 42}}

    # Test synchronous routing
    assert {:ok, result} = MyAgent.call(agent, signal)
    assert result.processed == true

    # Test async routing
    assert {:ok, _id} = MyAgent.cast(agent, signal)
    assert_receive {:signal, response}, 1000
  end

  test "handles routing errors" do
    bad_signal = %Signal{type: "invalid"}
    assert {:error, _} = MyAgent.call(agent, bad_signal)
  end
end
```

## See Also

- [Signal Overview](signals/overview.md)
- [Signal Routing](signals/routing.md)
- [Signal Dispatching](signals/dispatching.md)
- [Signal Bus](signals/bus.md)
