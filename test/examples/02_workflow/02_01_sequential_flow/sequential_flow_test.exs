defmodule JidoTest.Examples.Workflow.SequentialFlowTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.SequentialFlow, as: Example

  test "a compiled inline Step can be reused through Builder and stored JSON" do
    alias Jido.Flow.{Builder, Codec}

    assert {:ok, flow} =
             Builder.new(
               name: "workflow_inline_reuse",
               schema: Zoi.object(%{amount: Zoi.integer()})
             )
             |> Builder.step("double", Example.Pipeline.step_action("double"), %{
               value: Builder.input(:amount)
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

    context = %{agent_state: %{label: "kept"}}
    assert {:ok, expected} = Jido.Exec.run(Example.Pipeline, %{value: 3}, context)
    assert expected == %{value: 6, label: "kept"}
    assert {:ok, ^expected} = Jido.Exec.run(flow, %{amount: 3}, context)
    assert {:ok, ^expected} = Jido.Exec.run(decoded, %{amount: 3}, context)
  end

  test "result and control dependencies produce one complete commit", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Server.snapshot(server)
    {:ok, command} = Example.double_value_signal(%{value: 4})

    assert {:ok, candidate, []} = Example.cmd(before.agent, command)
    assert candidate.state == %{value: 8, label: "kept"}
    assert Server.snapshot(server) == before

    assert {:ok, ^candidate} = Server.call(server, command)
    assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
  end

  test "an intermediate failure preserves the prior commit", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_1} = Example.double_value_signal(%{value: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_1, [])

    before = Server.snapshot(server)

    {:ok, route_signal_2} = Example.double_value_signal(%{value: 4, failure: :middle})

    assert {:error, error} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert Enum.any?(
             errors(error),
             &(&1.message == "gate rejected" and &1.details.stage == :gate)
           )

    assert Server.snapshot(server) == before

    {:ok, route_signal_3} = Example.double_value_signal(%{value: 5})

    assert {:ok, recovered} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert recovered.state.value == 10
    assert Server.snapshot(server).state_version == 2
  end

  test "Flow input, Flow output, and Agent state fail at distinct boundaries", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_4} = Example.double_value_signal(%{value: 3})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_4, [])

    before = Server.snapshot(server)

    {:ok, route_signal_5} = Example.double_value_signal(%{value: -1})

    assert {:error, %Jido.Flow.Error.InvalidExecutionError{details: %{context: "Flow"}}} =
             Jido.AgentServer.call(server, route_signal_5, [])

    {:ok, route_signal_6} = Example.double_value_signal(%{value: 4, failure: :output})

    assert {:error, %Jido.Flow.Error.InvalidExecutionError{details: %{context: "Flow output"}}} =
             Jido.AgentServer.call(server, route_signal_6, [])

    {:ok, route_signal_7} = Example.double_value_signal(%{value: 4, failure: :candidate})

    assert {:error, %Jido.Error.ValidationError{subject: :state}} =
             Jido.AgentServer.call(server, route_signal_7, [])

    assert Server.snapshot(server) == before
  end
end
