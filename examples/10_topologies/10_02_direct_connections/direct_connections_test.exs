Code.require_file("sink.ex", __DIR__)
Code.require_file("worker.ex", __DIR__)
Code.require_file("direct_connections.ex", __DIR__)

defmodule Jido.Examples.Topology.DirectConnectionsTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  import Jido.Test.AgentServer.TopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.DirectConnections, as: Example

  test "outputs travel root to worker to sink to root in separate commits", %{jido: jido} do
    server = start_topology(jido, Example)

    signal =
      Jido.Signal.new!("examples.topology.pipeline.request", %{value: 3},
        source: "/examples/topology/direct_connections"
      )

    assert {:ok, unchanged, [_]} = Server.call(server, signal)
    assert unchanged.state.completed == 0
    eventually(fn -> Server.agent(server).state.completed == 6 end)
    assert Server.snapshot(server).state_version == 2
    assert Enum.all?(members(server), &(Server.snapshot(&1).state_version == 1))

    assert {:ok, checks} =
             Jido.Agent.Topology.checks(Example.definition(), [], &Jido.Agent.Validation.resolve/2)

    assert Enum.all?(checks, &(&1.status == :unchecked))
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
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
