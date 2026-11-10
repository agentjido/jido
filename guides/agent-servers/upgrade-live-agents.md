# Upgrade Live Agents

A running Agent holds its definition as data: its schema, routes, Plugins, and version. Deploying new module code does not change that data. This guide shows how to change a live Agent's definition and state together, without stopping it.

Choose the tool by what changes:

| You want to | Use |
| --- | --- |
| Change data and definition together, from outside the Agent | `Jido.AgentServer.upgrade/3` |
| Change routes, topology, or Plugins as part of a Turn | A mutation Directive |
| Change an Agent that is not running | `Jido.Persistence.upgrade_agent/5` |

## Start an Agent to upgrade

This wallet stores a balance. The next version stores an amount and a currency.

```elixir
defmodule UpgradeGuide.Deposit do
  use Jido.Action,
    name: "upgrade_guide_deposit",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{cents: cents}, %{agent_state: state}) do
    {:ok, %{state | balance: state.balance + cents}}
  end
end

defmodule UpgradeGuide.DepositV2 do
  use Jido.Action,
    name: "upgrade_guide_deposit_v2",
    schema: Jido.Joi.object(%{cents: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{cents: cents}, %{agent_state: state}) do
    {:ok, %{state | amount: state.amount + cents}}
  end
end

defmodule UpgradeGuide.Wallet do
  use Jido.Agent, name: "wallet", vsn: 1

  state do
    schema Jido.Joi.object(%{balance: Jido.Joi.integer() |> Jido.Joi.default(100)})
  end

  routes do
    signal_source "/wallets"
    route "wallet.deposit", UpgradeGuide.Deposit, as: :deposit
  end
end

{:ok, _instance} = Jido.start(name: UpgradeGuide.Jido)
{:ok, wallet} = Jido.start_agent(UpgradeGuide.Jido, UpgradeGuide.Wallet, id: "wallet-1")
:ok = Jido.AgentServer.await_ready(wallet)

deposit = fn cents -> Jido.Signal.new!("wallet.deposit", %{cents: cents}, source: "/wallets") end
{:ok, %{state: %{balance: 150}}, []} = Jido.AgentServer.call(wallet, deposit.(50))
```

## Write an upgrade Action

An upgrade Action receives the current Agent as a portable snapshot in `%{snapshot: snapshot}`. It returns `{:ok, %{snapshot: upgraded}}`. Build the result with `Jido.Persistence.snapshot/2`, which validates the value.

Write it to accept a snapshot it has already upgraded, so that repeating a rollout changes no data.

```elixir
defmodule UpgradeGuide.WalletV1ToV2 do
  use Jido.Action, name: "upgrade_guide_wallet_v1_to_v2"

  @schema Jido.Joi.object(%{
            amount: Jido.Joi.integer(),
            currency: Jido.Joi.enum(["USD", "EUR"])
          })

  @impl Jido.Action
  def run(%{snapshot: %{agent: %{vsn: 1} = agent}}, context) do
    upgraded = %{
      agent
      | vsn: 2,
        schema: @schema,
        routes:
          Enum.map(agent.routes, fn route ->
            %{route | handler: %{route.handler | target: UpgradeGuide.DepositV2}}
          end),
        state: %{amount: agent.state.balance, currency: Map.get(context, :currency, "USD")}
    }

    with {:ok, saved} <- Jido.Persistence.snapshot(upgraded), do: {:ok, %{snapshot: saved}}
  end

  def run(%{snapshot: %{agent: %{vsn: 2}} = snapshot}, _context), do: {:ok, %{snapshot: snapshot}}
  def run(_input, _context), do: {:error, Jido.Error.validation_error("Unsupported wallet version")}
end
```

## Run the upgrade

`Jido.AgentServer.upgrade/3` runs the Action and commits the result. It returns the accepted Agent with an empty Directive list. The ID, process, and instance stay the same, and `state_version` rises by one.

```elixir
{:ok, upgraded, []} = Jido.AgentServer.upgrade(wallet, UpgradeGuide.WalletV1ToV2)

%{vsn: 2, id: "wallet-1", state: %{amount: 150, currency: "USD"}} = upgraded
%{agent: ^upgraded, state_version: 2} = Jido.AgentServer.snapshot(wallet)
^wallet = Jido.whereis_agent(UpgradeGuide.Jido, "wallet-1")
```

Later Signals use the new definition.

```elixir
{:ok, %{state: %{amount: 175}}, []} = Jido.AgentServer.call(wallet, deposit.(25))
```

The upgrade replaces the definition of this one live Agent. New Agents still start from the module's source, so update the source in the same release.

```elixir
%{vsn: 1} = UpgradeGuide.Wallet.instantiate!(id: "wallet-2")
```

Options can be a keyword list or a plain Map:

- `:context` is a plain Map passed to the Action as its context.
- `:timeout` is the caller's wait, with a default of 5,000 ms. A caller timeout exits the caller and does not cancel the upgrade.

## What upgrades guarantee

An upgrade runs like a Turn through the serial commit boundary:

- It waits behind the active Turn and queued work, and it counts against `:max_postponed_signals`.
- With admission closed, it returns `{:error, {:not_admitting, mode}}`, so you cannot upgrade a quiesced Agent. Reopen admission first.
- Reads return the old Agent until the upgrade commits.
- `:turn_timeout` bounds it, and `Jido.AgentServer.cancel/2` can stop it.
- A commit saves the result when the Agent has persistence, so a restart keeps the new definition.
- If it changes topology or Plugins, the server reconciles them after commit. Call `Jido.AgentServer.await_ready/2` to wait for that.

```elixir
:ok = Jido.AgentServer.quiesce(wallet)
{:error, {:not_admitting, :quiesced}} = Jido.AgentServer.upgrade(wallet, UpgradeGuide.WalletV1ToV2)
:ok = Jido.AgentServer.resume(wallet)
```

## What an upgrade can fail on

A failed upgrade returns `{:error, reason}`, and the Agent and revision stay as they were. The causes include:

- The result changes the Agent's `id` or `module`. An upgrade must keep both.
- The new state does not satisfy the new schema.
- The Action returns Directives, or extra output keys.
- The target is a Flow. An upgrade needs one Action.
- The result contains a value that cannot be saved, such as a PID.
- The Action returns an error or raises.

This Action writes a currency that the schema rejects.

```elixir
defmodule UpgradeGuide.BadCurrency do
  use Jido.Action, name: "upgrade_guide_bad_currency"

  @impl Jido.Action
  def run(%{snapshot: %{agent: agent}}, _context) do
    invalid = %{agent | state: %{agent.state | currency: "GBP"}}
    with {:ok, saved} <- Jido.Persistence.snapshot(invalid), do: {:ok, %{snapshot: saved}}
  end
end

before = Jido.AgentServer.snapshot(wallet)

{:error, %Jido.Error.ValidationError{}} =
  Jido.AgentServer.upgrade(wallet, UpgradeGuide.BadCurrency)

^before = Jido.AgentServer.snapshot(wallet)
%{error_count: 1, last_outcome: %{status: :failed}} = Jido.AgentServer.status(wallet)
```

A failed upgrade is a failed Turn, so it adds to `error_count` and runs the error policy.

## Change the definition from a Turn

When the Agent itself decides to change, return a mutation Directive such as `Jido.Agent.Directive.route_add/3` from an Action. It applies to the candidate before commit. See [Mutations and Diffs](../agents/agent-mutations-and-diffs.livemd) and [Change Live Composition](../composition/change-live-composition.md).

```elixir
defmodule UpgradeGuide.EnableRefunds do
  use Jido.Action, name: "upgrade_guide_enable_refunds"

  @impl Jido.Action
  def run(_input, %{agent_state: state}) do
    {:ok, state, [Jido.Agent.Directive.route_add("wallet.refund", UpgradeGuide.DepositV2)]}
  end
end

defmodule UpgradeGuide.Store do
  use Jido.Agent, name: "store_wallet"

  state do
    schema Jido.Joi.object(%{amount: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/wallets"
    route "wallet.enable_refunds", UpgradeGuide.EnableRefunds, as: :enable_refunds
  end
end

{:ok, store} = Jido.start_agent(UpgradeGuide.Jido, UpgradeGuide.Store, id: "store-1")
refund = Jido.Signal.new!("wallet.refund", %{cents: 5}, source: "/wallets")

{:error, %Jido.Error.ValidationError{code: :unmatched_input}} = Jido.AgentServer.call(store, refund)

{:ok, _agent, [%Jido.Agent.Directive.RouteAdd{}]} =
  Jido.AgentServer.call(store, UpgradeGuide.Store.enable_refunds_signal!(%{}))

{:ok, %{state: %{amount: 5}}, []} = Jido.AgentServer.call(store, refund)
```

## Roll out a new release

AgentServer does not run an upgrade on its own, and it does not compare a live Agent to the module's current source. A release that changes a definition needs an explicit step:

1. Load the new code. Live Agents keep their definition data, and named Action modules in their routes run as the loaded code.
2. List the live Agents with `Jido.list_agents/2`, and call `Jido.AgentServer.upgrade/3` on each one. Jido does not coordinate an upgrade across several Agents.
3. Upgrade Agents that are not running with `Jido.Persistence.upgrade_agent/5` before you thaw them.

A saved Agent records fingerprints of the code modules its definition references. Restoring after one of those modules changes fails with the code `:changed_reference`, and the upgrade Action is the way forward. See [Checkpoints and Upgrades](../durability/checkpoints-and-data-upgrades.md).

## Related

- [Agent Mutations and Diffs](../agents/agent-mutations-and-diffs.livemd) lists the definition changes a Turn can make.
- [Revisions and Conflicts](../durability/durable-revisions-and-conflicts.md) explains revision numbers in storage.
