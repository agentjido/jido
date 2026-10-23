# Checkpoints and Upgrades

Each durable revision stores a portable snapshot of the complete Agent: its
state, schema, routes, topology, and Plugins, plus a fingerprint of every code
module those parts reference. Restore rebuilds the Agent from that snapshot,
not from your current source. This guide shows how snapshots are built, how
to control their state format, and how to move saved data to a new shape with
an explicit upgrade Action.

```elixir
agent = MyApp.Wallet.instantiate!(id: "wallet-1", state: %{balance: 12})

{:ok, snapshot} = Jido.Persistence.snapshot(agent)

snapshot.format          # => 1
snapshot.state_format    # => :default
snapshot.agent.vsn       # => 1
snapshot.agent.state     # => %{balance: 12}
Map.keys(snapshot.references)
# => [MyApp.Deposit]

{:ok, restored} = Jido.Persistence.restore(snapshot)
restored == agent        # => true
```

The examples use this wallet:

```elixir
defmodule MyApp.Deposit do
  use Jido.Action, name: "deposit", schema: Zoi.object(%{amount: Zoi.integer()}), output_schema: Zoi.map()

  @impl true
  def run(%{amount: amount}, %{agent_state: state}),
    do: {:ok, %{state | balance: state.balance + amount}}
end

defmodule MyApp.Wallet do
  use Jido.Agent, name: "wallet", vsn: 1

  state do
    schema(Zoi.object(%{balance: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/wallet")
    route "wallet.deposit", MyApp.Deposit, as: :deposit do
      state from: output()
    end
  end
end
```

## The Snapshot

`Jido.Persistence.snapshot/2` builds the same value the Server saves. It
doesn't write storage. A snapshot is a map with exactly four keys:

| Key | Value |
| --- | --- |
| `format` | `1`, the snapshot format. |
| `agent` | The complete `%Jido.Agent{}`, with nested definitions frozen as data. |
| `references` | Each referenced module mapped to its 16-byte `module_info(:md5)`. |
| `state_format` | `:default`, or `:custom` when the Agent defines `checkpoint/2`. |

References include route Action and Flow modules, Flow call targets, Plugin
providers and their runtime modules, schema refinement modules, nested Agent
definitions, and the Agent module itself for a custom checkpoint.

Every value must be portable: no pids, refs, ports, or functions. A pid in
state fails:

```elixir
Jido.Persistence.snapshot(%{agent | state: %{balance: 1, owner: self()}})
# => {:error, %Jido.Agent.Error{code: :non_portable_term,
#      message: "Snapshot contains a non-portable value",
#      path: [:snapshot, :agent, :state, :owner]}}
```

## Live or Portable

`Jido.AgentServer.snapshot/2` is a different call. It reads the live Server:

```elixir
Jido.AgentServer.snapshot(wallet)
# => %{agent: %Jido.Agent{...}, state_version: 0}
```

| | `Jido.AgentServer.snapshot/2` | `Jido.Persistence.snapshot/2` |
| --- | --- | --- |
| Input | A running Server | An Agent value |
| Returns | The committed Agent and its revision, read together | A portable snapshot map |
| Checks portability | No | Yes |
| Fingerprints code | No | Yes |
| Use for | Reading a consistent Agent and revision | Storing, copying, or upgrading |

## Custom Checkpoints

Define `checkpoint/2` and `restore/2` on the Agent to save your own payload
instead of the full state. Use it to drop caches or to store a compact shape:

```elixir
defmodule MyApp.Session do
  use Jido.Agent, name: "session"

  state do
    schema(
      Zoi.object(%{
        user: Zoi.string() |> Zoi.default(""),
        cache: Zoi.map() |> Zoi.default(%{})
      })
    )
  end

  @impl true
  def checkpoint(agent, _context), do: {:ok, %{id: agent.id, user: agent.state.user}}

  @impl true
  def restore(%{id: id, user: user}, _context), do: instantiate(id: id, state: %{user: user})
end

agent = MyApp.Session.instantiate!(id: "s-1", state: %{user: "ada", cache: %{"k" => 1}})
{:ok, snapshot} = Jido.Persistence.snapshot(agent)

{snapshot.state_format, snapshot.agent.state, Map.keys(snapshot.references)}
# => {:custom, %{id: "s-1", user: "ada"}, [MyApp.Session]}

{:ok, restored} = Jido.Persistence.restore(snapshot)
restored.state
# => %{user: "ada", cache: %{}}
```

The rules:

- `checkpoint/2` returns `{:ok, map}` or `{:error, reason}`. The map must be
  portable.
- `restore/2` receives the payload and the caller context. The context
  doesn't include the Agent ID, so store the ID in the payload.
- `restore/2` must return an Agent with the saved ID. Another ID fails with
  `:invalid_snapshot_state` and `"Custom restore must retain the saved
  identity"`.
- The Agent module joins the references, so changing its code changes the
  fingerprint.

## Plugin State

On the default path, each Plugin with `dump/3` converts its owned field when
the snapshot is built, and `load/3` converts it back on restore. A custom
Agent checkpoint skips Plugin conversion; your `checkpoint/2` owns the whole
payload. [Plugin Persistence](plugin-persistence-and-live-changes.md) covers
`dump/3`, `load/3`, and Plugin `vsn`.

## Restore Checks

Restore validates the stored value before it runs any conversion code:

1. The record `vsn` matches the snapshot Agent's `vsn`.
2. The snapshot has the four keys, format `1`, and only portable values.
3. Every module the saved definition references is in `references`.
4. Each referenced module is loaded, and its md5 equals the saved one.
5. State converts back (`load/3` or `restore/2`) and the Agent validates.

A changed fingerprint fails at step 4:

```elixir
{:error, %Jido.Agent.Error{
  code: :changed_reference,
  message: "Snapshot code changed; use an explicit upgrade Action",
  details: %{module: MyApp.Deposit}
}}
```

A missing module fails with `:unavailable_reference` and `"Snapshot code is
unavailable"`. On a Server started with `persistence_mode: :restore`, both
make `await_ready/2` exit with `{:shutdown, %Jido.Agent.Error{code:
:changed_reference, ...}}`.

> #### Recompiling changes the fingerprint {: .warning}
>
> The md5 covers the compiled module. Any change to a referenced Action,
> Flow, Plugin, or schema refinement module blocks restore of every record
> saved with the old code. Jido has no public call that loads that stored
> snapshot for upgrade. Upgrade live Agents before you deploy the changed
> module, or add a new module and route to it instead of editing the old one.

## No Implicit Migration

Restore uses the saved definition. Deploying new routes or a new schema
doesn't change restored Agents: a `vsn: 1` record restores with its `vsn: 1`
schema and routes, as long as its referenced code is unchanged. Jido never
reshapes saved data by itself. You move it with an upgrade Action.

## Upgrade Actions

An upgrade Action receives `%{snapshot: snapshot}` and returns
`{:ok, %{snapshot: new_snapshot}}`. This one moves `balance` in dollars to
`balance_cents`, and adopts the current definition's schema and routes:

```elixir
defmodule MyApp.WalletV1ToV2 do
  use Jido.Action, name: "wallet_v1_to_v2", output_schema: Zoi.map()

  def run(%{snapshot: %{agent: %{vsn: 1, state: %{balance: balance}}} = snapshot}, _context) do
    current = MyApp.Wallet.definition()

    agent = %{
      snapshot.agent
      | vsn: current.vsn,
        schema: current.schema,
        routes: current.routes,
        state: %{balance_cents: balance * 100}
    }

    with {:ok, upgraded} <- Jido.Persistence.snapshot(agent),
         do: {:ok, %{snapshot: upgraded}}
  end

  def run(%{snapshot: %{agent: %{vsn: 2}} = snapshot}, _context),
    do: {:ok, %{snapshot: snapshot}}
end
```

The rules:

- Return exactly one `snapshot` key and no Directives. Anything else fails
  with `:invalid_upgrade_result` and `"Upgrade must return one snapshot and
  no Directives"`.
- Keep the Agent `id` and `module`. A change fails with `:upgrade_identity`.
- Build the result with `Jido.Persistence.snapshot/2`. It refreshes the
  fingerprints for the new code.
- Replace routes when the state shape changes. A `vsn: 1` route that reads
  `state.balance` crashes with `key :balance not found` on the new state.
- Match on `vsn` and return the snapshot unchanged when it's already
  current, so a repeated upgrade is safe.

### Upgrade a Live Agent

`Jido.AgentServer.upgrade/3` runs the Action as one serial Turn and commits
the result with the next revision:

```elixir
Jido.AgentServer.snapshot(wallet).state_version
# => 0

{:ok, upgraded, []} = Jido.AgentServer.upgrade(wallet, MyApp.WalletV1ToV2)
{upgraded.vsn, upgraded.state}
# => {2, %{balance_cents: 1200}}

Jido.AgentServer.snapshot(wallet).state_version
# => 1
```

The upgraded Agent then runs its new routes. Running the upgrade again on a
`vsn: 2` Agent leaves the state unchanged but still commits a new revision.

### Upgrade a Snapshot

`Jido.Persistence.upgrade/3` runs the same Action on a snapshot value and
returns the restored Agent. It checks the envelope before it runs the
Action, but resolves code references only after. So it accepts a snapshot
whose fingerprints no longer match:

```elixir
{:ok, upgraded} = Jido.Persistence.upgrade(snapshot, MyApp.WalletV1ToV2)
{upgraded.vsn, upgraded.state}
# => {2, %{balance_cents: 1200}}
```

The source snapshot doesn't change, and nothing is written. Save the result
with `Jido.Persistence.save_agent/3` and an `expected_revision:`, or start a
Server from it with `start_agent/2`. See
[Revisions and Conflicts](durable-revisions-and-conflicts.md) for the
revision rules.

## Next

- [Recovery Limits](recovery-and-effect-limits.md) – what each failure
  restores, and what it doesn't.
- [Storage Model](persistence-storage-model.md) – the record around the
  snapshot.
- [Durable Turns and Flows](durable-turns-and-flows.livemd) – pending Flow
  work must stay compatible across an upgrade.
