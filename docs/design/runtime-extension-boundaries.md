> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Runtime extension boundaries

[Design overview](README.md) | Previous: [Errors](errors.md)

- Status: Current extension points recorded; larger core and package designs deferred
- Scope: Jido core, `jido_durable`, `jido_cluster`, and `jido_fabric`

## Decision labels

This document distinguishes three states:

- **Implemented:** A public API with integration coverage on `v3-spike`.
- **Deferred — core proposal:** A possible future core contract. Do not build
  an extension that assumes it is available.
- **Proposed — pending full design:** This is a design direction. Do not treat
  its API, data shape, or package ownership as final.

## Implemented extension points

See the [core scope guide](../../guides/core-scope.md) for the current contract.
Core retains Builder, Codec, owned children, and public PID-based Agent Server
operations. Persistence uses `Jido.Persistence.Adapter` with binary keys and
values, including atomic compare-and-swap.

| Extension need | Current public support |
| --- | --- |
| Change pending schedule delivery timing | Scheduler Plugin `delivery_interval`; stable occurrence ID and acknowledgement remain unchanged. |
| Choose when to repair a local topology | Controller `repair: :manual`, `reconcile/2`, `status/2`, and `await_ready/2`. |
| Own a resource or recover application work | Existing Plugin runtime, public state read, and Signal/Directive callbacks. |
| Select a known node for an owned child | Existing explicit remote-child API. |
| Store committed Agent state | Existing persistence adapter and checkpoint operations. |

These controls do not supply a Ref facade, live target replacement, leases,
placement, or automatic recovery scans. Add another core operation only when
a real integration example demonstrates the missing contract.

## Goal

Jido core is a complete local Agent runtime. It owns Agent identity, Turn and
Commit rules, local activation, and the public instance API. It also defines
the minimum persistence contract that makes a Commit durable.

Future packages can add durable storage, recovery, automatic cluster placement,
and transport beyond the core owned-child Signal path. They must not depend on private Agent Server state,
private messages, or generated supervisor names.

## Deferred — core proposals

The following sections describe the earlier target design. They are not the
implemented data model or a prerequisite for using the current extension points.

### One Agent identity

`Jido.Agent.Ref` is the only Agent identity. Live lookup, persistence,
Directives, and future remote routing use the same value.

```elixir
%Jido.Agent.Ref{
  namespace: "my-app/primary",
  partition: nil,
  id: "order-123"
}
```

The identity tuple is `{namespace, partition, id}`. The Agent module and its
definition revision are stored in the Agent checkpoint. They are not part of
Agent identity.

Each Jido instance has one required stable namespace:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary"
end
```

The namespace is a non-empty binary. It is stable across process, node, and
application restarts. A module name remains the local OTP name, but it is not
the durable identity.

`Jido.Persistence.Key` is not a second Agent identity. Persistence uses the
Agent Ref directly.

### Public durable values

The proposed durable boundary has three values. REC-01 itself uses the
existing checkpoint adapter and Plugin state, without these new public structs:

```elixir
%Jido.Agent.Checkpoint{
  version: 1,
  agent_module: MyApp.OrderAgent,
  definition_revision: 1,
  agent_id: "order-123",
  state: %{status: :open},
  plugin_state: %{}
}

%Jido.Agent.Commit{
  turn_id: nil | "019...",
  source_signal_id: nil | "019...",
  checkpoint: checkpoint,
  state_version: 8
}

%Jido.Persistence.Record{
  agent_ref: agent_ref,
  status: :active,
  commit: commit,
  operation_id: "019...",
  storage_version: storage_version
}
```

`Jido.Agent.Commit` is not in the `Jido.AgentServer` namespace. It is a
stable Agent contract that the Server creates and persistence stores.
Explicit durable work belongs to Agent or Plugin state in the checkpoint.
Its capability owns stable IDs, acknowledgement, and recovery policy.
`Jido.Persistence.Record` is the only owner of `agent_ref` at the storage
boundary. Record validation matches that Ref to the Agent ID in the Commit
checkpoint.

`source_signal_id` connects the durable transition to its input Signal. It
does not make Signal processing idempotent. A future durable request log can
use it without changing the Commit identity.

`turn_id` and `source_signal_id` are nil only in the initial Commit that saves
a newly created Agent before it becomes ready. This Commit has state version
zero.

The checkpoint `version` identifies the checkpoint format.
`definition_revision` identifies the exact module-owned static Agent
definition. Persistent creation requires a positive revision and an exact
static match with the normalized definition exported by `agent_module`.
Restore fails before readiness if the module or revision does not match.

`state_version` changes once for each Agent state commit. `storage_version`
is an opaque compare-and-swap token normalized to nil, a nonnegative integer,
or a binary from 1 to 256 bytes. It can change for a lifecycle update. Work completion is an Agent commit.
`operation_id` identifies one attempted record write. A safe retry of the same
write uses the same operation ID.

A recovery capability keeps pending work across later Turns. Its worker reads
committed state after restart and sends completion through a new Signal. Core
does not impose a universal outbox, cursor, or gate on this background work.

The Record status is durable lifecycle intent:

- `:active` permits activation.
- `:hibernated` requires an explicit thaw.
- `:deleted` is a tombstone and prevents activation.

The status does not claim that a process is currently alive.

All four values are Zoi-backed structs. Jido validates them at each public
boundary. They contain only portable data.

Portable instance data follows the recursive core contract: no PID, port,
reference, function, improper list, or non-byte-aligned bitstring can enter
Agent state, Plugin state, a Directive, a checkpoint, or a durable work record. A
package cannot weaken this rule with a permissive schema.

### Compare-and-swap persistence

Persistence belongs to the Jido instance. The proposed replacement contract is:

```elixir
@callback load_agent(Jido.Agent.Ref.t()) ::
            {:ok, Jido.Persistence.Record.t()}
            | {:error, :not_found | Jido.Error.t()}

@callback persist_agent(Jido.Persistence.Record.t()) ::
            {:ok, Jido.Persistence.Record.t()}
            | {:error, :conflict | :indeterminate | Jido.Error.t()}
```

The callbacks are optional as one complete pair. A configured adapter supplies
the same behavior.

The persistence rules are fixed:

- A nil storage version means create only if the record is absent.
- A non-nil storage version means replace only that stored version.
- A successful write returns the new storage version.
- A conflict must not overwrite the stored record.
- Only a confirmed successful write lets the current Agent Server keep write
  authority.
- Any write error keeps the prior live Agent and state version, starts no new
  Directive, and stops the current Server with `:lost_write_authority`.
- A later explicit activation loads the authoritative Record before it admits
  Signals.
- The operation ID helps a provider recognize a repeated write and helps
  diagnostics. Core does not reconcile a failed write inside the Server that
  made it.

Normal Agent deletion writes a `:deleted` Record with compare-and-swap. It does
not use a blind delete. Physical tombstone removal is storage maintenance and
is not part of the Agent lifecycle API.

All Agents in one Jido instance use the same persistence provider. An Agent
Server cannot select or replace the provider. Applications use separate Jido
instances when they need separate storage authority.

### Ref-first instance API

The Jido instance is the stable public runtime boundary:

```elixir
ref = MyApp.Jido.agent_ref("order-123", partition: nil)

{:ok, ^ref} = MyApp.Jido.start_agent(MyApp.OrderAgent, id: "order-123")
{:ok, ^ref} = MyApp.Jido.activate_agent(ref)
{:ok, result} = MyApp.Jido.call(ref, signal)
:ok = MyApp.Jido.cast(ref, signal)
request_id = MyApp.Jido.send_request(ref, signal)
:ok = MyApp.Jido.cancel_turn(ref, turn_id)

:ok = MyApp.Jido.stop_agent(ref)
:ok = MyApp.Jido.hibernate(ref)
{:ok, ^ref} = MyApp.Jido.thaw(ref)
:ok = MyApp.Jido.delete_agent(ref)
```

The instance API uses Agent Refs. It does not require a caller to find a PID.
`whereis_local/2` can return a PID for local observation. Agent Server commands
and messages are internal and are not a package extension boundary.

An Agent-to-Agent Directive contains an Agent Ref. Directive dispatch resolves
the current runtime location for each delivery. A cached PID is observation
data only.

`cast/3` is a best-effort send. `:ok` means that the caller sent the message to
the resolved local Server. It does not confirm admission, execution, or
commit, and it does not promise a durable mailbox. The durability guarantee
for a synchronous call begins at Commit.

### Fixed lifecycle order

Core owns the operation order. A package cannot replace these state machines.

Creation:

```text
validate Agent Ref and new Agent
  -> confirm that no live Agent uses the Ref
  -> require a positive module-owned definition revision and exact static match
  -> start provisional Plugin runtimes and wait for readiness
  -> create the initial Record with compare-and-swap, when persistent
  -> publish the Agent as ready
  -> admit Signals
```

A successful persistent create means the initial Agent is recoverable under
its exact module definition revision. It fails if a durable Record already
exists or the Agent is not owned by a versioned module definition.
Readiness failure stops the provisional runtimes and writes no Record.

Activation or thaw:

```text
validate Agent Ref
  -> load the persistence Record
  -> restore and validate the checkpoint
  -> require the saved module definition revision
  -> start Plugin runtimes from committed state and wait for readiness
  -> publish the Agent as ready
  -> admit Signals
```

Commit:

```text
evaluate the Signal
  -> build the candidate Agent
  -> build the Commit and Record
  -> compare-and-swap the Record
  -> replace live Agent state
  -> reply to the caller
  -> dispatch the transient Directive batch
  -> admit the next Signal when the Turn settles
```

Deactivation:

```text
stop Signal admission
  -> cancel evaluation or let it finish, as policy selects
  -> wait for non-cancellable Commit or Directive work to settle
  -> confirm the latest durable Record
  -> persist lifecycle status when required
  -> remove the live directory entry
  -> stop the Agent Server
```

The core failure meanings are `:not_found`, `:conflict`, `:indeterminate`,
`:unavailable`, and invalid data. Providers can return a defined composed
Splode error, but they must preserve these meanings.

### Instance ownership

Core owns these facts:

- One Agent Server belongs to one Jido instance.
- One instance owns the local Agent Pool and local lookup.
- The instance persistence provider is the only storage authority for its
  Agent Refs.
- Provider resources start before Agent activation.
- Instance drain stops new admission and lets active work reach a safe
  boundary before shutdown.
- Only Turn evaluation is cancellable. Commit and Directive work must reach
  their defined terminal boundary.
- Every Plugin runtime root replacement uses a fresh Init from the Agent
  Server's latest committed Plugin state and state version.
- Lifecycle telemetry is observation only. It cannot change a Turn or Commit.

The application continues to supervise external resources such as an Ecto
Repo before the Jido instance.

### Plugin and provider terminology

`Plugin` has one meaning: an Agent capability with declared state, command
callbacks, Directives, and an optional runtime.

`Provider` means instance infrastructure in this proposal. Persistence is its first
provider boundary. A Provider does not receive Agent Turn callbacks and cannot
change candidate Agent state.

Core does not add a generic hook system. New provider boundaries require a
separate design and fixed lifecycle semantics.

## Deferred core implementation work

This list belongs to the earlier proposal. It does not authorize changes to
the retained API. Some guarantees already exist through different public
types; compare them with integration evidence before replacing anything:

1. Add the required instance namespace and canonical `Jido.Agent.Ref`.
2. Use Agent Ref for Registry, persistence, and Directives.
3. Add the proposed `Jido.Agent.Commit` and
   `Jido.Persistence.Record` as public structs.
4. Require one positive versioned module-owned definition for every Agent.
5. Replace blind persistence writes with compare-and-swap writes.
6. Prove explicit recoverable work with Plugin-owned intent and completion Signals.
7. Replace normal record deletion with a durable tombstone.
8. Remove per-Agent persistence adapter selection.
9. Add Ref-first command, asynchronous request, cancellation, lifecycle, and
   inspection operations to the instance facade.
10. Keep Agent Server PID-based functions internal to the Jido instance.
11. Enforce activation, Commit, restoration, and drain order in core.
12. Add failure-injection tests that prove every persistence write error
    removes the current Server's write authority.
13. Make `cast/3` a best-effort send with no admission acknowledgement.
14. Keep logical relationship policy, authoring Codecs, and debug timelines
    outside core.

## Proposed — `jido_durable`

The following ideas require a full package design:

- Production compare-and-swap providers for database and object stores.
- A durable Agent catalog and record scan API.
- Automatic Agent activation after instance or node restart.
- Ownership claims, fencing values, leases, and lease renewal.
- Indeterminate write reconciliation and bounded retry policy.
- Tombstone retention and physical cleanup.
- Checkpoint and Record migrations.
- Durable Signal receipts and bounded command deduplication.
- Durable result lookup for callers with an uncertain reply.
- Commit history, compaction, and retention policy.

The package can supervise a recovery controller next to the Jido instance. It
uses only the public persistence and instance APIs. The exact supervision and
configuration contract is not locked.

## Proposed — `jido_cluster`

Explicit node targeting for an owned child belongs to core Jido. The
[remote-child contract](remote-owned-children.md) defines this foundation.
A cluster package selects placement and recovery policy; an application does
not need such a package merely to start a child on a known Erlang node.

The following ideas require a full package design:

- BEAM cluster membership and node health.
- A distributed Agent directory.
- Placement and rebalance policy.
- Placement policy built on core activation of an owned child on an explicit node.
- Failover coordination after node loss.
- Load and capacity reporting.

A cluster directory is a location service. It is not durable storage
authority. When durability is enabled, a new owner must first win the durable
record claim. A Registry result alone cannot authorize a Commit.

Cluster-only operation can provide one live process by best effort. It cannot
recover committed state after process loss without a durable provider.

## Proposed — `jido_fabric`

The following ideas require a full package design:

- Signal routing between Jido namespaces, clusters, or transports.
- External Agent Ref encoding and resolution.
- Remote request and response correlation.
- Admission control, backpressure, and delivery timeouts.
- Gateways, authentication, and tenancy.
- Store-and-forward delivery or a durable Signal inbox.

Fabric does not inspect an Agent checkpoint or Commit. It delivers a Signal to
the instance boundary. The receiving Agent uses the normal local admission and
Commit path.

A durable inbox is separate from Agent Commit persistence. Core does not claim
durable Signal admission or exactly-once delivery.

## Proposed — additional provider boundaries

Future designs can consider explicit providers for runtime location,
placement, transport, and ownership. These APIs are not locked.

Until those designs exist, extensions use the current public instance, Agent
Server, Plugin, and persistence APIs. The Ref-first facade remains a proposal.
Extensions must not replace the core Commit state machine.

## Package boundary test

An external package has a missing core contract if it must do one of these
actions:

- Read or change private Agent Server state.
- Send a private Agent Server message.
- Construct a generated supervisor or Registry name.
- Change candidate Agent or Plugin state outside the Turn Evaluator.
- Dispatch a Directive before Commit.
- Treat a PID as durable Agent identity.

Add a small public core contract when this test fails. Do not expose the
private implementation.

## Current core non-goals

Jido core does not implement:

- A production database or object-store client.
- Storage retry schedules or cleanup jobs.
- Automatic recovery scans.
- Cluster membership or leader election.
- Placement, replication, or consensus.
- Transport gateways or network security beyond explicit Erlang node targeting.
- A durable Agent mailbox.
- Exactly-once Signal or Directive delivery.
- Application checkpoint migrations.
- Durable audit history.

The earlier proposal also removed Builders, Codecs, logical relationships,
and local debug timelines. Those removals are deferred. The current APIs
remain supported; this refinement changes only the extension points above.
