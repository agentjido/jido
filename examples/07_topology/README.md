# Topology spike

These examples define complete local Agent systems in three equal forms:
Spark DSL, Builder, and JSON through a Codec. All forms use `Jido.Topology.new/1`.
Construction and group expansion start no processes.

| Example | Definition | Behavior |
| --- | --- | --- |
| `07_01_independent` | [DSL](07_01_independent/independent.ex) | Two independent Agents |
| `07_02_hierarchy` | [DSL](07_02_hierarchy/hierarchy.ex) | A coordinator, a leader, and three owned workers |
| `07_03_bus_swarm` | [DSL](07_03_bus_swarm/swarm.ex), [Builder and Codec](07_03_bus_swarm/formats.ex), [JSON](07_03_bus_swarm/swarm.json) | A coordinator and 1000 workers receive work through a Bus |
| `07_04_keyed_accounts` | [DSL](07_04_keyed_accounts/accounts.ex) | Agent identities come from account keys |
| `07_05_composed_system` | [Guide and all forms](07_05_composed_system/README.md) | Two teams share one Bus through imports, bindings, and public exports |

## Start at application boot

```elixir
defmodule MyApp.Jido do
  use Jido, otp_app: :my_app
end

# In Application.start/2:
alias Jido.Examples.Topology.Swarm

children = [
  {MyApp.Jido, max_tasks: 4_096},
  {Jido.Topology.Controller,
   jido: MyApp.Jido,
   topology: Swarm.new!(id: "research", input: %{worker_count: 1_000})}
]

Supervisor.start_link(children, strategy: :rest_for_one, name: MyApp.Supervisor)
```

The application starts the controller. The controller starts Buses and Agents
in dependency layers, with at most 32 startup tasks at once by default. A Jido
restart also restarts the controller when the application uses `:rest_for_one`.
Agents remain peers under the Jido Agent pool. Ownership uses the existing
logical child API.

For an IEx session:

```elixir
alias Jido.Examples.Topology.{Cell, Swarm}
alias Jido.Topology.Controller

{:ok, _} = Jido.start(name: MyApp.Jido, max_tasks: 4_096)
instance = Swarm.new!(id: "research", input: %{worker_count: 1_000})
{:ok, controller} = Controller.start_link(jido: MyApp.Jido, topology: instance)
:ok = Controller.await_ready(controller, 60_000)
Controller.status(controller)

bus = Controller.whereis_bus(controller, :work)
{:ok, [_record]} = Jido.Signal.Bus.publish(bus, [Cell.work_signal!(3)])
worker = Controller.whereis_agent(controller, :workers, 1)
Jido.AgentServer.agent(worker).state

Supervisor.stop(controller)
```

The 1000-worker broadcast test sets `max_tasks: 4096`. The default Jido task
limit is 1000. Startup concurrency and simultaneous Agent execution are
separate limits. A normal Bus broadcast does not retry a failed Agent turn.
Each subscriber receives each matching Signal; this is not a work queue.

## The three authoring forms

```elixir
alias Jido.Examples.Topology.{Formats, Swarm}
alias Jido.Topology.{Builder, Codec}

# Compile-time Spark DSL.
definition = Swarm.topology()

# Runtime Builder.
{:ok, ^definition} = Builder.build(Formats.builder())

# JSON with stable application Registry IDs.
{:ok, json} = Formats.json()
{:ok, ^definition} = Codec.decode(JSON.decode!(json), Formats.registry())
{:ok, ^definition} = Formats.from_file()

# Instance input is separate from the definition.
{:ok, instance} = Codec.decode(JSON.decode!(json), Formats.registry(),
  id: "research", input: %{worker_count: 1_000})
```

The Codec reuses `Jido.Agent.Codec.Registry`. Agent modules, schemas, atoms,
and static struct values require trusted entries. JSON cannot create atoms,
load a module from a string, or supply executable functions. Input and member
references have explicit tagged JSON records. `Codec.encode/1` can derive a
temporary Registry; stored documents should use stable application IDs.

The JSON document contains the definition only. It excludes instance input,
expanded plans, PIDs, runtime status, and committed Agent state. The same
document can be instantiated more than once with different IDs and input.
Codec version 2 embeds composed definitions. Version 1 documents remain readable.

## DSL blocks

- `topology`: Zoi input schema and metadata.
- `agents`: singleton `agent` declarations and repeated `group` declarations.
- `resources`: named `bus` declarations with optional `config`.
- `relationships`: `owns parent, child` with `on_parent_exit` policy.
- `connections`: `subscribe agent_or_group, to: bus, path: pattern`.
- `topologies`: `include` declarations with mapped `inputs` and explicit `bind` declarations.
- `imports`: required Buses supplied by the containing topology.
- `exports`: public Agents, groups, and Buses, accessed through `ref(component, export)`.
- `startup`: `concurrency`, `ready :all`, `max_agents`, `retry_interval`, and `task_timeout`.

The default startup settings are 32 concurrent tasks, all members required,
10000 Agents maximum, a 1000 ms repair interval, and a 10000 ms task timeout. Groups accept either
`count` or `members` plus `key_by`. `input(:field)` reads topology input.
`member(:field)` reads one keyed member in an `initial_state` expression.
A counted group exposes `member(:index)` as an integer.

Keys normalize to strings. Singleton IDs have the form
`instance/agent/key`; group member IDs use `instance/group/key/member`.
Instance IDs and key components escape separators. Counted groups use decimal member keys
starting at `1`. Keyed groups sort by key and reject duplicates, so input
order cannot change identity. Zero-member groups are valid. The planner
checks the Agent count limit before allocating a counted group.

A subscription adds a startup dependency on its Bus. Ownership adds a
dependency on the parent. `depends_on` adds further readiness dependencies.
Cycles, unknown keys, duplicate declarations, and multiple owners fail
validation. A group cannot act as a singleton parent.

## Lifecycle and scope

The controller repairs missing Agents and ownership bindings. Topology Agents
are temporary children in the Jido Agent pool. The controller owns reactivation
after both normal and abnormal exits. Each repair pass checks the
current processes and required Bus subscriptions. `status/1` reports the
latest pass and detects dead recorded processes. Startup and check tasks run asynchronously with a time limit. Status calls
remain available while a member starts. Independent branches do not wait for
a blocked branch.

A normal controller shutdown stops its owned Agents in reverse dependency
order. It also stops its Buses and tasks. A controller worker crash can find
its existing Agents through stable IDs and an ownership marker in metadata.
A conflicting Agent or Bus is reported; the controller does not take it over.
Partial startup reports `:degraded` and retries. It leaves successful members
running. `await_ready/2` waits for all members and uses the caller's timeout.

All declarations remain desired and active. A normal Agent stop or parent
failure can stop children, but the controller will recreate missing members.
To leave a member stopped, stop the controller. Live topology changes and
per-member pause are outside this spike. Included topologies share one root
controller and its execution limits.

Agent restoration uses the existing Jido persistence adapter. The controller
loads saved state and its revision, validates identity, and reapplies the
topology metadata and Bus inputs before starting the Server. This is necessary
because module restoration rebuilds the Agent from its module definition.
Initial state applies to new Agents; a saved Agent retains its committed state. The restore
test uses ETS and proves controller restart, not disk or VM durability. Keep
the definition unchanged when restoring this spike. Definition revisions and
migration are separate work.

Database records can supply the keyed account input. This spike has no
database adapter, cluster placement, generated route
interfaces, on-demand activation, or durable queue protocol. It provides the
shared authoring and local runtime contracts needed to test those extensions.

## Verification

```sh
mix test test/jido/topology test/examples/07_topology --include example
mix quality
```

The scale test boots 1000 workers plus one coordinator, publishes one Signal,
checks every worker's committed result, and checks shutdown cleanup. The
other tests cover authoring parity, document validation, stable identities,
startup cycles, ownership, multiple subscriptions, failure recovery, identity
conflicts, and restoration.
