# 99_04 Child Topology Runtime

Status: core implementation candidate for
[issue 395](https://github.com/agentjido/jido/issues/395), with stored members
from [issue 394](https://github.com/agentjido/jido/issues/394). These examples
first failed in the first examples commit in this PR and now exercise the runtime and gates.

## Public contract

A combined Topology module generates a child specification for
`Jido.Topology.Runtime`. The Runtime owns its director, Controller, members,
resources, and child branches. Eager mode starts the complete local member
target. Deferred and lazy modes start control processes only. A call starts
its requested dependency closure. Static `include` still makes one Controller
target and does not start a child director or runtime.

## Read the code

Read [Parent](parent.ex) and [Child](child.ex) first. Each has its own director
definition. Child declares Alice, Bob, and a private Bus. [Worker](worker.ex)
has one record command. [Observe](observe.ex) records lifecycle Signals in
director state. Then read [specifications.ex](specifications.ex), which defines
the child data form without new child DSL block syntax.

| Contract | Tests |
| --- | --- |
| Generated child specification; DSL and data parent/child combinations; stored members; eager, deferred, and lazy startup; static include control | [Startup](../../../test/examples/99_research/99_04_child_topology_runtime/startup_test.exs) |
| Concurrent first calls; accepted commands; explicit event exports; Bus isolation; dormant Bus subscribers | [Gate](../../../test/examples/99_research/99_04_child_topology_runtime/gate_test.exs) |
| Aggregate child state; member and runtime restart; restart limit; call deadline; parent shutdown; persistence restore after Jido restart | [Lifecycle](../../../test/examples/99_research/99_04_child_topology_runtime/lifecycle_test.exs) |
| JSON transport; cycles; duplicate gates; invalid command targets; parent scope; a grandchild; depth limit | [Validation and scope](../../../test/examples/99_research/99_04_child_topology_runtime/validation_test.exs) |

## Ownership model

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

## Public data and API

The source contains this data form:

```elixir
%{
  key: :team,
  topology: Child, # Or a neutral Topology definition.
  activation: :lazy,
  gate: %{
    commands: [%{type: "examples.research.child_runtime.record", member: :alice}],
    events: ["examples.research.child_runtime.completed"],
    to: :signals
  },
  max_restarts: 1,
  max_seconds: 5
}
```

A data child also supplies its neutral `director` definition. The parent
passes the entries to `Topology.new/1` in `children`. Constructor validation
must reject cycles, duplicate child keys, and missing command targets. Runtime
validation must reject a target beyond `max_depth` before process startup.

The Runtime functions use the Jido instance and Topology ID:

- `call(jido, id, member, signal, opts)` selects an Agent or `{:child, key}` gate.
- `activate(jido, id, :all)` activates a deferred target.
- `publish(jido, id, bus, signals, opts)` starts the owned Bus if needed and
  delivers to active subscribers. It leaves dormant members dormant.
- `status/2` reports readiness, active and dormant members, and aggregate child state.
- `await_ready/3` waits for the selected activation mode to become ready.
- `whereis_runtime/2`, `whereis_child/3`, `whereis_member/3`, `whereis_bus/3`,
  `director/2`, and `controller/2` expose owned processes.
- `await_gate_idle/4` provides a completion barrier for event forwarding.

The last function is a completion boundary. It lets the tests check
event isolation after forwarding has completed, without a sleep timer.

## Failure and recovery

Lazy readiness permits dormant children and members. A child failure degrades
parent readiness while the parent processes stay running. Child restart limits
apply to that branch. An exhausted limit leaves the gate failed and returns
`{:error, :child_restart_limit}`. Application policy must then replace or
restart that branch; the gate cannot retry without a limit.

An expired activation deadline returns `{:error, :activation_timeout}` and does
not deliver that call's Signal. A command outside the gate returns
`{:error, :command_not_allowed}` before child startup. A clean child stop leaves a failed gate with `{:error, :child_stopped}`.
It cannot start again through a call. Member and child restart retain committed
state. Parent shutdown stops all owned child processes.

Review these API names, status fields, errors, event payloads, Bus policy,
and restart policy in the PR. The [API review note](../API_REVIEW.md) also
states the member selector, JSON versions, and restore rules.

## Run it

Run from the local `jido` V3 repository:

```sh
mix test test/examples/99_research/99_04_child_topology_runtime --include example --seed 0
```

Expected result: all 32 tests pass. They check startup, concurrent commands,
event isolation, branch limits, committed state recovery, and process cleanup.
The tests call core APIs directly, with no application runtime adapter.

Test support: [runtime assertions](../../../test/examples/support/child_topology_runtime_assertions.ex),
[process cleanup](../../../test/examples/support/topology_assertions.ex).

## Limits and promotion

These examples use local processes, trusted compiled code, in-memory JSON,
and ETS persistence. They do not test remote placement, machine loss, idle
eviction, distributed ownership, or an external database. New child DSL block syntax
needs a separate review. Keep these examples in research until the PR contract
is accepted, then promote them to the main topology catalog.

Return to the [research catalog](../README.md).
