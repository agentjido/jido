Code.require_file("../support/ticket.ex", __DIR__)
Code.require_file("partitioned_ingress.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)
Code.require_file("../support/sql_hosts.exs", __DIR__)

defmodule Jido.Examples.DistributedAgents.PartitionWithoutOwnershipTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.AgentServer.TurnResult
  alias Jido.Examples.DistributedAgents.{PartitionedIngress, PeerHosts, SqlHosts, Ticket}

  @instance Jido.Examples.DistributedAgents.PartitionedHost
  @sources [Path.expand("../support/ticket.ex", __DIR__), Path.expand("partitioned_ingress.ex", __DIR__)]

  test "losing the BEAM link leaves both SQL-backed instances able to activate a ticket", c do
    peers = [c.peer_a, c.peer_b]
    PeerHosts.load(peers, @sources)
    persistence = SqlHosts.open(peers, c.tmp_dir)
    address = Address.new!(namespace: "examples/distribution/support-partition", id: "ticket-42")
    opts = [name: @instance, namespace: address.namespace, persistence: persistence]
    Enum.each(peers, &PeerHosts.start(&1, opts))

    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [@instance, address, Ticket])

    assert {:ok, %TurnResult{status: :committed, agent_activation_id: first_activation, agent_revision: 1}} =
             peer_call(c.peer_a, PartitionedIngress, :record_note, [@instance, address, "Opened on A"])

    assert {:ok, first} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, address])
    assert {:error, :not_found} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])
    cookie = peer_call(c.peer_b, Node, :get_cookie, [])

    # Keep only Erlang distribution disconnected. Both SQL pools stay open.
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, :example_partitioned_peer])
    assert true = peer_call(c.peer_b, Node, :disconnect, [c.node_a])
    refute c.node_a in peer_call(c.peer_b, Node, :list, [])

    assert {:ok, second} = peer_call(c.peer_b, Jido, :activate_agent, [@instance, address])
    assert :ok = peer_call(c.peer_b, AgentServer, :await_ready, [second])
    assert node(second) == c.node_b
    assert peer_call(c.peer_b, AgentServer, :snapshot, [second]).agent.state.last_note == "Opened on A"

    assert {:ok, %TurnResult{status: :committed, agent_activation_id: ^first_activation, agent_revision: 2}} =
             peer_call(c.peer_a, PartitionedIngress, :record_note, [@instance, address, "A is still writing"])

    assert {:ok, %{state: %{last_note: "A is still writing"}}, _store_revision, 2, _turn} =
             peer_call(c.peer_b, Jido.Persistence, :load_agent_address, [@instance, address])

    refute c.node_a in peer_call(c.peer_b, Node, :list, [])
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, cookie])
    assert true = peer_call(c.peer_b, Node, :connect, [c.node_a])

    assert {:ok, ^first} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, address])
    assert {:ok, ^second} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])
    Enum.each(peers, &PeerHosts.stop(&1, @instance))
  end
end
