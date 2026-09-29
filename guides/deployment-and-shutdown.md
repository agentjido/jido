# Deployment and Shutdown

Run a Jido instance as part of your application supervision tree. The instance
owns the registry, task supervisor, runtime coordination store, spawn registry,
and dynamic Agent supervisor for its actors.

## Supervise the instance

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [MyApp.Jido]
    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end
end
```

Do not start production actors with the Livebook helper `Jido.start/1`. Use a
named instance module so configuration, registry names, and ownership are clear.

The top-level Jido child has a 10-second shutdown timeout. Agent actors are
children of its dynamic supervisor. A normal application shutdown stops the
instance and its actors under OTP supervision.

## Put an Agent directly under application supervision

A fixed set of Agents needs no Topology. Add each `Jido.AgentServer` after its
named Jido infrastructure. Give the Agent and the OTP child explicit IDs:

```elixir
children = [
  MyApp.Jido,
  Supervisor.child_spec(
    {Jido.AgentServer,
     jido: MyApp.Jido, agent: MyApp.Counter, id: "counter", restart: :transient},
    id: :counter
  )
]

Supervisor.start_link(children, strategy: :rest_for_one, max_restarts: 3, max_seconds: 5)
```

`:rest_for_one` starts infrastructure first and stops the Agent first. It also
replaces the Agent if the infrastructure is replaced. `:transient` restarts an
abnormal Agent exit but leaves normal exit, explicit stop, and hibernation
stopped. The supervisor retains a stopped child specification. Use
`Supervisor.restart_child/2` for an explicit restart, or terminate and delete
the child specification when removing it from the application.

See the working [OTP supervision example](https://github.com/agentjido/jido/tree/release/v3/examples/01_basic/01_05_otp_supervision).
It commits state, kills the Agent, checks OTP recovery and Plugin cleanup, and
stops the application. It uses no Topology or startup Task.

Use Topology when group expansion, graph validation, declared connections,
aggregate readiness, or target changes are required. Its local subtree uses
OTP restart limits; a coordinator restart preserves healthy Agents. Read the
[ownership contract](topology-supervision.md) before selecting an outer restart
policy. Repair cannot restart a local member that was explicitly stopped or
recreate a subtree that reached its restart limit.

## Start actors from stable intent

Start long-lived actors from application supervision, a topology activation, or
another durable application decision. Do not depend on the lifetime of the
request process that called `start_agent/2`. A managed actor links to its Jido
supervisor, not to that caller.

An actor ID is unique inside one Jido instance and partition. Use stable IDs for
actors that restore durable state. Use a partition only when the application
has a clear namespace rule.

## Plan restarts

An abnormal `AgentServer` restart can use the instance runtime checkpoint while
the Jido instance stays alive. Durable persistence is necessary when an Agent
must survive an instance or node restart.

If the local runtime store is unavailable during a restart, the Agent does not
activate from its initial state. Restore the store worker, then start the Agent
again. The local checkpoint is ephemeral: loss of the instance or its ETS table
still requires durable persistence to recover committed state.

If the local Registry restarts, live Agents register again under the same IDs.
The instance keeps an Agent ID claim while its owner is alive. A new Agent with
that ID cannot start during the Registry gap. Lookup and Ref resolution can
return `:not_found` until the owner registers again. This recovery applies to
one local instance; it does not coordinate IDs across nodes.

Plugin runtime processes restart from Plugin specifications. Signal bus
subscribers and application connections must also have a restart or
reconciliation rule. Do not put a PID or connection in durable Agent state.

Plugin wrappers run in the Jido Dynamic Supervisor. Agent Servers can run in
that pool, an application supervisor, or a Topology member supervisor.
The Plugin callbacks have separate owner contracts. These contracts do not
create separate runtime pools. A Plugin root, its private Supervisor, and its wrapper stop
with the Agent Server.

## Stop and hibernate

Use `stop_agent/2` for a clean stop under the default transient restart policy:

```elixir
:ok = MyApp.Jido.stop_agent("agent-42")
```

A normal stop removes the instance runtime checkpoint. It does not delete a
durable persistence record. Delete that record explicitly when the domain
operation is a durable delete.

Normal durable delete writes a tombstone. It preserves the stale-writer fence
and does not physically remove the storage key. Physical purge and retention
are provider maintenance policy. A Redis TTL applies to tombstones and limits
the duration of that fence.

Use hibernate when you want to save the current Agent and stop its actor:

```elixir
:ok = MyApp.Jido.hibernate(server)
```

Use thaw with the same module, ID, and partition for instance-pool Agents.
For a direct OTP child, restart its retained child specification to restore it.
A `:permanent` child restarts after clean stop or hibernation as well; select
that policy only when this is the intended application behavior.

## Deploy more than one node

The core registry and runtime store are local to one Jido instance on one node.
A child Directive can name one known Erlang node with `node:`. The same named
Jido instance on that node owns the child. An explicit remote start never
falls back to a local start. This does not create a cluster registry, leader
election system, automatic placement service, or network partition policy.

A Topology Agent or group can also declare `node:`. Use
`Jido.Topology.Controller.place_agent/4` when a control Agent or Plugin has
selected a new exact node. This operation is a mechanism, not a placement
policy. The new Agent restores through configured shared persistence. Without
shared persistence, it starts from declared initial state. A remote Agent
cannot subscribe to a Controller-owned local Bus.

For multiple writers, use a persistence adapter with shared atomic
compare-and-swap behavior. Define ownership, routing, fencing, and reconciliation
in the application or in an integration package. Do not use the File adapter
for shared writers.

## Make effects safe during shutdown

Shutdown can occur after an Agent commit and before external work completes.
For important work, store pending intent in portable state and use idempotent
operation IDs. On restore, reconcile the durable state with the external
system. See [Recoverable Effects](recoverable-effects.html).
