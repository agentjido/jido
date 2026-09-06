defmodule Jido.Examples.StateMigration.Schema do
  @moduledoc false
  def old_wallet, do: Zoi.object(%{format: Zoi.literal(1), balance: Zoi.integer()})

  def new_wallet,
    do:
      Zoi.object(%{
        format: Zoi.literal(2),
        amount: Zoi.integer(),
        currency: Zoi.enum(["USD", "EUR"])
      })

  def compatible_wallet, do: Zoi.union([old_wallet(), new_wallet()])
  def initial_wallet, do: %{format: 1, balance: 100}
end

defmodule Jido.Examples.StateMigration.UpgradeAudit do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{upgrade_id: Zoi.string()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.StateMigration.Audit do
  @moduledoc "Owns audit state whose static schema accepts both formats."
  use Jido.Plugin
  alias Jido.Examples.StateMigration.UpgradeAudit

  def state_spec(_) do
    {:audit,
     Zoi.union([
       Zoi.object(%{format: Zoi.literal(1), events: Zoi.list(Zoi.string())}),
       Zoi.object(%{
         format: Zoi.literal(2),
         entries: Zoi.list(Zoi.string()),
         upgrade_id: Zoi.string()
       })
     ])
     |> Zoi.default(%{format: 1, events: ["opened"]})}
  end

  def directives(_), do: [UpgradeAudit]
  def validate_directive(directive, _), do: Zoi.parse(UpgradeAudit.schema(), directive)

  def update_state(state, directives, _) do
    {:ok,
     Enum.reduce(directives, state, fn
       %UpgradeAudit{upgrade_id: id}, %{format: 1, events: events} ->
         %{format: 2, entries: events, upgrade_id: id}

       %UpgradeAudit{}, current ->
         current
     end)}
  end

  def dispatch(_, _, _, _), do: :ok
end

defmodule Jido.Examples.StateMigration.Migrate do
  @moduledoc false
  use Jido.Action,
    name: "research_migrate_wallet",
    schema: Zoi.object(%{upgrade_id: Zoi.string(), currency: Zoi.string()})

  alias Jido.Examples.StateMigration.UpgradeAudit

  def run(input, %{agent_state: %{wallet: %{format: 1, balance: balance}} = state}) do
    wallet = %{format: 2, amount: balance, currency: input.currency}
    {:ok, %{state | wallet: wallet}, [%UpgradeAudit{upgrade_id: input.upgrade_id}]}
  end

  def run(%{upgrade_id: id}, %{agent_state: %{audit: %{upgrade_id: id}} = state}),
    do: {:ok, state}

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("Upgrade ID does not match")}
end

defmodule Jido.Examples.StateMigration.CompatibleWallet do
  @moduledoc "Both state formats are declared before the Agent starts."
  alias Jido.Examples.StateMigration.{Audit, Migrate, Schema}

  use Jido.Agent, name: "research_compatible_wallet"

  agent do
    schema Zoi.object(%{
             wallet: Schema.compatible_wallet() |> Zoi.default(Schema.initial_wallet())
           })

    plugin Audit
  end

  routes do
    signal_source "/examples/migration"
    route "wallet.migrate", Migrate
  end
end

defmodule Jido.Examples.StateMigration.StrictWallet do
  @moduledoc "The old definition accepts only the original state format."
  alias Jido.Examples.StateMigration.{Audit, Migrate, Schema}

  use Jido.Agent, name: "research_strict_wallet"

  agent do
    schema Zoi.object(%{wallet: Schema.old_wallet() |> Zoi.default(Schema.initial_wallet())})
    plugin Audit
  end

  routes do
    signal_source "/examples/migration"
    route "wallet.migrate", Migrate
  end
end

defmodule Jido.Examples.StateMigration do
  @moduledoc """
  Tests migration through a normal Turn with Plugin-owned state.
  A compatible static schema supports application state migration today.
  The same Signal cannot install a new schema on StrictWallet.
  """
  def migrate(server, id \\ "wallet-1-to-2", currency \\ "USD") do
    Jido.AgentServer.call(
      server,
      Jido.Signal.new!("wallet.migrate", %{upgrade_id: id, currency: currency},
        source: "/examples/migration"
      )
    )
  end
end
