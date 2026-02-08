# Error Handling

**After:** You can handle errors consistently across actions, directives, and signal processing.

Jido provides structured error handling across the agent lifecycle, from action execution to directive processing. All errors use a unified system built on [Splode](https://hexdocs.pm/splode) for consistent error classification and aggregation.

## Error Types

### Jido.Error

The core error module provides six consolidated error types:

| Error | Use Case |
|-------|----------|
| `ValidationError` | Invalid inputs, actions, sensors, configs |
| `ExecutionError` | Runtime failures during execution or planning |
| `RoutingError` | Signal routing and dispatch failures |
| `TimeoutError` | Operation timeouts |
| `CompensationError` | Saga compensation failures |
| `InternalError` | Unexpected system failures |

#### Creating Errors

```elixir
alias Jido.Error

# Validation errors (with optional kind)
Error.validation_error("Invalid email", field: :email)
Error.validation_error("Unknown action", kind: :action, action: MyAction)
Error.validation_error("Bad config", kind: :config, details: %{key: :timeout})

# Execution errors (with optional phase)
Error.execution_error("Action failed", phase: :execution)
Error.execution_error("Planning failed", phase: :planning)

# Routing/dispatch errors
Error.routing_error("No handler found", target: "user.created")

# Timeout errors
Error.timeout_error("Operation timed out", timeout: 5000)

# Compensation errors (saga rollbacks)
Error.compensation_error("Rollback failed", 
  original_error: original, 
  compensated: false
)

# Internal errors
Error.internal_error("Unexpected failure", details: %{module: MyModule})
```

#### Error Struct Fields

Each error type includes specific fields:

```elixir
%Jido.Error.ValidationError{
  message: "Invalid email format",
  kind: :input,           # :input | :action | :sensor | :config
  subject: :email,        # The invalid value or field
  details: %{}
}

%Jido.Error.ExecutionError{
  message: "Action failed",
  phase: :execution,      # :execution | :planning
  details: %{}
}

%Jido.Error.RoutingError{
  message: "No handler",
  target: "user.created", # Intended routing target
  details: %{}
}
```

### Directive.Error

The `Directive.Error` struct wraps errors for directive-based processing. Agents emit this directive from `cmd/2` when errors occur during command handling.

```elixir
alias Jido.Agent.Directive

# Create an error directive
Directive.error(Jido.Error.validation_error("Invalid input"))

# With context (where the error occurred)
Directive.error(error, :normalize)
Directive.error(error, :instruction)
```

The `context` field indicates where the error originated:
- `:normalize` — Error during signal normalization
- `:instruction` — Error during action instruction execution
- `:fsm_transition` — Error during FSM state transition
- `:routing` — Error during signal routing
- `:plugin_handle_signal` — Error in plugin signal handler

## Action Errors

Actions return tagged tuples. Return `{:error, reason}` for failures:

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    name: "process_order",
    schema: [
      order_id: [type: :string, required: true]
    ]

  def run(params, context) do
    case validate_order(params.order_id) do
      {:ok, order} ->
        {:ok, %{processed: order}}

      {:error, :not_found} ->
        {:error, Jido.Error.validation_error(
          "Order not found",
          field: :order_id,
          details: %{order_id: params.order_id}
        )}

      {:error, :insufficient_stock} ->
        {:error, Jido.Error.execution_error(
          "Insufficient stock",
          phase: :execution,
          details: %{order_id: params.order_id}
        )}
    end
  end
end
```

### Validation Errors in Actions

Schema validation errors are automatically wrapped:

```elixir
# When required params are missing or invalid types,
# Jido returns a ValidationError automatically
{:error, %Jido.Error.ValidationError{
  message: "Invalid parameters for action (MyApp.Actions.ProcessOrder) at [:order_id]: required"
}}
```

## Error Propagation

Errors flow through the system in a predictable manner:

### 1. Action → Agent

When an action fails, the agent's strategy wraps it in an `Error` directive:

```elixir
# Inside agent cmd/2, if action fails:
{agent, [%Directive.Error{error: error, context: :instruction}]}
```

### 2. Agent → AgentServer

The AgentServer receives directives from `cmd/2` and executes them. Error directives are handled by the configured error policy.

### 3. AgentServer → Error Policy

The `ErrorPolicy` module determines what happens with errors based on configuration.

## Not Found Convention

Jido uses a single explicit not-found contract across runtime and storage layers:

- `{:error, :not_found}`

Examples:

- Runtime/process APIs: `Jido.AgentServer.call/3`, `Jido.Agent.InstanceManager.lookup/2`
- Storage/persistence APIs: `c:Jido.Storage.get_checkpoint/2`, `c:Jido.Storage.load_thread/2`, `Jido.Persist.thaw/3`

## Raise vs Return Policy

Jido follows this rule:

- Return `{:error, ...}` for runtime failures and user/data validation failures.
- Raise for programmer/setup errors (invalid API usage, missing required opts) and `!` APIs by convention.

In short: if the caller can recover at runtime, return an error tuple; if it indicates a coding/config contract violation, raise.

## Thread Store Contract

`Jido.Thread.Store` uses a pure state-threading contract:

- `{:ok, store, value}`
- `{:error, store, reason}`

The second element is always the updated store state and must be threaded by callers, even on errors.

## Error Policies

Configure how the AgentServer handles error directives:

```elixir
# In AgentServer.start_link options:
AgentServer.start_link(
  agent: MyAgent,
  error_policy: :log_only,  # or other policies
  jido: jido
)
```

### Available Policies

| Policy | Behavior |
|--------|----------|
| `:log_only` | Log the error and continue processing |
| `:stop_on_error` | Log and stop the agent process |
| `{:max_errors, n}` | Stop after `n` errors |
| `{:emit_signal, dispatch_cfg}` | Emit an error signal via dispatch |
| `fun/2` | Custom function |

### Examples

```elixir
# Log errors but keep running (default)
error_policy: :log_only

# Stop on first error
error_policy: :stop_on_error

# Stop after 5 errors
error_policy: {:max_errors, 5}

# Emit error signals to a topic
error_policy: {:emit_signal, {:pubsub, topic: "errors"}}

# Custom error handler
error_policy: fn %Directive.Error{error: error, context: ctx}, state ->
  Logger.error("Custom handler: #{inspect(error)}")
  
  case ctx do
    :critical -> {:stop, {:error, error}, state}
    _ -> {:ok, state}
  end
end
```

### Custom Policy Function

Custom policies receive the error directive and server state, returning:
- `{:ok, state}` — Continue with updated state
- `{:stop, reason, state}` — Stop the agent

```elixir
error_policy: fn error_directive, state ->
  %Directive.Error{error: error, context: context} = error_directive
  
  # Track errors in state
  state = Jido.AgentServer.State.increment_error_count(state)
  
  if state.error_count > 10 do
    {:stop, :too_many_errors, state}
  else
    {:ok, state}
  end
end
```

## Error Utilities

### Converting Errors to Maps

```elixir
error = Jido.Error.validation_error("Bad input", field: :email)
map = Jido.Error.to_map(error)

# Returns:
%{
  type: :validation_error,
  message: "Bad input",
  details: %{},
  stacktrace: [...]
}
```

### Extracting Messages

```elixir
# Handle nested error structures
message = Jido.Error.extract_message(error)
```

## Testing Error Scenarios

### Testing Action Errors

```elixir
defmodule ProcessOrderTest do
  use ExUnit.Case, async: true

  alias MyApp.Actions.ProcessOrder

  test "returns validation error for missing order" do
    result = Jido.Action.run(ProcessOrder, %{order_id: "invalid"}, %{})
    
    assert {:error, %Jido.Error.ValidationError{} = error} = result
    assert error.message =~ "Order not found"
    assert error.kind == :input
  end
end
```

### Testing Error Directives in Agents

```elixir
defmodule MyAgentTest do
  use ExUnit.Case, async: true

  test "returns error directive for invalid action" do
    agent = MyAgent.new()

    {_agent, directives} = MyAgent.cmd(agent, {InvalidAction, %{}})

    assert [%Jido.Agent.Directive.Error{context: :instruction}] = directives
  end

  test "error includes original error struct" do
    agent = MyAgent.new()

    {_agent, [error_directive]} = MyAgent.cmd(agent, {FailingAction, %{}})

    assert %Jido.Agent.Directive.Error{error: error} = error_directive
    assert %Jido.Error.ExecutionError{} = error
  end
end
```

### Testing Error Policies

```elixir
defmodule ErrorPolicyTest do
  use JidoTest.Case, async: true

  test "max_errors policy stops agent after threshold", %{jido: jido} do
    {:ok, pid} = AgentServer.start_link(
      agent: MyAgent,
      error_policy: {:max_errors, 3},
      jido: jido
    )
    
    ref = Process.monitor(pid)

    # Send signals that cause errors
    for _ <- 1..3 do
      signal = Signal.new!("cause_error", %{}, source: "/test")
      AgentServer.cast(pid, signal)
    end

    assert_receive {:DOWN, ^ref, :process, ^pid, {:max_errors_exceeded, 3}}, 1000
  end

  test "log_only policy continues after errors", %{jido: jido} do
    {:ok, pid} = AgentServer.start_link(
      agent: MyAgent,
      error_policy: :log_only,
      jido: jido
    )

    # Send error-causing signal
    signal = Signal.new!("cause_error", %{}, source: "/test")
    AgentServer.cast(pid, signal)

    Process.sleep(50)
    assert Process.alive?(pid)
  end
end
```

### Capturing Error Logs

```elixir
import ExUnit.CaptureLog

test "logs error with agent context", %{jido: jido} do
  {:ok, pid} = AgentServer.start_link(
    agent: MyAgent,
    id: "error-test",
    error_policy: :log_only,
    jido: jido
  )

  log = capture_log(fn ->
    signal = Signal.new!("cause_error", %{}, source: "/test")
    AgentServer.cast(pid, signal)
    Process.sleep(50)
  end)

  assert log =~ "error-test"
  assert log =~ "Error"
end
```

## Cross-Package Error Mapping

Jido unifies errors from ecosystem packages. Errors from `jido_action` and `jido_signal` are automatically mapped to the unified type system:

| Package Error | Unified Type |
|---------------|--------------|
| `Jido.Action.Error.InvalidInputError` | `:validation_error` |
| `Jido.Action.Error.ExecutionFailureError` | `:execution_error` |
| `Jido.Action.Error.TimeoutError` | `:timeout` |
| `Jido.Signal.Error.RoutingError` | `:routing_error` |
| `Jido.Signal.Error.DispatchError` | `:routing_error` |

## Related

- [Core Loop](core-loop.md)
- [Directives](directives.md)
- [Testing](testing.md)
