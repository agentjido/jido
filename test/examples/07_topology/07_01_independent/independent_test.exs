defmodule Jido.Examples.Topology.IndependentTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.TopologyAssertions
  alias Jido.AgentServer, as: Server
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

    assert {:ok, work} = Cell.work_signal(%{value: 4})
    assert {:ok, _} = Server.call(left, work)
    assert Server.agent(left).state == %{label: "left", received: 1, total: 4}
    assert Server.agent(right).state == %{label: "right", received: 0, total: 0}
    stop_topology(controller, [left, right])
    assert Jido.agent_count(jido) == 0
  end

  test "OTP restarts a failed Agent while Topology repair is manual", %{jido: jido} do
    instance = Independent.new!(id: "manual-example")
    controller = start_supervised!({Controller, jido: jido, topology: instance, repair: :manual})
    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    right = Controller.whereis_agent(controller, :right)

    assert {:ok, work} = Cell.work_signal(%{value: 7})
    assert {:ok, _} = Server.call(right, work)

    assert {:ok, work} = Cell.work_signal(%{value: 11})
    assert {:ok, committed} = Server.call(left, work)

    monitor = Process.monitor(left)
    Process.exit(left, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^left, :killed}, 1_000
    assert :ok = Controller.await_ready(controller)
    replacement = Controller.whereis_agent(controller, :left)
    assert is_pid(replacement) and replacement != left
    assert Server.agent(replacement) == committed
    assert Server.snapshot(replacement).state_version == 1
    assert Controller.whereis_agent(controller, :right) == right
    assert Server.agent(right).state == %{label: "right", received: 1, total: 7}
    assert {:ok, work} = Cell.work_signal(%{value: 3})
    assert {:ok, _} = Server.call(replacement, work)
    assert Server.agent(replacement).state == %{label: "left", received: 2, total: 14}
    assert Server.snapshot(replacement).state_version == 2
    stop_topology(controller, [replacement, right])
    assert Jido.agent_count(jido) == 0
  end

  test "a clean stop stays stopped after manual repair", %{jido: jido} do
    controller =
      start_supervised!(
        {Controller, jido: jido, topology: Independent.new!(id: "clean-stop"), repair: :manual}
      )

    assert :ok = Controller.await_ready(controller)
    left = Controller.whereis_agent(controller, :left)
    right = Controller.whereis_agent(controller, :right)
    monitor = Process.monitor(left)
    assert :ok = Server.stop(left)
    assert_receive {:DOWN, ^monitor, :process, ^left, :shutdown}, 1_000
    assert :ok = Controller.reconcile(controller)
    eventually(fn -> Controller.status(controller).active == 0 end)

    assert %{status: :degraded, errors: %{"agent/left" => :member_stopped}} =
             Controller.status(controller)

    assert Controller.whereis_agent(controller, :left) == nil
    assert Controller.whereis_agent(controller, :right) == right
    stop_topology(controller, [right])
    assert Jido.agent_count(jido) == 0
  end
end
