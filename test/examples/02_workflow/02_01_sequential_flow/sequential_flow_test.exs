defmodule JidoTest.Examples.Workflow.SequentialFlowTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.SequentialFlow, as: Example

  test "a compiled inline Step can be reused through a data definition and stored JSON" do
    alias Jido.Flow.{Ref, Codec}

    assert {:ok, flow} =
             Jido.Flow.new(%{
               name: "workflow_inline_reuse",
               schema: Zoi.object(%{amount: Zoi.integer()}),
               components: [
                 %{
                   kind: :step,
                   name: "double",
                   action: Example.Pipeline.step_action("double"),
                   params: %{value: Ref.input(:amount)}
                 },
                 %{
                   kind: :step,
                   name: "finish",
                   action: Example.Finish,
                   params: %{value: Ref.result("double", :value), failure: :none}
                 }
               ],
               output: Ref.result("finish")
             })

    registry =
      Jido.Authoring.Registry.new!(%{
        {"actions/double", 1} => {:action, Example.Pipeline.step_action("double")},
        {"actions/finish", 1} => {:action, Example.Finish},
        {"schemas/input", 1} => {:schema, flow.schema},
        {"schemas/output", 1} => {:schema, flow.output_schema},
        {"atoms/amount", 1} => {:atom, :amount},
        {"atoms/failure", 1} => {:atom, :failure},
        {"atoms/none", 1} => {:atom, :none},
        {"atoms/value", 1} => {:atom, :value}
      })

    opts = [registry: registry, codec: Codec]
    assert {:ok, document} = Jido.Authoring.encode(flow, opts)
    assert {:ok, decoded} = Jido.Authoring.decode(JSON.decode!(JSON.encode!(document)), opts)
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

    assert {:ok, ^candidate, _directives} = Server.call(server, command)
    assert Server.snapshot(server) == %{agent: candidate, state_version: 1}
  end

  test "an intermediate failure preserves the prior commit", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_1} = Example.double_value_signal(%{value: 3})

    assert {:ok, _, _directives} =
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

    assert {:ok, recovered, _directives} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert recovered.state.value == 10
    assert Server.snapshot(server).state_version == 2
  end

  test "Flow input, Flow output, and Agent state fail at distinct boundaries", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_4} = Example.double_value_signal(%{value: 3})

    assert {:ok, _, _directives} =
             Jido.AgentServer.call(server, route_signal_4, [])

    before = Server.snapshot(server)

    {:ok, route_signal_5} = Example.double_value_signal(%{value: -1})

    assert {:error, %Jido.Action.Error.InvalidInputError{details: %{phase: :flow_input}}} =
             Jido.AgentServer.call(server, route_signal_5, [])

    {:ok, route_signal_6} = Example.double_value_signal(%{value: 4, failure: :output})

    assert {:error, %Jido.Action.Error.InvalidInputError{details: %{phase: :flow_output}}} =
             Jido.AgentServer.call(server, route_signal_6, [])

    {:ok, route_signal_7} = Example.double_value_signal(%{value: 4, failure: :candidate})

    assert {:error, %Jido.Agent.Error{code: :invalid_state, path: [:state]}} =
             Jido.AgentServer.call(server, route_signal_7, [])

    assert Server.snapshot(server) == before
  end
end
