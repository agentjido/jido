# Custom Strategies

**After:** You can implement a strategy for specialized execution patterns.

```elixir
defmodule RoundRobinStrategy do
  use Jido.Agent.Strategy

  alias Jido.Agent.Strategy.State, as: StratState

  @impl true
  def init(agent, _ctx) do
    agent = StratState.put(agent, %{
      module: __MODULE__,
      status: :idle,
      current_index: 0,
      total_executed: 0
    })
    {agent, []}
  end

  @impl true
  def cmd(agent, instructions, _ctx) do
    state = StratState.get(agent, %{})
    index = Map.get(state, :current_index, 0)

    # Execute only the instruction at current index
    case Enum.at(instructions, rem(index, length(instructions))) do
      nil ->
        {agent, []}

      instruction ->
        instruction = %{instruction | context: Map.put(instruction.context, :state, agent.state)}

        case Jido.Exec.run(instruction) do
          {:ok, result} ->
            agent = Jido.Agent.StateOps.apply_result(agent, result)
            agent = StratState.put(agent, %{state |
              current_index: index + 1,
              total_executed: state.total_executed + 1,
              status: :success
            })
            {agent, []}

          {:error, reason} ->
            error = Jido.Error.execution_error("Instruction failed", %{reason: reason})
            agent = StratState.put(agent, %{state | status: :failure})
            {agent, [%Jido.Agent.Directive.Error{error: error, context: :instruction}]}
        end
    end
  end
end
```

Use it in your agent:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "round_robin_agent",
    strategy: RoundRobinStrategy
end
```

## Strategy Responsibilities

Strategies control three things:

1. **Execution** — How `cmd/2` processes instructions
2. **Routing** — Which signals map to which actions (via `signal_routes/1`)
3. **State** — Tracking execution progress in `agent.state.__strategy__`

## Required Callback

### `cmd/3`

```elixir
@callback cmd(agent :: Agent.t(), instructions :: [Instruction.t()], ctx :: context()) ::
            {Agent.t(), [directive()]}
```

This is the only required callback. It receives normalized instructions and must return the updated agent plus any directives.

## Optional Callbacks

### `init/2`

Initialize strategy state. Called by AgentServer after `new/1`.

```elixir
@impl true
def init(agent, ctx) do
  agent = StratState.put(agent, %{
    module: __MODULE__,
    status: :idle,
    my_data: []
  })
  {agent, []}
end
```

### `tick/2`

Tick-based continuation for multi-step strategies. Called when you schedule a `:strategy_tick`.

```elixir
@impl true
def tick(agent, ctx) do
  # Continue long-running work
  {agent, []}
end
```

### `snapshot/2`

Return a stable view of strategy state for external inspection.

```elixir
@impl true
def snapshot(agent, _ctx) do
  state = StratState.get(agent, %{})

  %Jido.Agent.Strategy.Snapshot{
    status: Map.get(state, :status, :idle),
    done?: Map.get(state, :status) in [:success, :failure],
    result: Map.get(state, :result),
    details: %{custom_field: Map.get(state, :custom_field)}
  }
end
```

### `action_spec/1`

Schema for strategy-specific actions. Enables parameter normalization.

```elixir
@impl true
def action_spec(:my_internal_action) do
  %{
    schema: [query: [type: :string, required: true]],
    doc: "Internal action for this strategy"
  }
end
def action_spec(_), do: nil
```

### `signal_routes/1`

Declare signal-to-action routing handled by the strategy.

```elixir
@impl true
def signal_routes(_ctx) do
  [
    {"my_strategy.start", {:strategy_cmd, :start_action}},
    {"my_strategy.continue", {:strategy_cmd, :continue_action}}
  ]
end
```

## Strategy.Snapshot

The snapshot struct provides a stable interface for inspecting strategy state:

```elixir
%Strategy.Snapshot{
  status: :idle | :running | :waiting | :success | :failure,
  done?: boolean(),
  result: term() | nil,
  details: map()
}
```

Use `Snapshot.terminal?/1` to check if in a terminal state, or `Snapshot.running?/1` for active execution.

## Strategy State Helpers

The `Jido.Agent.Strategy.State` module provides helpers for managing `agent.state.__strategy__`:

```elixir
alias Jido.Agent.Strategy.State, as: StratState

# Get strategy state (with default)
state = StratState.get(agent, %{})

# Put new strategy state
agent = StratState.put(agent, %{status: :running, data: []})

# Update with function
agent = StratState.update(agent, fn state ->
  %{state | counter: state.counter + 1}
end)

# Status helpers
StratState.status(agent)      # :idle, :running, :waiting, :success, :failure
StratState.terminal?(agent)   # true if :success or :failure
StratState.active?(agent)     # true if :running or :waiting
StratState.set_status(agent, :running)

# Clear strategy state
agent = StratState.clear(agent)
```

## Minimal Custom Strategy Skeleton

```elixir
defmodule MyStrategy do
  use Jido.Agent.Strategy

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Agent.StateOps

  @impl true
  def init(agent, _ctx) do
    agent = StratState.put(agent, %{module: __MODULE__, status: :idle})
    {agent, []}
  end

  @impl true
  def cmd(agent, instructions, _ctx) do
    Enum.reduce(instructions, {agent, []}, fn instruction, {acc, directives} ->
      instruction = %{instruction | context: Map.put(instruction.context, :state, acc.state)}

      case Jido.Exec.run(instruction) do
        {:ok, result} ->
          {StateOps.apply_result(acc, result), directives}

        {:ok, result, effects} ->
          acc = StateOps.apply_result(acc, result)
          StateOps.apply_state_ops(acc, List.wrap(effects))

        {:error, reason} ->
          error = Jido.Error.execution_error("Failed", %{reason: reason})
          {acc, directives ++ [%Jido.Agent.Directive.Error{error: error, context: :instruction}]}
      end
    end)
  end
end
```

## When NOT to Write a Custom Strategy

**Don't write a custom strategy if:**

- You just need sequential action execution → Use `Direct`
- You need state machine transitions → Use `FSM`
- You want to modify action behavior → Write a different Action, not a Strategy
- You want pre/post processing → Use agent hooks (`on_before_cmd/2`, `on_after_cmd/3`)
- You want to route signals differently → Use plugin `router/1` callbacks

**Write a custom strategy when:**

- You need non-sequential execution (parallel, round-robin, priority-based)
- You're implementing complex control flow (behavior trees, planners)
- You need multi-step execution with ticks (LLM chains, async workflows)
- The execution model itself is the distinguishing feature

Most agents work fine with `Direct`. The FSM strategy handles 90% of cases that need more. Custom strategies are for the remaining 10%.

---

See [Strategies](strategies.md) for an overview of Direct vs FSM.

For FSM-specific patterns, see the [FSM Strategy Guide](fsm-strategy.livemd).
