# Actions as Tools

## Overview

Jido Actions can be converted into tools compatible with LLM frameworks like Langchain. This guide demonstrates how to transform your Actions into Langchain tools, enabling seamless integration with AI-powered workflows.

## Key Concepts

- An Action defines a discrete unit of functionality with validated inputs and outputs
- Langchain tools represent capabilities that can be invoked by LLMs
- The `Jido.Actions.Tool` module handles the conversion between these formats

## Basic Tool Conversion

Let's start with a simple example of converting a basic Action to a Langchain tool:

```elixir
defmodule WeatherAction do
  use Jido.Action,
    name: "get_weather",
    description: "Gets the current weather for a location",
    schema: [
      location: [
        type: :string,
        required: true,
        doc: "The city or location to get weather for"
      ],
      units: [
        type: {:in, ["celsius", "fahrenheit"]},
        default: "celsius",
        doc: "Temperature units to use"
      ]
    ]

  @impl true
  def run(%{location: location, units: units}, _context) do
    # Simulated weather API call
    {:ok, %{
      temperature: 22,
      units: units,
      conditions: "sunny",
      location: location
    }}
  end
end
```

Convert this Action to a Langchain tool:

```elixir
# Convert to tool format
weather_tool = WeatherAction.to_tool()

# The tool can now be used with Langchain
{:ok, chain} = Langchain.Chain.new([
  weather_tool,
  Langchain.Chains.ChatPrompt
])
```

## Tool Schema Generation

The `to_tool/0` function automatically generates a JSON Schema for the tool's parameters based on your Action's schema:

```elixir
%{
  "name" => "get_weather",
  "description" => "Gets the current weather for a location",
  "parameters" => %{
    "type" => "object",
    "properties" => %{
      "location" => %{
        "type" => "string",
        "description" => "The city or location to get weather for"
      },
      "units" => %{
        "type" => "string",
        "enum" => ["celsius", "fahrenheit"],
        "description" => "Temperature units to use"
      }
    },
    "required" => ["location"]
  }
}
```

## Advanced Tool Patterns

### 1. Complex Parameter Validation

For tools with complex parameter requirements:

```elixir
defmodule DataProcessingAction do
  use Jido.Action,
    name: "process_data",
    description: "Processes data with specified options",
    schema: [
      input_format: [
        type: {:in, ["json", "csv", "xml"]},
        required: true,
        doc: "Format of the input data"
      ],
      transformations: [
        type: {:list, :atom},
        default: [],
        doc: "List of transformations to apply"
      ],
      options: [
        type: :map,
        default: %{},
        doc: "Additional processing options"
      ]
    ]

  @impl true
  def run(params, context) do
    # Processing logic here
    {:ok, %{result: "processed"}}
  end
end
```

### 2. Error Handling in Tools

Tools should provide clear error messages that can be understood by the LLM:

```elixir
defmodule RobustAction do
  use Jido.Action,
    name: "robust_operation",
    description: "Performs an operation with comprehensive error handling",
    schema: [
      input: [type: :string, required: true]
    ]

  @impl true
  def run(%{input: input}, _context) do
    case process_input(input) do
      {:ok, result} ->
        {:ok, %{result: result}}

      {:error, :invalid_format} ->
        {:error, "Input must be in valid format X,Y,Z"}

      {:error, :not_found} ->
        {:error, "The requested resource could not be found"}
    end
  end
end
```

### 3. Contextual Tool Execution

Pass relevant context to your tools:

```elixir
defmodule ContextAwareAction do
  use Jido.Action,
    name: "context_aware",
    description: "Uses execution context for enhanced functionality",
    schema: [
      operation: [type: :string, required: true]
    ]

  @impl true
  def run(params, %{user_id: user_id, tenant: tenant}) do
    # Use context in processing
    {:ok, %{
      operation: params.operation,
      user: user_id,
      tenant: tenant
    }}
  end
end

# Use with Langchain
{:ok, chain} = Langchain.Chain.new([
  {ContextAwareAction.to_tool(), context: %{
    user_id: "user_123",
    tenant: "tenant_456"
  }},
  Langchain.Chains.ChatPrompt
])
```

## Integration with LangChain

Here's a complete example of using a Jido Action as a tool in a Langchain workflow:

```elixir
defmodule CalculatorAction do
  use Jido.Action,
    name: "calculate",
    description: "Performs basic arithmetic calculations",
    schema: [
      operation: [
        type: {:in, ["add", "subtract", "multiply", "divide"]},
        required: true,
        doc: "The arithmetic operation to perform"
      ],
      x: [type: :float, required: true, doc: "First number"],
      y: [type: :float, required: true, doc: "Second number"]
    ]

  @impl true
  def run(%{operation: op, x: x, y: y}, _context) do
    result = case op do
      "add" -> x + y
      "subtract" -> x - y
      "multiply" -> x * y
      "divide" when y != 0 -> x / y
      "divide" -> {:error, "Division by zero"}
    end

    case result do
      {:error, reason} -> {:error, reason}
      value -> {:ok, %{result: value}}
    end
  end
end

# Create Langchain workflow
defmodule MathWorkflow do
  def execute(prompt) do
    # Convert calculator to tool
    calculator_tool = CalculatorAction.to_tool()

    # Create chain with tool
    {:ok, chain} = Langchain.Chain.new([
      calculator_tool,
      {Langchain.Chains.ChatPrompt,
       prompt: """
       You are a helpful math assistant. Use the calculator tool to solve problems.
       User query: #{prompt}
       """}
    ])

    # Execute chain
    Langchain.run(chain)
  end
end

# Example usage
MathWorkflow.execute("What is 123.45 multiplied by 67.89?")
```

## Best Practices

1. **Clear Descriptions**

   - Provide detailed descriptions for both the tool and its parameters
   - Include examples in parameter documentation
   - Use consistent terminology

2. **Robust Validation**

   - Implement comprehensive parameter validation
   - Return clear error messages
   - Handle edge cases explicitly

3. **Context Handling**

   - Pass relevant context through the tool chain
   - Document expected context requirements
   - Provide defaults for missing context

4. **Error Handling**

   - Return structured error responses
   - Include actionable error messages
   - Handle both expected and unexpected errors

5. **Testing**
   - Test tool conversion explicitly
   - Verify schema generation
   - Test integration with Langchain

## Common Issues and Solutions

### 1. Schema Conversion

If your Action schema uses custom types, implement custom type conversion:

```elixir
defmodule CustomTypeAction do
  use Jido.Action,
    name: "custom_type_action",
    description: "Handles custom types",
    schema: [
      date: [
        type: :date,
        required: true,
        doc: "Date in ISO format"
      ]
    ]

  # Custom type validation
  def validate_params(%{date: date} = params) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, _valid_date} -> {:ok, params}
      {:error, _} -> {:error, "Invalid date format"}
    end
  end
end
```

### 2. Context Persistence

Ensure context is properly passed through the tool chain:

```elixir
# Create chain with persistent context
{:ok, chain} = Langchain.Chain.new([
  {MyAction.to_tool(),
   context: %{tenant_id: "t1"},
   persist_context: true},
  Langchain.Chains.ChatPrompt
])
```

## Testing Tools

Example test cases for your tools:

```elixir
defmodule WeatherActionTest do
  use ExUnit.Case

  test "converts to valid tool" do
    tool = WeatherAction.to_tool()

    assert tool.name == "get_weather"
    assert tool.description =~ "Gets the current weather"
    assert Map.has_key?(tool.parameters_schema["properties"], "location")
  end

  test "executes as tool" do
    tool = WeatherAction.to_tool()

    assert {:ok, result} = tool.function.(%{
      "location" => "Portland",
      "units" => "celsius"
    }, %{})

    assert is_binary(result)
    assert Jason.decode!(result)["temperature"]
  end
end
```

## See Also

- [Langchain Integration Guide](https://hexdocs.pm/langchain)
- [JSON Schema Documentation](https://json-schema.org/)
- [Testing Guide](testing.html)
