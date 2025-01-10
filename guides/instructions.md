# Instructions Guide

## Overview

Instructions are the fundamental unit of execution in the Jido system. An Instruction wraps an action module with its parameters and execution context, allowing Runners to execute them in a standardized way. This guide covers instruction formats, normalization, and best practices.

## Instruction Structure

A full instruction struct contains:

```elixir
%Jido.Instruction{
  action: module(),      # The action module to execute (required)
  params: map(),        # Parameters to pass to the action (default: %{})
  context: map(),       # Execution context data (default: %{})
  result: term()        # Execution result (default: nil)
}
```

## Instruction Formats

Jido supports several shorthand formats for convenience, all of which are normalized to the full instruction struct during processing. Here are the supported formats:

### 1. Action Module Only
```elixir
# Shorthand
MyApp.Actions.ProcessFile

# Normalizes to
%Instruction{
  action: MyApp.Actions.ProcessFile,
  params: %{},
  context: %{}
}
```

### 2. Action With Parameters (Tuple Form)
```elixir
# Shorthand
{MyApp.Actions.ProcessFile, %{path: "/tmp/data.csv"}}

# Normalizes to
%Instruction{
  action: MyApp.Actions.ProcessFile,
  params: %{path: "/tmp/data.csv"},
  context: %{}
}
```

### 3. Full Instruction Struct
```elixir
# Explicit struct
%Instruction{
  action: MyApp.Actions.ProcessFile,
  params: %{path: "/tmp/data.csv"},
  context: %{user_id: "123"}
}
```

### 4. Lists of Mixed Formats
```elixir
# Mixed shorthand list
[
  ValidateAction,
  {ProcessAction, %{file: "data.csv"}},
  %Instruction{action: StoreAction, context: %{store_id: "456"}}
]

# Each element normalizes to a full instruction struct
```

## Normalization Process

All instruction formats are normalized when:
1. Planning actions on an Agent
2. Directly executing through a Runner
3. Creating instruction queues

The normalization ensures:
- Consistent structure for execution
- Parameter validation
- Context preservation
- Type safety
- Serialization support

## Best Practices

### When to Use Shorthand

Use shorthand formats when:
- Planning simple action sequences
- Writing tests
- Demonstrating examples
- Working with basic workflows

```elixir
# Good use of shorthand
{:ok, agent} = MyAgent.plan(agent, [
  ValidateInput,
  {ProcessData, %{format: "csv"}},
  StoreResults
])
```

### When to Use Full Structs

Use full instruction structs when:
- Implementing custom runners
- Building complex workflows
- Needing explicit context control
- Working with instruction queues directly

```elixir
# Good use of full struct
instruction = %Instruction{
  action: ProcessData,
  params: %{format: "csv"},
  context: %{
    request_id: "abc123",
    user_id: "456",
    tenant: "acme"
  }
}
```

### Context Management

The context map is preserved during normalization and is available to:
- Action implementations
- Runners
- Error handlers
- Telemetry events

```elixir
# Setting context during planning
{:ok, agent} = MyAgent.plan(
  agent,
  ProcessAction,
  %{                        # Context map
    request_id: "abc123",
    user_id: "456"
  }
)
```

### Working with Instructions Programmatically

When manipulating instructions in code:

```elixir
# Pattern match on full struct
def process_instruction(%Instruction{action: action, params: params}) do
  # Work with normalized form
end

# Transform instructions
def add_context(instructions, context) do
  Enum.map(instructions, fn
    %Instruction{} = inst -> 
      %{inst | context: Map.merge(inst.context, context)}
    {action, params} -> 
      %Instruction{action: action, params: params, context: context}
    action when is_atom(action) -> 
      %Instruction{action: action, context: context}
  end)
end
```

## Error Handling

Instructions provide rich error context:

```elixir
case MyAgent.plan(agent, invalid_instruction) do
  {:ok, agent} -> 
    # Success case
  {:error, %Error{type: :validation_error, context: context}} ->
    # Handle validation failure with full context
end
```

## Testing Instructions

Test both shorthand and normalized forms:

```elixir
test "supports shorthand planning" do
  {:ok, agent} = MyAgent.plan(agent, SimpleAction)
  assert [%Instruction{action: SimpleAction}] = 
    :queue.to_list(agent.pending_instructions)
end

test "preserves context in normalization" do
  context = %{request_id: "123"}
  {:ok, agent} = MyAgent.plan(agent, SimpleAction, context)
  
  [instruction] = :queue.to_list(agent.pending_instructions)
  assert instruction.context.request_id == "123"
end
```

## Summary

- Use shorthand formats for convenience in simple cases
- Work with full instruction structs in implementation code
- Trust the normalization process to handle all formats consistently
- Leverage the context map for cross-cutting concerns
- Test both shorthand and normalized forms
- Handle errors with full context

Remember: Instructions are always normalized before execution, so choose the format that makes your code most readable and maintainable in each specific situation.