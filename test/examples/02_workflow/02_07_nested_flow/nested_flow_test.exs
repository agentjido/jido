defmodule JidoTest.Examples.Workflow.NestedFlowTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.NestedFlow, as: Example

  test "child calls keep separate results and share context without intermediate commits", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Example.draft_and_review(server, input: %{text: "seed"})
    before = Server.snapshot(server)

    caller =
      call_async(
        server,
        Example.draft_and_review_signal!(input: %{text: "draft"}),
        context([{:child, :editor}], %{request: "shared"})
      )

    assert_receive {:step, {:child, :writer}, _,
                    %{input: %{text: "draft"}, request: "shared", agent: id}},
                   1_000

    assert id == before.agent.id

    assert_receive {:step, {:child, :editor}, worker,
                    %{input: %{text: "draft:writer"}, request: "shared", agent: ^id}},
                   1_000

    assert Server.snapshot(server) == before
    send(worker, {:release, {:child, :editor}})
    assert {:ok, agent} = Task.await(caller)
    assert agent.state.result == %{text: "draft:writer:editor", request: "shared"}
    assert Server.snapshot(server) == %{agent: agent, state_version: 2}
  end

  test "child input and output contracts stop the parent and preserve its prior commit", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)

    assert {:ok, _} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "seed"}))

    before = Server.snapshot(server)

    assert {:error, input_error} =
             Example.draft_and_review(server, input: %{text: 42}, context: context())

    assert Enum.any?(
             errors(input_error),
             &(&1.type in [:validation_error, :flow_invalid_execution])
           )

    refute_received {:step, {:child, _}, _, _}

    assert {:error, output_error} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "draft"}),
               context: context([], %{invalid_role: :writer, request: "same"})
             )

    assert Enum.any?(
             errors(output_error),
             &(&1.type in [:validation_error, :flow_invalid_execution])
           )

    assert_receive {:step, {:child, :writer}, _, _}
    refute_received {:step, {:child, :editor}, _, _}
    assert Server.snapshot(server) == before
  end

  test "a nested Action error keeps its typed cause and the parent can run again", %{jido: jido} do
    server = start_agent!(jido, Example)

    assert {:ok, _} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "seed"}))

    before = Server.snapshot(server)

    assert {:error, error} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "draft"}),
               context: %{fail_role: :editor}
             )

    assert Enum.any?(
             errors(error),
             &(&1.type == :execution_error and &1.message == "child failed" and
                 &1.details.role == :editor)
           )

    assert Server.snapshot(server) == before

    assert {:ok, _} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "next"}))

    assert Server.snapshot(server).state_version == 2
  end

  test "the parent execution timeout also stops a blocked child", %{jido: jido} do
    server = start_agent!(jido, Example, exec_opts: [timeout: 200])

    assert {:ok, _} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "seed"}))

    before = Server.snapshot(server)

    caller =
      call_async(
        server,
        Example.draft_and_review_signal!(input: %{text: "draft"}),
        context([{:child, :editor}])
      )

    assert_receive {:step, {:child, :editor}, worker, _}, 1_000
    monitor = Process.monitor(worker)
    assert {:error, %Jido.Flow.Error.TimeoutError{timeout: 200}} = Task.await(caller)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert Server.snapshot(server) == before

    assert {:ok, _} =
             Server.call(server, Example.draft_and_review_signal!(input: %{text: "next"}))

    assert Server.snapshot(server).state_version == 2
  end
end
