defmodule Jido.Examples.Topology.KeyedAccountsTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag timeout: 120_000
  alias Jido.Examples.Topology.Accounts
  alias Jido.Topology.{Codec, Controller}

  test "starts keyed account records through the same Codec", %{jido: jido} do
    {:ok, document, registry} = Codec.encode(Accounts.topology())

    {:ok, instance} =
      Codec.decode(document, registry,
        id: "accounts",
        input: %{
          accounts: [%{account_id: "acme", label: "Acme"}, %{account_id: "beta", label: "Beta"}]
        }
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)

    assert Jido.AgentServer.agent(Controller.whereis_agent(controller, :accounts, "acme")).state.label ==
             "Acme"
  end
end
