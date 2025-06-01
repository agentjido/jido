# Executing Actions with Workflows

## Overview

The Jido `Workflow` module provides a robust execution engine for running Actions. It handles parameter validation, error handling, timeouts, retries, and telemetry - giving you a production-ready foundation for executing Actions in your agent systems.

## Basic Usage

The `Workflow.run/4` function can accept either Action parameters or an Instruction struct. Instructions provide a way to encapsulate the complete execution context for an Action. See the [Instructions guide](instructions.md) for more details on working with Instructions.

```elixir
# Using an Action module directly
{:ok, result} = Workflow.run(MyAction, %{param1: "value"})

# Using an Instruction struct
instruction = %Instruction{
  action: MyAction,
  params: %{param1: "value"},
  context: %{user_id: 123},
  opts: [timeout: 10_000]
}
{:ok, result} = Workflow.run(instruction)

# Basic module execution
{:ok, result} = Workflow.run(MyAction, %{param1: "value"})

# Basic execution
{:ok, result} = Workflow.run(MyAction, %{param1: "value"})

# With context
{:ok, result} = Workflow.run(MyAction, %{param1: "value"}, %{user_id: 123})

# With options
{:ok, result} = Workflow.run(MyAction, %{param1: "value"}, %{}, timeout: 10_000)
```

## Parameters

The `run/4` function accepts:

```elixir
# With Action module:
Workflow.run(action, params \\ %{}, context \\ %{}, opts \\ [])

# With Instruction struct:
Workflow.run(%Instruction{} = instruction)
```

- `action` - The Action module to execute
- `params` - Map of parameters for the Action (validated against schema)
- `context` - Additional context data passed to the Action
- `opts` - Execution options (see below)

## Execution Options

### Timeouts

By default, Actions have a 30 second timeout. You can customize this globally or per-action:

```elixir
# Global configuration (in config.exs)
config :jido, default_timeout: 60_000  # 60 seconds

# Disable timeout completely
Workflow.run(MyAction, %{}, %{}, timeout: 0)

# Set custom timeout (in milliseconds)
Workflow.run(MyAction, %{}, %{}, timeout: 10_000) # 10 seconds
```

### Retries

Actions support automatic retries with exponential backoff:

```elixir
# Configure max retries and initial backoff
Workflow.run(MyAction, %{}, %{},
  max_retries: 3,          # Maximum retry attempts (default: 1)
  backoff: 250            # Initial backoff in ms, doubles each retry (default: 250)
)
```

The backoff duration doubles after each retry, up to a maximum of 30 seconds.

### Telemetry

Actions emit telemetry events for monitoring. You can control the level of detail:

```elixir
# Full telemetry (default)
Workflow.run(MyAction, %{}, %{}, telemetry: :full)

# Basic telemetry
Workflow.run(MyAction, %{}, %{}, telemetry: :minimal)

# Disable telemetry
Workflow.run(MyAction, %{}, %{}, telemetry: :silent)
```

## Asynchronous Execution

For long-running Actions, you can execute them asynchronously:

```elixir
# Start async execution
async_ref = Workflow.run_async(MyAction, params)

# Do other work...

# Wait for result
{:ok, result} = Workflow.await(async_ref)

# Wait with timeout
{:ok, result} = Workflow.await(async_ref, 10_000)

# Cancel execution
:ok = Workflow.cancel(async_ref)
```

### Task Supervision

Async Actions run under a Task Supervisor, providing:

- Automatic process cleanup
- Crash isolation
- Timeout handling
- Cancellation support

The Jido framework starts a Task Supervisor by default. You can customize this by setting the `task_supervisor` option:

```elixir
# In your application.ex
children = [
  {Task.Supervisor, name: MyApp.TaskSupervisor}
]

# Configure Jido to use your supervisor
config :jido,
  task_supervisor: MyApp.TaskSupervisor
```

## Error Handling

Actions should use standard `{:ok, result}` and `{:error, error}` tuples for consistent error handling:

```elixir
case Workflow.run(MyAction, params) do
  {:ok, result} ->
    # Success case
    handle_success(result)

  {:error, %Error{type: :timeout}} ->
    # Timeout error
    handle_timeout()

  {:error, %Error{type: :validation_error}} ->
    # Parameter validation failed
    handle_validation_error()

  {:error, error} ->
    # Other error cases
    handle_error(error)
end
```

Common error types:

- `:timeout` - Action exceeded timeout duration
- `:validation_error` - Invalid parameters
- `:execution_error` - Runtime error in Action
- `:compensation_error` - Error during compensation

## Compensation

Actions can define compensation logic that runs on failure:

```elixir
defmodule MyAction do
  use Jido.Action,
    name: "my_action",
    compensation: [
      enabled: true,           # Enable compensation
      max_retries: 3,          # Retry compensation attempts
      timeout: 5000           # Compensation timeout
    ]

  def on_error(failed_params, error, context, opts) do
    # Compensation logic here
    rollback_changes(failed_params)
  end
end
```

## Best Practices

1. **Always Set Timeouts**

   - Use explicit timeouts for Actions
   - Consider the Action's expected duration
   - Allow extra time for retries

2. **Handle All Error Cases**

   - Pattern match on specific error types
   - Provide descriptive error messages
   - Consider using compensation for cleanup

3. **Use Async for Long-Running Actions**

   - Move expensive operations to async execution
   - Set appropriate timeouts
   - Handle cancellation gracefully

4. **Monitor with Telemetry**
   - Enable full telemetry in production
   - Track execution times and error rates
   - Set up alerts for timeout/error thresholds

## Testing

The `Workflow` module provides testing utilities:

```elixir
defmodule MyActionTest do
  use ExUnit.Case

  test "executes successfully" do
    {:ok, result} = Workflow.run(MyAction, test_params())
    assert result.status == :success
  end

  test "handles timeout" do
    {:error, error} = Workflow.run(MyAction, %{}, %{}, timeout: 1)
    assert error.type == :timeout
  end

  test "validates params" do
    {:error, error} = Workflow.run(MyAction, %{invalid: true})
    assert error.type == :validation_error
  end
end
```

## See Also

- `Jido.Action` - Action behavior and implementation
- `Jido.Instruction` - Working with Instructions and execution context
- `Jido.Runner` - Action execution strategies
- `Jido.Error` - Error handling and compensation
- `Jido.Telemetry` - Monitoring and metrics
