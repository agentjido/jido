> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the current core scope](../../guides/core-scope.md).

# Instance persistence

[Design overview](README.md) | Previous: [Commit and effects](commit-and-effects.md) | Next: [Durability guarantee](durability-guarantee.md)

- Status: Deferred core proposal; current persistence uses the binary adapter
- Depends on: Jido instance, Agent Ref, Agent checkpoint, and Agent Commit.
- Defines: the proposed instance-level load and compare-and-swap callbacks.

REC-01 uses the existing byte adapters and Plugin-owned intent. This proposed
instance API remains separate work; it no longer requires a core Directive
outbox. See [Commit and effects](commit-and-effects.md).

## Boundary

Persistence belongs to `MyApp.Jido`, not to an Agent or Plugin module. This
keeps storage I/O outside the direct Agent command path. All Agents in one Jido
instance use the same provider. An Agent Server cannot select another adapter.

These are module callbacks. They do not run inside the `MyApp.Jido` supervisor
process. Jido calls them at the Agent Server persistence boundary.

An application can add two callbacks to its instance:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary"

  @impl Jido.Instance.Persistence
  def load_agent(ref), do: MyApp.AgentStore.load(ref)

  @impl Jido.Instance.Persistence
  def persist_agent(record), do: MyApp.AgentStore.compare_exchange(record)
end
```

The callbacks are optional as one complete pair. If the module defines none,
persistence is disabled. If it defines one, it must define both. `use Jido`
checks this contract at compile time.

## Agent identity

Persistence uses the canonical Agent Ref directly:

```elixir
%Jido.Agent.Ref{
  namespace: "my-app/primary",
  partition: nil,
  id: "order-123"
}
```

There is no separate `Jido.Persistence.Key`. Registry, persistence, and
Directives use the same Agent identity. The Agent module is
stored with its definition revision in the checkpoint and is not part of the
persistence key.

## Persistence Record

The instance stores one defined value:

```elixir
%Jido.Persistence.Record{
  agent_ref: agent_ref,
  status: :active,
  commit: %Jido.Agent.Commit{},
  operation_id: "019...",
  storage_version: "opaque-store-version"
}
```

The fields have these meanings:

- `agent_ref` is the canonical Agent identity.
- `status` is `:active`, `:hibernated`, or `:deleted`.
- `commit` contains the checkpoint, state version, and Turn identity. Explicit pending
  work belongs to Agent or Plugin state inside the checkpoint.
- `operation_id` identifies one attempted write. A safe retry keeps it.
- `storage_version` is nil, a nonnegative integer, or a binary from 1 to 256
  bytes. It is the opaque compare-and-swap token.

The provider returns the storage version with the Record but does not include
it in the encoded durable Record content.

The status records lifecycle intent. It does not claim that an Agent process
is alive.

`Jido.Persistence.Record` is a Zoi-backed public struct. Jido validates every
loaded and returned Record. The persistence implementation owns its storage
model, encoding, encryption, and transactions. It must not change the Record
meaning.

Record validation also validates the nested checkpoint portable terms and the bounded storage-version token. A provider cannot return a
process-local handle inside a valid Record.

The Record is the only owner of `agent_ref` at the persistence boundary. The
nested Commit does not repeat it. Record validation confirms that
`agent_ref.id` equals `commit.checkpoint.agent_id`.

`load_agent/1` must return a Record whose complete Agent Ref equals the
requested Ref. Jido rejects a valid Record returned for the wrong namespace,
partition, or Agent ID.

## Callback contract

```elixir
@callback load_agent(Jido.Agent.Ref.t()) ::
            {:ok, Jido.Persistence.Record.t()}
            | {:error, :not_found | Jido.Error.t()}

@callback persist_agent(Jido.Persistence.Record.t()) ::
            {:ok, Jido.Persistence.Record.t()}
            | {:error, :conflict | :indeterminate | Jido.Error.t()}
```

`persist_agent/1` is a compare-and-swap operation:

- A nil `storage_version` creates the Record only when no Record exists.
- A non-nil `storage_version` replaces only that stored version.
- Success returns the Record with its new storage version.
- A version mismatch returns `{:error, :conflict}`.
- A write with an unknown result returns `{:error, :indeterminate}`.
- If Jido reaches the instance `persistence_timeout` before a write returns,
  Jido treats the result as indeterminate because the provider can have stored
  the Record.

The provider can use a database revision, ETag, or transaction sequence as the
storage version. It must normalize the token to the permitted integer or
bounded binary form before it crosses the callback boundary.

Only `{:ok, record}` confirms the write and lets the current Agent Server keep
write authority. Every error result means that the current Server must stop
before it admits or performs more work. A later activation loads the
authoritative Record through `load_agent/1`.

`operation_id` still lets a provider recognize a repeated write and helps
diagnose an indeterminate result. Core does not reconcile an uncertain write
inside the Server that attempted it.

## Lifecycle

On persistent Agent creation:

```text
build and validate Agent Ref and Agent
  -> confirm a positive module-owned definition revision and exact static match
  -> reserve the local Agent Ref without publishing it
  -> start Plugin runtimes from the validated initial Plugin state at version zero
  -> wait for all Plugin runtimes to become ready
  -> build an initial Commit at state version zero
  -> persist a new active Record with a nil storage version
  -> publish the Agent as ready
  -> accept Signals
```

The initial Commit has no Turn ID or source Signal ID. Its
checkpoint contains the Agent module and definition revision. A successful
`start_agent/2` means that the initial Agent is recoverable under that exact
definition. The operation fails if a durable Record already exists, the
Agent definition is invalid, or the Agent's static configuration does not
exactly match the normalized configuration owned by its module.

Runtime startup before the initial write is provisional. It cannot admit a
Signal or dispatch a Directive. If `child_spec/1` or `await_ready/2` fails,
Jido stops all provisional runtime roots, releases the local reservation, and
writes no Record. If the initial persistence write fails, Jido stops the
provisional runtime roots and applies the normal write-authority rule. An
indeterminate initial write can have created the Record, so the caller must use
explicit activation to discover it.

On activation or thaw:

```text
build Agent Ref
  -> MyApp.Jido.load_agent/1
  -> validate Record, Commit, and checkpoint
  -> require the saved Agent definition revision to match the current module
  -> reject a hibernated or deleted Record unless the operation permits it
  -> restore Agent
  -> start Plugin runtimes from committed Plugin state and wait for readiness
  -> publish the Agent as ready
  -> accept Signals
```

On Commit:

```text
candidate Agent
  -> build Agent Commit
  -> build the next persistence Record
  -> MyApp.Jido.persist_agent/1
  -> swap live Agent
  -> reply to caller
  -> dispatch the transient Directive batch
  -> accept the next Signal when the Turn settles
```

Jido also calls `persist_agent/1` when it changes durable lifecycle status.
A status write can change the storage version without an Agent state change.
Explicit work completion is a new Signal and Agent commit. It advances the
Agent state version and preserves other pending work. A Plugin can resume
pending work while the Agent accepts other Signals.

A failed pre-commit write does not change live Agent state and starts no new
Directive. Jido does not claim that the prior Record remains authoritative. A
conflict proves that another Record is current. An indeterminate result means
that the attempted Record can be current.

After any `persist_agent/1` error, the Server rejects further admission and
stops with `{:shutdown, :lost_write_authority}`. This controlled shutdown does
not use the Agent Pool's automatic abnormal-restart path. A later explicit
activation loads and validates the current Record before it publishes the Agent
as ready.

## Delete and purge

Normal Agent deletion is a compare-and-swap lifecycle update:

```elixir
%Jido.Persistence.Record{record | status: :deleted}
```

The tombstone prevents an old process from deleting or restoring a newer
Agent record. The core Agent lifecycle does not call a blind storage delete.

Physical tombstone removal is a provider maintenance operation. Its retention,
authorization, and conditional delete rules are outside Jido core.

The instance facade exposes logical deletion:

```elixir
ref = MyApp.Jido.agent_ref("order-123", partition: nil)
:ok = MyApp.Jido.delete_agent(ref)
```

## Existing adapters

The adapter option remains a shorthand:

```elixir
defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/primary",
    persistence: {Jido.Persistence.File, path: "var/jido"}
end
```

`use Jido` supplies the two callback implementations for this form. An
application chooses either the adapter shorthand or custom callbacks. It does
not combine both forms.

All v3 adapters must provide compare-and-swap behavior. The current blind byte
`put` contract is not a conforming v3 durable adapter.

## Failure rules

- `{:error, :not_found}` permits a new Agent only for an explicit create
  operation.
- A required restore fails when no Record exists.
- Another load error fails activation.
- A missing or changed Agent definition revision fails creation or activation.
- A static Agent definition mismatch fails creation even when the numeric
  revision matches.
- Only `{:ok, record}` lets the current Agent Server continue.
- A conflict means that the current Server lost write authority, even though
  the attempted write did not overwrite storage.
- An indeterminate result means that the current Server lost write authority
  because the attempted write can have succeeded.
- A persistence timeout has the same indeterminate meaning and removes write
  authority.
- Any other persistence callback error also stops the current Server. Core does
  not require the Server to decide whether the provider started a write.
- The controlled `:lost_write_authority` shutdown requires a later activation
  to load the authoritative Record.
- Jido converts callback exceptions and invalid returns to defined Splode
  errors.

There are no `before_*` or `after_*` persistence hooks. Use telemetry for
observation. Persistence has one load boundary and one compare-and-swap write
boundary.

Future recovery, ownership, and storage provider ideas are proposed in
[Runtime extension boundaries](runtime-extension-boundaries.md). They do not
change this core persistence contract.
