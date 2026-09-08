# Portable State and Checkpoints

An Agent value is useful when you can move it between direct code, a live actor,
and durable storage without a change to its meaning. Jido uses checkpoints for
this boundary.

A checkpoint is a portable map that represents one Agent value. It is not a
copy of the `AgentServer` process. Mailboxes, caller data, process identifiers,
monitors, tasks, and Plugin runtime processes do not enter the record.

## The default checkpoint

Agents created with `use Jido.Agent` have default `checkpoint/2` and
`restore/2` callbacks. The default checkpoint contains the Agent identity and
its complete validated state. Complete state includes the domain state and each
Plugin state slice.

```elixir
{:ok, checkpoint} = MyAgent.checkpoint(agent, %{
  instance: MyApp.Jido,
  partition: nil,
  revision: 7,
  reason: :manual
})

{:ok, restored} = MyAgent.restore(checkpoint, %{
  instance: MyApp.Jido,
  partition: nil,
  revision: 7,
  reason: :restore
})
```

Application code usually uses `Jido.Persistence` instead of these callbacks.
Persistence adds the record format, storage identity, revision, and adapter
boundary.

## Portable terms only

Checkpoint data must remain valid outside the current process and BEAM node.
Do not put these values in persistent Agent or Plugin state:

- PIDs
- ports
- references
- functions
- runtime handles that are valid only on one node

Use stable identifiers and portable configuration. Rebuild runtime resources
in a Plugin runtime or in application supervision after restore.

## Custom checkpoint formats

Override `checkpoint/2` and `restore/2` when you need a durable format that is
different from the default Agent representation. Keep the format explicit and
versioned.

```elixir
def checkpoint(agent, _context) do
  {:ok, %{version: 1, id: agent.id, state: agent.state}}
end

def restore(%{version: 1, id: id, state: state}, _context) do
  new(id: id, state: state)
end
```

Restore must return an Agent with the module and ID that the persistence record
names. Jido rejects a checkpoint that changes this identity.

Treat a format change as a data migration. Accept old versions for as long as
stored records can contain them. Return a clear error for a version that the
current code cannot read.

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
