defmodule JidoTest.Examples.Workflow.OrderedBatchTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.OrderedBatch, as: Example

  test "Map keeps source order before serial Reduce", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 3])

    assert {:ok, agent} =
             Server.call(server, Example.convert_all_signal!(input: %{values: [3, 1, 2]}))

    assert agent.state.items == [
             %{index: 0, value: 6},
             %{index: 1, value: 2},
             %{index: 2, value: 4}
           ]

    assert Server.snapshot(server) == %{agent: agent, state_version: 1}
  end

  test "collected errors keep their input position", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 3])

    assert {:ok, agent} =
             Server.call(server, Example.collect_results_signal!(input: %{values: [1, -1, 2]}))

    assert [
             %{status: :ok, value: %{index: 0, value: 2}},
             %{status: :error, error: %{message: "invalid item"}},
             %{status: :ok, value: %{index: 2, value: 4}}
           ] = agent.state.items
  end

  test "fail-fast rejects the complete batch and preserves prior state", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 1])
    assert {:ok, _} = Server.call(server, Example.convert_all_signal!(input: %{values: [7]}))
    before = Server.snapshot(server)

    assert {:error, error} =
             Server.call(server, Example.convert_all_signal!(input: %{values: [-1, 2]}))

    assert Enum.any?(errors(error), &(&1.message == "invalid item" and &1.details.index == 0))
    assert Server.snapshot(server) == before
  end

  test "empty Map and Reduce return an empty result", %{jido: jido} do
    for build_signal <- [&Example.convert_all_signal!/1, &Example.collect_results_signal!/1] do
      server = start_agent!(jido, Example)
      assert {:ok, agent} = Server.call(server, build_signal.(input: %{values: []}))
      assert agent.state.items == []
      assert Server.snapshot(server) == %{agent: agent, state_version: 1}
    end
  end
end
