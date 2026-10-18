# Portable State and Checkpoints

Live Agent state must match its schema and Agent invariants. This rule applies
to creation, transitions, commands, live commits, and Plugin-owned fields.
A field with `Zoi.any()` can contain local values, including a PID or a three-bit
value such as `<<5::size(3)>>`. No persistence adapter is required.

A durable checkpoint has a separate rule: its complete stored representation
must contain supported portable terms. A valid live Agent can therefore fail
to checkpoint unless application conversion supplies a portable representation.

A checkpoint is a portable map that represents one Agent value. It is not a
copy of the `AgentServer` process. Mailboxes, process identifiers,
monitors, tasks, and Plugin runtime processes do not enter the snapshot.
A persistent Flow separately saves portable caller context in its Turn receipt.

## The default checkpoint

Use `Jido.Persistence.snapshot/2` to capture the complete Agent definition and
state. Nested Agent definitions and code fingerprints are part of the snapshot.
Restore uses the saved definition. It does not rebuild static fields from the
current Agent module.

```elixir
{:ok, snapshot} = Jido.Persistence.snapshot(agent, context: %{reason: :manual})
{:ok, restored} = Jido.Persistence.restore(snapshot, context: %{reason: :restore})
```

The snapshot format is 1. It contains `:agent`, `:references`, and
`:state_format`. Persistence stores this snapshot in an outer format-4 record
with a stable namespaced identity and revision. See
[Hibernate and Thaw](compare-and-swap-hibernate-and-thaw.md).

## Persistence Plugin conversion

A Plugin can implement `dump/3` and `load/3` when its owned state needs a
durable representation that differs from its live Agent value. For the default
Agent checkpoint, Persistence calls these callbacks with only:

- the state value declared by the Plugin's `state_spec/1`;
- a context with package version, record format, direction, and reason;
- the static options mapped to Persistence callbacks.

The callbacks cannot read the adapter, record key, complete Agent state, process,
or commit result. Conversion runs before the final checkpoint portability
check. Dump output must be portable. Load receives validated stored data and
can reconstruct local values. Its output must match the Plugin's owned field
schema and the complete Agent schema; it need not be portable.
Jido validates the loaded value without adding defaults or changing values.
A missing required field is an error. A valid `nil` value remains `nil`.

`Jido.Persistence.snapshot/2` and `Jido.Persistence.restore/2` apply Plugin
conversion on the default state path.

Each callback must return `{:ok, value}` or `{:error, reason}`. A raised
callback, an invalid return, non-portable dump output, or invalid loaded state
returns an error to the Persistence caller. A dump failure prevents the record
write. A load failure prevents Agent restore. Keep every Plugin-owned field in
the checkpoint; a missing field is an error. Authors should handle the error
and fix the callback or record instead of assuming a partial Agent exists.

A snapshot retains the complete saved definition, including data-defined
fields and nested topology. The complete stored representation must be portable.
Code fingerprints detect changes to the implementations that it requires.

## Portable terms only

Checkpoint data must remain valid outside the current process and BEAM node.
These values must not remain in the final stored representation:

- PIDs
- ports
- references
- functions
- improper lists
- bitstrings that are not byte-aligned
- runtime handles that are valid only on one node

The portable-term check accepts atoms, but that does not make every atom safe
across BEAM nodes. Persistence decodes a stored record with
`binary_to_term(bytes, [:safe])`. A fresh BEAM rejects an atom name that it has
not already loaded. The two-BEAM
[checkpoint test](../test/jido/persistence/cross_beam_atom_test.exs) saves a
new atom on one node and gets `:invalid_persistence_record` on the other; the
same value as a string loads. Jido loads the caller-supplied Agent module
before it decodes a record. The application must load other trusted modules
that define fixed atoms in saved state. Jido does not select modules from
stored bytes. Use stable strings for data that can introduce new names. A
custom Agent checkpoint or Plugin Persistence callbacks can convert that data at
its state boundary. Do not depend on unrestricted atom portability.

Use stable identifiers and portable configuration. Rebuild runtime resources
in a Plugin runtime or in application supervision after restore.

## Custom checkpoint formats

Override `checkpoint/2` and `restore/2` when you need a durable payload that is
different from the default Agent representation. The callbacks own an opaque
plain-map payload. Jido first validates live state, then calls `checkpoint/2`,
then checks its output for portability. On restore, it validates the stored
payload before the callback and validates the reconstructed Agent afterward.

```elixir
# The Agent schema declares a :bits field with Zoi.any().
def checkpoint(agent, _context) do
  bits = for <<bit::1 <- agent.state.bits>>, do: bit
  {:ok, %{id: agent.id, bits: bits}}
end

def restore(%{id: id, bits: bits}, _context) do
  value = for bit <- bits, into: <<>>, do: <<bit::1>>
  new(id: id, state: %{bits: value})
end
```

The optional callbacks `c:Jido.Agent.checkpoint/2` and
`c:Jido.Agent.restore/2` convert the state payload. The snapshot keeps the
saved definition and marks the payload with `state_format: :custom`.
Restore passes the payload to the callback and uses its returned state.
The returned Agent must retain the saved ID. The saved definition stays
authoritative.

Custom callbacks bypass Plugin state conversion. The application owns the
complete custom state payload. Use `Jido.Persistence.upgrade/3` with an upgrade
Action when saved data or code references need an explicit change. Test the
upgraded snapshot through restore before use.

## Live values and local restart

Without durable persistence, the instance runtime checkpoint copies the
complete Agent. A local abnormal restart restores the same terms and validates
the live schema. A bitstring keeps its value. A PID, port, or reference keeps
its identity but can refer to a resource that has stopped. Copying a monitor
reference does not install a monitor in the replacement Server. Copying a port
does not transfer its connected process. Functions retain local code references;
they are not a durable code-version or resource recovery contract.

Keep resource start, stop, ownership, and reconnection in a Plugin runtime or
application supervision. A schema check does not prove that a resource is live.
Clean stop removes the runtime checkpoint. Instance or BEAM loss removes it too.
See [Runtime Coordination State](runtime-coordination-state.md).

## Move from the earlier V3 live-state rule

Earlier V3 code required all live state to be portable. Code that used portable
values still works. Tests that expected `:non_portable_term` at creation or
command execution must now check the checkpoint boundary. Use a narrower
schema when a local value is invalid for the application.

Before enabling persistence for local state, add custom Agent conversion or
Plugin Persistence callbacks, and test save and restore together. Default
checkpoints remain strict and do not remove fields. The saved formats and
version numbers do not change. A required checkpoint or write failure prevents
the candidate commit and directive dispatch; it cannot undo earlier Action I/O.

## Context is not state

The callback context describes why and where the checkpoint operation occurs.
It is not caller execution context. The standard fields are:

- `:instance` — the Jido instance name
- `:partition` — the registry partition, when used
- `:revision` — the committed Agent state version
- `:reason` — such as `:manual` or `:restore`

If a request value must survive a restart, put it in validated Agent state as
part of the Turn. Do not depend on a caller PID, trace process, or task-local
value to appear after restore.

## Checkpoints and codecs

Agent builders and codecs move authored definitions across trusted program
boundaries. Persistence checkpoints move Agent instances across time. These
formats have different purposes. Do not use an Agent definition codec as a
replacement for a durable state format.

Next, use [Persistence Adapters](persistence-adapters.html) to store a
checkpoint and load it as an Agent value.
