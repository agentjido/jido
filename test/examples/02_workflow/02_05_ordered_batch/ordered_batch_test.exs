defmodule JidoTest.Examples.Workflow.OrderedBatchTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.OrderedBatch, as: Example

  test "reverse Map completion feeds an ordered serial Reduce", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 3])
    before = Server.snapshot(server)
    barriers = for index <- 0..2, do: {:item, index}

    caller =
      call_async(
        server,
        Example.convert_all_signal!(input: %{values: [3, 1, 2]}),
        context(barriers ++ [{:reduce, 0}])
      )

    workers =
      for index <- 0..2 do
        assert_receive {:step, {:item, ^index}, worker, %{index: ^index}}, 1_000
        {index, worker}
      end

    for {index, worker} <- Enum.reverse(workers) do
      monitor = Process.monitor(worker)
      send(worker, {:release, {:item, index}})
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    end

    assert_receive {:step, {:reduce, 0}, reducer, %{items: []}}, 1_000
    refute_received {:step, {:reduce, 1}, _, _}
    assert Server.snapshot(server) == before
    send(reducer, {:release, {:reduce, 0}})
    assert {:ok, agent} = Task.await(caller)
    assert_receive {:step, {:reduce, 1}, _, %{items: [%{index: 0}]}}, 1_000
    assert_receive {:step, {:reduce, 2}, _, %{items: [%{index: 0}, %{index: 1}]}}, 1_000

    assert agent.state.items == [
             %{index: 0, value: 6},
             %{index: 1, value: 2},
             %{index: 2, value: 4}
           ]

    assert Server.snapshot(server).state_version == 1
  end

  test "collected errors keep their source position under reversed completion", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 3])
    barriers = for index <- 0..2, do: {:item, index}

    caller =
      call_async(
        server,
        Example.collect_results_signal!(input: %{values: [1, -1, 2]}),
        context(barriers)
      )

    workers =
      for index <- 0..2 do
        assert_receive {:step, {:item, ^index}, worker, _}, 1_000
        {index, worker}
      end

    for {index, worker} <- Enum.reverse(workers) do
      monitor = Process.monitor(worker)
      send(worker, {:release, {:item, index}})
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    end

    assert {:ok, agent} = Task.await(caller)

    assert [
             %{status: :ok, value: %{index: 0, value: 2}},
             %{status: :error, error: %{message: "invalid item"}},
             %{status: :ok, value: %{index: 2, value: 4}}
           ] = agent.state.items

    assert Server.snapshot(server).state_version == 1
  end

  test "fail-fast stops pending items and rejects the batch and its dependent Reduce", %{
    jido: jido
  } do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 1])
    assert {:ok, _} = Server.call(server, Example.convert_all_signal!(input: %{values: ~c"\a"}))
    before = Server.snapshot(server)
    barriers = for index <- 0..2, do: {:item, index}
    # Every item fails, so the first admitted item is the failure in any ready order.
    caller =
      call_async(
        server,
        Example.convert_all_signal!(input: %{values: [-1, -2, -3]}),
        context(barriers)
      )

    assert_receive {:step, {:item, index}, worker, _}, 1_000
    assert index in 0..2
    refute_received {:step, {:item, _}, _, _}
    assert Server.snapshot(server) == before

    send(worker, {:release, {:item, index}})
    assert {:error, error} = Task.await(caller)
    assert Enum.any?(errors(error), &(&1.message == "invalid item" and &1.details.index == index))
    refute_received {:step, {:item, _}, _, _}
    refute_received {:step, {:reduce, _}, _, _}
    assert Server.snapshot(server) == before
  end

  test "empty Map and Reduce return their empty result without invoking a body", %{jido: jido} do
    for build_signal <- [&Example.convert_all_signal!/1, &Example.collect_results_signal!/1] do
      server = start_agent!(jido, Example)
      assert {:ok, _} = Server.call(server, build_signal.(input: %{values: [1]}))

      assert {:ok, agent} =
               Server.call(server, build_signal.(input: %{values: []}), context: context())

      assert agent.state.items == []
      assert Server.snapshot(server).state_version == 2
      refute_received {:step, _, _, _}
    end
  end
end
