defmodule Jido.Examples.StateMigration do
  @moduledoc "Migrates domain and Plugin-owned state as one validated commit."

  defmodule Schema do
    @moduledoc false
    def old_wallet, do: Zoi.object(%{format: Zoi.literal(1), balance: Zoi.integer()})

    def new_wallet do
      Zoi.object(%{
        format: Zoi.literal(2),
        amount: Zoi.integer(),
        currency: Zoi.enum(["USD", "EUR"])
      })
    end

    def compatible_wallet, do: Zoi.union([old_wallet(), new_wallet()])
    def initial_wallet, do: %{format: 1, balance: 100}
  end

  defmodule UpgradeAudit do
    @moduledoc false
    @schema Zoi.struct(__MODULE__, %{upgrade_id: Zoi.string()})
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
    def schema, do: @schema
    def validate(%__MODULE__{} = directive), do: Zoi.parse(@schema, directive)
  end

  defmodule Audit.Agent do
    @moduledoc false
    @behaviour Jido.Plugin

    def state_spec(_opts) do
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

    def directives(_opts), do: [Jido.Examples.StateMigration.UpgradeAudit]

    def reduce(reduction, _opts) do
      directives =
        Enum.filter(
          reduction.directives,
          &match?(%Jido.Examples.StateMigration.UpgradeAudit{}, &1)
        )

      next =
        Enum.reduce(directives, reduction.plugin_state, fn
          %Jido.Examples.StateMigration.UpgradeAudit{upgrade_id: id},
          %{
            format: 1,
            events: events
          } ->
            %{format: 2, entries: events, upgrade_id: id}

          %Jido.Examples.StateMigration.UpgradeAudit{}, current ->
            current
        end)

      {:ok, next}
    end
  end

  defmodule Audit.Server do
    @moduledoc false
    @behaviour Jido.Plugin

    @impl true
    def dispatch(_runtime, _directive, _context, _opts), do: :ok
  end

  defmodule Audit do
    @moduledoc "Owns audit state whose schema accepts both migration formats."
    use Jido.Plugin

    @impl true
    defdelegate state_spec(opts), to: Jido.Examples.StateMigration.Audit.Agent

    @impl true
    defdelegate directives(opts), to: Jido.Examples.StateMigration.Audit.Agent

    @impl true
    defdelegate reduce(reduction, opts), to: Jido.Examples.StateMigration.Audit.Agent

    @impl true
    defdelegate dispatch(runtime, directive, context, opts),
      to: Jido.Examples.StateMigration.Audit.Server
  end

  defmodule Migrate do
    @moduledoc "A shared migration Action for compatible wallet definitions."
    use Jido.Action,
      name: "runtime_migrate_wallet",
      schema: Zoi.object(%{upgrade_id: Zoi.string(), currency: Zoi.string()})

    alias Jido.Examples.StateMigration.UpgradeAudit

    def run(input, %{agent_state: %{wallet: %{format: 1, balance: balance}} = state}) do
      wallet = %{format: 2, amount: balance, currency: input.currency}
      {:ok, %{state | wallet: wallet}, [%UpgradeAudit{upgrade_id: input.upgrade_id}]}
    end

    def run(%{upgrade_id: id}, %{agent_state: %{audit: %{upgrade_id: id}} = state}),
      do: {:ok, state}

    def run(_input, _context),
      do: {:error, Jido.Action.Error.validation_error("Upgrade ID does not match")}
  end

  use Jido.Agent, name: "runtime_compatible_wallet"

  agent do
    schema Zoi.object(%{
             wallet: Schema.compatible_wallet() |> Zoi.default(Schema.initial_wallet())
           })

    plugin Audit
  end

  routes do
    signal_source "/examples/runtime/state_migration"
    route "examples.runtime.state_migration.wallet.migrate", Migrate, as: :migrate
  end

  def migrate(server, id \\ "wallet-1-to-2", currency \\ "USD") do
    Jido.AgentServer.call(
      server,
      Jido.Signal.new!(
        "examples.runtime.state_migration.wallet.migrate",
        %{upgrade_id: id, currency: currency},
        source: "/examples/runtime/state_migration"
      )
    )
  end

  @doc "Replaces the strict definition after it validates the complete migrated state."
  def upgrade(server, id \\ "wallet-1-to-2", currency \\ "USD") do
    Jido.AgentServer.upgrade(server, __MODULE__.MigratedWallet, fn agent ->
      migrate_state(agent.state, id, currency)
    end)
  end

  defp migrate_state(
         %{
           wallet: %{format: 1, balance: balance},
           audit: %{format: 1, events: events}
         },
         id,
         currency
       ) do
    {:ok,
     %{
       wallet: %{format: 2, amount: balance, currency: currency},
       audit: %{format: 2, entries: events, upgrade_id: id}
     }}
  end

  defp migrate_state(%{audit: %{format: 2, upgrade_id: id}} = state, id, _currency),
    do: {:ok, state}

  defp migrate_state(_state, _id, _currency),
    do: {:error, Jido.Action.Error.validation_error("Upgrade ID does not match")}
end

defmodule Jido.Examples.StateMigration.StrictWallet do
  @moduledoc "The old definition accepts only the original state format."
  alias Jido.Examples.StateMigration.{Audit, Migrate, Schema}

  use Jido.Agent, name: "runtime_strict_wallet"

  agent do
    schema Zoi.object(%{wallet: Schema.old_wallet() |> Zoi.default(Schema.initial_wallet())})
    plugin Audit
  end

  routes do
    signal_source "/examples/runtime/state_migration"
    route "examples.runtime.state_migration.wallet.migrate", Migrate
  end
end

defmodule Jido.Examples.StateMigration.MigratedWallet do
  @moduledoc "The target definition accepts only the migrated state format."
  alias Jido.Examples.StateMigration.{Audit, Migrate, Schema}

  use Jido.Agent, name: "runtime_migrated_wallet", vsn: 2

  agent do
    schema Zoi.object(%{
             wallet:
               Schema.new_wallet()
               |> Zoi.default(%{format: 2, amount: 0, currency: "USD"})
           })

    plugin Audit
  end

  routes do
    signal_source "/examples/runtime/state_migration"
    route "examples.runtime.state_migration.wallet.migrate", Migrate
  end
end
