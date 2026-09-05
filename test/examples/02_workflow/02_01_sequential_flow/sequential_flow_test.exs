defmodule JidoTest.Examples.Workflow.SequentialFlowTest do
  use JidoTest.WorkflowSDKCase
  alias Jido.Examples.SequentialFlow, as: Example

  test "a compiled inline Step can use new bindings through Builder and stored JSON" do
    alias Jido.Flow.{Builder, Codec}

    assert {:ok, flow} =
             Builder.new(
               name: "workflow_inline_reuse",
               schema: Zoi.object(%{amount: Zoi.integer()})
             )
             |> Builder.step("double", Example.Pipeline.step_action("double"), %{
               value: Jido.Expr.new!(:multiply, [Builder.input(:amount), 2])
             })
             |> Builder.step("finish", Example.Finish, %{
               value: Builder.result("double", :value),
               failure: :none
             })
             |> Builder.output(Builder.result("finish"))
             |> Builder.build()

    assert {:ok, document, registry} = Codec.encode(flow)
    assert {:ok, decoded} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert decoded == flow

    ctx = %{agent_state: %{label: "kept"}}
    assert {:ok, expected} = Jido.Exec.run(Example.Pipeline, %{value: 3}, ctx)
    assert expected == %{value: 6, label: "kept"}
    assert {:ok, ^expected} = Jido.Exec.run(flow, %{amount: 3}, ctx)
    assert {:ok, ^expected} = Jido.Exec.run(decoded, %{amount: 3}, ctx)
  end

  test "dependencies hold intermediate state and direct/live output agrees", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Example.double_value(server, 2, :none)
    before = Server.snapshot(server)
    assert {:ok, candidate, []} = Example.cmd(before.agent, Example.double_value_signal!(4))
    assert Server.snapshot(server) == before

    caller = call_async(server, Example.double_value_signal!(4), context([:gate]))
    assert_receive {:step, :double, _, %{value: 8}}, 1_000
    assert_receive {:step, :gate, worker, %{value: 8}}, 1_000
    assert Server.snapshot(server) == before
    refute_received {:step, :finish, _, _}
    send(worker, {:release, :gate})
    assert {:ok, ^candidate} = Task.await(caller)
    assert_receive {:step, :finish, _, %{value: 8}}, 1_000
    assert candidate.state == %{value: 8, label: "kept"}
    assert Server.snapshot(server) == %{agent: candidate, state_version: 2}
  end

  test "an intermediate failure stops its dependent and keeps an existing commit", %{jido: jido} do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Server.call(server, Example.double_value_signal!(3))
    before = Server.snapshot(server)
    assert {:error, error} = Example.double_value(server, 4, :middle, context: context())

    assert Enum.any?(
             errors(error),
             &(&1.message == "gate rejected" and &1.details.stage == :gate)
           )

    refute_received {:step, :finish, _, _}
    assert Server.snapshot(server) == before
    assert {:ok, _} = Server.call(server, Example.double_value_signal!(5))
    assert Server.snapshot(server).state_version == 2
  end

  test "Flow input, Flow output, and Agent candidate schemas reject at distinct boundaries", %{
    jido: jido
  } do
    server = start_agent!(jido, Example)
    assert {:ok, _} = Server.call(server, Example.double_value_signal!(3))
    before = Server.snapshot(server)

    for value <- [-1, "4", nil, 1.5] do
      assert {:error, input_error} =
               Server.call(server, Example.double_value_signal!(value), context: context())

      assert %Jido.Flow.Error.InvalidExecutionError{details: %{context: "Flow"}} = input_error
      refute_received {:step, :double, _, _}
      assert Server.snapshot(server) == before
    end

    for failure <- [:output, :candidate] do
      assert {:error, error} =
               Server.call(server, Example.double_value_signal!(4, failure), context: context())

      case failure do
        :output ->
          assert %Jido.Flow.Error.InvalidExecutionError{details: %{context: "Flow output"}} =
                   error

        :candidate ->
          assert %Jido.Error.ValidationError{subject: :state} = error
      end

      assert_receive {:step, :finish, _, _}, 1_000
      assert Server.snapshot(server) == before
    end
  end
end
