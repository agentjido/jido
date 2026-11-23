Code.require_file("approval_desk.ex", __DIR__)
Code.require_file("../support/peer_hosts.exs", __DIR__)

defmodule Jido.Examples.DistributedAgents.MoveDurableAgentTest do
  use Jido.Test.AgentServer.PeerCase, async: false

  @moduletag :integration
  @moduletag :tmp_dir

  alias Jido.Agent.Address
  alias Jido.AgentServer
  alias Jido.AgentServer.{Status, TurnResult}
  alias Jido.Examples.DistributedAgents.{ApprovalDesk, PeerHosts}

  @instance Jido.Examples.DistributedAgents.ApprovalHost
  @sources [Path.expand("approval_desk.ex", __DIR__)]

  test "a controlled move keeps committed state and resumes the same waiting Turn", c do
    PeerHosts.load([c.peer_a, c.peer_b], @sources)
    address = Address.new!(namespace: "examples/distribution/approvals", id: "desk")
    opts = [name: @instance, namespace: address.namespace, persistence: {Jido.Persistence.File, path: c.tmp_dir}]

    PeerHosts.start(c.peer_a, opts)
    assert {:ok, ^address} = peer_call(c.peer_a, Jido, :create_agent, [@instance, address, ApprovalDesk])

    assert {:ok, %TurnResult{status: :waiting}} =
             peer_call(c.peer_a, Jido, :call, [@instance, address, ApprovalDesk.request("request-1")])

    assert {:ok, %TurnResult{status: :committed, agent_revision: 1}} =
             peer_call(c.peer_a, Jido, :call, [@instance, address, ApprovalDesk.approve("request-1")])

    assert {:ok, %TurnResult{status: :waiting, turn_id: turn_id, agent_activation_id: old_activation}} =
             peer_call(c.peer_a, Jido, :call, [@instance, address, ApprovalDesk.request("request-2")])

    assert {:ok, old_worker} = peer_call(c.peer_a, Jido, :resolve_agent, [@instance, address])
    PeerHosts.stop(c.peer_a, @instance)
    refute peer_call(c.peer_a, Process, :alive?, [old_worker])

    PeerHosts.start(c.peer_b, opts)
    assert {:error, :not_found} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])

    assert %Status{residency: :passivated, work_state: :waiting, agent_revision: 1, active_turn_id: ^turn_id} =
             peer_call(c.peer_b, Jido, :status, [@instance, address])

    assert {:ok,
            %TurnResult{status: :committed, turn_id: ^turn_id, agent_activation_id: new_activation, agent_revision: 2}} =
             peer_call(c.peer_a, :erpc, :call, [
               c.node_b,
               Jido,
               :call,
               [@instance, address, ApprovalDesk.approve("request-2")],
               6_000
             ])

    assert old_activation != new_activation
    assert {:ok, new_worker} = peer_call(c.peer_b, Jido, :resolve_agent, [@instance, address])
    assert node(new_worker) == c.node_b

    assert peer_call(c.peer_b, AgentServer, :snapshot, [new_worker]).agent.state.approved_requests ==
             ["request-1", "request-2"]

    PeerHosts.stop(c.peer_b, @instance)
  end
end
