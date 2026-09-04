# Agents

<!-- covers: jido.agents_and_actions.schema_defined_agents jido.agents_and_actions.pure_cmd_contract -->

**After:** You can define agents with schemas, hooks, and the `cmd/2`/`cmd/3` contract.

Agents are immutable data structures that hold state and respond to actions. The
core operation is `cmd/2` (or `cmd/3` with options), which processes actions and
returns an updated agent plus any runtime-owned directives.

Jido keeps agent decision logic pure. Actions may be pure or effectful.
Directives are for effects you want the runtime to own.

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
    default_plugins: true,                   # Load built-in plugins (Default: true)
    schedules: [                             # Declarative cron schedules (Default: [])
      {"*/5 * * * *", "heartbeat.tick", job_id: :heartbeat}
    ]
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
- `directives` describe runtime-owned external effects only—they never modify
  agent state
- Agent decision logic stays explicit and testable

Use an effectful action when the current step needs a result back now to continue
reasoning or update state. Use a directive when the workflow has already decided
on an outbound effect and wants the runtime or integration layer to own delivery.

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

### Optional state size budget

Set `max_state_size` to a byte limit when you define an agent:

```elixir
use Jido.Agent,
  name: "bounded_agent",
  max_state_size: 10 * 1024 * 1024
```

The default is `nil` (no limit). Jido measures the complete `agent.state` with
`:erlang.external_size/1`, including plugin, thread, and strategy data. This is
an external term size, not a process heap or total memory limit. The calculation
visits the state, so its cost grows with the state. No size calculation runs when
the limit is `nil`.

`set/2`, `validate/2`, and `restore/2` return
`{:error, %Jido.Error.ValidationError{kind: :state_size}}` when the candidate state
exceeds the limit. Error details contain `max_state_size` and `actual_state_size`.
`MyAgent.new/1` keeps its existing struct return contract and raises this error
for oversized initial state. The base `Jido.Agent.new/1` returns a tagged error.

A failed `cmd/2` or `cmd/3` returns the original agent and one error directive
with `context: :state_size`. It discards the command's other directives. This
also applies to before/after hooks and custom strategies. An action that has
already performed an external effect cannot be rolled back.

Core state helpers that return a struct, such as `StateOps.apply_result/2`,
`Strategy.State.put/2`, and the thread, memory, and plugin state helpers, raise
the same validation error. The command boundary converts it to an error
directive. `Jido.Agent.StateBudget.replace/2` is a tagged-result boundary for
custom code that replaces the complete state.

AgentServer checks initial state, command results, and directive results before
it accepts them. Runtime references count towards the limit. Persistence checks
the complete state after thread and plugin restoration. Leave room for runtime
metadata when you choose a budget. If mandatory orphan metadata cannot fit,
the runtime stops with a structured shutdown reason.

Jido does not choose which data to delete. The application can compact its state
and retry. Direct Elixir struct or map edits cannot be intercepted; call
`validate/2` or a checked state helper before you use such a value. An arbitrary
custom callback that replaces the public API must also use these checks.

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

If the module is primarily a durable coordinator for named collaborators, use
`Jido.Pod` instead of `Jido.Agent`. `Jido.Pod` wraps the same agent model and
adds a canonical topology plus a reserved singleton pod plugin.

## Further Reading

- [Actions](actions.md) — Defining actions that transform agent state
- [State Operations](state-ops.md) — Internal state transitions during `cmd/2`
- [Directives](directives.md) — External effects emitted by agents
- [Strategies](strategies.md) — Execution strategies for `cmd/2`
- [Plugins — Default Plugins](plugins.md#default-plugins) — Built-in plugins (identity, thread) and how to override them
- [Pods](pods.md) — Manager-led durable topologies built on top of agents
- `Jido.Agent` — Full module documentation
