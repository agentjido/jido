# Actions Overview

Actions are the fundamental building blocks of agent behavior in Jido. Each Action represents a discrete, composable unit of functionality that can be executed as part of a workflow. This guide explores how to create, use, and compose Actions effectively.

## Core Concepts

Actions in Jido follow several key design principles:

1. **Self-Contained**: Each Action encapsulates a specific piece of functionality with clear inputs and outputs
2. **Composable**: Actions can be chained together to create complex workflows
3. **Validated**: Input parameters are validated using schemas
4. **Context-Aware**: Actions receive execution context for enhanced flexibility
5. **Error-Resilient**: Built-in error handling and compensation mechanisms

## Defining Actions

Here's a simple Action that adds two numbers:

```elixir
defmodule MyApp.Actions.Add do
  use Jido.Action,
    name: "add",
    description: "Adds two numbers together",
    schema: [
      value: [type: :number, required: true, doc: "First number"],
      amount: [type: :number, required: true, doc: "Second number"]
    ]

  @impl true
  def run(%{value: value, amount: amount}, _context) do
    {:ok, %{result: value + amount}}
  end
end
```

### Key Components

1. **Module Definition**: Actions are Elixir modules that use the `Jido.Action` behavior
2. **Configuration**:
   - `name`: Unique identifier for the Action
   - `description`: Human-readable description
   - `schema`: Parameter validation rules using NimbleOptions
3. **Run Implementation**: The `run/2` callback defines the Action's core logic

## Action Lifecycle

When an Action is executed, it goes through several phases:

1. **Parameter Validation**: Input is checked against the schema
2. **Execution**: The `run/2` callback is invoked
3. **Result Processing**: Output is normalized and returned
4. **Error Handling**: Failures are caught and processed

### Example Workflow

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    name: "process_order",
    description: "Processes a customer order",
    schema: [
      order_id: [type: :string, required: true],
      customer_id: [type: :string, required: true]
    ]

  @impl true
  def run(params, context) do
    with {:ok, order} <- fetch_order(params.order_id),
         {:ok, processed} <- apply_processing(order, context) do
      {:ok, %{
        order_id: params.order_id,
        status: "processed",
        result: processed
      }}
    else
      {:error, reason} -> {:error, "Failed to process order: #{reason}"}
    end
  end
end
```

## Error Handling

Actions support multiple error handling patterns:

### 1. Basic Error Return

```elixir
def run(%{value: 0}, _context) do
  {:error, "Cannot process zero value"}
end
```

### 2. Compensation Logic

```elixir
defmodule MyApp.Actions.RiskyOperation do
  use Jido.Action,
    name: "risky_operation",
    compensation: [enabled: true]

  def on_error(failed_params, error, _context, _opts) do
    # Compensation logic here
    {:ok, %{compensated: true, original_error: error}}
  end
end
```

### 3. Error Context

```elixir
{:error, %Jido.Error{
  type: :validation_error,
  message: "Invalid input",
  details: %{field: :value, reason: "must be positive"}
}}
```

## Composing Actions

Actions can be composed in several ways:

### 1. Sequential Chaining

```elixir
alias MyApp.Actions.{ValidateOrder, ProcessOrder, NotifyCustomer}

instructions = [
  ValidateOrder,
  {ProcessOrder, %{priority: "high"}},
  NotifyCustomer
]

Jido.Workflow.run_chain(instructions, %{order_id: "123"})
```

### 2. Conditional Execution

```elixir
def process_with_notification(params) do
  base_instructions = [ValidateOrder, ProcessOrder]

  instructions =
    if params.notify do
      base_instructions ++ [NotifyCustomer]
    else
      base_instructions
    end

  Jido.Workflow.run_chain(instructions, params)
end
```

## Built-in Actions

Jido provides several built-in Action modules:

### Basic Operations

```elixir
alias Jido.Tools.Basic

# Sleep for a duration
Basic.Sleep.run(%{duration_ms: 1000}, %{})

# Log a message
Basic.Log.run(%{level: :info, message: "Processing"}, %{})
```

### File Operations

```elixir
alias Jido.Actions.Files

# Write to a file
Files.WriteFile.run(%{
  path: "output.txt",
  content: "Hello",
  create_dirs: true
}, %{})
```

### Arithmetic Operations

```elixir
alias Jido.Actions.Arithmetic

# Add numbers
Arithmetic.Add.run(%{value: 5, amount: 3}, %{})

# Multiply numbers
Arithmetic.Multiply.run(%{value: 4, amount: 2}, %{})
```

## Testing Actions

Actions can be tested using standard ExUnit tests:

```elixir
defmodule MyApp.Actions.AddTest do
  use ExUnit.Case

  test "adds two numbers" do
    params = %{value: 5, amount: 3}
    assert {:ok, %{result: 8}} = MyApp.Actions.Add.run(params, %{})
  end

  test "validates required parameters" do
    params = %{value: 5}
    assert {:error, _} = MyApp.Actions.Add.run(params, %{})
  end
end
```

## Best Practices

1. **Keep Actions Focused**: Each Action should do one thing well
2. **Validate Inputs**: Use comprehensive schemas to catch issues early
3. **Handle Errors**: Implement proper error handling and compensation
4. **Provide Context**: Use the context parameter for shared state
5. **Document Well**: Include clear descriptions and parameter documentation

## Next Steps

- Learn about [Action Configuration](configuration.md) including timeout settings
- Learn about [Action Workflows](workflows.html)
- Explore [Testing Actions](testing.html)
- Understand [Action Directives](directives.html)
- See [Actions as Tools](actions-as-tools.html)

## See Also

- [Action Configuration](configuration.md)
- [Signal Overview](../signals/overview.livemd)
- [Agent Overview](../agents/overview.md)
- [Action Testing](testing.md)
