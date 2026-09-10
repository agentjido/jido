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
Action or Flow success
  -> protect Plugin-owned fields
  -> validate Directives
  -> update Plugin-owned fields in declaration order
  -> validate the complete candidate state
```

`Jido.Agent.Plugin.Pipeline` is private. It has one entry point:

```elixir
run({:ok, candidate_state, directives}, original_state, agent_plugin_specs)
```

An Agent facet has four optional callbacks:

```elixir
state_spec/1
directives/1
validate_directive/2
update_state/3
```

`update_state/3` receives the current owned value, the validated Directives
owned by that facet, and static options. It returns the complete next owned
value.

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

`PLG-REQ-015`: When an Agent facet updates state, the Plugin pipeline shall let
it replace only its owned field.

`PLG-REQ-016`: When an Agent facet returns state, the Plugin pipeline shall
validate it with the facet state schema.

`PLG-REQ-017`: When an Agent facet returns state, the Plugin pipeline shall
apply the portable-value rule.

`PLG-REQ-031`: When more than one Agent facet updates state, the Plugin
pipeline shall call them in declaration order and stop at the first failure.

`PLG-REQ-032`: Where an Agent facet has no `update_state/3` callback, the Plugin
pipeline shall preserve its owned state.

`PLG-REQ-035`: If an Agent state update fails, then Turn evaluation shall
return no candidate Agent.

`PLG-REQ-036`: When a Plugin declares a Directive type, the Plugin boundary
shall assign that type to only one Agent facet.

`PLG-REQ-037`: When Turn evaluation accepts a Plugin Directive, it shall
validate the complete Directive before candidate return.

`PLG-REQ-038`: Where a Plugin Directive has no live handler, the Agent Server
shall treat its successful state update as complete handling.

`PLG-REQ-039`: Where an Agent Server facet handles a Plugin Directive, the
paired Agent facet shall own that Directive type.

### Agent Server

`PLG-REQ-019`: When more than one Agent Server facet participates in admission,
the Agent Server shall call them in declaration order.

`PLG-REQ-020`: If an Agent Server facet rejects admission, then the Agent
Server shall start no executable work.

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

## Retired requirements

Requirements `PLG-REQ-018`, `PLG-REQ-021` through `PLG-REQ-030`,
`PLG-REQ-033`, and `PLG-REQ-034` described Agent Plugin preparation,
domain-state observation, prepared input, or Plugin-added Directives. The
one-phase design removes those capabilities.

Scheduler requirements `PLG-REQ-061` through `PLG-REQ-076` remain owned by the
Scheduler. They do not add work to the Agent Plugin pipeline.

## Non-goals

- No Agent Plugin preparation phase.
- No Plugin input map in Action or Flow context.
- No domain-state observation callback.
- No Plugin-added Directive phase.
- No stage behaviour, middleware protocol, or pipeline DSL.
