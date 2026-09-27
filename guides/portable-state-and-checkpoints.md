# Portable State and Checkpoints

Live Agent state must match its schema and Agent invariants. This rule applies
to creation, transitions, commands, live commits, and Plugin-owned fields.
A field with `Zoi.any()` can contain local values, including a PID or a three-bit
value such as `<<5::size(3)>>`. No persistence adapter is required.

A durable checkpoint has a separate rule: its complete stored representation
must contain supported portable terms. A valid live Agent can therefore fail
to checkpoint unless application conversion supplies a portable representation.

A checkpoint is a portable map that represents one Agent value. It is not a
copy of the `AgentServer` process. Mailboxes, caller data, process identifiers,
monitors, tasks, and Plugin runtime processes do not enter the record.

## The default checkpoint

The public Agent checkpoint boundary uses core default behavior when an Agent
module does not define `checkpoint/2` or `restore/2`. The default checkpoint
contains the Agent identity and its complete validated state. The one state map
includes domain fields and each Plugin-owned top-level field. A generated Agent
module also owns a positive `vsn`. Jido stores it in the version-2 checkpoint
and rejects a module or `vsn` mismatch before it accepts saved state.

```elixir
{:ok, checkpoint} = Jido.Agent.checkpoint(agent, %{
  instance: MyApp.Jido,
  partition: nil,
  revision: 7,
  reason: :manual
})

{:ok, restored} = Jido.Agent.restore(MyAgent, checkpoint, %{
  instance: MyApp.Jido,
  partition: nil,
  revision: 7,
  reason: :restore
})
```

Application code usually uses `Jido.Persistence` instead of these callbacks.
Persistence adds the active-or-tombstone record format, storage identity,
Agent `vsn`, revision, and adapter boundary. All durable Agents use a stable
namespaced Ref key and outer format 3. Earlier outer formats require an
[offline migration](compare-and-swap-hibernate-and-thaw.md#move-records-from-an-earlier-v3-beta).
The nested checkpoint format remains version 2.

## Persistence Plugin conversion

A Plugin package can select a `Jido.Persistence.Plugin` facet when its owned
state needs a durable representation that differs from its live Agent value.
For the default Agent checkpoint, Persistence calls this facet with only:

- the state value owned by the paired `Jido.Agent.Plugin` facet;
- a context with package version, record format, direction, and reason;
- the static options mapped to the Persistence facet.

The facet cannot read the adapter, record key, complete Agent state, process,
or commit result. Conversion runs before the final checkpoint portability
check. Dump output must be portable. Load receives validated stored data and
can reconstruct local values. Its output must match the paired Agent-facet
state schema and the complete Agent schema; it need not be portable.

Direct `Jido.Agent.checkpoint/2` and `Jido.Agent.restore/3` do not run Plugin
persistence conversion. Use `Jido.Persistence` for this conversion.

Each callback must return `{:ok, value}` or `{:error, reason}`. A raised
callback, an invalid return, non-portable dump output, or invalid loaded state
returns an error to the Persistence caller. A dump failure prevents the record
write. A load failure prevents Agent restore. Keep every Plugin-owned field in
the checkpoint; a missing field is an error. Authors should handle the error
and fix the callback or record instead of assuming a partial Agent exists.

Direct and behavior-only definitions use the version-2 checkpoint format with
an embedded definition. This includes an explicitly unversioned direct
definition that uses a generated module as its behavior but owns changed static
data. Direct definitions can contain runtime authoring data in memory. The
default checkpoint can store them only when the complete map is portable. Use
an exact generated Agent definition or a custom durable format for other
definitions.

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
custom Agent checkpoint or Plugin Persistence facet can convert that data at
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

The public `Jido.Agent.checkpoint/2` function wraps a new custom payload in a
core-owned version-2 envelope. The envelope contains `agent_module`, `vsn`, and
the opaque `payload`. `Jido.Agent.restore/3` checks the module and `vsn`, then
passes only the payload to the callback. Raw custom payload maps are not
checkpoint envelopes and restore rejects them.

Persistence does not apply Plugin owned-state conversion to a complete custom
checkpoint. The custom callback owns the complete payload and its migration.

Restore must return an Agent with the module and ID that the persistence record
names. Jido rejects a checkpoint that changes this identity.

Treat a format change as a data migration. Convert version-1 Agent checkpoints
before you use the V3 code. The current Agent boundary reads and writes only
version 2.

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

Before enabling persistence for local state, add custom Agent conversion or a
Plugin Persistence facet, and test save and restore together. Default
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
