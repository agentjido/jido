> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Runtime topology

[Design overview](README.md) | Previous: [Durability guarantee](durability-guarantee.md) | Next: [Observability](observability.md)

- Depends on: OTP, Agent Server, Plugin configuration, and Directives.
- Defines: supervision ownership, stable Agent identity, Signal delivery, and
  Plugin runtime behavior.

## OTP runtime shape

One Jido instance owns the complete core runtime:

```text
MyApp.Jido                              :rest_for_one
├── MyApp.Jido.Registry                Registry
├── MyApp.Jido.TaskSupervisor          short Turn and Directive tasks
├── MyApp.Jido.PluginRuntimePool       DynamicSupervisor
└── MyApp.Jido.AgentPool               DynamicSupervisor
    ├── Agent.Server A
    ├── Agent.Server B
    └── Agent.Server C
```

The child order records runtime dependencies. A Registry failure stops the
later pools so the instance does not keep live Agents with stale names. An
individual Agent Server failure stays inside `AgentPool`.

`AgentPool` is a dynamic lifecycle set. It is not a shared work queue. Each
Agent Server has one OTP mailbox and processes one Signal at a time. Every
Agent Server is a direct peer in the pool. Core has no nested Agent supervision
tree and no logical relationship store.

Each live evaluation uses one owner-bound task under `TaskSupervisor`.
Readiness and Directive work also use bounded tasks. Each task carries its
owner PID, Turn ID when applicable, and task reference. It stops when its owner
Server stops. A late or duplicate task result cannot change Agent state.

An Agent Server is a `:transient` child. An abnormal failure can restart it.
Its child specification preserves one explicit restart source:

- A persistent Agent uses its Agent Ref and Jido instance. Restart loads the
  latest durable Record and validates its module definition revision.
- A nonpersistent Agent uses the complete initial Agent supplied at start.
  Restart resets to that value and state version zero. It does not recover
  later in-memory commits or pending Plugin work.

A normal stop or hibernation does not restart the Server. A pool or instance
restart does not discover persistent Agents by itself. Explicit activation or
a future catalog policy supplies Agent identity.

## Agent identity and Signal delivery

One value identifies an Agent across live lookup, persistence, Directives, and
future transport:

```elixir
%Jido.Agent.Ref{
  namespace: "my-app/primary",
  partition: nil,
  id: "order-123"
}
```

The identity tuple is `{namespace, partition, id}`. Registry permits only one
live Agent Server for one Ref. The Agent module and its definition revision are
stored in the checkpoint. They are not part of process identity.

`Jido.Agent.Ref` is a Zoi-backed public struct. `namespace` and `id` are
nonempty strings. `partition` is nil or a nonempty string. No PID is stable
Agent identity.

Agent-to-Agent communication uses a Signal Directive that contains the target
Agent Ref. Dispatch resolves the current local Server for each delivery. A
cached PID is observation data only.

Core defines logical parent-child relationships, owner-local tags, adoption,
child stop, and parent-death policy. These records belong to runtime state.
Applications keep desired work, retries, and domain policy in Agent or Plugin
state and change them through Signals.

`SpawnAgent`, `AdoptChild`, `StopChild`, `EmitToChild`, and `EmitToParent` are
core Directives. `SpawnAgent` accepts an explicit `node` target. The target
runs the same named Jido instance and owns the child's process and execution.
The parent keeps the logical relationship. See
[remote owned children](remote-owned-children.md) for creation identity,
uncertain outcomes, shutdown, and the limits of this first implementation.
Automatic placement, cluster-wide identity, and failover authority remain
separate contracts.

## Plugin runtime ownership

A Plugin runtime owns processes and external resources for one Plugin
instance. It does not own command preparation or candidate state assembly.
Actions can call external resources during execution. Runtime work includes:

- Start, readiness, replacement, and shutdown.
- Signal production through the Ref-first instance API.
- Dispatch of Directives owned by the Plugin instance.
- Runtime logs, traces, and metrics.

A Plugin that only dispatches typed Directives need not own a runtime process.
The Agent Server runs its callback in a supervised task after commit, with the
same ordering, timeout, and failure rules. A configured runtime that is missing
is an error; the Server must not silently use the process-free form instead.

Plugin runtime hosts, when required, live in `PluginRuntimePool`. Each host is bound to one
`{agent_ref, plugin_id}` and monitors the internal Agent Server. The host stops
its runtime root when that Server stops.

The runtime behavior has three callbacks:

```elixir
@callback child_spec(Jido.Plugin.Runtime.Init.t()) ::
            Supervisor.child_spec()

@callback await_ready(runtime_ref :: pid(), timeout()) ::
            :ok | {:error, Jido.Error.t()}

@callback dispatch(
            runtime_ref :: pid(),
            directive :: struct(),
            Jido.Plugin.Runtime.Context.t()
          ) :: :ok | {:error, Jido.Error.t()}
```

`child_spec/1` defines the supervised runtime root. `await_ready/2` confirms
that the root can serve its declared capability. `dispatch/3` handles one
owned post-commit Directive. `use Jido.Plugin.Runtime` can supply an immediate
successful `await_ready/2`. A runtime must define `dispatch/3` only when it
owns Directive types.

The host normalizes the returned root child specification to
`restart: :temporary`. The Plugin can use a normal supervision tree inside
that root. It cannot make the host restart the root from captured old input.

## Runtime initialization and replacement

The Agent Server supplies one defined start value:

```elixir
%Jido.Plugin.Runtime.Init{
  agent_ref: agent_ref,
  plugin: %Jido.Plugin{},
  plugin_state: %{cron: updated_cron},
  state_version: 8,
  jido: MyApp.Jido
}
```

`plugin` is the complete validated Plugin configuration. `plugin_state` is the
complete Agent-owned state for that Plugin, or nil for a stateless Plugin.
`state_version` identifies the Agent state that owns it.

Every first start uses the validated initial Plugin state at version zero.
During persistent creation, this state is provisional until the initial Record
commits. Jido admits no Signal and dispatches no Directive until every runtime
is ready and that write succeeds. A readiness failure stops all provisional
runtime roots and writes no Record.

Every activation and runtime replacement uses the latest committed Plugin
state and state version. For a nonpersistent live Agent, committed means its
current in-memory commit. A runtime exit stays inside its host. The host
reports the exit to the Agent Server and waits. The Server builds a fresh Init
and asks the host to start the replacement. The host never reuses an earlier
Init.

Runtime startup and `await_ready/2` must be safe to repeat. They reconcile
disposable runtime resources from the supplied Plugin state. Runtime-local
PIDs, timers, monitors, and library handles are not restored.

The Plugin root does not receive an Agent Server PID. It sends a new Signal
through the `call/3` or `cast/3` function on the module in `init.jido`, with
`init.agent_ref` as the target. This keeps the Ref-first instance facade as the
only public live Agent boundary.

## Directive dispatch context

A post-commit dispatch receives one narrow committed context:

```elixir
%Jido.Plugin.Runtime.Context{
  turn_id: "019...",
  agent_ref: agent_ref,
  plugin_id: :scheduler,
  source_signal_id: "019...",
  signal_id: "019...",
  trace: %Jido.Signal.Trace{},
  state_version: 8,
  plugin_state: %{cron: updated_cron},
  jido: MyApp.Jido
}
```

The context carries the current dispatch commit coordinates, complete
owned Plugin state, and trace data. It does not carry a complete Agent, Signal,
private Turn value, or Agent Server state. The Directive contains all data
required for its external effect.

Init validation checks the declared runtime module, complete Plugin state, and
nonnegative state version. A stateless Plugin requires nil state. Context
validation checks the Plugin owner and committed Plugin state.

A dispatch error or timeout follows the Agent runtime error policy. Durable
work is an explicit capability. Its Plugin stores work IDs and pending intent
in its checkpoint state, retries through its worker, and commits completion
through another Signal. Ordinary Directives are not replayed automatically.

There is no Plugin terminate callback and no callback for every Agent state
change. OTP owns runtime shutdown. A Plugin that must change Agent state sends
a Signal. A Plugin that must reconcile runtime resources after a state change
emits an owned Directive in that Turn.

## Runtime observation

The Ref-first instance API returns runtime status:

```elixir
MyApp.Jido.plugin_runtimes(agent_ref, timeout: 5_000)

%Jido.Plugin.Runtime.Status{
  plugin_id: :scheduler,
  module: MyApp.SchedulerPlugin.Runtime,
  pid: runtime_pid | nil,
  state_version: 8,
  status: :starting | :ready | :restarting | :unavailable
}
```

The PID is current local observation only. `state_version` identifies the
Plugin state supplied to the current or attempted runtime root. Status
validation requires a PID only for a live local state and always requires a
nonnegative state version.

## Required tests

- Agent Servers are direct peers under `AgentPool`.
- Core starts no relationship store and exposes no relationship API or type.
- Cross-Agent Signal delivery resolves a fresh PID from Agent Ref.
- An owner-bound task stops with its Agent Server.
- A persistent restart restores the latest Record.
- A nonpersistent restart uses the exact preserved initial Agent and version
  zero.
- A first persistent runtime start uses provisional initial Plugin state and
  writes no Record when readiness fails.
- Every activation and runtime replacement uses the latest committed Plugin
  state and version.
- The runtime host cannot restart a root with an old Init.
- A stateless runtime receives nil Plugin state.
- A Plugin runtime sends Signals only through the Ref-first instance API.
- Pending capability work survives later Agent commits until its completion
  or cancellation policy changes it.
