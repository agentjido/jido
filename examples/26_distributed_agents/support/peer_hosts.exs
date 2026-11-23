defmodule Jido.Examples.DistributedAgents.PeerHosts do
  @moduledoc false

  import ExUnit.Assertions
  import Jido.Test.AgentServer.PeerCase, only: [peer_call: 4, peer_eventually: 1]

  def load(peers, sources) do
    for peer <- peers, source <- sources do
      assert [_ | _] = peer_call(peer, Code, :require_file, [source])
    end

    :ok
  end

  def start(peer, opts) do
    assert {:ok, _pid} = peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {Jido, opts}])
    :ok
  end

  def stop(peer, instance) do
    assert :ok = peer_call(peer, Supervisor, :terminate_child, [Jido.Supervisor, instance])
    assert :ok = peer_call(peer, Supervisor, :delete_child, [Jido.Supervisor, instance])
    assert nil == peer_call(peer, Process, :whereis, [instance])
    :ok
  end

  def disconnect(c) do
    cookie = peer_call(c.peer_b, Node, :get_cookie, [])
    assert true = peer_call(c.peer_a, Node, :set_cookie, [c.node_b, :blocked_from_a])
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, :blocked_from_b])
    assert true = peer_call(c.peer_b, Node, :disconnect, [c.node_a])

    peer_eventually(fn ->
      c.node_b not in peer_call(c.peer_a, Node, :list, []) and
        c.node_a not in peer_call(c.peer_b, Node, :list, [])
    end)

    cookie
  end

  def reconnect(c, cookie) do
    assert true = peer_call(c.peer_a, Node, :set_cookie, [c.node_b, cookie])
    assert true = peer_call(c.peer_b, Node, :set_cookie, [c.node_a, cookie])
    assert true = peer_call(c.peer_a, Node, :connect, [c.node_b])

    peer_eventually(fn ->
      c.node_b in peer_call(c.peer_a, Node, :list, []) and
        c.node_a in peer_call(c.peer_b, Node, :list, [])
    end)

    :ok
  end

  def kill(peer) do
    os_pid = peer_call(peer, System, :pid, [])
    monitor = Process.monitor(peer)
    assert {_, 0} = System.cmd("kill", ["-KILL", os_pid], stderr_to_stdout: true)
    assert_receive {:DOWN, ^monitor, :process, ^peer, _reason}, 10_000
    :ok
  end
end
