# Deployment and Sizing

A Jido instance runs inside your application's supervision tree like any
other OTP supervisor. This guide shows where to place it, how it stops, how
to drain Agents before a deploy, and which limits control memory and load.

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Repo,
      MyApp.Jido,
      MyAppWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end

  @impl true
  def prep_stop(state) do
    MyApp.Jido.list_agents()
    |> Task.async_stream(fn {_id, pid} -> Jido.AgentServer.quiesce(pid) end,
      max_concurrency: 100,
      timeout: 10_000,
      on_timeout: :kill_task
    )
    |> Stream.run()

    state
  end
end
```

## Placement

OTP starts children in order and stops them in reverse order. Place the
instance:

- **after** what your Actions and persistence adapter need, such as the
  database Repo, HTTP pools, and PubSub; and
- **before** what sends Signals to Agents, such as the web endpoint and
  queue consumers.

The endpoint then stops first, so no new Signals arrive. Agents stop next,
while the Repo is still up for their last save.

Inside the instance, the Agent supervisor starts last, so it stops first.
The registry, task supervisor, and runner stay up until every Agent is gone.

## Shutdown

The instance child spec has `shutdown: 10_000`. Your application
supervisor waits 10,000 ms for the whole instance to stop, then kills it.
Each Agent Server worker has its own 10,000 ms limit inside that budget.

A plain shutdown doesn't drain. An Agent Server that is stopped in the
middle of a Turn kills its pre-commit work and records the Turn as
`:indeterminate`. The waiting caller exits. Committed state is safe: with persistence, each commit was
saved before its reply. Directives that hadn't finished don't run again.

To finish in-progress work first, quiesce the Agents in `prep_stop/1`, as
above. `quiesce/2`:

1. closes admission, so new calls return `{:error, :quiesced}`;
2. rejects Turns already queued: calls get the same error, and casts are
   dropped with an `AgentServer cast dropped` warning;
3. waits for the active Turn, its save, and its Directives; and
4. returns `:ok`.

The default budget is 5,000 ms per Agent. Pass `active: :cancel` to cancel
pre-commit work instead of waiting for it. Reads still work while an Agent is
quiesced. `resume/2` opens admission again.

Keep the total drain time below your platform's stop grace period. On
Kubernetes the default `terminationGracePeriodSeconds` is 30.

## Idle Agents

An Agent Server runs until you stop it. Set `idle_timeout:` to stop Agents
that receive no Turns:

```elixir
MyApp.Jido.start_agent(MyApp.Counter,
  id: "counter-1",
  persistence: :inherit,
  idle_timeout: :timer.minutes(15),
  idle_policy: :hibernate
)
```

| `idle_policy:` | On timeout | Exit reason |
| --- | --- | --- |
| `:stop` (default) | Stops with no extra save | `{:shutdown, :idle_timeout}` |
| `:hibernate` | Saves, then stops | `{:shutdown, :hibernate}` |

The timer starts when the Agent is ready, idle, open, and has no attached
owners. Turns and `touch/1` reset it. Reads don't. `idle_timeout:` defaults
to `:infinity`. `:hibernate` requires persistence; without it, startup fails
with `"invalid idle_policy"`.

`thaw/3` starts a hibernated Agent again from its last saved revision. Set
idle defaults for the whole instance in its `agent_server:` list. See
[Instances and Tenants](configuration-and-tenant-isolation.md).

## Limits

| Option | Default | Limits |
| --- | --- | --- |
| `turn_timeout:` | 60,000 ms | All pre-commit work in one Turn, retries included. |
| `admission_timeout:` (per call) | 5,000 ms | How long a call waits in the queue before it starts. |
| `max_postponed_signals:` | 1,000 | Turns queued behind the active one. Over the limit, calls return `{:error, {:overloaded, ...}}`. |
| `max_directives_per_turn:` | 1,000 | Directives one Turn can return. |
| `directive_timeout:` | 5,000 ms | All Directives of one Turn. |
| `commit_timeout:` | 5,000 ms | All Plugin `after_commit/3` hooks of one Turn. |
| `persistence_timeout:` | 5,000 ms | Each storage operation. |
| `max_tasks` (instance) | 1,000 | Children of the instance task supervisor. |

`max_tasks` limits `MyApp.Jido.task_supervisor_name()`, a
`Task.Supervisor` that your code can use for tasks tied to the instance.
In this release, Agent Servers don't run their own work under it, so it
doesn't limit Turns or Directives.

### Turn Sizing

One Agent runs one Turn at a time. Its throughput is about one divided by
the Turn duration: an Agent with 200 ms Turns completes about 5 Turns per
second, whatever the load on the rest of the node. Work across many Agents
runs in parallel.

When one Agent receives more Signals than it can handle:

- move slow I/O out of the Action and into a Directive, which runs after
  the reply;
- split the work across more Agents, one per entity; or
- lower `max_postponed_signals:` so callers get `:overloaded` early instead
  of waiting.

The Turn duration is in telemetry as
`jido.agent_server.turn.stop.duration`. See
[Observability](observe-agent-turns.livemd).

### Memory

Each live Agent has an activation supervisor, a Server process, its
committed state, its Plugin runtimes, and its queue. State size varies most.
Measure your own Agent in a release build:

```elixir
before = :erlang.memory(:processes)

for i <- 1..1_000 do
  {:ok, _pid} = MyApp.Jido.start_agent(MyApp.Counter, id: "probe-#{i}")
end

:erlang.garbage_collect()
div(:erlang.memory(:processes) - before, 1_000)
```

The result is bytes per Agent, including the registry entry. Repeat with a
realistic state. Use `idle_timeout:` to keep the number of live Agents near
the number of active ones.

Jido doesn't publish reference benchmark numbers. Measure on your hardware,
with your Actions and storage adapter.

## Clusters

Each Jido instance is local to one node. Its registry, namespace binding,
and partition IDs are node-local.

- Jido doesn't enforce one owner per Agent across a cluster. Two nodes can
  each start an Agent with the same namespace, partition, and ID.
- Persistence revision checks reject a stale write, but they aren't a
  writer lease. The second writer fails at its next save, after its Action
  has already run.
- Jido doesn't route a Signal to the node that runs an Agent.

To run Agents on more than one node, choose the owning node for each Agent
yourself. Use a consistent hash of the Agent ID, a distributed registry, or
a lease in your database. Start the Agent only on that node and send
Signals there.

## Next

- [Recovery Limits](recovery-and-effect-limits.md) – what restarts and
  thaws can't recover.
- [Admission and Deadlines](agent-server-admission.md) – queue limits,
  cancellation, and quiescence.
