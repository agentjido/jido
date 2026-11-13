Code.require_file("sink.ex", __DIR__)
Code.require_file("worker.ex", __DIR__)
Code.require_file("direct_connections.ex", __DIR__)

defmodule Jido.Examples.Topology.DirectConnectionsTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  import Jido.Test.AgentServer.TopologyAssertions
  alias Jido.Examples.Topology.DirectConnections, as: Example

  test "outputs travel root to worker to sink to root in separate commits", %{jido: jido} do
    server = start_topology(jido, Example)

    signal =
      Jido.Signal.new!("examples.topology.pipeline.request", %{value: 3},
        source: "/examples/topology/direct_connections"
      )

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, signal)

      assert turn_result.status in [:committed, :waiting]
      unchanged = Jido.AgentServer.snapshot(server).agent
    )

    assert unchanged.state.completed == 0
    eventually(fn -> Jido.AgentServer.snapshot(server).agent.state.completed == 6 end)
    assert Jido.AgentServer.snapshot(server).agent_revision == 2
    assert Enum.all?(members(server), &(Jido.AgentServer.snapshot(&1).agent_revision == 1))

    assert {:ok, checks} =
             Jido.Agent.Topology.checks(
               Example.definition(),
               [],
               &Jido.Agent.Validation.resolve/2
             )

    assert Enum.all?(checks, &(&1.status == :unchecked))
    stop_topology(server)
    assert Jido.resident_agent_count(jido) == 0
  end

  test "connections are validated as part of the complete definition" do
    definition = Example.definition()
    assert length(definition.topology.connections) == 2

    invalid =
      put_in(definition.topology.connections, [
        %{
          path: "examples.topology.pipeline.receipt",
          from: %{kind: :agent, name: :sink},
          to: %{kind: :agent, name: :worker},
          delivery: :single
        }
      ])

    assert {:error, %{code: :unaccepted_type}} =
             invalid
             |> Map.from_struct()
             |> Jido.Agent.define()
  end
end
