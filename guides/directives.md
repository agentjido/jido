# Directives

**After:** You can emit directives from actions to perform effects without polluting pure logic.

Directives are **pure descriptions of external effects**. Agents emit them from `cmd/2` callbacks; the runtime (`AgentServer`) executes them.

**Key principle**: Directives never mutate state directly; state changes happen through `cmd/2` return values (including `result_action` callbacks used by `RunInstruction`).

## Directives vs State Operations

Jido separates two distinct concerns:

| Concept | Module | Purpose | Handled By |
|---------|--------|---------|------------|
| **Directives** | `Jido.Agent.Directive` | External effects (emit signals, spawn processes) | Runtime (AgentServer) |
| **State Operations** | `Jido.Agent.StateOp` | Internal state transitions (set, replace, delete) | Strategy layer |

State operations are applied during `cmd/2` and never leave the strategy layer. Directives are passed through to the runtime for execution. See the [State Operations guide](state-ops.md) for details on `SetState`, `SetPath`, and other state ops.

```elixir
def cmd({:notify_user, message}, agent, _context) do
  signal = Jido.Signal.new!("notification.sent", %{message: message}, source: "/agent")
  
  {:ok, agent, [Directive.emit(signal)]}
end
```

## Core Directives

| Directive | Purpose | Tracking |
|-----------|---------|----------|
| `Emit` | Dispatch a signal via configured adapters | — |
| `Error` | Signal an error from cmd/2 | — |
| `Spawn` | Spawn generic BEAM child process | None (fire-and-forget) |
| `SpawnAgent` | Spawn child Jido agent with hierarchy | Full (monitoring, exit signals) |
| `StopChild` | Gracefully stop a tracked child agent | Uses children map |
| `Schedule` | Schedule a delayed message | — |
| `RunInstruction` | Execute `%Instruction{}` at runtime and route result back through `cmd/2` | — |
| `Stop` | Stop the agent process (self) | — |
| `Cron` | Recurring scheduled execution | — |
| `CronCancel` | Cancel a cron job | — |

## Helper Constructors

```elixir
alias Jido.Agent.Directive

# Emit signals
Directive.emit(signal)
Directive.emit(signal, {:pubsub, topic: "events"})
Directive.emit_to_pid(signal, pid)
Directive.emit_to_parent(agent, signal)

# Spawn processes
Directive.spawn(child_spec)
Directive.spawn_agent(MyWorkerAgent, :worker_1)
Directive.spawn_agent(MyWorkerAgent, :processor, opts: %{initial_state: %{batch_size: 100}})

# Stop processes
Directive.stop_child(:worker_1)
Directive.stop()
Directive.stop(:shutdown)

# Scheduling
Directive.schedule(5000, :timeout)
Directive.cron("*/5 * * * *", :tick, job_id: :heartbeat)
Directive.cron_cancel(:heartbeat)

# Runtime instruction execution
Directive.run_instruction(instruction, result_action: :fsm_instruction_result)

# Errors
Directive.error(Jido.Error.validation_error("Invalid input"))
```

## RunInstruction

`RunInstruction` is used by strategies that keep `cmd/2` pure. Instead of calling
`Jido.Exec.run/1` inline, the strategy emits `%Directive.RunInstruction{}` and the
runtime executes it, then routes the result back through `cmd/2` using `result_action`.

## Spawn vs SpawnAgent

| `Spawn` | `SpawnAgent` |
|---------|--------------|
| Generic Tasks/GenServers | Child Jido agents |
| Fire-and-forget | Full hierarchy tracking |
| No monitoring | Monitors child, receives exit signals |
| — | Enables `emit_to_parent/3` |

```elixir
# Fire-and-forget task
Directive.spawn({Task, :start_link, [fn -> send_webhook(url) end]})

# Tracked child agent
Directive.spawn_agent(WorkerAgent, :worker_1, opts: %{initial_state: state})
```

## Custom Directives

External packages can define their own directives:

```elixir
defmodule MyApp.Directive.CallLLM do
  defstruct [:model, :prompt, :tag]
end
```

The runtime dispatches on struct type — no core changes needed. Implement a custom `AgentServer` or middleware to handle your directive types.

## Complete Example: Action → Directive Flow

Here's a full example showing an action that processes an order and emits a signal:

```elixir
defmodule ProcessOrderAction do
  use Jido.Action,
    name: "process_order",
    schema: [order_id: [type: :string, required: true]]

  alias Jido.Agent.{Directive, StateOp}

  def run(%{order_id: order_id}, context) do
    signal = Jido.Signal.new!(
      "order.processed",
      %{order_id: order_id, processed_at: DateTime.utc_now()},
      source: "/orders"
    )

    {:ok, %{order_id: order_id}, [
      StateOp.set_state(%{last_order: order_id}),  # Applied by strategy
      Directive.emit(signal)                        # Passed to runtime
    ]}
  end
end
```

When the agent runs this action via `cmd/2`:
1. The strategy applies `StateOp.set_state` — agent state is updated
2. The `Emit` directive passes through to the runtime
3. `AgentServer` dispatches the signal via configured adapters

---

See `Jido.Agent.Directive` moduledoc for the complete API reference.

**Related guides:** [State Operations](state-ops.md)
