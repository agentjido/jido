# 99_04 Child Topology Runtime

Status: enabled failing contract examples for
[issue 395](https://github.com/agentjido/jido/issues/395), with stored members
from [issue 394](https://github.com/agentjido/jido/issues/394).
The child runtime and gate data forms are proposals for review.

## Current public contract

The combined Topology DSL returns an owner Agent and a Topology definition.
Applications currently start the AgentServer and Controller separately. The
Controller starts its target eagerly. Static `include` puts child members and
resources in that same Controller target. It does not start a child director,
Controller, or runtime supervisor.

Jido does not yet have `Jido.Topology.Runtime`, generated Topology child
specifications, or a `children` Topology field. The included-child control and
standalone stored member control pass. The new runtime cases fail at the
missing boundaries.

## Read the code

Read [Parent](parent.ex) and [Child](child.ex) first. Each has its own director
definition. Child declares Alice, Bob, and a private Bus. [Worker](worker.ex)
has one record command. [Observe](observe.ex) records lifecycle Signals in
director state. Then read [specifications.ex](specifications.ex), which defines
the proposed child data form without adding DSL syntax.

| Contract | Tests |
| --- | --- |
| Generated child specification; DSL and data parent/child combinations; stored members; eager, deferred, and lazy startup; static include control | [Startup](../../../test/examples/99_research/99_04_child_topology_runtime/startup_test.exs) |
| Concurrent first calls; accepted commands; explicit event exports; Bus isolation; dormant Bus subscribers | [Gate](../../../test/examples/99_research/99_04_child_topology_runtime/gate_test.exs) |
| Aggregate child state; member and runtime restart; restart limit; call deadline; parent shutdown; persistence restore after Jido restart | [Lifecycle](../../../test/examples/99_research/99_04_child_topology_runtime/lifecycle_test.exs) |
| JSON transport; cycles; duplicate gates; invalid command targets; parent scope; a grandchild; depth limit | [Validation and scope](../../../test/examples/99_research/99_04_child_topology_runtime/validation_test.exs) |

## Proposed ownership model

```text
Parent Runtime supervisor
  Parent director AgentServer
  Parent Controller and owned resources
  Child gate :team
    Child Runtime supervisor, started on the first accepted call
      Child director AgentServer
      Child Controller and owned resources
      Active child members; other members remain dormant
```

The gate is the only parent command path into the child. It has one stable
identity, accepted Signal types with member targets, and exported event types.
Concurrent first calls start one child runtime and one requested member. Signal
delivery waits for that member and its required resources to become ready.

The child identity is `parent-id/child/team`. A grandchild adds another child
scope. Each child has separate director, Controller, and Bus processes.
Static `include` continues to mean one composed Controller target.

The parent director receives `jido.topology.lifecycle.child.status_changed`
with `{child, id, status}` data. It does not receive the child's private
lifecycle stream. An event export is an explicit bridge into the parent Bus.
An empty export list leaves the Buses isolated.

## Proposed public data and API

The source contains this data form:

```elixir
%{
  key: :team,
  topology: Child, # Or a neutral Topology definition.
  activation: :lazy,
  gate: %{
    commands: [%{type: "examples.research.child_runtime.record", member: :alice}],
    events: ["examples.research.child_runtime.completed"]
  },
  max_restarts: 1,
  max_seconds: 5
}
```

A data child also supplies its neutral `director` definition. The parent
passes the entries to `Topology.new/1` in `children`. Constructor validation
must reject cycles, duplicate child keys, and missing command targets. Runtime
validation must reject a target beyond `max_depth` before process startup.

The proposed Runtime functions use the Jido instance and Topology ID:

- `call(jido, id, member, signal, opts)` selects an Agent or `{:child, key}` gate.
- `activate(jido, id, :all)` activates a deferred target.
- `publish(jido, id, bus, signals, opts)` starts the owned Bus if needed and
  delivers to active subscribers. It leaves dormant members dormant.
- `status/2` reports readiness, active and dormant members, and aggregate child state.
- `await_ready/3` waits for the selected activation mode to become ready.
- `whereis_runtime/2`, `whereis_child/3`, `whereis_member/3`, `whereis_bus/3`,
  `director/2`, and `controller/2` expose owned processes.
- `await_gate_idle/4` provides a completion barrier for event forwarding.

The last function is a proposed observation boundary. It lets the tests check
event isolation after forwarding has completed, without a sleep timer.

## Failure and recovery choices for review

Lazy readiness permits dormant children and members. A child failure degrades
parent readiness while the parent processes stay running. Child restart limits
apply to that branch. An exhausted limit leaves the gate failed and returns
`{:error, :child_restart_limit}`. Application policy must then replace or
restart that branch; the gate cannot retry without a limit.

An expired activation deadline returns `{:error, :activation_timeout}` and does
not deliver that call's Signal. A command outside the gate returns
`{:error, :command_not_allowed}` before child startup. Member and child restart
retain committed state. Parent shutdown stops all owned child processes.

These exact API names, status fields, errors, event payloads, Bus policy, and
restart policy are review choices. The tests describe them; they are not yet
implemented or approved. The related
[API review note](../API_REVIEW.md) also covers the member definition field.

## Run it

Run from the local `jido` V3 repository:

```sh
mix test test/examples/99_research/99_04_child_topology_runtime --include example --seed 0
```

Expected result: static include and standalone stored member controls pass.
Runtime tests fail because
`children`, the generated child specification, or `Jido.Topology.Runtime` is
missing. Stored member cases first fail with `Expected an Agent module`.
The command exits with status 2. Tests stay enabled. Later runtime assertions
have not yet run, so they do not prove the proposed recovery or isolation.

Test calls use `apply/3` only to compile before Runtime exists. They call the
proposed API directly. There is no mock runtime or application adapter.
Test support: [runtime assertions](../../../test/examples/support/child_topology_runtime_assertions.ex),
[process cleanup](../../../test/examples/support/topology_assertions.ex).

## Limits and promotion

These examples use local processes, trusted compiled code, in-memory JSON,
and ETS persistence. They do not test remote placement, machine loss, idle
eviction, distributed ownership, or an external database. New child DSL syntax
is deferred until user review. Promote the examples after the public contract
is approved, implemented, and all required tests pass.

Return to the [research catalog](../README.md).
