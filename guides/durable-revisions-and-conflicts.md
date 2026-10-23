# Revisions and Conflicts

Every durable Agent record has a revision number. The Agent Server writes
each commit with compare-and-swap against the revision it last saved. When
another writer changes the record first, the write fails with a conflict and
the Server stops. This guide shows the revision rules, the conflict and
uncertain-write outcomes, and why a revision check isn't a writer lease.

```elixir
{:ok, counter} =
  MyApp.Jido.start_agent(MyApp.Counter, id: "counter-1", persistence: :inherit)

:ok = Jido.AgentServer.await_ready(counter)
Jido.AgentServer.status(counter).state_version
# => 0

signal = MyApp.Counter.add_signal!(%{amount: 2})
{:ok, _agent, []} = Jido.AgentServer.call(counter, signal)

Jido.Persistence.load_agent_with_revision(MyApp.Jido, MyApp.Counter, "counter-1")
# => {:ok, %Jido.Agent{state: %{count: 2}, ...}, 1}
```

The examples use this counter and an instance with the ETS adapter:

```elixir
defmodule MyApp.Add do
  use Jido.Action, name: "add", schema: Zoi.object(%{amount: Zoi.integer()}), output_schema: Zoi.map()

  @impl true
  def run(%{amount: amount}, %{agent_state: state}),
    do: {:ok, %{state | count: state.count + amount}}
end

defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/counter")
    route "counter.add", MyApp.Add, as: :add, defaults: %{amount: 1} do
      state from: output()
    end
  end
end

defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my_app",
    persistence: {Jido.Persistence.ETS, table: :my_app_agents}
end
```

## Revision Numbers

The stored revision is the Server's `state_version`:

| Event | Stored revision |
| --- | --- |
| New persistent activation, before ready | 0 |
| Successful ordinary Turn | previous + 1, even if state is identical |
| Durable Flow Turn | acceptance and completion writes; see [Durable Turns and Flows](durable-turns-and-flows.livemd) |
| Failed Turn before commit | unchanged |
| Failure in hooks or Directives | unchanged; the commit stands |

State and the current topology share one revision. Child Agents have their
own records and revisions. Jido doesn't save an Agent family atomically.

## Compare-and-Swap

`Jido.Persistence.save_agent/3` takes `:revision` (default `0`) and an
optional `:expected_revision`. Results against a record stored at revision 1:

```elixir
Jido.Persistence.save_agent(MyApp.Jido, changed, revision: 1)
# => {:error, :conflict}    changed state needs a greater revision

Jido.Persistence.save_agent(MyApp.Jido, same, revision: 1)
# => :ok                    the identical record is accepted again

Jido.Persistence.save_agent(MyApp.Jido, same, revision: 0)
# => {:error, :conflict}    revisions never decrease

Jido.Persistence.save_agent(MyApp.Jido, changed, revision: 3, expected_revision: 0)
# => {:error, :conflict}    the stored revision isn't 0

Jido.Persistence.save_agent(MyApp.Jido, changed, revision: 2, expected_revision: 1)
# => :ok
```

The Agent Server always passes `expected_revision`, set to the revision it
last wrote or loaded. Use `expected_revision` on every direct write you make.
Without it, any greater revision wins.

## Write Outcomes

The persistence store classifies each write:

| Outcome | Meaning | Write happened |
| --- | --- | --- |
| `:ok` | Stored. | Yes |
| `{:error, :conflict}` | The revision check failed. | No |
| `{:error, {:rejected, reason}}` | The adapter refused before writing. | No |
| `{:error, {:indeterminate, reason}}` | Any other error, such as a timeout. | Unknown |

Don't retry an indeterminate write blindly. Load the record and compare it
with what you meant to write.

## Server on a Conflict

Write the record behind the running Server, then send a Signal:

```elixir
:ok =
  Jido.Persistence.save_agent(MyApp.Jido, %{agent | state: %{count: 50}},
    revision: 2,
    expected_revision: 1
  )

Jido.AgentServer.call(counter, signal)
# => {:error, %Jido.Error.ExecutionError{
#      message: "Required durable commit failed",
#      details: %{reason: :conflict}}}
```

On any failed or uncertain commit write, the Server:

- replies with that error and the store reason (`:conflict`,
  `{:rejected, reason}`, or `{:indeterminate, reason}`);
- runs no `after_commit/3` hooks and no Directives;
- stops the activation root with reason `:shutdown`; and
- isn't restarted. `whereis_agent/1` returns `nil`.

Storage keeps the other writer's record, `%{count: 50}` at revision 2. Start
the Agent again with `persistence_mode: :restore` to continue from it.

### Hibernate Failures

`hibernate/2` can fail the same way. The Server stays up, but blocks Turns:

```elixir
Jido.AgentServer.hibernate(counter)
# => {:error, %{reason: :conflict, resumable?: false}}

Jido.AgentServer.resume(counter)
# => {:error, :unsafe_resume}

Jido.AgentServer.call(counter, signal)
# => {:error, :quiesced}
```

`status/2` reports `admission.mode` as `:blocked`. A conflict or an
indeterminate result sets `resumable?: false`, because the Server's state may
no longer match storage. Stop the Server and restore it from storage.

## Start Modes

`persistence_mode:` selects how a new activation treats an existing record.
`start_agent/2` returns `{:ok, pid}` before storage is checked. A failure
appears at `await_ready/2` as an exit:

| Mode | Stored record | Result |
| --- | --- | --- |
| `:create` (default) | none | ready at revision 0 |
| `:create` | active or tombstone | exit `{:shutdown, :conflict}` |
| `:restore` | active | ready at the stored revision |
| `:restore` | none | exit `{:shutdown, :not_found}` |
| `:restore` | tombstone | exit `{:shutdown, :deleted}` |

`delete_agent` writes a tombstone. Loads then return `{:error, :deleted}`,
and a delayed `save_agent/3` returns `{:error, :conflict}`, so a slow writer
can't bring the record back. [Durable Activation](durable-agent-activation.livemd)
covers start, hibernate, and thaw.

## Two Activations

In one BEAM, a namespace binds to one instance. A second instance with the
same namespace fails to start with `"Jido instance namespace is already
bound"`. That check is local. Two nodes with the same namespace and a shared
store, such as PostgreSQL or Redis, can each start an activation for the same
Ref. Both Servers accept Turns. Each write checks the revision the Server last
saw:

1. A and B restore `counter-1` at revision 4.
2. A commits revision 5.
3. B tries to commit revision 5 with `expected_revision: 4` and gets
   `:conflict`. B's caller gets the error, and B stops.

This is the same path as the outside write in
[Server on a Conflict](#server-on-a-conflict). The record stays consistent,
but B's Turn already ran. Any I/O its Action did
happened, and B's caller sees a failure for work that A never saw.

## Not a Writer Lease

A revision check detects a stale write after the work is done. It doesn't
stop two activations from running at the same time. It doesn't fence an
external system, and a write that times out can still land.

To keep one writer per Agent:

- route each Agent ID to one node, such as with a consistent hash over the
  cluster, a global registry, or a partition owner;
- keep that owner check in your application, outside Jido; and
- treat `:conflict` as a sign that ownership moved, not as a retry signal.

[Durability Model](durability-model.md) lists which guarantees Jido gives
and which ones your deployment owns.

## Next

- [Checkpoints and Upgrades](checkpoints-and-data-upgrades.md) – the snapshot
  inside each revision, and how to change its shape.
- [Recovery Limits](recovery-and-effect-limits.md) – what each failure
  recovers to, and what isn't replayed.
- [Custom Adapters](custom-persistence-adapter.md) – implement
  compare-and-swap for your store.
