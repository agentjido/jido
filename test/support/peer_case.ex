defmodule JidoTest.PeerCase do
  @moduledoc """
  Two isolated Erlang nodes with a Jido instance on each node.

  Peer calls control the test through standard IO. Agent commands between the
  two nodes use Erlang distribution. The ExUnit node stays unnamed. Cleanup is
  registered before application startup, so a failed setup or assertion still
  stops each peer.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoTest.Eventually
      import JidoTest.PeerCase, only: [peer_call: 4]
    end
  end

  setup context do
    cookie =
      :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false) |> String.to_charlist()

    jido = JidoTest.PeerInstance
    {peer_a, node_a} = start_peer(~c"jido_dist_a", cookie, jido)

    if delay = context[:peer_start_delay] do
      ref = make_ref()
      Process.send_after(self(), {:start_younger, ref}, delay)
      assert_receive {:start_younger, ^ref}, delay + 1_000
    end

    {peer_b, node_b} = start_peer(~c"jido_dist_b", cookie, jido)
    assert peer_call(peer_a, Node, :connect, [node_b]) == true
    assert peer_call(peer_b, Node, :connect, [node_a]) == true

    {:ok, jido: jido, peer_a: peer_a, peer_b: peer_b, node_a: node_a, node_b: node_b}
  end

  @doc "Calls test setup or a public API through the independent peer control channel."
  def peer_call(peer, module, function, args) do
    :peer.call(peer, module, function, args, 10_000)
  end

  defp start_peer(prefix, cookie, jido) do
    {:ok, peer, peer_node} =
      :peer.start(%{
        name: :peer.random_name(prefix),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [
          ~c"+S",
          ~c"2",
          ~c"-setcookie",
          cookie,
          ~c"-kernel",
          ~c"inet_dist_use_interface",
          ~c"{127,0,0,1}"
        ],
        wait_boot: 15_000
      })

    on_exit(fn -> stop_peer(peer) end)
    :ok = peer_call(peer, :code, :add_paths, [:code.get_path()])
    {:ok, _apps} = peer_call(peer, Application, :ensure_all_started, [:jido])

    # A temporary RPC caller cannot own the long-lived Jido instance.
    {:ok, _instance} =
      peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {Jido, name: jido}])

    {peer, peer_node}
  end

  defp stop_peer(peer) do
    ref = Process.monitor(peer)
    if Process.alive?(peer), do: :peer.stop(peer)
    assert_receive {:DOWN, ^ref, :process, ^peer, _reason}, 5_000
  end
end
