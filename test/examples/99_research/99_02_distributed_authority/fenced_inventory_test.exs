defmodule JidoTest.Examples.FencedInventoryTest do
  use JidoTest.PeerCase, async: false
  @moduletag :example
  alias Jido.Examples.FencedInventory, as: Example
  alias Example.{Authority, Client, Store}
  alias Jido.AgentServer, as: Server

  setup c do
    {:ok, authority} =
      peer_call(c.peer_a, Supervisor, :start_child, [Jido.Supervisor, {Authority, []}])

    {:ok, probe} = peer_call(c.peer_a, Authority, :start_probe, [])

    for peer <- [c.peer_a, c.peer_b] do
      assert {:ok, _} = peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {Client, []}])
    end

    %{authority: authority, probe: probe}
  end

  test "replacement on a second node fences the old activation before Action work", c do
    token1 = peer_call(c.peer_a, Authority, :claim, [c.authority])
    assert {:ok, old} = start(c.peer_a, c, token1)
    assert {:ok, _} = peer_call(c.peer_a, Example, :record, [old, 1])
    token2 = peer_call(c.peer_b, Authority, :claim, [c.authority])
    assert token2 > token1
    assert {:ok, replacement} = start(c.peer_b, c, token2)
    assert node(old) != node(replacement)
    assert peer_call(c.peer_b, Server, :snapshot, [replacement]).agent.state.value == 1
    assert {:error, _} = peer_call(c.peer_a, Example, :record, [old, 99])
    assert peer_call(c.peer_a, Example, :probe_count, [c.probe]) == 1
    assert {:ok, _} = peer_call(c.peer_b, Example, :record, [replacement, 2])
    assert peer_call(c.peer_a, Authority, :effects, [c.authority]) == [{token1, 1}, {token2, 2}]
    assert peer_call(c.peer_b, Server, :snapshot, [replacement]).agent.state.value == 2
  end

  test "storage and the external sink reject a stale token even outside admission", c do
    old = peer_call(c.peer_a, Authority, :claim, [c.authority])
    assert :ok = peer_call(c.peer_a, Store, :put, ["probe", "first", opts(c, old)])
    new = peer_call(c.peer_b, Authority, :claim, [c.authority])

    assert {:error, :stale_owner} =
             peer_call(c.peer_a, Store, :compare_and_swap, [
               "probe",
               "first",
               "stale",
               opts(c, old)
             ])

    assert {:error, :stale_owner} =
             peer_call(c.peer_a, Authority, :effect, [c.authority, old, 99])

    assert {:ok, "first"} = peer_call(c.peer_b, Store, :get, ["probe", opts(c, new)])
    assert peer_call(c.peer_a, Authority, :effects, [c.authority]) == []
  end

  test "authority loss rejects work without executing the Action", c do
    token = peer_call(c.peer_a, Authority, :claim, [c.authority])
    assert {:ok, owner} = start(c.peer_b, c, token)
    assert {:ok, _} = peer_call(c.peer_b, Example, :record, [owner, 1])
    assert :ok = peer_call(c.peer_a, GenServer, :stop, [c.authority])
    assert {:error, _} = peer_call(c.peer_b, Example, :record, [owner, 2])
    assert peer_call(c.peer_a, Example, :probe_count, [c.probe]) == 1
    assert peer_call(c.peer_b, Server, :snapshot, [owner]).agent.state.value == 1
  end

  test "a disconnected old owner stays fenced after reconnection", c do
    token1 = peer_call(c.peer_a, Authority, :claim, [c.authority])
    assert {:ok, old} = start(c.peer_b, c, token1)
    assert {:ok, _} = peer_call(c.peer_b, Example, :record, [old, 1])
    cookie = peer_call(c.peer_b, Node, :get_cookie, [])
    # Block automatic reconnection. The standard IO peer channel stays available.
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, :fenced_probe_disconnected])
    assert true = peer_call(c.peer_b, Node, :disconnect, [c.node_a])
    assert c.node_a not in peer_call(c.peer_b, Node, :list, [])
    assert {:error, _} = peer_call(c.peer_b, Example, :record, [old, 90])
    assert peer_call(c.peer_a, Example, :probe_count, [c.probe]) == 1
    token2 = peer_call(c.peer_a, Authority, :claim, [c.authority])
    assert {:ok, replacement} = start(c.peer_a, c, token2)
    assert {:ok, _} = peer_call(c.peer_a, Example, :record, [replacement, 2])
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, cookie])
    assert true = peer_call(c.peer_b, Node, :connect, [c.node_a])
    assert {:error, _} = peer_call(c.peer_b, Example, :record, [old, 91])
    assert peer_call(c.peer_a, Authority, :effects, [c.authority]) == [{token1, 1}, {token2, 2}]
    assert peer_call(c.peer_a, Example, :probe_count, [c.probe]) == 2
  end

  defp start(peer, c, token) do
    :ok =
      peer_call(peer, Client, :configure, [
        "inventory",
        %{authority: c.authority, token: token, probe: c.probe}
      ])

    peer_call(peer, Jido, :start_agent, [
      c.jido,
      Example,
      [id: "inventory", persistence: {Store, opts(c, token)}, restore: :if_found]
    ])
  end

  defp opts(c, token), do: [authority: c.authority, token: token]
end
