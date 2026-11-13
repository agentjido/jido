# Checkpoints and Upgrades

This guide shows what a saved Agent contains, why restore refuses changed code, and how to deploy new code by upgrading saved Agents with an Action.

## See what a checkpoint holds

`Jido.Persistence.snapshot/2` captures a complete Agent as portable data and writes nothing. A durable record stores the same structure.

```elixir
defmodule UpgradesGuide.AddLine do
  use Jido.Action,
    name: "upgrades_add_line",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{cents: cents}, %{agent_state: state}) do
    {:ok, %{state | total_cents: state.total_cents + cents}}
  end
end

defmodule UpgradesGuide.Invoice do
  use Jido.Agent, name: "upgrades_invoice", vsn: 1

  state do
    schema Jido.Joi.object(%{total_cents: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/guides/upgrades"
    route "invoice.add_line", UpgradesGuide.AddLine, as: :add_line
  end
end

alias UpgradesGuide.{AddLine, Invoice}

invoice = Invoice.instantiate!(id: "invoice-1", state: %{total_cents: 1_200})
{:ok, snapshot} = Jido.Persistence.snapshot(invoice)

{:ok, ^invoice} = Jido.Persistence.restore(snapshot)

%{format: 3, state_format: :default, agent: ^invoice} = snapshot
[AddLine] = Map.keys(snapshot.references)
```

The snapshot has four fields:

| Field | Meaning |
| --- | --- |
| `:format` | Snapshot format. Version 3 is the only supported format |
| `:agent` | The complete Agent, with its definition and state as data |
| `:references` | A map from each module the definition depends on to its 16-byte BEAM MD5 |
| `:state_format` | `:default`, or `:custom` when the Agent has a `checkpoint/2` callback |

The references cover route handlers, Actions and Flows reached from those handlers, Plugin providers, schema refinement modules, and the same modules for nested topology members. The record stores references to code. It does not store the code.

Saved state must be portable data. A PID, reference, port, or function fails the save with a `:non_portable_term` error, and no record is written. [Portable Values](../data/portable-values-and-references.md) has the full rule.

## Know what restore checks

Restore uses the saved definition. It does not rebuild the Agent from the current source module, so a new route or schema in source has no effect on a saved Agent until you upgrade it.

Restore also compares every saved fingerprint with the loaded module, and it returns an error instead of guessing:

| Error code | Cause |
| --- | --- |
| `:changed_reference` | A referenced module now has a different MD5 |
| `:unavailable_reference` | A referenced module cannot be loaded |
| `:snapshot_references` | The reference map is incomplete |
| `:unsupported_snapshot_format` | The snapshot format is not 3 |

## Deploy changed code

The rest of this guide simulates a deploy. First, save an invoice with the old code in a real store. Then redefine the Action and the Agent, as a new release would. This release counts a tax line and adds a `:currency` field.

```elixir
alias UpgradesGuide.Invoice

{:ok, _} =
  Jido.start_link(
    name: UpgradesGuide.Jido,
    namespace: "guides/upgrades",
    persistence: {Jido.Persistence.ETS, table: :upgrades_guide}
  )

{:ok, server} =
  Jido.start_agent(UpgradesGuide.Jido, Invoice,
    id: "invoice-2",
    state: %{total_cents: 1_200}
  )

:ok = Jido.AgentServer.await_ready(server)
:ok = Jido.stop_agent(UpgradesGuide.Jido, server)

# Redefining modules stands in for a new release in this guide.
Code.compiler_options(ignore_module_conflict: true)

defmodule UpgradesGuide.AddLine do
  use Jido.Action,
    name: "upgrades_add_line",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{cents: cents}, %{agent_state: state}) do
    {:ok, %{state | total_cents: state.total_cents + cents + div(cents, 10)}}
  end
end

defmodule UpgradesGuide.Invoice do
  use Jido.Agent, name: "upgrades_invoice", vsn: 2

  state do
    schema Jido.Joi.object(%{
             total_cents: Jido.Joi.integer() |> Jido.Joi.default(0),
             currency: Jido.Joi.string() |> Jido.Joi.default("USD")
           })
  end

  routes do
    signal_source "/guides/upgrades"
    route "invoice.add_line", UpgradesGuide.AddLine, as: :add_line
  end
end

Code.compiler_options(ignore_module_conflict: false)
```

The saved invoice now refuses to load, and an activation of it stops with the same reason.

```elixir
alias UpgradesGuide.{AddLine, Invoice}

{:error, %{code: :changed_reference, details: %{module: AddLine}}} =
  Jido.Persistence.load_agent(UpgradesGuide.Jido, Invoice, "invoice-2")
```

## Write an upgrade Action

An upgrade Action is an ordinary Action with a fixed contract. It receives `%{snapshot: snapshot}` before Jido resolves any old code reference, so it still runs when old modules are gone. It must return `{:ok, %{snapshot: next}}` and nothing else. Jido rejects these results:

- A different Agent ID or origin module.
- Extra output keys or Directives.
- A target that is a Flow.
- A next snapshot that fails restore, for example state that does not match the new schema.

Build the next snapshot from the saved Agent and the current definition. Calling `Jido.Persistence.snapshot/2` on the new Agent records the fingerprints of the new code.

```elixir
defmodule UpgradesGuide.AddCurrency do
  use Jido.Action, name: "upgrades_add_currency"

  @impl Jido.Action
  def run(%{snapshot: %{agent: saved}}, _context) do
    current = UpgradesGuide.Invoice.definition()

    agent = %{
      saved
      | vsn: current.vsn,
        schema: current.schema,
        routes: current.routes,
        state: Map.put(saved.state, :currency, "USD")
    }

    with {:ok, next} <- Jido.Persistence.snapshot(agent), do: {:ok, %{snapshot: next}}
  end
end
```

## Upgrade an inactive Agent

`Jido.Persistence.upgrade_agent/5` applies the Action to one saved Agent. It reads and validates the record, runs the Action, validates the result, and writes the next revision with compare-and-swap. It returns the upgraded Agent and the new revision.

```elixir
alias Jido.AgentServer, as: Server
alias UpgradesGuide.{AddCurrency, Invoice}

{:ok, upgraded, 1} =
  Jido.Persistence.upgrade_agent(UpgradesGuide.Jido, Invoice, "invoice-2", AddCurrency)

%{vsn: 2, state: %{total_cents: 1_200, currency: "USD"}} = upgraded

{:ok, server} = Jido.thaw(UpgradesGuide.Jido, Invoice, "invoice-2")
:ok = Server.await_ready(server)

{:ok, signal} = Invoice.add_line_signal(%{cents: 100})
{:ok, agent, []} = Server.call(server, signal)
%{total_cents: 1_310, currency: "USD"} = agent.state

:ok = Server.stop(server)
```

The restored Agent ran the new Action, which added 100 cents and a 10-cent tax line.

A failed read, Action, or validation does not change the stored bytes. A concurrent writer causes `{:error, :conflict}`. The Action context holds your `:context` option plus `:instance`, `:namespace`, `:partition`, `:revision`, and `reason: :stored_upgrade`, so one Action can log or branch on the record it changes.

## Settle Turns before you deploy

`Jido.Persistence.upgrade_agent/5` returns `{:error, :turn_in_flight}` when the record has a nonterminal durable Turn. A terminal receipt is fine and is kept in the new revision.

The pending Turn cannot resume on changed code either. A changed Flow or Action makes the activation stop with `:changed_reference`, so a Turn left running across a deploy blocks both paths until the old code runs again. The only other exits are `Jido.Persistence.save_agent/3` with a fresh instance at the next revision or `Jido.Persistence.delete_agent/4`, and both discard saved state. Follow this order:

1. On the old release, finish or cancel durable Turns. `Jido.AgentServer.quiesce/2` closes admission and waits, and `active: :cancel` cancels the current Turn. `Jido.AgentServer.cancel/2` also works.
2. Stop the Agents.
3. Deploy the new release.
4. Run the upgrade Action for each saved Agent that needs it.
5. Activate the Agents.

## Choose an upgrade function

| Function | Use it when | What it writes |
| --- | --- | --- |
| `Jido.Persistence.upgrade_agent/5` | The Agent is stopped and saved | The next revision, with compare-and-swap |
| `Jido.Persistence.upgrade/3` | You hold a snapshot value, such as an export | Nothing. It returns the upgraded Agent |
| `Jido.AgentServer.upgrade/3` | One supervised activation is idle | A complete trusted definition and state at the next revision, followed by activation restart. See [Upgrade Live Agents](../agent-servers/upgrade-live-agents.md) |

`Jido.Persistence.upgrade/3` runs the same contract with no store.

```elixir
alias UpgradesGuide.{AddCurrency, Invoice}

old = %{snapshot | agent: %{snapshot.agent | state: %{total_cents: 50}}}

{:ok, %{vsn: 2, state: %{total_cents: 50, currency: "USD"}}} =
  Jido.Persistence.upgrade(old, AddCurrency, context: %{source: "export"})
```

## Use custom checkpoint callbacks

Most Agents do not need this. Define `checkpoint/2` and `restore/2` on the Agent module when the stored state must differ from live state, such as a compact form.

- `checkpoint/2` receives the Agent and a context map. It returns `{:ok, plain_map}`.
- `restore/2` receives that map and a context map. It returns `{:ok, agent}` with the same ID.
- During a durable save or restore, the context holds `:instance`, `:partition`, `:revision`, and `:reason`. During `Jido.Persistence.snapshot/2` and `Jido.Persistence.restore/2`, it holds your `:context` option.

Defining these callbacks has three effects. The snapshot uses `state_format: :custom`, the Agent module joins the references, and Plugin state conversion does not run.

```elixir
defmodule UpgradesGuide.Ledger do
  use Jido.Agent, name: "upgrades_ledger"

  state do
    schema Jido.Joi.object(%{
             entries: Jido.Joi.list(Jido.Joi.integer()) |> Jido.Joi.default([])
           })
  end

  @impl Jido.Agent
  def checkpoint(agent, _context) do
    {:ok, %{id: agent.id, packed: Enum.join(agent.state.entries, ",")}}
  end

  @impl Jido.Agent
  def restore(%{id: id, packed: packed}, _context) do
    entries = packed |> String.split(",", trim: true) |> Enum.map(&String.to_integer/1)
    instantiate(id: id, state: %{entries: entries})
  end
end

alias UpgradesGuide.Ledger

ledger = Ledger.instantiate!(id: "ledger-1", state: %{entries: [5, 7]})
{:ok, ledger_snapshot} = Jido.Persistence.snapshot(ledger)

%{state_format: :custom, agent: %{state: %{packed: "5,7"}}} = ledger_snapshot
true = Map.has_key?(ledger_snapshot.references, Ledger)

{:ok, %{state: %{entries: [5, 7]}}} = Jido.Persistence.restore(ledger_snapshot)
```

To convert only one Plugin's state field, use its Persistence facet instead. See [Plugin Persistence](../plugins/plugin-persistence.md).

## Next steps

- [Revisions and Conflicts](durable-revisions-and-conflicts.md) explains the compare-and-swap write.
- [Upgrade Live Agents](../agent-servers/upgrade-live-agents.md) upgrades through a running server.
- [Flow Identity](../flow-data/flow-identity-and-versioning.md) explains Flow fingerprints.
