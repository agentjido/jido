# Revisions and Conflicts

This guide gives the exact rules for a durable record's revision, what each write result means, and how to respond when a write fails. Use it when you call `Jido.Persistence.save_agent/3` directly or when you handle a failed durable write.

## Read a revision

A revision is a non-negative integer stored with each record. On a live server, `Jido.AgentServer.snapshot/2` returns the committed Agent and its revision from the same server event. Without a server, use `Jido.Persistence.load_agent_with_revision/4`.

```elixir
defmodule RevisionsGuide.Ticket do
  use Jido.Agent, name: "revisions_ticket"

  state do
    schema Jido.Joi.object(%{status: Jido.Joi.string() |> Jido.Joi.default("open")})
  end

  routes do
    signal_source "/guides/revisions"

    route "ticket.close" do
      action _input, schema: Jido.Joi.object(%{}) do
        {:ok, %{status: "closed"}}
      end
    end
  end
end

alias Jido.Persistence
alias RevisionsGuide.Ticket

store = {Jido.Persistence.ETS, table: :revisions_guide}
identity = [namespace: "guides/revisions"]
ticket = Ticket.instantiate!(id: "ticket-1")

:ok = Persistence.save_agent(store, ticket, identity)
{:ok, _agent, 0} = Persistence.load_agent_with_revision(store, Ticket, "ticket-1", identity)
```

A direct save with a raw adapter needs `:namespace`. When you pass an instance name as the source, the save uses that instance's namespace and adapter.

## Know the write rules

`Jido.Persistence.save_agent/3` reads the record, checks these rules, and then writes with compare-and-swap. `:revision` is the proposed revision and defaults to zero. `:expected_revision` is the revision you read.

| Stored record | Proposed write | Result |
| --- | --- | --- |
| None | Any revision, no `:expected_revision` | `:ok` |
| None | `expected_revision: 0` | `:ok` |
| None | `expected_revision` above zero | `{:error, :conflict}` |
| Active at revision N | Same revision, identical record | `:ok`, a repeat of the same write |
| Active at revision N | Same revision, different record | `{:error, :conflict}` |
| Active at revision N | Lower revision | `{:error, :conflict}` |
| Active at revision N | Higher revision, no `:expected_revision` | `:ok` |
| Active at revision N | `expected_revision` other than N | `{:error, :conflict}`, even for a higher revision |
| Active at revision N | Higher revision, `expected_revision: N` | `:ok` |
| Tombstone | Any | `{:error, :conflict}` |

The next code checks the active-record rows against the record saved above.

```elixir
alias Jido.Persistence
alias RevisionsGuide.Ticket

closed = %{ticket | state: %{status: "closed"}}

:ok = Persistence.save_agent(store, ticket, identity)
{:error, :conflict} = Persistence.save_agent(store, closed, identity)

:ok = Persistence.save_agent(store, closed, identity ++ [revision: 2])
{:error, :conflict} = Persistence.save_agent(store, ticket, identity ++ [revision: 1])

{:error, :conflict} =
  Persistence.save_agent(store, ticket, identity ++ [revision: 3, expected_revision: 1])

:ok = Persistence.save_agent(store, ticket, identity ++ [revision: 3, expected_revision: 2])
```

Without `:expected_revision`, a direct save overwrites any older revision, including one you never read. Always pass it when your write depends on what you read.

## Update a record from a script

Read the record with its revision, compute the change, and write with both options. On a conflict, read again and decide whether the change still applies. Do not retry the same value.

```elixir
alias Jido.Persistence
alias RevisionsGuide.Ticket

{:ok, current, revision} = Persistence.load_agent_with_revision(store, Ticket, "ticket-1", identity)

:ok =
  Persistence.save_agent(store, %{current | state: %{status: "escalated"}},
    namespace: "guides/revisions",
    revision: revision + 1,
    expected_revision: revision,
    reason: :support_console
  )

{:ok, %{state: %{status: "escalated"}}, 4} =
  Persistence.load_agent_with_revision(store, Ticket, "ticket-1", identity)
```

The accepted options are `:instance`, `:namespace`, `:partition`, `:reason`, `:revision`, and `:expected_revision`. Unknown or duplicate options return an error before any adapter work.

Do this only for an Agent with no running server. The next section shows why.

## Let the server own its revision

An AgentServer writes each commit with its current revision as `:expected_revision`. It is the only writer of that record while it runs. If something else changes the record, the server's next commit conflicts, the caller gets an error, and the activation stops. It stops because its live state is stale. OTP does not restart it, so nothing keeps accepting work on old state.

```elixir
alias Jido.AgentServer, as: Server
alias Jido.Persistence
alias RevisionsGuide.Ticket

{:ok, _} =
  Jido.start_link(
    name: RevisionsGuide.Jido,
    namespace: "guides/revisions-live",
    persistence: {Jido.Persistence.ETS, table: :revisions_guide_live}
  )

{:ok, server} = Jido.start_agent(RevisionsGuide.Jido, Ticket, id: "ticket-2", persistence: :inherit)
:ok = Server.await_ready(server)
monitor = Process.monitor(server)

# Another writer commits behind the server.
:ok =
  Persistence.save_agent(RevisionsGuide.Jido, Server.snapshot(server).agent,
    revision: 1,
    expected_revision: 0
  )

close = Jido.Signal.new!("ticket.close", %{}, source: "/guides/revisions")
{:error, %Jido.Error.ExecutionError{details: %{reason: :conflict}}} = Server.call(server, close)

receive do
  {:DOWN, ^monitor, :process, ^server, _reason} -> :ok
end

nil = Jido.whereis_agent(RevisionsGuide.Jido, "ticket-2")

{:ok, %{state: %{status: "open"}}, 1} =
  Persistence.load_agent_with_revision(RevisionsGuide.Jido, Ticket, "ticket-2")
```

To continue, activate the Agent again. The new activation reads the winning record.

Compare-and-swap protects the record, but it is not a writer lease. Two activations on separate nodes can both run against a shared store. The first commit wins, and the other activation stops at its next write, so it can run an Action before it learns it lost. See [Recovery Limits](recovery-and-effect-limits.md).

## Understand write results

`Jido.Persistence.Store.compare_and_swap/4` reduces every adapter reply to one of these results:

| Result | Meaning | What to do |
| --- | --- | --- |
| `:ok` | The write happened | Continue |
| `{:error, :conflict}` | No write happened, because the record changed | Read again and decide |
| `{:error, {:rejected, reason}}` | The adapter finished a documented check and no write started | Fix the cause, for example a read-only store |
| `{:error, :indeterminate}` or `{:error, {:indeterminate, reason}}` | The write may or may not have happened | Do not retry blindly. Read the record first |

Any other adapter error, an invalid reply, a raised exception, or an exit is reported as indeterminate, because Jido cannot prove that nothing was written. A custom adapter must return the exact forms above to claim a conflict or a rejection. [Custom Adapters](../storage/custom-persistence-adapter.md) has the contract.

## Know how the server responds

The server treats a required Turn write and a hibernation save differently.

**Turn writes** include Flow acceptance, step checkpoints, terminal receipts, and commits. Any failure stops the activation without a success reply, whatever the reason. Hooks and post-commit effects do not run. If the result is uncertain and the write did land, the next activation restores that revision without replaying its effects.

`persistence_timeout:` bounds each required write and defaults to 5,000 ms. A write that finishes after this deadline counts as indeterminate, even if its reply arrives before the timer fires.

**A hibernation save** reports its failure to the caller, as `{:error, %{reason: reason, resumable?: boolean}}` from `Jido.AgentServer.hibernate/2`.

| `resumable?` | Reasons | Server state | Next step |
| --- | --- | --- | --- |
| `true` | A known no-write failure such as `{:rejected, :disk_full}` | Live, with prior admission restored | Fix the cause and retry |
| `false` | `:conflict` or an indeterminate result | Live for reads, admission `:blocked` | `Jido.AgentServer.resume/2` returns `{:error, :unsafe_resume}`. Stop the server and activate again |

The block survives a restart of the same activation. Only a new activation, which reads the stored record, clears it. An idle-policy hibernation that fails closes admission and does not retry on its own.

## Next steps

- [Deletion and Tombstones](deletion-and-tombstones.md) explains the tombstone row.
- [Checkpoints and Upgrades](checkpoints-and-data-upgrades.md) writes a new revision with a data change.
- [Durability Model](durability-model.md) shows how many revisions each Turn writes.
