defmodule Jido.Examples.Topology.KeyedAccountsTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag timeout: 120_000
  import JidoTest.TopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.{Accounts, Cell}
  alias Jido.Topology.{Codec, Controller}

  test "a keyed account retains its identity and state after restart through the Codec", %{
    jido: jido
  } do
    {:ok, document, registry} = Codec.encode(Accounts.topology())

    {:ok, instance} =
      Codec.decode(document, registry,
        id: "accounts",
        input: %{
          accounts: [
            %{account_id: "acme/east", label: "Acme"},
            %{account_id: "beta", label: "Beta"}
          ]
        }
      )

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)

    acme = Controller.whereis_agent(controller, :accounts, "acme/east")
    beta = Controller.whereis_agent(controller, :accounts, "beta")
    assert Server.agent(acme).state == %{label: "Acme", received: 0, total: 0}
    assert Server.agent(beta).state == %{label: "Beta", received: 0, total: 0}
    assert {:ok, work} = Cell.work_signal(%{value: 6})
    assert {:ok, committed} = Server.call(acme, work)
    assert committed.id == "accounts/group/accounts/acme%2Feast"
    monitor = Process.monitor(acme)
    Process.exit(acme, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^acme, :killed}, 1_000
    assert :ok = Controller.await_ready(controller)
    replacement = Controller.whereis_agent(controller, :accounts, "acme/east")
    assert replacement != acme
    assert Server.agent(replacement) == committed
    assert Server.snapshot(replacement).state_version == 1
    assert Controller.whereis_agent(controller, :accounts, "beta") == beta
    stop_topology(controller, [replacement, beta])
    assert Jido.agent_count(jido) == 0
  end
end
