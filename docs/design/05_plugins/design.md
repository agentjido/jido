# Plugin design

> Pending approval. Selected review decisions are recorded below.

This document defines the recommended Plugin contract. Its review status is in
the main [design index](../README.md).

## Current review decisions

On 2026-10-01, the user selected one Plugin module with optional callbacks
([GAP-018](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/GAP_ANALYSIS.md#gap-018)).
The user intentionally returned to this form after the separate-module
API became too complex. A larger Plugin can delegate to ordinary internal
modules. Authors do not declare roles or separate facet modules. Core keeps
callback timing, write ownership, and owner-specific validation.

The current code already implements this form. `use Jido.Plugin` accepts
only `vsn` and `option_keys`. The version defaults to 1. Capability groups
are selected from implemented callbacks at compile time. Optional option
filtering limits which declaration options each owner receives. Live option
validation uses `validate_options/1` when implemented. These current API
facts correct GAP-019; they do not approve the complete document.

The selected live/durable distinction also corrects GAP-020. Dump output
and stored load input are portable. Reconstructed output is checked against
its live schema and can include local values. Resource reconstruction does
not transfer process ownership or prove that a saved resource still exists.

The user also selected the current required `after_commit/3` contract in
[GAP-021](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/GAP_ANALYSIS.md#gap-021).
The callback is optional to implement. When present, it is a required
post-commit step. Failure stops later hooks and Directives. The committed
state and the result already sent to the caller remain intact. Telemetry
provides optional observation.

The user selected removal of Scheduler durable delivery in
[GAP-023](/Users/mhostetler/Source/Jido/proj_jido_core/jido/docs/design/GAP_ANALYSIS.md#gap-023).
The target keeps OTP timers, mailbox delivery, and restoration of saved
recurring definitions. It removes saved pending occurrences, automatic
redelivery, enqueue controls, and business acknowledgement. The current
source still contains this feature; code removal and migration checks remain.
No replacement package or durable job system is part of this decision.

## Scope

The Plugin seam owns module declarations, owner callback groups, Plugin-owned Agent
state, Plugin Directive ownership, and Plugin callback order.

Actions and Flows own domain-state changes and the complete Directive list.
Agent Server owns live work and commit. Persistence owns records and adapters.
Topology owns planning and activation.

## Model

```text
one Plugin module with optional callbacks
  -> Agent evaluation callbacks
  -> Agent Server runtime callbacks
  -> Persistence conversion callbacks
  -> Topology contribution callbacks
```

A stateful Plugin owns one top-level field in the complete Agent state
map. There is no second Plugin state map. Owner callback groups remain
separate contracts, but they use the same authoring module. Internal manifest
fields and support types can still use facet names; those names do not
require separate modules from Plugin authors.

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

The Plugin module can implement these four Agent callbacks:

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

### Required after-commit notification

`after_commit/3` runs after live commit and any caller confirmation, before any
Directive. It receives its runtime reference, a read-only
`Jido.AgentServer.Plugin.Commit` view, and static options. A Plugin without
a runtime receives `nil` as its runtime reference. The view contains the
exact committed owned state (`nil` for a stateless Plugin), state version,
and identity context. It excludes the complete Agent, runtime handles,
storage adapters, and caller context. The only accepted results are `:ok` and
`{:error, reason}`; the callback cannot replace state or return Directives.

The Agent Server calls hooks in Plugin declaration order, including when
the state value is unchanged. Each hook runs in an owned task during
`directing`. Its operation limit is the finite `directive_timeout`, with
a 5,000-millisecond fallback when that option is `:infinity`. A failure,
task exit, or timeout stops later hooks and every Directive from that Turn.
The Server applies its error policy and records a committed failure at
the `after_commit` Outcome stage. Commit success does not confirm effects.

Startup, restore, and direct Agent commands do not call this hook. Plugin
runtimes rebuild from `Jido.Plugin.Init` on startup and replacement. Hooks
have no automatic replay guarantee. A synchronous call from a hook to the
same activation returns `{:error, :reentrant_commit}`. Cancellation is too
late once commit begins. Telemetry is the boundary for optional observation.

## Requirements

### Declaration

`PLG-REQ-001`: When an Agent declares Plugins, the Plugin boundary shall accept
an ordered list of package modules or `{module, keyword_options}` pairs.

`PLG-REQ-003`: If an Agent declares the same Plugin package more than once,
then the Plugin boundary shall reject the definition.

`PLG-REQ-005`: When the generated Plugin manifest selects an active owner,
the Plugin boundary shall use callbacks implemented in that same Plugin
module for the owner.

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

`PLG-REQ-017`: Retired. Live reducer output is checked against its schema,
not the durable portability rule. PLG-REQ-016 retains state validation;
PLG-REQ-055 retains portable dump output.

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

`PLG-REQ-049`: While a Plugin runtime runs, the Agent Server shall keep its private
process-management data outside Agent state and checkpoints.

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

`PLG-REQ-056`: When a Plugin load callback returns reconstructed live state,
the Persistence boundary shall validate that result with the owned state
schema.

`PLG-REQ-059`: When a Topology facet contributes static data, the Topology
boundary shall accept only canonical supported entries.

`PLG-REQ-060`: When a Topology facet contributes static data, the Topology
boundary shall keep process and persistence authority out of the callback.

### After-commit notification requirements

`PLG-REQ-077`: Where a Plugin implements `after_commit/3`, when a live Turn
commits, the Agent Server shall call that hook after any caller confirmation and
before starting any Directive, including when the state value is unchanged.

`PLG-REQ-078`: When more than one Plugin implements `after_commit/3`, the
Agent Server shall call those hooks serially in Plugin declaration order.

`PLG-REQ-079`: When the Agent Server calls `after_commit/3`, it shall provide
only the Plugin's runtime reference, a read-only view of its exact committed
owned state and version, and static options.

`PLG-REQ-080`: When an `after_commit/3` callback returns, the Agent Server
shall accept only `:ok` or `{:error, reason}` as its result.

`PLG-REQ-081`: If an `after_commit/3` hook fails, exits, or times out, then the
Agent Server shall skip all later hooks and Directives from that Turn.

`PLG-REQ-082`: If an `after_commit/3` hook fails, then the Agent Server shall
preserve the committed Agent, state version, and caller result already sent.

`PLG-REQ-083`: When startup, restore, or a direct Agent command runs, the
Plugin boundary shall not invoke `after_commit/3` for that operation.

`PLG-REQ-084`: When an Agent activation restarts, the Agent Server shall not
replay earlier after-commit notification attempts.

### Core Scheduler

The Scheduler is a core Plugin. Its owned state contains recurring schedule
definitions. Its supervised runtime owns OTP timers and job processes. Saved
definitions can recreate future timers after restore; they do not preserve
old mailbox messages or promise delivery of missed ticks. One-shot delayed
Signals remain transient. Normal Signal queueing stays with OTP.

Optional occurrence metadata identifies a scheduled tick. It is independent
of saved pending work, acknowledgement, and redelivery. This review does not
select removal of that metadata API. The retained requirements below were
recovered from commit `c2825dfb`; their IDs retain their original meaning.
The removed delivery requirements are explicitly retired below.

`PLG-REQ-061`: Where Scheduler recurring work includes a generation, the
Scheduler shall derive one opaque occurrence ID from its versioned identity
scope, job ID, generation, and scheduled UTC instant.

`PLG-REQ-062`: When Scheduler derives an occurrence ID, it shall exclude node,
PID, arrival time, and Signal ID from the occurrence coordinates.

`PLG-REQ-063`: When Scheduler creates Signals with the same occurrence
coordinates, it shall keep the occurrence ID and create a fresh Signal ID.

`PLG-REQ-064`: When Scheduler adds tracked occurrence metadata, it shall keep
Signal data and unrelated context unchanged.

`PLG-REQ-065`: If tracked occurrence metadata is absent, malformed, or
incomplete, then the Scheduler occurrence accessor shall return its documented
tagged error.

`PLG-REQ-066`: When Scheduler accepts a tracked recurring schedule, it shall
require a generation from 0 through 2,147,483,647.

`PLG-REQ-067`: Where a recurring schedule omits generation, the Scheduler shall
preserve the untracked definition and delivery behavior.

`PLG-REQ-068`: When Scheduler creates a one-shot delayed Signal, it shall keep
that timer and pending timer delivery outside Agent state and checkpoint recovery.

`PLG-REQ-085`: When a live Scheduler timer becomes due, the core Scheduler
shall send its Signal through the Agent's OTP mailbox boundary.

`PLG-REQ-086`: When saved recurring definitions are restored, the core
Scheduler shall recreate timers for future occurrences.

`PLG-REQ-087`: When a scheduled occurrence is missed during process loss,
the core Scheduler shall not automatically replay that occurrence.

`PLG-REQ-088`: When business work handles a scheduled Signal, the core
Scheduler shall not require an acknowledgement Directive from that work.

## Retired requirements

Requirements `PLG-REQ-030`, `PLG-REQ-033`, and `PLG-REQ-034` described broader
domain-state observation or Plugin-added Directive phases. Those capabilities
remain retired.

`PLG-REQ-069`: Retired. Durable delivery generation and enqueue-route requirements
are removed by the selected core Scheduler contract.

`PLG-REQ-070`: Retired. Core Scheduler no longer requires committed pending
business occurrences before delivery.

`PLG-REQ-071`: Retired. The one-pending-occurrence queue and its slot policy are removed.

`PLG-REQ-072`: Retired. Core Scheduler no longer resumes pending deliveries on restart.

`PLG-REQ-073`: Retired. Business acknowledgement with state commit is removed.

`PLG-REQ-074`: Retired. The durable pending-tick admission gate is removed.

`PLG-REQ-075`: Retired. The pending-delivery attempt interval is removed.

`PLG-REQ-076`: Retired. The durable retry duplicate-handling contract is removed.

These retirements state the selected target. The current code still implements
the removed feature until GAP-023's code cleanup is complete.

## Non-goals

- No Plugin replacement of an incoming Signal or caller context.
- No Plugin write to another package's input.
- No domain-state observation callback.
- No Plugin-added Directive phase.
- No stage behaviour, middleware protocol, or pipeline DSL.
