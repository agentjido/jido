# Agents

**After:** You can define agents with schemas, hooks, and the `cmd/2`/`cmd/3` contract.

Agents are immutable data structures that hold state and respond to actions. The core operation is `cmd/2` (or `cmd/3` with options), which processes actions and returns an updated agent plus directives for external effects.

## Defining an Agent

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",                        # Required - alphanumeric + underscores
    description: "My custom agent",          # Optional
    category: "example",                     # Optional
    tags: ["demo"],                          # Default: []
    vsn: "1.0.0",                            # Optional
    schema: [                                # State schema (see below)
      status: [type: :atom, default: :idle],
      counter: [type: :integer, default: 0]
    ],
    strategy: Jido.Agent.Strategy.Direct,    # Default
    plugins: [MyPlugin],                     # Default: []
    default_plugins: true                    # Load built-in plugins (Default: true)
end
```

## The `cmd/2` and `cmd/3` Contract

The fundamental operation:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
{agent, directives} = MyAgent.cmd(agent, action, opts)
```

**Key invariants:**

- The returned `agent` is always complete—no "apply directives" step needed
- `directives` describe external effects only—they never modify agent state
- `cmd/2` and `cmd/3` are pure functions—given same inputs, always same outputs

**Action formats:**

```elixir
# Action module with no params
{agent, directives} = MyAgent.cmd(agent, MyAction)

# Action with params
{agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}})

# Action with params and context
{agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}, %{user_id: 123}})

# Action with params, context, and per-instruction opts
{agent, directives} = MyAgent.cmd(agent, {MyAction, %{value: 42}, %{}, [timeout: 5000]})

# Full instruction struct
{agent, directives} = MyAgent.cmd(agent, %Instruction{action: MyAction, params: %{}})

# List of actions (processed in sequence)
{agent, directives} = MyAgent.cmd(agent, [Action1, {Action2, %{x: 1}}])
```

**Execution options via `cmd/3`:**

Pass options that apply to all actions in the command:

```elixir
# With timeout (5 second limit per action)
{agent, directives} = MyAgent.cmd(agent, MyAction, timeout: 5000)

# With timeout and no retries
{agent, directives} = MyAgent.cmd(agent, MyAction, timeout: 1000, max_retries: 0)

# Options applied to all actions in a list
{agent, directives} = MyAgent.cmd(agent, [Action1, Action2], timeout: 5000)
```

Supported options:
- `:timeout` — Maximum time (in ms) for each action to complete
- `:max_retries` — Maximum retry attempts on failure
- `:backoff` — Initial backoff time in ms (doubles with each retry)

## State Management

### `set/2` — Update State

Deep-merges attributes into agent state:

```elixir
{:ok, agent} = MyAgent.set(agent, %{status: :running})
{:ok, agent} = MyAgent.set(agent, counter: 5)
```

### `validate/2` — Validate Against Schema

```elixir
# Validate state, keeping extra fields
{:ok, agent} = MyAgent.validate(agent)

# Strict mode: only schema-defined fields are kept
{:ok, agent} = MyAgent.validate(agent, strict: true)
```

## Lifecycle Hooks

Optional callbacks for pure transformations before/after command processing.

### `on_before_cmd/2`

Called before action processing. Transform agent or action:

```elixir
def on_before_cmd(agent, action) do
  # Example: log the action being processed
  {:ok, agent} = set(agent, %{last_action: inspect(action)})
  {:ok, agent, action}
end
```

Use cases:
- Mirror action params into agent state
- Add default params based on current state
- Enforce invariants before execution

### `on_after_cmd/3`

Called after action processing. Transform agent or directives:

```elixir
def on_after_cmd(agent, action, directives) do
  # Example: auto-validate after every command
  {:ok, agent} = validate(agent)
  {:ok, agent, directives}
end
```

Use cases:
- Auto-validate state after changes
- Derive computed fields
- Add invariant checks

## Schema Options

Agent state is validated against a schema. Two formats are supported:

### NimbleOptions (legacy, familiar)

```elixir
use Jido.Agent,
  name: "my_agent",
  schema: [
    status: [type: :atom, default: :idle],
    counter: [type: :integer, default: 0],
    config: [type: {:map, :atom, :string}, default: %{}]
  ]
```

### Zoi (recommended for new code)

```elixir
use Jido.Agent,
  name: "my_agent",
  schema: Zoi.object(%{
    status: Zoi.atom() |> Zoi.default(:idle),
    counter: Zoi.integer() |> Zoi.default(0),
    config: Zoi.map() |> Zoi.default(%{})
  })
```

Both are handled transparently by the Agent module.

## Creating Agents

```elixir
# Create with defaults
agent = MyAgent.new()

# Create with custom ID
agent = MyAgent.new(id: "custom-id")

# Create with initial state
agent = MyAgent.new(state: %{counter: 10})
```

## Further Reading

- [Actions](actions.md) — Defining actions that transform agent state
- [State Operations](state-ops.md) — Internal state transitions during `cmd/2`
- [Directives](directives.md) — External effects emitted by agents
- [Strategies](strategies.md) — Execution strategies for `cmd/2`
- [Plugins — Default Plugins](plugins.md#default-plugins) — Built-in plugins (Identity, Thread) and how to override them
- `Jido.Agent` — Full module documentation
