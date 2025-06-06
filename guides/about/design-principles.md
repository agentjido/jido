# Design Principles

## Overview

Jido follows a set of core design principles that shape its architecture and guide implementation decisions. These principles emphasize reliability, clarity, and flexibility while maintaining strong guarantees about system behavior.

## Core Principles

### 1. Error Tuples Over Exceptions

Jido adopts a strict "no exceptions" policy, using tagged tuples to handle errors explicitly:

```elixir
# Good - Using error tuples
def process_data(input) do
  case validate_input(input) do
    {:ok, validated} -> perform_processing(validated)
    {:error, reason} -> {:error, "Invalid input: #{reason}"}
  end
end

# Bad - Using exceptions
def process_data(input) do
  validated = validate_input!(input)  # May raise
  perform_processing(validated)
rescue
  e -> handle_error(e)  # Hidden control flow
end
```

This approach provides:

- Explicit error handling paths
- Clear function contracts
- Predictable control flow
- Easy composition with `with` statements

### 2. Data-First Architecture

Jido prioritizes data transformation over behavioral inheritance:

```elixir
# Data-centric approach
defmodule DataProcessor do
  def process(%{type: "user", data: data} = signal) do
    with {:ok, enriched} <- enrich_user_data(data),
         {:ok, validated} <- validate_user(enriched) do
      {:ok, %{signal | data: validated}}
    end
  end
end

# Instead of behavioral inheritance
defmodule UserProcessor do
  @behaviour Processor
  def process(signal), do: # Implementation
end
```

Benefits:

- Simpler testing and reasoning
- Easier refactoring
- Natural composition
- Clear data flow

### 3. Rich Compile-Time Discovery

Jido leverages compile-time metadata to enable rich discovery and validation:

```elixir
defmodule MyApp.UserAction do
  use Jido.Action,
    name: "process_user",
    description: "Processes user data with validation",
    category: :users,
    tags: [:processing, :validation],
    schema: [
      user_id: [
        type: :string,
        required: true,
        doc: "Unique user identifier"
      ],
      options: [
        type: :map,
        default: %{},
        doc: "Processing options"
      ]
    ]
end
```

This enables:

- Automatic documentation generation
- Schema validation
- Runtime introspection
- Tool integration

### 4. Event-Driven Processing

The system is built around event-driven communication using actions and instructions:

```elixir
# Create an instruction
instruction = %Jido.Instruction{
  action: "process_user",
  params: %{user_data: user_data, source: "/users"}
}

# Process instruction through agent
def run(%{user_data: data}, context) do
  with {:ok, processed} <- process_user(data),
       {:ok, notification} <- generate_notification(processed) do
    {:ok, notification}
  end
end
```

Key aspects:

- Decoupled components
- Asynchronous processing
- Clear action paths
- Flexible routing

### 5. Agents as Dynamic ETL

Agents function as dynamic Extract-Transform-Load processors:

```elixir
defmodule DataTransformAgent do
  use Jido.Agent,
    name: "data_transformer"

  def process_data(data) do
    with {:ok, extracted} <- extract_data(data),
         {:ok, transformed} <- apply_transformations(extracted),
         {:ok, loaded} <- load_result(transformed) do
      {:ok, loaded}
    end
  end

  # Transformation steps are composed dynamically
  defp apply_transformations(data) do
    transformations = [
      &validate_format/1,
      &enrich_data/1,
      &normalize_values/1
    ]

    Enum.reduce_while(transformations, {:ok, data}, fn transform, {:ok, acc} ->
      case transform.(acc) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
```

Benefits:

- Flexible processing pipelines
- Clear data transformations
- Composable operations
- Runtime adaptation

### 6. Balanced Data Validation

Jido implements a "validate what you know" approach to data handling:

```elixir
defmodule FlexibleProcessor do
  # Schema defines only known fields
  use Jido.Action,
    schema: [
      id: [type: :string, required: true],
      status: [type: {:in, [:pending, :complete]}]
    ]

  def process(params) do
    # Unknown fields pass through unchanged
    case validate_required_fields(params) do
      {:ok, validated} ->
        # Process while preserving unknown fields
        result = do_process(validated)
        {:ok, Map.merge(params, result)}

      {:error, _} = error -> error
    end
  end
end
```

This approach:

- Validates critical fields
- Preserves extensibility
- Enables forward compatibility
- Reduces maintenance burden

### 7. Robust Error Recovery

Following Erlang's "let it crash" philosophy while maintaining system stability:

```elixir
defmodule ResilientAgent do
  use Jido.Agent,
    name: "resilient_processor"

  # Supervisor ensures recovery
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5000
    }
  end

  # Trap exits for cleanup
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  # Handle known errors
  def handle_error({:error, :recoverable} = error, state) do
    Logger.warning("Recovering from error", error: error)
    {:ok, reset_state(state)}
  end

  # Let unknown errors crash
  def handle_error(error, _state) do
    Logger.error("Unhandled error", error: error)
    {:stop, error}
  end
end
```

Key features:

- Supervision hierarchies
- Process isolation
- Clean error separation
- Graceful degradation

## See Also

- [Agent Overview](agents/overview.md)
- [Action Overview](actions/overview.md)
