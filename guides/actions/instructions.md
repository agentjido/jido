# Instructions in Jido

Instructions represent discrete units of work that can be planned, validated, and executed by agents. Think of them as "work orders" that specify exactly what needs to be done and how to do it.

## Core Concepts

An Instruction wraps an Action module with everything it needs to execute:

- The Action to perform (required)
- Parameters for the action
- Execution context
- Runtime options

### Instruction Structure

Each Instruction contains:

```elixir
%Instruction{
  id: "inst_abc123",           # Unique identifier
  action: MyApp.Actions.DoTask, # The action module to execute
  params: %{value: 42},        # Parameters for the action, always a map
  context: %{user_id: "123"},  # Execution context
  opts: [retry: true],         # Runtime options
}
```

## Creating Instructions

Jido supports multiple formats for creating instructions, offering flexibility while maintaining type safety:

### 1. Full Instruction Struct

```elixir
%Instruction{
  action: MyApp.Actions.ProcessOrder,
  params: %{order_id: "123"},
  context: %{tenant_id: "456"}
}
```

### 2. Action Module Only

```elixir
MyApp.Actions.ProcessOrder
```

### 3. Action With Parameters

```elixir
{MyApp.Actions.ProcessOrder, %{order_id: "123"}}
```

### 4. Factory Function

```elixir
Instruction.new!(%{
  action: MyApp.Actions.ProcessOrder,
  params: %{order_id: "123"},
  context: %{tenant_id: "456"}
})
```

### 5. Lists of any of the above

```elixir
[
  MyApp.Actions.ProcessOrder,
  %Instruction{
    action: MyApp.Actions.ProcessOrder,
    params: %{order_id: "123"},
    context: %{tenant_id: "456"}
  }
]
```

## Working with Instructions

### Normalization

Convert various input formats to standard instruction structs:

```elixir
# Normalize a single instruction
{:ok, [instruction]} = Instruction.normalize(MyApp.Actions.ProcessOrder)

# Normalize with context
{:ok, instructions} = Instruction.normalize(
  [
    MyApp.Actions.ValidateOrder,
    {MyApp.Actions.ProcessOrder, %{priority: "high"}}
  ],
  %{tenant_id: "123"}  # Shared context
)
```

### Validation

Ensure instructions use allowed actions:

```elixir
agent_allowed_actions = [
  MyApp.Actions.ValidateOrder,
  MyApp.Actions.ProcessOrder
]

:ok = Instruction.validate_allowed_actions(instructions, agent_allowed_actions)
```

## Common Patterns

### 1. Workflow Definition

```elixir
instructions = [
  MyApp.Actions.ValidateInput,
  {MyApp.Actions.ProcessData, %{format: "json"}},
  MyApp.Actions.SaveResults
]
```

### 2. Conditional Execution

```elixir
instructions = [
  MyApp.Actions.ValidateOrder,
  {MyApp.Actions.CheckInventory, %{strict: true}},
  # Add fulfillment only if in stock
  if has_stock? do
    {MyApp.Actions.FulfillOrder, %{warehouse: "main"}}
  end
]
|> Enum.reject(&is_nil/1)
```

### 3. Context Sharing

```elixir
# All instructions share common context
{:ok, instructions} = Instruction.normalize(
  [ValidateUser, ProcessOrder, NotifyUser],
  %{
    request_id: "req_123",
    tenant_id: "tenant_456",
  }
)
```

## Instruction Execution

Instructions are executed directly by agents through their built-in execution logic:

```elixir
# Execute pending instructions on an agent
{:ok, agent, directives} = MyAgent.run(agent)

# Execute specific instructions with parameters
{:ok, agent, directives} = MyAgent.cmd(agent, instructions, %{})
```

### Error Handling

Instructions use the `OK` monad for consistent error handling:

```elixir
def process_instruction(instruction) do
  with {:ok, validated} <- validate_instruction(instruction),
       {:ok, processed} <- execute_instruction(validated) do
    {:ok, processed}
  else
    {:error, reason} -> handle_error(reason)
  end
end
```

## Testing Instructions

Instructions can be tested both in isolation and as part of workflows:

```elixir
defmodule InstructionTest do
  use ExUnit.Case

  test "creates valid instruction" do
    assert {:ok, instruction} = Instruction.new(%{
      action: MyApp.Actions.ProcessOrder,
      params: %{order_id: "123"}
    })
    assert instruction.action == MyApp.Actions.ProcessOrder
  end

  test "normalizes action tuple" do
    assert {:ok, [instruction]} = Instruction.normalize(
      {MyApp.Actions.ProcessOrder, %{order_id: "123"}}
    )
    assert instruction.params.order_id == "123"
  end
end
```

## Best Practices

1. **Explicit Intent**: Use the most explicit instruction format that fits your use case

   ```elixir
   # Good - Clear intent with full struct
   %Instruction{action: ProcessOrder, params: %{id: order_id}}

   # Less Clear - Relies on normalization
   {ProcessOrder, [id: order_id]}
   ```

2. **Context Management**: Keep context focused and relevant

   ```elixir
   # Good - Relevant context
   context = %{user_id: user.id, tenant_id: tenant.id}

   # Bad - Excessive context
   context = %{entire_user: user, database_connection: conn}
   ```

3. **Error Handling**: Implement comprehensive error handling

   ```elixir
   def handle_instruction(instruction) do
     case execute(instruction) do
       {:ok, result} -> {:ok, result}
       {:error, :invalid_params} -> {:error, "Invalid parameters"}
       {:error, reason} -> {:error, "Execution failed: #{reason}"}
     end
   end
   ```

4. **Validation**: Always validate instructions before execution
   ```elixir
   def safe_execute(instruction) do
     with :ok <- validate_allowed_actions([instruction], allowed_actions()),
          {:ok, normalized} <- normalize(instruction),
          {:ok, result} <- execute(normalized) do
       {:ok, result}
     end
   end
   ```

## Common Questions

### When should I use full structs vs. tuples?

Use full structs when:

- You need explicit control over all instruction fields
- The code benefits from clarity over brevity
- You're defining complex workflows

Use tuples when:

- You only need action and params
- You're defining simple, linear workflows
- The brevity improves readability

### How do I share context between instructions?

Pass context during normalization:

```elixir
shared_context = %{tenant_id: "123"}
{:ok, instructions} = Instruction.normalize(workflow, shared_context)
```

### Can I modify instructions during execution?

No, instructions are immutable by design. Instead:

1. Create new instructions with modified parameters
2. Use the agent's directive system to enqueue modified instructions

## See Also

- [Actions Overview](actions/overview.md) - Learn about implementing actions

- [Testing](actions/testing.md) - Comprehensive testing guide
