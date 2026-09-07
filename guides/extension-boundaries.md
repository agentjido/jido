# Extension Boundaries

Jido core defines the Agent value, actor runtime, Plugin boundary, composition
model, and persistence contract. Extensions connect these contracts to a
specific application or service.

## Public extension points

Use these public boundaries:

- `Jido.Action` and `Jido.Exec` for executable work
- `Jido.Plugin` for reusable Agent state, Directives, and runtime children
- `Jido.Persistence.Adapter` for checkpoint storage
- `Jido.Observe.Tracer` for trace export
- Jido Signal dispatch adapters and buses for message transport
- `Jido.Agent.Extension` and `Jido.Topology.Extension` for static DSL lowering
- Agent and Topology builders and codecs for trusted authoring systems
- `spawn_fun` for an application-owned remote child start

An extension must validate its options and return documented error shapes. It
must not depend on private `AgentServer` state or ETS table layouts.

## Package boundaries

Jido uses [Jido Action](https://hexdocs.pm/jido_action/) for Action, Flow,
Instruction, and execution contracts. Put reusable executable work in that
package or in an application Action module.

Jido uses [Jido Signal](https://hexdocs.pm/jido_signal/) for Signal values,
routing, buses, and dispatch. A transport integration belongs at that boundary.

Jido core coordinates these packages around an Agent Turn. It does not duplicate
their schema, execution, or transport systems.

## Application-owned systems

The core does not supply these policies:

- a distributed Agent registry
- cluster membership or leader election
- a database transaction that includes an external service
- a general durable message broker
- model provider clients, prompt policy, or tool catalogs
- business-specific authorization and tenancy
- unlimited conversation or audit storage

Build these in the host application or in a focused integration package. Keep a
small stable reference in Agent state when Jido must coordinate with the system.

## Keep runtime resources out of checkpoints

A Plugin runtime can own a process, connection, watcher, or worker pool. Its
portable Plugin state should contain only the configuration and facts necessary
to rebuild that resource. A persistence adapter stores Agent checkpoints, not
runtime processes.

## Prefer explicit protocols

Use Signals for messages, Directives for runtime-owned effects, Plugin callbacks
for Plugin-owned behavior, and adapters for external boundaries. Do not mutate
an Agent behind the Turn boundary or send private messages to an actor process.

When an extension needs a new core capability, first define the ownership,
failure, timeout, retry, and restore rules. A public function without those
rules is not a complete extension contract.
