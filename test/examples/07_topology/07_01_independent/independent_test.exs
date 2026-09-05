defmodule Jido.Examples.Topology.IndependentTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.Topology.{Cell, Independent}
  alias Jido.Topology.Controller

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
end
