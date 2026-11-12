Code.require_file("sequential_flow.ex", __DIR__)

defmodule Jido.Examples.Workflow.SequentialFlowTest do
  use Jido.Test.Agent.WorkflowSDKCase
  @moduletag :integration

  alias Jido.Examples.SequentialFlow, as: Example

  test "a compiled inline Step can be reused through a data definition and stored JSON" do
    alias Jido.Flow.{Ref, Codec}

    assert {:ok, flow} =
             Jido.Flow.new(%{
               name: "workflow_inline_reuse",
               schema: Jido.Joi.object(%{amount: Jido.Joi.integer()}),
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

    catalog =
      Jido.Catalog.from_targets!(__MODULE__, :jido, %{
        {"actions/double", 1} => Example.Pipeline.step_action("double"),
        {"actions/finish", 1} => Example.Finish,
        {"schemas/input", 1} => flow.schema,
        {"schemas/output", 1} => flow.output_schema,
        {"atoms/amount", 1} => :amount,
        {"atoms/failure", 1} => :failure,
        {"atoms/none", 1} => :none,
        {"atoms/value", 1} => :value
      })

    opts = [catalog: catalog, codec: Codec]
    assert {:ok, document} = Jido.Codec.encode(flow, opts)
    assert {:ok, decoded} = Jido.Codec.decode(JSON.decode!(JSON.encode!(document)), opts)
    assert decoded == flow

    context = %{agent_state: %{label: "kept"}}
    assert {:ok, expected} = Jido.Exec.run(Example.Pipeline, %{value: 3}, context)
    assert expected == %{value: 6, label: "kept"}
    assert {:ok, ^expected} = Jido.Exec.run(flow, %{amount: 3}, context)
    assert {:ok, ^expected} = Jido.Exec.run(decoded, %{amount: 3}, context)
  end

  test "result and control dependencies produce one complete commit", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Jido.AgentServer.snapshot(server)
    {:ok, command} = Example.double_value_signal(%{value: 4})

    assert {:ok, candidate, []} = Example.cmd(before.agent, command)
    assert candidate.state == %{value: 8, label: "kept"}
    assert Jido.AgentServer.snapshot(server) == before

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, command)

      assert turn_result.status in [:committed, :waiting]
      assert candidate == Jido.AgentServer.snapshot(server).agent
    )

    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == candidate
    assert snapshot.agent_revision == 1
  end

  test "an intermediate failure preserves the prior commit", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_1} = Example.double_value_signal(%{value: 3})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_1, [])

      assert turn_result.status in [:committed, :waiting]
    )

    before = Jido.AgentServer.snapshot(server)

    {:ok, route_signal_2} = Example.double_value_signal(%{value: 4, failure: :middle})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert Enum.any?(
             errors(error),
             &(&1.message == "gate rejected" and &1.details.stage == :gate)
           )

    assert Jido.AgentServer.snapshot(server) == before

    {:ok, route_signal_3} = Example.double_value_signal(%{value: 5})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_3, [])

      assert turn_result.status in [:committed, :waiting]
      recovered = Jido.AgentServer.snapshot(server).agent
    )

    assert recovered.state.value == 10
    assert Jido.AgentServer.snapshot(server).agent_revision == 2
  end

  test "Flow input, Flow output, and Agent state fail at distinct boundaries", %{jido: jido} do
    server = start_agent!(jido, Example)

    {:ok, route_signal_4} = Example.double_value_signal(%{value: 3})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, route_signal_4, [])

      assert turn_result.status in [:committed, :waiting]
    )

    before = Jido.AgentServer.snapshot(server)

    {:ok, route_signal_5} = Example.double_value_signal(%{value: -1})

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Jido.Error.ValidationError{details: %{phase: :flow_input}}
            }} = Jido.AgentServer.call(server, route_signal_5, [])

    {:ok, route_signal_6} = Example.double_value_signal(%{value: 4, failure: :output})

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Jido.Error.ValidationError{details: %{phase: :flow_output}}
            }} = Jido.AgentServer.call(server, route_signal_6, [])

    {:ok, route_signal_7} = Example.double_value_signal(%{value: 4, failure: :candidate})

    assert {:ok,
            %Jido.AgentServer.TurnResult{
              status: :failed,
              error: %Jido.Error.ValidationError{code: :invalid_state, path: [:state]}
            }} = Jido.AgentServer.call(server, route_signal_7, [])

    assert Jido.AgentServer.snapshot(server) == before
  end
end
