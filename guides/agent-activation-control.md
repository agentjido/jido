# Supervision and Lifecycle

Every started Agent runs inside an activation: a small supervisor that holds
its Agent Server and its nested members. This guide shows how the activation
recovers from a crash, what each kind of stop does, and how idle Agents shut
down on their own.

```elixir
{:ok, _} = Jido.start()
{:ok, counter} = Jido.start_agent(MyApp.Counter, id: "counter-1", idle_timeout: :timer.minutes(10))

:ok = Jido.AgentServer.attach(counter)   # keep it alive while this process runs
:ok = Jido.stop_agent("counter-1")       # stops the activation and its members
```

## The Process Tree

```text
Jido instance (Supervisor, :one_for_one)
├── Runic.Runner, Task.Supervisor, Registry, RuntimeStore
└── DynamicSupervisor (:one_for_one)
    └── activation: Jido.AgentServer.Supervisor (:one_for_all, :transient)
        ├── Jido.AgentServer                    (:transient, significant)
        ├── :owned_agents DynamicSupervisor     (nested member activations)
        └── Plugin runtime supervisors
```

`Jido.start_agent/2` starts one activation under the instance's
DynamicSupervisor. The activation uses `:one_for_all`: if the Server or a
required Plugin runtime crashes, all of them restart together. Owned nested
members restart with it, from their initial state.

`Jido.AgentServer.activation/1` returns the activation PID.
[Inspect Activations](inspect-and-control-activations.livemd) reads the tree.

## Crash Recovery

The activation keeps a checkpoint in memory: the last committed Agent and its
revision. When the Server process crashes, the activation restarts it from
that checkpoint.

These examples use a counter with one `counter.increment` route that adds 1:

```elixir
defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/counter")

    route "counter.increment", as: :increment do
      action %{}, name: "increment", schema: Zoi.object(%{}), output_schema: Zoi.map(), context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
      state from: output()
    end
  end
end

wait_for = fn fun ->
  Enum.find_value(1..300, fn _ -> Process.sleep(10) && fun.() end)
end

{:ok, _} = Jido.start()
```

Commit two Turns, kill the Server, and read the restarted one:

```elixir
{:ok, counter} = Jido.start_agent(MyApp.Counter, id: "counter-1")
increment = MyApp.Counter.increment_signal!(%{})
for _ <- 1..2, do: {:ok, _, []} = Jido.AgentServer.call(counter, increment)

activation = Jido.AgentServer.activation(counter)
Process.exit(counter, :kill)

restarted = wait_for.(fn ->
  pid = Jido.whereis_agent("counter-1")
  pid != counter && pid
end)

snapshot = Jido.AgentServer.snapshot(restarted)
{Jido.AgentServer.activation(restarted) == activation, snapshot.state_version, snapshot.agent.state.count}
# => {true, 2, 2}
```

The new Server has a new PID, the same activation, and the committed state.
Hold a stable Ref or look the Agent up by ID instead of keeping the PID. See
[Start and Address Agents](start-and-address-live-agents.livemd).

The checkpoint is local memory, not storage:

- It survives a Server crash, not the loss of the activation or the node.
- It doesn't replay the Turn that was running or rerun Directives.
- Queued Turns and pending callers are lost. Their callers get an exit or
  `{:error, %Jido.Error.ExecutionError{}}`.
- Owners and closed admission are runtime data. Closed admission stays closed
  after recovery.

With persistence configured, recovery reloads the Agent from storage instead.
Storage can be ahead of the local checkpoint. See
[Durability Model](durability-model.md).

### Restart Limits

The activation allows 3 restarts in 5 seconds. One more crash in that window
stops the activation. Its restart type is `:transient` and it exits with
`:shutdown`, so the DynamicSupervisor doesn't restart it:

```elixir
for _ <- 1..4 do
  if pid = wait_for.(fn -> Jido.whereis_agent("counter-1") end), do: Process.exit(pid, :kill)
  Process.sleep(30)
end

Process.sleep(200)
{Jido.whereis_agent("counter-1"), Process.alive?(activation)}
# => {nil, false}
```

The state is gone. Start the Agent again, or use persistence to keep it.

An exception in an Action doesn't crash the Server. It fails the Turn and
returns an error. See [Admission and Deadlines](agent-server-admission.md).

## Stopping

Every stop takes down the activation, its members, and its Plugin runtimes.
None of them restart.

| Call | Notes |
| --- | --- |
| `Jido.stop_agent(id_or_pid)` | Default instance. `{:error, :not_found}` for an unknown ID. |
| `Jido.stop_agent(instance, id_or_pid, partition: p)` | A named instance and partition. |
| `MyApp.Jido.stop_agent_ref(ref, reason, timeout)` | Through a stable Ref. |
| `Jido.AgentServer.stop(server, reason \\ :shutdown, timeout \\ 5_000)` | Any reason. Returns `:ok` after the activation exits. |
| `Jido.stop(instance)` | Stops the instance and every Agent in it. |

`Jido.AgentServer.stop/3` wraps a reason other than `:normal` or `:shutdown`
in `{:shutdown, reason}`:

```elixir
{:ok, stopped} = Jido.start_agent(MyApp.Counter, id: "counter-2")
monitor = Process.monitor(stopped)
:ok = Jido.AgentServer.stop(stopped, :retired)

receive do
  {:DOWN, ^monitor, :process, _, reason} -> {reason, Jido.whereis_agent("counter-2")}
end
# => {{:shutdown, :retired}, nil}
```

A stop terminates the running Turn. Like cancellation, it can't undo I/O the
Action already did. To finish in-flight work first, call
`Jido.AgentServer.quiesce/2`, then stop.

A failed Turn can also stop the Server through `error_policy:`. It exits with
`{:shutdown, :agent_error}` or another `{:shutdown, reason}` and isn't
restarted. See [Admission and Deadlines](agent-server-admission.md).

## Idle Shutdown

`idle_timeout:` stops an Agent that has nothing to do. The default is
`:infinity`. A finite timeout starts counting when the Server is ready, idle,
open to admission, and has no owners.

```elixir
{:ok, idle} = Jido.start_agent(MyApp.Counter, id: "idle-1", idle_timeout: 100)
monitor = Process.monitor(idle)

receive do
  {:DOWN, ^monitor, :process, _, reason} -> reason
after
  1_000 -> :still_running
end
# => {:shutdown, :idle_timeout}
```

| Event | Effect on the idle timer |
| --- | --- |
| A Turn | Resets it. |
| `touch/1` | Resets it. |
| Reads: `agent/2`, `status/2`, `snapshot/2` | No effect. |
| `attach/3` | Stops it while any owner is attached. |
| `detach/3` of the last owner, or its exit | Starts a new full period. |
| `quiesce/2` | Stops it until `resume/2`. |

Attach the process that uses the Agent, such as a LiveView or a socket. The
Server monitors each owner, so an owner crash counts as a detach:

```elixir
{:ok, owned} = Jido.start_agent(MyApp.Counter, id: "idle-2", idle_timeout: 100)
:ok = Jido.AgentServer.attach(owned)
Process.sleep(250)
alive = Process.alive?(owned)

monitor = Process.monitor(owned)
:ok = Jido.AgentServer.detach(owned)

receive do
  {:DOWN, ^monitor, :process, _, reason} -> {alive, reason}
end
# => {true, {:shutdown, :idle_timeout}}
```

`idle_policy:` sets what happens when the timer fires:

| Policy | Effect |
| --- | --- |
| `:stop` | Stop with `{:shutdown, :idle_timeout}`. No save. The default. |
| `:hibernate` | Save the Agent, then stop. Requires persistence. |

Without persistence, `idle_policy: :hibernate` fails startup with
`"invalid idle_policy"`.

## Hibernate and Thaw

`Jido.AgentServer.hibernate/2` quiesces the Agent, saves its current revision,
and stops the activation. Starting the same ID later thaws it from storage. It
requires persistence:

```elixir
{:ok, plain} = Jido.start_agent(MyApp.Counter, id: "counter-3")
Jido.AgentServer.hibernate(plain)
# => {:error, %{reason: :persistence_not_configured, resumable?: true}}
```

`resumable?: true` means nothing was written and the Agent is still open. A
conflict or an uncertain write returns `resumable?: false`, keeps admission
closed, and forbids `resume/2`.

Hibernate acts on one activation. It doesn't hibernate independent child
Agents. The save, thaw, and conflict rules are in
[Durable Activation](durable-agent-activation.livemd).

```elixir
:ok = Jido.stop_agent("counter-3")
:ok = Jido.stop()
```

## Next

- [Durability Model](durability-model.md) for what persistence saves and when.
- [Durable Activation](durable-agent-activation.livemd) to hibernate and thaw.
