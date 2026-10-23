defmodule JidoTest.Examples.Topology.DirectConnectionsTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.AgentTopologyAssertions
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
    assert {:ok, checks} = Jido.Agent.Topology.checks(Example.definition())
    assert Enum.all?(checks, &(&1.status == :unchecked))
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end

  test "an incompatible destination is rejected without changing the definition" do
    definition = Example.definition()

    assert {:error, %{code: :unaccepted_type}} =
             Jido.Agent.mutate(definition, [
               Jido.Agent.Directive.connection_add("examples.topology.pipeline.receipt",
                 from: :sink,
                 to: :worker
               )
             ])

    assert length(definition.topology.connections) == 2
  end
end
