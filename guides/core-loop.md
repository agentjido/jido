# Core Loop

**After:** You can explain Jido in one sentence: "Signal → Action → cmd/2 → {agent, directives} → runtime executes directives."

This guide explains the mental model behind Jido, an autonomous agent framework
for Elixir built for workflows and multi-agent systems.

Jido combines immutable agents, actions, signals, directives, and an OTP
runtime so you can build agent systems as ordinary Elixir software.

The core boundary is: Jido keeps agent decision logic pure. Actions may be pure
or effectful. Directives are for effects you want the runtime to own.

## The Elm/Redux Pattern

Jido agents follow a functional state architecture:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

**Key principles:**

1. **Agents are immutable structs** — `cmd/2` never mutates; it returns a new agent
2. **State changes are explicit** — the returned agent has updated state
3. **Directives are not executed by agents** — the runtime (AgentServer) interprets them
4. **Actions own immediate work** — an action may perform I/O when it needs the result to update state
5. **Runtime-owned effects are directives** — emit, spawn, schedule, and stop decisions leave `cmd/2` as data

```
┌─────────────────────────────────────────────────────────────────┐
│                        Signal arrives                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  AgentServer (GenServer)                                        │
│  ─────────────────────────                                      │
│  • Routes signal to action                                      │
│  • Calls Agent.cmd/2                                            │
│  • Executes returned directives                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Agent.cmd/2 (agent decision boundary)                          │
│  ─────────────────────────────────────                          │
│  Input:  agent struct + action                                  │
│  Output: {updated_agent, directives}                            │
└─────────────────────────────────────────────────────────────────┘
```

## Agent vs AgentServer

| Concept | What It Is | Responsibility |
|---------|------------|----------------|
| **Agent** | Immutable struct + module | Defines schema, handles `cmd/2`, pure decision logic |
| **AgentServer** | GenServer process | Holds agent state, executes directives, routes signals |

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    schema: [count: [type: :integer, default: 0]]
end

agent = MyAgent.new()
{agent, directives} = MyAgent.cmd(agent, IncrementAction)

{:ok, pid} = MyApp.Jido.start_agent(MyAgent)
{:ok, agent} = Jido.AgentServer.call(pid, signal)
```

## Instance-Scoped Architecture

Jido uses explicit instances — no global singletons. Define an instance module and add it to your supervision tree:

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end
```

```elixir
children = [
  MyApp.Jido
]

Supervisor.start_link(children, strategy: :one_for_one)
```

This enables:
- Multiple isolated Jido instances in one application
- Clear ownership and supervision boundaries
- Easier testing with isolated instances

## Key Terms

| Term | Definition |
|------|------------|
| **Agent** | Immutable struct with state and schema. Defines `cmd/2` for explicit state transitions. |
| **Action** | Function that transforms agent state (may perform side effects). Defined in [jido_action](https://hexdocs.pm/jido_action). |
| **Directive** | Effect description for runtime execution (Emit, Spawn, Schedule, etc.). Never modifies state. |
| **Plugin** | Composable capability module bundling actions, state, and routing rules. |
| **Strategy** | Execution pattern (Direct, FSM, custom) that controls how actions are processed. |
| **Signal** | CloudEvents-compliant message. Defined in [jido_signal](https://hexdocs.pm/jido_signal). |

## Action Or Directive?

Use an effectful action when the current step needs a result back now to continue
reasoning or update state. Use a directive when the workflow has already decided
on an outbound effect and wants the runtime or integration layer to own delivery.

Examples:

- Reading a file so the action can parse it and update state can live in the action.
- Dispatching a domain event, spawning a child, scheduling future work, or
  stopping an agent should be returned as a directive.

## The Core Flow

```
Signal → AgentServer → Agent.cmd/2 → {agent, directives} → DirectiveExec
```

1. **Signal arrives** at AgentServer (via `call/3` or `cast/2`)
2. **AgentServer routes** signal to action using strategy, agent, and plugin routes
3. **Agent.cmd/2** executes the action, returns updated agent + directives
4. **DirectiveExec** processes directives (emit signals, spawn processes, schedule messages)

## Why This Architecture?

**Testability**: Test `cmd/2` directly without processes:

```elixir
agent = MyAgent.new()
{agent, directives} = MyAgent.cmd(agent, MyAction)
assert agent.state.count == 1
assert match?([%Directive.Emit{}], directives)
```

**Predictability**: No hidden state mutations. The agent you get back is complete.

**Composability**: Directives are data — inspect, transform, filter, or mock them.

**Separation of concerns**: Pure agent decisions, explicit action work, and
runtime-owned directive execution.

## Further Reading

- [Agents](agents.md) — Defining agents with schemas and hooks
- [Directives](directives.md) — Available effect descriptions
- [Plugins](plugins.md) — Composable capability modules
- [Runtime](runtime.md) — AgentServer and process management
- [Strategies](strategies.md) — Execution patterns

> **Ecosystem tutorials:** See [jido.run](https://jido.run) for recipes combining jido, jido_ai, and jido_memory.
