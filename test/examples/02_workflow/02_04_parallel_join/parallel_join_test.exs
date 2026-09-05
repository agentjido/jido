defmodule JidoTest.Examples.Workflow.ParallelJoinTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.ParallelJoin, as: Example

  test "named commands apply defaults and reject invalid input before either branch", %{
    jido: jido
  } do
    assert {:ok, signal} = Example.fetch_pair_signal(3)
    assert signal.type == "workflow.parallel"
    assert signal.source == "/workflow"
    assert signal.data == %{value: 3}

    server = start_agent!(jido, Example)

    assert {:ok, agent} = Example.fetch_pair(server, 3, context: %{request: "generated"})
    assert agent.state.result.left == %{side: :left, value: 3, request: "generated"}
    assert agent.state.result.right == %{side: :right, value: 3, request: "generated"}
    before = Server.snapshot(server)

    assert {:error,
            %Jido.Flow.Error.InvalidExecutionError{
              details: %{phase: :flow_input, errors: [%{path: [:fail]}]}
            }} =
             Example.fetch_pair(server, 3, :invalid, context: context())

    assert Server.snapshot(server) == before
    refute_received {:step, _, _, _}
  end

  test "independent work overlaps and the join waits for both results", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    assert {:ok, _} = Server.call(server, Example.fetch_pair_signal!(1))
    before = Server.snapshot(server)

    caller =
      call_async(
        server,
        Example.fetch_pair_signal!(2),
        context([:left, :right], %{request: "shared"})
      )

    assert_receive {:step, :left, left, _}, 1_000
    assert_receive {:step, :right, right, _}, 1_000
    assert left != right
    right_monitor = Process.monitor(right)
    send(right, {:release, :right})
    assert_receive {:DOWN, ^right_monitor, :process, ^right, _}, 1_000
    refute_received {:step, :join, _, _}
    assert Server.snapshot(server) == before
    send(left, {:release, :left})
    assert {:ok, agent} = Task.await(caller)
    assert_receive {:step, :join, _, _}, 1_000
    assert agent.state.result.left == %{side: :left, value: 2, request: "shared"}
    assert agent.state.result.right == %{side: :right, value: 2, request: "shared"}
    assert Server.snapshot(server) == %{agent: agent, state_version: 2}
  end

  test "a concurrency limit of one prevents overlap", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 1])
    caller = call_async(server, Example.fetch_pair_signal!(2), context([:left, :right]))
    assert_receive {:step, first, worker, _}, 1_000
    assert first in [:left, :right]
    refute_received {:step, _, _, _}
    send(worker, {:release, first})
    assert_receive {:step, second, next, _}, 1_000
    assert second in [:left, :right] and second != first
    send(next, {:release, second})
    assert {:ok, _} = Task.await(caller)
  end

  test "branch failure permits already started work to finish but prevents the join", %{
    jido: jido
  } do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    assert {:ok, _} = Server.call(server, Example.fetch_pair_signal!(1))
    before = Server.snapshot(server)
    caller = call_async(server, Example.fetch_pair_signal!(2, :left), context([:left, :right]))
    assert_receive {:step, :left, left, _}, 1_000
    assert_receive {:step, :right, right, _}, 1_000
    send(left, {:release, :left})
    assert Process.alive?(right)
    send(right, {:release, :right})
    assert {:error, error} = Task.await(caller)

    assert Enum.any?(
             errors(error),
             &(&1.message == "retriever failed" and &1.details.source == :left)
           )

    refute_received {:step, :join, _, _}
    assert Server.snapshot(server) == before
  end

  test "cancellation stops every Flow worker and the next Turn uses fresh context", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [max_concurrency: 2])
    assert {:ok, _} = Server.call(server, Example.fetch_pair_signal!(1))
    before = Server.snapshot(server)

    caller =
      call_async(
        server,
        Example.fetch_pair_signal!(100),
        context([:left, :right], %{request: "abandoned"})
      )

    assert_receive {:step, :left, left, _}, 1_000
    assert_receive {:step, :right, right, _}, 1_000
    monitors = Enum.map([left, right], &{&1, Process.monitor(&1)})
    next = call_async(server, Example.fetch_pair_signal!(3), %{request: "next"})
    eventually(fn -> Server.status(server).admission.postponed == 1 end)
    turn = Server.status(server).active.turn_id
    assert :ok = Server.cancel_turn(server, turn)
    assert {:error, :cancelled} = Task.await(caller)

    for {worker, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    end

    assert {:ok, agent} = Task.await(next)
    assert agent.state.result.left.request == "next"
    assert agent.state.result.left.value == 3
    assert Server.snapshot(server).state_version == before.state_version + 1
    refute_received {:step, :join, _, _}
  end
end
