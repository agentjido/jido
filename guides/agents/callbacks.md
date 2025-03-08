# Agent Callbacks

## Overview

Jido Agents provide a rich set of callbacks that allow you to customize behavior at key lifecycle points. These callbacks enable you to implement custom validation logic, manage state transitions, handle errors, and control execution flow.

## Core Callbacks

### Lifecycle Management

#### `mount/2`

Called when the agent server starts up. Use this callback to perform initialization tasks.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [status: [type: :atom]]

  def mount(state, _opts) do
    # Initialize connections, load configs, etc.
    {:ok, state}
  end
end
```

#### `shutdown/2`

Called when the agent server is stopping. Use this for cleanup tasks.

```elixir
def shutdown(state, reason) do
  Logger.info("Agent shutting down", reason: reason)
  cleanup_resources(state)
  {:ok, state}
end
```

### State Management

#### `on_before_validate_state/1`

Called before validating any state changes. Useful for preprocessing state attributes.

```elixir
def on_before_validate_state(agent) do
  # Preprocess state before validation
  updated_state = Map.update(agent.state, :status, :pending, fn
    nil -> :pending
    other -> other
  end)

  {:ok, %{agent | state: updated_state}}
end
```

#### `on_after_validate_state/1`

Called after state validation but before saving changes.

```elixir
def on_after_validate_state(agent) do
  # Post-process validated state
  if agent.state.status == :completed do
    {:ok, clear_temporary_data(agent)}
  else
    {:ok, agent}
  end
end
```

### Execution Control

#### `on_before_plan/3`

Called before planning actions. Allows preprocessing of instructions.

```elixir
def on_before_plan(agent, instructions, context) do
  # Add metadata to context
  enhanced_context = Map.put(context, :planned_at, DateTime.utc_now())

  case validate_instructions(instructions) do
    :ok -> {:ok, agent, enhanced_context}
    {:error, reason} -> {:error, reason}
  end
end
```

#### `on_before_run/1`

Called before executing planned actions.

```elixir
def on_before_run(agent) do
  case check_preconditions(agent) do
    :ok -> {:ok, agent}
    {:error, reason} -> {:error, reason}
  end
end
```

#### `on_after_run/3`

Called after action execution completes.

```elixir
def on_after_run(agent, result, unapplied_directives) do
  # Process execution results
  agent = update_execution_stats(agent, result)

  case length(unapplied_directives) do
    0 -> {:ok, agent}
    n -> Logger.warning("#{n} directives not applied")
         {:ok, agent}
  end
end
```

### Error Handling

#### `on_error/2`

Called when errors occur during execution.

```elixir
def on_error(agent, reason) do
  Logger.error("Agent error", error: reason)

  updated_agent = %{agent |
    state: %{agent.state | status: :error},
    result: %{error: reason}
  }

  {:ok, updated_agent}
end
```

### Signal Processing

#### `handle_signal/1`

Processes incoming signals before routing.

```elixir
def handle_signal(signal) do
  case validate_signal_format(signal) do
    :ok ->
      enhanced_signal = add_metadata(signal)
      {:ok, enhanced_signal}
    {:error, reason} ->
      {:error, reason}
  end
end
```

#### `transform_result/2`

Processes results before returning them.

```elixir
def transform_result(signal, result) do
  case result do
    {:ok, data} ->
      processed = transform_result(data)
      {:ok, processed}
    {:error, _} = error ->
      error
  end
end
```

## Common Patterns

### State Preprocessing

```elixir
defmodule PreprocessingAgent do
  use Jido.Agent,
    name: "preprocessing_agent",
    schema: [
      input: [type: :string],
      processed: [type: :string]
    ]

  def on_before_validate_state(agent) do
    # Ensure input is preprocessed before validation
    case agent.state do
      %{input: input, processed: nil} when not is_nil(input) ->
        processed = String.trim(input)
        {:ok, put_in(agent.state.processed, processed)}

      _ ->
        {:ok, agent}
    end
  end
end
```

### Execution Guards

```elixir
defmodule GuardedAgent do
  use Jido.Agent,
    name: "guarded_agent",
    schema: [status: [type: :atom]]

  def on_before_run(agent) do
    case agent.state.status do
      :ready ->
        {:ok, agent}

      :locked ->
        {:error, "Agent is locked"}

      other ->
        {:error, "Invalid status: #{other}"}
    end
  end
end
```

### Result Transformation

```elixir
defmodule TransformingAgent do
  use Jido.Agent,
    name: "transforming_agent"

  def transform_result(_signal, {:ok, result}) do
    transformed = %{
      data: result,
      processed_at: DateTime.utc_now(),
      format_version: "1.0"
    }

    {:ok, transformed}
  end

  def transform_result(_signal, {:error, _} = error), do: error
end
```

### Comprehensive Error Recovery

```elixir
defmodule RecoveringAgent do
  use Jido.Agent,
    name: "recovering_agent",
    schema: [
      status: [type: :atom],
      retry_count: [type: :integer, default: 0],
      last_error: [type: :map]
    ]

  def on_error(agent, reason) do
    agent = update_in(agent.state.retry_count, &(&1 + 1))

    if agent.state.retry_count <= 3 do
      # Attempt recovery
      {:ok, %{agent |
        state: %{agent.state |
          status: :retrying,
          last_error: %{
            reason: reason,
            timestamp: DateTime.utc_now()
          }
        }
      }}
    else
      # Give up after 3 retries
      {:ok, %{agent |
        state: %{agent.state |
          status: :failed
        }
      }}
    end
  end
end
```

## Best Practices

1. **Keep Callbacks Focused**

   - Each callback should have a single responsibility
   - Complex logic should be moved to private functions
   - Return values should be consistent

2. **Handle All Error Cases**

   - Use pattern matching for different error scenarios
   - Provide meaningful error messages
   - Consider implementing recovery strategies

3. **State Management**

   - Validate state changes thoroughly
   - Use schema validations for type safety
   - Keep state transitions explicit

4. **Performance Considerations**

   - Avoid blocking operations in callbacks
   - Keep preprocessing lightweight
   - Consider using Task for heavy operations

5. **Logging and Monitoring**
   - Log important state transitions
   - Include relevant context in logs
   - Use appropriate log levels

## See Also

- [Agent State Management](state.html)
- [Agent Configuration](configuration.html)
- [Error Handling](error-handling.html)
- [Testing Agents](testing.html)
