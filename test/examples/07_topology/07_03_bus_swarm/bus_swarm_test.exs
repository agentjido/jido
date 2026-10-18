defmodule JidoTest.Examples.Topology.BusSwarmTest do
  use JidoTest.Case, async: true
  @moduletag :example
  import JidoTest.AgentTopologyAssertions
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Topology.Swarm

  test "a local Bus broadcasts a work output to every counted member", %{jido: jido} do
    server = start_topology(jido, Swarm)
    workers = members(server)
    assert length(workers) == 3
    assert Jido.agent_count(jido) == 4
    assert {:ok, signal} = Swarm.work_signal(%{value: 5})
    assert {:ok, accepted, [_]} = Server.call(server, signal)
    assert accepted.state.sent == 1

    # The root reply confirms its commit. Each member commits a separate Turn.
    eventually(fn -> Enum.all?(workers, &(Server.agent(&1).state.total == 5)) end)
    assert Enum.all?(workers, &(Server.snapshot(&1).state_version == 1))
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end

  test "stopping the owner stops its Bus runtime and member tree", %{jido: jido} do
    server = start_topology(jido, Swarm)
    assert length(members(server)) == 3
    stop_topology(server)
    assert Jido.agent_count(jido) == 0
  end
end
