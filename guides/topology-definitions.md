# Topology Definitions

A `Jido.Topology` is a declarative description of Agents, groups, Signal Buses,
and logical ownership. You first declare the system and then instantiate it
with input. Declaration, validation, and planning start no processes.

## Main Values

| Value | Purpose |
| --- | --- |
| Topology definition | Static components, references, and startup policy |
| Topology instance | Definition plus validated input and instance ID |
| Topology plan | Expanded local members and dependency layers |
| Controller | Live local activation and repair process |

Topology input is not Agent state. It supplies values used to build initial
component configuration.

## Declare Components

Use singleton Agents for fixed roles. Use counted groups for repeated identical
roles. Use keyed groups when input records provide stable member IDs.

A Bus resource is one owned Jido Signal Bus. A subscription connects an Agent
or group to one Bus path. An ownership relationship gives one Agent logical
parent responsibility for another Agent or group.

## Plan Before Activation

Instantiation validates input, expands groups, resolves references, assigns
stable local IDs, checks startup bounds, and builds dependency layers. It does
not check external service readiness.

Use a finite `max_agents` and startup concurrency. The controller starts only
the expanded local plan.

## Separate Static And Dynamic Systems

Use a Topology for an application system whose desired members are known from
one static definition and instance input. Use child Directives when a live
Agent decides to create or stop workers from changing domain state.

The controller repairs one existing target. It does not apply a new topology
definition to a running system.

## Know Current Scope

The v3 spike supports local activation, readiness, normal Bus input, logical
ownership, and automatic or manual repair. It does not provide cluster
placement, live graph changes, database-driven membership, or distributed work
ownership.

Continue with [Topology DSL](topology-dsl.livemd) and
[Activate And Repair A Topology](activate-and-repair-a-topology.livemd).
