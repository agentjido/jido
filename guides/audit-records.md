# Audit Records

`Jido.Plugin.Audit` stores a bounded list of domain decisions in the Agent's
state. An Action returns a record next to its state change, and the record
commits in the same Turn. If the Turn fails, neither the change nor the
record is kept.

This guide builds an account Agent that records each approved and declined
withdrawal. Read [State and Directives](agent-results-and-directives.md)
first if Directives are new to you.

## The Result

After two withdrawals, the account holds its balance and the reason for each
decision:

```elixir
account.state
# => %{
#      balance: 70,
#      audit: %{
#        records: [
#          %Jido.Plugin.Audit.Record{event: :withdrawal, outcome: :approved,
#                                    metadata: %{amount: 30}, ...},
#          %Jido.Plugin.Audit.Record{event: :withdrawal, outcome: :declined,
#                                    metadata: %{amount: 500, balance: 70}, ...}
#        ]
#      }
#    }
```

## Add The Plugin

```elixir
defmodule MyApp.Withdraw do
  use Jido.Action,
    name: "withdraw",
    schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.min(1)})

  alias Jido.Plugin.Audit

  @impl true
  def run(%{amount: amount}, %{agent_state: state}) do
    if amount <= state.balance do
      {:ok, %{state | balance: state.balance - amount},
       [Audit.record(:withdrawal, :approved, metadata: %{amount: amount})]}
    else
      {:ok, state,
       [Audit.record(:withdrawal, :declined, metadata: %{amount: amount, balance: state.balance})]}
    end
  end
end

defmodule MyApp.Account do
  use Jido.Agent, name: "account"

  agent do
    schema(Zoi.object(%{balance: Zoi.integer() |> Zoi.default(100)}))
    plugin(Jido.Plugin.Audit, config: %{max_entries: 3})
  end

  routes do
    signal_source("/my_app/accounts")
    route "account.withdraw", MyApp.Withdraw, as: :withdraw
  end
end
```

The Plugin adds an `audit` field to the Agent state. Don't declare it in your
schema: the Plugin owns the field and supplies its schema.

```elixir
account = MyApp.Account.instantiate!(id: "acct-1")
account.state
# => %{balance: 100, audit: %{records: []}}
```

## Record A Decision

`Jido.Plugin.Audit.record/3` returns a Directive. The decline branch above
leaves the balance unchanged but still returns a record, so the decision is
kept even though no other state changed.

```elixir
signal = MyApp.Account.withdraw_signal!(%{amount: 30})
{:ok, account, _directives} = MyApp.Account.cmd(account, signal)

signal = MyApp.Account.withdraw_signal!(%{amount: 500})
{:ok, account, _directives} = MyApp.Account.cmd(account, signal)

{account.state.balance, Enum.map(account.state.audit.records, & &1.outcome)}
# => {70, [:approved, :declined]}
```

The Plugin's reducer runs during pure evaluation, so you can test audit
behavior with `cmd/3` and no process.

## Record Fields

| Field | Set by | Rule |
| --- | --- | --- |
| `id` | `:id` option, or a generated UUID7 | Must be a valid UUID7. |
| `at` | `:at` option, or the current Unix time in ms | Non-negative integer. |
| `event` | first argument | Any portable term, such as `:withdrawal`. |
| `outcome` | second argument | An atom. |
| `metadata` | `:metadata` option | A portable map. Default `%{}`. |

Jido validates each record before commit. An invalid record fails the whole
Turn:

| Input | Error message |
| --- | --- |
| `metadata: %{pid: self()}` | `"Audit record must contain portable data"` |
| `id: "abc"` | `"Audit record id must be a UUID7"` |

Portable data can be saved and restored with the Agent: no PIDs, references,
or functions.

## Read The Records

Records are at `agent.state.audit.records`, oldest first. On a live Agent,
read them with `plugin_state/2`:

```elixir
{:ok, %{records: records}} = Jido.AgentServer.plugin_state(server, Jido.Plugin.Audit)
```

Records are Agent state, so they persist, snapshot, and restore with the
Agent at the same revision. There is no second store.

On a live Server, each record also appears in the Turn's Directive list, and
`status/2` counts it as a completed effect. It does no work after commit: the
reducer applied it before validation.

## Ownership

Only the Plugin writes the `audit` field. An Action that edits it directly
fails its Turn, even with a valid record:

```elixir
def run(_params, %{agent_state: state}) do
  {:ok, %{state | audit: %{records: [Jido.Plugin.Audit.record(:fake, :approved)]}}}
end
# Turn fails: "Agent executable changed Plugin-owned state"
```

Records enter only through `record/3` and the reducer, so an Action can't
rewrite or delete earlier records.

## Limit The List

`max_entries` caps the list. When a commit exceeds it, the oldest records are
dropped. With `max_entries: 3`, three more withdrawals of 10 after the two
records above leave:

```elixir
{account.state.balance, Enum.map(account.state.audit.records, & &1.outcome)}
# => {40, [:approved, :approved, :approved]}
```

The declined record has been dropped.

Agent state is validated on every Turn and written on every persistent
commit, so the list's size affects every Turn. Size `max_entries` for the
questions you answer from the Agent itself, and copy older records to an
external store if you need a permanent archive.

| Option | Default | Rule |
| --- | --- | --- |
| `max_entries` | `1_000` | Positive integer. |

## Failed Turns

A failed Turn commits nothing, so it adds no record. To track failures, use
the Agent Server:

- `Jido.AgentServer.status/2` returns the last Turn summary in
  `last_outcome`.
- An `error_policy:` callback receives the error and the Turn summary after
  each failed Turn. Write it to your own store from there.

Turn summaries contain IDs, stage, status, and revisions. They don't contain
Signal data, Agent state, or raw errors.

## Limits

- Audit records only what your Actions return. It doesn't record every Turn.
- Records are protected by Plugin ownership inside Jido, not by cryptography.
  It isn't a tamper-proof ledger.
- Records leave the Agent only when you persist, snapshot, or read them.
- Old records are dropped at `max_entries`.

## Next

- [Heartbeats and Schedules](heartbeats-and-schedules.livemd): run Agents on
  a timer.
- [Stateful Plugins](write-a-stateful-plugin.livemd): build a Plugin with an
  owned field and a reducer, like Audit.
- [Plugin Persistence](plugin-persistence-and-live-changes.md): how
  Plugin-owned state is saved and restored.
