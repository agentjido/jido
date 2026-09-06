defmodule Jido.Examples.Topology.IndependentTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.Topology.{Cell, Independent}
  alias Jido.Topology.{Builder, Controller}

  test "starts independent Agents in the application child specification", %{jido: jido} do
    controller =
      start_supervised!(
        {Controller, jido: jido, topology: Independent.new!(id: "independent-example")}
      )

    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    right = Controller.whereis_agent(controller, :right)
    assert {:ok, _} = Cell.work(left, 4)
    assert Jido.AgentServer.agent(left).state.total == 4
    assert Jido.AgentServer.agent(right).state.total == 0
  end

  test "an external policy requests repair without replacing unchanged Agents", %{jido: jido} do
    instance =
      Builder.new(Independent)
      |> Builder.startup(retry_interval: 10)
      |> Builder.build!(id: "manual-example")

    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    right = Controller.whereis_agent(controller, :right)
    assert {:ok, _} = Cell.work(right, 7)
    assert :ok = Jido.stop_agent(jido, left)
    assert %{status: :degraded, repair: :manual} = Controller.status(controller)

    assert catch_exit(Controller.await_ready(controller, 50))
    assert Controller.whereis_agent(controller, :left) == nil
    assert :ok = Controller.reconcile(controller)
    assert :ok = Controller.await_ready(controller)
    replacement = Controller.whereis_agent(controller, :left)
    assert is_pid(replacement) and replacement != left
    assert Controller.whereis_agent(controller, :right) == right
    assert Jido.AgentServer.agent(right).state.total == 7
    assert {:ok, _} = Cell.work(replacement, 3)
  end
end
