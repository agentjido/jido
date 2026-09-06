# Composed topology

One root topology includes two copies of `WorkerTeam`. Each team has a private
coordinator and worker group. The root owns one Bus. Both teams import that
Bus and export their leader, workers, and Bus access.

The default system has eight Agents: one director, two leaders, and five
workers. East has two workers; west has three. Each worker has its team's
label. A Bus Signal reaches all five workers. A direct call to the east leader
does not change the west leader's state.

| Form | Source |
| --- | --- |
| Reusable team DSL | [worker_team.ex](worker_team.ex) |
| Root DSL | [composed_system.ex](composed_system.ex) |
| Builder and trusted Registry | [formats.ex](formats.ex) |
| Embedded JSON composition | [composed_system.json](composed_system.json) |

## Run

Start IEx with `iex -S mix`, then run:

```elixir
alias Jido.Examples.Topology.{Cell, ComposedFormats, ComposedSystem}
alias Jido.Topology.{Builder, Codec, Controller, Ref}

{:ok, _} = Jido.start(name: MyApp.Jido)

# All three forms produce the same definition.
definition = ComposedSystem.topology()
{:ok, ^definition} = Builder.build(ComposedFormats.builder())
{:ok, ^definition} = ComposedFormats.from_file()

{:ok, json} = ComposedFormats.json()
{:ok, instance} = Codec.decode(JSON.decode!(json), ComposedFormats.registry(),
  id: "research", input: %{east_workers: 2, west_workers: 3})

{:ok, controller} = Controller.start_link(jido: MyApp.Jido, topology: instance)
:ok = Controller.await_ready(controller)
Controller.status(controller)

bus = Controller.whereis_bus(controller, :events)
# These resolve to the same owned Bus.
^bus = Controller.whereis_bus(controller, Ref.ref(:east, :events))
^bus = Controller.whereis_bus(controller, Ref.ref(:west, :events))

{:ok, [_]} = Jido.Signal.Bus.publish(bus, [Cell.work_signal!(4)])
east_worker = Controller.whereis_agent(controller, Ref.ref(:east, :workers), 1)
Jido.AgentServer.agent(east_worker).state

east_leader = Controller.whereis_agent(controller, Ref.ref(:east, :leader))
{:ok, _} = Cell.work(east_leader, 9)

Supervisor.stop(controller)
```

The same `{Controller, jido: MyApp.Jido, topology: instance}` tuple can go in
the application supervision tree after the Jido instance. Use the application's
`:rest_for_one` strategy as shown in the [topology guide](../README.md).

## Composition contract

`include` accepts a topology module or a neutral definition. Construction
resolves the source to an embedded definition. Each child has its own input
schema. `inputs` maps parent input to child input; unspecified child fields
use that child's schema defaults. Child input never inherits parent fields
without an explicit mapping.

`imports` declares required Buses. Every inclusion must bind exactly those
requirements. A binding may target a parent Bus or a sibling's exported Bus.
A root definition with unbound imports cannot start. Binding a Bus gives access
to its owner; it does not create another Bus or another resource supervisor.

`exports` supports Agents, groups, and Buses. `ref(:east, :leader)` resolves an
export, so callers do not depend on the private name `:coordinator`. Nested
components must re-export their public endpoints. A reference cannot reach
through an unexported child boundary.

The root explicitly owns both exported leaders. Each leader owns its own
workers. Inclusion alone creates no Agent parent/child relationship.

## Identity, limits, and lifecycle

Plan nodes retain their component path. The east leader has a key such as
`component/east/agent/coordinator`. Its workers have keys such as
`component/east/group/workers/1`. Instance IDs and path components escape
separators. A component alias is part of Agent identity; renaming it changes
that identity and requires a migration decision for saved state.

One controller runs the complete plan. The root startup concurrency and task
timeout apply across all components. Included startup execution settings are
standalone defaults; they do not create separate controller policies. Each
component's `max_agents` limit still applies to its full subtree, in addition
to the root limit. The default timeout is 10000 ms per startup/check task.

Startup tasks run asynchronously. A blocked member can time out while
independent members start and the controller continues to answer status calls.
The controller retries unavailable members. A timeout does not undo external
work that already completed during initialization.

Stopping one team's leader triggers that team's child policy. The root Bus
and other team remain available. The controller then repairs the missing
members. Stopping the root controller stops all its owned Agents and Buses.
Independent component stop, live replacement, and per-component pause remain
outside this version.

Codec version 2 preserves the composition tree, mapped inputs, bindings, and
exports. It embeds definitions and uses the trusted Registry for code and
schemas. Version 1 topology documents remain readable. Input values supplied
to `new/1`, runtime PIDs, plans, and committed state remain outside the document.

## Tests

```sh
mix test test/jido/topology test/examples/07_topology --include example
```

The example test loads JSON, checks all ownership bindings, checks delivery to
every worker, and checks shutdown. Core tests also cover nested re-exports,
invalid imports, endpoint kinds, cycles across components, input validation,
identity separation, global limits, blocked readiness, failure recovery, and
persistence restoration.
