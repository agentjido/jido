defmodule JidoTest.AgentServer.DurableTopologyPeerTest do
  use JidoTest.PeerCase
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias JidoTest.DurableFixtures, as: F

  test "SIGKILL recovery restores member commits, connections, and step 6 in a fresh BEAM", c do
    persistence = {Jido.Persistence.File, path: c.tmp_dir}
    id = JidoTest.Case.unique_id("durable-team")

    assert {:ok, _} =
             peer_call(c.peer_a, Supervisor, :start_child, [Jido.Supervisor, {F.Probe, nil}])

    assert {:ok, root} =
             peer_call(c.peer_a, Jido, :start_agent, [
               c.jido,
               F.Team,
               [id: id, persistence: persistence]
             ])

    assert :ok = peer_call(c.peer_a, Server, :await_ready, [root])
    worker = peer_call(c.peer_a, F, :member, [root, :worker])
    sibling = peer_call(c.peer_a, F, :member, [root, :sibling])

    assert {:ok, _, []} =
             peer_call(c.peer_a, Server, :call, [sibling, JidoTest.Case.signal("increment")])

    assert :ok =
             peer_call(c.peer_a, Server, :cast, [
               worker,
               JidoTest.Case.signal("request", %{id: "job", value: 0})
             ])

    peer_eventually(fn -> peer_call(c.peer_a, F.Probe, :records, []) == Enum.to_list(1..6) end,
      timeout: 5_000
    )

    assert {:ok, snapshot} =
             peer_call(c.peer_a, Jido.Persistence, :snapshot, [
               peer_call(c.peer_a, Server, :agent, [root])
             ])

    worker_id = peer_call(c.peer_a, Server, :agent, [worker]).id
    sibling_id = peer_call(c.peer_a, Server, :agent, [sibling]).id

    os_pid = peer_call(c.peer_a, System, :pid, [])
    monitor = Process.monitor(c.peer_a)
    assert {_, 0} = System.cmd("kill", ["-KILL", os_pid])
    assert_receive {:DOWN, ^monitor, :process, _, _}, 10_000

    assert {:ok, _} =
             peer_call(c.peer_b, Supervisor, :start_child, [Jido.Supervisor, {F.Probe, nil}])

    assert {:ok, awake} =
             peer_call(c.peer_b, Jido, :thaw, [
               c.jido,
               F.Team,
               id,
               [persistence: persistence]
             ])

    assert :ok = peer_call(c.peer_b, Server, :await_ready, [awake])
    restored_worker = peer_call(c.peer_b, F, :member, [awake, :worker])
    restored_sibling = peer_call(c.peer_b, F, :member, [awake, :sibling])
    assert peer_call(c.peer_b, Server, :agent, [restored_worker]).id == worker_id
    assert peer_call(c.peer_b, Server, :agent, [restored_sibling]).id == sibling_id
    assert peer_call(c.peer_b, Server, :agent, [restored_sibling]).state.count == 1

    assert {:ok, ^snapshot} =
             peer_call(c.peer_b, Jido.Persistence, :snapshot, [
               peer_call(c.peer_b, Server, :agent, [awake])
             ])

    peer_eventually(fn -> peer_call(c.peer_b, F.Probe, :records, []) == [6] end, timeout: 5_000)
    assert :ok = peer_call(c.peer_b, F.Probe, :release, [])

    peer_eventually(
      fn ->
        peer_call(c.peer_b, Server, :agent, [restored_worker]).state.count == 10
      end,
      timeout: 5_000
    )

    assert peer_call(c.peer_b, F.Probe, :records, []) == Enum.to_list(6..10)
    assert :ok = peer_call(c.peer_b, Server, :stop, [awake])
    assert peer_call(c.peer_b, Jido, :agent_count, [c.jido]) == 0
  end
end
