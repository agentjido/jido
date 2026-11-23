Code.require_file("result_lookup.ex", __DIR__)
Code.require_file("../support/ticket.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)
Code.require_file("../support/sql_hosts.exs", __DIR__)

defmodule Jido.Examples.DistributedAgents.TicketDeadlineTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.AgentServer.TurnResult
  alias Jido.Examples.DistributedAgents.{PeerHosts, SqlHosts, Ticket, TicketResult}
  alias Jido.Exec.Wait

  @instance Jido.Examples.DistributedAgents.DeadlineHost
  @sources [Path.expand("result_lookup.ex", __DIR__), Path.expand("../support/ticket.ex", __DIR__)]

  test "the survivor runs a saved deadline after the ticket host dies", c do
    peers = [c.peer_a, c.peer_b]
    PeerHosts.load(peers, @sources)
    persistence = SqlHosts.open(peers, c.tmp_dir)
    address = Address.new!(namespace: "examples/distribution/support-deadlines", id: "ticket-42")
    opts = [name: @instance, namespace: address.namespace, persistence: persistence]

    PeerHosts.start(c.peer_a, opts)
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [@instance, address, Ticket])

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id, agent_activation_id: old_activation, waits: waits}} =
             peer_call(c.peer_a, Ticket, :open, [@instance, address])

    deadline = Wait.next_deadline(waits)
    PeerHosts.kill(c.peer_a)
    assert System.system_time(:millisecond) < deadline

    # The test starts the survivor only after it has confirmed the old BEAM exited.
    PeerHosts.start(c.peer_b, opts)

    result =
      peer_eventually(
        fn ->
          case peer_call(c.peer_b, TicketResult, :lookup, [@instance, address, turn_id]) do
            {:ok, result} -> result
            {:error, :not_found} -> nil
          end
        end,
        timeout: 10_000
      )

    assert %{
             status: :committed,
             agent_address: ^address,
             agent_activation_id: new_activation,
             agent_revision: 1,
             turn_id: ^turn_id
           } =
             result

    assert old_activation != new_activation
    assert {:ok, worker} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])
    assert node(worker) == c.node_b
    assert peer_call(c.peer_b, AgentServer, :snapshot, [worker]).agent.state.status == :escalated
    assert {:ok, ^result} = peer_call(c.peer_b, TicketResult, :lookup, [@instance, address, turn_id])

    assert :ok = peer_call(c.peer_b, Jido, :acknowledge_turn_result, [@instance, address, turn_id])
    assert {:error, :not_found} = peer_call(c.peer_b, TicketResult, :lookup, [@instance, address, turn_id])

    assert_approval_before_deadline(c.peer_b, %{address | id: "ticket-43"})
    PeerHosts.stop(c.peer_b, @instance)
  end

  defp assert_approval_before_deadline(peer, address) do
    assert {:ok, ^address} = peer_call(peer, Jido, :create_agent, [@instance, address, Ticket])

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id}} =
             peer_call(peer, Ticket, :open, [@instance, address])

    assert {:ok, %TurnResult{status: :committed, turn_id: ^turn_id}} =
             peer_call(peer, Jido, :call, [@instance, address, Ticket.approve(address.id)])

    assert {:ok, worker} = peer_call(peer, Jido, :resolve_agent, [@instance, address])
    assert peer_call(peer, AgentServer, :snapshot, [worker]).agent.state.status == :approved
    assert :ok = peer_call(peer, Jido, :acknowledge_turn_result, [@instance, address, turn_id])
  end
end
