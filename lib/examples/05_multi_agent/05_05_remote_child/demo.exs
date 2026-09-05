# Run with mix run lib/examples/05_multi_agent/05_05_remote_child/demo.exs.
# Starts and stops a real owned child on the requested remote node.
defmodule Jido.Examples.RemoteChildDemo do
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.{RemoteCounter, RemoteParent}

  def run do
    cookie =
      :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false) |> String.to_charlist()

    {peer_a, node_a} = start_peer(~c"jido_example_a", cookie)

    try do
      {peer_b, node_b} = start_peer(~c"jido_example_b", cookie)

      try do
        true = :peer.call(peer_a, Node, :connect, [node_b])
        true = :peer.call(peer_b, Node, :connect, [node_a])
        check(peer_a, peer_b, node_a, node_b)
      after
        :peer.stop(peer_b)
      end
    after
      :peer.stop(peer_a)
    end
  end

  defp start_peer(prefix, cookie) do
    {:ok, peer, peer_node} =
      :peer.start_link(%{
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

    try do
      :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
      {:ok, _apps} = :peer.call(peer, Application, :ensure_all_started, [:jido])

      {:ok, _instance} =
        :peer.call(peer, Supervisor, :start_child, [
          Jido.Supervisor,
          {Jido, name: JidoExamplePeer}
        ])

      {peer, peer_node}
    catch
      kind, reason ->
        :peer.stop(peer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp check(peer_a, peer_b, node_a, node_b) do
    {:ok, remote} =
      :peer.call(peer_b, Jido, :start_agent, [
        JidoExamplePeer,
        RemoteCounter,
        [id: "remote-counter"]
      ])

    ^node_b = node(remote)

    # Peer RPC sets up the test. This Agent command travels from node A to B
    # through the normal generated command and Agent Server APIs.
    {:ok, %{state: %{value: 7}}} = :peer.call(peer_a, RemoteCounter, :record, [remote, 7])
    %{state_version: 1} = :peer.call(peer_b, Server, :snapshot, [remote])

    {:ok, parent} =
      :peer.call(peer_a, Jido, :start_agent, [
        JidoExamplePeer,
        RemoteParent,
        [id: "parent"]
      ])

    {:ok, _agent} = :peer.call(peer_a, RemoteParent, :request_child, [parent, node_b])
    {:ok, _agent} = :peer.call(peer_a, RemoteParent, :synchronize, [parent])
    %{worker: child} = :peer.call(peer_a, Server, :children, [parent])

    ^node_b = node(child.pid)
    :ok = :peer.call(peer_a, Server, :stop_child, [parent, :worker])
    nil = :peer.call(peer_b, Jido, :whereis_agent, [JidoExamplePeer, child.id])

    result = %{
      origin_node: node_a,
      requested_node: node_b,
      actual_child_node: node(child.pid),
      remote_pid_command: :passed,
      remote_child_placement: :passed,
      remote_child_stop: :passed
    }

    :ok = :peer.call(peer_a, Jido, :stop_agent, [JidoExamplePeer, parent])
    :ok = :peer.call(peer_b, Jido, :stop_agent, [JidoExamplePeer, remote])
    result
  end
end

result = Jido.Examples.RemoteChildDemo.run()
IO.inspect(result, label: "Distributed Agent capability probe")
