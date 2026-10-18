defmodule JidoTest.Examples.Durable.VMRecoveryTest do
  use JidoTest.Case, async: false
  @moduletag :example
  @moduletag :peer
  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Durable.{SavedProgress, VMRecovery}
  alias JidoTest.Examples.Durable.{ObservedAgent, Peer, StepProbe}

  @instance VMRecovery.Instance
  @sources Path.wildcard(
             Path.expand("../../../../examples/11_durable/11_02_saved_progress/*.ex", __DIR__)
           ) ++
             Path.wildcard(
               Path.expand("../../../../examples/11_durable/11_03_vm_recovery/**/*.ex", __DIR__)
             ) ++
             [Path.expand("../../support/durable_step_probe.ex", __DIR__)]

  test "a fresh BEAM resumes the saved AgentServer Turn at step 6", c do
    path = Path.join(c.tmp_dir, "flow.dets")
    id = unique_id("vm-recovery")
    {writer, writer_node} = start_beam(path)

    assert {:ok, server} =
             :peer.call(writer, Jido, :start_agent, [
               @instance,
               ObservedAgent.new(id),
               [persistence: :inherit]
             ])

    assert :ok = :peer.call(writer, Server, :await_ready, [server])
    {:ok, request} = SavedProgress.Agent.run_signal(%{value: 0})
    assert :ok = :peer.call(writer, Server, :cast, [server, request])
    before_crash = await_step_6(writer, Enum.to_list(1..5))
    turn = :peer.call(writer, Server, :status, [server]).active.turn_id
    Peer.kill(writer)

    {reader, reader_node} = start_beam(path)
    assert writer_node != reader_node

    assert {:ok, restored} =
             :peer.call(reader, Jido, :thaw, [
               @instance,
               SavedProgress.Agent,
               id,
               [persistence: :inherit]
             ])

    assert :ok = :peer.call(reader, Server, :await_ready, [restored])
    assert await_step_6(reader, []) == %{started: [{6, 5}], completed: []}
    assert :peer.call(reader, Server, :status, [restored]).active.turn_id == turn
    assert :ok = :peer.call(reader, StepProbe, :release, [])

    eventually(fn -> :peer.call(reader, Server, :agent, [restored]).state == %{value: 10} end,
      timeout: 5_000
    )

    after_crash = :peer.call(reader, StepProbe, :records, [])
    assert before_crash.completed ++ after_crash.completed == Enum.to_list(1..10)
    assert after_crash.started == Enum.map(6..10, &{&1, &1 - 1})
    assert :ok = :peer.call(reader, Server, :hibernate, [restored])

    assert {:ok, completed} =
             :peer.call(reader, Jido, :thaw, [
               @instance,
               SavedProgress.Agent,
               id,
               [persistence: :inherit]
             ])

    assert :ok = :peer.call(reader, Server, :await_ready, [completed])
    assert :peer.call(reader, Server, :agent, [completed]).state == %{value: 10}
    assert :peer.call(reader, StepProbe, :records, []) == after_crash
    assert :ok = :peer.call(reader, Server, :stop, [completed])
    assert :ok = :peer.call(reader, Supervisor, :terminate_child, [Jido.Supervisor, VMRecovery])
    assert :peer.call(reader, :dets, :info, [VMRecovery.Checkpoints]) == :undefined
    Peer.stop(reader)
  end

  defp start_beam(path) do
    {peer, peer_node} = Peer.start(@sources)

    assert {:ok, _} =
             :peer.call(peer, Supervisor, :start_child, [Jido.Supervisor, {StepProbe, nil}])

    assert {:ok, _} =
             :peer.call(peer, Supervisor, :start_child, [
               Jido.Supervisor,
               {VMRecovery, path: path}
             ])

    {peer, peer_node}
  end

  defp await_step_6(peer, completed) do
    eventually(
      fn ->
        records =
          :peer.call(peer, StepProbe, :records, [], JidoTest.Eventually.remaining_timeout(5_000))

        if List.last(records.started) == {6, 5} and records.completed == completed, do: records
      end,
      timeout: 5_000
    )
  end
end
