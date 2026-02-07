# Jido Agent Development Guide

## Commands
- **Test all**: `mix test`
- **Test single file**: `mix test test/path/to/test_file.exs`
- **Test with coverage**: `mix test --cover` (80%+ threshold)
- **Build/compile**: `mix compile`
- **Quality check**: `mix quality` (format, dialyzer, credo) — must pass
- **Format code**: `mix format`
- **Type check**: `mix dialyzer`
- **Lint**: `mix credo`

## Code Style
- Pure Elixir library, not Phoenix/Nerves
- Use `snake_case` for functions/variables, `PascalCase` for modules
- Add `@moduledoc` and `@doc` to all public functions
- Use `@spec` for type specifications
- Pattern match with function heads instead of conditionals
- Return tagged tuples: `{:ok, result}` or `{:error, reason}`
- Use `with` statements for complex operations
- Prefix test modules with namespace: `JidoTest.ModuleName`
- Use `use Action` for action modules with name, description, schema
- Follow .cursorrules for detailed standards and examples

## Architecture Overview

### Core Pattern: Immutable Agent + `cmd/2` (Elm/Redux-inspired)

A **Jido Agent** is an immutable struct. The core operation is:

```elixir
{agent, directives} = MyAgent.cmd(agent, action)
```

- `cmd/2` is **pure**: same inputs → same outputs
- Returned `agent` is **fully updated**; directives never modify state
- Accepts: `MyAction`, `{MyAction, %{param: value}}`, `%Instruction{}`, or lists

### Schemas with Zoi

Agents and directives use **Zoi** schemas (preferred over NimbleOptions for new code):

```elixir
@schema Zoi.struct(
          __MODULE__,
          %{
            signal: Zoi.any(description: "Jido.Signal.t() to dispatch"),
            dispatch: Zoi.any(description: "Dispatch config") |> Zoi.optional()
          },
          coerce: true
        )

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

Single source of truth for fields, types, enforced keys, and validation.

### Actions vs. Directives vs. State Operations

| **Actions** | **Directives** | **State Operations** |
|-------------|----------------|----------------------|
| Transform state, may perform side effects | Describe *external effects* | Describe *internal state changes* |
| Executed by `cmd/2`, update `agent.state` | Bare structs emitted by agents | Applied by strategy layer |
| Can call APIs, read files, query databases | Runtime (AgentServer) interprets them | Never leave the strategy |

### State Operations (`Jido.Agent.StateOp`)

State operations are internal state transitions handled by the strategy layer during `cmd/2`. Unlike directives, they never reach the runtime.

| StateOp | Purpose |
|---------|---------|
| `SetState` | Deep merge attributes into state |
| `ReplaceState` | Replace state wholesale |
| `DeleteKeys` | Remove top-level keys |
| `SetPath` | Set value at nested path |
| `DeletePath` | Delete value at nested path |

```elixir
alias Jido.Agent.{Directive, StateOp}

# Actions can return state ops alongside directives
{:ok, result, [
  %StateOp.SetState{attrs: %{status: :processing}},
  %Directive.Emit{signal: my_signal}
]}
```

### Core Directives

| Directive | Purpose | Tracking |
|-----------|---------|----------|
| `Emit` | Dispatch a signal via configured adapters | — |
| `Error` | Signal an error from cmd/2 | — |
| `Spawn` | Spawn generic BEAM child process | None (fire-and-forget) |
| `SpawnAgent` | Spawn child Jido agent with hierarchy | Full (monitoring, exit signals) |
| `StopChild` | Gracefully stop a tracked child agent | Uses children map |
| `Schedule` | Schedule a delayed message | — |
| `Stop` | Stop the agent process (self) | — |

**Spawn vs SpawnAgent**: Use `Spawn` for generic Tasks/GenServers that don't need parent-child semantics. Use `SpawnAgent` for Jido agents that need hierarchy tracking, `emit_to_parent/3`, and lifecycle management via `StopChild`.

### Agent vs. AgentServer

- **Agent module** (`use Jido.Agent`): Pure, stateless. Owns schema and `cmd/2`.
- **AgentServer**: GenServer wrapper. Holds agent in process state, executes directives.

### Multi-Agent Patterns

- `%Directive.SpawnAgent{}` — spawn child agent with parent-child hierarchy
- `%Directive.StopChild{}` — gracefully stop a tracked child by tag
- `Directive.emit_to_pid(signal, pid)` — direct signal to specific process
- `Directive.emit_to_parent(agent, signal)` — child signals back to parent

## Quality Gates

1. `mix test --cover` — 80%+ coverage threshold
2. `mix quality` — format, credo, dialyzer must pass
3. End-to-end examples in `/examples`

## Git Commit Guidelines

Use **Conventional Commits** format for all commit messages:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation only
- `style` - Formatting, no code change
- `refactor` - Code change that neither fixes a bug nor adds a feature
- `test` - Adding or updating tests
- `chore` - Maintenance tasks, dependency updates

**Examples:**
```
feat(agent): add new directive for child process management
fix(server): handle timeout edge case in signal dispatch
docs: update architecture overview
test(plugin): add plugin integration tests
chore(deps): bump jido_action to 2.0.0-rc.0
```

---

> **Note**: `Jido.AI.*` modules and `req_llm` are incubating. They will be extracted to a separate package before 1.0 release. Treat as experimental.