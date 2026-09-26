defmodule JidoTest.Examples.Workflow.OrderedBatchTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.OrderedBatch, as: Example

  test "Map keeps source order before serial Reduce", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 3])

    {:ok, command_signal_1} = Example.convert_all_signal(%{values: [3, 1, 2]})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_1
             )

    assert agent.state.items == [
             %{index: 0, value: 6},
             %{index: 1, value: 2},
             %{index: 2, value: 4}
           ]

    assert Server.snapshot(server) == %{agent: agent, state_version: 1}
  end

  test "collected errors keep their input position", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 3])

    {:ok, command_signal_2} = Example.collect_results_signal(%{values: [1, -1, 2]})

    assert {:ok, agent} =
             Server.call(
               server,
               command_signal_2
             )

    assert [
             %{status: :ok, value: %{index: 0, value: 2}},
             %{status: :error, error: %{message: "invalid item"}},
             %{status: :ok, value: %{index: 2, value: 4}}
           ] = agent.state.items
  end

  test "fail-fast rejects the complete batch and preserves prior state", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 1])

    {:ok, command_signal_3} = Example.convert_all_signal(%{values: ~c"\a"})

    assert {:ok, _} =
             Server.call(
               server,
               command_signal_3
             )

    before = Server.snapshot(server)

    {:ok, command_signal_4} = Example.convert_all_signal(%{values: [-1, 2]})

    assert {:error, error} =
             Server.call(
               server,
               command_signal_4
             )

    assert Enum.any?(errors(error), &(&1.message == "invalid item" and &1.details.index == 0))
    assert Server.snapshot(server) == before
  end

  test "empty Map and Reduce return an empty result", %{jido: jido} do
    for build_signal <- [&Example.convert_all_signal/1, &Example.collect_results_signal/1] do
      server = start_agent!(jido, Example)
      assert {:ok, signal} = build_signal.(%{values: []})
      assert {:ok, agent} = Server.call(server, signal)
      assert agent.state.items == []
      assert Server.snapshot(server) == %{agent: agent, state_version: 1}
    end
  end
end
