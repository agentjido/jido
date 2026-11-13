---
title: Jido durable Agent activation plan
status: implemented
last-reviewed: 2026-11-13
---

# Jido durable Agent activation plan

Purpose: Define the target model, public contract, lifecycle, and delivery plan
for a durable Agent and its resident `Jido.AgentServer` activation.

Implementation status: The local, single-Instance activation kernel described
here is implemented. Mesh membership, remote placement, replication, and
distributed failover remain outside Jido core.

## Goal

A managed Agent is a durable logical entity. It stays alive when no BEAM
process is resident for it. `Jido.Agent.Address` is its stable address.

`Jido.AgentServer` is the warm, resident activation of that Agent. It runs one
Agent at a time, serializes work, commits state, and protects the execution
boundary. The activation can stop after an idle period. The Agent does not
stop when this occurs.

The first implementation supports one Jido Instance only. It must keep a clean
boundary for a later mesh that can route work to an owning Instance. Jido core
does not implement mesh membership, placement, remote routing, replication, or
distributed failover in this plan.

## Terms

- **Agent**: The durable logical entity and its committed state.
- **Agent Address**: The stable public identity and address of one Agent.
- **Activation**: The current resident OTP runtime for one Agent.
- **AgentServer**: The local Turn kernel inside an activation.
- **Jido Instance**: The local runtime host. It routes by Agent Address, controls
  activation lifetime, and provides persistence.
- **Passivation**: A clean stop of a resident activation while the durable
  Agent remains alive.
- **Reactivation**: The restore of a passivated Agent into a new activation.
- **Warm residency**: The idle period during which an activation stays
  resident and ready for more work.

An in-memory Agent can use the same kernel for tests and temporary work. It
does not have the durable-Agent guarantee. It is unavailable after its
activation stops.

## Component boundaries

- `Jido.Agent` owns the immutable Agent value and process-free state
  transitions.
- `Jido.Exec` runs Actions and Flows. It knows nothing about Agents, durable
  execution, activation, or routing.
- `Jido.Durable` accepts only `Jido.Flow`. It owns durable Flow continuation
  and reuses `Jido.Exec`.
- `Jido.AgentServer` is the resident Turn kernel. It owns serialized admission,
  commit, effects, waits, cancellation, and live recovery.
- The Jido Instance owns local routing, activation control, persistence access,
  and the residency policy.

This dependency direction is fixed:

```text
Jido.AgentServer -> Jido.Agent
Jido.AgentServer -> Jido.Durable -> Jido.Flow -> Jido.Exec
Jido Instance    -> Jido.AgentServer
Jido Instance    -> Persistence profile -> codec and Store adapter
```

`Jido.Exec` does not depend on `Jido.Agent` or `Jido.Durable`.
`Jido.Durable` does not depend on `Jido.Agent` or `Jido.AgentServer`.
`Jido.AgentServer` does not know about mesh membership or remote nodes.

## Identity and state model

Agent identity and process identity are not the same.

- An Agent Address remains stable for the logical life of the Agent.
- Each activation has one `agent_activation_id` UUID.
- A worker restart inside one activation keeps the activation ID.
- Passivation followed by reactivation creates a new activation ID.
- Neither worker restart nor reactivation changes the Agent Address.

The runtime reports three separate state axes:

```text
Agent lifecycle:  alive | deleted
Work state:       idle | running | waiting | faulted
Residency:        passivated | activating | active | passivating
```

A waiting Agent can be alive and passivated. A deleted Agent has a tombstone
and cannot reactivate. Stopping an AgentServer activation does not delete the
Agent.

`Jido.AgentServer.Status` reports the state of a resident activation. An
Instance-level status operation can combine persistence and activation state
to report a passivated Agent. AgentServer does not claim to report state after
its activation stops.

## Public AgentServer API

The accepted `Jido.AgentServer` API has 14 functions:

```elixir
child_spec/1

call/3
cast/3
submit/3
await/2
abandon/1

cancel_turn/3

quiesce/2
resume/2
remove_topology_member/4
stop/3

snapshot/2
status/2
await_ready/2
```

The public value types are:

- `Jido.AgentServer.server()`
- `Jido.AgentServer.Pending.t()`
- `Jido.AgentServer.TurnResult.t()`
- `Jido.AgentServer.Snapshot.t()`
- `Jido.AgentServer.Status.t()`

`Jido.Agent.Address` is the primary logical address. `server()` is an advanced,
activation-specific handle. A direct AgentServer operation never activates or
reactivates an Agent. The handle becomes invalid when the activation stops.

The Jido Instance owns normal create and restore operations:

- `Jido.create_agent/4` synchronously creates a new durable Agent and returns
  its Address without starting an activation.
- `Jido.activate_agent/4` restores an existing durable Agent.
- There is no restore-or-create operation.
- A tombstone, conflict, missing record, or invalid record has a distinct
  result.
- Address-based Signal delivery can activate a passivated Agent.

`stop/3` stops the resident activation. It does not end the logical life of a
durable Agent. An explicit Instance lifecycle operation must write a tombstone
to delete an Agent.

## Result values

`snapshot/2` returns the complete committed Agent view:

```elixir
%Jido.AgentServer.Snapshot{
  agent: %Jido.Agent{},
  agent_address: %Jido.Agent.Address{},
  agent_activation_id: activation_id,
  agent_revision: non_neg_integer(),
  persistence_revision: non_neg_integer() | nil,
  durability: :memory | :durable
}
```

An accepted Turn returns one `TurnResult`:

```elixir
%Jido.AgentServer.TurnResult{
  turn_id: turn_id,
  agent_address: %Jido.Agent.Address{},
  agent_activation_id: activation_id,
  status:
    :committed
    | :waiting
    | :failed
    | :cancelled
    | :timed_out
    | :uncertain,
  durability: :memory | :durable | :unknown,
  agent_revision: non_neg_integer(),
  persistence_revision: non_neg_integer() | nil,
  reply: %Jido.Signal{} | nil,
  waits: [Jido.Exec.Wait.t()],
  effects: :none | :pending,
  error: term() | nil
}
```

The result rules are:

- Every accepted Turn returns `{:ok, %TurnResult{}}`, including a failed,
  cancelled, timed-out, or uncertain Turn.
- `{:error, reason}` means that the request was not accepted, the address was
  not available, or transport failed.
- `reply` is present only for a committed Turn.
- `waits` is present only for a waiting Turn.
- `error` is present only for failure, timeout, or uncertainty.
- `persistence_revision` is `nil` for an in-memory Agent.
- Public values contain no PID, task, monitor, callback, Runic value, or
  internal Directive.

## Activation ownership

The Jido Instance owns normal activation lifetime.

- Address-based Signal operations route to a current activation or start one.
- Activation is single-flight for one Agent Address.
- A bounded per-Agent FIFO holds input while activation starts.
- The activation queue is not durable.
- A stopped in-memory Agent cannot be restored.
- An externally supervised activation is outside Instance lifetime control.

The activation root owns the stable local Registry entry, Plugin runtime
processes, and AgentServer worker. The Registry entry can report `:starting`,
`:ready`, `:recovering`, `:quiesced`, or `:faulted` while the worker changes.

Applications can use `child_spec/1` to supervise a complete activation root.
This is an explicit opt-out from Instance lifetime control. Persistence and
wait rules still apply, but the application owns activation start and stop.

## Warm residency

An activation stays resident for a configured idle period. The initial default
is five minutes. The Jido Instance owns this policy through one setting:

```elixir
activation: [idle_residency_timeout: :timer.minutes(5)]
```

The first version has no per-Agent timeout override.

AgentServer implements the local idle timer because it knows when work is
safe. The Instance supplies the timeout value. These rules apply:

- The timeout starts only when AgentServer is fully idle.
- Accepted work cancels the idle timer.
- A new full timeout starts when the activation becomes idle again.
- Running work, queued work, an unconfirmed commit, and unsettled effects
  prevent passivation.
- A durable wait becomes idle after the continuation and wait state are saved.
- A Flow can run longer than the timeout. Runtime duration is not idle time.
- Worker failure is recovery, not passivation.
- Native OTP hibernation is an optional memory optimization. It is not
  passivation and has no public lifecycle meaning.

## Turn admission and execution

One Agent has one active Turn. A fixed, bounded FIFO holds accepted Turn
requests. `queue_limit` is the only queue policy option. There is no pluggable
queue policy.

`call/3`, `cast/3`, and `submit/3` use the same Turn path:

1. AgentServer validates and accepts the Signal.
2. `Jido.Agent` selects the route and prepares the Flow instruction.
3. `Jido.Exec` or `Jido.Durable` runs the selected Flow.
4. The process-free Agent transition produces a complete candidate Agent.
5. AgentServer validates and commits the complete candidate Agent.
6. AgentServer returns the committed or waiting `TurnResult`.
7. AgentServer runs the post-commit effect batch.
8. The next Turn starts only after that batch settles.

A durable wait is a committed stop for the caller. A matching Signal resumes
the same Turn and returns the next `TurnResult`. AgentServer does not hold one
call open across a long wait.

`submit/3` returns a small owner-bound `Pending` value with the Turn ID,
request ID, and owner. It is not durable or transferable. `await/2` waits for
its result. `abandon/1` stops local waiting but does not cancel the Turn.

## Signal delivery and durable wake-up

Signals are the only input for new work and durable resume. AgentServer has no
separate public wait-delivery API.

The Instance owns local wake delivery:

1. A Flow confirms its execution checkpoint.
2. The Instance stores each timed wake in a one-minute bucket and one of 64 fixed shards.
3. AgentServer commits the matching waiting receipt in the Agent record.
4. The local wake capability reads the active-bucket index and finds a due occurrence.
5. It creates a `Jido.Signal` and delivers it by Agent Address.
6. The Instance routes to the warm activation or reactivates the Agent.
7. AgentServer validates the wait match and resumes the Flow.

`Jido.Durable` defines and restores the wait. It does not schedule work.
AgentServer does not contain a scheduler. One local wake capability owns one
Instance. A recovery read failure retries with bounded backoff and prevents
the instance start from reporting ready.

## Deadlines and cancellation

Turn cancellation always requires an exact Turn ID.

- A queued Turn is removed.
- A running Turn stops before commit.
- A waiting durable Turn gets a terminal cancellation receipt.
- An already committed Turn returns an error.

A Turn deadline covers one active execution segment. It stops when the Turn
enters a durable wait and starts again when a Signal resumes the Turn.

Caller wait, admission, effect, persistence, readiness, and activation
timeouts are separate clocks. The Instance owns AgentServer lifecycle timeout
policy.

## Commit, reply, and effects

AgentServer is the only Agent commit owner for its active activation. It
returns to the caller after the commit or durable checkpoint. The caller does
not wait for post-commit effects. The next Turn waits for the effect batch to
settle.

A reply Signal exists only in `TurnResult`. AgentServer sends no separate reply
message. `cast/3` discards a reply without failing the transition.

Core effects are limited to Signal emission and explicitly Plugin-owned typed
effects. The design removes generic Directive handlers and server-control
effects. Agent and parent delivery use Emit targets that the Instance resolves.

Effects run in order. If one effect fails, AgentServer records the failure and
stops the remaining effects. The activation stays available. A settled effect
failure does not prevent later passivation. Core has no effect outbox or
automatic effect retry.

## Durable execution and persistence

Persistence belongs to the Jido Instance. One profile fixes its Store and
codec for Agent, Flow, and wake records. A namespace manifest pins that codec
and all V3 record layouts. Per-Agent Store replacement is not supported. The
default Term codec is compact. The tagged JSON codec is opt-in.

The adapter must atomically compare and swap one complete Agent record. It
must distinguish:

- successful write;
- known no-write;
- revision conflict; and
- uncertain result.

The record contains the frozen Agent snapshot and only the latest durable Turn
receipt. A later durable Turn replaces the earlier receipt. Core has no Agent
journal and no general Turn-result history.

For a durable Flow, Jido prepares the execution record and timed wakes before
it writes the Agent receipt. The Agent record is the commit point. A crash can
leave an auxiliary orphan, but a committed timed wait cannot lack its wake
record.

The latest receipt supports exact resume retry. The durable wait input key
contains Agent Address, Turn ID, Wait ID, and Signal ID:

- The same key and the same Signal content returns the existing result.
- The same key with different content is a conflict.
- The first successful compare-and-swap wins.
- A stale or unmatched input has a specific error.

Ordinary Signals are not deduplicated by AgentServer.

An uncertain write closes admission and puts the activation in a faulted
state. AgentServer does not retry it without proof. An Instance reconciliation
operation reads the authoritative record and replaces the faulted activation
with a new activation ID.

A tombstone permanently reserves an Agent Address. The design has no Address generation
field and does not reuse a deleted Address.

## Revision model

The design has two independent revisions:

- `agent_revision` increments after an Agent state commit or definition
  upgrade. It does not change for a wait-only write or failure receipt.
- `persistence_revision` increments after every durable compare-and-swap,
  including wait, input, cancellation, commit, upgrade, and tombstone writes.
  It is `nil` for an in-memory Agent.

`state_version` is not a public AgentServer term.

The existing `Jido.Agent.vsn` identifies the Agent definition. An upgrade must
change `vsn` and increment `agent_revision`. The frozen snapshot and existing
reference fingerprints validate executable references. AgentServer does not
add `definition_vsn`, `definition_digest`, or a second definition catalog.

The Jido Instance owns definition upgrades as activation replacement. An
upgrade requires no active or waiting durable Turn. It does not migrate an
active continuation. Agent migration changes only non-Plugin state. Each
Plugin owns migration of its state.

## Passivation protocol

Idle timeout does not permit an unsafe process exit. Passivation is a defined
protocol:

1. AgentServer enters `:passivating` and atomically closes admission.
2. It confirms that no queued or running Turn exists.
3. It confirms that effects and Plugin work are settled.
4. It confirms that the Agent snapshot, latest receipt, and durable wait are
   committed.
5. It unregisters the activation as a valid delivery target.
6. The activation root stops normally.

If a Signal arrives during passivation, the Instance activation path holds it
in the bounded activation queue. It delivers the Signal after passivation and
reactivation finish. A caller that uses a direct server handle gets a
not-accepted error and must resolve the Agent Address again.

A known persistence no-write can reopen admission. A revision conflict or an
uncertain result leaves the activation quiesced or faulted. It must not report
successful passivation.

## Reactivation protocol

Address-based delivery to a passivated Agent uses one local activation path:

1. The Instance receives the Agent Address and Signal.
2. It confirms that no activation is ready or starting.
3. It starts one activation root for the Agent Address.
4. The activation restores and validates the durable record.
5. It creates a new activation ID and registers as ready.
6. The Instance delivers queued Signals in FIFO order.

Concurrent requests join the same activation attempt. A missing record,
tombstone, invalid record, or persistence failure is returned to every queued
caller with a specific result.

## Plugin boundary

Plugin authority is phase-specific:

- Admission can accept or reject input and add ephemeral input data.
- Reduction can change only the Plugin's owned state field.
- Post-commit processing can produce only the Plugin's typed effects.

Plugins cannot change Agent identity, definition, topology, lifecycle,
revision, or another Plugin's state. Plugin order is deterministic.

New Plugins start with their declared defaults. Removed Plugins delete their
owned state. A Plugin version change runs that Plugin's migration.

Plugin runtime processes run under the activation root. With
`:rest_for_one`, a Plugin crash restarts that Plugin and the AgentServer worker
while it keeps the activation ID and local checkpoint. A worker-only crash does
not restart healthy Plugins. Repeated failure can terminate the activation
root.

Authentication and authorization belong to the host or an explicit Plugin.
An Agent Address is an address, not a credential. AgentServer validates Signal and
wait semantics only.

## Lifecycle controls

`quiesce/2` closes admission and lets the caller inspect a stable resident
runtime. `resume/2` reopens admission when the runtime is safe. Both return
`{:ok, %Status{}}`.

`stop/3` is graceful activation stop. It closes admission, rejects queued
direct work, settles active pre-commit work, preserves a durable wait, settles
effects and Plugin work, and stops runtime resources. It returns
`{:ok, %Snapshot{}}`. The durable Agent remains alive.

If `quiesce/2` or `stop/3` reaches its timeout, admission stays closed and the
control operation stops. No hidden background stop continues. The caller can
resume, cancel, retry, or use supervisor force.

The resident runtime phases are:

```elixir
:starting
| :idle
| :running
| :waiting
| :quiescing
| :quiesced
| :passivating
| :stopping
| :faulted
```

`status/2` reports semantic state only. It does not expose exact internal
process phases or process values.

## Failure rules

An ordinary Turn failure preserves the last committed Agent and keeps the
activation alive. AgentServer stops only for an integrity failure, explicit
stop, successful passivation, or exhausted activation-root restart policy.

AgentServer keeps only current status and the last outcome. It has no history
ring, error-policy callback, failure counter, or `ErrorReport` effect.

## Telemetry

Telemetry can contain safe identifiers and classifications:

- namespace and local partition;
- Agent Address and activation ID;
- Turn, execution, and Signal IDs;
- Agent and persistence revisions;
- work and residency states; and
- status and error classes.

Telemetry must not contain Agent state, Signal data, reply content, raw
sensitive errors, Plugin state, or credentials.

## Clean boundary for a future mesh

The single-Instance path is:

```text
Signal entry
    -> Jido Instance route by Agent Address
    -> local activation or reactivation
    -> AgentServer Turn
```

A future mesh can add one step before the local activation path:

```text
Signal entry
    -> mesh selects the owning Instance
    -> owning Instance routes by Agent Address
    -> local activation or reactivation
    -> AgentServer Turn
```

AgentServer stays unchanged in both paths. A future mesh owns:

- membership and discovery;
- placement and ownership;
- remote Signal transport;
- ownership leases and commit fencing;
- distributed wake claims;
- failover and rebalancing; and
- optional replication.

The first version does not add placeholders for these features. It preserves
the boundary by using Agent Address at entry, keeping routing in the Instance, and
keeping all Agent commits behind the persistence adapter.

## Waterpark-like single-Instance simulation

The end-to-end proof is a Waterpark-like simulation that uses one Jido
Instance. It demonstrates the programming model without implementing a mesh.

The simulation has many durable, long-lived Agents. Signals enter through the
Instance by Agent Address. Only recently active Agents have resident
AgentServers. Idle Agents passivate and later reactivate from durable state.

The automated example must prove:

1. Many durable Agents start under one Instance.
2. Signals addressed by Agent Address update independent Agent state.
3. Repeated activity keeps an activation warm.
4. Idle timeout passivates an Agent without deleting it.
5. A later Signal reactivates the same Agent Address with its committed state.
6. Worker failure keeps the activation ID and recovers from the local
   checkpoint.
7. Passivation and reactivation change the activation ID.
8. A durable event wait resumes through a matching Signal.
9. A due timer or cron occurrence reaches a passivated Agent through the local
   wake capability.
10. No caller stores or routes by AgentServer PID.
11. The number of resident activations falls after the idle period.
12. All delivery stays inside one Jido Instance.

The normal ExUnit example uses a bounded Agent count and a short configured
idle timeout so it stays fast and deterministic. An optional load profile can
raise the count to thousands. The correctness test must not use real
five-minute waits.

The simulation must not start a second Jido Instance, connect BEAM nodes, use a
distributed Registry, or emulate a remote owner. Its purpose is to prove that
those features can be added outside AgentServer.

## Delivery sequence

### 1. Contract and types

- Keep the public AgentServer API at the accepted 14 functions.
- Add or align `Pending`, `TurnResult`, `Snapshot`, and `Status`.
- Make Agent Address the normal address and keep server handles advanced.
- Separate Agent lifecycle, work state, and residency state in public terms.

### 2. Activation root and worker

- Make the activation root own the stable local Registry entry and activation
  ID.
- Put the replaceable `gen_statem` worker behind that root.
- Keep the activation ID across worker recovery.
- Remove public worker and topology inspection.

### 3. One Turn path

- Route `call`, `cast`, and `submit` through one admission and execution path.
- Use `Jido.Agent` for process-free transition preparation.
- Use `Jido.Exec` for transient Flow execution.
- Use `Jido.Durable` for durable Flow execution and resume.
- Commit one complete candidate Agent through one compare-and-swap path.

### 4. Durable activation and recovery

- Separate strict create from strict restore.
- Restore the Agent snapshot, receipt, continuation, and revisions.
- Make wait resume idempotent by the durable input key.
- Keep uncertain persistence results closed for reconciliation.

### 5. Warm residency and passivation

- Add the Instance-level `idle_residency_timeout` setting.
- Start the idle timer only from a safe idle state.
- Implement the passivation state and protocol.
- Queue Address-based input that races with passivation.
- Reactivate with the same Agent Address and a new activation ID.

### 6. Local wake capability

- Find due durable timer and cron occurrences for this Instance.
- Convert each occurrence to a Signal.
- Deliver by Agent Address through the normal activation path.
- Reuse the same path for external event Signals.
- Do not add a scheduler to AgentServer or Durable.

### 7. Waterpark-like proof

- Add the co-located example and ExUnit test.
- Run the bounded correctness scenario in the normal example test suite.
- Keep the thousands-of-Agents profile optional.
- Record resident activation counts and state restoration evidence.
- Confirm that no mesh or cluster module is required.

## Removed or moved concepts

This design removes or moves these concepts from AgentServer:

- public `start` and `start_link` as the normal lifecycle API;
- `whereis`, `alive?`, activation, and worker inspection;
- direct Agent and Plugin-state reads;
- cancel-current behavior;
- public hibernate and thaw behavior;
- public owner and idle-policy mutation APIs;
- runtime topology mutation and adoption;
- AgentServer definition upgrade logic;
- history and debug rings;
- reply gates and requester tracking;
- generic Directive handlers;
- error-policy callbacks and counters;
- AgentServer execution-option duplication;
- effect retry and outbox logic;
- an AgentServer scheduler or worker pool;
- mesh membership, placement, and remote routing; and
- native OTP hibernation as a lifecycle concept.

## Completion criteria

The plan is complete when:

- A durable Agent remains addressable while no AgentServer process exists.
- Address-based Signal delivery activates or reuses one local activation.
- One Agent has no concurrent commit owner inside the Instance.
- AgentServer can passivate only from a proven safe state.
- Worker restart and Agent reactivation have distinct identity rules.
- Durable waits resume only through Signals.
- Scheduled durable work can wake a passivated Agent on one Instance.
- Public values expose no runtime process or Runic implementation value.
- The Waterpark-like simulation passes as part of the example test suite.
- AgentServer contains no mesh, node, placement, or remote transport code.

## Related records

- [Agent component](../components/agent.md)
- [Exec component](../components/exec.md)
- [Durable component](../components/durable.md)
- [Persistence component](../components/persistence.md)
- [Package vision](package-vision.md)
- [Agent boundary refactor plan](../plans/2026-11-11-1815-agent-boundary-refactor-plan.md)
- [Superseded restore-or-create decision](../adr/0002-restore-or-create-durable-agent-activation.md)
