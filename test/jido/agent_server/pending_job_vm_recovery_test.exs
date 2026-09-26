defmodule Jido.AgentServer.PendingJobVMRecoveryTest do
  use JidoTest.PeerCase, async: false
  @moduletag capability: "REC-02"

  alias Jido.AgentServer, as: Server
  alias Jido.Agent.Directive
  alias Jido.Examples.PendingJobRecovery, as: Agent
  alias JidoTest.RemoteChildFixtures, as: Fixtures

  setup c do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "jido-job-vm-#{suffix}")
    on_exit(fn -> File.rm_rf!(path) end)

    for peer <- [c.peer_a, c.peer_b] do
      assert {:ok, _} = peer_call(peer, JidoTest.RecoveryInstance, :start_for_test, [path])
    end

    {:ok, jido: JidoTest.RecoveryInstance, persistence: {Jido.Persistence.File, path: path}}
  end

  for loss <- [:parent, :node] do
    @loss loss
    test "saved work can be retried after #{@loss} loss", c do
      assert {:ok, parent} =
               peer_call(c.peer_a, Jido, :start_agent, [
                 c.jido,
                 Fixtures.Parent,
                 [id: "job-parent", restart: :temporary]
               ])

      directive =
        Directive.spawn_child(Agent, :worker, restart: :temporary)

      command =
        Jido.Signal.new!("test.remote.directive", %{directive: directive}, source: "/test")

      assert {:ok, _} = peer_call(c.peer_a, Server, :call, [parent, command])
      child = peer_eventually(fn -> peer_call(c.peer_a, Server, :children, [parent])[:worker] end)

      {:ok, route_signal_1} = Agent.request_job_signal(%{job_id: "job-1", value: 4})

      assert {:ok, _} =
               peer_call(c.peer_a, Jido.AgentServer, :call, [child.pid, route_signal_1])

      observer = peer_call(c.peer_a, Fixtures, :observer, [])

      assert {:ok, running} =
               peer_call(c.peer_a, JidoTest.RecoveryFixtures, :approve_held, [child.pid, observer])

      task = peer_eventually(fn -> peer_call(c.peer_a, Fixtures, :observed, [observer]) end)

      assert {:ok, ^running, revision} =
               peer_call(c.peer_a, Jido.Persistence, :load_agent_with_revision, [
                 c.persistence,
                 Agent,
                 child.id,
                 [instance: c.jido]
               ])

      assert running.state.status == :running
      assert running.state.attempt_id == "attempt-1"

      target_peer =
        if @loss == :node do
          # Stop the old VM before transferring ownership of the File directory.
          :ok = :peer.stop(c.peer_a)
          c.peer_b
        else
          assert :ok = peer_call(c.peer_a, Jido, :stop_agent, [c.jido, parent])
          peer_eventually(fn -> not peer_call(c.peer_a, Process, :alive?, [child.pid]) end)
          peer_eventually(fn -> not peer_call(c.peer_a, Process, :alive?, [task]) end)
          c.peer_a
        end

      assert {:ok, restored} =
               peer_call(target_peer, Jido, :start_agent, [
                 c.jido,
                 Agent,
                 [
                   id: child.id,
                   persistence: c.persistence,
                   restore: :required,
                   restart: :temporary
                 ]
               ])

      assert peer_call(target_peer, Server, :snapshot, [restored]) == %{
               agent: running,
               state_version: revision
             }

      {:ok, route_signal_2} = Agent.retry_job_signal(%{job_id: "job-1", attempt_id: "attempt-2"})

      assert {:ok, _} =
               peer_call(target_peer, Jido.AgentServer, :call, [restored, route_signal_2])

      peer_eventually(fn ->
        peer_call(target_peer, Server, :agent, [restored]).state.status == :completed
      end)

      snapshot = peer_call(target_peer, Server, :snapshot, [restored])
      assert snapshot.agent.state.result == "8"
      assert snapshot.state_version == revision + 2

      {:ok, stale} =
        Agent.settle_attempt_signal(%{job_id: "attempt-1", status: :completed, result: "wrong"})

      assert {:error, _} = peer_call(target_peer, Server, :call, [restored, stale])
      assert peer_call(target_peer, Server, :snapshot, [restored]) == snapshot
    end
  end
end
