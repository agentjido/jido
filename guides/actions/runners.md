# Understanding Jido Runners

Runners are the execution engines that power Jido's agent system, responsible for processing instructions and managing state transitions. This guide explores both built-in runners and how to create custom implementations.

## Core Concepts

Runners serve as the bridge between agent instructions and their execution. They handle:

- Instruction processing
- State management
- Directive handling
- Error recovery
- Context propagation

## Built-in Runners

Jido provides two built-in runners optimized for different use cases:

### Simple Runner

The Simple Runner processes one instruction at a time, providing atomic execution and clear state transitions.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "simple_example",
    runner: Jido.Runner.Simple
end
```

#### Key Features

- Single instruction execution
- Atomic state updates
- Clear error boundaries
- Predictable behavior

#### State Flow

```elixir
# Simple Runner execution flow
{:ok, agent, directives} = Jido.Runner.Simple.run(agent, opts)

# Internal process:
# 1. Dequeue single instruction
# 2. Execute via action module
# 3. Update state atomically
# 4. Process any directives
# 5. Return updated agent
```

### Chain Runner

The Chain Runner enables sequential execution of multiple instructions with state flowing between steps.

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "chain_example",
    runner: Jido.Runner.Chain
end
```

#### Key Features

- Sequential instruction processing
- State flows between steps
- Directive accumulation
- Comprehensive error handling

#### State Flow

```elixir
# Chain Runner execution flow
{:ok, agent, directives} = Jido.Runner.Chain.run(agent, opts)

# Internal process:
# 1. Convert queue to instruction list
# 2. Execute instructions sequentially
# 3. Flow state between steps
# 4. Accumulate directives
# 5. Apply final state
```

## Context and State Management

Both runners handle agent state through context propagation:

```elixir
# State is automatically included in context
def run(%{action: action, params: params, context: context}, _opts) do
  # Context includes agent state
  enhanced_context = Map.put(context, :state, agent.state)

  case Jido.Workflow.run(action, params, enhanced_context) do
    {:ok, result} -> handle_success(result)
    {:error, reason} -> handle_error(reason)
  end
end
```

## Directive Processing

Runners handle directives that modify agent behavior:

```elixir
# Example directive processing
defp handle_directive_result(agent, state_map, directives) do
  case Directive.apply_agent_directive(agent, directives) do
    {:ok, updated_agent, server_directives} ->
      {:ok, updated_agent, server_directives}

    {:error, reason} ->
      {:error, Error.validation_error("Invalid directive", reason)}
  end
end
```

## Creating Custom Runners

Implement the `Jido.Runner` behavior to create custom runners:

```elixir
defmodule MyCustomRunner do
  @behaviour Jido.Runner

  @impl true
  def run(agent, opts \\ []) do
    # Custom execution logic here
    # Must return {:ok, updated_agent, directives} | {:error, reason}
  end

  # Helper functions
  defp process_instructions(instructions, agent) do
    # Custom instruction processing
  end

  defp update_agent_state(agent, result) do
    # Custom state update logic
  end
end
```

### Implementation Guidelines

1. **State Management**

   - Handle state updates atomically
   - Preserve agent state on errors
   - Validate state transitions

2. **Error Handling**

   - Implement comprehensive error handling
   - Provide clear error messages
   - Consider retry strategies

3. **Directive Support**

   - Process directives consistently
   - Validate directive types
   - Handle directive errors gracefully

4. **Performance**
   - Consider concurrency implications
   - Optimize for your use case
   - Handle resource cleanup

## Integration with Agents

Runners are automatically integrated into Agents when specified in the configuration. This means you typically won't interact with runners directly, but rather through the Agent interface:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "example_agent",
    runner: Jido.Runner.Chain  # Runner is automatically integrated

  # All runner operations are handled internally
  def process_workflow(data) do
    enqueue(ProcessData, %{input: data})
  end
end
```

This guide serves primarily as a reference for understanding runner behavior and creating custom implementations when needed.

## Timeout Configuration

Runners support flexible timeout configuration at multiple levels, providing fine-grained control over action execution timing.

### Global Timeout Configuration

Configure the default timeout for all actions in your application:

```elixir
# config/config.exs
config :jido, default_timeout: 60_000  # 60 seconds (default: 30 seconds)
```

### Runner-Level Timeouts

Set timeouts that apply to all instructions processed by a runner:

```elixir
# Simple Runner with timeout
{:ok, agent, directives} = Jido.Runner.Simple.run(agent, timeout: 45_000)

# Chain Runner with timeout
{:ok, agent, directives} = Jido.Runner.Chain.run(agent, timeout: 120_000)
```

### Instruction-Level Timeouts

Individual instructions can specify their own timeouts, which take precedence over runner-level timeouts:

```elixir
# Instruction with specific timeout
instruction = %Instruction{
  action: LongRunningAction,
  params: %{data: large_dataset},
  opts: [timeout: 300_000]  # 5 minutes for this specific action
}

# This instruction will use 300 seconds, others use runner or global timeout
{:ok, agent, directives} = Jido.Runner.Simple.run(agent, timeout: 30_000)
```

### Timeout Precedence Rules

Timeout options follow a clear precedence hierarchy:

1. **Instruction-level timeout** (highest precedence)
2. **Runner-level timeout** 
3. **Global configuration timeout** (lowest precedence)

```elixir
# Example showing precedence
instructions = [
  %Instruction{
    action: FastAction,
    opts: [timeout: 5_000]    # This instruction: 5 seconds
  },
  %Instruction{
    action: NormalAction,
    opts: []                  # This instruction: 45 seconds (runner timeout)
  }
]

# Runner timeout applies to instructions without specific timeout
Jido.Runner.Chain.run(agent, timeout: 45_000)
```

### Special Timeout Values

- **`timeout: 0`** - Disables timeout completely, action can run indefinitely
- **Positive integers** - Timeout in milliseconds

```elixir
# Disable timeout for long-running batch operations
batch_instruction = %Instruction{
  action: BatchProcessor,
  params: %{items: thousands_of_items},
  opts: [timeout: 0]  # No timeout limit
}
```

### Integration with Agent Configuration

Agents can specify default timeouts for their runners:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "timeout_example",
    runner: Jido.Runner.Simple
  
  # Override start_link to set default runner options
  def start_link(opts \\ []) do
    runner_opts = Keyword.get(opts, :runner_opts, [])
    runner_opts = Keyword.put_new(runner_opts, :timeout, 120_000)  # 2 minutes
    
    opts = Keyword.put(opts, :runner_opts, runner_opts)
    super(opts)
  end
end
```

## Best Practices

1. **Choose the Right Runner**

   - Use Simple Runner for atomic operations
   - Use Chain Runner for complex workflows
   - Create custom runners for specific needs

2. **State Management**

   - Keep state transitions explicit
   - Validate state changes
   - Handle edge cases

3. **Timeout Management**

   - Set appropriate global defaults in configuration
   - Use runner-level timeouts for consistent behavior
   - Override with instruction-level timeouts for special cases
   - Use `timeout: 0` sparingly and only for truly long-running operations
   - Monitor timeout patterns to optimize performance

4. **Error Handling**

   - Implement comprehensive error handling
   - Provide clear error messages
   - Consider recovery strategies

5. **Testing**
   - Test happy paths thoroughly
   - Test error conditions
   - Test state transitions
   - Test directive handling
   - Test timeout scenarios

## Next Steps

- Explore the source code of built-in runners
- Implement custom runners for specific needs
- Contribute improvements to the community

Remember that runners are a critical part of your agent system. Choose and implement them carefully based on your specific requirements.
