# Topology Definitions

A `Jido.Topology` is a declarative description of Agents, groups, resources,
and logical ownership. You first declare the system and then instantiate it
with input. Declaration, validation, and planning start no processes.

## Main Values

| Value | Purpose |
| --- | --- |
| Topology definition | Static components, references, and startup policy |
| Topology instance | Definition plus validated input and instance ID |
| Topology plan | Expanded members, exact nodes, and dependency layers |
| Controller | Live activation, placement, and repair process |

Topology input is not Agent state. It supplies values used to build initial
component configuration.

## Use One DSL Shape

A Topology module has three root blocks:

- `agent do` defines an optional control Agent.
- `routes do` defines normal control-Agent routes and requires `agent do`.
- `topology do` contains all topology-specific sections.

The `agent` and `topology` blocks are independent. Creating a topology instance
does not start the control Agent. Starting the control Agent does not activate
the topology.

## Declare Components

Use singleton Agents for fixed roles. Use counted groups for repeated identical
roles. Use keyed groups when input records provide stable member IDs.

The `resources` section is not Bus-specific. A Bus is the first and only current
core resource type. A Bus resource is one owned Jido Signal Bus. A subscription
connects an Agent or group to one Bus path. An ownership relationship gives one
Agent logical parent responsibility for another Agent or group.

Resource kinds use one small internal boundary for validation, lookup, startup,
and ownership checks. The DSL and Codec still accept only the closed, trusted
core set. Thus, a decoded document cannot select an arbitrary runtime module.

A durable work queue is a useful future resource. It has stable identity,
supervised lifecycle, readiness, and Agent consumers. Its confirmation, retry,
and storage rules are not core Topology rules. It should be in an optional
Topology package after that package has a clear resource and Codec registration
contract.

## Plan Before Activation

Instantiation validates input, expands groups, resolves references, assigns
stable IDs, resolves exact nodes, checks startup bounds, and builds dependency layers. It does
not check external service readiness.

Use a finite `max_agents` and startup concurrency. The controller starts only
the expanded plan.

## Add Static Plugin Entries

An Agent can declare a Plugin package with a `Jido.Topology.Plugin` facet. When
Jido builds an instance plan, that facet can contribute Bus resources,
ownership relationships, and Bus subscriptions for the Agent declaration.

Jido applies Agent contributions first and then group contributions. It keeps
source declaration order and Plugin declaration order. Included Topologies
receive contributions in their own scope. A group gets one contribution for
the declaration, and all its members use the resulting group wiring.

The validated source definition stays unchanged. Jido validates the complete
expanded graph before activation. A duplicate key, unknown endpoint, duplicate
subscription, or graph cycle returns an error before the Controller starts.

This facet is for pure static planning. It cannot add Agents or new resource
types. It does not start a Jido process, persist state, replace the Controller
target, or grant live authority. See the
[`07_06_plugin_contribution`](../examples/07_topology/07_06_plugin_contribution/README.md)
example.

## Separate Static And Dynamic Systems

Use a Topology for an application system whose desired members are known from
one static definition and instance input. Use child Directives when a live
Agent decides to create or stop workers from changing domain state.

The controller repairs one existing target. An additive update can add Agents.
It cannot remove Agents or change resources.

## Use Signals For Lifecycle And Policy

Pass a control Agent PID or `Jido.Agent.Ref` as the Controller `:lifecycle`
option. The Controller sends best-effort `jido.topology.lifecycle.**` Signals
for operations, component results, and status changes. These Signals use normal
Agent routes. Each event is a custom `Jido.Signal` module under
`Jido.Topology.Signal`. An observation failure cannot change a Controller
result.

An Agent or group declaration can name an exact Erlang node with `node:`.
`Controller.place_agent/4` can move one planned Agent to another exact node.
Core does not discover nodes, select placement, or rebalance a system. Put
those decisions in a control Agent or Plugin. A target node must run compatible
code and the same named Jido instance. Core does not fall back to a local node.
The new Agent restores through configured shared persistence. Without shared
persistence, it starts from its declared initial state.

## Add Refined Authoring Syntax

Pass Spark extensions with
`use Jido.Topology, extensions: [MyApp.TopologyExtension]`. A Topology extension
implements `Jido.Topology.Extension` and lowers its static declarations into
normal Agents, groups, Buses, relationships, connections, composition data, and
startup policy.

All foreign entities must be consumed. The lowered result passes normal
Topology validation and uses the normal controller. Use an extension to add a
focused application DSL. Do not use it to add another runtime or to put changing
application data in the static topology.

See [Authoring Extensions](authoring-extensions.md) for the lowering contract.

## Know Current Scope

V3 supports readiness, normal Bus input, logical ownership, automatic or manual
repair, additive Agent updates, lifecycle Signals, and exact known-node
placement. It does not provide membership discovery, placement selection,
automatic rebalance, live removal, distributed authority, or work ownership.

`Controller.status/2` and `await_ready/2` report current local readiness. A
public query checks cached PIDs, each required Bus input subscription runtime,
and each live parent binding with a short timeout. If a Bus client disconnects
or a parent binding is lost while the Agent and Bus PIDs remain alive, status
becomes `:degraded` with an input error. After reconnection or binding repair,
a later query can report `:ready` again. Readiness does not confirm that a
Signal has committed a target Agent Turn.

Continue with [Topology DSL](topology-dsl.livemd) and
[Activate And Repair A Topology](activate-and-repair-a-topology.livemd).
