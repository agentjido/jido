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
       → route_signal_to_action (via strategy/agent/plugin routes)
       → Agent.cmd/2
       → {agent, directives}
       → Directives queued → drain loop via DirectiveExec
       → (for RunInstruction) execute instruction → call Agent.cmd/2 with result_action
```

The AgentServer routes incoming signals using strategy, agent, and plugin route tables (`signal_routes/1` callbacks), executes the action via `cmd/2`, and processes any returned directives.

## Parent-Child Hierarchy

### Logical Hierarchy vs OTP Supervision

Jido's parent/child model is a **logical hierarchy**, not nested OTP supervision.

- Parent and child agents are OTP peers under the same supervisor tree.
- The relationship is tracked with `ParentRef`, child-start signals, and process monitors.
- Parent death policies such as `on_parent_death: :stop` or `:emit_orphan` describe domain behavior, not OTP ancestry.

This is why a child can survive a logical parent death and become orphaned without becoming an independently supervised OTP child of that parent.

### Spawning Children

Emit a `SpawnAgent` directive to create a child agent:

```elixir
%Directive.SpawnAgent{agent: ChildAgent, tag: :worker_1}
# Or keep the child running across restarts/stops:
%Directive.SpawnAgent{agent: ChildAgent, tag: :durable_worker, restart: :permanent}
```

`SpawnAgent` is for live tracked child agents. It supports standard child
startup options such as `:id`, `:initial_state`, and `:on_parent_death`, but it
does not install `InstanceManager` lifecycle features like storage-backed
hibernate/thaw. If you need durable agent lifecycle, use
`Jido.Agent.InstanceManager` and treat reacquisition/reattachment as an explicit
workflow concern.

If the durable unit is a named team rather than a single agent, use
`Jido.Pod`. A pod runs through ordinary `InstanceManager` lifecycle, persists
its topology snapshot in `agent.state[:__pod__]`, and re-establishes live node
attachments explicitly with `Jido.Pod.reconcile/2` and `Jido.Pod.ensure_node/3`
after thaw. Root pod nodes are adopted into the pod manager, while owned nodes
are adopted under their logical runtime owner. Nested `kind: :pod` nodes are
acquired through their own `InstanceManager` and then reconciled recursively.
`Jido.Pod.get/3` is the default
happy path because it performs the initial eager reconciliation after
`InstanceManager.get/3`. See [Pods](pods.md).

The parent:
- Monitors the child process
- Tracks children in `state.children` map by tag
- Receives `jido.agent.child.exit` signals when children exit
- Rebinds tracked child info automatically if the child restarts

### Child Communication

Children can emit signals back to their parent:

```elixir
Directive.emit_to_parent(agent, signal)
```

`emit_to_parent/3` only works while the child is currently attached. If the
child becomes orphaned, `__parent__` is cleared and `emit_to_parent/3` returns
`nil` until a replacement parent explicitly adopts the child.

### Parent Death, Orphans, and Adoption

`on_parent_death` controls what happens when a logical parent disappears:

| Option | Behavior |
|--------|----------|
| `:stop` | Child shuts down |
| `:continue` | Child stays alive and becomes orphaned silently |
| `:emit_orphan` | Child stays alive, becomes orphaned, then handles `jido.agent.orphaned` |

When orphaning happens, Jido:

- clears `state.parent`
- clears `agent.state.__parent__`
- preserves the former parent in `state.orphaned_from`
- preserves the former parent in `agent.state.__orphaned_from__`

If you need to reattach the child, use `Directive.adopt_child/3` from the new
parent. Adoption restores `emit_to_parent/3` and `Jido.get_children/1`, and
the current binding is mirrored into `Jido.RuntimeStore` so later child
restarts come back under the adopted parent as well. See
[Orphans & Adoption](orphans.md) for the full lifecycle and caveats.

### Stopping Children

```elixir
%Directive.StopChild{tag: :worker_1}
```

`SpawnAgent` children default to `restart: :transient`, so `StopChild` cleanly removes
them instead of immediately restarting them.

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

AgentServer can record recent events in an in-memory buffer to help diagnose agent behavior without configuring telemetry. Debug mode can be enabled at two levels: for an entire Jido instance (all agents) or for individual agents.

### Instance-Level Debug

Enable debug recording for all agents in a Jido instance.

At boot time via config:

```elixir
config :my_app, MyApp.Jido, debug: true
config :my_app, MyApp.Jido, debug: :verbose
```

Or toggle at runtime:

```elixir
MyApp.Jido.debug(:on)
MyApp.Jido.debug(:verbose)
MyApp.Jido.debug(:off)
```

Query the current debug level:

```elixir
MyApp.Jido.debug()
```

Get full debug status including active agent counts:

```elixir
MyApp.Jido.debug_status()
```

When instance-level debug is enabled, recording is turned on for ALL agents managed by that instance.

### Per-Agent Debug

For surgical debugging of a single agent, enable debug mode on a specific process.

At start:

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyAgent, debug: true)
{:ok, pid} = Jido.AgentServer.start_link(agent: MyAgent, debug: true)
```

Or toggle at runtime:

```elixir
:ok = Jido.AgentServer.set_debug(pid, true)
```

### Retrieve Events

```elixir
{:ok, events} = MyApp.Jido.recent(pid, 20)
```

Or use the AgentServer API directly:

```elixir
{:ok, events} = Jido.AgentServer.recent_events(pid, limit: 20)
```

Inspect the results:

```elixir
Enum.each(events, fn e ->
  IO.inspect({e.type, e.data}, label: "event")
end)
```

Events are returned newest-first. Each event has:
- `:at` - monotonic timestamp in milliseconds
- `:type` - event type (`:signal_received`, `:directive_started`)
- `:data` - event-specific details

The buffer holds up to 500 events by default (configurable via `debug_max_events`). This is a development aid, not an audit log.

## Related

- [Debugging](debugging.md) — Systematic debugging workflow
- [Persistence & Storage](storage.md) — Hibernate/thaw and InstanceManager lifecycle
- [Worker Pools](worker-pools.md) — Pre-warmed agent pools for throughput
- [Await & Coordination](await.md) — Waiting on agent completion
- [Orphans & Adoption](orphans.md) — Advanced orphan lifecycle and explicit adoption
