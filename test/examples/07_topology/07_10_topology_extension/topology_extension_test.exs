defmodule JidoTest.Examples.Topology.AuthoringExtensionTest do
  use JidoTest.Case, async: true

  @moduletag :example

  import JidoTest.TopologyAssertions

  alias Jido.AgentServer
  alias Jido.Examples.Topology.{AuthoringExtension, Cell}
  alias Jido.Examples.Topology.AuthoringExtension.Roles
  alias Jido.Topology.Controller
  alias Jido.Topology.Extension

  defmodule Foreign do
    defstruct [:value]
  end

  test "planning is pure and the normal Controller activates the lowered Agent", %{jido: jido} do
    definition = AuthoringExtension.topology()
    assert definition.metadata.role_count == 1

    assert [%{key: "operator", module: Cell, initial_state: %{label: "operator"}}] =
             definition.agents

    instance = AuthoringExtension.new!(id: unique_id("topology-extension"))
    assert Jido.agent_count(jido) == 0
    assert map_size(instance.plan.agents) == 1

    controller = start_supervised!({Controller, jido: jido, topology: instance})
    assert :ok = Controller.await_ready(controller)
    operator = Controller.whereis_agent(controller, :operator)

    assert {:ok, signal} = Cell.work_signal(%{value: 4})
    assert {:ok, result} = AgentServer.call(operator, signal)
    assert result.state == %{label: "operator", received: 1, total: 4}

    stop_topology(controller, [operator])
    assert Jido.agent_count(jido) == 0
  end

  test "an entity without an owning extension is rejected" do
    config = %{agents: [], metadata: %{}}

    assert {:error, error} =
             Extension.lower([Roles], config, [%Foreign{value: :unknown}])

    assert Exception.message(error) == "Unclaimed Topology extension entities"
  end
end
