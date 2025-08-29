# Building Stateless Agents in Jido

## Overview

Jido Agents may be used in either a stateful or stateless manner. Stateless agents provide an immutable, functional approach to workflow orchestration allowing the developer to overlay their own OTP lifecycle as needed. Stateless agents are also ideal for testing and development, as they can be manipulated and inspected as pure Elixir data structures.

Alternatively, you may use the `Jido.Agent.Server` module to create a stateful agent that uses a GenServer for its lifecycle. Learn more about [stateful agents](stateful.md) in the next section.

## Core Design Principles

1. **Immutability**: All state transitions create new agent instances
2. **Pure Functions**: Operations have no side effects
3. **Explicit State Flow**: State changes are always returned, never mutated
4. **Functional Composition**: Operations chain through return values

## Implementation Guide

### Basic Agent Structure

```elixir
defmodule MyApp.StatelessAgent do
  use Jido.Agent,
    name: "stateless_agent",
    description: "Pure functional workflow processor",
    schema: [
      input: [
        type: :map,
        required: true,
        doc: "Input data to process"
      ],
      format: [
        type: {:in, ["json", "xml", "yaml"]},
        required: true,
        doc: "Data format"
      ],
      metadata: [
        type: :map,
        default: %{},
        doc: "Optional processing metadata"
      ],
      status: [
        type: {:in, [:pending, :processing, :complete]},
        default: :pending,
        doc: "Processing status"
      ]
    ],
    actions: [
      MyApp.Actions.ValidateInput,
      MyApp.Actions.TransformData,
      MyApp.Actions.EnrichMetadata
    ]

  # No GenServer callbacks or state mutation
  # All operations use core Agent module functions
end
```

### Understanding the Agent Struct

At its core, a Jido agent is an Elixir struct that can be freely inspected and pattern matched against. This transparency is crucial for testing and debugging:

```elixir
%MyApp.StatelessAgent{
  id: "agent_123",           # Unique identifier
  state: %{},               # Current validated state
  pending_instructions: queue, # Erlang queue of pending actions
  actions: [],              # List of allowed action modules
  dirty_state?: false,      # State modification tracking
  result: nil               # Last execution result
}
```

### Inspecting Agent State

You can pattern match and inspect any aspect of the agent:

```elixir
# Pattern match on specific states
def handle_agent(%{state: %{status: :complete}} = agent) do
  # Handle completed agent
end

# Inspect pending instructions
instruction_count = :queue.len(agent.pending_instructions)

# Check allowed actions
allowed_actions = agent.actions
```

## Core Operations

### Action Registration

Before an agent can execute actions, they must be registered either at compile-time or runtime:

```elixir
# Compile-time registration
use Jido.Agent,
  actions: [
    MyApp.Actions.ValidateInput,
    MyApp.Actions.ProcessData
  ]

# Runtime registration
{:ok, agent} = Jido.Agent.register_action(agent, MyApp.Actions.NewAction)
{:ok, agent} = Jido.Agent.register_action(agent, [Action1, Action2])

# Remove action
{:ok, agent} = Jido.Agent.deregister_action(agent, MyApp.Actions.OldAction)

# Check registration
actions = Jido.Agent.registered_actions(agent)
```

Only registered actions can be used in planning - this provides a safety mechanism against executing unintended code.

### Core Method Architecture

Jido agents provide four primary methods that work together for workflow orchestration:

New agent instances are created through the core Agent module:

```elixir
# Basic creation
agent = MyApp.StatelessAgent.new()

# With initial state
agent = MyApp.StatelessProcessor.new("custom_id", %{
  input: %{key: "value"},
  format: "json"
})
```

#### 1. State Management with `set/3`

The `set/3` function manages agent state through immutable updates:

```elixir
@spec set(agent :: t(), attrs :: map() | keyword(), opts :: keyword()) ::
  {:ok, t()} | {:error, Error.t()}
```

Parameters:

- `agent`: The agent struct to update
- `attrs`: Map or keyword list of attributes to merge into state
- `opts`: Configuration options
  - `:strict_validation` - Enable/disable strict schema validation (default: false)

The set operation:

1. Deep merges new attributes with existing state
2. Validates against the agent's schema
3. Sets the dirty_state? flag
4. Returns a new agent instance

```elixir
# Basic state update
{:ok, updated} = Jido.Agent.set(agent, %{
  status: :processing,
  metadata: %{started_at: DateTime.utc_now()}
})

# With strict validation
{:ok, validated} = Jido.Agent.set(agent, attrs, strict_validation: true)
```

```elixir
{:ok, updated_agent} = Jido.Agent.set(agent, %{
  input: new_input,
  metadata: %{processed_at: DateTime.utc_now()}
})

# Validation happens automatically
{:error, reason} = Jido.Agent.set(agent, %{
  format: "invalid"  # Will fail format validation
})
```

#### 2. Workflow Planning with `plan/3`

The `plan/3` function builds an immutable queue of instructions:

```elixir
@spec plan(agent :: t(), instructions :: instruction() | [instruction()], context :: map()) ::
  {:ok, t()} | {:error, Error.t()}
```

Parameters:

- `agent`: The agent struct to plan actions for
- `instructions`: Single action module or list of instruction specifications
  - Single module: `MyAction`
  - With params: `{MyAction, %{param: value}}`
  - Multiple actions: `[Action1, {Action2, %{}}]`
- `context`: Shared context map passed to all instructions

The planning process:

1. Validates that all actions are registered
2. Normalizes instructions into consistent format
3. Adds instructions to pending queue
4. Returns new agent with updated queue

````elixir
# Single action
{:ok, agent} = Jido.Agent.plan(agent, ValidateAction)

# Multiple actions with context
{:ok, agent} = Jido.Agent.plan(
  agent,
  [
    ValidateAction,
    {ProcessAction, %{mode: :strict}},
    FinalizeAction
  ],
  %{request_id: "req_123"}
)

```elixir
{:ok, agent_with_plan} = Jido.Agent.plan(agent, [
  ValidateInput,
  {TransformData, %{target_format: "xml"}},
  EnrichMetadata
])

# Planning preserves immutability
assert agent != agent_with_plan
````

#### 3. Execution with `run/2`

The `run/2` function executes pending instructions using built-in logic:

```elixir
@spec run(agent :: t(), opts :: keyword()) ::
  {:ok, t(), [Directive.t()]} | {:error, Error.t()}
```

Parameters:

- `agent`: The agent struct containing pending instructions
- `opts`: Execution options
  - `:apply_state` - Merge results into agent state (default: true)
  - `:timeout` - Execution timeout in milliseconds
  - `:retry` - Enable automatic retries (default: false)
  - `:max_retries` - Maximum retry attempts
  - `:backoff` - Retry backoff strategy

The execution process:

1. Executes pending instructions in order
2. Handles any returned directives
3. Returns new agent with results and directives

````elixir
# Basic execution
{:ok, agent, directives} = Jido.Agent.run(agent)

# With custom options
{:ok, agent, directives} = Jido.Agent.run(agent,
  apply_state: false,
  timeout: 5000,
  retry: true,
  max_retries: 3
)

```elixir
{:ok, final_agent, directives} = Jido.Agent.run(agent_with_plan)

# Results stored in agent
result = final_agent.result

# Original agent unchanged
assert agent_with_plan != final_agent
````

#### 4. Composite Operations with `cmd/4`

The `cmd/4` function composes set, plan, and run operations into a single call:

```elixir
@spec cmd(agent :: t(), instructions :: instruction() | [instruction()],
    attrs :: map(), opts :: keyword()) ::
  {:ok, t(), [Directive.t()]} | {:error, Error.t()}
```

Parameters:

- `agent`: The agent struct to operate on
- `instructions`: Action specifications to plan
- `attrs`: State attributes to set
- `opts`: Combined options for all operations
  - All options from `set/3`
  - All options from `plan/3`
  - All options from `run/2`

The command process:

1. Sets new state with validation
2. Plans specified instructions
3. Executes instructions with runner
4. Returns final agent state and directives

````elixir
# Complete workflow in one call
{:ok, agent, directives} = Jido.Agent.cmd(
  agent,
  [ValidateAction, ProcessAction],
  %{status: :processing, input: data},
  strict_validation: true,
  timeout: 10_000
)

```elixir
{:ok, final_agent, directives} = Jido.Agent.cmd(
  agent,
  [ValidateInput, TransformData],
  %{input: new_data, format: "json"}
)
````

## Purpose and Testing Philosophy

Stateless agents serve a crucial role in Jido's development workflow:

1. **Test-First Development**

   - Write and test agent logic before adding server capabilities
   - Focus on pure business logic without distributed system complexity
   - Ensure core workflows work correctly in isolation

2. **Predictable Testing**

   - Every operation produces new agent instances
   - No hidden state or side effects
   - Deterministic results for given inputs

3. **Comprehensive Coverage**
   - Test state validation rules
   - Verify action planning logic
   - Ensure proper error handling
   - Validate workflow composition

Example test suite:

```elixir
defmodule MyApp.StatelessAgentTest do
  use ExUnit.Case

  setup do
    agent = MyApp.StatelessAgent.new("test_id", %{
      status: :pending
    })
    {:ok, agent: agent}
  end

  test "validates state updates", %{agent: agent} do
    # Test state validation
    {:error, error} = Jido.Agent.set(agent, %{
      status: :invalid_status
    })
    assert error.type == :validation_error

    # Test successful update
    {:ok, updated} = Jido.Agent.set(agent, %{
      status: :processing
    })
    assert updated.state.status == :processing
  end

  test "plans allowed actions only", %{agent: agent} do
    # Test unregistered action
    {:error, error} = Jido.Agent.plan(agent, UnregisteredAction)

    # Register and plan action
    {:ok, agent} = Jido.Agent.register_action(agent, AllowedAction)
    {:ok, agent} = Jido.Agent.plan(agent, AllowedAction)
    assert :queue.len(agent.pending_instructions) == 1
  end

  test "executes complete workflow", %{agent: agent} do
    {:ok, final_agent, _directives} = Jido.Agent.cmd(
      agent,
      [ValidateAction, ProcessAction],
      %{input: test_data()}
    )

    assert final_agent.state.status == :complete
    assert final_agent.result != nil
  end
end
```

Once core logic is verified, you can add server capabilities with confidence that the underlying agent behavior works correctly.

## Advanced Patterns

### Functional Composition

Chain operations using pattern matching:

```elixir
def process_data(agent, input) do
  with {:ok, agent1} <- Jido.Agent.set(agent, %{input: input}),
       {:ok, agent2} <- Jido.Agent.plan(agent1, ValidateInput),
       {:ok, agent3, _} <- Jido.Agent.run(agent2) do
    {:ok, agent3}
  end
end
```

### State Flow Management

Track state transitions explicitly:

```elixir
def safe_transform(agent, data) do
  with {:ok, agent_with_data} <- set_with_validation(agent, data),
       {:ok, agent_with_plan} <- plan_transformation(agent_with_data),
       {:ok, final_agent, _} <- execute_transformation(agent_with_plan) do
    {:ok, final_agent}
  else
    {:error, reason} -> handle_transform_error(reason)
  end
end

defp set_with_validation(agent, data) do
  Jido.Agent.set(agent, %{
    input: data,
    status: :processing
  })
end

defp plan_transformation(agent) do
  Jido.Agent.plan(agent, [
    ValidateInput,
    TransformData,
    EnrichMetadata
  ])
end

defp execute_transformation(agent) do
  Jido.Agent.run(agent)
end
```

### Error Recovery

Implement explicit error handling:

```elixir
def transform_with_retry(agent, data, opts \\ []) do
  max_attempts = Keyword.get(opts, :max_attempts, 3)

  do_transform_with_retry(agent, data, 1, max_attempts)
end

defp do_transform_with_retry(agent, data, attempt, max_attempts) do
  case safe_transform(agent, data) do
    {:ok, transformed} ->
      {:ok, transformed}

    {:error, reason} when attempt < max_attempts ->
      :timer.sleep(exponential_backoff(attempt))
      do_transform_with_retry(agent, data, attempt + 1, max_attempts)

    {:error, reason} ->
      {:error, %{reason: reason, attempts: attempt}}
  end
end
```

## Best Practices

### 1. State Management

- Keep state minimal and focused
- Use computed properties when possible
- Validate state transitions early
- Return descriptive errors

### 2. Action Planning

- Build complete instruction sets
- Validate action sequences
- Consider compensation strategies
- Plan for retries

### 3. Execution

- Handle all error cases
- Use timeouts appropriately
- Implement backoff strategies
- Consider partial successes

### 4. Testing

Stateless agents enable simple testing:

```elixir
test "processes data immutably" do
  agent = StatelessAgent.new()

  {:ok, updated} = Jido.Agent.set(agent, %{
    input: test_data,
    format: "json"
  })

  assert agent != updated
  assert updated.state.input == test_data
end
```

## Key Benefits

1. **Predictable Behavior**: Pure functions with no side effects
2. **Thread Safety**: Immutable state eliminates race conditions
3. **Easy Testing**: Deterministic outputs for given inputs
4. **Simple Reasoning**: Explicit state transitions
5. **Functional Composition**: Natural operation chaining

## Anti-Patterns to Avoid

1. **State Mutation**: Never modify agent state directly
2. **Hidden Side Effects**: Keep operations pure and explicit
3. **Implicit Dependencies**: Make requirements clear in function signatures
4. **Complex State**: Keep state minimal and focused
5. **Mixed Paradigms**: Don't mix stateless and stateful approaches

## See Also

- [Agent Overview](overview.md)
- [Signal Overview](../signals/overview.livemd)
- [Action Development](../actions/overview.md)
- [Testing Guide](../signals/testing.md)

## Next Steps

1. Review the [Agent module documentation](https://hexdocs.pm/jido/Jido.Agent.html)
2. Explore the examples in the [Getting Started Guide](../getting-started.livemd)
3. Join the [GitHub Discussions](https://github.com/agentjido/jido/discussions)

This pattern provides a solid foundation for building predictable, maintainable agent workflows while leveraging Jido's core orchestration capabilities.
