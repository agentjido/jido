defmodule Jido.AgentServer.DistributedAuthorityTest do
  use JidoTest.PeerCase, async: false
  @moduletag :research
  @moduletag capability: "DIST-03"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DistributedAuthorityProbe, as: Agent
  alias JidoTest.DistributedAuthorityFixtures.SharedETS

  test "a replacement restores on another node and fences an older revision", c do
    persistence = persistence(c)
    assert {:ok, old} = start(c.peer_a, c, persistence)

    {:ok, route_signal_1} = Agent.record_signal(%{value: 1})

    assert {:ok, %{state: %{value: 1}}} =
             peer_call(c.peer_a, Jido.AgentServer, :call, [old, route_signal_1])

    assert {:ok, replacement} = start(c.peer_b, c, persistence)
    assert node(replacement) == c.node_b

    assert %{state_version: 1, agent: %{state: %{value: 1}}} =
             peer_call(c.peer_b, Server, :snapshot, [replacement])

    {:ok, route_signal_2} = Agent.record_signal(%{value: 2})

    assert {:ok, %{state: %{value: 2}}} =
             peer_call(c.peer_b, Jido.AgentServer, :call, [replacement, route_signal_2])

    {:ok, route_signal_3} = Agent.record_signal(%{value: 3})

    assert {:error, {:persistence_failed, :conflict}} =
             peer_call(c.peer_a, Jido.AgentServer, :call, [old, route_signal_3])

    peer_eventually(fn -> not peer_call(c.peer_a, Process, :alive?, [old]) end)

    assert %{state_version: 2, agent: %{state: %{value: 2}}} =
             peer_call(c.peer_b, Server, :snapshot, [replacement])
  end

  @tag skip: "DIST-03: cluster-exclusive ownership deferred by migration scope decision"
  test "one logical identity has at most one live cluster owner", c do
    persistence = persistence(c)
    assert {:ok, owner} = start(c.peer_a, c, persistence)

    assert {:error, {:agent_identity_owned, "authority", ^owner}} =
             start(c.peer_b, c, persistence)
  end

  defp start(peer, c, persistence) do
    peer_call(peer, Jido, :start_agent, [
      c.jido,
      Agent,
      [id: "authority", persistence: persistence, restore: :if_found]
    ])
  end

  defp persistence(c) do
    assert {:ok, store} = peer_call(c.peer_a, SharedETS, :start_store, [])
    {SharedETS, store: store, table: :distributed_authority_test}
  end
end
