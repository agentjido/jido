# Runtime

**After:** You can run agents in a supervision tree and manage parent/child hierarchies.

Agents run inside an `AgentServer` GenServer process. This guide covers starting agents, sending signals, and managing parent-child hierarchies.

> For complete API details, see `Jido.AgentServer` and `Jido.Await` moduledocs.

## Starting Agents

Use your instance module's `start_agent/2` to start agents (recommended):

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyAgent)
{:ok, pid} = MyApp.Jido.start_agent(MyAgent,
  id: "custom-id",
  initial_state: %{counter: 10}
)
```

Or start directly via `AgentServer`:

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent)
{:ok, pid} = Jido.AgentServer.start(agent: MyAgent, jido: MyApp.Jido)
```

## call/3 vs cast/2

**Synchronous** - blocks until signal is processed, returns updated agent:

```elixir
{:ok, agent} = Jido.AgentServer.call(pid, signal)
{:ok, agent} = Jido.AgentServer.call(pid, signal, 10_000)  # custom timeout
```

**Asynchronous** - returns immediately:

```elixir
:ok = Jido.AgentServer.cast(pid, signal)
```

## Signal Processing Flow

```
Signal → AgentServer.call/cast
       → route_signal_to_action (via strategy.signal_routes or default)
       → Agent.cmd/2
       → {agent, directives}
       → Directives queued → drain loop via DirectiveExec
```

The AgentServer routes incoming signals to actions based on your strategy's `signal_routes/0`, executes the action via `cmd/2`, and processes any returned directives.

## Parent-Child Hierarchy

### Spawning Children

Emit a `SpawnAgent` directive to create a child agent:

```elixir
%Directive.SpawnAgent{agent: ChildAgent, tag: :worker_1}
```

The parent:
- Monitors the child process
- Tracks children in `state.children` map by tag
- Receives `jido.agent.child.exit` signals when children exit

### Child Communication

Children can emit signals back to their parent:

```elixir
Directive.emit_to_parent(agent, signal)
```

### Stopping Children

```elixir
%Directive.StopChild{tag: :worker_1}
```

## Completion Detection

Agents signal completion via **state**, not process death. This allows retrieving results and keeps the agent available for inspection.

```elixir
# In your agent/strategy - set terminal status
agent = put_in(agent.state.status, :completed)
agent = put_in(agent.state.last_answer, result)
```

Check state externally:

```elixir
{:ok, state} = Jido.AgentServer.state(pid)

case state.agent.state.status do
  :completed -> state.agent.state.last_answer
  :failed -> {:error, state.agent.state.error}
  _ -> :still_running
end
```

## Await Helpers

The `Jido.Await` module provides conveniences for waiting on agent completion.

```elixir
# Wait for single agent
{:ok, result} = Jido.await(pid, 10_000)

# Wait for child by tag
{:ok, result} = Jido.await_child(parent, :worker_1, 30_000)

# Wait for all agents
{:ok, results} = Jido.await_all([pid1, pid2], 30_000)

# Wait for first completion
{:ok, {winner, result}} = Jido.await_any([pid1, pid2], 10_000)
```

### Utilities

```elixir
Jido.alive?(pid)                    # Check if agent is running
{:ok, children} = Jido.get_children(parent)  # List child agents
Jido.cancel(pid)                    # Cancel a running agent
```

For detailed await patterns, fan-out coordination, and testing without `Process.sleep`, see the [Await & Coordination](await.md) guide.

### Timeout Diagnostics

When `await` times out, you get a diagnostic map to help troubleshoot:

```elixir
case Jido.await(pid, 5_000) do
  {:ok, result} -> 
    result
  {:error, {:timeout, diag}} ->
    Logger.warning("Agent await timed out", diag)
    # diag includes: :hint, :server_status, :queue_length, :iteration, :waited_ms
    {:error, :timeout}
end
```

Use the `:hint` and `:server_status` to understand why the agent hasn't completed.

## Debug Mode

AgentServer can record recent events in an in-memory buffer to help diagnose agent behavior without configuring telemetry.

### Enable Debug Mode

At start:

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyAgent, debug: true)
# or
{:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent, debug: true)
```

Or toggle at runtime:

```elixir
:ok = Jido.AgentServer.set_debug(pid, true)
```

### Retrieve Events

```elixir
{:ok, events} = Jido.AgentServer.recent_events(pid, limit: 20)

Enum.each(events, fn e ->
  IO.inspect({e.type, e.data}, label: "event")
end)
```

Events are returned newest-first. Each event has:
- `:at` - monotonic timestamp in milliseconds
- `:type` - event type (`:signal_received`, `:directive_started`)
- `:data` - event-specific details

The buffer holds up to 50 events. This is a development aid, not an audit log.

## Related

- [Persistence & Storage](storage.md) — Hibernate/thaw and InstanceManager lifecycle
- [Worker Pools](worker-pools.md) — Pre-warmed agent pools for throughput
- [Await & Coordination](await.md) — Waiting on agent completion
