defmodule JidoTest.Agent.RemoteLifecycleTest do
  use JidoTest.PeerCase, async: false
  @moduletag capability: "DIST-02"

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.RemoteLifecycle, as: Parent
  alias JidoTest.RemoteChildFixtures, as: Fixtures

  test "a connected remote process exit carries its observed reason", c do
    {parent, child} = start_pair(c)
    assert peer_call(c.peer_b, Process, :exit, [child.pid, :kill])
    assert [%{observation: :exited, reason: :killed, child_id: id}] = observations(c, parent)
    assert id == child.id
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert peer_call(c.peer_a, Process, :alive?, [parent])
    assert peer_call(c.peer_b, Node, :list, []) == [c.node_a]
  end

  test "node loss is reported as unreachable rather than confirmed child death", c do
    {parent, _child} = start_pair(c)
    :ok = :peer.stop(c.peer_b)
    assert [%{observation: :unreachable, reason: :noconnection}] = observations(c, parent)
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}
    assert peer_call(c.peer_a, Process, :alive?, [parent])
  end

  test "disconnect stops owned work and reconnect needs explicit replacement", c do
    {parent, child} = start_pair(c, worker_module: Fixtures.Child)
    observer = peer_call(c.peer_b, Fixtures, :observer, [])
    signal = Jido.Signal.new!("test.remote.hold", %{observer: observer}, source: "/test")
    :ok = peer_call(c.peer_a, Server, :cast, [child.pid, signal])
    task = eventually(fn -> peer_call(c.peer_b, Fixtures, :observed, [observer]) end)
    assert node(task) == c.node_b
    assert peer_call(c.peer_a, Node, :disconnect, [c.node_b])

    assert [%{observation: :unreachable, reason: :noconnection}] = observations(c, parent)
    eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [child.pid]) end, timeout: 2_000)
    eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [task]) end, timeout: 2_000)
    assert peer_call(c.peer_a, Process, :alive?, [parent])
    assert peer_call(c.peer_a, Node, :list, []) == []
    assert peer_call(c.peer_b, Node, :list, []) == []
    assert peer_call(c.peer_a, Node, :connect, [c.node_b])
    assert peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, child.id]) == nil
    assert peer_call(c.peer_a, Server, :children, [parent]) == %{}

    # The previous active request is closed on B. The first retry resolves
    # that receipt; the following request can use a new generation.
    assert {:ok, _} =
             peer_call(c.peer_a, Parent, :create_worker, [
               parent,
               c.node_b,
               [input: %{worker_module: Fixtures.Child}]
             ])

    eventually(fn -> peer_call(c.peer_a, Server, :status, [parent]).phase == :idle end)

    assert {:ok, _} =
             peer_call(c.peer_a, Parent, :create_worker, [
               parent,
               c.node_b,
               [input: %{worker_module: Fixtures.Child}]
             ])

    replacement = eventually(fn -> peer_call(c.peer_a, Server, :children, [parent])[:worker] end)
    assert replacement.pid != child.pid
    assert replacement.id == child.id

    # A delayed old lifecycle notification cannot replace the current child.
    stale = {:agent_child_online, child.pid, child.id, Fixtures.Child, nil, :worker, %{}}

    current =
      peer_call(c.peer_a, Fixtures, :inject_online_and_read_children, [parent, stale])[:worker]

    assert current.pid == replacement.pid
    assert :ok = peer_call(c.peer_a, Server, :stop_child, [parent, :worker])
    eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [replacement.pid]) end)
  end

  test "parent node loss stops the remote Agent and its execution task", c do
    {parent, child} = start_pair(c, worker_module: Fixtures.Child)
    observer = peer_call(c.peer_b, Fixtures, :observer, [])
    signal = Jido.Signal.new!("test.remote.hold", %{observer: observer}, source: "/test")
    :ok = peer_call(c.peer_a, Server, :cast, [child.pid, signal])
    task = eventually(fn -> peer_call(c.peer_b, Fixtures, :observed, [observer]) end)
    assert peer_call(c.peer_a, Process, :alive?, [parent])
    :ok = :peer.stop(c.peer_a)
    eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [child.pid]) end, timeout: 2_000)
    eventually(fn -> not peer_call(c.peer_b, Process, :alive?, [task]) end, timeout: 2_000)
    assert peer_call(c.peer_b, Jido, :whereis_agent, [c.jido, child.id]) == nil
  end

  defp start_pair(c, opts \\ []) do
    assert {:ok, parent} =
             peer_call(c.peer_a, Jido, :start_agent, [c.jido, Parent, [id: "lifecycle-parent"]])

    assert {:ok, _} =
             peer_call(c.peer_a, Parent, :create_worker, [
               parent,
               c.node_b,
               [input: Map.new(opts)]
             ])

    child = eventually(fn -> peer_call(c.peer_a, Server, :children, [parent])[:worker] end)
    {parent, child}
  end

  defp observations(c, parent) do
    eventually(
      fn ->
        case peer_call(c.peer_a, Server, :agent, [parent]).state.observations do
          [] -> nil
          events -> events
        end
      end,
      timeout: 2_000
    )
  end
end
