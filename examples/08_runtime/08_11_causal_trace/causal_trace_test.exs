Code.require_file("../support/event_probe.ex", __DIR__)
Code.require_file("causal_trace.ex", __DIR__)

defmodule Jido.Examples.Runtime.CausalTraceTest do
  use Jido.Test.Agent.Case
  @moduletag :integration

  alias Jido.Examples.CausalTrace, as: Example
  alias Jido.Examples.Runtime.EventProbe

  test "one Agent Turn keeps one public causal identity", %{jido: jido} do
    id = unique_id("example-causal-trace")
    probe = EventProbe.attach([id])

    try do
      assert {:ok, server} = Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, Example, id: id)
      {:ok, signal} = Example.compute_signal(%{value: 7})

      assert {:ok, %Jido.AgentServer.TurnResult{status: :committed, turn_id: turn_id}} =
               Jido.AgentServer.call(server, signal)

      assert Jido.AgentServer.snapshot(server).agent.state.results == %{left: 14, right: 14}

      settled =
        eventually(fn ->
          Enum.find(EventProbe.events(probe), fn event ->
            event.event == [:jido, :agent_server, :turn, :settled]
          end)
        end)

      assert settled.metadata.turn_id == turn_id
      assert settled.metadata.signal_id == signal.id
      assert is_binary(settled.metadata.trace_id)
    after
      EventProbe.detach(probe)
    end
  end
end
