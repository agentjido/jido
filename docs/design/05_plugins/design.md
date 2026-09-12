# Plugin design

This document defines the recommended Plugin contract. Its review status is in
the main [design index](../README.md).

## Scope

The Plugin seam owns package declarations, owner facets, Plugin-owned Agent
state, Plugin Directive ownership, and Plugin callback order.

Actions and Flows own domain-state changes and the complete Directive list.
Agent Server owns live work and commit. Persistence owns records and adapters.
Topology owns planning and activation.

## Model

```text
Plugin package
  -> Agent facet
  -> Agent Server facet
  -> optional Persistence facet
  -> optional Topology facet
```

A stateful Agent facet owns one top-level field in the complete Agent state
map. There is no second Plugin state map.

The Agent Plugin sequence is:

```text
prepare one package input or reject
  -> select and run Action or Flow
Action or Flow success
  -> protect Plugin-owned fields
  -> validate each Directive once
  -> reduce Plugin-owned fields in declaration order
  -> validate the complete candidate state
```

`Jido.Agent.Plugin.Pipeline` is private. It has one entry point:

```elixir
run({:ok, candidate_state, directives}, agent, signal, plugin_inputs, agent_plugin_specs)
```

An Agent facet has four optional callbacks:

```elixir
prepare/2
state_spec/1
directives/1
reduce/2
```

`reduce/2` receives a read-only reduction value and static options. The value
contains the complete state before the Turn, the current complete candidate
state, the current owned value, the pure prepared input, and all validated
Directives. The callback returns only the complete next owned value.

`prepare/2` receives a read-only preparation value and static options. It can
reject or return one portable value. Jido stores that value under the package
module in the `prepared` slot of `context.plugin_inputs`. The preparation value
includes the complete current Agent state. The callback cannot change the
incoming Signal or state.

Each custom Directive owns `validate/1`. The pipeline validates every
Directive once after Action or Flow success. The Agent facet declares
Directive ownership but does not validate a Directive again.

Plugin callbacks use explicit input and result values. Their contract does not
include the caller PID, process dictionary, link set, monitor set, or Task
identity. A direct Agent call can run pure callbacks in its caller process. A
live Agent Server can run callbacks inside owned Tasks. The execution location
must not change callback order, input, result, or authority.

## Requirements

### Declaration

`PLG-REQ-001`: When an Agent declares Plugins, the Plugin boundary shall accept
an ordered list of package modules or `{module, keyword_options}` pairs.

`PLG-REQ-003`: If an Agent declares the same Plugin package more than once,
then the Plugin boundary shall reject the definition.

`PLG-REQ-005`: When a package manifest selects facets, the Plugin boundary
shall accept no more than one facet for each owner.

`PLG-REQ-007`: When an authoring API produces Plugin declarations, the Agent
boundary shall preserve declaration order.

`PLG-REQ-009`: When Agent Codec encodes a Plugin declaration, the Agent
boundary shall encode only the package module and validated static options.

### Agent state and Directives

`PLG-REQ-011`: Where an Agent facet owns state, the facet shall declare one
atom key and one static Zoi schema.

`PLG-REQ-012`: If a Plugin-owned key duplicates a domain key or another
Plugin-owned key, then Agent construction shall reject the definition.

`PLG-REQ-013`: When Agent construction builds the complete state schema, it
shall add each Plugin-owned field at the top level.

`PLG-REQ-014`: If an Action or Flow changes a Plugin-owned field, then Turn
evaluation shall reject the candidate.

`PLG-REQ-015`: When an Agent facet reduces state, the Plugin pipeline shall let
it replace only its owned field.

`PLG-REQ-016`: When an Agent facet returns state, the Plugin pipeline shall
validate it with the facet state schema.

`PLG-REQ-017`: When an Agent facet returns state, the Plugin pipeline shall
apply the portable-value rule.

`PLG-REQ-018`: Before route selection, the Agent Plugin boundary shall call
each `prepare/2` callback in declaration order.

`PLG-REQ-021`: Agent Plugin preparation shall receive the unchanged source
Signal, Agent identity, Agent module, the complete current Agent state, its
owned state, and static options.

`PLG-REQ-022`: Agent Plugin preparation shall return one package-owned input or
reject evaluation.

`PLG-REQ-023`: The Agent Plugin boundary shall require pure prepared input to
be portable.

`PLG-REQ-024`: Agent Plugin preparation shall not change the Agent, source
Signal, caller context, route, or another package's input.

`PLG-REQ-025`: The execution context shall store prepared inputs by Plugin
package module under the `plugin_inputs[Package].prepared` slot.

`PLG-REQ-031`: When more than one Agent facet reduces state, the Plugin
pipeline shall call them in declaration order and stop at the first failure.

`PLG-REQ-032`: Where an Agent facet has no `reduce/2` callback, the Plugin
pipeline shall preserve its owned state.

`PLG-REQ-035`: If an Agent state reduction fails, then Turn evaluation shall
return no candidate Agent.

`PLG-REQ-036`: When a Plugin declares a Directive type, the Plugin boundary
shall assign that type to only one Agent facet.

`PLG-REQ-037`: When Turn evaluation accepts a Plugin Directive, it shall call
the Directive module's `validate/1` once before candidate return.

`PLG-REQ-038`: Where a Plugin Directive has no live handler, the Agent Server
shall treat its successful state reduction as complete handling.

`PLG-REQ-039`: Where an Agent Server facet handles a Plugin Directive, the
paired Agent facet shall own that Directive type.

### Agent Server

`PLG-REQ-019`: When more than one Agent Server facet participates in admission,
the Agent Server shall call them in declaration order.

`PLG-REQ-020`: If an Agent Server facet rejects admission, then the Agent
Server shall start no executable work.

`PLG-REQ-026`: An Agent Server facet shall return only its own package runtime
input or reject admission.

`PLG-REQ-027`: Agent Server admission shall receive a read-only Admission value
and shall have no return path that changes the Agent, incoming Signal, caller
context, prepared input, or another package's input.

`PLG-REQ-028`: The execution context shall store a successful live input under
`plugin_inputs[Package].runtime`. It may contain a transient runtime term
because the input does not enter Agent state or checkpoints.

`PLG-REQ-029`: Direct `Jido.Agent.cmd/3` shall run pure Agent Plugin preparation
but shall not run Agent Server admission.

`PLG-REQ-040`: When a live commit succeeds, the Agent Server shall start Plugin
Directive handling after the committed state is authoritative.

`PLG-REQ-042`: If post-commit Plugin Directive handling fails, then the Agent
Server shall preserve the committed state and version.

`PLG-REQ-043`: Where an Agent Server facet declares a runtime, the Agent Server
shall accept only one valid permanent OTP child specification.

`PLG-REQ-044`: Where a Plugin declares no runtime, the Agent Server shall not
start a Plugin process.

`PLG-REQ-046`: When an Agent Server starts a Plugin runtime, it shall wait for
the readiness result before it reports ready.

`PLG-REQ-049`: While a Plugin runtime runs, the Agent Server shall keep process
data outside Agent state and checkpoints.

`PLG-REQ-050`: When a Plugin runtime requests an Agent state change, it shall
send a Signal through the Agent mailbox boundary.

`PLG-REQ-051`: When outbound Signal preparation runs, the Agent Server shall
call selected facets in reverse declaration order.

### Persistence and Topology

`PLG-REQ-053`: Where a Plugin declares a Persistence facet, the Plugin boundary
shall require a stateful Agent facet in the same package.

`PLG-REQ-054`: When a Persistence facet dumps or loads state, it shall receive
only its paired owned value, bounded context, and static options.

`PLG-REQ-055`: When a Persistence facet dumps state, the Persistence boundary
shall require a portable result.

`PLG-REQ-056`: When a Persistence facet loads state, the Persistence boundary
shall validate the portable result with the Agent facet schema.

`PLG-REQ-059`: When a Topology facet contributes static data, the Topology
boundary shall accept only canonical supported entries.

`PLG-REQ-060`: When a Topology facet contributes static data, the Topology
boundary shall keep process and persistence authority out of the callback.

### Callback execution boundary

`PLG-REQ-077`: When Jido invokes a Plugin callback, the callback contract shall
not derive Agent identity, Agent Server identity, or runtime authority from the
calling PID or process dictionary.

`PLG-REQ-078`: Whether a Plugin callback runs in a direct caller process or an
Agent Server-owned Task, Jido shall preserve its documented input, result,
ordering, and failure contract.

`PLG-REQ-079`: When an Agent Server waits for a Plugin callback result, the
Plugin callback shall not make a synchronous call to that same Agent Server
activation.

`PLG-REQ-080`: When a Plugin callback runs in an Agent Server-owned Task, the
Task shall return a value or fault result and shall not directly change the
live Agent, state version, relationship projection, lifecycle state, or
Directive position.

## Retired requirements

Requirements `PLG-REQ-030`, `PLG-REQ-033`, and `PLG-REQ-034` described broader
domain-state observation or Plugin-added Directive phases. Those capabilities
remain retired.

Scheduler requirements `PLG-REQ-061` through `PLG-REQ-076` remain owned by the
Scheduler. They do not add work to the Agent Plugin pipeline.

## Non-goals

- No Plugin replacement of an incoming Signal or caller context.
- No Plugin write to another package's input.
- No domain-state observation callback.
- No Plugin-added Directive phase.
- No stage behaviour, middleware protocol, or pipeline DSL.
