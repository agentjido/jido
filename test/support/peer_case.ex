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

      import JidoTest.PeerCase,
        only: [peer_call: 4, peer_call: 5, peer_eventually: 1, peer_eventually: 2]
    end
  end

  setup do
    cookie =
      :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false) |> String.to_charlist()

    jido = JidoTest.PeerInstance
    [{peer_a, node_a}, {peer_b, node_b}] = start_peers(cookie, jido)
    assert peer_call(peer_a, Node, :connect, [node_b]) == true
    assert peer_call(peer_b, Node, :connect, [node_a]) == true

    {:ok, jido: jido, peer_a: peer_a, peer_b: peer_b, node_a: node_a, node_b: node_b}
  end

  @doc "Calls test setup or a public API through the independent peer control channel."
  def peer_call(peer, module, function, args) do
    peer_call(peer, module, function, args, JidoTest.Eventually.remaining_timeout(10_000))
  end

  def peer_call(peer, module, function, args, timeout) do
    :peer.call(peer, module, function, args, timeout)
  end

  @doc "Polls a peer call without permitting one call to exceed the polling deadline."
  def peer_eventually(fun, opts \\ []) when is_function(fun, 0) or is_function(fun, 1) do
    JidoTest.Eventually.eventually(fun, opts)
  end

  defp start_peers(cookie, jido) do
    coverage_files = coverage_files()
    prefixes = [~c"jido_dist_a", ~c"jido_dist_b"]

    results =
      prefixes
      |> Task.async_stream(&boot_peer(&1, cookie),
        ordered: true,
        max_concurrency: 2,
        timeout: 20_000
      )

    peers =
      for {:ok, {:ok, peer, peer_node}} <- results,
          do: {peer, peer_node}

    on_exit(fn ->
      try do
        Enum.each(peers, fn {peer, _peer_node} ->
          if coverage_files != [] and Process.alive?(peer), do: collect_coverage(peer)
        end)
      after
        peers
        |> Task.async_stream(fn {peer, _peer_node} -> stop_peer(peer) end,
          max_concurrency: 2,
          timeout: 10_000
        )
        |> Enum.each(fn result -> assert result == {:ok, :ok} end)
      end
    end)

    Enum.each(results, fn result ->
      assert match?({:ok, {:ok, _peer, _peer_node}}, result),
             "peer failed to start: #{inspect(result)}"
    end)

    peers
    |> Task.async_stream(
      fn {peer, _peer_node} -> initialize_peer(peer, jido, coverage_files) end,
      ordered: true,
      max_concurrency: 2,
      timeout: 70_000
    )
    |> Enum.each(fn result -> assert result == {:ok, :ok} end)

    peers
  end

  defp boot_peer(prefix, cookie) do
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
  end

  defp initialize_peer(peer, jido, coverage_files) do
    :ok = peer_call(peer, :code, :add_paths, [:code.get_path()])

    if coverage_files != [] do
      {:ok, _cover} = peer_call(peer, :cover, :start, [])
      results = :peer.call(peer, :cover, :compile_beam, [coverage_files], 60_000)
      assert Enum.all?(results, &match?({:ok, _module}, &1)), inspect(results)
    end

    {:ok, _apps} = peer_call(peer, Application, :ensure_all_started, [:jido])
    :ok = peer_call(peer, :logger, :remove_handler, [:default])

    # A temporary RPC caller cannot own the long-lived Jido instance.
    {:ok, _instance} =
      peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {Jido, name: jido}])

    :ok
  end

  defp stop_peer(peer) do
    ref = Process.monitor(peer)
    if Process.alive?(peer), do: :peer.stop(peer)
    assert_receive {:DOWN, ^ref, :process, ^peer, _reason}, 5_000
    :ok
  end

  defp coverage_files do
    if Process.whereis(:cover_server) do
      root = File.cwd!()
      lib_root = Path.join(root, "lib/jido")
      facade = Path.join(root, "lib/jido.ex")

      for module <- :cover.modules(),
          {:file, file} <- [:cover.is_compiled(module)],
          beam = List.to_string(file),
          File.regular?(beam),
          source = module.module_info(:compile)[:source] |> List.to_string() |> Path.expand(),
          source == facade or String.starts_with?(source, lib_root <> "/"),
          do: file
    else
      []
    end
  end

  defp collect_coverage(peer) do
    path =
      Path.join(System.tmp_dir!(), "jido-peer-#{System.unique_integer([:positive])}.coverdata")

    try do
      :ok = :peer.call(peer, :cover, :export, [String.to_charlist(path)], 60_000)
      :ok = :cover.import(String.to_charlist(path))
    after
      File.rm(path)
    end
  end
end
