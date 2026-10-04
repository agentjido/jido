defmodule JidoTest.Examples.Topology.AdditiveUpdateTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.AdditiveUpdate
  alias Jido.Topology.Controller

  test "an additive target keeps existing PIDs and state", %{jido: jido} do
    {:ok, initial} = AdditiveUpdate.build(unique_id("additive-team"), 3)
    controller = start_supervised!({Controller, jido: jido, topology: initial, repair: :manual})
    assert :ok = Controller.await_ready(controller)

    old_workers = worker_pids(controller, 3)
    observer = Controller.whereis_agent(controller, :observer)
    assert {:ok, _agent} = AdditiveUpdate.record(hd(old_workers), 7)

    {:ok, expanded} = AdditiveUpdate.build(initial.id, 5)
    assert :ok = Controller.update(controller, expanded)
    assert :ok = Controller.await_ready(controller)

    assert worker_pids(controller, 3) == old_workers
    assert Controller.whereis_agent(controller, :observer) == observer
    assert Enum.all?(worker_pids(controller, 5), &is_pid/1)
    assert Server.agent(hd(old_workers)).state.total == 7
  end

  test "a removal is rejected without changing live Agents", %{jido: jido} do
    {:ok, initial} = AdditiveUpdate.build(unique_id("fixed-team"), 3)
    controller = start_supervised!({Controller, jido: jido, topology: initial})
    assert :ok = Controller.await_ready(controller)
    before = worker_pids(controller, 3)

    {:ok, smaller} = AdditiveUpdate.build(initial.id, 2)
    assert {:error, %Jido.Error.ValidationError{}} = Controller.update(controller, smaller)
    assert worker_pids(controller, 3) == before
  end

  defp worker_pids(controller, count) do
    Enum.map(1..count, &Controller.whereis_agent(controller, :workers, &1))
  end
end
