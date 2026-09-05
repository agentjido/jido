defmodule JidoTest.Examples.Workflow.BoundedIterationTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.BoundedIteration, as: Example

  test "initial completion skips the body and final allowed repair succeeds", %{jido: jido} do
    server = start_agent!(jido, Example)

    assert {:ok, agent} =
             Server.call(server, Example.repair_signal!(input: %{missing: 0}), context: context())

    assert agent.state.result.iterations == 0
    refute_received {:step, {:iteration, _}, _, _}

    assert {:ok, agent} =
             Server.call(server, Example.repair_signal!(input: %{missing: 3}), context: context())

    assert agent.state.result.iterations == 3
    assert agent.state.result.state == %{missing: 0, repairs: 3}

    for index <- 0..2 do
      assert_receive {:step, {:iteration, ^index}, _, %{repairs: ^index}}
    end

    refute_received {:step, {:iteration, 3}, _, _}
    assert Server.snapshot(server).state_version == 2
  end

  test "exhaustion runs exactly three bodies and preserves the prior result", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Server.call(server, Example.repair_signal!(input: %{missing: 1}))
    before = Server.snapshot(server)

    caller =
      call_async(server, Example.repair_signal!(input: %{missing: 4}), context([{:iteration, 2}]))

    assert_receive {:step, {:iteration, 2}, worker, %{missing: 2, repairs: 2}}, 1_000
    assert Server.snapshot(server) == before
    send(worker, {:release, {:iteration, 2}})
    assert {:error, error} = Task.await(caller)
    assert Enum.any?(errors(error), &(&1.type == :flow_execution_error))
    assert_receive {:step, {:iteration, 0}, _, _}
    assert_receive {:step, {:iteration, 1}, _, _}
    refute_received {:step, {:iteration, 3}, _, _}
    assert Server.snapshot(server) == before
  end

  test "invalid initial or replacement state stops before another iteration", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Server.call(server, Example.repair_signal!(input: %{missing: 1}))
    before = Server.snapshot(server)

    assert {:error, initial} =
             Server.call(server, Example.repair_signal!(input: %{missing: -1}),
               context: context()
             )

    assert %Jido.Flow.Error.InvalidExecutionError{details: %{phase: :iterate_state_initial}} =
             initial

    refute_received {:step, {:iteration, _}, _, _}

    assert {:error, replacement} =
             Server.call(server, Example.repair_signal!(input: %{missing: 2}),
               context: context([], %{invalid_update: true})
             )

    assert %Jido.Flow.Error.InvalidExecutionError{details: %{phase: :iterate_state_update}} =
             replacement

    assert_receive {:step, {:iteration, 0}, _, _}
    refute_received {:step, {:iteration, 1}, _, _}
    assert Server.snapshot(server) == before
  end
end
