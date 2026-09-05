defmodule JidoTest.Examples.Workflow.ExecutableContinuationTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.ExecutableContinuation, as: Example

  test "Flow and Action continuations share context and commit only the terminal result", %{
    jido: jido
  } do
    server = start_agent!(jido, Example, exec_opts: [max_continuations: 4])
    assert {:ok, _} = Server.call(server, Example.add_repeatedly_signal!(1, 0))
    before = Server.snapshot(server)

    caller =
      call_async(
        server,
        Example.add_repeatedly_signal!(2, 2),
        context([{:add, 3}], %{request: "chain"})
      )

    assert_receive {:step, {:add, 2}, _, %{request: "chain", agent: id}}, 1_000
    assert id == before.agent.id
    assert_receive {:step, {:add, 3}, worker, %{request: "chain", agent: ^id}}, 1_000
    assert Server.snapshot(server) == before
    send(worker, {:release, {:add, 3}})
    assert {:ok, agent} = Task.await(caller)
    assert agent.state == %{value: 4, request: "chain"}
    assert Server.snapshot(server) == %{agent: agent, state_version: 2}
  end

  test "one continuation budget bounds the whole chain without an intermediate commit", %{
    jido: jido
  } do
    server = start_agent!(jido, Example, exec_opts: [max_continuations: 3])
    assert {:ok, _} = Server.call(server, Example.add_repeatedly_signal!(1, 0))
    before = Server.snapshot(server)

    assert {:error, error} =
             Server.call(server, Example.add_repeatedly_signal!(2, 2), context: context())

    assert Enum.any?(
             errors(error),
             &(&1.type == :execution_error and
                 &1.message == "continuation limit exceeded" and &1.details.max_continuations == 3 and
                 &1.details.count == 4)
           )

    assert_receive {:step, {:add, 2}, _, _}
    assert_receive {:step, {:add, 3}, _, _}
    refute_received {:step, {:decision, 4}, _, _}
    assert Server.snapshot(server) == before
    assert {:ok, _} = Server.call(server, Example.add_repeatedly_signal!(2, 1))
    assert Server.snapshot(server).state_version == 2
  end

  test "the terminal Flow validates its output after prior executables finish", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Server.call(server, Example.add_repeatedly_signal!(1, 0))
    before = Server.snapshot(server)

    assert {:error, error} =
             Server.call(server, Example.add_repeatedly_signal!(2, 1),
               context: context([], %{invalid_final: true})
             )

    assert %Jido.Flow.Error.InvalidExecutionError{details: %{context: "Flow output"}} = error
    assert_receive {:step, {:add, 2}, _, _}
    assert Server.snapshot(server) == before
  end

  test "an execution timeout ends the active chain and stops its worker", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [timeout: 200])
    assert {:ok, _} = Server.call(server, Example.add_repeatedly_signal!(1, 0))
    before = Server.snapshot(server)
    caller = call_async(server, Example.add_repeatedly_signal!(2, 1), context([{:add, 2}]))
    assert_receive {:step, {:add, 2}, worker, _}, 1_000
    monitor = Process.monitor(worker)
    assert {:error, error} = Task.await(caller)
    assert Enum.any?(errors(error), &(&1.type in [:timeout, :flow_timeout]))
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert Server.snapshot(server) == before
    assert {:ok, _} = Server.call(server, Example.add_repeatedly_signal!(3, 0))
    assert Server.snapshot(server).state_version == 2
  end
end
