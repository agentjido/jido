defmodule Jido.Examples.StateMigration do
  @moduledoc "Migrates one portable wallet snapshot while the Agent is inactive."

  defmodule WalletV1ToV2 do
    @moduledoc "Converts a version 1 wallet snapshot to version 2."
    use Jido.Action,
      name: "wallet_v1_to_v2"

    @schema Jido.Joi.object(%{
              wallet:
                Jido.Joi.object(%{
                  format: Jido.Joi.literal(2),
                  amount: Jido.Joi.integer(),
                  currency: Jido.Joi.enum(["USD", "EUR"])
                })
            })

    def run(
          %{
            snapshot: %{agent: %{vsn: 1, state: %{wallet: %{format: 1, balance: balance}}}} = snapshot
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
      do: {:error, Jido.Error.validation_error("Unsupported wallet version")}
  end

  use Jido.Agent, name: "runtime_wallet", vsn: 1

  state do
    schema Jido.Joi.object(%{
             wallet:
               Jido.Joi.object(%{format: Jido.Joi.literal(1), balance: Jido.Joi.integer()})
               |> Jido.Joi.default(%{format: 1, balance: 100})
           })
  end
end
