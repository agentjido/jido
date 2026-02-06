# Core Loop

**After:** You can explain Jido in one sentence: "Signal → Action → cmd/2 → {agent, directives} → runtime executes directives."

This guide explains the mental model behind Jido — an Elm/Redux-inspired agent framework for Elixir.

## The Elm/Redux Pattern

Jido agents follow a pure functional architecture:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

**Key principles:**

1. **Agents are immutable structs** — `cmd/2` never mutates; it returns a new agent
2. **State changes and effects are separated** — the returned agent has updated state; directives describe effects
3. **Directives are not executed by agents** — the runtime (AgentServer) interprets them
4. **Same inputs → same outputs** — `cmd/2` is deterministic and testable

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
│  Agent.cmd/2 (pure function)                                    │
│  ───────────────────────────                                    │
│  Input:  agent struct + action                                  │
│  Output: {updated_agent, directives}                            │
└─────────────────────────────────────────────────────────────────┘
```

## Agent vs AgentServer

| Concept | What It Is | Responsibility |
|---------|------------|----------------|
| **Agent** | Immutable struct + module | Defines schema, handles `cmd/2`, pure logic |
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
| **Agent** | Immutable struct with state and schema. Defines `cmd/2` for pure transformations. |
| **Action** | Function that transforms agent state (may perform side effects). Defined in [jido_action](https://hexdocs.pm/jido_action). |
| **Directive** | Effect description for runtime execution (Emit, Spawn, Schedule, etc.). Never modifies state. |
| **Skill** | Composable capability module bundling actions, state, and routing rules. |
| **Strategy** | Execution pattern (Direct, FSM, custom) that controls how actions are processed. |
| **Signal** | CloudEvents-compliant message. Defined in [jido_signal](https://hexdocs.pm/jido_signal). |

## The Core Flow

```
Signal → AgentServer → Agent.cmd/2 → {agent, directives} → DirectiveExec
```

1. **Signal arrives** at AgentServer (via `call/3` or `cast/2`)
2. **AgentServer routes** signal to action using strategy's signal routes
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

**Separation of concerns**: Pure logic (Agent) vs. effectful runtime (AgentServer).

## Further Reading

- [Agents](agents.md) — Defining agents with schemas and hooks
- [Directives](directives.md) — Available effect descriptions
- [Plugins](plugins.md) — Composable capability modules
- [Runtime](runtime.md) — AgentServer and process management
- [Strategies](strategies.md) — Execution patterns

> **Ecosystem tutorials:** See [agentjido.xyz](https://agentjido.xyz) for recipes combining jido, jido_ai, and jido_memory.
