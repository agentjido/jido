defmodule Jido.Examples.StateMigration do
  @moduledoc "Upgrades a wallet definition and its state with one snapshot Action."

  defmodule WalletV1ToV2 do
    @moduledoc "Converts a version 1 wallet snapshot to version 2."
    use Jido.Action,
      name: "wallet_v1_to_v2"

    @schema Zoi.object(%{
              wallet:
                Zoi.object(%{
                  format: Zoi.literal(2),
                  amount: Zoi.integer(),
                  currency: Zoi.enum(["USD", "EUR"])
                })
            })

    def run(
          %{
            snapshot:
              %{agent: %{vsn: 1, state: %{wallet: %{format: 1, balance: balance}}}} = snapshot
          },
          context
        ) do
      agent = %{
        snapshot.agent
        | vsn: 2,
          schema: @schema,
          state: %{
            wallet: %{format: 2, amount: balance, currency: Map.get(context, :currency, "USD")}
          }
      }

      with {:ok, saved} <- Jido.Persistence.snapshot(agent), do: {:ok, %{snapshot: saved}}
    end

    def run(%{snapshot: %{agent: %{vsn: 2}} = snapshot}, _context),
      do: {:ok, %{snapshot: snapshot}}

    def run(_input, _context),
      do: {:error, Jido.Action.Error.validation_error("Unsupported wallet version")}
  end

  use Jido.Agent, name: "runtime_wallet", vsn: 1

  state do
    schema Zoi.object(%{
             wallet:
               Zoi.object(%{format: Zoi.literal(1), balance: Zoi.integer()})
               |> Zoi.default(%{format: 1, balance: 100})
           })
  end
end
