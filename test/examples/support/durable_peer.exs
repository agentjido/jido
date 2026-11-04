defmodule JidoTest.Examples.Durable.Peer do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks

  def start(sources) do
    {:ok, peer, peer_node} =
      :peer.start(%{
        name: :peer.random_name(~c"jido_durable"),
        host: ~c"127.0.0.1",
        longnames: true,
        connection: :standard_io,
        args: [~c"+S", ~c"2", ~c"-kernel", ~c"inet_dist_use_interface", ~c"{127,0,0,1}"],
        wait_boot: 15_000
      })

    on_exit(fn -> if Process.alive?(peer), do: stop(peer) end)
    assert :ok = :peer.call(peer, :code, :add_paths, [:code.get_path()])
    assert {:ok, _} = :peer.call(peer, Application, :ensure_all_started, [:jido])

    assert {:ok, _, _} =
             :peer.call(peer, Kernel.ParallelCompiler, :compile, [
               sources,
               [return_diagnostics: true]
             ])

    {peer, peer_node}
  end

  def kill(peer) do
    os_pid = :peer.call(peer, System, :pid, [])
    monitor = Process.monitor(peer)
    assert {_, 0} = System.cmd("kill", ["-KILL", os_pid], stderr_to_stdout: true)
    assert_receive {:DOWN, ^monitor, :process, ^peer, _}, 10_000
  end

  def stop(peer) do
    monitor = Process.monitor(peer)
    assert :ok = :peer.stop(peer)
    assert_receive {:DOWN, ^monitor, :process, ^peer, _}, 10_000
  end
end
