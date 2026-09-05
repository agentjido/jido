defmodule JidoTest.Agent.DistributedAuthorityTest do
  use JidoTest.PeerCase, async: false
  @moduletag :research
  @moduletag capability: "DIST-03"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DistributedAuthorityProbe, as: Agent
  alias JidoTest.DistributedAuthorityFixtures.SharedETS

  test "a replacement restores on another node and fences an older revision", c do
    persistence = persistence(c)
    assert {:ok, old} = start(c.peer_a, c, persistence)
    assert {:ok, %{state: %{value: 1}}} = peer_call(c.peer_a, Agent, :record, [old, 1])
    assert {:ok, replacement} = start(c.peer_b, c, persistence)
    assert node(replacement) == c.node_b

    assert %{state_version: 1, agent: %{state: %{value: 1}}} =
             peer_call(c.peer_b, Server, :snapshot, [replacement])

    assert {:ok, %{state: %{value: 2}}} =
             peer_call(c.peer_b, Agent, :record, [replacement, 2])

    assert {:error, _conflict} = peer_call(c.peer_a, Agent, :record, [old, 3])

    assert %{state_version: 1, agent: %{state: %{value: 1}}} =
             peer_call(c.peer_a, Server, :snapshot, [old])

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
