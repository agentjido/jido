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

Plugin runtime processes restart from Plugin specifications. Signal bus
subscribers and application connections must also have a restart or
reconciliation rule. Do not put a PID or connection in durable Agent state.

Plugin wrappers are peers of Agent Servers in the same Dynamic Supervisor.
The four Plugin facet modules separate owner contracts. They do not create
four runtime pools. A Plugin root, its private Supervisor, and its wrapper stop
with the Agent Server.

## Stop and hibernate

Use `stop_agent/2` for a normal permanent stop:

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

Use thaw with the same module, ID, and partition to restore it later.

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
